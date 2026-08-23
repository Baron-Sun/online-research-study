-- Study 2 advice-transfer database. This namespace is intentionally separate
-- from the existing advice_* and source_detection_* studies.
begin;

create extension if not exists pgcrypto;

create table if not exists public.advice_transfer_settings (
  setting_key text primary key,
  setting_value jsonb not null,
  updated_at timestamptz not null default now()
);

-- These defaults are intentionally inert. Re-running this setup must never
-- reopen, close, or resize an in-progress formal study.
insert into public.advice_transfer_settings (setting_key, setting_value)
values
  ('formal_recruitment_open', 'false'::jsonb),
  ('formal_target_per_cell', '0'::jsonb),
  ('assignment_lease_minutes', '30'::jsonb)
on conflict (setting_key) do nothing;

create table if not exists public.advice_transfer_stimuli (
  stimulus_id text primary key,
  pair_number integer not null unique check (pair_number between 1 and 13),
  pair_role text not null check (pair_role in ('primary', 'reserve')),
  topic_cluster integer not null,
  exposure_post_id text not null unique,
  exposure_post_title text not null,
  exposure_post_body text not null,
  exposure_post_body_sha256 text not null check (length(exposure_post_body_sha256) = 64),
  target_post_id text not null unique,
  target_post_title text not null,
  target_post_body text not null,
  target_post_body_sha256 text not null check (length(target_post_body_sha256) = 64),
  human_comments jsonb not null
    check (jsonb_typeof(human_comments) = 'array' and jsonb_array_length(human_comments) = 5),
  human_comment_sha256 jsonb not null
    check (jsonb_typeof(human_comment_sha256) = 'array' and jsonb_array_length(human_comment_sha256) = 5),
  ai_comments jsonb not null
    check (jsonb_typeof(ai_comments) = 'array' and jsonb_array_length(ai_comments) = 5),
  ai_comment_sha256 jsonb not null
    check (jsonb_typeof(ai_comment_sha256) = 'array' and jsonb_array_length(ai_comment_sha256) = 5),
  audit_metadata jsonb not null default '{}'::jsonb,
  active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (exposure_post_id <> target_post_id),
  check ((pair_role = 'primary' and active) or (pair_role = 'reserve' and not active))
);

create table if not exists public.advice_transfer_assignments (
  id uuid primary key default gen_random_uuid(),
  assignment_id text not null unique,
  prolific_pid text not null,
  study_id text,
  session_id text,
  stimulus_id text not null references public.advice_transfer_stimuli(stimulus_id),
  pair_number integer not null check (pair_number between 1 and 13),
  condition text not null check (condition in ('human', 'ai')),
  comment_order jsonb not null
    check (jsonb_typeof(comment_order) = 'array' and jsonb_array_length(comment_order) = 5),
  presented_comment_sha256 jsonb not null
    check (jsonb_typeof(presented_comment_sha256) = 'array' and jsonb_array_length(presented_comment_sha256) = 5),
  is_test boolean not null,
  status text not null default 'claimed'
    check (status in ('claimed', 'submitted', 'screened_out', 'excluded', 'abandoned')),
  comprehension_failures integer not null default 0
    check (comprehension_failures between 0 and 2),
  comprehension_events jsonb not null default '[]'::jsonb
    check (jsonb_typeof(comprehension_events) = 'array'),
  claimed_at timestamptz not null default now(),
  last_heartbeat_at timestamptz,
  lease_expires_at timestamptz,
  draft_payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(draft_payload) = 'object'),
  draft_updated_at timestamptz,
  screened_out_at timestamptz,
  abandoned_at timestamptz,
  abandonment_reason text,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists advice_transfer_participant_session_unique
  on public.advice_transfer_assignments (
    prolific_pid,
    coalesce(study_id, ''),
    coalesce(session_id, '')
  );

create index if not exists advice_transfer_assignment_balance_idx
  on public.advice_transfer_assignments (is_test, status, pair_number, condition);

create table if not exists public.advice_transfer_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id text not null unique
    references public.advice_transfer_assignments(assignment_id),
  prolific_pid text not null,
  study_id text,
  session_id text,
  stimulus_id text not null references public.advice_transfer_stimuli(stimulus_id),
  pair_number integer not null,
  pair_role text not null,
  condition text not null check (condition in ('human', 'ai')),
  is_test boolean not null,
  comment_order jsonb not null,
  comment_sha256 jsonb not null,
  exposure_post_id text not null,
  exposure_post_body_sha256 text not null,
  target_post_id text not null,
  target_post_body_sha256 text not null,
  advice_text text not null,
  advice_word_count integer not null check (advice_word_count >= 50),
  advice_character_count integer not null check (advice_character_count >= 1),
  difficulty integer not null check (difficulty between 1 and 7),
  effort integer not null check (effort between 1 and 7),
  confidence integer not null check (confidence between 1 and 7),
  exposure_time_ms integer not null check (exposure_time_ms >= 0),
  advice_response_time_ms integer not null check (advice_response_time_ms >= 0),
  purpose_guess text not null,
  comments_stood_out text not null check (comments_stood_out in ('yes', 'no', 'unsure')),
  comments_stood_out_details text,
  ai_generated_belief text not null check (ai_generated_belief in ('yes', 'no', 'unsure')),
  ai_likelihood integer not null check (ai_likelihood between 1 and 7),
  full_payload jsonb not null,
  validity_status text not null default 'pending'
    check (validity_status in ('pending', 'valid', 'excluded')),
  reviewed_at timestamptz,
  exclusion_reason text,
  submitted_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Upgrade an existing preview database without deleting assignments or data.
