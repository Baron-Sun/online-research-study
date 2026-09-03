-- Study 2 same-post design migration.
-- Existing A-to-B assignments remain unchanged. New assignments created by
-- claim_advice_transfer_assignment_same_post show the exposure post again in
-- Phase 2 and record that exposure post as the actual response target.
begin;

alter table public.advice_transfer_assignments
  add column if not exists design_variant text not null default 'a_to_b';

alter table public.advice_transfer_submissions
  add column if not exists design_variant text not null default 'a_to_b',
  add column if not exists response_post_id text,
  add column if not exists response_post_body_sha256 text;

update public.advice_transfer_submissions
   set response_post_id = coalesce(response_post_id, target_post_id),
       response_post_body_sha256 = coalesce(response_post_body_sha256, target_post_body_sha256)
 where response_post_id is null
    or response_post_body_sha256 is null;

alter table public.advice_transfer_submissions
  alter column response_post_id set not null,
  alter column response_post_body_sha256 set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.advice_transfer_assignments'::regclass
       and conname = 'advice_transfer_assignment_design_variant'
  ) then
    alter table public.advice_transfer_assignments
      add constraint advice_transfer_assignment_design_variant
      check (design_variant in ('a_to_b', 'same_post'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.advice_transfer_submissions'::regclass
       and conname = 'advice_transfer_submission_design_variant'
  ) then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submission_design_variant
      check (design_variant in ('a_to_b', 'same_post'));
  end if;

  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.advice_transfer_submissions'::regclass
       and conname = 'advice_transfer_response_post_hash_length'
  ) then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_response_post_hash_length
      check (length(response_post_body_sha256) = 64);
  end if;
end;
$$;

create or replace function public.claim_advice_transfer_assignment_same_post(
  p_prolific_pid text,
  p_study_id text default null,
  p_session_id text default null,
  p_is_test boolean default false,
  p_pair_number integer default null,
  p_condition text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing_id uuid;
  v_response jsonb;
  v_assignment public.advice_transfer_assignments%rowtype;
  v_pid text := nullif(trim(p_prolific_pid), '');
  v_study text := nullif(trim(p_study_id), '');
  v_session text := nullif(trim(p_session_id), '');
  v_is_test boolean := coalesce(v_pid ~* '^(test|preview|qa)[-_]', false);
  v_response_post jsonb;
begin
  -- Reuse the allocator's transaction lock so the identity check and the
  -- design stamp remain atomic even during a burst of first-page requests.
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));

  select id into v_existing_id
    from public.advice_transfer_assignments
   where prolific_pid = v_pid
     and coalesce(study_id, '') = coalesce(v_study, '')
     and (
       (v_is_test and coalesce(session_id, '') = coalesce(v_session, ''))
       or (not v_is_test and not is_test)
     )
   order by created_at desc
   limit 1;

  v_response := public.claim_advice_transfer_assignment_v4(
    p_prolific_pid, p_study_id, p_session_id,
    p_is_test, p_pair_number, p_condition
  );

  if v_response ->> 'admissionStatus' <> 'assigned' then
    return v_response;
  end if;

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = v_response ->> 'assignmentId'
   for update;

  if v_existing_id is null
     and v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    update public.advice_transfer_assignments
       set design_variant = 'same_post',
           updated_at = now()
     where id = v_assignment.id
     returning * into v_assignment;
  end if;

  v_response_post := case
    when v_assignment.design_variant = 'same_post'
      then v_response -> 'exposurePost'
    else v_response -> 'targetPost'
  end;

  return v_response || jsonb_build_object(
    'designVariant', v_assignment.design_variant,
    'responsePost', v_response_post
  );
end;
$$;

-- The final-submit RPC continues to preserve the selected A/B pair for audit.
-- This trigger adds the post that was actually shown for the response, so an
-- A-to-A response can never be misattributed to the unused B post.
create or replace function public.set_advice_transfer_response_post_audit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_design_variant text;
  v_server_audit jsonb;
begin
  select design_variant into v_design_variant
    from public.advice_transfer_assignments
   where assignment_id = new.assignment_id;

  if v_design_variant is null then
    raise exception 'Assignment design variant is missing';
  end if;

  new.design_variant := v_design_variant;
  if v_design_variant = 'same_post' then
    new.response_post_id := new.exposure_post_id;
    new.response_post_body_sha256 := new.exposure_post_body_sha256;
  else
    new.response_post_id := new.target_post_id;
    new.response_post_body_sha256 := new.target_post_body_sha256;
  end if;

  v_server_audit := case
    when jsonb_typeof(new.full_payload #> '{serverAudit}') = 'object'
      then new.full_payload -> 'serverAudit'
    else '{}'::jsonb
  end;

  new.full_payload := new.full_payload || jsonb_build_object(
    'designVariant', new.design_variant,
    'responsePostId', new.response_post_id,
    'responsePostSha256', new.response_post_body_sha256,
    'serverAudit', v_server_audit || jsonb_build_object(
      'designVariant', new.design_variant,
      'responsePostId', new.response_post_id,
      'responsePostSha256', new.response_post_body_sha256
    )
  );

  return new;
end;
$$;

drop trigger if exists advice_transfer_response_post_audit
  on public.advice_transfer_submissions;
create trigger advice_transfer_response_post_audit
before insert or update of assignment_id, exposure_post_id,
  exposure_post_body_sha256, target_post_id, target_post_body_sha256, full_payload
on public.advice_transfer_submissions
for each row execute function public.set_advice_transfer_response_post_audit();

revoke all on function public.claim_advice_transfer_assignment_same_post(
  text, text, text, boolean, integer, text
) from public;
grant execute on function public.claim_advice_transfer_assignment_same_post(
  text, text, text, boolean, integer, text
) to anon, authenticated;

revoke all on function public.set_advice_transfer_response_post_audit()
  from public;

grant select, insert, update, delete on public.advice_transfer_assignments
  to service_role;
grant select, insert, update, delete on public.advice_transfer_submissions
  to service_role;

notify pgrst, 'reload schema';
commit;
