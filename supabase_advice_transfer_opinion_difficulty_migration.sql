-- Study 2 post-task measure migration.
--
-- Historical assignments keep the effort question they were created with.
-- New same-post assignments instead receive the final-opinion difficulty
-- question. The existing difficulty column stores that answer; the explicit
-- post_task_measure field makes the item wording auditable and prevents the
-- two constructs from being pooled accidentally.
begin;

alter table public.advice_transfer_assignments
  add column if not exists post_task_measure text not null default 'effort';

alter table public.advice_transfer_submissions
  add column if not exists post_task_measure text not null default 'effort',
  alter column effort drop not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.advice_transfer_assignments'::regclass
       and conname = 'advice_transfer_assignment_post_task_measure'
  ) then
    alter table public.advice_transfer_assignments
      add constraint advice_transfer_assignment_post_task_measure
      check (post_task_measure in ('effort', 'opinion_difficulty'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.advice_transfer_assignments'::regclass
       and conname = 'advice_transfer_assignment_difficulty_design'
  ) then
    alter table public.advice_transfer_assignments
      add constraint advice_transfer_assignment_difficulty_design
      check (post_task_measure <> 'opinion_difficulty' or design_variant = 'same_post');
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.advice_transfer_submissions'::regclass
       and conname = 'advice_transfer_submission_post_task_measure'
  ) then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submission_post_task_measure
      check (post_task_measure in ('effort', 'opinion_difficulty'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.advice_transfer_submissions'::regclass
       and conname = 'advice_transfer_submission_difficulty_design'
  ) then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submission_difficulty_design
      check (post_task_measure <> 'opinion_difficulty' or design_variant = 'same_post');
  end if;
end;
$$;

create or replace function public.submit_advice_transfer_payload(
  p_assignment_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
    from public.advice_transfer_stimuli
   where stimulus_id = v_assignment.stimulus_id;

  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    if p_payload ->> 'schemaVersion' is distinct from v_assignment.protocol_version then
      raise exception 'Submission protocol does not match assignment';
    end if;
    if v_assignment.phase1_snapshot is null or v_assignment.phase2_snapshot is null then
      raise exception 'Both Study 2 phases must be saved before final submission';
    end if;
    p_payload := public.advice_transfer_locked_payload(v_assignment, p_payload);
    v_comment_judgments := v_assignment.phase1_snapshot -> 'commentJudgments';
    v_gist_text := v_assignment.phase1_snapshot ->> 'gistText';
    v_gist_difficulty := public.advice_transfer_required_integer(
      v_assignment.phase1_snapshot -> 'gistDifficulty', 'gistDifficulty', 1, 7
    );
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
  v_difficulty := nullif(p_payload ->> 'difficulty', '')::integer;
  v_effort := nullif(p_payload ->> 'effort', '')::integer;
  v_confidence := nullif(p_payload ->> 'confidence', '')::integer;
  v_exposure_time := coalesce(nullif(p_payload #>> '{timings,exposureTimeMs}', '')::integer, 0);
  v_advice_time := coalesce(nullif(p_payload #>> '{timings,adviceResponseTimeMs}', '')::integer, 0);
  v_purpose := trim(coalesce(p_payload ->> 'purposeGuess', ''));
  v_stood_out := lower(trim(coalesce(p_payload ->> 'commentsStoodOut', '')));
  v_stood_out_details := nullif(trim(coalesce(p_payload ->> 'commentsStoodOutDetails', '')), '');
  v_ai_belief := lower(trim(coalesce(p_payload ->> 'aiGeneratedBelief', '')));
  v_ai_likelihood := case when v_assignment.protocol_version = 'advice-transfer-v4-gist'
    then public.advice_transfer_required_integer(p_payload -> 'aiLikelihood', 'aiLikelihood', 1, 7)
    else nullif(p_payload ->> 'aiLikelihood', '')::integer end;

  if v_word_count < 77 then
    raise exception 'Advice must contain at least 77 English words';
  end if;
  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    if v_assignment.post_task_measure = 'opinion_difficulty' then
      if v_difficulty is null or v_difficulty not between 1 and 7 or v_effort is not null then
        raise exception 'A difficulty rating between 1 and 7 is required; effort must be empty';
      end if;
    elsif v_effort is null or v_effort not between 1 and 7 or v_difficulty is not null then
      raise exception 'An effort rating between 1 and 7 is required; difficulty must be empty';
    end if;
  elsif v_difficulty is null or v_difficulty not between 1 and 7
     or v_effort is null or v_effort not between 1 and 7 then
    raise exception 'Required post-task ratings must each be between 1 and 7';
  end if;
  if v_confidence is null or v_confidence not between 1 and 7 then
    raise exception 'A confidence rating between 1 and 7 is required';
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
     or v_ai_likelihood is null or v_ai_likelihood not between 1 and 7 then
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
    is_test,
    comment_order,
    comment_sha256,
    exposure_post_id,
    exposure_post_body_sha256,
    target_post_id,
    target_post_body_sha256,
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
    post_task_measure,
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
    v_assignment.is_test,
    v_assignment.comment_order,
    v_assignment.presented_comment_sha256,
    v_stimulus.exposure_post_id,
    v_stimulus.exposure_post_body_sha256,
    v_stimulus.target_post_id,
    v_stimulus.target_post_body_sha256,
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
    v_assignment.post_task_measure,
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
      'postTaskMeasure', v_assignment.post_task_measure,
      'serverAudit', jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'stimulusId', v_assignment.stimulus_id,
        'pairNumber', v_assignment.pair_number,
        'pairRole', v_stimulus.pair_role,
        'condition', v_assignment.condition,
        'isTest', v_assignment.is_test,
        'postTaskMeasure', v_assignment.post_task_measure,
        'commentOrder', v_assignment.comment_order,
        'commentHashes', v_assignment.presented_comment_sha256,
        'exposurePostId', v_stimulus.exposure_post_id,
        'exposurePostSha256', v_stimulus.exposure_post_body_sha256,
        'targetPostId', v_stimulus.target_post_id,
        'targetPostSha256', v_stimulus.target_post_body_sha256,
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
$$;

-- The v4 constraint used to require difficulty=NULL for every v4 row. It now
-- binds the applicable numeric column to the exact question assigned.
alter table public.advice_transfer_submissions
  drop constraint if exists advice_transfer_submission_protocol_measures;

alter table public.advice_transfer_submissions
  add constraint advice_transfer_submission_protocol_measures check (
    (
      protocol_version <> 'advice-transfer-v4-gist'
      and difficulty is not null and difficulty between 1 and 7
      and effort is not null and effort between 1 and 7
    )
    or (
      protocol_version = 'advice-transfer-v4-gist'
      and comment_judgments is not null
      and jsonb_typeof(comment_judgments) = 'array'
      and jsonb_array_length(comment_judgments) = 5
      and gist_text is not null and length(btrim(gist_text)) > 0
      and gist_difficulty is not null and gist_difficulty between 1 and 7
      and phase1_active_time_ms is not null and phase1_active_time_ms >= 0
      and gist_active_time_ms is not null and gist_active_time_ms >= 0
      and gist_active_time_ms <= phase1_active_time_ms
      and phase1_locked_at is not null and phase2_locked_at is not null
      and phase2_locked_at >= phase1_locked_at
      and (
        (
          post_task_measure = 'effort'
          and difficulty is null
          and effort is not null and effort between 1 and 7
        )
        or (
          post_task_measure = 'opinion_difficulty'
          and difficulty is not null and difficulty between 1 and 7
          and effort is null
        )
      )
    )
  );

create or replace function public.advice_transfer_locked_payload(
  p_assignment public.advice_transfer_assignments,
  p_payload jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
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
$$;

create or replace function public.save_advice_transfer_stage(
  p_assignment_id text,
  p_prolific_pid text,
  p_stage text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
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

  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id and prolific_pid = p_prolific_pid
   for update;
  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.protocol_version <> 'advice-transfer-v4-gist' then
    raise exception 'This assignment belongs to the legacy Study 2 protocol';
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
      if jsonb_typeof(p_payload -> 'commentJudgments') is distinct from 'array'
         or jsonb_array_length(p_payload -> 'commentJudgments') <> 5 then
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
      v_gist_difficulty := public.advice_transfer_required_integer(
        p_payload -> 'gistDifficulty', 'gistDifficulty', 1, 7
      );
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
        'stage', 'phase1',
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
         and p_payload ->> 'postTaskMeasure' is distinct from v_assignment.post_task_measure then
        raise exception 'Post-task measure does not match assignment';
      end if;
      if v_assignment.post_task_measure = 'opinion_difficulty' then
        v_difficulty := public.advice_transfer_required_integer(
          p_payload -> 'difficulty', 'difficulty', 1, 7
        );
        if p_payload -> 'effort' is not null
           and jsonb_typeof(p_payload -> 'effort') is distinct from 'null' then
          raise exception 'The opinion-difficulty task must not include an effort rating';
        end if;
        v_effort := null;
      else
        v_effort := public.advice_transfer_required_integer(
          p_payload -> 'effort', 'effort', 1, 7
        );
        if p_payload -> 'difficulty' is not null
           and jsonb_typeof(p_payload -> 'difficulty') is distinct from 'null' then
          raise exception 'The effort task must not include a difficulty rating';
        end if;
        v_difficulty := null;
      end if;
      v_confidence := public.advice_transfer_required_integer(
        p_payload -> 'confidence', 'confidence', 1, 7
      );
      v_advice_ms := public.advice_transfer_required_integer(
        v_timings -> 'adviceResponseTimeMs', 'adviceResponseTimeMs', 0, 2147483647
      );
      v_now := greatest(clock_timestamp(), v_assignment.phase1_locked_at);
      v_snapshot := jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'stage', 'phase2',
        'postTaskMeasure', v_assignment.post_task_measure,
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
$$;

create or replace function public.claim_advice_transfer_assignment_same_post(
  p_prolific_pid text,
  p_study_id text default null,
  p_session_id text default null,
  p_is_test boolean default false,
  p_pair_number integer default null,
  p_condition text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_id uuid;
  v_response jsonb;
  v_assignment public.advice_transfer_assignments%rowtype;
  v_pid text := nullif(trim(p_prolific_pid), '');
  v_study text := nullif(trim(p_study_id), '');
  v_session text := nullif(trim(p_session_id), '');
  v_is_test boolean := coalesce(v_pid ~* '^(test|preview|qa)[-_]', false);
  v_response_post jsonb;
begin
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));

  select id into v_existing_id
    from public.advice_transfer_assignments
   where prolific_pid = v_pid
     and coalesce(study_id, '') = coalesce(v_study, '')
     and (
       (v_is_test and coalesce(session_id, '') = coalesce(v_session, ''))
       or (not v_is_test and not is_test)
     )
   order by created_at desc
   limit 1;

  v_response := public.claim_advice_transfer_assignment_v4(
    p_prolific_pid, p_study_id, p_session_id,
    p_is_test, p_pair_number, p_condition
  );

  if v_response ->> 'admissionStatus' <> 'assigned' then
    return v_response;
  end if;

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = v_response ->> 'assignmentId'
   for update;

  if v_existing_id is null
     and v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    update public.advice_transfer_assignments
       set design_variant = 'same_post',
           post_task_measure = 'opinion_difficulty',
           updated_at = now()
     where id = v_assignment.id
     returning * into v_assignment;
  end if;

  v_response_post := case
    when v_assignment.design_variant = 'same_post'
      then v_response -> 'exposurePost'
    else v_response -> 'targetPost'
  end;

  return v_response || jsonb_build_object(
    'designVariant', v_assignment.design_variant,
    'postTaskMeasure', v_assignment.post_task_measure,
    'responsePost', v_response_post,
    'draftPayload', public.advice_transfer_locked_payload(
      v_assignment, v_assignment.draft_payload
    )
  );
end;
$$;

-- Keep the actual response post and the exact post-task item authoritative in
-- both relational columns and the immutable server audit.
create or replace function public.set_advice_transfer_response_post_audit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_design_variant text;
  v_post_task_measure text;
  v_server_audit jsonb;
begin
  select design_variant, post_task_measure
    into v_design_variant, v_post_task_measure
    from public.advice_transfer_assignments
   where assignment_id = new.assignment_id;

  if v_design_variant is null or v_post_task_measure is null then
    raise exception 'Assignment design or post-task measure is missing';
  end if;

  new.design_variant := v_design_variant;
  new.post_task_measure := v_post_task_measure;
  if v_design_variant = 'same_post' then
    new.response_post_id := new.exposure_post_id;
    new.response_post_body_sha256 := new.exposure_post_body_sha256;
  else
    new.response_post_id := new.target_post_id;
    new.response_post_body_sha256 := new.target_post_body_sha256;
  end if;

  v_server_audit := case
    when jsonb_typeof(new.full_payload #> '{serverAudit}') = 'object'
      then new.full_payload -> 'serverAudit'
    else '{}'::jsonb
  end;

  new.full_payload := new.full_payload || jsonb_build_object(
    'designVariant', new.design_variant,
    'postTaskMeasure', new.post_task_measure,
    'responsePostId', new.response_post_id,
    'responsePostSha256', new.response_post_body_sha256,
    'serverAudit', v_server_audit || jsonb_build_object(
      'designVariant', new.design_variant,
      'postTaskMeasure', new.post_task_measure,
      'responsePostId', new.response_post_id,
      'responsePostSha256', new.response_post_body_sha256
    )
  );

  return new;
end;
$$;

drop trigger if exists advice_transfer_response_post_audit
  on public.advice_transfer_submissions;
create trigger advice_transfer_response_post_audit
before insert or update of assignment_id, exposure_post_id,
  exposure_post_body_sha256, target_post_id, target_post_body_sha256,
  post_task_measure, full_payload
on public.advice_transfer_submissions
for each row execute function public.set_advice_transfer_response_post_audit();

revoke all on function public.claim_advice_transfer_assignment_same_post(
  text, text, text, boolean, integer, text
) from public;
grant execute on function public.claim_advice_transfer_assignment_same_post(
  text, text, text, boolean, integer, text
) to anon, authenticated;

revoke all on function public.set_advice_transfer_response_post_audit()
  from public;

grant select, insert, update, delete on public.advice_transfer_assignments
  to service_role;
grant select, insert, update, delete on public.advice_transfer_submissions
  to service_role;

notify pgrst, 'reload schema';
commit;