alter table public.advice_transfer_assignments
  add column if not exists last_heartbeat_at timestamptz,
  add column if not exists lease_expires_at timestamptz,
  add column if not exists draft_payload jsonb not null default '{}'::jsonb,
  add column if not exists draft_updated_at timestamptz,
  add column if not exists abandoned_at timestamptz,
  add column if not exists abandonment_reason text;

alter table public.advice_transfer_submissions
  add column if not exists validity_status text not null default 'pending',
  add column if not exists reviewed_at timestamptz,
  add column if not exists exclusion_reason text;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'advice_transfer_assignments_draft_payload_object'
       and conrelid = 'public.advice_transfer_assignments'::regclass
  ) then
    alter table public.advice_transfer_assignments
      add constraint advice_transfer_assignments_draft_payload_object
      check (jsonb_typeof(draft_payload) = 'object');
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conname = 'advice_transfer_submissions_validity_status_check'
       and conrelid = 'public.advice_transfer_submissions'::regclass
  ) then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submissions_validity_status_check
      check (validity_status in ('pending', 'valid', 'excluded'));
  end if;
end;
$$;

create index if not exists advice_transfer_submission_analysis_idx
  on public.advice_transfer_submissions (is_test, pair_number, condition, submitted_at);

create index if not exists advice_transfer_assignment_lease_idx
  on public.advice_transfer_assignments (status, lease_expires_at)
  where status = 'claimed';

create index if not exists advice_transfer_submission_validity_idx
  on public.advice_transfer_submissions
    (is_test, validity_status, stimulus_id, condition);

