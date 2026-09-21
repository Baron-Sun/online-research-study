-- Run after the migration in a transaction; this test always rolls back.
begin;
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
do $test$
declare
  prefix text:='qa-revised-'||gen_random_uuid()::text;
  row record; old_session record; claim jsonb; again jsonb; expected public.advice_transfer_stimuli%rowtype;
  result jsonb; phase1 jsonb; phase2 jsonb; payload jsonb; judgments jsonb; bad jsonb;
  pid text; condition_name text; actual text; expected_text text; err text; i integer;
  formal_before text; settings_before text; quota_before text; checked integer:=0;
  saved public.advice_transfer_submissions%rowtype;
begin
  select md5(jsonb_agg(to_jsonb(s) order by id)::text) into formal_before
    from public.advice_transfer_submissions s where not is_test;
  select md5(jsonb_agg(to_jsonb(s) order by setting_key)::text) into settings_before from public.advice_transfer_settings s;
  select md5(jsonb_agg(to_jsonb(s) order by id)::text) into quota_before from public.advice_transfer_quota_tokens s;
  -- Resume every currently active historical QA assignment against its archived text.
  for old_session in select * from public.advice_transfer_assignments where is_test
    and material_version='original-comments-v1' and status='claimed' loop
    claim:=public.claim_advice_transfer_assignment_revised(old_session.prolific_pid,old_session.study_id,
      old_session.session_id,true,old_session.pair_number,old_session.condition);
    if claim->>'admissionStatus' is distinct from 'assigned' then continue; end if;
    if claim->>'assignmentId'<>old_session.assignment_id
      or claim->>'materialVersion'<>'original-comments-v1'
      or claim->>'perceptionQuestionsVersion'<>old_session.perception_questions_version
      or claim->'commentHashes'<>old_session.presented_comment_sha256 then
      raise exception 'Historical assignment changed on resume'; end if;
    select * into expected from public.advice_transfer_stimulus_version(old_session.stimulus_id,'original-comments-v1');
    for i in 0..4 loop
      actual:=claim->'comments'->>i;
      expected_text:=(case when old_session.condition='human' then expected.human_comments else expected.ai_comments end)
        ->>(old_session.comment_order->>i)::integer;
      if actual not in (expected_text,public.advice_transfer_remove_leading_judgment_label(expected_text),
        public.advice_transfer_remove_judgment_labels(expected_text)) then
        raise exception 'Historical text replaced'; end if;
    end loop;
  end loop;
  -- Every new post and source has correctly ordered and hashed material.
  for row in select * from public.advice_transfer_stimuli where active and pair_role='primary' order by pair_number loop
    foreach condition_name in array array['human','ai'] loop
      pid:=prefix||'-'||row.pair_number||'-'||condition_name;
      claim:=public.claim_advice_transfer_assignment_revised(pid,'revised-qa','new',true,row.pair_number,condition_name);
      if claim->>'materialVersion'<>'content-priority-v2-20260921'
        or claim->>'perceptionQuestionsVersion'<>'perception-questions-v2-reasons'
        or claim ? 'condition' then raise exception 'New assignment version or masking failed'; end if;
      judgments:='[]'::jsonb;
      for i in 0..4 loop
        expected_text:=(case when condition_name='human' then row.human_comments else row.ai_comments end)
          ->>(claim->'commentOrder'->>i)::integer;
        actual:=claim->'comments'->>i;
        if actual<>public.advice_transfer_remove_leading_judgment_label(expected_text)
          or encode(extensions.digest(actual,'sha256'),'hex')<>claim->'commentHashes'->>i then
          raise exception 'New displayed comment or hash does not match'; end if;
        -- Intentionally choose an incorrect label for every comment; continuing must work.
        expected_text:=case when public.advice_transfer_original_comment_label(expected_text)='YTA' then 'NTA' else 'YTA' end;
        result:=public.record_advice_transfer_comment_label(claim->>'assignmentId',pid,i+1,
          (claim->'commentOrder'->>i)::integer,claim->'commentHashes'->>i,expected_text,'first-'||i);
        if not (result->'commentLabelFeedback'->i->>'feedbackOffered')::boolean then
          raise exception 'Incorrect answer failed to show original label'; end if;
        judgments:=judgments||jsonb_build_array(jsonb_build_object('displayPosition',i+1,
          'commentIndex',(claim->'commentOrder'->>i)::integer,'commentSha256',claim->'commentHashes'->>i,'label',expected_text));
        checked:=checked+1;
      end loop;
      phase1:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','commentJudgments',judgments,
        'gistText',repeat('word ',25),'gistDifficulty',4,'perceptionQuestionsVersion','perception-questions-v2-reasons',
        'perceivedConsensus',0,'roomForDisagreement',100,
        'timings',jsonb_build_object('phase1ActiveTimeMs',12000,'gistActiveTimeMs',4000));
      bad:=jsonb_set(phase1,'{perceptionQuestionsVersion}','"perception-questions-v1"'); err:=null;
      begin perform public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase1',bad);
      exception when others then get stacked diagnostics err=message_text; end;
      if err is null then raise exception 'Wrong wording version accepted'; end if;
      result:=public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase1',phase1);
      if result#>>'{snapshot,materialVersion}'<>'content-priority-v2-20260921'
        or result#>>'{snapshot,perceptionQuestionsVersion}'<>'perception-questions-v2-reasons'
        or result#>>'{snapshot,perceivedConsensus}'<>'0' then raise exception 'Phase 1 audit failed'; end if;
      again:=public.claim_advice_transfer_assignment_revised(pid,'revised-qa','new',true,row.pair_number,condition_name);
      if again->'comments'<>claim->'comments' or again->'phase1Snapshot'<>result->'phase1Snapshot' then
        raise exception 'Reload changed text or answers'; end if;
      phase2:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','adviceText',repeat('word ',77),
        'difficulty',4,'effort',null,'confidence',6,'timings',jsonb_build_object('adviceResponseTimeMs',16000));
      perform public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase2',phase2);
      payload:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','assignmentId',claim->>'assignmentId',
        'participant',jsonb_build_object('prolificPid',pid,'studyId','revised-qa','sessionId','new'),
        'purposeGuess','Synthetic test, rolled back.','commentsStoodOut','no','commentsStoodOutDetails','',
        'aiGeneratedBelief','unsure','aiLikelihood',4,'materialVersion','forged','perceivedConsensus',999,
        'demographics',jsonb_build_object('genderIdentity','prefer-not-to-say','ageYears',35,
          'englishProficiency','no-fluent','educationLevel','graduate-or-professional-training','employmentStatus','self-employed'));
      perform public.submit_advice_transfer_payload(claim->>'assignmentId',payload);
      select * into saved from public.advice_transfer_submissions where assignment_id=claim->>'assignmentId';
      if saved.material_version<>'content-priority-v2-20260921'
        or saved.full_payload->>'materialVersion'<>saved.material_version
        or saved.full_payload#>>'{serverAudit,materialVersion}'<>saved.material_version
        or saved.perception_questions_version<>'perception-questions-v2-reasons'
        or saved.perceived_consensus<>0 or saved.room_for_disagreement<>100 then
        raise exception 'Submission audit failed'; end if;
    end loop;
  end loop;
  if checked<>100 then raise exception 'Not all 100 active comments checked'; end if;
  if (select md5(jsonb_agg(to_jsonb(s) order by id)::text) from public.advice_transfer_submissions s where not is_test)
    is distinct from formal_before
    or (select md5(jsonb_agg(to_jsonb(s) order by setting_key)::text) from public.advice_transfer_settings s)
      is distinct from settings_before
    or (select md5(jsonb_agg(to_jsonb(s) order by id)::text) from public.advice_transfer_quota_tokens s)
      is distinct from quota_before then raise exception 'Formal data or recruitment changed'; end if;
end; $test$;
rollback;
select 'PASS: all 100 comments, old-session recovery, new wording, incorrect-label continuation, refresh and canonical submission; all test records rolled back' as result;
