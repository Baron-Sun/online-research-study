-- Study 2: 0–100 ratings for newly assigned sessions. Historical ratings keep 1–7 units.
-- Apply atomically before deploying the client that uses the new claim endpoint.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
create temporary table scale_migration_before on commit drop as
select 'submissions' as kind,md5(coalesce(jsonb_agg(to_jsonb(s) order by id)::text,'')) as hash from public.advice_transfer_submissions s
union all select 'assignments',md5(coalesce(jsonb_agg(to_jsonb(s) order by id)::text,'')) from public.advice_transfer_assignments s
union all select 'settings',md5(coalesce(jsonb_agg(to_jsonb(s) order by setting_key)::text,'')) from public.advice_transfer_settings s
union all select 'stimuli',md5(coalesce(jsonb_agg(to_jsonb(s) order by stimulus_id)::text,'')) from public.advice_transfer_stimuli s
union all select 'quota',md5(coalesce(jsonb_agg(to_jsonb(s) order by id)::text,'')) from public.advice_transfer_quota_tokens s;
do $guard$ begin
  if (select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace='public'::regnamespace and proname='save_advice_transfer_stage') is distinct from 'd2f33abab1fff08510fcfe3b15f47347' then raise exception 'Unexpected installed function: save_advice_transfer_stage'; end if;
  if (select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace='public'::regnamespace and proname='save_advice_transfer_draft') is distinct from 'eaa52bb1bfc603518472a4d9361fa2fe' then raise exception 'Unexpected installed function: save_advice_transfer_draft'; end if;
  if (select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace='public'::regnamespace and proname='submit_advice_transfer_payload') is distinct from '09db4d4b9f5a8e26cb8bd4a76b790c46' then raise exception 'Unexpected installed function: submit_advice_transfer_payload'; end if;
  if (select md5(pg_get_functiondef(oid)) from pg_proc where pronamespace='public'::regnamespace and proname='advice_transfer_locked_payload') is distinct from '8a5f03ce76ec888c8a463f7098b774cd' then raise exception 'Unexpected installed function: advice_transfer_locked_payload'; end if;
end; $guard$;
alter table public.advice_transfer_assignments add column rating_scale_version text not null default 'likert-1-7-v1'
  check (rating_scale_version in ('likert-1-7-v1','ratings-0-100-v1'));
alter table public.advice_transfer_submissions add column rating_scale_version text not null default 'likert-1-7-v1'
  check (rating_scale_version in ('likert-1-7-v1','ratings-0-100-v1'));
comment on column public.advice_transfer_submissions.rating_scale_version is
  'Recorded rating units: likert-1-7-v1 uses 1–7 for difficulty/confidence/AI likelihood; ratings-0-100-v1 uses integer 0–100. Perception items use 0–100 in both versions when present. Never rescale stored historical values.';
create function public.advice_transfer_rating_valid(p_value integer,p_version text) returns boolean
language sql immutable set search_path=public as $$
select case p_version when 'likert-1-7-v1' then p_value between 1 and 7
  when 'ratings-0-100-v1' then p_value between 0 and 100 else false end;
$$;
create function public.advice_transfer_required_rating(p_value jsonb,p_name text,p_version text) returns integer
language plpgsql immutable set search_path=public as $$
begin
  if p_version='ratings-0-100-v1' then return public.advice_transfer_required_integer(p_value,p_name,0,100);
  elsif p_version='likert-1-7-v1' then return public.advice_transfer_required_integer(p_value,p_name,1,7);
  else raise exception 'Unknown rating scale'; end if;
end; $$;
create function public.advice_transfer_check_rating_version(p_version text,p_payload jsonb) returns void
language plpgsql immutable set search_path=public as $$
begin
  if coalesce(p_payload->>'ratingScaleVersion','likert-1-7-v1') is distinct from p_version then
    raise exception 'Rating scale version does not match this assignment. Please reload the study page.';
  end if;