create or replace function public.advice_transfer_word_count(p_text text)
returns integer
language sql
immutable
set search_path = public
as $$
  select count(*)::integer
    from regexp_matches(coalesce(p_text, ''), $re$[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*$re$, 'g');
$$;

create or replace function public.reclaim_expired_advice_transfer_assignments()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reclaimed integer := 0;
begin
  update public.advice_transfer_assignments
     set status = 'abandoned',
         abandoned_at = now(),
         abandonment_reason = 'lease_expired',
         updated_at = now()
   where status = 'claimed'
     and lease_expires_at is not null
     and lease_expires_at < now();

  get diagnostics v_reclaimed = row_count;
  return v_reclaimed;
end;
$$;

create or replace function public.claim_advice_transfer_assignment(
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
  v_assignment public.advice_transfer_assignments%rowtype;
  v_stimulus public.advice_transfer_stimuli%rowtype;
  v_stimulus_id text;
  v_is_test boolean;
  v_formal_open boolean := false;
  v_target_per_cell integer := 0;
  v_lease_minutes integer := 30;
  v_condition text;
  v_comment_order jsonb;
  v_source_comments jsonb;
  v_source_hashes jsonb;
  v_ordered_comments jsonb;
  v_ordered_hashes jsonb;
  v_now timestamptz := now();
begin
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  p_study_id := nullif(trim(p_study_id), '');
  p_session_id := nullif(trim(p_session_id), '');
  p_condition := nullif(lower(trim(p_condition)), '');

  if p_prolific_pid is null then
    raise exception 'Missing PROLIFIC_PID';
  end if;
  if p_pair_number is not null and (p_pair_number < 1 or p_pair_number > 13) then
    raise exception 'The requested test pair must be between 1 and 13';
  end if;
  if p_condition is not null and p_condition not in ('human', 'ai') then
    raise exception 'The requested test condition must be human or ai';
  end if;

  -- Test status is derived from the identifier, not trusted from the browser.
  v_is_test := p_prolific_pid ~* '^(test|preview|qa)[-_]';
  if coalesce(p_is_test, false) <> v_is_test then
    raise exception 'Participant identifier and test flag do not match';
  end if;
  if not v_is_test and (p_pair_number is not null or p_condition is not null) then
    raise exception 'Pair and condition overrides are available only for test identifiers';
  end if;

  select coalesce((setting_value #>> '{}')::boolean, false)
    into v_formal_open
    from public.advice_transfer_settings
   where setting_key = 'formal_recruitment_open';

  select coalesce((setting_value #>> '{}')::integer, 0)
    into v_target_per_cell
    from public.advice_transfer_settings
   where setting_key = 'formal_target_per_cell';

  select greatest(5, least(120, coalesce((setting_value #>> '{}')::integer, 30)))
    into v_lease_minutes
    from public.advice_transfer_settings
   where setting_key = 'assignment_lease_minutes';

  v_target_per_cell := coalesce(v_target_per_cell, 0);
  v_lease_minutes := coalesce(v_lease_minutes, 30);

  -- The lock makes the least-filled allocation deterministic under bursts.
  -- The critical section is short and no longer depends on a finite slot table.
  perform pg_advisory_xact_lock(hashtext('advice_transfer_assignment_v2'));
  perform public.reclaim_expired_advice_transfer_assignments();

  select *
    into v_assignment
    from public.advice_transfer_assignments
   where prolific_pid = p_prolific_pid
     and coalesce(study_id, '') = coalesce(p_study_id, '')
     and coalesce(session_id, '') = coalesce(p_session_id, '')
   order by created_at desc
   limit 1
   for update;

  if v_assignment.id is not null and v_assignment.status = 'abandoned' then
    if v_assignment.abandonment_reason = 'lease_expired' then
      update public.advice_transfer_assignments
         set status = 'claimed',
             last_heartbeat_at = v_now,
             lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
             abandoned_at = null,
             abandonment_reason = null,
             updated_at = v_now
       where id = v_assignment.id
       returning * into v_assignment;
    else
      raise exception 'This research session is no longer active';
    end if;
  elsif v_assignment.id is not null and v_assignment.status = 'excluded' then
    raise exception 'This research session is no longer active';
  elsif v_assignment.id is not null and v_assignment.status = 'claimed' then
    update public.advice_transfer_assignments
       set last_heartbeat_at = v_now,
           lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;
  end if;

  if v_assignment.id is null then
    if not v_is_test and not coalesce(v_formal_open, false) then
      raise exception 'Formal recruitment is not open yet';
    end if;

    if v_is_test then
      -- Select the least-filled eligible pair x condition cell. Screened-out,
      -- excluded and abandoned attempts do not occupy the cell.
      with conditions(condition) as (
        values ('human'::text), ('ai'::text)
      ),
      eligible_cells as (
        select stimulus.stimulus_id,
               stimulus.pair_number,
               conditions.condition
          from public.advice_transfer_stimuli stimulus
          cross join conditions
         where (
                 (p_pair_number is null and stimulus.active and stimulus.pair_role = 'primary')
                 or stimulus.pair_number = p_pair_number
               )
           and (p_condition is null or conditions.condition = p_condition)
      ),
      cell_counts as (
        select assignment.stimulus_id,
               assignment.condition,
               count(*) as occupied_count
          from public.advice_transfer_assignments assignment
         where assignment.is_test
           and assignment.status in ('claimed', 'submitted')
         group by assignment.stimulus_id, assignment.condition
      )
      select eligible.stimulus_id,
             eligible.condition
        into v_stimulus_id,
             v_condition
        from eligible_cells eligible
        left join cell_counts counts
          on counts.stimulus_id = eligible.stimulus_id
         and counts.condition = eligible.condition
       order by coalesce(counts.occupied_count, 0), random()
       limit 1;

      select * into v_stimulus
        from public.advice_transfer_stimuli
       where stimulus_id = v_stimulus_id;
    else
      if v_target_per_cell < 1 then
        raise exception 'Formal assignment targets have not been configured';
      end if;

      -- Formal capacity is defined by completed, non-excluded responses, not by
      -- the historical number of people who opened the study. Active leases are
      -- still used as a balancing signal so simultaneous entrants spread evenly.
      with conditions(condition) as (
        values ('human'::text), ('ai'::text)
      ),
      eligible_cells as (
        select stimulus.stimulus_id,
               stimulus.pair_number,
               conditions.condition
          from public.advice_transfer_stimuli stimulus
          cross join conditions
         where stimulus.active
           and stimulus.pair_role = 'primary'
      ),
      completion_counts as (
        select submission.stimulus_id,
               submission.condition,
               count(*)::integer as completed_count
          from public.advice_transfer_submissions submission
         where not submission.is_test
           and submission.validity_status in ('pending', 'valid')
         group by submission.stimulus_id, submission.condition
      ),
      active_counts as (
        select assignment.stimulus_id,
               assignment.condition,
               count(*)::integer as active_count
          from public.advice_transfer_assignments assignment
         where not assignment.is_test
           and assignment.status = 'claimed'
           and (
             assignment.lease_expires_at is null
             or assignment.lease_expires_at >= v_now
           )
         group by assignment.stimulus_id, assignment.condition
      )
      select cell.stimulus_id,
             cell.condition
        into v_stimulus_id,
             v_condition
        from eligible_cells cell
        left join completion_counts completed
          on completed.stimulus_id = cell.stimulus_id
         and completed.condition = cell.condition
        left join active_counts active
          on active.stimulus_id = cell.stimulus_id
         and active.condition = cell.condition
       where coalesce(completed.completed_count, 0) < v_target_per_cell
       order by coalesce(completed.completed_count, 0),
                coalesce(active.active_count, 0),
                random()
       limit 1;

      if v_stimulus_id is null then
        raise exception 'The formal study has reached its configured response quota';
      end if;

      select * into v_stimulus
        from public.advice_transfer_stimuli
       where stimulus_id = v_stimulus_id;
    end if;

    if v_stimulus.stimulus_id is null or v_condition is null then
      raise exception 'No eligible advice-transfer cell was available';
    end if;

    select jsonb_agg(comment_index order by random())
      into v_comment_order
      from generate_series(0, 4) indexes(comment_index);

    v_source_hashes := case
      when v_condition = 'human' then v_stimulus.human_comment_sha256
      else v_stimulus.ai_comment_sha256
    end;

    select jsonb_agg(v_source_hashes -> ordered.comment_index order by ordered.position)
      into v_ordered_hashes
      from (
        select value::integer as comment_index, ordinality as position
          from jsonb_array_elements_text(v_comment_order) with ordinality
      ) ordered;

    insert into public.advice_transfer_assignments (
      assignment_id,
      prolific_pid,
      study_id,
      session_id,
      stimulus_id,
      pair_number,
      condition,
      comment_order,
      presented_comment_sha256,
      is_test,
      last_heartbeat_at,
      lease_expires_at
    ) values (
      'at-' || replace(gen_random_uuid()::text, '-', ''),
      p_prolific_pid,
      p_study_id,
      p_session_id,
      v_stimulus.stimulus_id,
      v_stimulus.pair_number,
      v_condition,
      v_comment_order,
      v_ordered_hashes,
      v_is_test,
      v_now,
      v_now + make_interval(mins => v_lease_minutes)
    )
    returning * into v_assignment;
  else
    select * into v_stimulus
      from public.advice_transfer_stimuli
     where stimulus_id = v_assignment.stimulus_id;
    v_condition := v_assignment.condition;
  end if;

  if v_stimulus.stimulus_id is null then
    select * into v_stimulus
      from public.advice_transfer_stimuli
     where stimulus_id = v_assignment.stimulus_id;
  end if;

  v_source_comments := case
    when v_assignment.condition = 'human' then v_stimulus.human_comments
    else v_stimulus.ai_comments
  end;
  v_source_hashes := case
    when v_assignment.condition = 'human' then v_stimulus.human_comment_sha256
    else v_stimulus.ai_comment_sha256
  end;

  select jsonb_agg(v_source_comments -> ordered.comment_index order by ordered.position),
         jsonb_agg(v_source_hashes -> ordered.comment_index order by ordered.position)
    into v_ordered_comments,
         v_ordered_hashes
    from (
      select value::integer as comment_index, ordinality as position
        from jsonb_array_elements_text(v_assignment.comment_order) with ordinality
    ) ordered;

  -- Neither condition nor model names are returned to the participant client.
  return jsonb_build_object(
    'assignmentId', v_assignment.assignment_id,
    'status', v_assignment.status,
    'isTest', v_assignment.is_test,
    'pairNumber', v_stimulus.pair_number,
    'pairRole', v_stimulus.pair_role,
    'exposurePost', jsonb_build_object(
      'postId', v_stimulus.exposure_post_id,
      'title', v_stimulus.exposure_post_title,
      'body', v_stimulus.exposure_post_body,
      'sha256', v_stimulus.exposure_post_body_sha256
    ),
    'targetPost', jsonb_build_object(
      'postId', v_stimulus.target_post_id,
      'title', v_stimulus.target_post_title,
      'body', v_stimulus.target_post_body,
      'sha256', v_stimulus.target_post_body_sha256
    ),
    'comments', v_ordered_comments,
    'commentHashes', v_ordered_hashes,
    'commentOrder', v_assignment.comment_order,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'draftPayload', coalesce(v_assignment.draft_payload, '{}'::jsonb),
    'draftUpdatedAt', v_assignment.draft_updated_at,
    'claimedAt', v_assignment.claimed_at,
    'leaseExpiresAt', v_assignment.lease_expires_at,
    'screenedOutAt', v_assignment.screened_out_at,
    'submittedAt', v_assignment.submitted_at,
    'serverTime', v_now
  );
end;
$$;

create or replace function public.heartbeat_advice_transfer_assignment(
  p_assignment_id text,
  p_prolific_pid text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_lease_minutes integer := 30;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  if p_assignment_id is null or p_prolific_pid is null then
    raise exception 'Missing assignment or participant identifier';
  end if;

  select greatest(5, least(120, coalesce((setting_value #>> '{}')::integer, 30)))
    into v_lease_minutes
    from public.advice_transfer_settings
   where setting_key = 'assignment_lease_minutes';
  v_lease_minutes := coalesce(v_lease_minutes, 30);

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
     and prolific_pid = p_prolific_pid
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;

  if v_assignment.status = 'abandoned'
     and v_assignment.abandonment_reason = 'lease_expired' then
    update public.advice_transfer_assignments
       set status = 'claimed',
           last_heartbeat_at = v_now,
           lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
           abandoned_at = null,
           abandonment_reason = null,
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;
  elsif v_assignment.status = 'claimed' then
    update public.advice_transfer_assignments
       set last_heartbeat_at = v_now,
           lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', v_assignment.status,
    'active', v_assignment.status = 'claimed',
    'leaseExpiresAt', v_assignment.lease_expires_at,
    'serverTime', v_now
  );
end;
$$;

create or replace function public.save_advice_transfer_draft(
  p_assignment_id text,
  p_prolific_pid text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_lease_minutes integer := 30;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  if p_assignment_id is null or p_prolific_pid is null then
    raise exception 'Missing assignment or participant identifier';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Draft payload must be a JSON object';
  end if;
  if octet_length(p_payload::text) > 200000 then
    raise exception 'Draft payload is too large';
  end if;

  select greatest(5, least(120, coalesce((setting_value #>> '{}')::integer, 30)))
    into v_lease_minutes
    from public.advice_transfer_settings
   where setting_key = 'assignment_lease_minutes';
  v_lease_minutes := coalesce(v_lease_minutes, 30);

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
     and prolific_pid = p_prolific_pid
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.status = 'submitted' then
    return jsonb_build_object(
      'ok', true,
      'status', 'submitted',
      'savedAt', v_assignment.submitted_at,
      'alreadySubmitted', true
    );
  end if;
  if v_assignment.status in ('screened_out', 'excluded')
     or (v_assignment.status = 'abandoned'
         and v_assignment.abandonment_reason is distinct from 'lease_expired') then
    raise exception 'This assignment is no longer active';
  end if;

  update public.advice_transfer_assignments
     set status = 'claimed',
         draft_payload = p_payload,
         draft_updated_at = v_now,
         last_heartbeat_at = v_now,
         lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
         abandoned_at = null,
         abandonment_reason = null,
         updated_at = v_now
   where id = v_assignment.id;

  return jsonb_build_object(
    'ok', true,
    'status', 'claimed',
    'savedAt', v_now,
    'leaseExpiresAt', v_now + make_interval(mins => v_lease_minutes),
    'alreadySubmitted', false
  );
end;
$$;

create or replace function public.withdraw_advice_transfer_assignment(
  p_assignment_id text,
  p_prolific_pid text,
  p_reason text default 'participant_withdrew'
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  p_reason := lower(coalesce(nullif(trim(p_reason), ''), 'participant_withdrew'));
  if p_assignment_id is null or p_prolific_pid is null then
    raise exception 'Missing assignment or participant identifier';
  end if;
  if p_reason not in ('consent_declined', 'participant_withdrew') then
    raise exception 'Invalid withdrawal reason';
  end if;

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
     and prolific_pid = p_prolific_pid
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.status = 'submitted' then
    return jsonb_build_object('ok', true, 'status', 'submitted');
  end if;
  if v_assignment.status = 'claimed'
     or (v_assignment.status = 'abandoned'
         and v_assignment.abandonment_reason = 'lease_expired') then
    update public.advice_transfer_assignments
       set status = 'abandoned',
           lease_expires_at = null,
           abandoned_at = v_now,
           abandonment_reason = p_reason,
           updated_at = v_now
     where id = v_assignment.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', 'abandoned',
    'releasedAt', v_now
  );
end;
$$;

create or replace function public.record_advice_transfer_comprehension_failure(
  p_assignment_id text,
  p_selected_option text default null,
  p_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_failures integer;
  v_status text;
  v_lease_minutes integer := 30;
  v_now timestamptz := now();
begin
  select greatest(5, least(120, coalesce((setting_value #>> '{}')::integer, 30)))
    into v_lease_minutes
    from public.advice_transfer_settings
   where setting_key = 'assignment_lease_minutes';
  v_lease_minutes := coalesce(v_lease_minutes, 30);

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.status = 'submitted' then
    return jsonb_build_object(
      'status', v_assignment.status,
      'comprehensionFailures', v_assignment.comprehension_failures,
      'screenedOut', false
    );
  end if;
  if v_assignment.status = 'screened_out' then
    return jsonb_build_object(
      'status', v_assignment.status,
      'comprehensionFailures', v_assignment.comprehension_failures,
      'screenedOut', true
    );
  end if;
  if v_assignment.status = 'abandoned'
     and v_assignment.abandonment_reason = 'lease_expired' then
    update public.advice_transfer_assignments
       set status = 'claimed',
           abandoned_at = null,
           abandonment_reason = null
     where id = v_assignment.id;
    v_assignment.status := 'claimed';
  end if;
  if v_assignment.status <> 'claimed' then
    raise exception 'This assignment is no longer active';
  end if;

  v_failures := least(2, v_assignment.comprehension_failures + 1);
  v_status := case when v_failures >= 2 then 'screened_out' else 'claimed' end;

  update public.advice_transfer_assignments
     set comprehension_failures = v_failures,
         comprehension_events = comprehension_events || jsonb_build_array(
           jsonb_build_object(
             'selectedOption', nullif(trim(p_selected_option), ''),
             'occurredAt', v_now,
             'payload', coalesce(p_payload, '{}'::jsonb)
           )
         ),
         status = v_status,
         screened_out_at = case when v_status = 'screened_out' then v_now else screened_out_at end,
         last_heartbeat_at = v_now,
         lease_expires_at = case
           when v_status = 'screened_out' then null
           else v_now + make_interval(mins => v_lease_minutes)
         end,
         updated_at = v_now
   where assignment_id = p_assignment_id;

  return jsonb_build_object(
    'status', v_status,
    'comprehensionFailures', v_failures,
    'screenedOut', v_status = 'screened_out'
  );
end;
$$;

create or replace function public.submit_advice_transfer_payload(
  p_assignment_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_stimulus public.advice_transfer_stimuli%rowtype;
  v_existing public.advice_transfer_submissions%rowtype;
  v_advice text;
  v_word_count integer;
  v_character_count integer;
  v_difficulty integer;
  v_effort integer;
  v_confidence integer;
  v_exposure_time integer;
  v_advice_time integer;
  v_purpose text;
  v_stood_out text;
  v_stood_out_details text;
  v_ai_belief text;
  v_ai_likelihood integer;
  v_now timestamptz := now();
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Submission payload must be a JSON object';
  end if;

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.status = 'screened_out' then
    raise exception 'This session ended after two incorrect attention-check answers';
  end if;
  if v_assignment.status not in ('claimed', 'submitted')
     and not (
       v_assignment.status = 'abandoned'
       and v_assignment.abandonment_reason = 'lease_expired'
     ) then
    raise exception 'This assignment is no longer active';
  end if;

  if nullif(trim(p_payload #>> '{participant,prolificPid}'), '')
       is distinct from v_assignment.prolific_pid then
    raise exception 'Participant does not match assignment';
  end if;

  select * into v_existing
    from public.advice_transfer_submissions
   where assignment_id = p_assignment_id;
  if v_existing.id is not null then
    return jsonb_build_object(
      'ok', true,
      'status', 'submitted',
      'submittedAt', v_existing.submitted_at,
      'alreadySubmitted', true
    );
  end if;

  select * into v_stimulus
    from public.advice_transfer_stimuli
   where stimulus_id = v_assignment.stimulus_id;

  v_advice := trim(coalesce(p_payload ->> 'adviceText', ''));
  v_word_count := public.advice_transfer_word_count(v_advice);
  v_character_count := char_length(v_advice);
  v_difficulty := nullif(p_payload ->> 'difficulty', '')::integer;
  v_effort := nullif(p_payload ->> 'effort', '')::integer;
  v_confidence := nullif(p_payload ->> 'confidence', '')::integer;
  v_exposure_time := coalesce(nullif(p_payload #>> '{timings,exposureTimeMs}', '')::integer, 0);
  v_advice_time := coalesce(nullif(p_payload #>> '{timings,adviceResponseTimeMs}', '')::integer, 0);
  v_purpose := trim(coalesce(p_payload ->> 'purposeGuess', ''));
  v_stood_out := lower(trim(coalesce(p_payload ->> 'commentsStoodOut', '')));
  v_stood_out_details := nullif(trim(coalesce(p_payload ->> 'commentsStoodOutDetails', '')), '');
  v_ai_belief := lower(trim(coalesce(p_payload ->> 'aiGeneratedBelief', '')));
  v_ai_likelihood := nullif(p_payload ->> 'aiLikelihood', '')::integer;

  if v_word_count < 50 then
    raise exception 'Advice must contain at least 50 English words';
  end if;
  if v_difficulty not between 1 and 7
     or v_effort not between 1 and 7
     or v_confidence not between 1 and 7 then
    raise exception 'Difficulty, effort and confidence must each be between 1 and 7';
  end if;
  if v_purpose = '' then
    raise exception 'The study-purpose response is required';
  end if;
  if v_stood_out not in ('yes', 'no', 'unsure') then
    raise exception 'The comment-notice response is required';
  end if;
  if v_ai_belief not in ('yes', 'no', 'unsure') or v_ai_likelihood not between 1 and 7 then
    raise exception 'The AI-source responses are required';
  end if;

  insert into public.advice_transfer_submissions (
    assignment_id,
    prolific_pid,
    study_id,
    session_id,
    stimulus_id,
    pair_number,
    pair_role,
    condition,
    is_test,
    comment_order,
    comment_sha256,
    exposure_post_id,
    exposure_post_body_sha256,
    target_post_id,
    target_post_body_sha256,
    advice_text,
    advice_word_count,
    advice_character_count,
    difficulty,
    effort,
    confidence,
    exposure_time_ms,
    advice_response_time_ms,
    purpose_guess,
    comments_stood_out,
    comments_stood_out_details,
    ai_generated_belief,
    ai_likelihood,
    full_payload,
    submitted_at
  ) values (
    v_assignment.assignment_id,
    v_assignment.prolific_pid,
    v_assignment.study_id,
    v_assignment.session_id,
    v_assignment.stimulus_id,
    v_assignment.pair_number,
    v_stimulus.pair_role,
    v_assignment.condition,
    v_assignment.is_test,
    v_assignment.comment_order,
    v_assignment.presented_comment_sha256,
    v_stimulus.exposure_post_id,
    v_stimulus.exposure_post_body_sha256,
    v_stimulus.target_post_id,
    v_stimulus.target_post_body_sha256,
    v_advice,
    v_word_count,
    v_character_count,
    v_difficulty,
    v_effort,
    v_confidence,
    v_exposure_time,
    v_advice_time,
    v_purpose,
    v_stood_out,
    v_stood_out_details,
    v_ai_belief,
    v_ai_likelihood,
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
      'serverAudit', jsonb_build_object(
        'schemaVersion', 'advice-transfer-v2-resilient',
        'stimulusId', v_assignment.stimulus_id,
        'pairNumber', v_assignment.pair_number,
        'pairRole', v_stimulus.pair_role,
        'condition', v_assignment.condition,
        'isTest', v_assignment.is_test,
        'commentOrder', v_assignment.comment_order,
        'commentHashes', v_assignment.presented_comment_sha256,
        'exposurePostId', v_stimulus.exposure_post_id,
        'exposurePostSha256', v_stimulus.exposure_post_body_sha256,
        'targetPostId', v_stimulus.target_post_id,
        'targetPostSha256', v_stimulus.target_post_body_sha256,
        'serverReceivedAt', v_now
      )
    ),
    v_now
  );

  update public.advice_transfer_assignments
     set status = 'submitted',
         submitted_at = v_now,
         last_heartbeat_at = v_now,
         lease_expires_at = null,
         draft_payload = '{}'::jsonb,
         draft_updated_at = null,
         abandoned_at = null,
         abandonment_reason = null,
         updated_at = v_now
   where assignment_id = p_assignment_id;

  return jsonb_build_object(
    'ok', true,
    'status', 'submitted',
    'submittedAt', v_now,
    'alreadySubmitted', false
  );
end;
$$;

create or replace function public.review_advice_transfer_assignment(
  p_assignment_id text,
  p_decision text,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_decision := lower(nullif(trim(p_decision), ''));
  p_reason := nullif(trim(p_reason), '');

  if p_assignment_id is null then
    raise exception 'Missing assignment id';
  end if;
  if p_decision is null or p_decision not in ('valid', 'excluded', 'abandoned') then
    raise exception 'Decision must be valid, excluded, or abandoned';
  end if;

  perform pg_advisory_xact_lock(hashtext('advice_transfer_assignment_v2'));
  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.is_test then
    raise exception 'Test assignments do not occupy formal quotas';
  end if;

  if p_decision = 'valid' then
    if v_assignment.status <> 'submitted' or not exists (
      select 1
        from public.advice_transfer_submissions
       where assignment_id = p_assignment_id
    ) then
      raise exception 'Only a submitted response can be marked valid';
    end if;

    update public.advice_transfer_submissions
       set validity_status = 'valid',
           reviewed_at = v_now,
           exclusion_reason = null
     where assignment_id = p_assignment_id;
  elsif p_decision = 'excluded' then
    update public.advice_transfer_submissions
       set validity_status = 'excluded',
           reviewed_at = v_now,
           exclusion_reason = p_reason
     where assignment_id = p_assignment_id;

    update public.advice_transfer_assignments
       set status = 'excluded',
           lease_expires_at = null,
           abandoned_at = null,
           abandonment_reason = p_reason,
           updated_at = v_now
     where assignment_id = p_assignment_id;
  else
    if v_assignment.status = 'submitted' then
      raise exception 'A submitted response must be marked valid or excluded';
    end if;

    update public.advice_transfer_assignments
       set status = 'abandoned',
           lease_expires_at = null,
           abandoned_at = v_now,
           abandonment_reason = coalesce(p_reason, 'researcher_released'),
           updated_at = v_now
     where assignment_id = p_assignment_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'assignmentId', p_assignment_id,
    'decision', p_decision,
    'quotaReopened', p_decision in ('excluded', 'abandoned'),
    'reviewedAt', v_now
  );
end;
$$;

create or replace view public.advice_transfer_test_cell_progress as
select stimulus.pair_number,
       stimulus.pair_role,
       conditions.condition,
       count(assignment.id) filter (where assignment.status in ('claimed', 'submitted')) as occupied,
       count(assignment.id) filter (where assignment.status = 'submitted') as completed,
       count(assignment.id) filter (where assignment.status = 'screened_out') as screened_out
  from public.advice_transfer_stimuli stimulus
  cross join (values ('human'::text), ('ai'::text)) conditions(condition)
  left join public.advice_transfer_assignments assignment
    on assignment.stimulus_id = stimulus.stimulus_id
   and assignment.condition = conditions.condition
   and assignment.is_test
 group by stimulus.pair_number, stimulus.pair_role, conditions.condition;

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
assignment_counts as (
  select assignment.stimulus_id,
         assignment.condition,
         count(*) filter (
           where assignment.status = 'claimed'
             and (assignment.lease_expires_at is null
                  or assignment.lease_expires_at >= now())
         )::integer as active_leases,
         count(*) filter (
           where assignment.status = 'claimed'
             and assignment.lease_expires_at < now()
         )::integer as stale_leases,
         count(*) filter (where assignment.status = 'screened_out')::integer as screened_out,
         count(*) filter (where assignment.status = 'abandoned')::integer as abandoned
    from public.advice_transfer_assignments assignment
   where not assignment.is_test
   group by assignment.stimulus_id, assignment.condition
),
submission_counts as (
  select submission.stimulus_id,
         submission.condition,
         count(*) filter (where submission.validity_status = 'pending')::integer as pending,
         count(*) filter (where submission.validity_status = 'valid')::integer as valid,
         count(*) filter (where submission.validity_status = 'excluded')::integer as excluded
    from public.advice_transfer_submissions submission
   where not submission.is_test
   group by submission.stimulus_id, submission.condition
)
select cell.pair_number,
       cell.pair_role,
       cell.stimulus_id,
       cell.condition,
       settings.target_per_cell,
       coalesce(assignments.active_leases, 0) as active_leases,
       coalesce(assignments.stale_leases, 0) as stale_leases,
       coalesce(submissions.pending, 0) as pending,
       coalesce(submissions.valid, 0) as valid,
       coalesce(submissions.excluded, 0) as excluded,
       coalesce(assignments.screened_out, 0) as screened_out,
       coalesce(assignments.abandoned, 0) as abandoned,
       coalesce(submissions.pending, 0) + coalesce(submissions.valid, 0) as usable_completed,
       greatest(
         settings.target_per_cell
           - coalesce(submissions.pending, 0)
           - coalesce(submissions.valid, 0),
         0
       ) as remaining
  from cells cell
  cross join settings
  left join assignment_counts assignments
    on assignments.stimulus_id = cell.stimulus_id
   and assignments.condition = cell.condition
  left join submission_counts submissions
    on submissions.stimulus_id = cell.stimulus_id
   and submissions.condition = cell.condition
 order by cell.pair_number, cell.condition;

alter table public.advice_transfer_settings enable row level security;
alter table public.advice_transfer_stimuli enable row level security;
alter table public.advice_transfer_assignments enable row level security;
alter table public.advice_transfer_submissions enable row level security;

revoke all on public.advice_transfer_settings from anon, authenticated;
revoke all on public.advice_transfer_stimuli from anon, authenticated;
revoke all on public.advice_transfer_assignments from anon, authenticated;
revoke all on public.advice_transfer_submissions from anon, authenticated;
revoke all on public.advice_transfer_test_cell_progress from anon, authenticated;
revoke all on public.advice_transfer_formal_cell_progress from anon, authenticated;

revoke all on function public.claim_advice_transfer_assignment(text, text, text, boolean, integer, text)
  from public;
revoke all on function public.heartbeat_advice_transfer_assignment(text, text)
  from public;
revoke all on function public.save_advice_transfer_draft(text, text, jsonb)
  from public;
revoke all on function public.withdraw_advice_transfer_assignment(text, text, text)
  from public;
revoke all on function public.record_advice_transfer_comprehension_failure(text, text, jsonb)
  from public;
revoke all on function public.submit_advice_transfer_payload(text, jsonb)
  from public;
revoke all on function public.reclaim_expired_advice_transfer_assignments()
  from public;
revoke all on function public.review_advice_transfer_assignment(text, text, text)
  from public;
revoke all on function public.advice_transfer_word_count(text)
  from public;

grant execute on function public.claim_advice_transfer_assignment(text, text, text, boolean, integer, text)
  to anon, authenticated;
grant execute on function public.heartbeat_advice_transfer_assignment(text, text)
  to anon, authenticated;
grant execute on function public.save_advice_transfer_draft(text, text, jsonb)
  to anon, authenticated;
grant execute on function public.withdraw_advice_transfer_assignment(text, text, text)
  to anon, authenticated;
grant execute on function public.record_advice_transfer_comprehension_failure(text, text, jsonb)
  to anon, authenticated;
grant execute on function public.submit_advice_transfer_payload(text, jsonb)
  to anon, authenticated;

grant select, insert, update, delete on public.advice_transfer_settings to service_role;
grant select, insert, update, delete on public.advice_transfer_stimuli to service_role;
grant select, insert, update, delete on public.advice_transfer_assignments to service_role;
grant select, insert, update, delete on public.advice_transfer_submissions to service_role;
grant select on public.advice_transfer_test_cell_progress to service_role;
grant select on public.advice_transfer_formal_cell_progress to service_role;
grant execute on function public.advice_transfer_word_count(text) to service_role;
grant execute on function public.reclaim_expired_advice_transfer_assignments() to service_role;
grant execute on function public.review_advice_transfer_assignment(text, text, text) to service_role;

commit;
