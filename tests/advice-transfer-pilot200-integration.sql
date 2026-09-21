-- Real allocator and save functions; every synthetic record is rolled back.
begin;
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
do $test$
declare
  cohort text:='6ab145947e9c974c2b6cf1cd';
  previous text:='6a9b2d61ae180a9b2920551b';
  prefix text:='pilot200-rehearsal-'||gen_random_uuid()::text;
  pid text; old_pid text; error_message text; claim jsonb; result jsonb; again jsonb;
  judgments jsonb; phase1 jsonb; phase2 jsonb; payload jsonb; raw text; selected text;
  historical_submissions text; historical_assignments text; historical_tokens text;
  i integer; j integer; checked integer:=0; cell record;
  standby public.advice_transfer_assignments%rowtype;
  displaced public.advice_transfer_assignments%rowtype;
  assignment public.advice_transfer_assignments%rowtype;
  saved public.advice_transfer_submissions%rowtype;
begin
  if public.advice_transfer_active_study_id()<>cohort then raise exception 'Wrong active study'; end if;
  select md5(jsonb_agg(to_jsonb(s) order by id)::text) into historical_submissions
    from public.advice_transfer_submissions s where study_id=previous and not is_test;
  select md5(jsonb_agg(to_jsonb(a) order by id)::text) into historical_assignments
    from public.advice_transfer_assignments a where study_id=previous and not is_test;
  select md5(jsonb_agg(to_jsonb(q) order by id)::text) into historical_tokens
    from public.advice_transfer_quota_tokens q where study_id=previous;

  -- Old completed standbys must not consume the new cohort's empty slots.
  for cell in select stimulus_id,condition from public.advice_transfer_formal_cell_progress loop
    if public.promote_advice_transfer_standby(cell.stimulus_id,cell.condition)<>0 then
      raise exception 'An old standby was promoted into the new pilot'; end if;
  end loop;
  if public.ensure_advice_transfer_quota_tokens()<>0 then raise exception 'Quota generation is not idempotent'; end if;

  -- The formal entry is tied to this Prolific study, and previous participants are blocked.
  error_message:=null;
  begin perform public.claim_advice_transfer_assignment_revised(prefix||'-wrong-study','wrong-study','new',false,null,null);
  exception when others then get stacked diagnostics error_message=message_text; end;
  if error_message is null or error_message not like '%not open for recruitment%' then
    raise exception 'Incorrect study ID was not rejected: %',error_message; end if;
  select prolific_pid into old_pid from public.advice_transfer_submissions where study_id=previous and not is_test limit 1;
  error_message:=null;
  begin perform public.claim_advice_transfer_assignment_revised(old_pid,cohort,'new',false,null,null);
  exception when others then get stacked diagnostics error_message=message_text; end;
  if error_message is null or error_message not like '%earlier version%' then
    raise exception 'Previous participant was not blocked: %',error_message; end if;

  -- Allocate 200 distinct new participants through the production entry point.
  for i in 1..200 loop
    pid:=prefix||'-'||i;
    claim:=public.claim_advice_transfer_assignment_revised(pid,cohort,'new',false,null,null);
    if claim->>'admissionStatus' is distinct from 'assigned'
      or claim->>'materialVersion' is distinct from 'content-priority-v2-20260921'
      or claim->>'perceptionQuestionsVersion' is distinct from 'perception-questions-v2-reasons'
      or claim->>'labelFeedbackVersion' is distinct from 'original-label-v1'
      or claim ? 'condition' or (claim->>'isTest')::boolean then
      raise exception 'Formal assignment % failed or used the wrong version',i; end if;
  end loop;
  if (select count(*) from public.advice_transfer_assignments where study_id=cohort and not is_test and reservation_kind='quota')<>200
    or (select count(distinct quota_token_id) from public.advice_transfer_assignments where study_id=cohort and not is_test)<>200
    or exists(select 1 from public.advice_transfer_formal_cell_progress
      where reserved<>10 or token_total<>10 or available<>0 or not quota_invariant_ok) then
    raise exception '200 entrants did not create ten unique reservations in each of 20 cells'; end if;

  -- Entry 201 waits; a standby can take over only a released token in the same new-cohort cell.
  pid:=prefix||'-extra';
  claim:=public.claim_advice_transfer_assignment_revised(pid,cohort,'new',false,null,null);
  if claim->>'admissionStatus'<>'waiting' then raise exception 'Capacity cap failed'; end if;
  update public.advice_transfer_waitlist set enqueued_at=now()-interval '91 seconds'
    where prolific_pid=pid and study_id=cohort;
  claim:=public.claim_advice_transfer_assignment_revised(pid,cohort,'new',false,null,null);
  select * into standby from public.advice_transfer_assignments where assignment_id=claim->>'assignmentId';
  if standby.reservation_kind is distinct from 'standby' or standby.quota_token_id is not null then
    raise exception 'Standby consumed a quota prematurely'; end if;
  select * into displaced from public.advice_transfer_assignments where study_id=cohort and not is_test
    and reservation_kind='quota' and stimulus_id=standby.stimulus_id and condition=standby.condition limit 1;
  perform public.withdraw_advice_transfer_assignment(displaced.assignment_id,displaced.prolific_pid,'participant_withdrew');
  select * into standby from public.advice_transfer_assignments where assignment_id=standby.assignment_id;
  if standby.reservation_kind<>'quota' or standby.quota_token_id is distinct from displaced.quota_token_id then
    raise exception 'Same-cell standby replacement failed'; end if;

  -- A token cannot be attached to a participant from the historical cohort.
  error_message:=null;
  begin
    update public.advice_transfer_quota_tokens set current_assignment_id=(
      select assignment_id from public.advice_transfer_assignments where study_id=previous and not is_test
        and quota_token_id is null limit 1) where id=standby.quota_token_id;
  exception when others then get stacked diagnostics error_message=message_text; end;
  if error_message is null then raise exception 'Cross-study quota assignment was allowed'; end if;

  -- Save and submit one actual allocated participant in every cell (100 exposures).
  for assignment in select distinct on(stimulus_id,condition) * from public.advice_transfer_assignments
    where study_id=cohort and not is_test and status='claimed' and reservation_kind='quota'
    order by stimulus_id,condition,id loop
    pid:=assignment.prolific_pid;
    claim:=public.claim_advice_transfer_assignment_revised(pid,cohort,'new',false,null,null);
    judgments:='[]'::jsonb;
    for j in 0..4 loop
      select (case when assignment.condition='human' then s.human_comments else s.ai_comments end)
        ->>(assignment.comment_order->>j)::integer into raw
        from public.advice_transfer_stimuli s where s.stimulus_id=assignment.stimulus_id;
      if claim->'comments'->>j<>public.advice_transfer_remove_leading_judgment_label(raw)
        or encode(extensions.digest(claim->'comments'->>j,'sha256'),'hex')<>claim->'commentHashes'->>j then
        raise exception 'Formal stimulus text/hash mismatch'; end if;
      selected:=case when public.advice_transfer_original_comment_label(raw)='YTA' then 'NTA' else 'YTA' end;
      perform public.record_advice_transfer_comment_label(assignment.assignment_id,pid,j+1,
        (assignment.comment_order->>j)::integer,assignment.presented_comment_sha256->>j,selected,'first-'||j);
      judgments:=judgments||jsonb_build_array(jsonb_build_object('displayPosition',j+1,
        'commentIndex',(assignment.comment_order->>j)::integer,'commentSha256',assignment.presented_comment_sha256->>j,'label',selected));
      checked:=checked+1;
    end loop;
    phase1:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','commentJudgments',judgments,
      'gistText',repeat('word ',25),'gistDifficulty',4,'perceptionQuestionsVersion','perception-questions-v2-reasons',
      'perceivedConsensus',0,'roomForDisagreement',100,
      'timings',jsonb_build_object('phase1ActiveTimeMs',12000,'gistActiveTimeMs',4000));
    result:=public.save_advice_transfer_stage_perception(assignment.assignment_id,pid,'phase1',phase1);
    again:=public.claim_advice_transfer_assignment_revised(pid,cohort,'new',false,null,null);
    if again->'comments'<>claim->'comments' or again->'phase1Snapshot'<>result->'phase1Snapshot' then
      raise exception 'Reload changed formal text or responses'; end if;
    phase2:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','adviceText',repeat('word ',77),
      'difficulty',4,'effort',null,'confidence',6,'timings',jsonb_build_object('adviceResponseTimeMs',16000));
    perform public.save_advice_transfer_stage_perception(assignment.assignment_id,pid,'phase2',phase2);
    payload:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','assignmentId',assignment.assignment_id,
      'participant',jsonb_build_object('prolificPid',pid,'studyId',cohort,'sessionId','new'),
      'purposeGuess','Synthetic launch check; all records rolled back.','commentsStoodOut','no',
      'commentsStoodOutDetails','','aiGeneratedBelief','unsure','aiLikelihood',4,
      'clientAudit',jsonb_build_object('labelFeedbackPresentationVersion','original-label-confirmation-v2'),
      'demographics',jsonb_build_object('genderIdentity','prefer-not-to-say','ageYears',35,
        'englishProficiency','no-fluent','educationLevel','graduate-or-professional-training','employmentStatus','self-employed'));
    perform public.submit_advice_transfer_payload(assignment.assignment_id,payload);
    again:=public.submit_advice_transfer_payload(assignment.assignment_id,payload);
    if not (again->>'alreadySubmitted')::boolean then raise exception 'Duplicate submission not deduplicated'; end if;
    select * into saved from public.advice_transfer_submissions where assignment_id=assignment.assignment_id;
    if saved.study_id<>cohort or saved.material_version<>'content-priority-v2-20260921'
      or saved.quota_disposition<>'quota' or saved.perceived_consensus<>0 or saved.room_for_disagreement<>100
      or saved.full_payload#>>'{clientAudit,labelFeedbackPresentationVersion}'<>'original-label-confirmation-v2' then
      raise exception 'Formal submission lost study, quota or response metadata'; end if;
  end loop;
  if checked<>100 or (select count(*) from public.advice_transfer_submissions where study_id=cohort and not is_test)<>20
    or exists(select 1 from public.advice_transfer_formal_cell_progress where pending<>1 or reserved<>9 or not quota_invariant_ok) then
    raise exception 'Post-submission balance failed'; end if;

  if (select md5(jsonb_agg(to_jsonb(s) order by id)::text) from public.advice_transfer_submissions s where study_id=previous and not is_test)
      is distinct from historical_submissions
    or (select md5(jsonb_agg(to_jsonb(a) order by id)::text) from public.advice_transfer_assignments a where study_id=previous and not is_test)
      is distinct from historical_assignments
    or (select md5(jsonb_agg(to_jsonb(q) order by id)::text) from public.advice_transfer_quota_tokens q where study_id=previous)
      is distinct from historical_tokens then raise exception 'Historical cohort was modified'; end if;
end; $test$;
rollback;
select 'PASS: 200 independent slots, 20 balanced cells, capacity cap, same-cell replacement, old-participant exclusion, 100 comment hashes, all-wrong-label continuation, saves, repeat submissions and historical-data preservation; synthetic records rolled back' as result;
