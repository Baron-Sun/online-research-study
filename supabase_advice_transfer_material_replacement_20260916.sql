-- Activate reviewed whole-post replacements. Keep original stimulus IDs and responses.
-- Prerequisite: deployed displayPostBody() cleanup for encoded blank lines.
-- For rehearsal, replace the final COMMIT with ROLLBACK.
begin;
set local lock_timeout = '5s';
select pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
lock table public.advice_transfer_stimuli, public.advice_transfer_assignments,
  public.advice_transfer_submissions, public.advice_transfer_quota_tokens,
  public.advice_transfer_settings in share row exclusive mode;

create temporary table replacement_before on commit drop as
select
  (select md5(coalesce(jsonb_agg(to_jsonb(t) order by id)::text,'[]')) from public.advice_transfer_assignments t) assignments_hash,
  (select md5(coalesce(jsonb_agg(to_jsonb(t) order by id)::text,'[]')) from public.advice_transfer_submissions t) submissions_hash,
  (select md5(jsonb_agg(to_jsonb(t) order by setting_key)::text) from public.advice_transfer_settings t) settings_hash,
  (select md5(jsonb_agg(to_jsonb(t) - array['pair_role','active','audit_metadata','updated_at'] order by pair_number)::text) from public.advice_transfer_stimuli t) text_hash;
create temporary table replacement_old_tokens on commit drop as
select * from public.advice_transfer_quota_tokens;

do $guard$
declare v_active integer[];
begin
  select array_agg(pair_number order by pair_number) into v_active
    from public.advice_transfer_stimuli where active and pair_role='primary';
  if v_active is distinct from array[1,2,3,4,5,6,7,8,9,10]
     and v_active is distinct from array[1,2,3,4,5,6,7,9,11,13] then
    raise exception 'Unexpected active material set: %', v_active;
  end if;
  if exists(select 1 from public.advice_transfer_assignments
    where not is_test and status='claimed' and lease_expires_at >= now()) then
    raise exception 'A formal participant is active; retry after completion';
  end if;
  if exists (
    select 1 from (values
      (8, '1f0131a34894ed584be84c2cbac7ef7304476736f5f48bbade51f2b18c364d31', '1a007a800f48ff1535b342455b418eb4', 'd983208f2bc6e33fc6e52cb263b0422d'),
      (10, '29e93aa8f291765ffa019cff30f1068ec1d49bfb678d02ce2fd41b4d9d6de068', 'c41a937df3c5e01384e4e96277c5d356', '077901d109a03272cac349c8dcf2cc06'),
      (11, '61c0881dbfb03ad0e3a1226cae70f3cd0192629596999ca27a3f59a34ef4def7', '94cb71c5f2ff79dd34c9c451cfb79117', '35e9d70a057af8555e597ee2de887c3b'),
      (13, '7673dbbd6eaa30ae105e4bf01273f2138fe4d59bd72d46f330a18453e0c5d8db', 'eb2f67ceb205d8cae389ec259ea4ece2', 'cfd5b9c0147218239b4044c9c6ee618c')
    ) expected(pair_number, body_sha, human_md5, ai_md5)
    left join public.advice_transfer_stimuli s using(pair_number)
    where s.exposure_post_body_sha256 is distinct from expected.body_sha
      or md5(s.human_comments::text) is distinct from expected.human_md5
      or md5(s.ai_comments::text) is distinct from expected.ai_md5
      or jsonb_array_length(s.human_comments) <> 5
      or jsonb_array_length(s.ai_comments) <> 5
  ) then raise exception 'Reviewed materials have changed'; end if;
end;
$guard$;

update public.advice_transfer_stimuli
set active = pair_number in (11,13),
    pair_role = case when pair_number in (11,13) then 'primary' else 'reserve' end,
    audit_metadata = audit_metadata || jsonb_build_object(
      'materialReplacement20260916', jsonb_build_object(
        'revision', '2026-09-16-reserve-replacement',
        'appliedAt', now(),
        'replacesPair', case when pair_number=11 then 10 when pair_number=13 then 8 end,
        'replacedByPair', case when pair_number=10 then 11 when pair_number=8 then 13 end,
        'rawTextUnchanged', true,
        'historicalResponsesRetained', true)),
    updated_at = now()
where pair_number in (8,10,11,13)
  and not (audit_metadata ? 'materialReplacement20260916');

select public.ensure_advice_transfer_quota_tokens();

do $verify$
begin
  if (select array_agg(pair_number order by pair_number) from public.advice_transfer_stimuli
       where active and pair_role='primary') is distinct from array[1,2,3,4,5,6,7,9,11,13] then
    raise exception 'Wrong active set after replacement';
  end if;
  if (select md5(coalesce(jsonb_agg(to_jsonb(t) order by id)::text,'[]')) from public.advice_transfer_assignments t)
      is distinct from (select assignments_hash from replacement_before)
    or (select md5(coalesce(jsonb_agg(to_jsonb(t) order by id)::text,'[]')) from public.advice_transfer_submissions t)
      is distinct from (select submissions_hash from replacement_before)
    or (select md5(jsonb_agg(to_jsonb(t) order by setting_key)::text) from public.advice_transfer_settings t)
      is distinct from (select settings_hash from replacement_before)
    or (select md5(jsonb_agg(to_jsonb(t) - array['pair_role','active','audit_metadata','updated_at'] order by pair_number)::text) from public.advice_transfer_stimuli t)
      is distinct from (select text_hash from replacement_before) then
    raise exception 'Historical records, recruitment settings, or raw materials changed';
  end if;
  if exists(select 1 from replacement_old_tokens old
    left join public.advice_transfer_quota_tokens current using(id)
    where to_jsonb(old) is distinct from to_jsonb(current)) then
    raise exception 'Historical quota tokens changed';
  end if;
  if (select count(*) from public.advice_transfer_formal_cell_progress) <> 20 then
    raise exception 'Expected 20 active post-condition cells';
  end if;
end;
$verify$;

select 'PASS: history, settings and raw text preserved' as verification,
       (select string_agg(pair_number::text, ',' order by pair_number)
          from public.advice_transfer_stimuli where active) as active_posts,
       (select count(*) from public.advice_transfer_assignments) as assignments,
       (select count(*) from public.advice_transfer_submissions) as submissions;
commit;