end; $$;
alter table public.advice_transfer_submissions drop constraint advice_transfer_submissions_effort_check;
alter table public.advice_transfer_submissions add constraint advice_transfer_submissions_effort_check CHECK (public.advice_transfer_rating_valid(effort,rating_scale_version));
alter table public.advice_transfer_submissions drop constraint advice_transfer_submission_protocol_measures;
alter table public.advice_transfer_submissions add constraint advice_transfer_submission_protocol_measures CHECK ((((protocol_version <> 'advice-transfer-v4-gist'::text) AND (difficulty IS NOT NULL) AND public.advice_transfer_rating_valid(difficulty,rating_scale_version) AND (effort IS NOT NULL) AND public.advice_transfer_rating_valid(effort,rating_scale_version)) OR ((protocol_version = 'advice-transfer-v4-gist'::text) AND (comment_judgments IS NOT NULL) AND (jsonb_typeof(comment_judgments) = 'array'::text) AND (jsonb_array_length(comment_judgments) = 5) AND (gist_text IS NOT NULL) AND (length(btrim(gist_text)) > 0) AND (gist_difficulty IS NOT NULL) AND public.advice_transfer_rating_valid(gist_difficulty,rating_scale_version) AND (phase1_active_time_ms IS NOT NULL) AND (phase1_active_time_ms >= 0) AND (gist_active_time_ms IS NOT NULL) AND (gist_active_time_ms >= 0) AND (gist_active_time_ms <= phase1_active_time_ms) AND (phase1_locked_at IS NOT NULL) AND (phase2_locked_at IS NOT NULL) AND (phase2_locked_at >= phase1_locked_at) AND (((post_task_measure = 'effort'::text) AND (difficulty IS NULL) AND (effort IS NOT NULL) AND public.advice_transfer_rating_valid(effort,rating_scale_version)) OR ((post_task_measure = 'opinion_difficulty'::text) AND (difficulty IS NOT NULL) AND public.advice_transfer_rating_valid(difficulty,rating_scale_version) AND (effort IS NULL))))));
alter table public.advice_transfer_submissions drop constraint advice_transfer_submissions_confidence_check;
alter table public.advice_transfer_submissions add constraint advice_transfer_submissions_confidence_check CHECK (public.advice_transfer_rating_valid(confidence,rating_scale_version));
alter table public.advice_transfer_submissions drop constraint advice_transfer_submissions_difficulty_check;
alter table public.advice_transfer_submissions add constraint advice_transfer_submissions_difficulty_check CHECK (public.advice_transfer_rating_valid(difficulty,rating_scale_version));
alter table public.advice_transfer_submissions drop constraint advice_transfer_submissions_ai_likelihood_check;
alter table public.advice_transfer_submissions add constraint advice_transfer_submissions_ai_likelihood_check CHECK (public.advice_transfer_rating_valid(ai_likelihood,rating_scale_version));
CREATE OR REPLACE FUNCTION public.save_advice_transfer_stage(p_assignment_id text, p_prolific_pid text, p_stage text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '250ms'
AS $function$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_stimulus public.advice_transfer_stimuli%rowtype;
  v_heartbeat jsonb;
  v_snapshot jsonb;
  v_locked_at timestamptz;
  v_already_saved boolean := false;
  v_judgments jsonb := '[]'::jsonb;
  v_judgment jsonb;
  v_position integer;
  v_comment_index integer;
  v_label text;
  v_gist text;
  v_gist_word_count integer;
  v_gist_difficulty integer;
  v_phase1_ms integer;
  v_gist_ms integer;
  v_advice text;
  v_word_count integer;
  v_difficulty integer;
  v_effort integer;
  v_confidence integer;
  v_advice_ms integer;
  v_timings jsonb;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  if p_assignment_id is null or p_prolific_pid is null then
    raise exception 'Missing assignment or participant identifier';
  end if;
  if p_stage is null or p_stage not in ('phase1', 'phase2') then
    raise exception 'Unknown Study 2 phase';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) is distinct from 'object'
     or octet_length(p_payload::text) > 200000 then
    raise exception 'Stage payload must be a JSON object no larger than 200000 bytes';
  end if;
  if p_payload ->> 'schemaVersion' is distinct from 'advice-transfer-v4-gist' then
    raise exception 'Stage payload protocol is not advice-transfer-v4-gist';
  end if;

  perform pg_advisory_xact_lock_shared(hashtext('advice_transfer_admission_v3'));
  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id and prolific_pid = p_prolific_pid
   for update;
  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  perform public.advice_transfer_check_rating_version(v_assignment.rating_scale_version,p_payload);
  if v_assignment.protocol_version <> 'advice-transfer-v4-gist' then
    raise exception 'This assignment belongs to the legacy Study 2 protocol';
  end if;

  select * into v_stimulus
    from public.advice_transfer_stimulus_version(v_assignment.stimulus_id,v_assignment.material_version);
  if v_stimulus.stimulus_id is null then
    raise exception 'Assigned Study 2 stimulus was not found';
  end if;

  v_snapshot := case when p_stage = 'phase1'
    then v_assignment.phase1_snapshot else v_assignment.phase2_snapshot end;
  v_locked_at := case when p_stage = 'phase1'
    then v_assignment.phase1_locked_at else v_assignment.phase2_locked_at end;
  v_already_saved := v_snapshot is not null;
  if not v_already_saved then
    if p_stage = 'phase2' and v_assignment.phase1_snapshot is null then
      raise exception 'Phase 1 must be saved before Phase 2';
    end if;
    v_heartbeat := public.heartbeat_advice_transfer_assignment(p_assignment_id, p_prolific_pid);
    if not coalesce((v_heartbeat ->> 'active')::boolean, false) then
      raise exception 'This assignment is no longer active';
    end if;
    select * into v_assignment
      from public.advice_transfer_assignments
     where assignment_id = p_assignment_id;
    if jsonb_typeof(p_payload -> 'timings') is distinct from 'object' then
      raise exception 'Stage timings are required';
    end if;
    v_timings := p_payload -> 'timings';

    if p_stage = 'phase1' then
      if jsonb_typeof(p_payload -> 'commentJudgments') is distinct from 'array' then
        raise exception 'Exactly five comment classifications are required';
      end if;
      if jsonb_array_length(p_payload -> 'commentJudgments') <> 5 then
        raise exception 'Exactly five comment classifications are required';
      end if;
      for v_position in 1..5 loop
        v_judgment := p_payload -> 'commentJudgments' -> (v_position - 1);
        if jsonb_typeof(v_judgment) is distinct from 'object' then
          raise exception 'Comment classification % is invalid', v_position;
        end if;
        if public.advice_transfer_required_integer(
             v_judgment -> 'displayPosition', 'displayPosition', 1, 5
           ) <> v_position then
          raise exception 'Comment classifications must match display positions 1 through 5';
        end if;
        v_comment_index := public.advice_transfer_required_integer(
          v_judgment -> 'commentIndex', 'commentIndex', 0, 4
        );
        if v_comment_index <> (v_assignment.comment_order ->> (v_position - 1))::integer
           or v_judgment ->> 'commentSha256' is distinct from
                v_assignment.presented_comment_sha256 ->> (v_position - 1) then
          raise exception 'Comment classification % does not match its assigned comment', v_position;
        end if;
        v_label := v_judgment ->> 'label';
        if v_label is null or v_label not in ('YTA', 'NTA', 'ESH', 'NAH', 'INFO') then
          raise exception 'Each comment requires one of YTA, NTA, ESH, NAH, or INFO';
        end if;
        v_judgments := v_judgments || jsonb_build_array(jsonb_build_object(
          'displayPosition', v_position,
          'commentIndex', v_comment_index,
          'commentSha256', v_assignment.presented_comment_sha256 ->> (v_position - 1),
          'label', v_label
        ));
      end loop;
      if jsonb_typeof(p_payload -> 'gistText') is distinct from 'string' then
        raise exception 'A nonempty gist summary is required';
      end if;
      v_gist := btrim(p_payload ->> 'gistText');
      if v_gist = '' or v_gist !~ '\S' then
        raise exception 'A nonempty gist summary is required';
      end if;
      v_gist_word_count := public.advice_transfer_word_count(v_gist);
      if v_gist_word_count < 25 then
        raise exception 'A gist summary of at least 25 English words is required';
      end if;
      v_gist_difficulty := public.advice_transfer_required_rating(
        p_payload -> 'gistDifficulty', 'gistDifficulty', v_assignment.rating_scale_version);
      v_phase1_ms := public.advice_transfer_required_integer(
        v_timings -> 'phase1ActiveTimeMs', 'phase1ActiveTimeMs', 0, 2147483647
      );
      v_gist_ms := public.advice_transfer_required_integer(
        v_timings -> 'gistActiveTimeMs', 'gistActiveTimeMs', 0, 2147483647
      );
      if v_gist_ms > v_phase1_ms then
        raise exception 'Gist time cannot exceed total Phase 1 active time';
      end if;
      v_now := clock_timestamp();
      v_snapshot := jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'ratingScaleVersion', v_assignment.rating_scale_version,
        'stage', 'phase1',
        'designVariant', v_assignment.design_variant,
        'postTaskMeasure', v_assignment.post_task_measure,
        'responsePostId', case
          when v_assignment.design_variant = 'same_post'
            then v_stimulus.exposure_post_id
          else v_stimulus.target_post_id
        end,
        'responsePostSha256', case
          when v_assignment.design_variant = 'same_post'
            then v_stimulus.exposure_post_body_sha256
          else v_stimulus.target_post_body_sha256
        end,
        'commentJudgments', v_judgments,
        'gistText', v_gist,
        'gistWordCount', v_gist_word_count,
        'gistDifficulty', v_gist_difficulty,
        'timings', v_timings || jsonb_build_object(
          'phase1ActiveTimeMs', v_phase1_ms, 'gistActiveTimeMs', v_gist_ms
        ),
        'lockedAt', v_now
      );
      update public.advice_transfer_assignments
         set phase1_snapshot = v_snapshot, phase1_locked_at = v_now, updated_at = v_now
       where id = v_assignment.id
       returning * into v_assignment;
    else
      if jsonb_typeof(p_payload -> 'adviceText') is distinct from 'string' then
        raise exception 'An opinion of at least 77 English words is required';
      end if;
      v_advice := btrim(p_payload ->> 'adviceText');
      v_word_count := public.advice_transfer_word_count(v_advice);
      if v_word_count < 77 then
        raise exception 'An opinion of at least 77 English words is required';
      end if;
      if p_payload ? 'postTaskMeasure'
         and p_payload ->> 'postTaskMeasure'
           is distinct from v_assignment.post_task_measure then
        raise exception 'Post-task measure does not match assignment';
      end if;
      if v_assignment.post_task_measure = 'opinion_difficulty' then
        v_difficulty := public.advice_transfer_required_rating(
          p_payload -> 'difficulty', 'difficulty', v_assignment.rating_scale_version);
        if p_payload -> 'effort' is not null
           and jsonb_typeof(p_payload -> 'effort') is distinct from 'null' then
          raise exception 'Effort is not collected for this assignment';
        end if;
        v_effort := null;
      else
        v_effort := public.advice_transfer_required_rating(
          p_payload -> 'effort', 'effort', v_assignment.rating_scale_version);
        if p_payload -> 'difficulty' is not null
           and jsonb_typeof(p_payload -> 'difficulty') is distinct from 'null' then
          raise exception 'Opinion difficulty is not collected for this assignment';
        end if;
        v_difficulty := null;
      end if;
      v_confidence := public.advice_transfer_required_rating(p_payload -> 'confidence', 'confidence', v_assignment.rating_scale_version);
      v_advice_ms := public.advice_transfer_required_integer(
        v_timings -> 'adviceResponseTimeMs', 'adviceResponseTimeMs', 0, 2147483647
      );
      v_now := greatest(clock_timestamp(), v_assignment.phase1_locked_at);
      v_snapshot := jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'ratingScaleVersion', v_assignment.rating_scale_version,
        'stage', 'phase2',
        'designVariant', v_assignment.design_variant,
        'postTaskMeasure', v_assignment.post_task_measure,
        'responsePostId', case
          when v_assignment.design_variant = 'same_post'
            then v_stimulus.exposure_post_id
          else v_stimulus.target_post_id
        end,
        'responsePostSha256', case
          when v_assignment.design_variant = 'same_post'
            then v_stimulus.exposure_post_body_sha256
          else v_stimulus.target_post_body_sha256
        end,
        'adviceText', v_advice,
        'adviceWordCount', v_word_count,
        'adviceCharacterCount', char_length(v_advice),
        'difficulty', v_difficulty,
        'effort', v_effort,
        'confidence', v_confidence,
        'timings', v_timings || jsonb_build_object('adviceResponseTimeMs', v_advice_ms),
        'lockedAt', v_now
      );
      update public.advice_transfer_assignments
         set phase2_snapshot = v_snapshot, phase2_locked_at = v_now, updated_at = v_now
       where id = v_assignment.id
       returning * into v_assignment;
    end if;
    v_locked_at := v_now;
    update public.advice_transfer_assignments
       set draft_payload = public.advice_transfer_locked_payload(v_assignment, draft_payload),
           draft_updated_at = v_now
     where id = v_assignment.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'stage', p_stage,
    'postTaskMeasure', v_assignment.post_task_measure,
    'alreadySaved', v_already_saved,
    'snapshot', v_snapshot,
    'lockedAt', v_locked_at,
    'phase1Snapshot', v_assignment.phase1_snapshot,
    'phase1LockedAt', v_assignment.phase1_locked_at,
    'phase2Snapshot', v_assignment.phase2_snapshot,
    'phase2LockedAt', v_assignment.phase2_locked_at,
    'serverTime', v_now
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.save_advice_transfer_draft(p_assignment_id text, p_prolific_pid text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '250ms'
AS $function$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_heartbeat jsonb;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  if p_assignment_id is null or p_prolific_pid is null then
    raise exception 'Missing assignment or participant identifier';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Draft payload must be a JSON object';
  end if;
  if octet_length(p_payload::text) > 200000 then
    raise exception 'Draft payload is too large';
  end if;

  v_heartbeat := public.heartbeat_advice_transfer_assignment(
    p_assignment_id,
    p_prolific_pid
  );

  if coalesce((v_heartbeat ->> 'status'), '') = 'submitted' then
    select * into v_assignment
      from public.advice_transfer_assignments
     where assignment_id = p_assignment_id;
    return jsonb_build_object(
      'ok', true,
      'status', 'submitted',
      'savedAt', v_assignment.submitted_at,
      'alreadySubmitted', true
    );
  end if;

  if not coalesce((v_heartbeat ->> 'active')::boolean, false) then
    return jsonb_build_object(
      'ok', false,
      'status', coalesce(v_heartbeat ->> 'status', 'inactive'),
      'saved', false,
      'alreadySubmitted', false
    );
  end if;

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
     and prolific_pid = p_prolific_pid
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  perform public.advice_transfer_check_rating_version(v_assignment.rating_scale_version,p_payload);
  if v_assignment.status <> 'claimed' then
    raise exception 'This assignment is no longer active';
  end if;

  if v_assignment.protocol_version = 'advice-transfer-v4-gist'
     and p_payload ->> 'schemaVersion' is distinct from v_assignment.protocol_version then
    raise exception 'Draft protocol does not match assignment';
  elsif v_assignment.protocol_version <> 'advice-transfer-v4-gist'
        and p_payload ->> 'schemaVersion' = 'advice-transfer-v4-gist' then
    raise exception 'A legacy draft cannot be replaced with a v4 draft';
  end if;

  update public.advice_transfer_assignments
     set draft_payload = public.advice_transfer_locked_payload(v_assignment, p_payload),
         draft_updated_at = v_now,
         updated_at = v_now
   where id = v_assignment.id;

  return jsonb_build_object(
    'ok', true,
    'status', 'claimed',
    'savedAt', v_now,
    'leaseExpiresAt', v_assignment.lease_expires_at,
    'phase1Snapshot', v_assignment.phase1_snapshot,
    'phase1LockedAt', v_assignment.phase1_locked_at,
    'phase2Snapshot', v_assignment.phase2_snapshot,
    'phase2LockedAt', v_assignment.phase2_locked_at,
    'alreadySubmitted', false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.submit_advice_transfer_payload(p_assignment_id text, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '250ms'
AS $function$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_stimulus public.advice_transfer_stimuli%rowtype;
  v_existing public.advice_transfer_submissions%rowtype;
  v_token public.advice_transfer_quota_tokens%rowtype;
  v_advice text;
  v_word_count integer;
  v_character_count integer;
  v_difficulty integer;
  v_effort integer;
  v_confidence integer;
  v_exposure_time integer;
  v_advice_time integer;
  v_purpose text;
  v_stood_out text;
  v_stood_out_details text;
  v_ai_belief text;
  v_ai_likelihood integer;
  v_gender_identity text;
  v_age_years integer;
  v_english_proficiency text;
  v_education_level text;
  v_employment_status text;
  v_quota_disposition text := 'standby';
  v_comment_judgments jsonb;
  v_gist_text text;
  v_gist_difficulty integer;
  v_phase1_ms integer;
  v_gist_ms integer;
  v_now timestamptz := now();
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Submission payload must be a JSON object';
  end if;
  if octet_length(p_payload::text) > 200000 then
    raise exception 'Submission payload is too large';
  end if;

  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  perform public.reclaim_expired_advice_transfer_assignments();

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  perform public.advice_transfer_check_rating_version(v_assignment.rating_scale_version,p_payload);
  if nullif(trim(p_payload #>> '{participant,prolificPid}'), '')
       is distinct from v_assignment.prolific_pid then
    raise exception 'Participant does not match assignment';
  end if;

  select * into v_existing
    from public.advice_transfer_submissions
   where assignment_id = p_assignment_id;
  if v_existing.id is not null then
    return jsonb_build_object(
      'ok', true,
      'status', 'submitted',
      'submittedAt', v_existing.submitted_at,
      'alreadySubmitted', true
    );
  end if;

  if v_assignment.status = 'screened_out' then
    raise exception 'This session ended after two incorrect attention-check answers';
  end if;
  if v_assignment.status = 'abandoned'
     and v_assignment.abandonment_reason = 'lease_expired' then
    update public.advice_transfer_assignments
       set status = 'claimed',
           reservation_kind = case when is_test then 'test' else 'standby' end,
           quota_token_id = null,
           standby_enqueued_at = case
             when is_test then standby_enqueued_at
             else coalesce(standby_enqueued_at, v_now)
           end,
           last_heartbeat_at = v_now,
           abandoned_at = null,
           abandonment_reason = null,
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;
  elsif v_assignment.status <> 'claimed' then
    raise exception 'This assignment is no longer active';
  end if;

  if not v_assignment.is_test and v_assignment.reservation_kind = 'standby' then
    perform public.promote_advice_transfer_standby(
      v_assignment.stimulus_id,
      v_assignment.condition
    );
    select * into v_assignment
      from public.advice_transfer_assignments
     where id = v_assignment.id;
  end if;

  if v_assignment.is_test then
    v_quota_disposition := 'quota';
  elsif v_assignment.reservation_kind = 'quota' then
    select * into v_token
      from public.advice_transfer_quota_tokens
     where id = v_assignment.quota_token_id
       and state = 'reserved'
       and current_assignment_id = v_assignment.assignment_id
     for update;
    if v_token.id is not null then
      v_quota_disposition := 'quota';
    else
      update public.advice_transfer_assignments
         set reservation_kind = 'standby',
             quota_token_id = null,
             standby_enqueued_at = coalesce(standby_enqueued_at, v_now)
       where id = v_assignment.id
       returning * into v_assignment;
      v_quota_disposition := 'standby';
    end if;
  end if;

  select * into v_stimulus
    from public.advice_transfer_stimulus_version(v_assignment.stimulus_id,v_assignment.material_version);

  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    if p_payload ->> 'schemaVersion' is distinct from v_assignment.protocol_version then
      raise exception 'Submission protocol does not match assignment';
    end if;
    if v_assignment.phase1_snapshot is null or v_assignment.phase2_snapshot is null then
      raise exception 'Both Study 2 phases must be saved before final submission';
    end if;
    -- Never trust final/draft copies of locked data. This also makes a final
    -- retry safe after an earlier stage response was lost in transit.
    p_payload := public.advice_transfer_locked_payload(v_assignment, p_payload);
    v_comment_judgments := v_assignment.phase1_snapshot -> 'commentJudgments';
    v_gist_text := v_assignment.phase1_snapshot ->> 'gistText';
    v_gist_difficulty := public.advice_transfer_required_rating(
      v_assignment.phase1_snapshot -> 'gistDifficulty', 'gistDifficulty', v_assignment.rating_scale_version);
    v_phase1_ms := public.advice_transfer_required_integer(
      v_assignment.phase1_snapshot #> '{timings,phase1ActiveTimeMs}', 'phase1ActiveTimeMs', 0, 2147483647
    );
    v_gist_ms := public.advice_transfer_required_integer(
      v_assignment.phase1_snapshot #> '{timings,gistActiveTimeMs}', 'gistActiveTimeMs', 0, 2147483647
    );
    if p_payload -> 'demographics' is null
       or jsonb_typeof(p_payload -> 'demographics') is distinct from 'object' then
      raise exception 'Demographic responses are required';
    end if;
    v_gender_identity := lower(trim(coalesce(
      p_payload #>> '{demographics,genderIdentity}', ''
    )));
    v_age_years := public.advice_transfer_required_integer(
      p_payload #> '{demographics,ageYears}', 'ageYears', 18, 120
    );
    v_english_proficiency := lower(trim(coalesce(
      p_payload #>> '{demographics,englishProficiency}', ''
    )));
    v_education_level := lower(trim(coalesce(
      p_payload #>> '{demographics,educationLevel}', ''
    )));
    v_employment_status := lower(trim(coalesce(
      p_payload #>> '{demographics,employmentStatus}', ''
    )));
  elsif p_payload ->> 'schemaVersion' = 'advice-transfer-v4-gist' then
    raise exception 'A legacy assignment must finish using its original protocol';
  end if;

  v_advice := trim(coalesce(p_payload ->> 'adviceText', ''));
  v_word_count := public.advice_transfer_word_count(v_advice);
  v_character_count := char_length(v_advice);
  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    if v_assignment.post_task_measure = 'opinion_difficulty' then
      if v_assignment.phase2_snapshot ->> 'postTaskMeasure'
           is distinct from 'opinion_difficulty' then
        raise exception 'Locked Phase 2 measure does not match assignment';
      end if;
      -- Historical server-locked snapshots predate these three audit keys.
      -- Preserve them unchanged; the assignment/trigger remains authoritative.
      -- If any audit key exists, require the complete matching set.
      if v_assignment.phase2_snapshot ?| array['designVariant', 'responsePostId', 'responsePostSha256']
         and (
           v_assignment.phase2_snapshot ->> 'designVariant'
             is distinct from v_assignment.design_variant
           or v_assignment.phase2_snapshot ->> 'responsePostId'
             is distinct from v_stimulus.exposure_post_id
           or v_assignment.phase2_snapshot ->> 'responsePostSha256'
             is distinct from v_stimulus.exposure_post_body_sha256
         ) then
        raise exception 'Locked Phase 2 design audit does not match assignment';
      end if;
      v_difficulty := public.advice_transfer_required_rating(
        v_assignment.phase2_snapshot -> 'difficulty', 'difficulty', v_assignment.rating_scale_version);
      v_effort := null;
    else
      if v_assignment.phase2_snapshot ? 'postTaskMeasure'
         and v_assignment.phase2_snapshot ->> 'postTaskMeasure'
           is distinct from 'effort' then
        raise exception 'Locked Phase 2 measure does not match assignment';
      end if;
      v_difficulty := null;
      v_effort := public.advice_transfer_required_rating(
        v_assignment.phase2_snapshot -> 'effort', 'effort', v_assignment.rating_scale_version);
    end if;
    v_confidence := public.advice_transfer_required_rating(
      v_assignment.phase2_snapshot -> 'confidence', 'confidence', v_assignment.rating_scale_version);
  else
    v_difficulty := nullif(p_payload ->> 'difficulty', '')::integer;
    v_effort := nullif(p_payload ->> 'effort', '')::integer;
    v_confidence := nullif(p_payload ->> 'confidence', '')::integer;
  end if;
  v_exposure_time := coalesce(nullif(p_payload #>> '{timings,exposureTimeMs}', '')::integer, 0);
  v_advice_time := coalesce(nullif(p_payload #>> '{timings,adviceResponseTimeMs}', '')::integer, 0);
  v_purpose := trim(coalesce(p_payload ->> 'purposeGuess', ''));
  v_stood_out := lower(trim(coalesce(p_payload ->> 'commentsStoodOut', '')));
  v_stood_out_details := nullif(trim(coalesce(p_payload ->> 'commentsStoodOutDetails', '')), '');
  v_ai_belief := lower(trim(coalesce(p_payload ->> 'aiGeneratedBelief', '')));
  v_ai_likelihood := case when v_assignment.protocol_version = 'advice-transfer-v4-gist'
    then public.advice_transfer_required_rating(p_payload -> 'aiLikelihood', 'aiLikelihood', v_assignment.rating_scale_version)
    else nullif(p_payload ->> 'aiLikelihood', '')::integer end;

  if v_word_count < 77 then
    raise exception 'Advice must contain at least 77 English words';
  end if;
  if (
       v_assignment.protocol_version <> 'advice-transfer-v4-gist'
       and (
         v_difficulty is null or not public.advice_transfer_rating_valid(v_difficulty,v_assignment.rating_scale_version)
         or v_effort is null or not public.advice_transfer_rating_valid(v_effort,v_assignment.rating_scale_version)
       )
     )
     or (
       v_assignment.protocol_version = 'advice-transfer-v4-gist'
       and v_assignment.post_task_measure = 'effort'
       and (
         v_difficulty is not null
         or v_effort is null or not public.advice_transfer_rating_valid(v_effort,v_assignment.rating_scale_version)
       )
     )
     or (
       v_assignment.protocol_version = 'advice-transfer-v4-gist'
       and v_assignment.post_task_measure = 'opinion_difficulty'
       and (
         v_difficulty is null or not public.advice_transfer_rating_valid(v_difficulty,v_assignment.rating_scale_version)
         or v_effort is not null
       )
     )
     or v_confidence is null or not public.advice_transfer_rating_valid(v_confidence,v_assignment.rating_scale_version) then
    raise exception 'Required post-task ratings must match the assigned scale';
  end if;
  if v_exposure_time < 0 or v_advice_time < 0 then
    raise exception 'Response times cannot be negative';
  end if;
  if v_purpose = '' or v_purpose !~ '\S' then
    raise exception 'The study-purpose response is required';
  end if;
  if v_stood_out not in ('yes', 'no', 'unsure') then
    raise exception 'The comment-notice response is required';
  end if;
  if v_ai_belief not in ('yes', 'no', 'unsure')
     or v_ai_likelihood is null or not public.advice_transfer_rating_valid(v_ai_likelihood,v_assignment.rating_scale_version) then
    raise exception 'The AI-source responses are required';
  end if;
  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    if v_gender_identity not in ('male', 'female', 'other', 'prefer-not-to-say') then
      raise exception 'A valid gender identity response is required';
    end if;
    if v_english_proficiency not in
       ('yes', 'no-fluent', 'no-mostly-fluent', 'no-minimal-fluency') then
      raise exception 'A valid English-language response is required';
    end if;
    if v_education_level not in (
      'no-school',
      'eighth-grade-or-less',
      'more-than-eighth-less-than-high-school',
      'high-school-degree-or-equivalent',
      'some-college',
      'four-year-college-degree',
      'graduate-or-professional-training'
    ) then
      raise exception 'A valid education-level response is required';
    end if;
    if v_employment_status not in
       ('employed', 'self-employed', 'student', 'unemployed', 'other') then
      raise exception 'A valid employment-status response is required';
    end if;
  end if;

  insert into public.advice_transfer_submissions (
    assignment_id,
    prolific_pid,
    study_id,
    session_id,
    stimulus_id,
    pair_number,
    pair_role,
    condition,
    design_variant,
    post_task_measure,
    is_test,
    comment_order,
    comment_sha256,
    exposure_post_id,
    exposure_post_body_sha256,
    target_post_id,
    target_post_body_sha256,
    response_post_id,
    response_post_body_sha256,
    advice_text,
    advice_word_count,
    advice_character_count,
    difficulty,
    effort,
    confidence,
    exposure_time_ms,
    advice_response_time_ms,
    purpose_guess,
    comments_stood_out,
    comments_stood_out_details,
    ai_generated_belief,
    ai_likelihood,
    gender_identity,
    age_years,
    english_proficiency,
    education_level,
    employment_status,
    protocol_version,
    comment_judgments,
    gist_text,
    gist_difficulty,
    phase1_active_time_ms,
    gist_active_time_ms,
    phase1_locked_at,
    phase2_locked_at,
    full_payload,
    quota_disposition,
    submitted_at
  ) values (
    v_assignment.assignment_id,
    v_assignment.prolific_pid,
    v_assignment.study_id,
    v_assignment.session_id,
    v_assignment.stimulus_id,
    v_assignment.pair_number,
    v_stimulus.pair_role,
    v_assignment.condition,
    v_assignment.design_variant,
    v_assignment.post_task_measure,
    v_assignment.is_test,
    v_assignment.comment_order,
    v_assignment.presented_comment_sha256,
    v_stimulus.exposure_post_id,
    v_stimulus.exposure_post_body_sha256,
    v_stimulus.target_post_id,
    v_stimulus.target_post_body_sha256,
    case when v_assignment.design_variant = 'same_post'
      then v_stimulus.exposure_post_id else v_stimulus.target_post_id end,
    case when v_assignment.design_variant = 'same_post'
      then v_stimulus.exposure_post_body_sha256 else v_stimulus.target_post_body_sha256 end,
    v_advice,
    v_word_count,
    v_character_count,
    v_difficulty,
    v_effort,
    v_confidence,
    v_exposure_time,
    v_advice_time,
    v_purpose,
    v_stood_out,
    v_stood_out_details,
    v_ai_belief,
    v_ai_likelihood,
    v_gender_identity,
    v_age_years,
    v_english_proficiency,
    v_education_level,
    v_employment_status,
    v_assignment.protocol_version,
    v_comment_judgments,
    v_gist_text,
    v_gist_difficulty,
    v_phase1_ms,
    v_gist_ms,
    v_assignment.phase1_locked_at,
    v_assignment.phase2_locked_at,
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
      'serverAudit', jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'ratingScaleVersion', v_assignment.rating_scale_version,
        'stimulusId', v_assignment.stimulus_id,
        'pairNumber', v_assignment.pair_number,
        'pairRole', v_stimulus.pair_role,
        'condition', v_assignment.condition,
        'isTest', v_assignment.is_test,
        'designVariant', v_assignment.design_variant,
        'postTaskMeasure', v_assignment.post_task_measure,
        'commentOrder', v_assignment.comment_order,
        'commentHashes', v_assignment.presented_comment_sha256,
        'exposurePostId', v_stimulus.exposure_post_id,
        'exposurePostSha256', v_stimulus.exposure_post_body_sha256,
        'targetPostId', v_stimulus.target_post_id,
        'targetPostSha256', v_stimulus.target_post_body_sha256,
        'responsePostId', case when v_assignment.design_variant = 'same_post'
          then v_stimulus.exposure_post_id else v_stimulus.target_post_id end,
        'responsePostSha256', case when v_assignment.design_variant = 'same_post'
          then v_stimulus.exposure_post_body_sha256 else v_stimulus.target_post_body_sha256 end,
        'serverReceivedAt', v_now
      )
    ),
    v_quota_disposition,
    v_now
  );

  if not v_assignment.is_test and v_quota_disposition = 'quota' then
    update public.advice_transfer_quota_tokens
       set state = 'pending',
           reservation_expires_at = null,
           updated_at = v_now
     where id = v_assignment.quota_token_id
       and state = 'reserved'
       and current_assignment_id = v_assignment.assignment_id;

    if not found then
      -- A late browser must never steal a token that has already been given
      -- to its replacement. The response is retained as paid standby data.
      v_quota_disposition := 'standby';
      update public.advice_transfer_submissions
         set quota_disposition = 'standby'
       where assignment_id = p_assignment_id;
      update public.advice_transfer_assignments
         set reservation_kind = 'standby',
             quota_token_id = null,
             standby_enqueued_at = coalesce(standby_enqueued_at, v_now)
       where assignment_id = p_assignment_id;
    end if;
  end if;

  update public.advice_transfer_assignments
     set status = 'submitted',
         submitted_at = v_now,
         last_heartbeat_at = v_now,
         lease_expires_at = null,
         draft_payload = '{}'::jsonb,
         draft_updated_at = null,
         abandoned_at = null,
         abandonment_reason = null,
         updated_at = v_now
   where assignment_id = p_assignment_id;

  if not v_assignment.is_test and v_quota_disposition = 'standby' then
    perform public.promote_advice_transfer_standby(
      v_assignment.stimulus_id,
      v_assignment.condition
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', 'submitted',
    'submittedAt', v_now,
    'alreadySubmitted', false
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.advice_transfer_locked_payload(p_assignment advice_transfer_assignments, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb := coalesce(p_payload, '{}'::jsonb);
  v_timings jsonb;
begin
  if p_assignment.protocol_version <> 'advice-transfer-v4-gist' then
    return v_result;
  end if;
  v_timings := case when jsonb_typeof(v_result -> 'timings') = 'object'
    then v_result -> 'timings' else '{}'::jsonb end;
  -- opinionDifficulty is only a UI state name. Persist one canonical field so
  -- exports cannot accidentally count the same response twice.
  v_result := (v_result - 'opinionDifficulty') || jsonb_build_object(
    'schemaVersion', p_assignment.protocol_version,
    'ratingScaleVersion', p_assignment.rating_scale_version,
    'protocolVersion', p_assignment.protocol_version,
    'postTaskMeasure', p_assignment.post_task_measure,
    'phase1Snapshot', p_assignment.phase1_snapshot,
    'phase1LockedAt', p_assignment.phase1_locked_at,
    'phase2Snapshot', p_assignment.phase2_snapshot,
    'phase2LockedAt', p_assignment.phase2_locked_at,
    'difficulty', null,
    'effort', null
  );
  if p_assignment.phase1_snapshot is not null then
    v_result := v_result || jsonb_build_object(
      'commentJudgments', p_assignment.phase1_snapshot -> 'commentJudgments',
      'gistText', p_assignment.phase1_snapshot -> 'gistText',
      'gistDifficulty', p_assignment.phase1_snapshot -> 'gistDifficulty'
    );
    v_timings := v_timings || (p_assignment.phase1_snapshot -> 'timings')
      || jsonb_build_object('exposureTimeMs',
           p_assignment.phase1_snapshot #> '{timings,phase1ActiveTimeMs}');
  end if;
  if p_assignment.phase2_snapshot is not null then
    v_result := v_result || jsonb_build_object(
      'advice', p_assignment.phase2_snapshot -> 'adviceText',
      'adviceText', p_assignment.phase2_snapshot -> 'adviceText',
      'adviceWordCount', p_assignment.phase2_snapshot -> 'adviceWordCount',
      'adviceCharacterCount', p_assignment.phase2_snapshot -> 'adviceCharacterCount',
      'difficulty', case when p_assignment.post_task_measure = 'opinion_difficulty'
        then p_assignment.phase2_snapshot -> 'difficulty' else null end,
      'effort', case when p_assignment.post_task_measure = 'effort'
        then p_assignment.phase2_snapshot -> 'effort' else null end,
      'confidence', p_assignment.phase2_snapshot -> 'confidence'
    );
    v_timings := v_timings || (p_assignment.phase2_snapshot -> 'timings');
  end if;
  if p_assignment.phase1_snapshot is not null then
    v_timings := v_timings || jsonb_build_object(
      'phase1ActiveTimeMs', p_assignment.phase1_snapshot #> '{timings,phase1ActiveTimeMs}',
      'gistActiveTimeMs', p_assignment.phase1_snapshot #> '{timings,gistActiveTimeMs}',
      'exposureTimeMs', p_assignment.phase1_snapshot #> '{timings,phase1ActiveTimeMs}'
    );
  end if;
  if p_assignment.phase2_snapshot is not null then
    v_timings := v_timings || jsonb_build_object(
      'adviceResponseTimeMs', p_assignment.phase2_snapshot #> '{timings,adviceResponseTimeMs}'
    );
  end if;
  return v_result || jsonb_build_object('timings', v_timings);
end;
$function$;

create function public.guard_advice_transfer_rating_scale() returns trigger language plpgsql set search_path=public as $$
begin
  if new.rating_scale_version is distinct from old.rating_scale_version and (
    old.rating_scale_version<>'likert-1-7-v1' or new.rating_scale_version<>'ratings-0-100-v1'
    or new.protocol_version<>'advice-transfer-v4-gist' or old.status<>'claimed'
    or old.phase1_snapshot is not null or old.phase2_snapshot is not null
    or old.draft_updated_at is not null or coalesce(old.draft_payload,'{}'::jsonb)<>'{}'::jsonb
  ) then raise exception 'A started assignment cannot change rating scale'; end if;
  return new;
end; $$;
create trigger advice_transfer_rating_scale_guard before update on public.advice_transfer_assignments
for each row execute function public.guard_advice_transfer_rating_scale();
create function public.audit_advice_transfer_rating_scale() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  select rating_scale_version into new.rating_scale_version from public.advice_transfer_assignments where assignment_id=new.assignment_id;
  new.full_payload:=new.full_payload||jsonb_build_object('ratingScaleVersion',new.rating_scale_version,
    'serverAudit',coalesce(new.full_payload->'serverAudit','{}'::jsonb)||jsonb_build_object('ratingScaleVersion',new.rating_scale_version));
  return new;
end; $$;
create trigger advice_transfer_rating_scale_audit before insert on public.advice_transfer_submissions
for each row execute function public.audit_advice_transfer_rating_scale();
create function public.claim_advice_transfer_assignment_ratings(
 p_prolific_pid text,p_study_id text default null,p_session_id text default null,
 p_is_test boolean default false,p_pair_number integer default null,p_condition text default null)
returns jsonb language plpgsql security definer set search_path=public set lock_timeout='250ms' as $$
declare v_existing boolean; v_response jsonb; v_assignment public.advice_transfer_assignments%rowtype;
 v_pid text:=nullif(trim(p_prolific_pid),''); v_study text:=nullif(trim(p_study_id),'');
 v_session text:=nullif(trim(p_session_id),''); v_is_test boolean:=coalesce(v_pid~*'^(test|preview|qa)[-_]',false);
begin
 perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
 select exists(select 1 from public.advice_transfer_assignments where prolific_pid=v_pid
   and coalesce(study_id,'')=coalesce(v_study,'') and ((v_is_test and coalesce(session_id,'')=coalesce(v_session,''))
     or (not v_is_test and not is_test))) into v_existing;
 v_response:=public.claim_advice_transfer_assignment_revised(p_prolific_pid,p_study_id,p_session_id,p_is_test,p_pair_number,p_condition);
 if v_response->>'admissionStatus' is distinct from 'assigned' then return v_response; end if;
 select * into v_assignment from public.advice_transfer_assignments where assignment_id=v_response->>'assignmentId' for update;
 if not v_existing and v_assignment.protocol_version='advice-transfer-v4-gist' then
   update public.advice_transfer_assignments set rating_scale_version='ratings-0-100-v1'
   where id=v_assignment.id returning * into v_assignment;
 end if;
 return v_response||jsonb_build_object('ratingScaleVersion',v_assignment.rating_scale_version,
   'draftPayload',public.advice_transfer_locked_payload(v_assignment,v_assignment.draft_payload));
end; $$;
revoke all on function public.advice_transfer_rating_valid(integer,text) from public,anon,authenticated;
revoke all on function public.advice_transfer_required_rating(jsonb,text,text) from public,anon,authenticated;
revoke all on function public.advice_transfer_check_rating_version(text,jsonb) from public,anon,authenticated;
revoke all on function public.guard_advice_transfer_rating_scale() from public,anon,authenticated;
revoke all on function public.audit_advice_transfer_rating_scale() from public,anon,authenticated;
revoke all on function public.claim_advice_transfer_assignment_ratings(text,text,text,boolean,integer,text) from public;
grant execute on function public.claim_advice_transfer_assignment_ratings(text,text,text,boolean,integer,text) to anon,authenticated;
do $unchanged$ declare r record; actual text; begin
  for r in select * from scale_migration_before loop
    case r.kind
      when 'submissions' then select md5(coalesce(jsonb_agg(to_jsonb(s)-'rating_scale_version' order by id)::text,'')) into actual from public.advice_transfer_submissions s;
      when 'assignments' then select md5(coalesce(jsonb_agg(to_jsonb(s)-'rating_scale_version' order by id)::text,'')) into actual from public.advice_transfer_assignments s;
      when 'settings' then select md5(coalesce(jsonb_agg(to_jsonb(s) order by setting_key)::text,'')) into actual from public.advice_transfer_settings s;
      when 'stimuli' then select md5(coalesce(jsonb_agg(to_jsonb(s) order by stimulus_id)::text,'')) into actual from public.advice_transfer_stimuli s;
      when 'quota' then select md5(coalesce(jsonb_agg(to_jsonb(s) order by id)::text,'')) into actual from public.advice_transfer_quota_tokens s;
    end case;
    if actual is distinct from r.hash then raise exception 'Existing % changed',r.kind; end if;
  end loop;
end; $unchanged$;
notify pgrst,'reload schema';
commit;
select 'PASS: rating scale migration committed; historical answers, materials and recruitment unchanged' as result;
