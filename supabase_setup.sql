-- Supabase setup for the /ratings/ Prolific study.
-- Run this in Supabase SQL Editor, then import the generated
-- supabase_import/full153k_v1/rating_posts_import_full153k_v1.csv file into
-- public.rating_posts, then import
-- supabase_import/full153k_v1/rating_assignment_slots_import_full153k_v1.csv
-- into public.rating_assignment_slots.

create extension if not exists pgcrypto;

create table if not exists public.rating_posts (
  task_id text primary key,
  submission_id text not null unique,
  sampling_level text not null,
  sampling_level_label text,
  rank_within_level integer,
  reddit_score integer,
  dominant_verdict text,
  top_comment_verdicts text,
  title text not null,
  body text not null,
  post_text text,
  month text,
  created_at timestamptz not null default now()
);

create table if not exists public.rating_assignment_slots (
  id uuid primary key default gen_random_uuid(),
  slot_id text not null unique,
  slot_index integer not null unique,
  pattern text not null check (pattern in ('A', 'B', 'C')),
  post_ids text[] not null,
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (
    status in ('open', 'claimed', 'submitted')
  ),
  assignment_id text unique,
  claimed_at timestamptz,
  submitted_at timestamptz,
  screened_out_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.rating_assignment_slots
  add column if not exists pattern text;

alter table public.rating_assignment_slots
  add column if not exists metadata jsonb not null default '{}'::jsonb;

alter table public.rating_assignment_slots
  add column if not exists assignment_id text;

alter table public.rating_assignment_slots
  add column if not exists claimed_at timestamptz;

alter table public.rating_assignment_slots
  add column if not exists submitted_at timestamptz;

alter table public.rating_assignment_slots
  add column if not exists screened_out_at timestamptz;

create index if not exists rating_assignment_slots_status_idx
  on public.rating_assignment_slots (status, slot_index);

create unique index if not exists rating_assignment_slots_assignment_id_idx
  on public.rating_assignment_slots (assignment_id)
  where assignment_id is not null;

create table if not exists public.rating_assignments (
  id uuid primary key default gen_random_uuid(),
  assignment_id text not null unique,
  prolific_pid text not null,
  study_id text,
  session_id text,
  slot_id text,
  post_ids text[] not null,
  posts_per_worker integer not null default 5,
  comprehension_failures integer not null default 0,
  last_comprehension_failure_at timestamptz,
  last_comprehension_failure_option text,
  status text not null default 'claimed',
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  screened_out_at timestamptz
);

alter table public.rating_assignments
  add column if not exists comprehension_failures integer not null default 0;

alter table public.rating_assignments
  add column if not exists last_comprehension_failure_at timestamptz;

alter table public.rating_assignments
  add column if not exists last_comprehension_failure_option text;

alter table public.rating_assignments
  add column if not exists screened_out_at timestamptz;

alter table public.rating_assignments
  add column if not exists slot_id text;

create unique index if not exists rating_assignments_participant_session_idx
  on public.rating_assignments (
    prolific_pid,
    coalesce(study_id, ''),
    coalesce(session_id, '')
  );

drop index if exists public.rating_assignments_slot_id_idx;

create index if not exists rating_assignments_slot_id_idx
  on public.rating_assignments (slot_id)
  where slot_id is not null;

create table if not exists public.rating_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id text not null references public.rating_assignments(assignment_id),
  prolific_pid text,
  study_id text,
  session_id text,
  attention_check text,
  post_task_disagreement_difficulty integer,
  post_task_study_purpose text,
  payload jsonb not null,
  submitted_at timestamptz not null default now()
);

create unique index if not exists rating_submissions_assignment_id_idx
  on public.rating_submissions (assignment_id);

alter table public.rating_submissions
  add column if not exists post_task_disagreement_difficulty integer;

alter table public.rating_submissions
  add column if not exists post_task_study_purpose text;

alter table public.rating_posts enable row level security;
alter table public.rating_assignment_slots enable row level security;
alter table public.rating_assignments enable row level security;
alter table public.rating_submissions enable row level security;

revoke all on public.rating_posts from anon, authenticated;
revoke all on public.rating_assignment_slots from anon, authenticated;
revoke all on public.rating_assignments from anon, authenticated;
revoke all on public.rating_submissions from anon, authenticated;

