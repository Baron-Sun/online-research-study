-- Original-label feedback for newly assigned Study 2 sessions only.
-- Existing assignments keep version 'none'; no recruitment or material change.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));

alter table public.advice_transfer_assignments
  add column if not exists label_feedback_version text not null default 'none',
  add column if not exists comment_label_feedback jsonb not null default '[]'::jsonb,
  add column if not exists comment_label_events jsonb not null default '[]'::jsonb;
alter table public.advice_transfer_submissions
  add column if not exists label_feedback_version text not null default 'none',
  add column if not exists comment_label_feedback jsonb not null default '[]'::jsonb,
  add column if not exists comment_label_events jsonb not null default '[]'::jsonb;

create or replace function public.advice_transfer_original_comment_label(p_comment text)
returns text language sql immutable set search_path = public as $$
  select upper((regexp_match(p_comment, '^\s*(YTA|NTA|ESH|NAH|INFO)\M', 'i'))[1]);
$$;

do $$ begin
  if exists(select 1 from public.advice_transfer_stimuli s
    cross join lateral jsonb_array_elements_text(s.human_comments || s.ai_comments) c(value)
    where s.active and public.advice_transfer_original_comment_label(c.value) is null) then
    raise exception 'An active comment has no unambiguous leading original label';
  end if;
end; $$;

create or replace function public.claim_advice_transfer_assignment_label_feedback(
  p_prolific_pid text, p_study_id text default null, p_session_id text default null,
  p_is_test boolean default false, p_pair_number integer default null, p_condition text default null
) returns jsonb language plpgsql security definer set search_path = public
set lock_timeout = '250ms' as $$
declare
  v_existing boolean; v_response jsonb;
  v_assignment public.advice_transfer_assignments%rowtype;
  v_pid text := nullif(trim(p_prolific_pid), '');
  v_study text := nullif(trim(p_study_id), '');
  v_session text := nullif(trim(p_session_id), '');
  v_is_test boolean := coalesce(v_pid ~* '^(test|preview|qa)[-_]', false);
begin
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  select exists(select 1 from public.advice_transfer_assignments
    where prolific_pid=v_pid and coalesce(study_id,'')=coalesce(v_study,'')
      and ((v_is_test and coalesce(session_id,'')=coalesce(v_session,''))
        or (not v_is_test and not is_test))) into v_existing;
  v_response := public.claim_advice_transfer_assignment_same_post(
    p_prolific_pid,p_study_id,p_session_id,p_is_test,p_pair_number,p_condition);
  if v_response->>'admissionStatus' is distinct from 'assigned' then return v_response; end if;
  select * into v_assignment from public.advice_transfer_assignments
    where assignment_id=v_response->>'assignmentId' for update;
  if not v_existing and v_assignment.protocol_version='advice-transfer-v4-gist'
    and v_assignment.design_variant='same_post' then
    update public.advice_transfer_assignments set label_feedback_version='original-label-v1'
      where id=v_assignment.id returning * into v_assignment;
  end if;
  return v_response || jsonb_build_object(
    'labelFeedbackVersion',v_assignment.label_feedback_version,
    'commentLabelFeedback',v_assignment.comment_label_feedback);
end; $$;

create or replace function public.record_advice_transfer_comment_label(
  p_assignment_id text, p_prolific_pid text, p_display_position integer,
  p_comment_index integer, p_comment_sha256 text, p_selected_label text, p_event_id text
) returns jsonb language plpgsql security definer set search_path = public
set lock_timeout = '250ms' as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_stimulus public.advice_transfer_stimuli%rowtype;
  v_original text; v_raw text; v_previous jsonb; v_record jsonb; v_event jsonb;
  v_feedback jsonb; v_now timestamptz := clock_timestamp();
