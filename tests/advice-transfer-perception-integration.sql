-- QA only; no recruitment setting changes; always roll back the test records.
begin;
set local statement_timeout='45s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
do $test$
declare
  prefix text:='qa-perception-sql-'||gen_random_uuid()::text;
  pid text; claim jsonb; again jsonb; result jsonb; phase1 jsonb; phase2 jsonb; final_payload jsonb;
  judgments jsonb; invalid jsonb; bad jsonb; err text; i integer; rating record; field text;
  baseline_count bigint; baseline_settings jsonb;
  saved public.advice_transfer_submissions%rowtype;
begin
  select count(*) into baseline_count from public.advice_transfer_submissions where not is_test;
  select jsonb_object_agg(setting_key,setting_value) into baseline_settings from public.advice_transfer_settings;
  -- An already assigned participant keeps the old questions and can still save Phase 1.
  pid:=prefix||'-old';
  claim:=public.claim_advice_transfer_assignment_same_post(pid,'perception-qa','old',true,11,'human');
  again:=public.claim_advice_transfer_assignment_perception(pid,'perception-qa','old',true,11,'human');
  if again->>'assignmentId' is distinct from claim->>'assignmentId'
    or again->>'perceptionQuestionsVersion' is distinct from 'none' then raise exception 'Legacy assignment changed'; end if;
  select jsonb_agg(jsonb_build_object('displayPosition',j+1,'commentIndex',(claim->'commentOrder'->>j)::integer,
    'commentSha256',claim->'commentHashes'->>j,'label','YTA') order by j) into judgments from generate_series(0,4) j;
  phase1:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','commentJudgments',judgments,
    'gistText',repeat('word ',25),'gistDifficulty',4,'timings',jsonb_build_object('phase1ActiveTimeMs',12000,'gistActiveTimeMs',4000));
  perform public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase1',phase1);

  for rating in select * from (values (0,100),(50,50),(100,0)) r(consensus,disagreement) loop
    pid:=prefix||'-'||rating.consensus;
    claim:=public.claim_advice_transfer_assignment_perception(pid,'perception-qa','new',true,13,'ai');
    if claim->>'perceptionQuestionsVersion' is distinct from 'perception-questions-v1'
      or claim->>'labelFeedbackVersion' is distinct from 'original-label-v1' then raise exception 'New assignment lost a protocol version'; end if;
    judgments:='[]'::jsonb;
    for i in 0..4 loop
      perform public.record_advice_transfer_comment_label(claim->>'assignmentId',pid,i+1,
        (claim->'commentOrder'->>i)::integer,claim->'commentHashes'->>i,'YTA','choice-'||i);
      judgments:=judgments||jsonb_build_array(jsonb_build_object('displayPosition',i+1,
        'commentIndex',(claim->'commentOrder'->>i)::integer,'commentSha256',claim->'commentHashes'->>i,'label','YTA'));
    end loop;
    phase1:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','commentJudgments',judgments,
      'gistText',repeat('word ',25),'gistDifficulty',4,'perceptionQuestionsVersion','perception-questions-v1',
      'perceivedConsensus',rating.consensus,'roomForDisagreement',rating.disagreement,
      'timings',jsonb_build_object('phase1ActiveTimeMs',12000,'gistActiveTimeMs',4000));
    -- Direct calls to the pre-existing stage RPC cannot bypass the new requirement.
    err:=null;
    begin perform public.save_advice_transfer_stage(claim->>'assignmentId',pid,'phase1',phase1);
    exception when others then get stacked diagnostics err=message_text; end;
    if err is null or err !~ 'Both perception ratings' then raise exception 'Missing saved ratings accepted: %',err; end if;
    foreach field in array array['perceivedConsensus','roomForDisagreement'] loop
      for invalid in select value from jsonb_array_elements('[null,"0",-1,101,50.5]'::jsonb) loop
        bad:=jsonb_set(phase1,array[field],invalid); err:=null;
        begin perform public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase1',bad);
        exception when others then get stacked diagnostics err=message_text; end;
        if err is null or position(field in err)=0 then raise exception 'Malformed % accepted: %',field,err; end if;
      end loop;
      err:=null;
      begin perform public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase1',phase1-field);
      exception when others then get stacked diagnostics err=message_text; end;
      if err is null then raise exception 'Missing % accepted',field; end if;
    end loop;
    if exists(select 1 from public.advice_transfer_assignments where assignment_id=claim->>'assignmentId'
      and (perceived_consensus is not null or room_for_disagreement is not null or phase1_locked_at is not null)) then
      raise exception 'Failed save left partial data'; end if;
    result:=public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase1',phase1);
    if (result#>>'{snapshot,perceivedConsensus}')::integer is distinct from rating.consensus
      or (result#>>'{snapshot,roomForDisagreement}')::integer is distinct from rating.disagreement
      or result->'snapshot' is distinct from result->'phase1Snapshot'
      or result#>>'{snapshot,labelFeedbackVersion}' is distinct from 'original-label-v1' then
      raise exception 'Stage snapshot lost ratings or label feedback'; end if;
    again:=public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase1',phase1-'perceivedConsensus');
    if again->'snapshot' is distinct from result->'snapshot' or not (again->>'alreadySaved')::boolean then
      raise exception 'Retry changed the saved ratings'; end if;
    err:=null;
    begin update public.advice_transfer_assignments set perceived_consensus=42 where assignment_id=claim->>'assignmentId';
    exception when others then get stacked diagnostics err=message_text; end;
    if err is null or err !~ 'locked' then raise exception 'Locked rating was editable'; end if;
    again:=public.claim_advice_transfer_assignment_perception(pid,'perception-qa','new',true,13,'ai');
    if again->'phase1Snapshot' is distinct from result->'phase1Snapshot' then raise exception 'Reload lost the snapshot'; end if;
    phase2:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','adviceText',repeat('word ',77),
      'difficulty',4,'effort',null,'confidence',6,'timings',jsonb_build_object('adviceResponseTimeMs',16000));
    perform public.save_advice_transfer_stage_perception(claim->>'assignmentId',pid,'phase2',phase2);
    final_payload:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','assignmentId',claim->>'assignmentId',
      'participant',jsonb_build_object('prolificPid',pid,'studyId','perception-qa','sessionId','new'),
      'purposeGuess','Synthetic test, rolled back.','commentsStoodOut','no','commentsStoodOutDetails','',
      'aiGeneratedBelief','unsure','aiLikelihood',4,'perceivedConsensus',999,'roomForDisagreement',999,
      'demographics',jsonb_build_object('genderIdentity','prefer-not-to-say','ageYears',35,'englishProficiency','no-fluent',
      'educationLevel','graduate-or-professional-training','employmentStatus','self-employed'));
    perform public.submit_advice_transfer_payload(claim->>'assignmentId',final_payload);
    select * into saved from public.advice_transfer_submissions where assignment_id=claim->>'assignmentId';
    if saved.perceived_consensus is distinct from rating.consensus or saved.room_for_disagreement is distinct from rating.disagreement
      or saved.perception_questions_version is distinct from 'perception-questions-v1'
      or (saved.full_payload->>'perceivedConsensus')::integer is distinct from rating.consensus
      or (saved.full_payload->>'roomForDisagreement')::integer is distinct from rating.disagreement
      or saved.full_payload#>>'{serverAudit,perceptionQuestionsVersion}' is distinct from 'perception-questions-v1'
      or saved.label_feedback_version is distinct from 'original-label-v1' then
      raise exception 'Final submission failed canonical rating/version audit'; end if;
  end loop;
  if (select count(*) from public.advice_transfer_submissions where not is_test)<>baseline_count
    or (select jsonb_object_agg(setting_key,setting_value) from public.advice_transfer_settings) is distinct from baseline_settings then
    raise exception 'Formal sample or recruitment settings changed'; end if;
end; $test$;
rollback;
select 'PASS: 0/50/100, missing and malformed responses, atomic saves, immutable retries, reload, legacy sessions and final submission; all QA records rolled back' as result;
