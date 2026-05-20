-- Supabase setup for the /ratings/ Prolific study.
-- Run this in Supabase SQL Editor, then import prolific_aita_rating_batch_300.csv
-- into the public.rating_posts table.

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

create table if not exists public.rating_assignments (
  id uuid primary key default gen_random_uuid(),
  assignment_id text not null unique,
  prolific_pid text not null,
  study_id text,
  session_id text,
  post_ids text[] not null,
  posts_per_worker integer not null default 5,
  status text not null default 'claimed',
  created_at timestamptz not null default now(),
  submitted_at timestamptz
);

create unique index if not exists rating_assignments_participant_session_idx
  on public.rating_assignments (
    prolific_pid,
    coalesce(study_id, ''),
    coalesce(session_id, '')
  );

create table if not exists public.rating_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id text not null references public.rating_assignments(assignment_id),
  prolific_pid text,
  study_id text,
  session_id text,
  attention_check text,
  payload jsonb not null,
  submitted_at timestamptz not null default now()
);

create unique index if not exists rating_submissions_assignment_id_idx
  on public.rating_submissions (assignment_id);

alter table public.rating_posts enable row level security;
alter table public.rating_assignments enable row level security;
alter table public.rating_submissions enable row level security;

revoke all on public.rating_posts from anon, authenticated;
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
    with assignment_counts as (
      select
        p.task_id,
        count(a.id) as assigned_count
      from public.rating_posts p
      left join public.rating_assignments a
        on p.task_id = any(a.post_ids)
       and a.status in ('claimed', 'submitted')
      group by p.task_id
    ),
    selected_posts as (
      select p.task_id
      from public.rating_posts p
      join assignment_counts c on c.task_id = p.task_id
      where c.assigned_count < p_max_assignments_per_post
      order by c.assigned_count asc, random()
      limit p_posts_per_worker
    )
    select array_agg(task_id)
      into v_post_ids
      from selected_posts;

    if coalesce(array_length(v_post_ids, 1), 0) < p_posts_per_worker then
      raise exception 'Not enough available posts for assignment';
    end if;

    v_assignment_id := 'rating-' || p_prolific_pid || '-' || substr(gen_random_uuid()::text, 1, 8);

    insert into public.rating_assignments (
      assignment_id,
      prolific_pid,
      study_id,
      session_id,
      post_ids,
      posts_per_worker
    )
    values (
      v_assignment_id,
      p_prolific_pid,
      p_study_id,
      p_session_id,
      v_post_ids,
      p_posts_per_worker
    )
    returning * into v_assignment;
  else
    v_post_ids := v_assignment.post_ids;
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
    'posts', coalesce(v_posts, '[]'::jsonb)
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
begin
  if nullif(trim(p_assignment_id), '') is null then
    raise exception 'Missing assignment id';
  end if;

  if p_payload is null then
    raise exception 'Missing payload';
  end if;

  v_prolific_pid := p_payload #>> '{participant,prolificPid}';
  v_study_id := p_payload #>> '{participant,studyId}';
  v_session_id := p_payload #>> '{participant,sessionId}';
  v_attention_check := p_payload ->> 'attentionCheck';

  insert into public.rating_submissions (
    assignment_id,
    prolific_pid,
    study_id,
    session_id,
    attention_check,
    payload,
    submitted_at
  )
  values (
    p_assignment_id,
    v_prolific_pid,
    v_study_id,
    v_session_id,
    v_attention_check,
    p_payload,
    now()
  )
  on conflict (assignment_id) do update
    set prolific_pid = excluded.prolific_pid,
        study_id = excluded.study_id,
        session_id = excluded.session_id,
        attention_check = excluded.attention_check,
        payload = excluded.payload,
        submitted_at = excluded.submitted_at;

  update public.rating_assignments
     set status = 'submitted',
         submitted_at = now()
   where assignment_id = p_assignment_id;

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
grant execute on function public.submit_rating_payload(text, jsonb) to anon, authenticated;
