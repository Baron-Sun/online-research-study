-- New independent 200-person pilot; retain the historical cohort and quota ledger.
-- One-time migration. Run the accompanying rollback rehearsal before COMMIT.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
lock table public.advice_transfer_settings,public.advice_transfer_assignments,
  public.advice_transfer_submissions,public.advice_transfer_quota_tokens,
  public.advice_transfer_stimuli in share row exclusive mode;
do $guard$ begin
  if exists(select 1 from information_schema.columns where table_schema='public'
    and table_name='advice_transfer_quota_tokens' and column_name='study_id') then
    raise exception 'Pilot cohort migration is already installed'; end if;
  if exists(select 1 from public.advice_transfer_assignments where not is_test
    and status='claimed' and lease_expires_at>now()) then raise exception 'Formal participants are active'; end if;
  if exists(select 1 from public.advice_transfer_assignments where not is_test and study_id='6ab145947e9c974c2b6cf1cd') then
    raise exception 'The new pilot already has formal assignments'; end if;
  if (select count(*) from public.advice_transfer_submissions where not is_test)<>102
    or exists(select 1 from public.advice_transfer_submissions where not is_test and study_id<>'6a9b2d61ae180a9b2920551b') then
    raise exception 'Unexpected historical sample'; end if;
  if (select jsonb_agg(pair_number order by pair_number) from public.advice_transfer_stimuli where active)
    <> '[1,2,3,4,5,6,7,9,11,13]'::jsonb then raise exception 'Unexpected material selection'; end if;
end; $guard$;

create temporary table pilot200_before on commit drop as select
  (select md5(jsonb_agg(to_jsonb(a) order by id)::text) from public.advice_transfer_assignments a) assignments_md5,
  (select md5(jsonb_agg(to_jsonb(s) order by id)::text) from public.advice_transfer_submissions s) submissions_md5,
  (select md5(jsonb_agg(to_jsonb(q) order by id)::text) from public.advice_transfer_quota_tokens q) quotas_md5,
  (select md5(jsonb_agg(to_jsonb(s) order by stimulus_id)::text) from public.advice_transfer_stimuli s) stimuli_md5;
alter table pilot200_before enable row level security;

insert into public.advice_transfer_settings(setting_key,setting_value) values
  ('formal_study_id','"6ab145947e9c974c2b6cf1cd"'::jsonb)
on conflict(setting_key) do update set setting_value=excluded.setting_value,updated_at=now();

create or replace function public.advice_transfer_active_study_id()
returns text language sql stable security definer set search_path=public as $fn$
  select setting_value #>> '{}' from public.advice_transfer_settings where setting_key='formal_study_id'
$fn$;
revoke all on function public.advice_transfer_active_study_id() from public,anon,authenticated;
grant execute on function public.advice_transfer_active_study_id() to service_role;

alter table public.advice_transfer_quota_tokens add column study_id text not null default '6a9b2d61ae180a9b2920551b';
alter table public.advice_transfer_quota_tokens alter column study_id set default public.advice_transfer_active_study_id();
alter table public.advice_transfer_quota_tokens drop constraint advice_transfer_quota_tokens_stimulus_id_condition_slot_ind_key;
alter table public.advice_transfer_quota_tokens add constraint advice_transfer_quota_study_cell_slot_unique
  unique(study_id,stimulus_id,condition,slot_index);
create index advice_transfer_quota_study_state_idx on public.advice_transfer_quota_tokens
  (study_id,stimulus_id,condition,state,reservation_expires_at,slot_index);

create or replace function public.guard_advice_transfer_quota_study()
returns trigger language plpgsql security definer set search_path=public as $fn$
begin
  if tg_op='UPDATE' and new.study_id is distinct from old.study_id then
    raise exception 'A quota token cannot change study'; end if;
  if new.current_assignment_id is not null and not exists(select 1 from public.advice_transfer_assignments a
    where a.assignment_id=new.current_assignment_id and a.study_id=new.study_id
      and a.stimulus_id=new.stimulus_id and a.condition=new.condition and not a.is_test) then
    raise exception 'Quota token and participant must belong to the same study and cell'; end if;
  return new;
end; $fn$;
revoke all on function public.guard_advice_transfer_quota_study() from public,anon,authenticated;
create trigger advice_transfer_quota_study_guard before insert or update on public.advice_transfer_quota_tokens
  for each row execute function public.guard_advice_transfer_quota_study();

