-- Destructive-looking but transactionally isolated Study 2 admission test.
-- Run only against a seeded preview/staging database while formal recruitment
-- is closed and the formal tables are empty. Every mutation is rolled back.
begin;
set local statement_timeout = '60s';

update public.advice_transfer_settings
   set setting_value = '1'::jsonb
 where setting_key = 'formal_target_per_cell';
update public.advice_transfer_settings
   set setting_value = 'true'::jsonb
 where setting_key = 'formal_recruitment_open';

do $test$
declare
  v_claim jsonb;
  v_old_assignment text;
  v_new_assignment text;
  v_old_stimulus text;
  v_new_stimulus text;
  v_old_condition text;
  v_new_condition text;
  v_payload jsonb;
  v_token_state text;
  v_token_owner text;
  v_old_disposition text;
  v_new_validity text;
begin
  for i in 0..19 loop
    v_claim := public.claim_advice_transfer_assignment(
      'itv3-p' || lpad(i::text, 2, '0'),
      'integration-v3',
      's' || lpad(i::text, 2, '0'),
      false,
      null,
      null
    );
    if v_claim ->> 'admissionStatus' <> 'assigned' then
      raise exception 'initial claim % was not assigned: %', i, v_claim;
    end if;
    if i = 0 then
      v_old_assignment := v_claim ->> 'assignmentId';
    end if;
  end loop;

  if exists (
    select 1
      from public.advice_transfer_quota_tokens
     group by stimulus_id, condition
    having count(*) <> 1
       or count(*) filter (where state = 'reserved') <> 1
  ) then
    raise exception 'initial token distribution was not exactly one reserved token per cell';
  end if;

  v_claim := public.claim_advice_transfer_assignment(
    'itv3-waiter', 'integration-v3', 'swait', false, null, null
  );
  if v_claim ->> 'admissionStatus' <> 'waiting' then
    raise exception 'the extra participant did not enter the waiting room: %', v_claim;
  end if;

  select stimulus_id, condition
    into v_old_stimulus, v_old_condition
    from public.advice_transfer_assignments
   where assignment_id = v_old_assignment;

  update public.advice_transfer_assignments
     set lease_expires_at = now() - interval '1 second'
   where assignment_id = v_old_assignment;
  update public.advice_transfer_quota_tokens
     set reservation_expires_at = now() - interval '1 second'
   where current_assignment_id = v_old_assignment;
  perform public.reclaim_expired_advice_transfer_assignments();

  v_claim := public.claim_advice_transfer_assignment(
    'itv3-waiter', 'integration-v3', 'swait', false, null, null
  );
  if v_claim ->> 'admissionStatus' <> 'assigned' then
    raise exception 'the waiter was not promoted after expiry: %', v_claim;
  end if;
  v_new_assignment := v_claim ->> 'assignmentId';

  select stimulus_id, condition
    into v_new_stimulus, v_new_condition
    from public.advice_transfer_assignments
   where assignment_id = v_new_assignment;
  if (v_new_stimulus, v_new_condition) is distinct from
     (v_old_stimulus, v_old_condition) then
    raise exception 'replacement was not assigned to the released cell';
  end if;

  v_payload := jsonb_build_object(
    'participant', jsonb_build_object(
      'prolificPid', 'itv3-p00',
      'studyId', 'integration-v3',
      'sessionId', 's00'
    ),
    'adviceText', repeat('thoughtful advice word ', 25),
    'difficulty', 4,
    'effort', 4,
    'confidence', 4,
    'purposeGuess', 'understanding how people give advice',
    'commentsStoodOut', 'no',
    'commentsStoodOutDetails', '',
    'aiGeneratedBelief', 'unsure',
    'aiLikelihood', 4,
    'timings', jsonb_build_object(
      'exposureTimeMs', 1000,
      'adviceResponseTimeMs', 2000
    )
  );
  perform public.submit_advice_transfer_payload(v_old_assignment, v_payload);
  perform public.review_advice_transfer_assignment(v_old_assignment, 'valid', null);

  select quota_disposition
    into v_old_disposition
    from public.advice_transfer_submissions
   where assignment_id = v_old_assignment;
  if v_old_disposition <> 'standby' then
    raise exception 'late old browser should initially be standby, got %', v_old_disposition;
  end if;

  v_payload := jsonb_set(
    jsonb_set(v_payload, '{participant,prolificPid}', to_jsonb('itv3-waiter'::text)),
    '{participant,sessionId}',
    to_jsonb('swait'::text)
  );
  perform public.submit_advice_transfer_payload(v_new_assignment, v_payload);
  perform public.review_advice_transfer_assignment(v_new_assignment, 'valid', null);
  perform public.review_advice_transfer_assignment(
    v_new_assignment, 'excluded', 'integration replacement exclusion'
  );

  select token.state, token.current_assignment_id
    into v_token_state, v_token_owner
    from public.advice_transfer_quota_tokens token
   where token.stimulus_id = v_old_stimulus
     and token.condition = v_old_condition;
  select quota_disposition
    into v_old_disposition
    from public.advice_transfer_submissions
   where assignment_id = v_old_assignment;
  select validity_status
    into v_new_validity
    from public.advice_transfer_submissions
   where assignment_id = v_new_assignment;

  if v_token_state <> 'valid'
     or v_token_owner <> v_old_assignment
     or v_old_disposition <> 'quota'
     or v_new_validity <> 'excluded' then
    raise exception 'exclusion/promotion final state failed';
  end if;
  if exists (
    select 1
      from public.advice_transfer_formal_cell_progress
     where not quota_invariant_ok
        or quota_committed > target_per_cell
  ) then
    raise exception 'quota invariant failed after the full lifecycle';
  end if;
end
$test$;

rollback;

select
  'integration_passed_and_rolled_back' as status,
  (select setting_value from public.advice_transfer_settings
    where setting_key = 'formal_target_per_cell') as formal_target,
  (select setting_value from public.advice_transfer_settings
    where setting_key = 'formal_recruitment_open') as recruitment_open,
  (select count(*) from public.advice_transfer_quota_tokens) as token_count,
  (select count(*) from public.advice_transfer_assignments where not is_test)
    as formal_assignments,
  (select count(*) from public.advice_transfer_submissions where not is_test)
    as formal_submissions;
