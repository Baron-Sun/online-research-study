-- V4 contract acceptance test. Requires setup + seed + v4 migration.
-- QA identifiers only; never opens recruitment or changes target settings.
-- All QA records, helper functions, and test mutations roll back together.
-- This is a single-transaction integration test, NOT a concurrent-client test.
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

create temporary table advice_transfer_v4_test_baseline on commit drop as
select
  (select jsonb_object_agg(setting_key, setting_value)
     from public.advice_transfer_settings) as settings,
  (select count(*) from public.advice_transfer_assignments where not is_test) as formal_assignments,
  (select count(*) from public.advice_transfer_submissions where not is_test) as formal_submissions,
  (select count(*) from public.advice_transfer_quota_tokens) as quota_tokens;

create function pg_temp.v4_expect_stage_error(
  p_assignment text, p_pid text, p_stage text, p_payload jsonb, p_pattern text
) returns void language plpgsql as $$
declare v_error text;
begin
  begin
    perform public.save_advice_transfer_stage(p_assignment, p_pid, p_stage, p_payload);
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;
  if v_error is null then
    raise exception 'Expected stage rejection matching %, but payload was accepted: %', p_pattern, p_payload;
  end if;
  if v_error !~* p_pattern then
    raise exception 'Unexpected stage error: % (expected %)', v_error, p_pattern;
  end if;
end;
$$;

create function pg_temp.v4_expect_final_error(
  p_assignment text, p_payload jsonb, p_pattern text
) returns void language plpgsql as $$
declare v_error text;
begin
  begin
    perform public.submit_advice_transfer_payload(p_assignment, p_payload);
  exception when others then
    get stacked diagnostics v_error = message_text;
  end;
  if v_error is null then
    raise exception 'Expected final rejection matching %, but payload was accepted', p_pattern;
  end if;
  if v_error !~* p_pattern then
    raise exception 'Unexpected final error: % (expected %)', v_error, p_pattern;
  end if;
end;
$$;

do $test$
declare
  v_prefix text := 'qa-v4-sql-' || replace(gen_random_uuid()::text, '-', '');
  v_pid text;
  v_hash_compat_pid text;
  v_legacy_pid text;
  v_id text;
  v_hash_compat_id text;
  v_legacy_id text;
  v_claim jsonb;
  v_again jsonb;
  v_result jsonb;
  v_phase1 jsonb;
  v_phase2 jsonb;
  v_phase1_result jsonb;
  v_phase2_result jsonb;
  v_final jsonb;
  v_legacy_final jsonb;
  v_demographics jsonb;
  v_draft jsonb;
  v_judgments jsonb;
  v_legacy_comments jsonb;
  v_legacy_hashes jsonb;
  v_case record;
  v_submission public.advice_transfer_submissions%rowtype;
  v_legacy_submission public.advice_transfer_submissions%rowtype;
  v_error text;
  v_advice text := 'NTA ' || repeat('word ', 76);
  v_gist_24 text := btrim(repeat('word ', 24));
  v_gist_25 text := btrim(repeat('word ', 25));