create or replace function public.guard_advice_transfer_assignment_quota_study()
returns trigger language plpgsql security definer set search_path=public as $fn$
begin
  if new.quota_token_id is not null and not exists(select 1 from public.advice_transfer_quota_tokens q
    where q.id=new.quota_token_id and q.study_id=new.study_id and q.stimulus_id=new.stimulus_id
      and q.condition=new.condition and not new.is_test) then
    raise exception 'Participant and quota token must belong to the same study and cell'; end if;
  return new;
end; $fn$;
revoke all on function public.guard_advice_transfer_assignment_quota_study() from public,anon,authenticated;
create trigger advice_transfer_assignment_quota_study_guard before insert or update of quota_token_id,study_id
  on public.advice_transfer_assignments for each row execute function public.guard_advice_transfer_assignment_quota_study();
do $patch$ declare fn oid := 'public.ensure_advice_transfer_quota_tokens()'::regprocedure; src text; definition text; begin
select prosrc,pg_get_functiondef(oid) into src,definition from pg_proc where oid=fn;
if md5(src)<>'ade65bc0084b0d9f666404f872c70b94' then raise exception 'Unexpected installed function: ensure_advice_transfer_quota_tokens'; end if;
if (length(definition)-length(replace(definition,'and token.slot_index <= v_target)','')))/length('and token.slot_index <= v_target)') <> 1 then raise exception 'Unexpected patch location in ensure_advice_transfer_quota_tokens'; end if;
definition:=replace(definition,'and token.slot_index <= v_target)','and token.slot_index <= v_target
         and token.study_id=public.advice_transfer_active_study_id())');