create or replace function public.claim_rating_assignment(
  p_prolific_pid text,
  p_study_id text default null,
  p_session_id text default null,
  p_posts_per_worker integer default 5,
  p_completion_code text default 'RATING2026',
  p_contact_email text default 'william.brady@kellogg.northwestern.edu',
  p_max_assignments_per_post integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.rating_assignments%rowtype;
  v_slot public.rating_assignment_slots%rowtype;
  v_assignment_id text;
  v_post_ids text[];
  v_posts jsonb;
begin
  if nullif(trim(p_prolific_pid), '') is null then
    raise exception 'Missing PROLIFIC_PID';
  end if;

  if p_posts_per_worker is null or p_posts_per_worker < 1 then
    p_posts_per_worker := 5;
  end if;

  perform pg_advisory_xact_lock(hashtext('aita_rating_assignment'));

  select *
    into v_assignment
    from public.rating_assignments
   where prolific_pid = p_prolific_pid
     and coalesce(study_id, '') = coalesce(p_study_id, '')
     and coalesce(session_id, '') = coalesce(p_session_id, '')
   order by created_at desc
   limit 1;

  if v_assignment.id is null then
    select *
      into v_slot
      from public.rating_assignment_slots
     where status = 'open'
       and coalesce(array_length(post_ids, 1), 0) = p_posts_per_worker
     order by slot_index asc
     for update skip locked
     limit 1;

    if v_slot.id is null then
      raise exception 'No available rating assignment slots';
    end if;

    v_post_ids := v_slot.post_ids;
    v_assignment_id := 'rating-' || p_prolific_pid || '-' || substr(gen_random_uuid()::text, 1, 8);

    insert into public.rating_assignments (
      assignment_id,
      prolific_pid,
      study_id,
      session_id,
      slot_id,
      post_ids,
      posts_per_worker
    )
    values (
      v_assignment_id,
      p_prolific_pid,
      p_study_id,
      p_session_id,
      v_slot.slot_id,
      v_post_ids,
      p_posts_per_worker
    )
    returning * into v_assignment;

    update public.rating_assignment_slots
       set status = 'claimed',
           assignment_id = v_assignment.assignment_id,
           claimed_at = now(),
           submitted_at = null,
           screened_out_at = null
     where slot_id = v_slot.slot_id;
  else
    v_post_ids := v_assignment.post_ids;
    if v_assignment.slot_id is not null then
      select *
        into v_slot
        from public.rating_assignment_slots
       where slot_id = v_assignment.slot_id
       limit 1;
    end if;
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'id', p.task_id,
      'title', p.title,
      'body', p.body,
      'sourceBin', p.sampling_level,
      'metadata', jsonb_build_object(
        'submissionId', p.submission_id,
        'samplingLevel', p.sampling_level,
        'samplingLevelLabel', p.sampling_level_label,
        'rankWithinLevel', p.rank_within_level,
        'redditScore', p.reddit_score,
        'dominantVerdict', p.dominant_verdict,
        'topCommentVerdicts', p.top_comment_verdicts,
        'month', p.month
      )
    )
    order by array_position(v_post_ids, p.task_id)
  )
  into v_posts
  from public.rating_posts p
  where p.task_id = any(v_post_ids);

  return jsonb_build_object(
    'assignmentId', v_assignment.assignment_id,
    'completionCode', p_completion_code,
    'contactEmail', p_contact_email,
    'slotId', v_assignment.slot_id,
    'slotIndex', v_slot.slot_index,
    'assignmentPattern', v_slot.pattern,
    'status', v_assignment.status,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'screenedOutAt', v_assignment.screened_out_at,
    'posts', coalesce(v_posts, '[]'::jsonb)
  );
end;
$$;

