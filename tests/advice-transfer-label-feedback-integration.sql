-- Run after the additive migration. Every synthetic QA change is rolled back.
begin;
set local statement_timeout = '45s';
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
do $test$
declare
  prefix text := 'qa-label-sql-' || gen_random_uuid()::text;
  pid text; claim jsonb; again jsonb; result jsonb; rec jsonb; original text;
  wrong text; selected text; raw text; judgments jsonb; phase1 jsonb; phase2 jsonb;
  final_payload jsonb; event text; err text; position integer; case_row record;
  formal_before bigint; submissions_before bigint; settings_before jsonb; stimuli_before text;
  assignment public.advice_transfer_assignments%rowtype;
  submission public.advice_transfer_submissions%rowtype;
begin
  select count(*) into formal_before from public.advice_transfer_assignments where not is_test;
  select count(*) into submissions_before from public.advice_transfer_submissions where not is_test;
  select jsonb_object_agg(setting_key,setting_value) into settings_before from public.advice_transfer_settings;
  select md5(jsonb_agg(to_jsonb(s) order by stimulus_id)::text) into stimuli_before from public.advice_transfer_stimuli s;
  -- Existing assignments do not switch protocol, even if they resume through the new RPC.
  claim := public.claim_advice_transfer_assignment_same_post(prefix||'-old','label-qa','old',true,11,'human');
  again := public.claim_advice_transfer_assignment_label_feedback(prefix||'-old','label-qa','old',true,11,'human');
  if again->>'assignmentId' is distinct from claim->>'assignmentId'
    or again->>'labelFeedbackVersion' is distinct from 'none' then
    raise exception 'Existing assignment changed feedback protocol';
  end if;
  -- Check the exact displayed order and original prefix for all 100 active comments.
  for case_row in select s.pair_number,c.condition from public.advice_transfer_stimuli s
    cross join (values ('human'),('ai')) c(condition) where s.active order by s.pair_number,c.condition loop
    pid := prefix||'-'||case_row.pair_number||'-'||case_row.condition;
    claim := public.claim_advice_transfer_assignment_label_feedback(pid,'label-qa','new',true,case_row.pair_number,case_row.condition);
    if claim->>'labelFeedbackVersion' is distinct from 'original-label-v1'
      or claim->'commentLabelFeedback' is distinct from '[]'::jsonb
      or claim ? 'condition' or claim ? 'originalLabels' then raise exception 'Invalid new assignment'; end if;
    select * into assignment from public.advice_transfer_assignments where assignment_id=claim->>'assignmentId';
    judgments := '[]'::jsonb;
    for position in 1..5 loop
      select (case when case_row.condition='human' then s.human_comments else s.ai_comments end)
        ->>((assignment.comment_order->>(position-1))::integer) into raw
        from public.advice_transfer_stimuli s where s.stimulus_id=assignment.stimulus_id;
      original := public.advice_transfer_original_comment_label(raw);
      wrong := case when original='YTA' then 'NTA' else 'YTA' end;
      selected := case when position in (1,5) then wrong else original end;
      event := position::text||'-first';
      if position=1 then
        err:=null;
        begin
          perform public.record_advice_transfer_comment_label(assignment.assignment_id,pid,position,
            (assignment.comment_order->>0)::integer,repeat('0',64),selected,'bad-hash');
        exception when others then get stacked diagnostics err=message_text; end;
        if err is null or err !~ 'assigned comment' then raise exception 'Incorrect hash accepted: %',err; end if;
        err:=null;
        begin
          perform public.record_advice_transfer_comment_label(assignment.assignment_id,pid||'-wrong',position,
            (assignment.comment_order->>0)::integer,assignment.presented_comment_sha256->>0,selected,'bad-pid');
        exception when others then get stacked diagnostics err=message_text; end;
        if err is null or err !~ 'Assignment not found' then raise exception 'Incorrect participant accepted: %',err; end if;
      end if;
      result := public.record_advice_transfer_comment_label(assignment.assignment_id,pid,position,
        (assignment.comment_order->>(position-1))::integer,assignment.presented_comment_sha256->>(position-1),selected,event);
      select value into rec from jsonb_array_elements(result->'commentLabelFeedback') where (value->>'displayPosition')::integer=position;
      if rec->>'originalLabel' is distinct from original or rec->>'firstLabel' is distinct from selected
        or (rec->>'feedbackOffered')::boolean is distinct from (selected<>original) then
        raise exception 'Original label, first answer, or feedback flag is incorrect'; end if;
      again := public.record_advice_transfer_comment_label(assignment.assignment_id,pid,position,
        (assignment.comment_order->>(position-1))::integer,assignment.presented_comment_sha256->>(position-1),selected,event);
      if not (again->>'alreadyRecorded')::boolean or again->'commentLabelFeedback' is distinct from result->'commentLabelFeedback'
        then raise exception 'Retry changed the saved first answer'; end if;
      if position=1 then
        result := public.record_advice_transfer_comment_label(assignment.assignment_id,pid,position,
          (assignment.comment_order->>0)::integer,assignment.presented_comment_sha256->>0,original,'1-corrected');
        rec := result->'commentLabelFeedback'->0;
        if rec->>'firstLabel' is distinct from wrong or rec->>'finalLabel' is distinct from original
          or not (rec->>'feedbackOffered')::boolean or (rec->>'selectionCount')::integer<>2 then
          raise exception 'Correction erased the initial choice or feedback'; end if;
        selected:=original;
      end if;
      judgments := judgments || jsonb_build_array(jsonb_build_object('displayPosition',position,
        'commentIndex',(assignment.comment_order->>(position-1))::integer,
        'commentSha256',assignment.presented_comment_sha256->>(position-1),'label',selected));
    end loop;
    again:=public.claim_advice_transfer_assignment_label_feedback(pid,'label-qa','new',true,case_row.pair_number,case_row.condition);
    if again->'commentLabelFeedback' is distinct from result->'commentLabelFeedback' then raise exception 'Reload lost feedback'; end if;
    phase1:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','commentJudgments',judgments,
      'gistText',repeat('word ',25),'gistDifficulty',4,'timings',jsonb_build_object('phase1ActiveTimeMs',12000,'gistActiveTimeMs',4000));
    wrong:=case when judgments->0->>'label'='YTA' then 'NTA' else 'YTA' end;
    err:=null;
    begin
      perform public.save_advice_transfer_stage(assignment.assignment_id,pid,'phase1',jsonb_set(phase1,'{commentJudgments,0,label}',to_jsonb(wrong)));
    exception when others then get stacked diagnostics err=message_text; end;
    if err is null or err !~ 'saved selection' then raise exception 'Unsaved choice accepted: %',err; end if;
    result:=public.save_advice_transfer_stage(assignment.assignment_id,pid,'phase1',phase1);
    if result#>>'{phase1Snapshot,labelFeedbackVersion}' is distinct from 'original-label-v1'
      or jsonb_array_length(result#>'{phase1Snapshot,commentLabelEvents}')<>6 then
      raise exception 'Locked stage lost the feedback audit'; end if;
    err:=null;
    begin
      perform public.record_advice_transfer_comment_label(assignment.assignment_id,pid,5,
        (assignment.comment_order->>4)::integer,assignment.presented_comment_sha256->>4,original,'after-lock');
    exception when others then get stacked diagnostics err=message_text; end;
    if err is null or err !~ 'locked' then raise exception 'Locked choices were editable: %',err; end if;
    -- A deliberately mismatched fifth answer remains eligible. No accuracy screening.
    phase2:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','adviceText',repeat('word ',77),
      'difficulty',4,'effort',null,'confidence',6,'timings',jsonb_build_object('adviceResponseTimeMs',16000));
    perform public.save_advice_transfer_stage(assignment.assignment_id,pid,'phase2',phase2);
    final_payload:=jsonb_build_object('schemaVersion','advice-transfer-v4-gist','assignmentId',assignment.assignment_id,
      'participant',jsonb_build_object('prolificPid',pid,'studyId','label-qa','sessionId','new'),
      'purposeGuess','A synthetic rollback-only acceptance test.','commentsStoodOut','no','commentsStoodOutDetails','',
      'aiGeneratedBelief','unsure','aiLikelihood',4,'demographics',jsonb_build_object('genderIdentity','prefer-not-to-say',
      'ageYears',35,'englishProficiency','no-fluent','educationLevel','graduate-or-professional-training','employmentStatus','self-employed'));
    perform public.submit_advice_transfer_payload(assignment.assignment_id,final_payload);
    select * into submission from public.advice_transfer_submissions where assignment_id=claim->>'assignmentId';
    if submission.label_feedback_version<>'original-label-v1' or jsonb_array_length(submission.comment_label_events)<>6
      or jsonb_array_length(submission.comment_label_feedback)<>5
      or submission.full_payload#>>'{serverAudit,labelFeedbackVersion}'<>'original-label-v1' then
      raise exception 'Submission lost the feedback audit'; end if;
  end loop;
  if (select count(*) from public.advice_transfer_assignments where not is_test)<>formal_before
    or (select count(*) from public.advice_transfer_submissions where not is_test)<>submissions_before
    or (select jsonb_object_agg(setting_key,setting_value) from public.advice_transfer_settings) is distinct from settings_before
    or (select md5(jsonb_agg(to_jsonb(s) order by stimulus_id)::text) from public.advice_transfer_stimuli s) is distinct from stimuli_before then
    raise exception 'Formal counts, recruitment settings, or stimuli changed'; end if;
end; $test$;
rollback;
select 'PASS: 100 comment mappings, retry, first/final choices, legacy assignments, stage locks and final submission; QA changes rolled back' as result;
