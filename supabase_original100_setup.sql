-- Isolated Original-prompt study. No existing study tables or functions are changed.
begin;
create table if not exists public.original100_settings (
  id boolean primary key default true check(id),
  version text not null default 'original100-20261024-v1',
  recruitment_open boolean not null default false,
  study_id text not null default '',
  completion_code text not null default '',
  consent_approved boolean not null default false,
  consent_version text not null default 'original100-preview-v1'
);
insert into public.original100_settings(id) values(true) on conflict do nothing;
create table if not exists public.original100_posts (
  stimulus_id text primary key,
  submission_id text unique not null,
  prompt_text text not null,
  prompt_sha256 text not null check(length(prompt_sha256)=64)
);
create table if not exists public.original100_slots (slot_id text primary key);
create table if not exists public.original100_plan (
  slot_id text references public.original100_slots,
  position integer check(position between 1 and 3),
  stimulus_id text not null references public.original100_posts,
  primary key(slot_id,position), unique(slot_id,stimulus_id)
);
create table if not exists public.original100_participants (
  id uuid primary key default gen_random_uuid(),
  mode text not null check(mode in ('preview','formal')),
  prolific_pid text not null,
  study_id text not null,
  session_id text not null,
  token_hash text not null,
  slot_id text not null references public.original100_slots,
  status text not null default 'active' check(status in ('active','completed','withdrawn','excluded')),
  consent_version text not null,
  consented_at timestamptz not null default now(),
  current_position integer not null default 1 check(current_position between 1 and 4),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  release_reason text,
  unique(mode,prolific_pid)
);
create unique index if not exists original100_one_person_per_slot
  on public.original100_participants(slot_id)
  where mode='formal' and status in ('active','completed');
create table if not exists public.original100_responses (
  participant_id uuid references public.original100_participants,
  position integer check(position between 1 and 3),
  stimulus_id text not null references public.original100_posts,
  answer text not null default '' check(octet_length(answer)<=250000),
  revision integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key(participant_id,position), unique(participant_id,stimulus_id)
);
create table if not exists public.original100_events (
  id bigint generated always as identity primary key,
  participant_id uuid references public.original100_participants,
  action text not null,
  detail jsonb not null default '{}',
  created_at timestamptz not null default now()
);
alter table public.original100_settings enable row level security;
alter table public.original100_posts enable row level security;
alter table public.original100_slots enable row level security;
alter table public.original100_plan enable row level security;
alter table public.original100_participants enable row level security;
alter table public.original100_responses enable row level security;
alter table public.original100_events enable row level security;
revoke all on public.original100_settings, public.original100_posts, public.original100_slots,
 public.original100_plan, public.original100_participants, public.original100_responses,
 public.original100_events from anon, authenticated;

create or replace function public.original100_valid_answer(a text) returns boolean
language sql immutable set search_path=public,pg_temp as $$
 select coalesce(btrim(split_part(replace(a,E'\r\n',E'\n'),E'\n',1)) in ('YTA','NTA','ESH','NAH','INFO')
   and strpos(a,E'\n')>0 and length(btrim(substring(a from strpos(a,E'\n')+1), E' \t\r\n'))>0,false);
$$;

-- All participant operations use a scoped capability token, never a supplied row ID.
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
begin
 if p_preview is null or p_pid is null or p_token is null or p_study_id is null or p_session_id is null
   or length(p_pid)>100 or length(p_study_id)>100 or length(p_session_id)>100
   or p_token !~ '^[a-f0-9]{64}$' then raise exception 'Invalid session details.'; end if;
 if (p_preview and p_pid !~ '^(preview|test|qa)-[A-Za-z0-9_-]+$')
   or (not p_preview and (p_pid !~ '^[a-f0-9]{24}$' or p_session_id !~ '^[a-f0-9]{24}$'))
   then raise exception 'Please open the study using your Prolific link.'; end if;
 if p_action not in ('claim','resume','save','navigate','complete','withdraw') then raise exception 'Unknown action.'; end if;
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
 if p_action='save' then
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
   'completionCode',case when p.mode='formal' and p.status='completed' then cfg.completion_code else null end,
   'posts',(select jsonb_agg(jsonb_build_object('position',r.position,'stimulusId',r.stimulus_id,
     'prompt',s.prompt_text,'sha256',s.prompt_sha256,'answer',r.answer,'revision',r.revision) order by r.position)
      from public.original100_responses r join public.original100_posts s using(stimulus_id) where r.participant_id=p.id))
 into result from public.original100_participants p where p.id=person.id;
 return result;
end $$;

-- Researcher-only release: retained raw answers are excluded from final coverage.
create or replace function public.original100_release(p_participant_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
begin
 if length(btrim(coalesce(p_reason,'')))<3 then raise exception 'A release reason is required.'; end if;
 perform pg_advisory_xact_lock(10020261024);
 update public.original100_participants set status='excluded',release_reason=p_reason,updated_at=now() where id=p_participant_id;
 if not found then raise exception 'Unknown participant.'; end if;
 insert into public.original100_events(participant_id,action,detail) values(p_participant_id,'researcher_release',jsonb_build_object('reason',p_reason));
end $$;
create or replace view public.original100_completed_comments as
 select p.id as participant_id,p.prolific_pid,p.study_id,p.session_id,p.slot_id,r.position,r.stimulus_id,
   s.submission_id,s.prompt_sha256,r.answer as comment,p.completed_at
 from public.original100_participants p join public.original100_responses r on r.participant_id=p.id
 join public.original100_posts s using(stimulus_id) where p.mode='formal' and p.status='completed';
revoke all on public.original100_completed_comments from anon,authenticated;
revoke all on function public.original100_valid_answer(text) from public,anon,authenticated;
revoke all on function public.original100_session(text,text,text,text,text,boolean,jsonb) from public;
grant execute on function public.original100_session(text,text,text,text,text,boolean,jsonb) to anon,authenticated;
revoke all on function public.original100_release(uuid,text) from public,anon,authenticated;
grant execute on function public.original100_release(uuid,text) to service_role;
grant select on public.original100_completed_comments to service_role;
notify pgrst,'reload schema';
commit;