begin
  if coalesce((select (setting_value #>> '{}')::boolean
    from public.advice_transfer_settings where setting_key = 'formal_recruitment_open'), false) then
    raise exception 'Run the v4 acceptance test only while formal recruitment is closed';
  end if;
  v_pid := v_prefix || '-current';
  v_hash_compat_pid := v_prefix || '-hash-compat';
  v_legacy_pid := v_prefix || '-legacy';
  v_claim := public.claim_advice_transfer_assignment_v4(v_pid, 'integration-v4', 'current', true, 1, 'human');
  v_id := v_claim ->> 'assignmentId';
  if v_claim ->> 'protocolVersion' is distinct from 'advice-transfer-v4-gist'
     or v_claim ->> 'admissionStatus' is distinct from 'assigned'
     or not (v_claim ->> 'isTest')::boolean then
    raise exception 'New QA claim did not create an assigned v4 test session: %', v_claim;
  end if;
  if v_claim ? 'condition' or v_claim ? 'model' or v_claim ? 'modelLabel' then
    raise exception 'The public assignment leaked a source or model label';
  end if;
  if jsonb_array_length(v_claim -> 'comments') <> 5
     or jsonb_array_length(v_claim -> 'commentHashes') <> 5 then
    raise exception 'Assignment does not contain exactly five comments and hashes';
  end if;
  if exists (
    select 1
      from jsonb_array_elements_text(v_claim -> 'comments') displayed(comment_text)
     where displayed.comment_text ~* '(?<![[:alnum:]])(Y[[:blank:]._-]*T[[:blank:]._-]*A|N[[:blank:]._-]*T[[:blank:]._-]*A|E[[:blank:]._-]*S[[:blank:]._-]*H|N[[:blank:]._-]*A[[:blank:]._-]*H|I[[:blank:]._-]*N[[:blank:]._-]*F[[:blank:]._-]*O)(?![[:alnum:]])'
  ) then
    raise exception 'A presented v4 comment still contains an explicit judgment label: %',
      v_claim -> 'comments';
  end if;
  if exists (
    select 1
      from jsonb_array_elements_text(v_claim -> 'comments')
           with ordinality displayed(comment_text, position)
     where encode(digest(displayed.comment_text, 'sha256'), 'hex') is distinct from
           v_claim #>> array['commentHashes', (displayed.position - 1)::text]
  ) then
    raise exception 'A presented v4 comment hash does not match its displayed body';
  end if;
  if (select presented_comment_sha256
        from public.advice_transfer_assignments
       where assignment_id = v_id) is distinct from v_claim -> 'commentHashes' then
    raise exception 'The assignment did not persist the hashes of its displayed comments';
  end if;
  -- Every current raw stimulus starts with a verdict. Presentation removes all
  -- standalone verdict tokens while leaving the stored source arrays untouched.
  -- This exercises all 130 human/AI comments, including the reserve pairs.
  if (select count(*)
        from public.advice_transfer_stimuli stimulus
        cross join lateral jsonb_array_elements_text(
          stimulus.human_comments || stimulus.ai_comments
        ) raw(comment_text)
       where raw.comment_text ~* '^[[:space:]]*(YTA|NTA|ESH|NAH|INFO)([^[:alnum:]]|$)') <> 130 then
    raise exception 'The seeded leading-verdict audit no longer covers exactly 130 comments';
  end if;
  if exists (
    select 1
      from public.advice_transfer_stimuli stimulus
      cross join lateral jsonb_array_elements_text(
        stimulus.human_comments || stimulus.ai_comments
      ) raw(comment_text)
     where public.advice_transfer_remove_judgment_labels(raw.comment_text)
           ~* '(?<![[:alnum:]])(Y[[:blank:]._-]*T[[:blank:]._-]*A|N[[:blank:]._-]*T[[:blank:]._-]*A|E[[:blank:]._-]*S[[:blank:]._-]*H|N[[:blank:]._-]*A[[:blank:]._-]*H|I[[:blank:]._-]*N[[:blank:]._-]*F[[:blank:]._-]*O)(?![[:alnum:]])'
  ) then
    raise exception 'At least one seeded comment retains a standalone verdict after presentation cleanup';
  end if;
  if public.advice_transfer_remove_judgment_labels(E'YTA first conclusion.\n\nNTA second conclusion.')
       is distinct from E'first conclusion.\n\nsecond conclusion.'
     or public.advice_transfer_remove_judgment_labels('This is valid. NTA.')
       is distinct from 'This is valid.'
     or public.advice_transfer_remove_judgment_labels('no your definitely NTA')
       is distinct from 'no your definitely'
     or public.advice_transfer_remove_judgment_labels('I lean N-T-A, but if X then E-S-H.')
       is distinct from 'I lean but if X then'
     or public.advice_transfer_remove_judgment_labels('Contact Jonah for fresh information.')
       is distinct from 'Contact Jonah for fresh information.'
     or public.advice_transfer_remove_judgment_labels(
          public.advice_transfer_remove_judgment_labels('This is valid. NTA.')
        ) is distinct from public.advice_transfer_remove_judgment_labels('This is valid. NTA.') then
    raise exception 'The presentation cleanup failed its standalone-token or idempotence contract';
  end if;

  -- A v4 session that already stored hashes under the former leading-only
  -- display rule must resume with that exact historical presentation, never
  -- fall back to the raw labeled source.
  v_result := public.claim_advice_transfer_assignment(
    v_hash_compat_pid, 'integration-v4', 'hash-compat', true, 1, 'human'
  );
  v_hash_compat_id := v_result ->> 'assignmentId';
  select jsonb_agg(to_jsonb(cleaned.comment_text) order by cleaned.position),
         jsonb_agg(to_jsonb(encode(digest(cleaned.comment_text, 'sha256'), 'hex')) order by cleaned.position)
    into v_legacy_comments, v_legacy_hashes
    from (
      select ordinality as position,
             public.advice_transfer_remove_leading_judgment_label(value) as comment_text
        from jsonb_array_elements_text(v_result -> 'comments') with ordinality
    ) cleaned;
  update public.advice_transfer_assignments
     set protocol_version = 'advice-transfer-v4-gist',
         presented_comment_sha256 = v_legacy_hashes
   where assignment_id = v_hash_compat_id;
  v_again := public.claim_advice_transfer_assignment_v4(
    v_hash_compat_pid, 'integration-v4', 'hash-compat', true, 1, 'human'
  );
  if v_again -> 'comments' is distinct from v_legacy_comments
     or v_again -> 'commentHashes' is distinct from v_legacy_hashes then
    raise exception 'An existing leading-only v4 session did not preserve its historical display and hashes';
  end if;

  v_again := public.claim_advice_transfer_assignment_v4(v_pid, 'integration-v4', 'current', true, 1, 'human');
  if v_again ->> 'assignmentId' is distinct from v_id
     or v_again -> 'commentOrder' is distinct from v_claim -> 'commentOrder'
     or v_again -> 'comments' is distinct from v_claim -> 'comments'
     or v_again -> 'commentHashes' is distinct from v_claim -> 'commentHashes' then
    raise exception 'Repeated claim changed the assignment or presented comments';
  end if;

  select jsonb_agg(jsonb_build_object(
    'displayPosition', i + 1,
    'commentIndex', v_claim -> 'commentOrder' -> i,
    'commentSha256', v_claim -> 'commentHashes' -> i,
    'label', (array['YTA', 'NTA', 'ESH', 'NAH', 'INFO'])[i + 1]
  ) order by i) into v_judgments from generate_series(0, 4) i;
  v_phase1 := jsonb_build_object(
    'schemaVersion', 'advice-transfer-v4-gist',
    'commentJudgments', v_judgments,
    'gistText', v_gist_25,
    'gistDifficulty', 4,
    'timings', jsonb_build_object('phase1ActiveTimeMs', 12000, 'gistActiveTimeMs', 4000,
      'adviceResponseTimeMs', 999999)
  );
  v_phase2 := jsonb_build_object(
    'schemaVersion', 'advice-transfer-v4-gist',
    'adviceText', v_advice, 'effort', 3, 'confidence', 6,
    'timings', jsonb_build_object('adviceResponseTimeMs', 16000,
      'phase1ActiveTimeMs', 999999, 'gistActiveTimeMs', 999999)
  );
  v_demographics := jsonb_build_object(
    'genderIdentity', 'prefer-not-to-say',
    'ageYears', 35,
    'englishProficiency', 'no-fluent',
    'educationLevel', 'graduate-or-professional-training',
    'employmentStatus', 'self-employed'
  );
  v_final := jsonb_build_object(
    'schemaVersion', 'advice-transfer-v4-gist', 'assignmentId', v_id,
    'participant', jsonb_build_object('prolificPid', v_pid, 'studyId', 'integration-v4', 'sessionId', 'current'),
    'purposeGuess', 'Understanding how people respond to online opinions.',
    'commentsStoodOut', 'no', 'commentsStoodOutDetails', '',
    'aiGeneratedBelief', 'unsure', 'aiLikelihood', 4,
    'demographics', v_demographics
  );
  perform pg_temp.v4_expect_stage_error(v_id, v_pid, 'phase2', v_phase2, 'Phase 1 must be saved');
  perform pg_temp.v4_expect_final_error(v_id, v_final, 'Both Study 2 phases');

  for v_case in select * from (values
    (v_phase1 - 'commentJudgments', 'five comment classifications'),
    (jsonb_set(v_phase1, '{commentJudgments}', 'null'::jsonb), 'five comment classifications'),
    (jsonb_set(v_phase1, '{commentJudgments}', v_judgments - 4), 'five comment classifications'),
    (jsonb_set(v_phase1, '{commentJudgments}', v_judgments || jsonb_build_array(v_judgments -> 0)), 'five comment classifications'),
    (jsonb_set(v_phase1, '{commentJudgments,1,displayPosition}', '1'::jsonb), 'display positions'),
    (jsonb_set(v_phase1, '{commentJudgments,0,displayPosition}', '"1"'::jsonb), 'displayPosition'),
    (jsonb_set(v_phase1, '{commentJudgments,0,commentSha256}', to_jsonb(repeat('f', 64))), 'assigned comment'),
    (jsonb_set(v_phase1, '{commentJudgments,0,commentIndex}', to_jsonb(((v_claim #>> '{commentOrder,0}')::integer + 1) % 5)), 'assigned comment'),
    (jsonb_set(v_phase1, '{commentJudgments,0,label}', '"UNKNOWN"'::jsonb), 'Each comment requires'),
    (jsonb_set(v_phase1, '{commentJudgments,0,label}', 'null'::jsonb), 'Each comment requires'),
    (v_phase1 - 'gistText', 'nonempty gist'),
    (jsonb_set(v_phase1, '{gistText}', '""'::jsonb), 'nonempty gist'),
    (jsonb_set(v_phase1, '{gistText}', to_jsonb(E' \t\n'::text)), 'nonempty gist'),
    (jsonb_set(v_phase1, '{gistText}', '5'::jsonb), 'nonempty gist'),
    (jsonb_set(v_phase1, '{gistText}', to_jsonb(v_gist_24)), '25 English words'),
    (v_phase1 - 'gistDifficulty', 'gistDifficulty'),
    (jsonb_set(v_phase1, '{gistDifficulty}', 'null'::jsonb), 'gistDifficulty'),
    (jsonb_set(v_phase1, '{gistDifficulty}', '0'::jsonb), 'gistDifficulty'),
    (jsonb_set(v_phase1, '{gistDifficulty}', '8'::jsonb), 'gistDifficulty'),
    (jsonb_set(v_phase1, '{gistDifficulty}', '"4"'::jsonb), 'gistDifficulty'),
    (jsonb_set(v_phase1, '{gistDifficulty}', '3.5'::jsonb), 'gistDifficulty'),
    (v_phase1 - 'timings', 'Stage timings'),
    (v_phase1 #- '{timings,phase1ActiveTimeMs}', 'phase1ActiveTimeMs'),
    (jsonb_set(v_phase1, '{timings,phase1ActiveTimeMs}', '-1'::jsonb), 'phase1ActiveTimeMs'),
    (jsonb_set(v_phase1, '{timings,gistActiveTimeMs}', '13000'::jsonb), 'Gist time'),
    (v_phase1 - 'schemaVersion', 'protocol'),
    (jsonb_set(v_phase1, '{schemaVersion}', '"advice-transfer-v3-admission"'::jsonb), 'protocol')
  ) as cases(payload, pattern) loop
    perform pg_temp.v4_expect_stage_error(v_id, v_pid, 'phase1', v_case.payload, v_case.pattern);
  end loop;
  perform pg_temp.v4_expect_stage_error(v_id, v_pid || '-wrong', 'phase1', v_phase1, 'Assignment not found');
  perform pg_temp.v4_expect_stage_error(v_id, v_pid, 'unknown', v_phase1, 'Unknown Study 2 phase');

  v_phase1_result := public.save_advice_transfer_stage(v_id, v_pid, 'phase1', v_phase1);
  if (v_phase1_result ->> 'alreadySaved')::boolean
     or v_phase1_result -> 'snapshot' -> 'commentJudgments' is distinct from v_judgments
     or v_phase1_result #>> '{snapshot,gistText}' is distinct from v_gist_25
     or v_phase1_result ->> 'lockedAt' is null then
    raise exception 'First phase save did not persist exact classifications, the 25-word gist, and a lock';
  end if;
  -- Classification choices are recorded as given, without scoring or screening.
  if (select comprehension_failures from public.advice_transfer_assignments where assignment_id = v_id) <> 0 then
    raise exception 'Comment classifications unexpectedly affected comprehension failures';
  end if;
  v_result := public.save_advice_transfer_stage(v_id, v_pid, 'phase1',
    jsonb_set(v_phase1, '{gistText}', '"a conflicting retry"'::jsonb));
  if not (v_result ->> 'alreadySaved')::boolean
     or v_result -> 'snapshot' is distinct from v_phase1_result -> 'snapshot'
     or v_result -> 'lockedAt' is distinct from v_phase1_result -> 'lockedAt' then
    raise exception 'Lost phase-1 ACK retry did not return the immutable original snapshot';
  end if;

  v_error := null;
  begin
    update public.advice_transfer_assignments set phase1_snapshot = '{}'::jsonb where assignment_id = v_id;
  exception when others then get stacked diagnostics v_error = message_text;
  end;
  if v_error is null or v_error !~* 'Phase 1 answers are locked' then
    raise exception 'A locked Phase 1 snapshot could be overwritten: %', v_error;
  end if;

  v_draft := jsonb_build_object(
    'schemaVersion', 'advice-transfer-v4-gist', 'assignmentId', v_id, 'screen', 'exposure',
    'savedAt', '2099-01-01T00:00:00Z', 'gistText', 'stale overwrite', 'gistDifficulty', 7,
    'commentJudgments', '[]'::jsonb, 'phase1Snapshot', null, 'phase1LockedAt', null,
    'timings', jsonb_build_object('phase1ActiveTimeMs', 999999, 'gistActiveTimeMs', 999999)
  );
  perform public.save_advice_transfer_draft(v_id, v_pid, v_draft);
  perform public.mark_advice_transfer_departure(v_id, v_pid, v_draft);
  v_again := public.claim_advice_transfer_assignment_v4(v_pid, 'integration-v4', 'current', true, 1, 'human');
  if v_again -> 'phase1Snapshot' is distinct from v_phase1_result -> 'snapshot'
     or v_again #> '{draftPayload,commentJudgments}' is distinct from v_judgments
     or v_again #>> '{draftPayload,gistText}' is distinct from v_gist_25
     or v_again #>> '{draftPayload,timings,phase1ActiveTimeMs}' is distinct from '12000'
     or v_again -> 'comments' is distinct from v_claim -> 'comments' then
    raise exception 'A stale autosave/departure changed locked Phase 1 answers or comments';
  end if;

  for v_case in select * from (values
    (v_phase2 - 'adviceText', '77 English words'),
    (jsonb_set(v_phase2, '{adviceText}', to_jsonb(repeat('word ', 76))), '77 English words'),
    (jsonb_set(v_phase2, '{adviceText}', '""'::jsonb), '77 English words'),
    (jsonb_set(v_phase2, '{adviceText}', '77'::jsonb), '77 English words'),
    (v_phase2 - 'effort', 'effort'),
    (jsonb_set(v_phase2, '{effort}', 'null'::jsonb), 'effort'),
    (jsonb_set(v_phase2, '{effort}', '0'::jsonb), 'effort'),
    (jsonb_set(v_phase2, '{effort}', '"3"'::jsonb), 'effort'),
    (v_phase2 - 'confidence', 'confidence'),
    (jsonb_set(v_phase2, '{confidence}', '8'::jsonb), 'confidence'),
    (jsonb_set(v_phase2, '{confidence}', '1.5'::jsonb), 'confidence'),
    (v_phase2 - 'timings', 'Stage timings'),
    (v_phase2 #- '{timings,adviceResponseTimeMs}', 'adviceResponseTimeMs'),
    (jsonb_set(v_phase2, '{timings,adviceResponseTimeMs}', '-1'::jsonb), 'adviceResponseTimeMs')
  ) as cases(payload, pattern) loop
    perform pg_temp.v4_expect_stage_error(v_id, v_pid, 'phase2', v_case.payload, v_case.pattern);
  end loop;
  perform pg_temp.v4_expect_final_error(v_id, v_final, 'Both Study 2 phases');
  v_phase2_result := public.save_advice_transfer_stage(v_id, v_pid, 'phase2', v_phase2);
  v_result := public.save_advice_transfer_stage(v_id, v_pid, 'phase2',
    jsonb_set(v_phase2, '{adviceText}', '"a stale shorter draft"'::jsonb));
  if (v_phase2_result ->> 'alreadySaved')::boolean
     or not (v_result ->> 'alreadySaved')::boolean
     or v_result -> 'snapshot' is distinct from v_phase2_result -> 'snapshot'
     or v_result -> 'lockedAt' is distinct from v_phase2_result -> 'lockedAt'
     or (v_result #>> '{snapshot,adviceWordCount}')::integer <> 77 then
    raise exception 'Phase 2 did not retain the original 77-word response on retry';
  end if;
  v_draft := v_draft || jsonb_build_object('screen', 'ratings', 'advice', 'overwrite', 'effort', 1,
    'confidence', 1, 'phase2Snapshot', null, 'phase2LockedAt', null);
  perform public.save_advice_transfer_draft(v_id, v_pid, v_draft);
  perform public.mark_advice_transfer_departure(v_id, v_pid, v_draft);
  v_again := public.claim_advice_transfer_assignment_v4(v_pid, 'integration-v4', 'current', true, 1, 'human');
  if v_again -> 'phase2Snapshot' is distinct from v_phase2_result -> 'snapshot'
     or v_again #>> '{draftPayload,advice}' is distinct from btrim(v_advice)
     or v_again #>> '{draftPayload,effort}' is distinct from '3'
     or v_again #>> '{draftPayload,confidence}' is distinct from '6'
     or v_again #>> '{draftPayload,timings,adviceResponseTimeMs}' is distinct from '16000' then
    raise exception 'A stale autosave/departure changed locked Phase 2 answers';
  end if;

  for v_case in select * from (values
    (v_final - 'schemaVersion', 'protocol'),
    (jsonb_set(v_final, '{schemaVersion}', '"advice-transfer-v3-admission"'::jsonb), 'protocol'),
    (v_final - 'purposeGuess', 'study-purpose'),
    (jsonb_set(v_final, '{purposeGuess}', to_jsonb(E' \t\n'::text)), 'study-purpose'),
    (v_final - 'commentsStoodOut', 'comment-notice'),
    (jsonb_set(v_final, '{commentsStoodOut}', '"invalid"'::jsonb), 'comment-notice'),
    (v_final - 'aiGeneratedBelief', 'AI-source'),
    (v_final - 'aiLikelihood', 'aiLikelihood'),
    (jsonb_set(v_final, '{aiLikelihood}', '8'::jsonb), 'aiLikelihood'),
    (jsonb_set(v_final, '{aiLikelihood}', '"4"'::jsonb), 'aiLikelihood'),
    (jsonb_set(v_final, '{aiLikelihood}', '3.5'::jsonb), 'aiLikelihood'),
    (v_final - 'demographics', 'Demographic responses'),
    (jsonb_set(v_final, '{demographics}', '[]'::jsonb), 'Demographic responses'),
    (v_final #- '{demographics,genderIdentity}', 'gender identity'),
    (jsonb_set(v_final, '{demographics,genderIdentity}', '"invalid"'::jsonb), 'gender identity'),
    (v_final #- '{demographics,ageYears}', 'ageYears'),
    (jsonb_set(v_final, '{demographics,ageYears}', '17'::jsonb), 'ageYears'),
    (jsonb_set(v_final, '{demographics,ageYears}', '121'::jsonb), 'ageYears'),
    (jsonb_set(v_final, '{demographics,ageYears}', '"35"'::jsonb), 'ageYears'),
    (v_final #- '{demographics,englishProficiency}', 'English-language'),
    (jsonb_set(v_final, '{demographics,englishProficiency}', '"invalid"'::jsonb), 'English-language'),
    (v_final #- '{demographics,educationLevel}', 'education-level'),
    (jsonb_set(v_final, '{demographics,educationLevel}', '"invalid"'::jsonb), 'education-level'),
    (v_final #- '{demographics,employmentStatus}', 'employment-status'),
    (jsonb_set(v_final, '{demographics,employmentStatus}', '"invalid"'::jsonb), 'employment-status'),
    (jsonb_set(v_final, '{participant,prolificPid}', to_jsonb(v_pid || '-wrong')), 'Participant does not match')
  ) as cases(payload, pattern) loop
    perform pg_temp.v4_expect_final_error(v_id, v_case.payload, v_case.pattern);
  end loop;

  -- Final-payload copies cannot override the authoritative stage snapshots.
  v_final := v_final || jsonb_build_object('adviceText', 'overwrite', 'gistText', 'overwrite',
    'gistDifficulty', 1, 'effort', 1, 'confidence', 1, 'difficulty', 7);
  v_result := public.submit_advice_transfer_payload(v_id, v_final);
  v_again := public.submit_advice_transfer_payload(v_id, v_final);
  if not (v_result ->> 'ok')::boolean or (v_result ->> 'alreadySubmitted')::boolean
     or not (v_again ->> 'alreadySubmitted')::boolean
     or v_again -> 'submittedAt' is distinct from v_result -> 'submittedAt' then
    raise exception 'Final submission is not idempotent';
  end if;
  select * into v_submission from public.advice_transfer_submissions where assignment_id = v_id;
  if v_submission.protocol_version <> 'advice-transfer-v4-gist'
     or v_submission.difficulty is not null or v_submission.gist_difficulty <> 4
     or v_submission.gist_text <> v_gist_25
     or v_submission.comment_judgments is distinct from v_judgments
     or v_submission.comment_sha256 is distinct from v_claim -> 'commentHashes'
     or v_submission.comment_order is distinct from v_claim -> 'commentOrder'
     or v_submission.advice_text is distinct from btrim(v_advice)
     or v_submission.advice_word_count <> 77 or v_submission.effort <> 3 or v_submission.confidence <> 6
     or v_submission.phase1_active_time_ms <> 12000 or v_submission.gist_active_time_ms <> 4000
     or v_submission.advice_response_time_ms <> 16000 or v_submission.exposure_time_ms <> 12000
     or v_submission.gender_identity <> 'prefer-not-to-say' or v_submission.age_years <> 35
     or v_submission.english_proficiency <> 'no-fluent'
     or v_submission.education_level <> 'graduate-or-professional-training'
     or v_submission.employment_status <> 'self-employed'
     or v_submission.phase1_locked_at is null or v_submission.phase2_locked_at is null then
    raise exception 'Persisted v4 measures differ from the immutable stage answers';
  end if;
  if (select count(*) from public.advice_transfer_submissions where assignment_id = v_id) <> 1 then
    raise exception 'Repeated final submission created more than one row';
  end if;

  -- A pre-existing legacy assignment must stay legacy even when opened by v4.
  v_claim := public.claim_advice_transfer_assignment(v_legacy_pid, 'integration-v4', 'legacy', true, 2, 'ai');
  v_legacy_id := v_claim ->> 'assignmentId';
  perform public.save_advice_transfer_draft(v_legacy_id, v_legacy_pid, jsonb_build_object(
    'schemaVersion', 'advice-transfer-v3-admission', 'assignmentId', v_legacy_id,
    'screen', 'advice', 'advice', 'An unfinished legacy draft.'
  ));
  v_again := public.claim_advice_transfer_assignment_v4(v_legacy_pid, 'integration-v4', 'legacy', true, 2, 'ai');
  if v_again ->> 'assignmentId' is distinct from v_legacy_id
     or v_again ->> 'protocolVersion' is distinct from 'advice-transfer-v3-admission'
     or v_again #>> '{draftPayload,advice}' is distinct from 'An unfinished legacy draft.' then
    raise exception 'The v4 wrapper upgraded or discarded an existing legacy assignment';
  end if;
  perform pg_temp.v4_expect_stage_error(v_legacy_id, v_legacy_pid, 'phase1', v_phase1, 'legacy Study 2 protocol');
  v_legacy_final := jsonb_build_object(
    'schemaVersion', 'advice-transfer-v3-admission', 'assignmentId', v_legacy_id,
    'participant', jsonb_build_object('prolificPid', v_legacy_pid, 'studyId', 'integration-v4', 'sessionId', 'legacy'),
    'adviceText', v_advice, 'difficulty', 4, 'effort', 3, 'confidence', 6,
    'purposeGuess', 'Understanding advice.', 'commentsStoodOut', 'no',
    'commentsStoodOutDetails', '', 'aiGeneratedBelief', 'unsure', 'aiLikelihood', 4,
    'timings', jsonb_build_object('exposureTimeMs', 12000, 'adviceResponseTimeMs', 16000)
  );
  perform pg_temp.v4_expect_final_error(v_legacy_id,
    jsonb_set(v_legacy_final, '{schemaVersion}', '"advice-transfer-v4-gist"'::jsonb), 'original protocol');
  perform pg_temp.v4_expect_final_error(v_legacy_id,
    jsonb_set(v_legacy_final, '{adviceText}', to_jsonb(repeat('word ', 76))), '77 English words');
  perform pg_temp.v4_expect_final_error(v_legacy_id, v_legacy_final - 'difficulty', 'post-task ratings');
  v_result := public.submit_advice_transfer_payload(v_legacy_id, v_legacy_final);
  v_again := public.submit_advice_transfer_payload(v_legacy_id, v_legacy_final);
  select * into v_legacy_submission from public.advice_transfer_submissions where assignment_id = v_legacy_id;
  if not (v_result ->> 'ok')::boolean or not (v_again ->> 'alreadySubmitted')::boolean
     or v_legacy_submission.protocol_version <> 'advice-transfer-v3-admission'
     or v_legacy_submission.difficulty <> 4 or v_legacy_submission.gist_difficulty is not null
     or v_legacy_submission.comment_judgments is not null
     or v_legacy_submission.gender_identity is not null
     or v_legacy_submission.age_years is not null
     or v_legacy_submission.english_proficiency is not null
     or v_legacy_submission.education_level is not null
     or v_legacy_submission.employment_status is not null then
    raise exception 'Legacy final submission or legacy retry failed after migration';
  end if;

  if exists (select 1 from public.advice_transfer_assignments
    where assignment_id in (v_id, v_hash_compat_id, v_legacy_id)
      and (not is_test or quota_token_id is not null)) then
    raise exception 'QA assignments consumed formal quota';
  end if;
  if (select count(*) from public.advice_transfer_assignments where not is_test)
       <> (select formal_assignments from advice_transfer_v4_test_baseline)
     or (select count(*) from public.advice_transfer_submissions where not is_test)
       <> (select formal_submissions from advice_transfer_v4_test_baseline)
     or (select count(*) from public.advice_transfer_quota_tokens)
       <> (select quota_tokens from advice_transfer_v4_test_baseline)
     or (select jsonb_object_agg(setting_key, setting_value) from public.advice_transfer_settings)
       is distinct from (select settings from advice_transfer_v4_test_baseline) then
    raise exception 'QA acceptance tests changed formal record counts, tokens, or settings';
  end if;
end;
$test$;

rollback;

select 'v4_integration_passed_and_rolled_back' as status;
