-- Study 2 advice-transfer database, resilient admission-control + v4 gist version.
-- This namespace is intentionally separate from the existing advice_* and
-- source_detection_* studies.
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
  ('assignment_lease_minutes', '5'::jsonb),
  ('departure_grace_seconds', '90'::jsonb),
  ('waitlist_ttl_seconds', '180'::jsonb),
  ('admission_poll_seconds', '3'::jsonb),
  ('standby_after_seconds', '90'::jsonb)
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
  design_variant text not null default 'a_to_b'
    check (design_variant in ('a_to_b', 'same_post')),
  post_task_measure text not null default 'effort'
    check (post_task_measure in ('effort', 'opinion_difficulty')),
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
  disconnect_noted_at timestamptz,
  reservation_kind text not null default 'test'
    check (reservation_kind in ('test', 'quota', 'standby', 'released', 'overflow')),
  standby_enqueued_at timestamptz,
  draft_payload jsonb not null default '{}'::jsonb
    check (jsonb_typeof(draft_payload) = 'object'),
  draft_updated_at timestamptz,
  screened_out_at timestamptz,
  abandoned_at timestamptz,
  abandonment_reason text,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (post_task_measure = 'effort' or design_variant = 'same_post')
);

-- Formal entrants wait here only while all exact cell reservations are in use.
-- Waiting never consumes a pair x condition quota. Rows are refreshed by the
-- browser and expire quickly when a participant closes the page.
create table if not exists public.advice_transfer_waitlist (
  id uuid primary key default gen_random_uuid(),
  waiter_id text not null unique,
  prolific_pid text not null,
  study_id text not null default '',
  session_id text not null default '',
  enqueued_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (prolific_pid, study_id)
);

create index if not exists advice_transfer_waitlist_order_idx
  on public.advice_transfer_waitlist (expires_at, enqueued_at, id);

-- Every formal observation is represented by one reusable token. The number
-- of tokens in a cell is the hard upper bound for quota-bearing observations.
create table if not exists public.advice_transfer_quota_tokens (
  id uuid primary key default gen_random_uuid(),
  stimulus_id text not null references public.advice_transfer_stimuli(stimulus_id),
  pair_number integer not null check (pair_number between 1 and 13),
  condition text not null check (condition in ('human', 'ai')),
  slot_index integer not null check (slot_index >= 1),
  state text not null default 'available'
    check (state in ('available', 'reserved', 'pending', 'valid')),
  current_assignment_id text unique
    references public.advice_transfer_assignments(assignment_id),
  reservation_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (stimulus_id, condition, slot_index),
  check (
    (state = 'available' and current_assignment_id is null and reservation_expires_at is null)
    or (state = 'reserved' and current_assignment_id is not null and reservation_expires_at is not null)
    or (state in ('pending', 'valid') and current_assignment_id is not null and reservation_expires_at is null)
  )
);

alter table public.advice_transfer_assignments
  add column if not exists quota_token_id uuid
    references public.advice_transfer_quota_tokens(id);

create index if not exists advice_transfer_quota_token_state_idx
  on public.advice_transfer_quota_tokens
    (stimulus_id, condition, state, reservation_expires_at, slot_index);

create unique index if not exists advice_transfer_assignment_quota_token_unique
  on public.advice_transfer_assignments (quota_token_id)
  where quota_token_id is not null;

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
  design_variant text not null default 'a_to_b'
    check (design_variant in ('a_to_b', 'same_post')),
  post_task_measure text not null default 'effort'
    check (post_task_measure in ('effort', 'opinion_difficulty')),
  is_test boolean not null,
  comment_order jsonb not null,
  comment_sha256 jsonb not null,
  exposure_post_id text not null,
  exposure_post_body_sha256 text not null,
  target_post_id text not null,
  target_post_body_sha256 text not null,
  response_post_id text,
  response_post_body_sha256 text,
  advice_text text not null,
  advice_word_count integer not null check (advice_word_count >= 77),
  advice_character_count integer not null check (advice_character_count >= 1),
  difficulty integer check (difficulty between 1 and 7),
  effort integer check (effort between 1 and 7),
  confidence integer not null check (confidence between 1 and 7),
  exposure_time_ms integer not null check (exposure_time_ms >= 0),
  advice_response_time_ms integer not null check (advice_response_time_ms >= 0),
  purpose_guess text not null,
  comments_stood_out text not null check (comments_stood_out in ('yes', 'no', 'unsure')),
  comments_stood_out_details text,
  ai_generated_belief text not null check (ai_generated_belief in ('yes', 'no', 'unsure')),
  ai_likelihood integer not null check (ai_likelihood between 1 and 7),
  gender_identity text,
  age_years integer,
  english_proficiency text,
  education_level text,
  employment_status text,
  full_payload jsonb not null,
  quota_disposition text not null default 'quota'
    check (quota_disposition in ('quota', 'standby', 'overflow_late')),
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
  add column if not exists disconnect_noted_at timestamptz,
  add column if not exists reservation_kind text not null default 'test',
  add column if not exists standby_enqueued_at timestamptz,
  add column if not exists quota_token_id uuid
    references public.advice_transfer_quota_tokens(id),
  add column if not exists draft_payload jsonb not null default '{}'::jsonb,
  add column if not exists draft_updated_at timestamptz,
  add column if not exists abandoned_at timestamptz,
  add column if not exists abandonment_reason text,
  -- Existing rows are historical A-to-B sessions. The same-post claim wrapper
  -- changes both fields only when it creates a new assignment.
  add column if not exists design_variant text not null default 'a_to_b',
  add column if not exists post_task_measure text not null default 'effort';

alter table public.advice_transfer_submissions
  add column if not exists quota_disposition text not null default 'quota',
  add column if not exists validity_status text not null default 'pending',
  add column if not exists reviewed_at timestamptz,
  add column if not exists exclusion_reason text,
  add column if not exists design_variant text not null default 'a_to_b',
  add column if not exists post_task_measure text not null default 'effort',
  add column if not exists response_post_id text,
  add column if not exists response_post_body_sha256 text;

-- Historical submissions answered the paired B post. Preserve that fact while
-- adding an explicit audit field for the post that actually received advice.
update public.advice_transfer_submissions
   set response_post_id = coalesce(response_post_id, target_post_id),
       response_post_body_sha256 = coalesce(
         response_post_body_sha256,
         target_post_body_sha256
       )
 where response_post_id is null
    or response_post_body_sha256 is null;

alter table public.advice_transfer_submissions
  alter column response_post_id set not null,
  alter column response_post_body_sha256 set not null;

-- V4 is additive. Existing assignments retain their legacy protocol and can
-- finish in the legacy client; only the new claim wrapper creates v4 sessions.
-- These fields never alter the allocator, quota tokens, or recruitment settings.
alter table public.advice_transfer_assignments
  add column if not exists protocol_version text not null default 'advice-transfer-v3-admission',
  add column if not exists phase1_snapshot jsonb,
  add column if not exists phase1_locked_at timestamptz,
  add column if not exists phase2_snapshot jsonb,
  add column if not exists phase2_locked_at timestamptz;

alter table public.advice_transfer_submissions
  add column if not exists protocol_version text not null default 'advice-transfer-v3-admission',
  add column if not exists comment_judgments jsonb,
  add column if not exists gist_text text,
  add column if not exists gist_difficulty integer,
  add column if not exists phase1_active_time_ms integer,
  add column if not exists gist_active_time_ms integer,
  add column if not exists phase1_locked_at timestamptz,
  add column if not exists phase2_locked_at timestamptz,
  -- Core questions from the first page of the Qualtrics Demos block. These
  -- remain nullable so legacy submissions and existing rows stay compatible;
  -- the final-submit RPC requires them for new v4 sessions.
  add column if not exists gender_identity text,
  add column if not exists age_years integer,
  add column if not exists english_proficiency text,
  add column if not exists education_level text,
  add column if not exists employment_status text;

-- The old decision-difficulty column is reused only for the same-post final-
-- opinion difficulty item, never for gist difficulty. Old A-to-B v4 sessions
-- continue to use effort, and legacy sessions continue to require both fields.
alter table public.advice_transfer_submissions
  alter column difficulty drop not null,
  alter column effort drop not null;

do $$
begin
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_assignments'::regclass
      and conname = 'advice_transfer_assignment_design_variant') then
    alter table public.advice_transfer_assignments
      add constraint advice_transfer_assignment_design_variant
      check (design_variant in ('a_to_b', 'same_post'));
  end if;
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_assignments'::regclass
      and conname = 'advice_transfer_assignment_post_task_measure') then
    alter table public.advice_transfer_assignments
      add constraint advice_transfer_assignment_post_task_measure
      check (
        post_task_measure in ('effort', 'opinion_difficulty')
        and (post_task_measure = 'effort' or design_variant = 'same_post')
      );
  end if;
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_submissions'::regclass
      and conname = 'advice_transfer_submission_design_variant') then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submission_design_variant
      check (design_variant in ('a_to_b', 'same_post'));
  end if;
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_submissions'::regclass
      and conname = 'advice_transfer_submission_post_task_measure') then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submission_post_task_measure
      check (
        post_task_measure in ('effort', 'opinion_difficulty')
        and (post_task_measure = 'effort' or design_variant = 'same_post')
      );
  end if;
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_submissions'::regclass
      and conname = 'advice_transfer_response_post_hash_length') then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_response_post_hash_length
      check (length(response_post_body_sha256) = 64);
  end if;
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_submissions'::regclass
      and conname = 'advice_transfer_response_post_matches_design') then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_response_post_matches_design
      check (
        (design_variant = 'same_post'
          and response_post_id = exposure_post_id
          and response_post_body_sha256 = exposure_post_body_sha256)
        or
        (design_variant = 'a_to_b'
          and response_post_id = target_post_id
          and response_post_body_sha256 = target_post_body_sha256)
      );
  end if;
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_assignments'::regclass
      and conname = 'advice_transfer_phase_snapshot_consistency') then
    alter table public.advice_transfer_assignments
      add constraint advice_transfer_phase_snapshot_consistency check (
        (phase1_snapshot is null) = (phase1_locked_at is null)
        and (phase2_snapshot is null) = (phase2_locked_at is null)
        and (phase1_snapshot is null or jsonb_typeof(phase1_snapshot) = 'object')
        and (phase2_snapshot is null or jsonb_typeof(phase2_snapshot) = 'object')
        and (phase2_snapshot is null or phase1_snapshot is not null)
        and (phase1_snapshot is null or protocol_version = 'advice-transfer-v4-gist')
      );
  end if;
  -- This constraint predates post_task_measure, so replace it on every setup
  -- run rather than leaving an installed effort-only definition in place.
  alter table public.advice_transfer_submissions
    drop constraint if exists advice_transfer_submission_protocol_measures;
  alter table public.advice_transfer_submissions
    add constraint advice_transfer_submission_protocol_measures check (
      (
        protocol_version <> 'advice-transfer-v4-gist'
        and difficulty is not null
        and effort is not null
      )
      or (
        protocol_version = 'advice-transfer-v4-gist'
        and (
          (post_task_measure = 'effort'
            and difficulty is null
            and effort is not null)
          or
          (post_task_measure = 'opinion_difficulty'
            and difficulty is not null
            and effort is null)
        )
        and comment_judgments is not null
        and jsonb_typeof(comment_judgments) = 'array'
        and jsonb_array_length(comment_judgments) = 5
        and gist_text is not null and length(btrim(gist_text)) > 0
        and gist_difficulty is not null and gist_difficulty between 1 and 7
        and phase1_active_time_ms is not null and phase1_active_time_ms >= 0
        and gist_active_time_ms is not null and gist_active_time_ms >= 0
        and gist_active_time_ms <= phase1_active_time_ms
        and phase1_locked_at is not null and phase2_locked_at is not null
        and phase2_locked_at >= phase1_locked_at
      )
    );
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_submissions'::regclass
      and conname = 'advice_transfer_submission_demographic_values') then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submission_demographic_values check (
        (gender_identity is null or gender_identity in
          ('male', 'female', 'other', 'prefer-not-to-say'))
        and (age_years is null or age_years between 18 and 120)
        and (english_proficiency is null or english_proficiency in
          ('yes', 'no-fluent', 'no-mostly-fluent', 'no-minimal-fluency'))
        and (education_level is null or education_level in (
          'no-school',
          'eighth-grade-or-less',
          'more-than-eighth-less-than-high-school',
          'high-school-degree-or-equivalent',
          'some-college',
          'four-year-college-degree',
          'graduate-or-professional-training'
        ))
        and (employment_status is null or employment_status in
          ('employed', 'self-employed', 'student', 'unemployed', 'other'))
      );
  end if;