begin
  if p_display_position is null or p_display_position not between 1 and 5
    or p_comment_index is null or p_comment_index not between 0 and 4
    or p_selected_label is null or p_selected_label not in ('YTA','NTA','ESH','NAH','INFO')
    or nullif(trim(p_event_id),'') is null or length(p_event_id)>128 then
    raise exception 'Invalid comment-label selection';
  end if;
  perform pg_advisory_xact_lock_shared(hashtext('advice_transfer_admission_v3'));
  select * into v_assignment from public.advice_transfer_assignments
    where assignment_id=trim(p_assignment_id) and prolific_pid=trim(p_prolific_pid) for update;
  if v_assignment.id is null then raise exception 'Assignment not found'; end if;
  if v_assignment.label_feedback_version <> 'original-label-v1' then
    raise exception 'Label feedback is not enabled for this assignment';
  end if;
  if p_comment_index is distinct from (v_assignment.comment_order->>(p_display_position-1))::integer
    or p_comment_sha256 is distinct from v_assignment.presented_comment_sha256->>(p_display_position-1) then
    raise exception 'Selection does not match its assigned comment';
  end if;
  select value into v_event from jsonb_array_elements(v_assignment.comment_label_events)
    where value->>'eventId'=p_event_id;
  if v_event is not null then
    if (v_event->>'displayPosition')::integer<>p_display_position or v_event->>'selectedLabel'<>p_selected_label then
      raise exception 'Selection event identifier was reused with a different answer';
    end if;
    return jsonb_build_object('ok',true,'alreadyRecorded',true,
      'commentLabelFeedback',v_assignment.comment_label_feedback,
      'phase1Snapshot',v_assignment.phase1_snapshot,'phase1LockedAt',v_assignment.phase1_locked_at);
  end if;
  if v_assignment.phase1_locked_at is not null then raise exception 'Phase 1 answers are locked'; end if;
  if v_assignment.status<>'claimed' then raise exception 'This assignment is no longer active'; end if;
  if jsonb_array_length(v_assignment.comment_label_events)>=250 then
    raise exception 'Too many comment-label changes';
  end if;
  select * into v_stimulus from public.advice_transfer_stimuli where stimulus_id=v_assignment.stimulus_id;
  v_raw := (case when v_assignment.condition='human' then v_stimulus.human_comments else v_stimulus.ai_comments end)->>p_comment_index;
  v_original := public.advice_transfer_original_comment_label(v_raw);
  if v_original is null then raise exception 'Original comment label is unavailable'; end if;
  -- A raw-prefix label must refer to the exact text actually assigned, including
  -- compatibility with the historical all-labels-removed presentation rule.
  if p_comment_sha256 not in (
    encode(extensions.digest(public.advice_transfer_remove_leading_judgment_label(v_raw),'sha256'),'hex'),
    encode(extensions.digest(public.advice_transfer_remove_judgment_labels(v_raw),'sha256'),'hex')) then
    raise exception 'Original label cannot be matched to the displayed text';
  end if;
  select value into v_previous from jsonb_array_elements(v_assignment.comment_label_feedback)
    where (value->>'displayPosition')::integer=p_display_position;
  v_record := jsonb_build_object(
    'displayPosition',p_display_position,'commentIndex',p_comment_index,'commentSha256',p_comment_sha256,
    'originalLabel',v_original,'firstLabel',coalesce(v_previous->>'firstLabel',p_selected_label),
    'firstSelectedAt',coalesce(v_previous->'firstSelectedAt',to_jsonb(v_now)),
    'finalLabel',p_selected_label,'lastSelectedAt',v_now,
    'selectionCount',coalesce((v_previous->>'selectionCount')::integer,0)+1,
    'feedbackOffered',coalesce((v_previous->>'feedbackOffered')::boolean,false) or p_selected_label<>v_original,
    'feedbackFirstOfferedAt',case when v_previous->>'feedbackFirstOfferedAt' is not null
      then v_previous->'feedbackFirstOfferedAt' when p_selected_label<>v_original then to_jsonb(v_now) else 'null'::jsonb end);
  select coalesce(jsonb_agg(value order by (value->>'displayPosition')::integer),'[]'::jsonb)
    into v_feedback from (
      select value from jsonb_array_elements(v_assignment.comment_label_feedback)
        where (value->>'displayPosition')::integer<>p_display_position
      union all select v_record) records;
  v_event := jsonb_build_object('eventId',p_event_id,'displayPosition',p_display_position,
    'commentIndex',p_comment_index,'commentSha256',p_comment_sha256,'selectedLabel',p_selected_label,
    'originalLabel',v_original,'matchesOriginal',p_selected_label=v_original,'recordedAt',v_now);
  update public.advice_transfer_assignments set comment_label_feedback=v_feedback,
    comment_label_events=comment_label_events||jsonb_build_array(v_event), updated_at=v_now
    where id=v_assignment.id;
  return jsonb_build_object('ok',true,'alreadyRecorded',false,'commentLabelFeedback',v_feedback);
