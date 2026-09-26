-- New independent formal cohort. No historical records or materials are changed.
-- Run the rollback rehearsal first. This does not publish the Prolific study.
begin;
set local lock_timeout='5s';
set local statement_timeout='60s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
lock table public.advice_transfer_settings, public.advice_transfer_assignments,
  public.advice_transfer_submissions, public.advice_transfer_quota_tokens,
  public.advice_transfer_stimuli in share row exclusive mode;

do $guard$ begin
  if public.advice_transfer_active_study_id() is distinct from '6ab145947e9c974c2b6cf1cd'
    or (select setting_value from public.advice_transfer_settings where setting_key='formal_target_per_cell') is distinct from '10'::jsonb
    then raise exception 'Unexpected existing cohort or target'; end if;
  if exists(select 1 from public.advice_transfer_assignments where not is_test
    and status='claimed' and lease_expires_at>now()) then raise exception 'Formal participants are active'; end if;
  if exists(select 1 from public.advice_transfer_assignments where not is_test and study_id='6ab3fa4fe3086041cbc44a37')
    or exists(select 1 from public.advice_transfer_quota_tokens where study_id='6ab3fa4fe3086041cbc44a37')
    then raise exception 'New formal cohort is not empty'; end if;
  if (select count(*) from public.advice_transfer_submissions where not is_test)<>303
    or (select count(*) from public.advice_transfer_submissions where not is_test and study_id='6a9b2d61ae180a9b2920551b')<>102
    or (select count(*) from public.advice_transfer_submissions where not is_test and study_id='6ab145947e9c974c2b6cf1cd')<>201
    then raise exception 'Historical response counts changed'; end if;
  if (select jsonb_agg(pair_number order by pair_number) from public.advice_transfer_stimuli where active)
    is distinct from '[1,2,3,4,5,6,7,9,11,13]'::jsonb then raise exception 'Unexpected material selection'; end if;
  if to_regprocedure('public.claim_advice_transfer_assignment_ratings(text,text,text,boolean,integer,text)') is null
    then raise exception '0-100 protocol is missing'; end if;
end; $guard$;

create temporary table formal2000_before on commit drop as
select 'assignments' as kind, md5(coalesce(jsonb_agg(to_jsonb(a) order by id)::text,'')) as checksum from public.advice_transfer_assignments a
union all select 'submissions',md5(coalesce(jsonb_agg(to_jsonb(s) order by id)::text,'')) from public.advice_transfer_submissions s
union all select 'quotas',md5(coalesce(jsonb_agg(to_jsonb(q) order by id)::text,'')) from public.advice_transfer_quota_tokens q
union all select 'stimuli',md5(coalesce(jsonb_agg(to_jsonb(s) order by stimulus_id)::text,'')) from public.advice_transfer_stimuli s
union all select 'other_settings',md5(coalesce(jsonb_agg(to_jsonb(s) order by setting_key)::text,'')) from public.advice_transfer_settings s
  where setting_key not in ('formal_study_id','formal_target_per_cell','formal_recruitment_open');
alter table formal2000_before enable row level security;

update public.advice_transfer_settings set setting_value='false'::jsonb,updated_at=now()
  where setting_key='formal_recruitment_open';
update public.advice_transfer_settings set setting_value='"6ab3fa4fe3086041cbc44a37"'::jsonb,updated_at=now()
  where setting_key='formal_study_id';
update public.advice_transfer_settings set setting_value='100'::jsonb,updated_at=now()
  where setting_key='formal_target_per_cell';
select public.ensure_advice_transfer_quota_tokens();

do $verify$ begin
  if public.advice_transfer_active_study_id()<>'6ab3fa4fe3086041cbc44a37'
    or (select count(*) from public.advice_transfer_formal_cell_progress)<>20
    or (select sum(token_total) from public.advice_transfer_formal_cell_progress)<>2000
    or exists(select 1 from public.advice_transfer_formal_cell_progress where
      study_id<>'6ab3fa4fe3086041cbc44a37' or target_per_cell<>100 or available<>100
      or token_total<>100 or quota_committed<>0 or not quota_invariant_ok)
    then raise exception 'Expected 20 cells with exactly 100 empty slots each'; end if;
  if public.ensure_advice_transfer_quota_tokens()<>0 then raise exception 'Quota generation is not idempotent'; end if;
  if (select md5(coalesce(jsonb_agg(to_jsonb(a) order by id)::text,'')) from public.advice_transfer_assignments a)
       is distinct from (select checksum from formal2000_before where kind='assignments')
    or (select md5(coalesce(jsonb_agg(to_jsonb(s) order by id)::text,'')) from public.advice_transfer_submissions s)
       is distinct from (select checksum from formal2000_before where kind='submissions')
    or (select md5(coalesce(jsonb_agg(to_jsonb(q) order by id)::text,'')) from public.advice_transfer_quota_tokens q where study_id<>'6ab3fa4fe3086041cbc44a37')
       is distinct from (select checksum from formal2000_before where kind='quotas')
    or (select md5(coalesce(jsonb_agg(to_jsonb(s) order by stimulus_id)::text,'')) from public.advice_transfer_stimuli s)
       is distinct from (select checksum from formal2000_before where kind='stimuli')
    or (select md5(coalesce(jsonb_agg(to_jsonb(s) order by setting_key)::text,'')) from public.advice_transfer_settings s
         where setting_key not in ('formal_study_id','formal_target_per_cell','formal_recruitment_open'))
       is distinct from (select checksum from formal2000_before where kind='other_settings')
    then raise exception 'Historical data, materials or unrelated settings changed'; end if;
  if not (select relrowsecurity from pg_class where oid='public.advice_transfer_quota_tokens'::regclass)
    or has_table_privilege('anon','public.advice_transfer_quota_tokens','select')
    or has_table_privilege('anon','public.advice_transfer_formal_cell_progress','select')
    then raise exception 'Quota data must stay private'; end if;
end; $verify$;

-- Enables only this cohort's allocator; recruitment starts separately in Prolific.
update public.advice_transfer_settings set setting_value='true'::jsonb,updated_at=now()
  where setting_key='formal_recruitment_open';
commit;