end;
$$;

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'advice_transfer_assignments_reservation_kind_check'
       and conrelid = 'public.advice_transfer_assignments'::regclass
  ) then
    alter table public.advice_transfer_assignments
      add constraint advice_transfer_assignments_reservation_kind_check
      check (reservation_kind in ('test', 'quota', 'standby', 'released', 'overflow'));
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conname = 'advice_transfer_submissions_quota_disposition_check'
       and conrelid = 'public.advice_transfer_submissions'::regclass
  ) then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submissions_quota_disposition_check
      check (quota_disposition in ('quota', 'standby', 'overflow_late'));
  end if;

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

  -- Preserve legacy test previews while enforcing the revised minimum on every
  -- formal response in an upgraded database. The submission RPC below also
  -- enforces 77 words for both formal and future test submissions.
  if not exists (
    select 1
      from pg_constraint
     where conname = 'advice_transfer_submissions_formal_word_count_check'
       and conrelid = 'public.advice_transfer_submissions'::regclass
  ) then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submissions_formal_word_count_check
      check (is_test or advice_word_count >= 77);
  end if;
end;
$$;

create index if not exists advice_transfer_submission_analysis_idx
  on public.advice_transfer_submissions (is_test, pair_number, condition, submitted_at);

create index if not exists advice_transfer_assignment_lease_idx
  on public.advice_transfer_assignments (status, lease_expires_at)
  where status = 'claimed';

create index if not exists advice_transfer_submission_quota_validity_idx
  on public.advice_transfer_submissions
    (is_test, quota_disposition, validity_status, stimulus_id, condition);

do $$
begin
  if exists (
    select 1
      from public.advice_transfer_assignments
     where not is_test
       and reservation_kind = 'test'
  ) then
    raise exception 'Existing formal Study 2 assignments require an explicit v2-to-v3 token backfill';
  end if;
end;
$$;

create unique index if not exists advice_transfer_formal_participant_study_unique
  on public.advice_transfer_assignments (prolific_pid, coalesce(study_id, ''))
  where not is_test;