end; $$;

create or replace function public.lock_advice_transfer_label_feedback()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_position integer; v_record jsonb;
begin
  if new.label_feedback_version='original-label-v1' and old.phase1_locked_at is null
    and new.phase1_locked_at is not null then
    if jsonb_array_length(new.comment_label_feedback)<>5 then
      raise exception 'Save all five label selections before continuing';
    end if;
    for v_position in 1..5 loop
      select value into v_record from jsonb_array_elements(new.comment_label_feedback)
        where (value->>'displayPosition')::integer=v_position;
      if v_record is null or new.phase1_snapshot->'commentJudgments'->(v_position-1)->>'label'
        is distinct from v_record->>'finalLabel' then
        raise exception 'Phase 1 label does not match the saved selection';
      end if;
    end loop;
    new.phase1_snapshot := new.phase1_snapshot || jsonb_build_object(
      'labelFeedbackVersion',new.label_feedback_version,
      'commentLabelFeedback',new.comment_label_feedback,'commentLabelEvents',new.comment_label_events);
  end if;
  return new;
end; $$;
create or replace trigger advice_transfer_lock_label_feedback
  before update of phase1_snapshot, phase1_locked_at on public.advice_transfer_assignments
  for each row execute function public.lock_advice_transfer_label_feedback();

create or replace function public.audit_advice_transfer_label_feedback()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_assignment public.advice_transfer_assignments%rowtype;
begin
  select * into v_assignment from public.advice_transfer_assignments where assignment_id=new.assignment_id;
  new.label_feedback_version := v_assignment.label_feedback_version;
  new.comment_label_feedback := v_assignment.comment_label_feedback;
  new.comment_label_events := v_assignment.comment_label_events;
  new.full_payload := new.full_payload || jsonb_build_object(
    'labelFeedbackVersion',new.label_feedback_version,
    'commentLabelFeedback',new.comment_label_feedback,'commentLabelEvents',new.comment_label_events,
    'serverAudit',coalesce(new.full_payload->'serverAudit','{}'::jsonb)||jsonb_build_object(
      'labelFeedbackVersion',new.label_feedback_version));
  return new;
end; $$;
create or replace trigger advice_transfer_submission_label_feedback_audit
  before insert on public.advice_transfer_submissions
  for each row execute function public.audit_advice_transfer_label_feedback();

revoke all on function public.advice_transfer_original_comment_label(text) from public, anon, authenticated;
revoke all on function public.lock_advice_transfer_label_feedback() from public, anon, authenticated;
revoke all on function public.audit_advice_transfer_label_feedback() from public, anon, authenticated;
revoke all on function public.claim_advice_transfer_assignment_label_feedback(text,text,text,boolean,integer,text) from public;
revoke all on function public.record_advice_transfer_comment_label(text,text,integer,integer,text,text,text) from public;
grant execute on function public.claim_advice_transfer_assignment_label_feedback(text,text,text,boolean,integer,text) to anon,authenticated,service_role;
grant execute on function public.record_advice_transfer_comment_label(text,text,integer,integer,text,text,text) to anon,authenticated,service_role;
notify pgrst, 'reload schema';
commit;