create or replace function public.record_rating_comprehension_failure(
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
  v_assignment public.rating_assignments%rowtype;
begin
  if nullif(trim(p_assignment_id), '') is null then
    raise exception 'Missing assignment id';
  end if;

  select *
    into v_assignment
    from public.rating_assignments
   where assignment_id = p_assignment_id
   limit 1;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;

  if v_assignment.status = 'submitted' then
    return jsonb_build_object(
      'ok', true,
      'assignmentId', v_assignment.assignment_id,
      'status', v_assignment.status,
      'comprehensionFailures', v_assignment.comprehension_failures,
      'screenedOut', false
    );
  end if;

  if v_assignment.status = 'screened_out' then
    return jsonb_build_object(
      'ok', true,
      'assignmentId', v_assignment.assignment_id,
      'status', v_assignment.status,
      'comprehensionFailures', v_assignment.comprehension_failures,
      'screenedOut', true
    );
  end if;

  update public.rating_assignments
     set comprehension_failures = comprehension_failures + 1,
         last_comprehension_failure_at = now(),
         last_comprehension_failure_option = p_selected_option,
         status = case
           when comprehension_failures + 1 >= 2 then 'screened_out'
           else status
         end,
         screened_out_at = case
           when comprehension_failures + 1 >= 2 then coalesce(screened_out_at, now())
           else screened_out_at
         end
   where assignment_id = p_assignment_id
   returning * into v_assignment;

  if v_assignment.status = 'screened_out' and v_assignment.slot_id is not null then
    update public.rating_assignment_slots
       set status = 'open',
           assignment_id = null,
           claimed_at = null,
           submitted_at = null,
           screened_out_at = now()
     where slot_id = v_assignment.slot_id
       and assignment_id = v_assignment.assignment_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'assignmentId', v_assignment.assignment_id,
    'status', v_assignment.status,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'screenedOut', v_assignment.status = 'screened_out'
  );
end;
$$;

create or replace function public.submit_rating_payload(
  p_assignment_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prolific_pid text;
  v_study_id text;
  v_session_id text;
  v_attention_check text;
  v_post_task_disagreement_difficulty integer;
  v_post_task_study_purpose text;
  v_assignment_status text;
  v_slot_id text;
begin
  if nullif(trim(p_assignment_id), '') is null then
    raise exception 'Missing assignment id';
  end if;

  if p_payload is null then
    raise exception 'Missing payload';
  end if;

  select status, slot_id
    into v_assignment_status, v_slot_id
    from public.rating_assignments
   where assignment_id = p_assignment_id
   limit 1;

  if v_assignment_status is null then
    raise exception 'Assignment not found';
  end if;

  if v_assignment_status = 'screened_out' then
    raise exception 'Assignment has been screened out';
  end if;

  v_prolific_pid := p_payload #>> '{participant,prolificPid}';
  v_study_id := p_payload #>> '{participant,studyId}';
  v_session_id := p_payload #>> '{participant,sessionId}';
  v_attention_check := p_payload ->> 'attentionCheck';
  v_post_task_disagreement_difficulty :=
    nullif(p_payload #>> '{postTaskResponses,disagreementDifficulty}', '')::integer;
  v_post_task_study_purpose :=
    nullif(p_payload #>> '{postTaskResponses,studyPurpose}', '');

  insert into public.rating_submissions (
    assignment_id,
    prolific_pid,
    study_id,
    session_id,
    attention_check,
    post_task_disagreement_difficulty,
    post_task_study_purpose,
    payload,
    submitted_at
  )
  values (
    p_assignment_id,
    v_prolific_pid,
    v_study_id,
    v_session_id,
    v_attention_check,
    v_post_task_disagreement_difficulty,
    v_post_task_study_purpose,
    p_payload,
    now()
  )
  on conflict (assignment_id) do update
    set prolific_pid = excluded.prolific_pid,
        study_id = excluded.study_id,
        session_id = excluded.session_id,
        attention_check = excluded.attention_check,
        post_task_disagreement_difficulty =
          excluded.post_task_disagreement_difficulty,
        post_task_study_purpose = excluded.post_task_study_purpose,
        payload = excluded.payload,
        submitted_at = excluded.submitted_at;

  update public.rating_assignments
     set status = 'submitted',
         submitted_at = now()
   where assignment_id = p_assignment_id;

  if v_slot_id is not null then
    update public.rating_assignment_slots
       set status = 'submitted',
           submitted_at = now()
     where slot_id = v_slot_id
       and assignment_id = p_assignment_id;
  end if;

  return jsonb_build_object('ok', true, 'assignmentId', p_assignment_id);
end;
$$;

grant usage on schema public to anon, authenticated;
grant execute on function public.claim_rating_assignment(
  text,
  text,
  text,
  integer,
  text,
  text,
  integer
) to anon, authenticated;
grant execute on function public.record_rating_comprehension_failure(text, text, jsonb) to anon, authenticated;
grant execute on function public.submit_rating_payload(text, jsonb) to anon, authenticated;
