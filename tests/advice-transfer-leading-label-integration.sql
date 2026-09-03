-- Rollback-only acceptance test for the leading-verdict-only display rule.
-- It creates QA assignments inside one transaction and leaves no records.
begin;
set local statement_timeout = '60s';
set local lock_timeout = '5s';

do $test$
declare
  v_prefix text := 'qa-leading-label-' || replace(gen_random_uuid()::text, '-', '');
  v_new_pid text := v_prefix || '-new';
  v_legacy_pid text := v_prefix || '-legacy';
  v_new jsonb;
  v_raw jsonb;
  v_again jsonb;
  v_expected_comments jsonb;
  v_expected_hashes jsonb;
  v_legacy_comments jsonb;
  v_legacy_hashes jsonb;
  v_legacy_id text;
begin
  if public.advice_transfer_remove_leading_judgment_label(
       E'YTA first conclusion.\n\nNTA second conclusion.'
     ) is distinct from E'first conclusion.\n\nNTA second conclusion.'
     or public.advice_transfer_remove_leading_judgment_label(
       'This is valid. NTA.'
     ) is distinct from 'This is valid. NTA.'
     or public.advice_transfer_remove_leading_judgment_label(
       'no your definitely NTA'
     ) is distinct from 'no your definitely NTA'
     or public.advice_transfer_remove_leading_judgment_label(
       'I lean N-T-A, but if X then E-S-H.'
     ) is distinct from 'I lean N-T-A, but if X then E-S-H.' then
    raise exception 'The leading-only cleanup rewrote a later judgment label';
  end if;

  v_new := public.claim_advice_transfer_assignment_same_post(
    v_new_pid, 'integration-leading-label', 'new', true, 1, 'human'
  );
  if v_new ->> 'admissionStatus' is distinct from 'assigned'
     or v_new ->> 'designVariant' is distinct from 'same_post'
     or v_new ->> 'postTaskMeasure' is distinct from 'opinion_difficulty' then
    raise exception 'The new same-post QA assignment was not prepared correctly: %', v_new;
  end if;

  select jsonb_agg(to_jsonb(cleaned.comment_text) order by cleaned.position),
         jsonb_agg(
           to_jsonb(encode(extensions.digest(cleaned.comment_text, 'sha256'), 'hex'))
           order by cleaned.position
         )
    into v_expected_comments, v_expected_hashes
    from (
      select ordered.position,
             public.advice_transfer_remove_leading_judgment_label(
               case when assignment.condition = 'human'
                 then stimulus.human_comments -> ordered.comment_index
                 else stimulus.ai_comments -> ordered.comment_index
               end #>> '{}'
             ) as comment_text
        from public.advice_transfer_assignments assignment
        join public.advice_transfer_stimuli stimulus
          on stimulus.stimulus_id = assignment.stimulus_id
        cross join lateral (
          select value::integer as comment_index, ordinality as position
            from jsonb_array_elements_text(assignment.comment_order) with ordinality
        ) ordered
       where assignment.assignment_id = v_new ->> 'assignmentId'
    ) cleaned;

  if v_new -> 'comments' is distinct from v_expected_comments
     or v_new -> 'commentHashes' is distinct from v_expected_hashes then
    raise exception 'A new assignment did not use the leading-only display and hashes';
  end if;
  if exists (
    select 1
      from jsonb_array_elements_text(v_new -> 'comments') displayed(comment_text)
     where displayed.comment_text ~*
       '^[[:space:]*_]*(YTA|NTA|ESH|NAH|INFO)([^[:alnum:]]|$)'
  ) then
    raise exception 'A new displayed comment still begins with a verdict label';
  end if;

  -- Simulate an assignment whose hashes were created under the former
  -- all-position cleanup rule. It must resume byte-for-byte unchanged.
  v_raw := public.claim_advice_transfer_assignment(
    v_legacy_pid, 'integration-leading-label', 'legacy', true, 1, 'human'
  );
  v_legacy_id := v_raw ->> 'assignmentId';
  select jsonb_agg(to_jsonb(cleaned.comment_text) order by cleaned.position),
         jsonb_agg(
           to_jsonb(encode(extensions.digest(cleaned.comment_text, 'sha256'), 'hex'))
           order by cleaned.position
         )
    into v_legacy_comments, v_legacy_hashes
    from (
      select ordinality as position,
             public.advice_transfer_remove_judgment_labels(value) as comment_text
        from jsonb_array_elements_text(v_raw -> 'comments') with ordinality
    ) cleaned;
  update public.advice_transfer_assignments
     set protocol_version = 'advice-transfer-v4-gist',
         presented_comment_sha256 = v_legacy_hashes
   where assignment_id = v_legacy_id;

  v_again := public.claim_advice_transfer_assignment_v4(
    v_legacy_pid, 'integration-leading-label', 'legacy', true, 1, 'human'
  );
  if v_again -> 'comments' is distinct from v_legacy_comments
     or v_again -> 'commentHashes' is distinct from v_legacy_hashes then
    raise exception 'An existing all-position-cleaned assignment changed on resume';
  end if;
end;
$test$;

rollback;
select 'leading_label_only_integration_passed_and_rolled_back' as status;
