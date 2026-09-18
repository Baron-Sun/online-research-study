-- Add the two Phase 1 perception items for newly assigned sessions only.
-- Apply after supabase_advice_transfer_label_feedback_20260918.sql.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
alter table public.advice_transfer_assignments
  add column if not exists perception_questions_version text not null default 'none',
  add column if not exists perceived_consensus integer check (perceived_consensus between 0 and 100),
  add column if not exists room_for_disagreement integer check (room_for_disagreement between 0 and 100);
alter table public.advice_transfer_submissions
  add column if not exists perception_questions_version text not null default 'none',
  add column if not exists perceived_consensus integer check (perceived_consensus between 0 and 100),
  add column if not exists room_for_disagreement integer check (room_for_disagreement between 0 and 100);

create or replace function public.claim_advice_transfer_assignment_perception(
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
  v_response := public.claim_advice_transfer_assignment_label_feedback(
    p_prolific_pid,p_study_id,p_session_id,p_is_test,p_pair_number,p_condition);
  if v_response->>'admissionStatus' is distinct from 'assigned' then return v_response; end if;
  select * into v_assignment from public.advice_transfer_assignments
    where assignment_id=v_response->>'assignmentId' for update;
  if not v_existing and v_assignment.protocol_version='advice-transfer-v4-gist'
    and v_assignment.design_variant='same_post' then
    update public.advice_transfer_assignments set perception_questions_version='perception-questions-v1'
      where id=v_assignment.id returning * into v_assignment;
  end if;
  return v_response || jsonb_build_object('perceptionQuestionsVersion',v_assignment.perception_questions_version);
end; $$;

create or replace function public.guard_advice_transfer_perception()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if old.phase1_locked_at is not null and
    row(new.perception_questions_version,new.perceived_consensus,new.room_for_disagreement)
    is distinct from row(old.perception_questions_version,old.perceived_consensus,old.room_for_disagreement) then
    raise exception 'Phase 1 perception answers are locked';
  end if;
  if new.perception_questions_version='perception-questions-v1' and old.phase1_locked_at is null
    and new.phase1_locked_at is not null then
    if new.perceived_consensus is null or new.room_for_disagreement is null then
      raise exception 'Both perception ratings must be selected before continuing';
    end if;
    new.phase1_snapshot := new.phase1_snapshot || jsonb_build_object(
      'perceptionQuestionsVersion',new.perception_questions_version,
      'perceivedConsensus',new.perceived_consensus,'roomForDisagreement',new.room_for_disagreement);
  end if;
  return new;
end; $$;
create or replace trigger advice_transfer_perception_phase1_guard
  before update of phase1_snapshot, phase1_locked_at, perception_questions_version, perceived_consensus, room_for_disagreement
  on public.advice_transfer_assignments for each row execute function public.guard_advice_transfer_perception();

create or replace function public.save_advice_transfer_stage_perception(
  p_assignment_id text,p_prolific_pid text,p_stage text,p_payload jsonb
) returns jsonb language plpgsql security definer set search_path = public
set lock_timeout = '250ms' as $$
declare v_assignment public.advice_transfer_assignments%rowtype; v_result jsonb;
  v_consensus integer; v_disagreement integer;
begin
  perform pg_advisory_xact_lock_shared(hashtext('advice_transfer_admission_v3'));
  select * into v_assignment from public.advice_transfer_assignments
    where assignment_id=trim(p_assignment_id) and prolific_pid=trim(p_prolific_pid) for update;
  if v_assignment.id is null then raise exception 'Assignment not found'; end if;
  if p_stage='phase1' and v_assignment.perception_questions_version='perception-questions-v1'
    and v_assignment.phase1_locked_at is null then
    if p_payload->>'perceptionQuestionsVersion' is distinct from 'perception-questions-v1' then
      raise exception 'Perception question version does not match this assignment'; end if;
    v_consensus:=public.advice_transfer_required_integer(p_payload->'perceivedConsensus','perceivedConsensus',0,100);
    v_disagreement:=public.advice_transfer_required_integer(p_payload->'roomForDisagreement','roomForDisagreement',0,100);
    update public.advice_transfer_assignments set perceived_consensus=v_consensus,room_for_disagreement=v_disagreement
      where id=v_assignment.id;
  end if;
  -- Validation, quota checks and all stage writes remain in the existing atomic save.
  -- A failure rolls back the ratings as well. A retry after lock returns the saved values.
  v_result:=public.save_advice_transfer_stage(p_assignment_id,p_prolific_pid,p_stage,p_payload);
  if p_stage='phase1' then
    v_result:=v_result||jsonb_build_object('snapshot',v_result->'phase1Snapshot');
  end if;
  return v_result;
end; $$;

create or replace function public.audit_advice_transfer_perception()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_assignment public.advice_transfer_assignments%rowtype;
begin
  select * into v_assignment from public.advice_transfer_assignments where assignment_id=new.assignment_id;
  new.perception_questions_version:=v_assignment.perception_questions_version;
  new.perceived_consensus:=v_assignment.perceived_consensus;
  new.room_for_disagreement:=v_assignment.room_for_disagreement;
  new.full_payload:=new.full_payload||jsonb_build_object(
    'perceptionQuestionsVersion',new.perception_questions_version,
    'perceivedConsensus',new.perceived_consensus,'roomForDisagreement',new.room_for_disagreement,
    'serverAudit',coalesce(new.full_payload->'serverAudit','{}'::jsonb)||jsonb_build_object(
      'perceptionQuestionsVersion',new.perception_questions_version));
  return new;
end; $$;
create or replace trigger advice_transfer_submission_perception_audit
  before insert on public.advice_transfer_submissions
  for each row execute function public.audit_advice_transfer_perception();
revoke all on function public.guard_advice_transfer_perception() from public,anon,authenticated;
revoke all on function public.audit_advice_transfer_perception() from public,anon,authenticated;
revoke all on function public.claim_advice_transfer_assignment_perception(text,text,text,boolean,integer,text) from public;
revoke all on function public.save_advice_transfer_stage_perception(text,text,text,jsonb) from public;
grant execute on function public.claim_advice_transfer_assignment_perception(text,text,text,boolean,integer,text) to anon,authenticated,service_role;
grant execute on function public.save_advice_transfer_stage_perception(text,text,text,jsonb) to anon,authenticated,service_role;
notify pgrst, 'reload schema';
commit;
