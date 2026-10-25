-- Additive attention check; preserves all prompts, assignments and existing response records.
begin;
alter table public.original100_participants add column if not exists attention_attempts integer not null default 0;
alter table public.original100_participants add column if not exists attention_passed_at timestamptz;
create unique index if not exists original100_attention_event_once
 on public.original100_events(participant_id,(detail->>'event_id')) where action='attention_check';
create or replace function public.original100_session(
 p_action text, p_pid text, p_study_id text, p_session_id text,
 p_token text, p_preview boolean, p_payload jsonb default '{}'
) returns jsonb language plpgsql security definer set search_path=public,extensions,pg_temp as $$
declare
 cfg public.original100_settings%rowtype;
 person public.original100_participants%rowtype;
 response public.original100_responses%rowtype;
 study_mode text := case when p_preview then 'preview' else 'formal' end;
 selected_slot text; token_digest text; pos integer; answer_text text; result jsonb;
 check_event text; check_choice text; previous_check jsonb;
begin
 if p_preview is null or p_pid is null or p_token is null or p_study_id is null or p_session_id is null
   or length(p_pid)>100 or length(p_study_id)>100 or length(p_session_id)>100
   or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Invalid session details.'; end if;
 if (p_preview and p_pid !~ '^(preview|test|qa)-[A-Za-z0-9_-]+$')
   or (not p_preview and (p_pid !~ '^[a-f0-9]{24}$' or p_session_id !~ '^[a-f0-9]{24}$'))
   then raise exception 'Please open the study using your Prolific link.'; end if;
 if p_action is null or p_action not in ('claim','resume','save','navigate','complete','withdraw','attention_check') then raise exception 'Unknown action.'; end if;
 token_digest := encode(digest(p_token,'sha256'),'hex');
 -- One lock order for every action; protects claim/release/complete against each other.
 perform pg_advisory_xact_lock(10020261024);
 select * into cfg from public.original100_settings where id;
 select * into person from public.original100_participants
   where mode=study_mode and prolific_pid=p_pid for update;
 if person.id is null then
   if p_action<>'claim' then raise exception 'No saved session found.'; end if;
   if not coalesce((p_payload->>'consent')::boolean,false) then raise exception 'Consent is required.'; end if;
   if not p_preview and (not cfg.recruitment_open or not cfg.consent_approved
     or cfg.study_id='' or p_study_id<>cfg.study_id or cfg.completion_code='')
     then raise exception 'This study is not open for recruitment yet.'; end if;
   if p_preview then
     selected_slot:=coalesce(p_payload->>'slot','S001');
     if not exists(select 1 from public.original100_slots where slot_id=selected_slot) then raise exception 'Unknown preview slot.'; end if;
   else
     select s.slot_id into selected_slot from public.original100_slots s
       where not exists(select 1 from public.original100_participants p where p.slot_id=s.slot_id
         and p.mode='formal' and p.status in ('active','completed')) order by s.slot_id limit 1;
   end if;
   if selected_slot is null then raise exception 'All study places are currently assigned. Please contact the researcher.'; end if;
   if (select count(*) from public.original100_plan where slot_id=selected_slot)<>3 then raise exception 'The study material is incomplete.'; end if;
   insert into public.original100_participants(mode,prolific_pid,study_id,session_id,token_hash,slot_id,consent_version)
     values(study_mode,p_pid,p_study_id,p_session_id,token_digest,selected_slot,cfg.consent_version) returning * into person;
   insert into public.original100_responses(participant_id,position,stimulus_id)
     select person.id,position,stimulus_id from public.original100_plan where slot_id=selected_slot;
   insert into public.original100_events(participant_id,action) values(person.id,'consent_and_claim');
 end if;
 if person.token_hash<>token_digest or person.study_id<>p_study_id or person.session_id<>p_session_id
   then raise exception 'This participant already has a session. Reopen the original browser and study link.'; end if;
 if person.status in ('withdrawn','excluded') then raise exception 'This session has ended. Please contact the researcher.'; end if;
 if p_action in ('save','navigate','withdraw') and person.status<>'active' then raise exception 'Your submitted responses are locked.'; end if;
 if p_action in ('save','navigate','complete') and person.status='active' and person.attention_passed_at is null
   then raise exception 'Please complete the attention check before beginning the posts.'; end if;
 if p_action='attention_check' then
   check_event:=p_payload->>'event_id'; check_choice:=p_payload->>'choice';
   if check_event is null or check_event !~ '^[a-f0-9-]{36}$' or check_choice is null or check_choice not in ('green','blue','yellow')
     or p_payload->>'version' is distinct from 'attention-v1-blue' then raise exception 'Invalid attention-check response.'; end if;
   select detail into previous_check from public.original100_events where participant_id=person.id and action='attention_check' and detail->>'event_id'=check_event;
   if previous_check is not null then
     if previous_check->>'choice'<>check_choice then raise exception 'This check response was already recorded.'; end if;
   elsif person.attention_passed_at is null and person.status='active' then
     insert into public.original100_events(participant_id,action,detail) values(person.id,'attention_check',
       jsonb_build_object('event_id',check_event,'choice',check_choice,'correct',check_choice='blue','version','attention-v1-blue'));
     update public.original100_participants set attention_attempts=attention_attempts+1,
       attention_passed_at=case when check_choice='blue' then now() else null end,updated_at=now() where id=person.id;
   end if;
 elsif p_action='save' then
   pos:=(p_payload->>'position')::integer; answer_text:=p_payload->>'answer';
   if pos is null or pos not between 1 and 3 or answer_text is null or octet_length(answer_text)>250000 then raise exception 'Invalid response.'; end if;
   select * into response from public.original100_responses where participant_id=person.id and position=pos for update;
   if response.revision is distinct from (p_payload->>'revision')::integer and response.answer<>answer_text
     then raise exception 'A newer response was saved in another tab. Reload before editing.'; end if;
   if response.answer<>answer_text then
     update public.original100_responses set answer=answer_text,revision=revision+1,updated_at=now()
       where participant_id=person.id and position=pos;
   end if;
   update public.original100_participants set updated_at=now() where id=person.id;
 elsif p_action='navigate' then
   pos:=(p_payload->>'position')::integer;
   if pos is null or pos not between 1 and 4 then raise exception 'Invalid page.'; end if;
   if pos>1 and exists(select 1 from public.original100_responses where participant_id=person.id
      and position<pos and not public.original100_valid_answer(answer)) then raise exception 'Please complete each earlier comment before continuing.'; end if;
   update public.original100_participants set current_position=pos,updated_at=now() where id=person.id;
 elsif p_action='complete' and person.status='active' then
   if (select count(*) from public.original100_responses where participant_id=person.id and public.original100_valid_answer(answer))<>3
     then raise exception 'Please finish all three comments before submitting.'; end if;
   if (select jsonb_agg(revision order by position) from public.original100_responses where participant_id=person.id)
      is distinct from p_payload->'revisions' then raise exception 'Your answers changed in another tab. Reload and review them before submitting.'; end if;
   update public.original100_participants set status='completed',completed_at=now(),updated_at=now(),current_position=4 where id=person.id;
   insert into public.original100_events(participant_id,action) values(person.id,'complete');
 elsif p_action='withdraw' then
   update public.original100_participants set status='withdrawn',release_reason='participant_withdrawal',updated_at=now() where id=person.id;
   insert into public.original100_events(participant_id,action) values(person.id,'withdraw');
   return jsonb_build_object('status','withdrawn');
 end if;
 select jsonb_build_object('id',p.id,'mode',p.mode,'slot',p.slot_id,'status',p.status,
   'position',p.current_position,'completedAt',p.completed_at,'version',cfg.version,
   'attentionCheck',jsonb_build_object('version','attention-v1-blue','attempts',p.attention_attempts,'passed',p.attention_passed_at is not null),
   'completionCode',case when p.mode='formal' and p.status='completed' then cfg.completion_code else null end,
   'posts',(select jsonb_agg(jsonb_build_object('position',r.position,'stimulusId',r.stimulus_id,
     'prompt',s.prompt_text,'sha256',s.prompt_sha256,'answer',r.answer,'revision',r.revision) order by r.position)
      from public.original100_responses r join public.original100_posts s using(stimulus_id) where r.participant_id=p.id))
 into result from public.original100_participants p where p.id=person.id;
 return result;
end $$;


notify pgrst,'reload schema';
commit;