create or replace function public.guard_advice_transfer_target_reduction()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_new_target integer;
begin
  if new.setting_key <> 'formal_target_per_cell' then
    return new;
  end if;
  v_new_target := coalesce((new.setting_value #>> '{}')::integer, 0);
  if v_new_target < 0 then
    raise exception 'The formal target cannot be negative';
  end if;
  if exists (
    select 1
      from public.advice_transfer_quota_tokens token
     where token.slot_index > v_new_target
  ) then
    raise exception 'The formal target cannot be reduced after quota tokens have been created';
  end if;
  return new;
end;
$$;

drop trigger if exists advice_transfer_target_reduction_guard
  on public.advice_transfer_settings;
create trigger advice_transfer_target_reduction_guard
before update of setting_value on public.advice_transfer_settings
for each row execute function public.guard_advice_transfer_target_reduction();

create or replace function public.advice_transfer_word_count(p_text text)
returns integer
language sql
immutable
set search_path = public
as $$
  select count(*)::integer
    from regexp_matches(coalesce(p_text, ''), $re$[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*$re$, 'g');
$$;

-- Phase boundaries are immutable even if a stale browser, draft, or privileged
-- bulk update subsequently attempts to write different locked answers.
create or replace function public.guard_advice_transfer_phase_snapshots()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if old.protocol_version = 'advice-transfer-v4-gist'
     and new.protocol_version is distinct from old.protocol_version then
    raise exception 'A v4 assignment cannot change protocol';
  end if;
  if (
       new.design_variant is distinct from old.design_variant
       or new.post_task_measure is distinct from old.post_task_measure
     ) and not (
       old.protocol_version = 'advice-transfer-v4-gist'
       and old.phase1_locked_at is null
       and old.design_variant = 'a_to_b'
       and old.post_task_measure = 'effort'
       and new.design_variant = 'same_post'
       and new.post_task_measure = 'opinion_difficulty'
     ) then
    raise exception 'Assignment design and post-task measure are immutable';
  end if;
  if old.phase1_locked_at is not null and (
       new.phase1_snapshot is distinct from old.phase1_snapshot
       or new.phase1_locked_at is distinct from old.phase1_locked_at
     ) then
    raise exception 'Phase 1 answers are locked';
  end if;
  if old.phase2_locked_at is not null and (
       new.phase2_snapshot is distinct from old.phase2_snapshot
       or new.phase2_locked_at is distinct from old.phase2_locked_at
     ) then
    raise exception 'Phase 2 answers are locked';
  end if;
  return new;
end;
$$;

drop trigger if exists advice_transfer_phase_snapshots_guard
  on public.advice_transfer_assignments;
create trigger advice_transfer_phase_snapshots_guard
before update on public.advice_transfer_assignments
for each row execute function public.guard_advice_transfer_phase_snapshots();

-- Unlike a bare NOT BETWEEN expression, this also rejects missing/null values,
-- JSON strings, fractions, and values outside the integer storage range.
create or replace function public.advice_transfer_required_integer(
  p_value jsonb,
  p_name text,
  p_min integer,
  p_max integer
)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  v_number numeric;
begin
  if p_value is null or jsonb_typeof(p_value) is distinct from 'number'
     or p_value::text !~ '^-?[0-9]+$' then
    raise exception '% must be an integer between % and %', p_name, p_min, p_max;
  end if;
  v_number := p_value::text::numeric;
  if v_number < p_min or v_number > p_max then
    raise exception '% must be an integer between % and %', p_name, p_min, p_max;
  end if;
  return v_number::integer;
end;
$$;

-- One normalizer is used by drafts, departures, claims, and final submissions.
-- A client can neither forge a lock nor overwrite values behind an existing
-- lock. Unlocked fields (including the funnel answers) remain normal drafts.
create or replace function public.advice_transfer_locked_payload(
  p_assignment public.advice_transfer_assignments,
  p_payload jsonb
)
returns jsonb
language plpgsql
immutable
set search_path = public
as $$
declare
  -- opinionDifficulty is a browser-only state alias. Never persist or return it;
  -- difficulty is the single canonical key for the same-post rating.
  v_result jsonb := coalesce(p_payload, '{}'::jsonb) - 'opinionDifficulty';
  v_timings jsonb;
begin
  if p_assignment.protocol_version <> 'advice-transfer-v4-gist' then
    return v_result;
  end if;
  v_timings := case when jsonb_typeof(v_result -> 'timings') = 'object'
    then v_result -> 'timings' else '{}'::jsonb end;
  v_result := v_result || jsonb_build_object(
    'schemaVersion', p_assignment.protocol_version,
    'protocolVersion', p_assignment.protocol_version,
    'designVariant', p_assignment.design_variant,
    'postTaskMeasure', p_assignment.post_task_measure,
    'phase1Snapshot', p_assignment.phase1_snapshot,
    'phase1LockedAt', p_assignment.phase1_locked_at,
    'phase2Snapshot', p_assignment.phase2_snapshot,
    'phase2LockedAt', p_assignment.phase2_locked_at
  );
  if p_assignment.post_task_measure = 'effort' then
    -- A-to-B v4 drafts retain their unlocked effort answer, but can never
    -- populate the same-post opinion-difficulty field.
    v_result := v_result || jsonb_build_object('difficulty', null);
  else
    -- Same-post drafts retain their unlocked difficulty answer, but can never
    -- populate the retired effort field.
    v_result := v_result || jsonb_build_object('effort', null);
  end if;
  if p_assignment.phase1_snapshot is not null then
    v_result := v_result || jsonb_build_object(
      'commentJudgments', p_assignment.phase1_snapshot -> 'commentJudgments',
      'gistText', p_assignment.phase1_snapshot -> 'gistText',
      'gistDifficulty', p_assignment.phase1_snapshot -> 'gistDifficulty',
      'responsePostId', p_assignment.phase1_snapshot -> 'responsePostId',
      'responsePostSha256', p_assignment.phase1_snapshot -> 'responsePostSha256'
    );
    v_timings := v_timings || (p_assignment.phase1_snapshot -> 'timings')
      || jsonb_build_object('exposureTimeMs',
           p_assignment.phase1_snapshot #> '{timings,phase1ActiveTimeMs}');
  end if;
  if p_assignment.phase2_snapshot is not null then
    v_result := v_result || jsonb_build_object(
      'advice', p_assignment.phase2_snapshot -> 'adviceText',
      'adviceText', p_assignment.phase2_snapshot -> 'adviceText',
      'adviceWordCount', p_assignment.phase2_snapshot -> 'adviceWordCount',
      'adviceCharacterCount', p_assignment.phase2_snapshot -> 'adviceCharacterCount',
      'confidence', p_assignment.phase2_snapshot -> 'confidence'
    );
    if p_assignment.post_task_measure = 'effort' then
      v_result := v_result || jsonb_build_object(
        'difficulty', null,
        'effort', p_assignment.phase2_snapshot -> 'effort'
      );
    else
      v_result := v_result || jsonb_build_object(
        'difficulty', p_assignment.phase2_snapshot -> 'difficulty',
        'effort', null
      );
    end if;
    v_timings := v_timings || (p_assignment.phase2_snapshot -> 'timings');
  end if;
  -- Optional client timing context in either snapshot must not override the
  -- other phase's validated duration fields.
  if p_assignment.phase1_snapshot is not null then
    v_timings := v_timings || jsonb_build_object(
      'phase1ActiveTimeMs', p_assignment.phase1_snapshot #> '{timings,phase1ActiveTimeMs}',
      'gistActiveTimeMs', p_assignment.phase1_snapshot #> '{timings,gistActiveTimeMs}',
      'exposureTimeMs', p_assignment.phase1_snapshot #> '{timings,phase1ActiveTimeMs}'
    );
  end if;
  if p_assignment.phase2_snapshot is not null then
    v_timings := v_timings || jsonb_build_object(
      'adviceResponseTimeMs', p_assignment.phase2_snapshot #> '{timings,adviceResponseTimeMs}'
    );
  end if;
  return v_result || jsonb_build_object('timings', v_timings);
end;
$$;

create or replace function public.ensure_advice_transfer_quota_tokens()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target integer := 0;
  v_inserted integer := 0;
begin
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));

  select coalesce((setting_value #>> '{}')::integer, 0)
    into v_target
    from public.advice_transfer_settings
   where setting_key = 'formal_target_per_cell';

  if coalesce(v_target, 0) < 1 then
    return 0;
  end if;

  insert into public.advice_transfer_quota_tokens (
    stimulus_id,
    pair_number,
    condition,
    slot_index
  )
  select stimulus.stimulus_id,
         stimulus.pair_number,
         conditions.condition,
         slot.slot_index
    from public.advice_transfer_stimuli stimulus
    cross join (values ('human'::text), ('ai'::text)) conditions(condition)
    cross join generate_series(1, v_target) slot(slot_index)
   where stimulus.active
     and stimulus.pair_role = 'primary'
  on conflict (stimulus_id, condition, slot_index) do nothing;

  get diagnostics v_inserted = row_count;
  return v_inserted;
end;
$$;

create or replace function public.promote_advice_transfer_standby(
  p_stimulus_id text,
  p_condition text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_token public.advice_transfer_quota_tokens%rowtype;
  v_assignment public.advice_transfer_assignments%rowtype;
  v_submission public.advice_transfer_submissions%rowtype;
  v_promoted integer := 0;
  v_token_state text;
  v_target integer := 0;
begin
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));

  select coalesce((setting_value #>> '{}')::integer, 0)
    into v_target
    from public.advice_transfer_settings
   where setting_key = 'formal_target_per_cell';

  loop
    select token.*
      into v_token
      from public.advice_transfer_quota_tokens token
      join public.advice_transfer_stimuli stimulus
        on stimulus.stimulus_id = token.stimulus_id
     where token.stimulus_id = p_stimulus_id
       and token.condition = p_condition
       and token.state = 'available'
       and token.slot_index <= v_target
       and stimulus.active
       and stimulus.pair_role = 'primary'
     order by token.slot_index
     limit 1
     for update skip locked;

    exit when v_token.id is null;

    select assignment.*
      into v_assignment
      from public.advice_transfer_assignments assignment
      left join public.advice_transfer_submissions submission
        on submission.assignment_id = assignment.assignment_id
     where not assignment.is_test
       and assignment.stimulus_id = p_stimulus_id
       and assignment.condition = p_condition
       and assignment.reservation_kind = 'standby'
       and (
         (
           assignment.status = 'submitted'
           and submission.quota_disposition = 'standby'
           and submission.validity_status in ('pending', 'valid')
         )
         or (
           assignment.status = 'claimed'
           and assignment.lease_expires_at is not null
           and assignment.lease_expires_at >= now()
         )
       )
     order by case when assignment.status = 'submitted' then 0 else 1 end,
              coalesce(assignment.submitted_at, assignment.standby_enqueued_at, assignment.claimed_at),
              assignment.id
     limit 1
     for update of assignment skip locked;

    exit when v_assignment.id is null;

    if v_assignment.status = 'submitted' then
      select *
        into v_submission
        from public.advice_transfer_submissions
       where assignment_id = v_assignment.assignment_id
       for update;
      v_token_state := case
        when v_submission.validity_status = 'valid' then 'valid'
        else 'pending'
      end;

      update public.advice_transfer_submissions
         set quota_disposition = 'quota'
       where assignment_id = v_assignment.assignment_id;
    else
      v_token_state := 'reserved';
    end if;

    update public.advice_transfer_quota_tokens
       set state = v_token_state,
           current_assignment_id = v_assignment.assignment_id,
           reservation_expires_at = case
             when v_token_state = 'reserved' then v_assignment.lease_expires_at
             else null
           end,
           updated_at = now()
     where id = v_token.id;

    update public.advice_transfer_assignments
       set reservation_kind = 'quota',
           quota_token_id = v_token.id,
           updated_at = now()
     where id = v_assignment.id;

    v_promoted := v_promoted + 1;
    v_token := null;
    v_assignment := null;
    v_submission := null;
  end loop;

  return v_promoted;
end;
$$;

create or replace function public.reclaim_expired_advice_transfer_assignments()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reclaimed integer := 0;
  v_expired_ids text[] := array[]::text[];
  v_cell record;
begin
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));

  select coalesce(array_agg(assignment_id), array[]::text[])
    into v_expired_ids
    from public.advice_transfer_assignments
   where status = 'claimed'
     and lease_expires_at is not null
     and lease_expires_at < now();

  v_reclaimed := coalesce(cardinality(v_expired_ids), 0);

  update public.advice_transfer_quota_tokens token
     set state = 'available',
         current_assignment_id = null,
         reservation_expires_at = null,
         updated_at = now()
   where token.state = 'reserved'
     and token.current_assignment_id = any(v_expired_ids);

  update public.advice_transfer_assignments
     set status = 'abandoned',
         abandoned_at = now(),
         abandonment_reason = 'lease_expired',
         lease_expires_at = null,
         reservation_kind = case when is_test then 'test' else 'released' end,
         quota_token_id = null,
         updated_at = now()
   where assignment_id = any(v_expired_ids);

  delete from public.advice_transfer_waitlist
   where expires_at < now();

  for v_cell in
    select distinct assignment.stimulus_id, assignment.condition
      from public.advice_transfer_assignments assignment
     where assignment.assignment_id = any(v_expired_ids)
       and not assignment.is_test
  loop
    perform public.promote_advice_transfer_standby(
      v_cell.stimulus_id,
      v_cell.condition
    );
  end loop;

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
  v_token public.advice_transfer_quota_tokens%rowtype;
  v_waiter public.advice_transfer_waitlist%rowtype;
  v_stimulus_id text;
  v_is_test boolean;
  v_formal_open boolean := false;
  v_target_per_cell integer := 0;
  v_lease_minutes integer := 5;
  v_waitlist_ttl_seconds integer := 180;
  v_poll_seconds integer := 3;
  v_standby_after_seconds integer := 90;
  v_queue_position integer := 1;
  v_waited_seconds integer := 0;
  v_reservation_kind text;
  v_condition text;
  v_comment_order jsonb;
  v_source_comments jsonb;
  v_source_hashes jsonb;
  v_ordered_comments jsonb;
  v_ordered_hashes jsonb;
  v_cell record;
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

  select greatest(3, least(30, coalesce((setting_value #>> '{}')::integer, 5)))
    into v_lease_minutes
    from public.advice_transfer_settings
   where setting_key = 'assignment_lease_minutes';

  select greatest(120, least(600, coalesce((setting_value #>> '{}')::integer, 180)))
    into v_waitlist_ttl_seconds
    from public.advice_transfer_settings
   where setting_key = 'waitlist_ttl_seconds';

  select greatest(2, least(15, coalesce((setting_value #>> '{}')::integer, 3)))
    into v_poll_seconds
    from public.advice_transfer_settings
   where setting_key = 'admission_poll_seconds';

  select greatest(30, least(600, coalesce((setting_value #>> '{}')::integer, 90)))
    into v_standby_after_seconds
    from public.advice_transfer_settings
   where setting_key = 'standby_after_seconds';

  v_target_per_cell := coalesce(v_target_per_cell, 0);
  v_lease_minutes := coalesce(v_lease_minutes, 5);
  v_waitlist_ttl_seconds := coalesce(v_waitlist_ttl_seconds, 180);
  v_poll_seconds := coalesce(v_poll_seconds, 3);
  v_standby_after_seconds := coalesce(v_standby_after_seconds, 90);

  -- Admission, token release and token promotion share one short transaction
  -- lock. Token rows are the hard per-cell quota boundary.
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  perform public.reclaim_expired_advice_transfer_assignments();

  if v_is_test then
    select *
      into v_assignment
      from public.advice_transfer_assignments
     where prolific_pid = p_prolific_pid
       and coalesce(study_id, '') = coalesce(p_study_id, '')
       and coalesce(session_id, '') = coalesce(p_session_id, '')
     order by created_at desc
     limit 1
     for update;
  else
    -- SESSION_ID can change when Prolific reopens a returned submission. A
    -- formal participant must still recover the original assignment.
    select *
      into v_assignment
      from public.advice_transfer_assignments
     where prolific_pid = p_prolific_pid
       and coalesce(study_id, '') = coalesce(p_study_id, '')
       and not is_test
     order by created_at desc
     limit 1
     for update;
  end if;

  if v_assignment.id is not null and v_assignment.status = 'abandoned' then
    if v_assignment.abandonment_reason = 'lease_expired' then
      v_reservation_kind := case when v_assignment.is_test then 'test' else 'standby' end;
      update public.advice_transfer_assignments
         set status = 'claimed',
             last_heartbeat_at = v_now,
             lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
             disconnect_noted_at = null,
             abandoned_at = null,
             abandonment_reason = null,
             reservation_kind = v_reservation_kind,
             quota_token_id = null,
             standby_enqueued_at = case
               when v_assignment.is_test then standby_enqueued_at
               else coalesce(standby_enqueued_at, v_now)
             end,
             updated_at = v_now
       where id = v_assignment.id
       returning * into v_assignment;

      if not v_assignment.is_test then
        perform public.promote_advice_transfer_standby(
          v_assignment.stimulus_id,
          v_assignment.condition
        );
        select * into v_assignment
          from public.advice_transfer_assignments
         where id = v_assignment.id;
      end if;
    else
      raise exception 'This research session is no longer active';
    end if;
  elsif v_assignment.id is not null and v_assignment.status = 'excluded' then
    raise exception 'This research session is no longer active';
  elsif v_assignment.id is not null and v_assignment.status = 'claimed' then
    if not v_assignment.is_test
       and v_assignment.reservation_kind = 'quota'
       and not exists (
         select 1
           from public.advice_transfer_quota_tokens token
          where token.id = v_assignment.quota_token_id
            and token.state = 'reserved'
            and token.current_assignment_id = v_assignment.assignment_id
       ) then
      update public.advice_transfer_assignments
         set reservation_kind = 'standby',
             quota_token_id = null,
             standby_enqueued_at = coalesce(standby_enqueued_at, v_now)
       where id = v_assignment.id;
      v_assignment.reservation_kind := 'standby';
      v_assignment.quota_token_id := null;
    end if;

    update public.advice_transfer_assignments
       set last_heartbeat_at = v_now,
           lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
           disconnect_noted_at = null,
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;

    if not v_assignment.is_test and v_assignment.reservation_kind = 'quota' then
      update public.advice_transfer_quota_tokens
         set reservation_expires_at = v_assignment.lease_expires_at,
             updated_at = v_now
       where id = v_assignment.quota_token_id
         and state = 'reserved'
         and current_assignment_id = v_assignment.assignment_id;
    elsif not v_assignment.is_test and v_assignment.reservation_kind = 'standby' then
      perform public.promote_advice_transfer_standby(
        v_assignment.stimulus_id,
        v_assignment.condition
      );
      select * into v_assignment
        from public.advice_transfer_assignments
       where id = v_assignment.id;
    end if;
  end if;

  if v_assignment.id is null then
    if not v_is_test
       and not coalesce(v_formal_open, false)
       and not exists (
         select 1
           from public.advice_transfer_waitlist queued
          where queued.prolific_pid = p_prolific_pid
            and queued.study_id = coalesce(p_study_id, '')
            and queued.expires_at >= v_now
       ) then
      return jsonb_build_object(
        'admissionStatus', 'closed',
        'message', 'Formal recruitment is not open yet',
        'serverTime', v_now
      );
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
      v_reservation_kind := 'test';
    else
      if v_target_per_cell < 1 then
        raise exception 'Formal assignment targets have not been configured';
      end if;

      perform public.ensure_advice_transfer_quota_tokens();

      -- A target increase first promotes existing standby participants before
      -- assigning newly arriving people.
      for v_cell in
        select distinct token.stimulus_id, token.condition
          from public.advice_transfer_quota_tokens token
         where token.state = 'available'
           and token.slot_index <= v_target_per_cell
      loop
        perform public.promote_advice_transfer_standby(
          v_cell.stimulus_id,
          v_cell.condition
        );
      end loop;

      insert into public.advice_transfer_waitlist (
        waiter_id,
        prolific_pid,
        study_id,
        session_id,
        enqueued_at,
        last_seen_at,
        expires_at,
        updated_at
      ) values (
        'atw-' || replace(gen_random_uuid()::text, '-', ''),
        p_prolific_pid,
        coalesce(p_study_id, ''),
        coalesce(p_session_id, ''),
        v_now,
        v_now,
        v_now + make_interval(secs => v_waitlist_ttl_seconds),
        v_now
      )
      on conflict (prolific_pid, study_id)
      do update set
        session_id = excluded.session_id,
        last_seen_at = excluded.last_seen_at,
        expires_at = excluded.expires_at,
        updated_at = excluded.updated_at
      returning * into v_waiter;

      select count(*)::integer + 1
        into v_queue_position
        from public.advice_transfer_waitlist queued
       where queued.expires_at >= v_now
         and queued.study_id = coalesce(p_study_id, '')
         and (queued.enqueued_at, queued.id) < (v_waiter.enqueued_at, v_waiter.id);

      v_waited_seconds := greatest(
        0,
        floor(extract(epoch from (v_now - v_waiter.enqueued_at)))::integer
      );

      if v_queue_position = 1 then
        with cell_counts as (
          select token.stimulus_id,
                 token.condition,
                 count(*) filter (where token.state in ('pending', 'valid'))::integer as completed,
                 count(*) filter (where token.state = 'reserved')::integer as active
            from public.advice_transfer_quota_tokens token
           where token.slot_index <= v_target_per_cell
           group by token.stimulus_id, token.condition
        )
        select token.*
          into v_token
          from public.advice_transfer_quota_tokens token
          join public.advice_transfer_stimuli stimulus
            on stimulus.stimulus_id = token.stimulus_id
          join cell_counts counts
            on counts.stimulus_id = token.stimulus_id
           and counts.condition = token.condition
         where token.state = 'available'
           and token.slot_index <= v_target_per_cell
           and stimulus.active
           and stimulus.pair_role = 'primary'
         order by counts.completed, counts.active, random(), token.slot_index
         limit 1
         for update of token skip locked;
      end if;

      if v_token.id is not null then
        v_stimulus_id := v_token.stimulus_id;
        v_condition := v_token.condition;
        v_reservation_kind := 'quota';
      elsif v_queue_position = 1 and v_waited_seconds >= v_standby_after_seconds then
        -- Standby absorbs the brief mismatch between a Prolific return and
        -- database lease expiry. It never consumes a quota token unless a real
        -- vacancy later appears in the same cell.
        with cells as (
          select stimulus.stimulus_id,
                 stimulus.pair_number,
                 conditions.condition
            from public.advice_transfer_stimuli stimulus
            cross join (values ('human'::text), ('ai'::text)) conditions(condition)
           where stimulus.active
             and stimulus.pair_role = 'primary'
        ),
        token_status as (
          select token.stimulus_id,
                 token.condition,
                 min(token.reservation_expires_at) filter (where token.state = 'reserved') as next_expiry
            from public.advice_transfer_quota_tokens token
           where token.slot_index <= v_target_per_cell
           group by token.stimulus_id, token.condition
        ),
        standby_counts as (
          select assignment.stimulus_id,
                 assignment.condition,
                 count(*)::integer as standby_count
            from public.advice_transfer_assignments assignment
           where not assignment.is_test
             and assignment.reservation_kind = 'standby'
             and assignment.status in ('claimed', 'submitted')
           group by assignment.stimulus_id, assignment.condition
        )
        select cell.stimulus_id,
               cell.condition
          into v_stimulus_id,
               v_condition
          from cells cell
          left join token_status token
            on token.stimulus_id = cell.stimulus_id
           and token.condition = cell.condition
          left join standby_counts standby
            on standby.stimulus_id = cell.stimulus_id
           and standby.condition = cell.condition
         order by (token.next_expiry is null),
                  token.next_expiry,
                  coalesce(standby.standby_count, 0),
                  random()
         limit 1;

        v_reservation_kind := 'standby';
      else
        return jsonb_build_object(
          'admissionStatus', 'waiting',
          'queuePosition', v_queue_position,
          'waitedSeconds', v_waited_seconds,
          'retryAfterMs', v_poll_seconds * 1000,
          'message', 'Your study place is being prepared.',
          'serverTime', v_now
        );
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
      reservation_kind,
      quota_token_id,
      standby_enqueued_at,
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
      v_reservation_kind,
      v_token.id,
      case when v_reservation_kind = 'standby' then v_waiter.enqueued_at else null end,
      v_now,
      v_now + make_interval(mins => v_lease_minutes)
    )
    returning * into v_assignment;

    if not v_is_test then
      delete from public.advice_transfer_waitlist
       where prolific_pid = p_prolific_pid
         and study_id = coalesce(p_study_id, '')
         ;
    end if;

    if v_reservation_kind = 'quota' then
      update public.advice_transfer_quota_tokens
         set state = 'reserved',
             current_assignment_id = v_assignment.assignment_id,
             reservation_expires_at = v_assignment.lease_expires_at,
             updated_at = v_now
       where id = v_token.id
         and state = 'available';
      if not found then
        raise exception 'The selected Study 2 quota token was no longer available';
      end if;
    end if;
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
    'admissionStatus', 'assigned',
    'assignmentId', v_assignment.assignment_id,
    'schemaVersion', v_assignment.protocol_version,
    'protocolVersion', v_assignment.protocol_version,
    'status', v_assignment.status,
    'isTest', v_assignment.is_test,
    'pairNumber', v_stimulus.pair_number,
    'pairRole', v_stimulus.pair_role,
    'designVariant', v_assignment.design_variant,
    'postTaskMeasure', v_assignment.post_task_measure,
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
    'responsePost', case
      when v_assignment.design_variant = 'same_post' then jsonb_build_object(
        'postId', v_stimulus.exposure_post_id,
        'title', v_stimulus.exposure_post_title,
        'body', v_stimulus.exposure_post_body,
        'sha256', v_stimulus.exposure_post_body_sha256
      )
      else jsonb_build_object(
        'postId', v_stimulus.target_post_id,
        'title', v_stimulus.target_post_title,
        'body', v_stimulus.target_post_body,
        'sha256', v_stimulus.target_post_body_sha256
      )
    end,
    'comments', v_ordered_comments,
    'commentHashes', v_ordered_hashes,
    'commentOrder', v_assignment.comment_order,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'draftPayload', public.advice_transfer_locked_payload(v_assignment, v_assignment.draft_payload),
    'draftUpdatedAt', v_assignment.draft_updated_at,
    'phase1Snapshot', v_assignment.phase1_snapshot,
    'phase1LockedAt', v_assignment.phase1_locked_at,
    'phase2Snapshot', v_assignment.phase2_snapshot,
    'phase2LockedAt', v_assignment.phase2_locked_at,
    'claimedAt', v_assignment.claimed_at,
    'leaseExpiresAt', v_assignment.lease_expires_at,
    'screenedOutAt', v_assignment.screened_out_at,
    'submittedAt', v_assignment.submitted_at,
    'serverTime', v_now
  );
end;
$$;

-- Remove only the explicit verdict token at the beginning of a comment.
-- Verdict abbreviations appearing later in the prose remain untouched.
create or replace function public.advice_transfer_remove_leading_judgment_label(p_comment text)
returns text
language sql
immutable
strict
set search_path = public
as $$
  select regexp_replace(
    p_comment,
    '^[[:space:]*_]*(Y[[:space:]._-]*T[[:space:]._-]*A|N[[:space:]._-]*T[[:space:]._-]*A|E[[:space:]._-]*S[[:space:]._-]*H|N[[:space:]._-]*A[[:space:]._-]*H|I[[:space:]._-]*N[[:space:]._-]*F[[:space:]._-]*O)(?=$|[^[:alnum:]])[[:space:]*_]*[:.,;!?—–-]*[[:space:]]*',
    '',
    'i'
  );
$$;

-- Preserve the former all-position cleanup only for sessions that already
-- stored hashes under that display rule. New sessions do not use this helper.
create or replace function public.advice_transfer_remove_judgment_labels(p_comment text)
returns text
language sql
immutable
strict
set search_path = public
as $$
  with legacy as (
    select public.advice_transfer_remove_leading_judgment_label(p_comment) as body
  ), trailing_removed as (
    select regexp_replace(
      body,
      '[[:blank:]]+(Y[[:blank:]._-]*T[[:blank:]._-]*A|N[[:blank:]._-]*T[[:blank:]._-]*A|E[[:blank:]._-]*S[[:blank:]._-]*H|N[[:blank:]._-]*A[[:blank:]._-]*H|I[[:blank:]._-]*N[[:blank:]._-]*F[[:blank:]._-]*O)(?=$|[^[:alnum:]])[[:blank:]*_]*[:.,;!?—–-]*[[:blank:]]*$',
      '',
      'i'
    ) as body
    from legacy
  )
  select regexp_replace(
    body,
    '(?<![[:alnum:]])(Y[[:blank:]._-]*T[[:blank:]._-]*A|N[[:blank:]._-]*T[[:blank:]._-]*A|E[[:blank:]._-]*S[[:blank:]._-]*H|N[[:blank:]._-]*A[[:blank:]._-]*H|I[[:blank:]._-]*N[[:blank:]._-]*F[[:blank:]._-]*O)(?![[:alnum:]])[[:blank:]*_]*[:.,;!?—–-]*[[:blank:]]*',
    '',
    'gi'
  )
  from trailing_removed;
$$;

-- Separate RPC name avoids PostgREST overload/default ambiguity. Keep the
-- original allocator available to already-open v2/v3 clients. The shared
-- transaction lock makes the pre-existing identity check and allocation one
-- atomic operation, including two simultaneous first-page requests.
create or replace function public.claim_advice_transfer_assignment_v4(
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
  v_assignment public.advice_transfer_assignments%rowtype;
  v_response jsonb;
  v_clean_comments jsonb;
  v_clean_hashes jsonb;
  v_legacy_comments jsonb;
  v_legacy_hashes jsonb;
  v_pid text := nullif(trim(p_prolific_pid), '');
  v_study text := nullif(trim(p_study_id), '');
  v_session text := nullif(trim(p_session_id), '');
  v_is_test boolean := coalesce(v_pid ~* '^(test|preview|qa)[-_]', false);
begin
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

  v_response := public.claim_advice_transfer_assignment(
    p_prolific_pid, p_study_id, p_session_id,
    p_is_test, p_pair_number, p_condition
  );
  if v_response ->> 'admissionStatus' <> 'assigned' then
    return v_response;
  end if;

  if v_existing_id is null then
    update public.advice_transfer_assignments
       set protocol_version = 'advice-transfer-v4-gist'
     where assignment_id = v_response ->> 'assignmentId'
     returning * into v_assignment;
  else
    select * into v_assignment
      from public.advice_transfer_assignments
     where assignment_id = v_response ->> 'assignmentId';
  end if;

  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    select jsonb_agg(to_jsonb(cleaned.comment_text) order by cleaned.position),
           jsonb_agg(
             to_jsonb(encode(extensions.digest(cleaned.comment_text, 'sha256'), 'hex'))
             order by cleaned.position
           ),
           jsonb_agg(to_jsonb(cleaned.legacy_text) order by cleaned.position),
           jsonb_agg(
             to_jsonb(encode(extensions.digest(cleaned.legacy_text, 'sha256'), 'hex'))
             order by cleaned.position
           )
      into v_clean_comments, v_clean_hashes, v_legacy_comments, v_legacy_hashes
      from (
        select ordinality as position,
               public.advice_transfer_remove_leading_judgment_label(value) as comment_text,
               public.advice_transfer_remove_judgment_labels(value) as legacy_text
          from jsonb_array_elements_text(v_response -> 'comments')
               with ordinality
      ) cleaned;

    -- New v4 sessions remove only the leading verdict token and persist hashes
    -- of exactly what participants see. Historical sessions that used the
    -- former all-position rule continue to receive their original display.
    if v_existing_id is null then
      update public.advice_transfer_assignments
         set presented_comment_sha256 = v_clean_hashes
       where assignment_id = v_assignment.assignment_id
      returning * into v_assignment;
    end if;

    if v_assignment.presented_comment_sha256 = v_clean_hashes then
      v_response := v_response || jsonb_build_object(
        'comments', v_clean_comments,
        'commentHashes', v_clean_hashes
      );
    elsif v_assignment.presented_comment_sha256 = v_legacy_hashes then
      v_response := v_response || jsonb_build_object(
        'comments', v_legacy_comments,
        'commentHashes', v_legacy_hashes
      );
    end if;
  end if;

  return v_response || jsonb_build_object(
    'schemaVersion', v_assignment.protocol_version,
    'protocolVersion', v_assignment.protocol_version,
    'designVariant', v_assignment.design_variant,
    'postTaskMeasure', v_assignment.post_task_measure,
    'responsePost', case
      when v_assignment.design_variant = 'same_post'
        then v_response -> 'exposurePost'
      else v_response -> 'targetPost'
    end,
    'draftPayload', public.advice_transfer_locked_payload(v_assignment, v_assignment.draft_payload),
    'phase1Snapshot', v_assignment.phase1_snapshot,
    'phase1LockedAt', v_assignment.phase1_locked_at,
    'phase2Snapshot', v_assignment.phase2_snapshot,
    'phase2LockedAt', v_assignment.phase2_locked_at
  );
end;
$$;

-- New Study 2 sessions use the same Reddit post in both phases and replace
-- the old effort item with final-opinion difficulty. Existing identities keep
-- their stored design and measure, so refreshes never change the task.
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
begin
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
           post_task_measure = 'opinion_difficulty',
           updated_at = now()
     where id = v_assignment.id
     returning * into v_assignment;
  end if;

  return v_response || jsonb_build_object(
    'designVariant', v_assignment.design_variant,
    'postTaskMeasure', v_assignment.post_task_measure,
    'responsePost', case
      when v_assignment.design_variant = 'same_post'
        then v_response -> 'exposurePost'
      else v_response -> 'targetPost'
    end,
    'draftPayload', public.advice_transfer_locked_payload(
      v_assignment,
      v_assignment.draft_payload
    )
  );
end;
$$;

-- Derive design, measure, and actual response-post audit fields from the
-- assignment on every submission write. This keeps them server-authoritative
-- even if a client sends forged audit metadata.
create or replace function public.set_advice_transfer_response_post_audit()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_server_audit jsonb;
begin
  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = new.assignment_id;

  if v_assignment.id is null then
    raise exception 'Assignment design audit is missing';
  end if;

  new.design_variant := v_assignment.design_variant;
  new.post_task_measure := v_assignment.post_task_measure;
  if v_assignment.design_variant = 'same_post' then
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
    'postTaskMeasure', new.post_task_measure,
    'responsePostId', new.response_post_id,
    'responsePostSha256', new.response_post_body_sha256,
    'serverAudit', v_server_audit || jsonb_build_object(
      'designVariant', new.design_variant,
      'postTaskMeasure', new.post_task_measure,
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
before insert or update of assignment_id, design_variant, post_task_measure,
  exposure_post_id, exposure_post_body_sha256, target_post_id,
  target_post_body_sha256, full_payload
on public.advice_transfer_submissions
for each row execute function public.set_advice_transfer_response_post_audit();

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
  v_lease_minutes integer := 5;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  if p_assignment_id is null or p_prolific_pid is null then
    raise exception 'Missing assignment or participant identifier';
  end if;

  -- Use the allocator's lock order: advisory lock BEFORE any assignment/token
  -- row. A heartbeat may promote standby work and must not invert that order
  -- against a simultaneous claim, stage save, or lease reclamation.
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));

  select greatest(3, least(30, coalesce((setting_value #>> '{}')::integer, 5)))
    into v_lease_minutes
    from public.advice_transfer_settings
   where setting_key = 'assignment_lease_minutes';
  v_lease_minutes := coalesce(v_lease_minutes, 5);

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
      'active', false,
      'serverTime', v_now
    );
  elsif v_assignment.status = 'abandoned'
        and v_assignment.abandonment_reason = 'lease_expired' then
    update public.advice_transfer_assignments
       set status = 'claimed',
           last_heartbeat_at = v_now,
           lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
           disconnect_noted_at = null,
           abandoned_at = null,
           abandonment_reason = null,
           reservation_kind = case when is_test then 'test' else 'standby' end,
           quota_token_id = null,
           standby_enqueued_at = case
             when is_test then standby_enqueued_at
             else coalesce(standby_enqueued_at, v_now)
           end,
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;
  end if;

  if v_assignment.status = 'claimed' then
    if not v_assignment.is_test
       and v_assignment.reservation_kind = 'quota'
       and not exists (
         select 1
           from public.advice_transfer_quota_tokens token
          where token.id = v_assignment.quota_token_id
            and token.state = 'reserved'
            and token.current_assignment_id = v_assignment.assignment_id
       ) then
      update public.advice_transfer_assignments
         set reservation_kind = 'standby',
             quota_token_id = null,
             standby_enqueued_at = coalesce(standby_enqueued_at, v_now)
       where id = v_assignment.id
       returning * into v_assignment;
    end if;

    update public.advice_transfer_assignments
       set last_heartbeat_at = v_now,
           lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
           disconnect_noted_at = null,
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;

    if not v_assignment.is_test and v_assignment.reservation_kind = 'quota' then
      update public.advice_transfer_quota_tokens
         set reservation_expires_at = v_assignment.lease_expires_at,
             updated_at = v_now
       where id = v_assignment.quota_token_id
         and state = 'reserved'
         and current_assignment_id = v_assignment.assignment_id;
    elsif not v_assignment.is_test and v_assignment.reservation_kind = 'standby' then
      perform public.promote_advice_transfer_standby(
        v_assignment.stimulus_id,
        v_assignment.condition
      );
      select * into v_assignment
        from public.advice_transfer_assignments
       where id = v_assignment.id;
    end if;
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

-- The first successful call at each boundary wins. Retrying a timed-out call,
-- even with stale client values, returns the original authoritative snapshot.
-- Comment labels are recorded, never graded or connected to screen-out logic.
create or replace function public.save_advice_transfer_stage(
  p_assignment_id text,
  p_prolific_pid text,
  p_stage text,
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
  v_heartbeat jsonb;
  v_snapshot jsonb;
  v_locked_at timestamptz;
  v_already_saved boolean := false;
  v_judgments jsonb := '[]'::jsonb;
  v_judgment jsonb;
  v_position integer;
  v_comment_index integer;
  v_label text;
  v_gist text;
  v_gist_word_count integer;
  v_gist_difficulty integer;
  v_phase1_ms integer;
  v_gist_ms integer;
  v_advice text;
  v_word_count integer;
  v_difficulty integer;
  v_effort integer;
  v_confidence integer;
  v_advice_ms integer;
  v_timings jsonb;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  if p_assignment_id is null or p_prolific_pid is null then
    raise exception 'Missing assignment or participant identifier';
  end if;
  if p_stage is null or p_stage not in ('phase1', 'phase2') then
    raise exception 'Unknown Study 2 phase';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) is distinct from 'object'
     or octet_length(p_payload::text) > 200000 then
    raise exception 'Stage payload must be a JSON object no larger than 200000 bytes';
  end if;
  if p_payload ->> 'schemaVersion' is distinct from 'advice-transfer-v4-gist' then
    raise exception 'Stage payload protocol is not advice-transfer-v4-gist';
  end if;

  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id and prolific_pid = p_prolific_pid
   for update;
  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.protocol_version <> 'advice-transfer-v4-gist' then
    raise exception 'This assignment belongs to the legacy Study 2 protocol';
  end if;

  select * into v_stimulus
    from public.advice_transfer_stimuli
   where stimulus_id = v_assignment.stimulus_id;
  if v_stimulus.stimulus_id is null then
    raise exception 'Assigned Study 2 stimulus was not found';
  end if;

  v_snapshot := case when p_stage = 'phase1'
    then v_assignment.phase1_snapshot else v_assignment.phase2_snapshot end;
  v_locked_at := case when p_stage = 'phase1'
    then v_assignment.phase1_locked_at else v_assignment.phase2_locked_at end;
  v_already_saved := v_snapshot is not null;
  if not v_already_saved then
    if p_stage = 'phase2' and v_assignment.phase1_snapshot is null then
      raise exception 'Phase 1 must be saved before Phase 2';
    end if;
    v_heartbeat := public.heartbeat_advice_transfer_assignment(p_assignment_id, p_prolific_pid);
    if not coalesce((v_heartbeat ->> 'active')::boolean, false) then
      raise exception 'This assignment is no longer active';
    end if;
    select * into v_assignment
      from public.advice_transfer_assignments
     where assignment_id = p_assignment_id;
    if jsonb_typeof(p_payload -> 'timings') is distinct from 'object' then
      raise exception 'Stage timings are required';
    end if;
    v_timings := p_payload -> 'timings';

    if p_stage = 'phase1' then
      if jsonb_typeof(p_payload -> 'commentJudgments') is distinct from 'array' then
        raise exception 'Exactly five comment classifications are required';
      end if;
      if jsonb_array_length(p_payload -> 'commentJudgments') <> 5 then
        raise exception 'Exactly five comment classifications are required';
      end if;
      for v_position in 1..5 loop
        v_judgment := p_payload -> 'commentJudgments' -> (v_position - 1);
        if jsonb_typeof(v_judgment) is distinct from 'object' then
          raise exception 'Comment classification % is invalid', v_position;
        end if;
        if public.advice_transfer_required_integer(
             v_judgment -> 'displayPosition', 'displayPosition', 1, 5
           ) <> v_position then
          raise exception 'Comment classifications must match display positions 1 through 5';
        end if;
        v_comment_index := public.advice_transfer_required_integer(
          v_judgment -> 'commentIndex', 'commentIndex', 0, 4
        );
        if v_comment_index <> (v_assignment.comment_order ->> (v_position - 1))::integer
           or v_judgment ->> 'commentSha256' is distinct from
                v_assignment.presented_comment_sha256 ->> (v_position - 1) then
          raise exception 'Comment classification % does not match its assigned comment', v_position;
        end if;
        v_label := v_judgment ->> 'label';
        if v_label is null or v_label not in ('YTA', 'NTA', 'ESH', 'NAH', 'INFO') then
          raise exception 'Each comment requires one of YTA, NTA, ESH, NAH, or INFO';
        end if;
        v_judgments := v_judgments || jsonb_build_array(jsonb_build_object(
          'displayPosition', v_position,
          'commentIndex', v_comment_index,
          'commentSha256', v_assignment.presented_comment_sha256 ->> (v_position - 1),
          'label', v_label
        ));
      end loop;
      if jsonb_typeof(p_payload -> 'gistText') is distinct from 'string' then
        raise exception 'A nonempty gist summary is required';
      end if;
      v_gist := btrim(p_payload ->> 'gistText');
      if v_gist = '' or v_gist !~ '\S' then
        raise exception 'A nonempty gist summary is required';
      end if;
      v_gist_word_count := public.advice_transfer_word_count(v_gist);
      if v_gist_word_count < 25 then
        raise exception 'A gist summary of at least 25 English words is required';
      end if;
      v_gist_difficulty := public.advice_transfer_required_integer(
        p_payload -> 'gistDifficulty', 'gistDifficulty', 1, 7
      );
      v_phase1_ms := public.advice_transfer_required_integer(
        v_timings -> 'phase1ActiveTimeMs', 'phase1ActiveTimeMs', 0, 2147483647
      );
      v_gist_ms := public.advice_transfer_required_integer(
        v_timings -> 'gistActiveTimeMs', 'gistActiveTimeMs', 0, 2147483647
      );
      if v_gist_ms > v_phase1_ms then
        raise exception 'Gist time cannot exceed total Phase 1 active time';
      end if;
      v_now := clock_timestamp();
      v_snapshot := jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'stage', 'phase1',
        'designVariant', v_assignment.design_variant,
        'postTaskMeasure', v_assignment.post_task_measure,
        'responsePostId', case
          when v_assignment.design_variant = 'same_post'
            then v_stimulus.exposure_post_id
          else v_stimulus.target_post_id
        end,
        'responsePostSha256', case
          when v_assignment.design_variant = 'same_post'
            then v_stimulus.exposure_post_body_sha256
          else v_stimulus.target_post_body_sha256
        end,
        'commentJudgments', v_judgments,
        'gistText', v_gist,
        'gistWordCount', v_gist_word_count,
        'gistDifficulty', v_gist_difficulty,
        'timings', v_timings || jsonb_build_object(
          'phase1ActiveTimeMs', v_phase1_ms, 'gistActiveTimeMs', v_gist_ms
        ),
        'lockedAt', v_now
      );
      update public.advice_transfer_assignments
         set phase1_snapshot = v_snapshot, phase1_locked_at = v_now, updated_at = v_now
       where id = v_assignment.id
       returning * into v_assignment;
    else
      if jsonb_typeof(p_payload -> 'adviceText') is distinct from 'string' then
        raise exception 'An opinion of at least 77 English words is required';
      end if;
      v_advice := btrim(p_payload ->> 'adviceText');
      v_word_count := public.advice_transfer_word_count(v_advice);
      if v_word_count < 77 then
        raise exception 'An opinion of at least 77 English words is required';
      end if;
      if coalesce(p_payload ->> 'postTaskMeasure', 'effort')
           is distinct from v_assignment.post_task_measure then
        raise exception 'Post-task measure does not match assignment';
      end if;
      if v_assignment.post_task_measure = 'opinion_difficulty' then
        v_difficulty := public.advice_transfer_required_integer(
          p_payload -> 'difficulty', 'difficulty', 1, 7
        );
        if p_payload -> 'effort' is not null
           and jsonb_typeof(p_payload -> 'effort') is distinct from 'null' then
          raise exception 'Effort is not collected for this assignment';
        end if;
        v_effort := null;
      else
        v_effort := public.advice_transfer_required_integer(
          p_payload -> 'effort', 'effort', 1, 7
        );
        if p_payload -> 'difficulty' is not null
           and jsonb_typeof(p_payload -> 'difficulty') is distinct from 'null' then
          raise exception 'Opinion difficulty is not collected for this assignment';
        end if;
        v_difficulty := null;
      end if;
      v_confidence := public.advice_transfer_required_integer(p_payload -> 'confidence', 'confidence', 1, 7);
      v_advice_ms := public.advice_transfer_required_integer(
        v_timings -> 'adviceResponseTimeMs', 'adviceResponseTimeMs', 0, 2147483647
      );
      v_now := greatest(clock_timestamp(), v_assignment.phase1_locked_at);
      v_snapshot := jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'stage', 'phase2',
        'designVariant', v_assignment.design_variant,
        'postTaskMeasure', v_assignment.post_task_measure,
        'responsePostId', case
          when v_assignment.design_variant = 'same_post'
            then v_stimulus.exposure_post_id
          else v_stimulus.target_post_id
        end,
        'responsePostSha256', case
          when v_assignment.design_variant = 'same_post'
            then v_stimulus.exposure_post_body_sha256
          else v_stimulus.target_post_body_sha256
        end,
        'adviceText', v_advice,
        'adviceWordCount', v_word_count,
        'adviceCharacterCount', char_length(v_advice),
        'difficulty', v_difficulty,
        'effort', v_effort,
        'confidence', v_confidence,
        'timings', v_timings || jsonb_build_object('adviceResponseTimeMs', v_advice_ms),
        'lockedAt', v_now
      );
      update public.advice_transfer_assignments
         set phase2_snapshot = v_snapshot, phase2_locked_at = v_now, updated_at = v_now
       where id = v_assignment.id
       returning * into v_assignment;
    end if;
    v_locked_at := v_now;
    update public.advice_transfer_assignments
       set draft_payload = public.advice_transfer_locked_payload(v_assignment, draft_payload),
           draft_updated_at = v_now
     where id = v_assignment.id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'stage', p_stage,
    'alreadySaved', v_already_saved,
    'snapshot', v_snapshot,
    'lockedAt', v_locked_at,
    'phase1Snapshot', v_assignment.phase1_snapshot,
    'phase1LockedAt', v_assignment.phase1_locked_at,
    'phase2Snapshot', v_assignment.phase2_snapshot,
    'phase2LockedAt', v_assignment.phase2_locked_at,
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
  v_heartbeat jsonb;
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

  v_heartbeat := public.heartbeat_advice_transfer_assignment(
    p_assignment_id,
    p_prolific_pid
  );

  if coalesce((v_heartbeat ->> 'status'), '') = 'submitted' then
    select * into v_assignment
      from public.advice_transfer_assignments
     where assignment_id = p_assignment_id;
    return jsonb_build_object(
      'ok', true,
      'status', 'submitted',
      'savedAt', v_assignment.submitted_at,
      'alreadySubmitted', true
    );
  end if;

  if not coalesce((v_heartbeat ->> 'active')::boolean, false) then
    return jsonb_build_object(
      'ok', false,
      'status', coalesce(v_heartbeat ->> 'status', 'inactive'),
      'saved', false,
      'alreadySubmitted', false
    );
  end if;

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
     and prolific_pid = p_prolific_pid
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.status <> 'claimed' then
    raise exception 'This assignment is no longer active';
  end if;

  if v_assignment.protocol_version = 'advice-transfer-v4-gist'
     and p_payload ->> 'schemaVersion' is distinct from v_assignment.protocol_version then
    raise exception 'Draft protocol does not match assignment';
  elsif v_assignment.protocol_version <> 'advice-transfer-v4-gist'
        and p_payload ->> 'schemaVersion' = 'advice-transfer-v4-gist' then
    raise exception 'A legacy draft cannot be replaced with a v4 draft';
  end if;

  update public.advice_transfer_assignments
     set draft_payload = public.advice_transfer_locked_payload(v_assignment, p_payload),
         draft_updated_at = v_now,
         updated_at = v_now
   where id = v_assignment.id;

  return jsonb_build_object(
    'ok', true,
    'status', 'claimed',
    'savedAt', v_now,
    'leaseExpiresAt', v_assignment.lease_expires_at,
    'phase1Snapshot', v_assignment.phase1_snapshot,
    'phase1LockedAt', v_assignment.phase1_locked_at,
    'phase2Snapshot', v_assignment.phase2_snapshot,
    'phase2LockedAt', v_assignment.phase2_locked_at,
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

  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  perform public.reclaim_expired_advice_transfer_assignments();

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
    update public.advice_transfer_quota_tokens
       set state = 'available',
           current_assignment_id = null,
           reservation_expires_at = null,
           updated_at = v_now
     where current_assignment_id = v_assignment.assignment_id
       and state = 'reserved';

    update public.advice_transfer_assignments
       set status = 'abandoned',
           lease_expires_at = null,
           disconnect_noted_at = null,
           abandoned_at = v_now,
           abandonment_reason = p_reason,
           reservation_kind = case when is_test then 'test' else 'released' end,
           quota_token_id = null,
           updated_at = v_now
     where id = v_assignment.id;

    if not v_assignment.is_test then
      perform public.promote_advice_transfer_standby(
        v_assignment.stimulus_id,
        v_assignment.condition
      );
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', 'abandoned',
    'releasedAt', v_now
  );
end;
$$;

create or replace function public.mark_advice_transfer_departure(
  p_assignment_id text,
  p_prolific_pid text,
  p_draft_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_transfer_assignments%rowtype;
  v_grace_seconds integer := 90;
  v_release_at timestamptz;
  v_now timestamptz := now();
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  if p_assignment_id is null or p_prolific_pid is null then
    raise exception 'Missing assignment or participant identifier';
  end if;
  if p_draft_payload is not null
     and (
       jsonb_typeof(p_draft_payload) <> 'object'
       or octet_length(p_draft_payload::text) > 200000
     ) then
    raise exception 'Departure draft payload is invalid or too large';
  end if;

  -- Same global-before-row ordering as heartbeat/admission; quota decisions
  -- and the departure grace interval are otherwise unchanged.
  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));

  select greatest(30, least(600, coalesce((setting_value #>> '{}')::integer, 90)))
    into v_grace_seconds
    from public.advice_transfer_settings
   where setting_key = 'departure_grace_seconds';
  v_grace_seconds := coalesce(v_grace_seconds, 90);
  v_release_at := v_now + make_interval(secs => v_grace_seconds);

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
     and prolific_pid = p_prolific_pid
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;

  if p_draft_payload is not null then
    if v_assignment.protocol_version = 'advice-transfer-v4-gist'
       and p_draft_payload ->> 'schemaVersion' is distinct from v_assignment.protocol_version then
      raise exception 'Departure draft protocol does not match assignment';
    elsif v_assignment.protocol_version <> 'advice-transfer-v4-gist'
          and p_draft_payload ->> 'schemaVersion' = 'advice-transfer-v4-gist' then
      raise exception 'A legacy draft cannot be replaced with a v4 draft';
    end if;
  end if;

  if v_assignment.status = 'claimed' then
    update public.advice_transfer_assignments
       set disconnect_noted_at = v_now,
           draft_payload = case
             when p_draft_payload is null then draft_payload
             else public.advice_transfer_locked_payload(v_assignment, p_draft_payload)
           end,
           draft_updated_at = case
             when p_draft_payload is null then draft_updated_at
             else v_now
           end,
           lease_expires_at = least(
             coalesce(lease_expires_at, v_release_at),
             v_release_at
           ),
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;

    if v_assignment.reservation_kind = 'quota' then
      update public.advice_transfer_quota_tokens
         set reservation_expires_at = v_assignment.lease_expires_at,
             updated_at = v_now
       where id = v_assignment.quota_token_id
         and state = 'reserved'
         and current_assignment_id = v_assignment.assignment_id;
    end if;
  end if;

  return jsonb_build_object(
    'ok', true,
    'status', v_assignment.status,
    'releaseAfter', v_assignment.lease_expires_at,
    'phase1Snapshot', v_assignment.phase1_snapshot,
    'phase1LockedAt', v_assignment.phase1_locked_at,
    'phase2Snapshot', v_assignment.phase2_snapshot,
    'phase2LockedAt', v_assignment.phase2_locked_at,
    'serverTime', v_now
  );
end;
$$;

-- Compatibility wrapper for a page that was opened before the v3 frontend
-- deployment and therefore sends no final draft with its departure signal.
create or replace function public.mark_advice_transfer_departure(
  p_assignment_id text,
  p_prolific_pid text
)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.mark_advice_transfer_departure(
    p_assignment_id,
    p_prolific_pid,
    null::jsonb
  );
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
  v_lease_minutes integer := 5;
  v_now timestamptz := now();
begin
  select greatest(3, least(30, coalesce((setting_value #>> '{}')::integer, 5)))
    into v_lease_minutes
    from public.advice_transfer_settings
   where setting_key = 'assignment_lease_minutes';
  v_lease_minutes := coalesce(v_lease_minutes, 5);

  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  perform public.reclaim_expired_advice_transfer_assignments();

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
           last_heartbeat_at = v_now,
           lease_expires_at = v_now + make_interval(mins => v_lease_minutes),
           disconnect_noted_at = null,
           abandoned_at = null,
           abandonment_reason = null,
           reservation_kind = case when is_test then 'test' else 'standby' end,
           quota_token_id = null,
           standby_enqueued_at = case
             when is_test then standby_enqueued_at
             else coalesce(standby_enqueued_at, v_now)
           end
     where id = v_assignment.id;
    v_assignment.status := 'claimed';
    v_assignment.reservation_kind := case when v_assignment.is_test then 'test' else 'standby' end;
    v_assignment.quota_token_id := null;

    if not v_assignment.is_test then
      perform public.promote_advice_transfer_standby(
        v_assignment.stimulus_id,
        v_assignment.condition
      );
      select * into v_assignment
        from public.advice_transfer_assignments
       where id = v_assignment.id;
    end if;
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

  if v_status = 'screened_out' and not v_assignment.is_test then
    update public.advice_transfer_quota_tokens
       set state = 'available',
           current_assignment_id = null,
           reservation_expires_at = null,
           updated_at = v_now
     where current_assignment_id = v_assignment.assignment_id
       and state = 'reserved';

    update public.advice_transfer_assignments
       set reservation_kind = 'released',
           quota_token_id = null
     where id = v_assignment.id;

    perform public.promote_advice_transfer_standby(
      v_assignment.stimulus_id,
      v_assignment.condition
    );
  elsif v_status = 'claimed'
        and not v_assignment.is_test
        and v_assignment.reservation_kind = 'quota' then
    update public.advice_transfer_quota_tokens
       set reservation_expires_at = v_now + make_interval(mins => v_lease_minutes),
           updated_at = v_now
     where id = v_assignment.quota_token_id
       and state = 'reserved'
       and current_assignment_id = v_assignment.assignment_id;
  end if;

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
  v_token public.advice_transfer_quota_tokens%rowtype;
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
  v_gender_identity text;
  v_age_years integer;
  v_english_proficiency text;
  v_education_level text;
  v_employment_status text;
  v_quota_disposition text := 'standby';
  v_comment_judgments jsonb;
  v_gist_text text;
  v_gist_difficulty integer;
  v_phase1_ms integer;
  v_gist_ms integer;
  v_now timestamptz := now();
begin
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Submission payload must be a JSON object';
  end if;
  if octet_length(p_payload::text) > 200000 then
    raise exception 'Submission payload is too large';
  end if;

  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  perform public.reclaim_expired_advice_transfer_assignments();

  select * into v_assignment
    from public.advice_transfer_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
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

  if v_assignment.status = 'screened_out' then
    raise exception 'This session ended after two incorrect attention-check answers';
  end if;
  if v_assignment.status = 'abandoned'
     and v_assignment.abandonment_reason = 'lease_expired' then
    update public.advice_transfer_assignments
       set status = 'claimed',
           reservation_kind = case when is_test then 'test' else 'standby' end,
           quota_token_id = null,
           standby_enqueued_at = case
             when is_test then standby_enqueued_at
             else coalesce(standby_enqueued_at, v_now)
           end,
           last_heartbeat_at = v_now,
           abandoned_at = null,
           abandonment_reason = null,
           updated_at = v_now
     where id = v_assignment.id
     returning * into v_assignment;
  elsif v_assignment.status <> 'claimed' then
    raise exception 'This assignment is no longer active';
  end if;

  if not v_assignment.is_test and v_assignment.reservation_kind = 'standby' then
    perform public.promote_advice_transfer_standby(
      v_assignment.stimulus_id,
      v_assignment.condition
    );
    select * into v_assignment
      from public.advice_transfer_assignments
     where id = v_assignment.id;
  end if;

  if v_assignment.is_test then
    v_quota_disposition := 'quota';
  elsif v_assignment.reservation_kind = 'quota' then
    select * into v_token
      from public.advice_transfer_quota_tokens
     where id = v_assignment.quota_token_id
       and state = 'reserved'
       and current_assignment_id = v_assignment.assignment_id
     for update;
    if v_token.id is not null then
      v_quota_disposition := 'quota';
    else
      update public.advice_transfer_assignments
         set reservation_kind = 'standby',
             quota_token_id = null,
             standby_enqueued_at = coalesce(standby_enqueued_at, v_now)
       where id = v_assignment.id
       returning * into v_assignment;
      v_quota_disposition := 'standby';
    end if;
  end if;

  select * into v_stimulus
    from public.advice_transfer_stimuli
   where stimulus_id = v_assignment.stimulus_id;

  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    if p_payload ->> 'schemaVersion' is distinct from v_assignment.protocol_version then
      raise exception 'Submission protocol does not match assignment';
    end if;
    if v_assignment.phase1_snapshot is null or v_assignment.phase2_snapshot is null then
      raise exception 'Both Study 2 phases must be saved before final submission';
    end if;
    -- Never trust final/draft copies of locked data. This also makes a final
    -- retry safe after an earlier stage response was lost in transit.
    p_payload := public.advice_transfer_locked_payload(v_assignment, p_payload);
    v_comment_judgments := v_assignment.phase1_snapshot -> 'commentJudgments';
    v_gist_text := v_assignment.phase1_snapshot ->> 'gistText';
    v_gist_difficulty := public.advice_transfer_required_integer(
      v_assignment.phase1_snapshot -> 'gistDifficulty', 'gistDifficulty', 1, 7
    );
    v_phase1_ms := public.advice_transfer_required_integer(
      v_assignment.phase1_snapshot #> '{timings,phase1ActiveTimeMs}', 'phase1ActiveTimeMs', 0, 2147483647
    );
    v_gist_ms := public.advice_transfer_required_integer(
      v_assignment.phase1_snapshot #> '{timings,gistActiveTimeMs}', 'gistActiveTimeMs', 0, 2147483647
    );
    if p_payload -> 'demographics' is null
       or jsonb_typeof(p_payload -> 'demographics') is distinct from 'object' then
      raise exception 'Demographic responses are required';
    end if;
    v_gender_identity := lower(trim(coalesce(
      p_payload #>> '{demographics,genderIdentity}', ''
    )));
    v_age_years := public.advice_transfer_required_integer(
      p_payload #> '{demographics,ageYears}', 'ageYears', 18, 120
    );
    v_english_proficiency := lower(trim(coalesce(
      p_payload #>> '{demographics,englishProficiency}', ''
    )));
    v_education_level := lower(trim(coalesce(
      p_payload #>> '{demographics,educationLevel}', ''
    )));
    v_employment_status := lower(trim(coalesce(
      p_payload #>> '{demographics,employmentStatus}', ''
    )));
  elsif p_payload ->> 'schemaVersion' = 'advice-transfer-v4-gist' then
    raise exception 'A legacy assignment must finish using its original protocol';
  end if;

  v_advice := trim(coalesce(p_payload ->> 'adviceText', ''));
  v_word_count := public.advice_transfer_word_count(v_advice);
  v_character_count := char_length(v_advice);
  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    if v_assignment.post_task_measure = 'opinion_difficulty' then
      if v_assignment.phase2_snapshot ->> 'postTaskMeasure'
           is distinct from 'opinion_difficulty'
         or v_assignment.phase2_snapshot ->> 'designVariant'
           is distinct from v_assignment.design_variant
         or v_assignment.phase2_snapshot ->> 'responsePostId'
           is distinct from v_stimulus.exposure_post_id
         or v_assignment.phase2_snapshot ->> 'responsePostSha256'
           is distinct from v_stimulus.exposure_post_body_sha256 then
        raise exception 'Locked Phase 2 design audit does not match assignment';
      end if;
      v_difficulty := public.advice_transfer_required_integer(
        v_assignment.phase2_snapshot -> 'difficulty', 'difficulty', 1, 7
      );
      v_effort := null;
    else
      if v_assignment.phase2_snapshot ? 'postTaskMeasure'
         and v_assignment.phase2_snapshot ->> 'postTaskMeasure'
           is distinct from 'effort' then
        raise exception 'Locked Phase 2 measure does not match assignment';
      end if;
      v_difficulty := null;
      v_effort := public.advice_transfer_required_integer(
        v_assignment.phase2_snapshot -> 'effort', 'effort', 1, 7
      );
    end if;
    v_confidence := public.advice_transfer_required_integer(
      v_assignment.phase2_snapshot -> 'confidence', 'confidence', 1, 7
    );
  else
    v_difficulty := nullif(p_payload ->> 'difficulty', '')::integer;
    v_effort := nullif(p_payload ->> 'effort', '')::integer;
    v_confidence := nullif(p_payload ->> 'confidence', '')::integer;
  end if;
  v_exposure_time := coalesce(nullif(p_payload #>> '{timings,exposureTimeMs}', '')::integer, 0);
  v_advice_time := coalesce(nullif(p_payload #>> '{timings,adviceResponseTimeMs}', '')::integer, 0);
  v_purpose := trim(coalesce(p_payload ->> 'purposeGuess', ''));
  v_stood_out := lower(trim(coalesce(p_payload ->> 'commentsStoodOut', '')));
  v_stood_out_details := nullif(trim(coalesce(p_payload ->> 'commentsStoodOutDetails', '')), '');
  v_ai_belief := lower(trim(coalesce(p_payload ->> 'aiGeneratedBelief', '')));
  v_ai_likelihood := case when v_assignment.protocol_version = 'advice-transfer-v4-gist'
    then public.advice_transfer_required_integer(p_payload -> 'aiLikelihood', 'aiLikelihood', 1, 7)
    else nullif(p_payload ->> 'aiLikelihood', '')::integer end;

  if v_word_count < 77 then
    raise exception 'Advice must contain at least 77 English words';
  end if;
  if (
       v_assignment.protocol_version <> 'advice-transfer-v4-gist'
       and (
         v_difficulty is null or v_difficulty not between 1 and 7
         or v_effort is null or v_effort not between 1 and 7
       )
     )
     or (
       v_assignment.protocol_version = 'advice-transfer-v4-gist'
       and v_assignment.post_task_measure = 'effort'
       and (
         v_difficulty is not null
         or v_effort is null or v_effort not between 1 and 7
       )
     )
     or (
       v_assignment.protocol_version = 'advice-transfer-v4-gist'
       and v_assignment.post_task_measure = 'opinion_difficulty'
       and (
         v_difficulty is null or v_difficulty not between 1 and 7
         or v_effort is not null
       )
     )
     or v_confidence is null or v_confidence not between 1 and 7 then
    raise exception 'Required post-task ratings must each be between 1 and 7';
  end if;
  if v_exposure_time < 0 or v_advice_time < 0 then
    raise exception 'Response times cannot be negative';
  end if;
  if v_purpose = '' or v_purpose !~ '\S' then
    raise exception 'The study-purpose response is required';
  end if;
  if v_stood_out not in ('yes', 'no', 'unsure') then
    raise exception 'The comment-notice response is required';
  end if;
  if v_ai_belief not in ('yes', 'no', 'unsure')
     or v_ai_likelihood is null or v_ai_likelihood not between 1 and 7 then
    raise exception 'The AI-source responses are required';
  end if;
  if v_assignment.protocol_version = 'advice-transfer-v4-gist' then
    if v_gender_identity not in ('male', 'female', 'other', 'prefer-not-to-say') then
      raise exception 'A valid gender identity response is required';
    end if;
    if v_english_proficiency not in
       ('yes', 'no-fluent', 'no-mostly-fluent', 'no-minimal-fluency') then
      raise exception 'A valid English-language response is required';
    end if;
    if v_education_level not in (
      'no-school',
      'eighth-grade-or-less',
      'more-than-eighth-less-than-high-school',
      'high-school-degree-or-equivalent',
      'some-college',
      'four-year-college-degree',
      'graduate-or-professional-training'
    ) then
      raise exception 'A valid education-level response is required';
    end if;
    if v_employment_status not in
       ('employed', 'self-employed', 'student', 'unemployed', 'other') then
      raise exception 'A valid employment-status response is required';
    end if;
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
    design_variant,
    post_task_measure,
    is_test,
    comment_order,
    comment_sha256,
    exposure_post_id,
    exposure_post_body_sha256,
    target_post_id,
    target_post_body_sha256,
    response_post_id,
    response_post_body_sha256,
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
    gender_identity,
    age_years,
    english_proficiency,
    education_level,
    employment_status,
    protocol_version,
    comment_judgments,
    gist_text,
    gist_difficulty,
    phase1_active_time_ms,
    gist_active_time_ms,
    phase1_locked_at,
    phase2_locked_at,
    full_payload,
    quota_disposition,
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
    v_assignment.design_variant,
    v_assignment.post_task_measure,
    v_assignment.is_test,
    v_assignment.comment_order,
    v_assignment.presented_comment_sha256,
    v_stimulus.exposure_post_id,
    v_stimulus.exposure_post_body_sha256,
    v_stimulus.target_post_id,
    v_stimulus.target_post_body_sha256,
    case when v_assignment.design_variant = 'same_post'
      then v_stimulus.exposure_post_id else v_stimulus.target_post_id end,
    case when v_assignment.design_variant = 'same_post'
      then v_stimulus.exposure_post_body_sha256 else v_stimulus.target_post_body_sha256 end,
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
    v_gender_identity,
    v_age_years,
    v_english_proficiency,
    v_education_level,
    v_employment_status,
    v_assignment.protocol_version,
    v_comment_judgments,
    v_gist_text,
    v_gist_difficulty,
    v_phase1_ms,
    v_gist_ms,
    v_assignment.phase1_locked_at,
    v_assignment.phase2_locked_at,
    coalesce(p_payload, '{}'::jsonb) || jsonb_build_object(
      'serverAudit', jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'stimulusId', v_assignment.stimulus_id,
        'pairNumber', v_assignment.pair_number,
        'pairRole', v_stimulus.pair_role,
        'condition', v_assignment.condition,
        'isTest', v_assignment.is_test,
        'designVariant', v_assignment.design_variant,
        'postTaskMeasure', v_assignment.post_task_measure,
        'commentOrder', v_assignment.comment_order,
        'commentHashes', v_assignment.presented_comment_sha256,
        'exposurePostId', v_stimulus.exposure_post_id,
        'exposurePostSha256', v_stimulus.exposure_post_body_sha256,
        'targetPostId', v_stimulus.target_post_id,
        'targetPostSha256', v_stimulus.target_post_body_sha256,
        'responsePostId', case when v_assignment.design_variant = 'same_post'
          then v_stimulus.exposure_post_id else v_stimulus.target_post_id end,
        'responsePostSha256', case when v_assignment.design_variant = 'same_post'
          then v_stimulus.exposure_post_body_sha256 else v_stimulus.target_post_body_sha256 end,
        'serverReceivedAt', v_now
      )
    ),
    v_quota_disposition,
    v_now
  );

  if not v_assignment.is_test and v_quota_disposition = 'quota' then
    update public.advice_transfer_quota_tokens
       set state = 'pending',
           reservation_expires_at = null,
           updated_at = v_now
     where id = v_assignment.quota_token_id
       and state = 'reserved'
       and current_assignment_id = v_assignment.assignment_id;

    if not found then
      -- A late browser must never steal a token that has already been given
      -- to its replacement. The response is retained as paid standby data.
      v_quota_disposition := 'standby';
      update public.advice_transfer_submissions
         set quota_disposition = 'standby'
       where assignment_id = p_assignment_id;
      update public.advice_transfer_assignments
         set reservation_kind = 'standby',
             quota_token_id = null,
             standby_enqueued_at = coalesce(standby_enqueued_at, v_now)
       where assignment_id = p_assignment_id;
    end if;
  end if;

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

  if not v_assignment.is_test and v_quota_disposition = 'standby' then
    perform public.promote_advice_transfer_standby(
      v_assignment.stimulus_id,
      v_assignment.condition
    );
  end if;

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
  v_submission public.advice_transfer_submissions%rowtype;
  v_reopened boolean := false;
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

  perform pg_advisory_xact_lock(hashtext('advice_transfer_admission_v3'));
  perform public.reclaim_expired_advice_transfer_assignments();
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

  select * into v_submission
    from public.advice_transfer_submissions
   where assignment_id = p_assignment_id
   for update;

  if p_decision = 'valid' then
    if v_assignment.status <> 'submitted' or v_submission.id is null then
      raise exception 'Only a submitted response can be marked valid';
    end if;

    update public.advice_transfer_submissions
       set validity_status = 'valid',
           reviewed_at = v_now,
           exclusion_reason = null
     where assignment_id = p_assignment_id;

    if v_submission.quota_disposition = 'quota' then
      update public.advice_transfer_quota_tokens
         set state = 'valid',
             reservation_expires_at = null,
             updated_at = v_now
       where id = v_assignment.quota_token_id
         and current_assignment_id = p_assignment_id
         and state in ('pending', 'valid');
      if not found then
        raise exception 'A quota response could not be matched to its quota token';
      end if;
    end if;
  elsif p_decision = 'excluded' then
    if v_submission.id is null then
      raise exception 'Only a submitted response can be excluded';
    end if;

    update public.advice_transfer_submissions
       set validity_status = 'excluded',
           reviewed_at = v_now,
           exclusion_reason = p_reason
     where assignment_id = p_assignment_id;

    if v_submission.quota_disposition = 'quota' then
      update public.advice_transfer_quota_tokens
         set state = 'available',
             current_assignment_id = null,
             reservation_expires_at = null,
             updated_at = v_now
       where id = v_assignment.quota_token_id
         and current_assignment_id = p_assignment_id
         and state in ('pending', 'valid');
      v_reopened := found;
    end if;

    update public.advice_transfer_assignments
       set status = 'excluded',
           lease_expires_at = null,
           reservation_kind = 'released',
           quota_token_id = null,
           abandoned_at = null,
           abandonment_reason = p_reason,
           updated_at = v_now
     where assignment_id = p_assignment_id;
  else
    if v_assignment.status = 'submitted' then
      raise exception 'A submitted response must be marked valid or excluded';
    end if;

    update public.advice_transfer_quota_tokens
       set state = 'available',
           current_assignment_id = null,
           reservation_expires_at = null,
           updated_at = v_now
     where id = v_assignment.quota_token_id
       and current_assignment_id = p_assignment_id
       and state = 'reserved';
    v_reopened := found;

    update public.advice_transfer_assignments
       set status = 'abandoned',
           lease_expires_at = null,
           reservation_kind = 'released',
           quota_token_id = null,
           abandoned_at = v_now,
           abandonment_reason = coalesce(p_reason, 'researcher_released'),
           updated_at = v_now
     where assignment_id = p_assignment_id;
  end if;

  if v_reopened then
    perform public.promote_advice_transfer_standby(
      v_assignment.stimulus_id,
      v_assignment.condition
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'assignmentId', p_assignment_id,
    'decision', p_decision,
    'quotaReopened', v_reopened,
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

drop view if exists public.advice_transfer_formal_cell_progress;
create view public.advice_transfer_formal_cell_progress as
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
   where not assignment.is_test
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
   where not submission.is_test
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
       ) as quota_invariant_ok
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

alter table public.advice_transfer_settings enable row level security;
alter table public.advice_transfer_stimuli enable row level security;
alter table public.advice_transfer_assignments enable row level security;
alter table public.advice_transfer_submissions enable row level security;
alter table public.advice_transfer_waitlist enable row level security;
alter table public.advice_transfer_quota_tokens enable row level security;

revoke all on public.advice_transfer_settings from anon, authenticated;
revoke all on public.advice_transfer_stimuli from anon, authenticated;
revoke all on public.advice_transfer_assignments from anon, authenticated;
revoke all on public.advice_transfer_submissions from anon, authenticated;
revoke all on public.advice_transfer_waitlist from anon, authenticated;
revoke all on public.advice_transfer_quota_tokens from anon, authenticated;
revoke all on public.advice_transfer_test_cell_progress from anon, authenticated;
revoke all on public.advice_transfer_formal_cell_progress from anon, authenticated;

revoke all on function public.claim_advice_transfer_assignment(text, text, text, boolean, integer, text)
  from public;
revoke all on function public.claim_advice_transfer_assignment_v4(text, text, text, boolean, integer, text)
  from public;
revoke all on function public.claim_advice_transfer_assignment_same_post(text, text, text, boolean, integer, text)
  from public;
revoke all on function public.save_advice_transfer_stage(text, text, text, jsonb)
  from public;
revoke all on function public.advice_transfer_required_integer(jsonb, text, integer, integer)
  from public;
revoke all on function public.advice_transfer_locked_payload(public.advice_transfer_assignments, jsonb)
  from public;
revoke all on function public.guard_advice_transfer_phase_snapshots()
  from public;
revoke all on function public.set_advice_transfer_response_post_audit()
  from public;
revoke all on function public.heartbeat_advice_transfer_assignment(text, text)
  from public;
revoke all on function public.save_advice_transfer_draft(text, text, jsonb)
  from public;
revoke all on function public.withdraw_advice_transfer_assignment(text, text, text)
  from public;
revoke all on function public.mark_advice_transfer_departure(text, text)
  from public;
revoke all on function public.mark_advice_transfer_departure(text, text, jsonb)
  from public;
revoke all on function public.record_advice_transfer_comprehension_failure(text, text, jsonb)
  from public;
revoke all on function public.submit_advice_transfer_payload(text, jsonb)
  from public;
revoke all on function public.reclaim_expired_advice_transfer_assignments()
  from public;
revoke all on function public.ensure_advice_transfer_quota_tokens()
  from public;
revoke all on function public.promote_advice_transfer_standby(text, text)
  from public;
revoke all on function public.review_advice_transfer_assignment(text, text, text)
  from public;
revoke all on function public.advice_transfer_word_count(text)
  from public;
revoke all on function public.advice_transfer_remove_leading_judgment_label(text)
  from public;
revoke all on function public.advice_transfer_remove_judgment_labels(text)
  from public;
revoke all on function public.guard_advice_transfer_target_reduction()
  from public;

grant execute on function public.claim_advice_transfer_assignment(text, text, text, boolean, integer, text)
  to anon, authenticated;
grant execute on function public.claim_advice_transfer_assignment_v4(text, text, text, boolean, integer, text)
  to anon, authenticated;
grant execute on function public.claim_advice_transfer_assignment_same_post(text, text, text, boolean, integer, text)
  to anon, authenticated;
grant execute on function public.save_advice_transfer_stage(text, text, text, jsonb)
  to anon, authenticated;
grant execute on function public.heartbeat_advice_transfer_assignment(text, text)
  to anon, authenticated;
grant execute on function public.save_advice_transfer_draft(text, text, jsonb)
  to anon, authenticated;
grant execute on function public.withdraw_advice_transfer_assignment(text, text, text)
  to anon, authenticated;
grant execute on function public.mark_advice_transfer_departure(text, text)
  to anon, authenticated;
grant execute on function public.mark_advice_transfer_departure(text, text, jsonb)
  to anon, authenticated;
grant execute on function public.record_advice_transfer_comprehension_failure(text, text, jsonb)
  to anon, authenticated;
grant execute on function public.submit_advice_transfer_payload(text, jsonb)
  to anon, authenticated;

grant select, insert, update, delete on public.advice_transfer_settings to service_role;
grant select, insert, update, delete on public.advice_transfer_stimuli to service_role;
grant select, insert, update, delete on public.advice_transfer_assignments to service_role;
grant select, insert, update, delete on public.advice_transfer_submissions to service_role;
grant select, insert, update, delete on public.advice_transfer_waitlist to service_role;
grant select, insert, update, delete on public.advice_transfer_quota_tokens to service_role;
grant select on public.advice_transfer_test_cell_progress to service_role;
grant select on public.advice_transfer_formal_cell_progress to service_role;
grant execute on function public.advice_transfer_word_count(text) to service_role;
grant execute on function public.advice_transfer_remove_leading_judgment_label(text) to service_role;
grant execute on function public.advice_transfer_remove_judgment_labels(text) to service_role;
grant execute on function public.guard_advice_transfer_target_reduction() to service_role;
grant execute on function public.set_advice_transfer_response_post_audit() to service_role;
grant execute on function public.reclaim_expired_advice_transfer_assignments() to service_role;
grant execute on function public.ensure_advice_transfer_quota_tokens() to service_role;
grant execute on function public.promote_advice_transfer_standby(text, text) to service_role;
grant execute on function public.review_advice_transfer_assignment(text, text, text) to service_role;

notify pgrst, 'reload schema';
commit;