if (length(definition)-length(replace(definition,'on conflict (stimulus_id, condition, slot_index) do nothing;','')))/length('on conflict (stimulus_id, condition, slot_index) do nothing;') <> 1 then raise exception 'Unexpected patch location in ensure_advice_transfer_quota_tokens'; end if;
definition:=replace(definition,'on conflict (stimulus_id, condition, slot_index) do nothing;','on conflict (study_id, stimulus_id, condition, slot_index) do nothing;');
execute definition; end; $patch$;
do $patch$ declare fn oid := 'public.claim_advice_transfer_assignment(text,text,text,boolean,integer,text)'::regprocedure; src text; definition text; begin
select prosrc,pg_get_functiondef(oid) into src,definition from pg_proc where oid=fn;
if md5(src)<>'d0a7eaf632fa778b6e781187a5ef303b' then raise exception 'Unexpected installed function: claim_advice_transfer_assignment'; end if;
if (length(definition)-length(replace(definition,'  if not v_is_test and (p_pair_number is not null or p_condition is not null) then','')))/length('  if not v_is_test and (p_pair_number is not null or p_condition is not null) then') <> 1 then raise exception 'Unexpected patch location in claim_advice_transfer_assignment'; end if;
definition:=replace(definition,'  if not v_is_test and (p_pair_number is not null or p_condition is not null) then','  if not v_is_test and p_study_id is distinct from public.advice_transfer_active_study_id()
     and not exists(select 1 from public.advice_transfer_assignments where not is_test
       and prolific_pid=p_prolific_pid and study_id=p_study_id and status=''submitted'') then
    raise exception ''This study link is not open for recruitment. Return to Prolific and contact the researcher.'';
  end if;
  if not v_is_test and p_study_id=public.advice_transfer_active_study_id()
     and exists(select 1 from public.advice_transfer_submissions where not is_test
       and prolific_pid=p_prolific_pid and study_id is distinct from p_study_id) then
    raise exception ''You already completed an earlier version of this study. Please return this submission on Prolific.'';
  end if;
  if not v_is_test and (p_pair_number is not null or p_condition is not null) then');
if (length(definition)-length(replace(definition,'token.slot_index <= v_target_per_cell','')))/length('token.slot_index <= v_target_per_cell') <> 4 then raise exception 'Unexpected patch location in claim_advice_transfer_assignment'; end if;
definition:=replace(definition,'token.slot_index <= v_target_per_cell','token.slot_index <= v_target_per_cell and token.study_id=p_study_id');
if (length(definition)-length(replace(definition,'and standby.condition = token.condition','')))/length('and standby.condition = token.condition') <> 1 then raise exception 'Unexpected patch location in claim_advice_transfer_assignment'; end if;
definition:=replace(definition,'and standby.condition = token.condition','and standby.condition = token.condition
                and standby.study_id=token.study_id');
if (length(definition)-length(replace(definition,'and assignment.reservation_kind = ''standby''','')))/length('and assignment.reservation_kind = ''standby''') <> 1 then raise exception 'Unexpected patch location in claim_advice_transfer_assignment'; end if;
definition:=replace(definition,'and assignment.reservation_kind = ''standby''','and assignment.reservation_kind = ''standby''
             and assignment.study_id=p_study_id');
execute definition; end; $patch$;
do $patch$ declare fn oid := 'public.promote_advice_transfer_standby(text,text)'::regprocedure; src text; definition text; begin
select prosrc,pg_get_functiondef(oid) into src,definition from pg_proc where oid=fn;
if md5(src)<>'cfe9f73f465ec81b1a1bb8f8b884319e' then raise exception 'Unexpected installed function: promote_advice_transfer_standby'; end if;
if (length(definition)-length(replace(definition,'and token.slot_index <= v_target','')))/length('and token.slot_index <= v_target') <> 1 then raise exception 'Unexpected patch location in promote_advice_transfer_standby'; end if;
definition:=replace(definition,'and token.slot_index <= v_target','and token.slot_index <= v_target
       and token.study_id=public.advice_transfer_active_study_id()');
if (length(definition)-length(replace(definition,'and assignment.condition = p_condition','')))/length('and assignment.condition = p_condition') <> 1 then raise exception 'Unexpected patch location in promote_advice_transfer_standby'; end if;
definition:=replace(definition,'and assignment.condition = p_condition','and assignment.condition = p_condition
       and assignment.study_id=v_token.study_id');
execute definition; end; $patch$;
do $patch$ declare fn oid := 'public.guard_advice_transfer_target_reduction()'::regprocedure; src text; definition text; begin
select prosrc,pg_get_functiondef(oid) into src,definition from pg_proc where oid=fn;
if md5(src)<>'a2b10dd5b4be86829e1e92ce92b55231' then raise exception 'Unexpected installed function: guard_advice_transfer_target_reduction'; end if;
if (length(definition)-length(replace(definition,'where token.slot_index > v_new_target','')))/length('where token.slot_index > v_new_target') <> 1 then raise exception 'Unexpected patch location in guard_advice_transfer_target_reduction'; end if;
definition:=replace(definition,'where token.slot_index > v_new_target','where token.slot_index > v_new_target
       and token.study_id=public.advice_transfer_active_study_id()');
execute definition; end; $patch$;
create or replace view public.advice_transfer_formal_cell_progress as
with settings as (
  select coalesce(max(
           case when setting_key = 'formal_target_per_cell'
                then (setting_value #>> '{}')::integer end
         ), 0)::integer as target_per_cell
    from public.advice_transfer_settings
),
cells as (
  select stimulus.stimulus_id,
         stimulus.pair_number,
         stimulus.pair_role,
         conditions.condition
    from public.advice_transfer_stimuli stimulus
    cross join (values ('human'::text), ('ai'::text)) conditions(condition)
   where stimulus.active
     and stimulus.pair_role = 'primary'
),
token_counts as (
  select token.stimulus_id,
         token.condition,
         count(*)::integer as token_total,
         count(*) filter (where token.state = 'available')::integer as available,
         count(*) filter (where token.state = 'reserved')::integer as reserved,
         count(*) filter (where token.state = 'pending')::integer as pending,
         count(*) filter (where token.state = 'valid')::integer as valid
    from public.advice_transfer_quota_tokens token
   where token.study_id=public.advice_transfer_active_study_id()
   group by token.stimulus_id, token.condition
),
assignment_counts as (
  select assignment.stimulus_id,
         assignment.condition,
         count(*) filter (
           where assignment.status = 'claimed'
             and assignment.reservation_kind = 'standby'
             and assignment.lease_expires_at >= now()
         )::integer as active_standby,
         count(*) filter (where assignment.status = 'screened_out')::integer as screened_out,
         count(*) filter (where assignment.status = 'abandoned')::integer as abandoned
    from public.advice_transfer_assignments assignment
   where not assignment.is_test and assignment.study_id=public.advice_transfer_active_study_id()
   group by assignment.stimulus_id, assignment.condition
),
submission_counts as (
  select submission.stimulus_id,
         submission.condition,
         count(*) filter (
           where submission.quota_disposition = 'standby'
             and submission.validity_status in ('pending', 'valid')
         )::integer as submitted_standby,
         count(*) filter (where submission.validity_status = 'excluded')::integer as excluded
    from public.advice_transfer_submissions submission
   where not submission.is_test and submission.study_id=public.advice_transfer_active_study_id()
   group by submission.stimulus_id, submission.condition
)
select cell.pair_number,
       cell.pair_role,
       cell.stimulus_id,
       cell.condition,
       settings.target_per_cell,
       coalesce(tokens.token_total, 0) as token_total,
       coalesce(tokens.available, 0) as available,
       coalesce(tokens.reserved, 0) as reserved,
       coalesce(tokens.pending, 0) as pending,
       coalesce(tokens.valid, 0) as valid,
       coalesce(tokens.reserved, 0)
         + coalesce(tokens.pending, 0)
         + coalesce(tokens.valid, 0) as quota_committed,
       coalesce(assignments.active_standby, 0) as active_standby,
       coalesce(submissions.submitted_standby, 0) as submitted_standby,
       coalesce(submissions.excluded, 0) as excluded,
       coalesce(assignments.screened_out, 0) as screened_out,
       coalesce(assignments.abandoned, 0) as abandoned,
       coalesce(tokens.pending, 0) + coalesce(tokens.valid, 0) as usable_completed,
       greatest(
         settings.target_per_cell
           - coalesce(tokens.pending, 0)
           - coalesce(tokens.valid, 0),
         0
       ) as remaining,
       (
         coalesce(tokens.token_total, 0) = settings.target_per_cell
         and coalesce(tokens.available, 0)
           + coalesce(tokens.reserved, 0)
           + coalesce(tokens.pending, 0)
           + coalesce(tokens.valid, 0) = coalesce(tokens.token_total, 0)
         and coalesce(tokens.reserved, 0)
           + coalesce(tokens.pending, 0)
           + coalesce(tokens.valid, 0) <= settings.target_per_cell
       ) as quota_invariant_ok,
       public.advice_transfer_active_study_id() as study_id
  from cells cell
  cross join settings
  left join token_counts tokens
    on tokens.stimulus_id = cell.stimulus_id
   and tokens.condition = cell.condition
  left join assignment_counts assignments
    on assignments.stimulus_id = cell.stimulus_id
   and assignments.condition = cell.condition
  left join submission_counts submissions
    on submissions.stimulus_id = cell.stimulus_id
   and submissions.condition = cell.condition
 order by cell.pair_number, cell.condition;


update public.advice_transfer_settings set setting_value='10'::jsonb,updated_at=now()
  where setting_key='formal_target_per_cell';
select public.ensure_advice_transfer_quota_tokens();
-- The draft can be launched by the researcher after readiness checks pass.
-- This backend switch enables allocation; it does not publish or pay for Prolific recruitment.
update public.advice_transfer_settings set setting_value='true'::jsonb,updated_at=now()
  where setting_key='formal_recruitment_open';

do $verify$ begin
  if (select count(*) from public.advice_transfer_formal_cell_progress)<>20
    or (select sum(token_total) from public.advice_transfer_formal_cell_progress)<>200
    or exists(select 1 from public.advice_transfer_formal_cell_progress
      where target_per_cell<>10 or available<>10 or quota_committed<>0 or not quota_invariant_ok) then
    raise exception 'New pilot does not have exactly 200 unused balanced slots'; end if;
  if (select md5(jsonb_agg(to_jsonb(a) order by id)::text) from public.advice_transfer_assignments a)
       is distinct from (select assignments_md5 from pilot200_before)
    or (select md5(jsonb_agg(to_jsonb(s) order by id)::text) from public.advice_transfer_submissions s)
       is distinct from (select submissions_md5 from pilot200_before)
    or (select md5(jsonb_agg(to_jsonb(q)-'study_id' order by id)::text) from public.advice_transfer_quota_tokens q where study_id='6a9b2d61ae180a9b2920551b')
       is distinct from (select quotas_md5 from pilot200_before)
    or (select md5(jsonb_agg(to_jsonb(s) order by stimulus_id)::text) from public.advice_transfer_stimuli s)
       is distinct from (select stimuli_md5 from pilot200_before) then
    raise exception 'Historical data or stimuli changed'; end if;
  if not (select relrowsecurity from pg_class where oid='public.advice_transfer_quota_tokens'::regclass)
    or has_table_privilege('anon','public.advice_transfer_quota_tokens','select')
    or has_table_privilege('anon','public.advice_transfer_formal_cell_progress','select') then
    raise exception 'Quota data must stay private'; end if;
end; $verify$;
notify pgrst,'reload schema';
commit;
