-- Run after supabase_advice_transfer_same_post_migration.sql.
-- Every write is rolled back.
begin;

do $$
declare
  v_suffix text := replace(gen_random_uuid()::text, '-', '');
  v_new_pid text := 'qa-same-post-' || v_suffix;
  v_old_pid text := 'qa-a-to-b-' || v_suffix;
  v_new jsonb;
  v_old_initial jsonb;
  v_old_again jsonb;
  v_assignment public.advice_transfer_assignments%rowtype;
  v_stimulus public.advice_transfer_stimuli%rowtype;
  v_submission public.advice_transfer_submissions%rowtype;
begin
  v_new := public.claim_advice_transfer_assignment_same_post(
    v_new_pid, 'same-post-integration', 'new-session', true, 1, 'human'
  );
  if v_new ->> 'admissionStatus' is distinct from 'assigned'
     or v_new ->> 'designVariant' is distinct from 'same_post'
     or v_new #>> '{responsePost,postId}' is distinct from v_new #>> '{exposurePost,postId}'
     or v_new #>> '{responsePost,sha256}' is distinct from v_new #>> '{exposurePost,sha256}'
     or v_new #>> '{targetPost,postId}' is not distinct from v_new #>> '{exposurePost,postId}' then
    raise exception 'A new same-post claim did not return A as its audited response post';
  end if;

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = v_new ->> 'assignmentId';
  if v_assignment.design_variant is distinct from 'same_post' then
    raise exception 'The new assignment did not retain its same-post design stamp';
  end if;

  -- An assignment created through the historical v4 endpoint remains A-to-B
  -- when it later reconnects through the new wrapper.
  v_old_initial := public.claim_advice_transfer_assignment_v4(
    v_old_pid, 'same-post-integration', 'old-session', true, 1, 'ai'
  );
  v_old_again := public.claim_advice_transfer_assignment_same_post(
    v_old_pid, 'same-post-integration', 'old-session', true, 1, 'ai'
  );
  if v_old_initial ->> 'admissionStatus' is distinct from 'assigned'
     or v_old_again ->> 'designVariant' is distinct from 'a_to_b'
     or v_old_again #>> '{responsePost,postId}' is distinct from v_old_again #>> '{targetPost,postId}' then
    raise exception 'An existing v4 assignment was incorrectly converted to same-post';
  end if;

  select * into v_stimulus
    from public.advice_transfer_stimuli
   where stimulus_id = v_assignment.stimulus_id;

  insert into public.advice_transfer_submissions (
    assignment_id, prolific_pid, study_id, session_id, stimulus_id,
    pair_number, pair_role, condition, is_test, comment_order, comment_sha256,
    exposure_post_id, exposure_post_body_sha256,
    target_post_id, target_post_body_sha256,
    advice_text, advice_word_count, advice_character_count, difficulty,
    effort, confidence, exposure_time_ms, advice_response_time_ms,
    purpose_guess, comments_stood_out, comments_stood_out_details,
    ai_generated_belief, ai_likelihood,
    gender_identity, age_years, english_proficiency, education_level,
    employment_status, full_payload, quota_disposition, validity_status,
    protocol_version, comment_judgments, gist_text, gist_difficulty,
    phase1_active_time_ms, gist_active_time_ms, phase1_locked_at,
    phase2_locked_at
  ) values (
    v_assignment.assignment_id, v_assignment.prolific_pid,
    v_assignment.study_id, v_assignment.session_id, v_assignment.stimulus_id,
    v_assignment.pair_number, v_stimulus.pair_role, v_assignment.condition,
    true, v_assignment.comment_order, v_assignment.presented_comment_sha256,
    v_stimulus.exposure_post_id, v_stimulus.exposure_post_body_sha256,
    v_stimulus.target_post_id, v_stimulus.target_post_body_sha256,
    repeat('word ', 77), 77, 385, null,
    4, 5, 1000, 1000,
    'Integration test purpose', 'no', null, 'no', 2,
    'prefer-not-to-say', 30, 'yes', 'graduate-or-professional-training',
    'employed', '{}'::jsonb, 'quota', 'pending',
    'advice-transfer-v4-gist',
    '[{"displayPosition":1},{"displayPosition":2},{"displayPosition":3},{"displayPosition":4},{"displayPosition":5}]'::jsonb,
    repeat('gist ', 25), 4, 3000, 1000, now(), now()
  );

  select * into v_submission
    from public.advice_transfer_submissions
   where assignment_id = v_assignment.assignment_id;

  if v_submission.design_variant is distinct from 'same_post'
     or v_submission.response_post_id is distinct from v_stimulus.exposure_post_id
     or v_submission.response_post_body_sha256 is distinct from v_stimulus.exposure_post_body_sha256
     or v_submission.full_payload #>> '{serverAudit,responsePostId}'
          is distinct from v_stimulus.exposure_post_id then
    raise exception 'The submission audit did not record the actual same-post response target';
  end if;
end;
$$;

rollback;
