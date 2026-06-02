-- Supabase setup for the /advice/ Prolific one-shot exposure study.
-- Run this in Supabase SQL Editor, then import pilot stimuli into
-- public.advice_stimuli and balanced participant slots into public.advice_slots.

create extension if not exists pgcrypto;

create table if not exists public.advice_stimuli (
  stimulus_id text primary key,
  exposure_title text not null,
  exposure_body text not null,
  friend_title text not null,
  friend_body text not null,
  moral_theme_metadata jsonb not null default '{}'::jsonb,
  human_comments jsonb not null default '[]'::jsonb,
  llm_comments jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  constraint advice_stimuli_human_comments_array
    check (jsonb_typeof(human_comments) = 'array'),
  constraint advice_stimuli_llm_comments_array
    check (jsonb_typeof(llm_comments) = 'array')
);

create table if not exists public.advice_slots (
  id uuid primary key default gen_random_uuid(),
  slot_id text not null unique,
  stimulus_id text not null references public.advice_stimuli(stimulus_id),
  condition text not null check (condition in ('human_comments', 'llm_comments')),
  slot_index integer not null,
  status text not null default 'open' check (status in ('open', 'claimed', 'submitted')),
  assignment_id text unique,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  submitted_at timestamptz,
  unique (stimulus_id, condition, slot_index)
);

create index if not exists advice_slots_status_condition_idx
  on public.advice_slots (status, condition);

create table if not exists public.advice_assignments (
  id uuid primary key default gen_random_uuid(),
  assignment_id text not null unique,
  prolific_pid text not null,
  study_id text,
  session_id text,
  slot_id text references public.advice_slots(slot_id),
  comprehension_failures integer not null default 0,
  last_comprehension_failure_at timestamptz,
  last_comprehension_failure_option text,
  status text not null default 'claimed'
    check (status in ('claimed', 'submitted', 'screened_out')),
  created_at timestamptz not null default now(),
  submitted_at timestamptz,
  screened_out_at timestamptz
);

create unique index if not exists advice_assignments_participant_session_idx
  on public.advice_assignments (
    prolific_pid,
    coalesce(study_id, ''),
    coalesce(session_id, '')
  );

create table if not exists public.advice_submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id text not null references public.advice_assignments(assignment_id),
  slot_id text,
  prolific_pid text,
  study_id text,
  session_id text,
  stimulus_id text,
  condition text,
  advice_text text,
  advice_char_count integer,
  ease integer,
  fluency integer,
  confidence integer,
  payload jsonb not null,
  submitted_at timestamptz not null default now()
);

create unique index if not exists advice_submissions_assignment_id_idx
  on public.advice_submissions (assignment_id);

alter table public.advice_stimuli enable row level security;
alter table public.advice_slots enable row level security;
alter table public.advice_assignments enable row level security;
alter table public.advice_submissions enable row level security;

revoke all on public.advice_stimuli from anon, authenticated;
revoke all on public.advice_slots from anon, authenticated;
revoke all on public.advice_assignments from anon, authenticated;
revoke all on public.advice_submissions from anon, authenticated;

create or replace function public.claim_advice_assignment(
  p_prolific_pid text,
  p_study_id text default null,
  p_session_id text default null,
  p_completion_code text default 'ADVICE2026',
  p_contact_email text default 'william.brady@kellogg.northwestern.edu',
  p_feed_size integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_assignments%rowtype;
  v_slot public.advice_slots%rowtype;
  v_stimulus public.advice_stimuli%rowtype;
  v_assignment_id text;
  v_comments jsonb;
begin
  if nullif(trim(p_prolific_pid), '') is null then
    raise exception 'Missing PROLIFIC_PID';
  end if;

  if p_feed_size is null or p_feed_size < 1 then
    p_feed_size := 5;
  end if;

  perform pg_advisory_xact_lock(hashtext('advice_assignment'));

  select *
    into v_assignment
    from public.advice_assignments
   where prolific_pid = p_prolific_pid
     and coalesce(study_id, '') = coalesce(p_study_id, '')
     and coalesce(session_id, '') = coalesce(p_session_id, '')
   order by created_at desc
   limit 1;

  if v_assignment.id is null then
    with condition_counts as (
      select
        s.condition,
        count(*) filter (where s.status in ('claimed', 'submitted')) as assigned_count
      from public.advice_slots s
      group by s.condition
    )
    select s.*
      into v_slot
      from public.advice_slots s
      join public.advice_stimuli st
        on st.stimulus_id = s.stimulus_id
      left join condition_counts c
        on c.condition = s.condition
     where s.status = 'open'
       and st.active = true
       and jsonb_array_length(
         case
           when s.condition = 'human_comments' then st.human_comments
           else st.llm_comments
         end
       ) >= p_feed_size
     order by coalesce(c.assigned_count, 0) asc, random()
     limit 1;

    if v_slot.id is null then
      raise exception 'No available advice assignment slots';
    end if;

    v_assignment_id :=
      'advice-' || p_prolific_pid || '-' || substr(gen_random_uuid()::text, 1, 8);

    insert into public.advice_assignments (
      assignment_id,
      prolific_pid,
      study_id,
      session_id,
      slot_id
    )
    values (
      v_assignment_id,
      p_prolific_pid,
      p_study_id,
      p_session_id,
      v_slot.slot_id
    )
    returning * into v_assignment;

    update public.advice_slots
       set status = 'claimed',
           assignment_id = v_assignment.assignment_id,
           claimed_at = now()
     where slot_id = v_slot.slot_id
     returning * into v_slot;
  else
    select *
      into v_slot
      from public.advice_slots
     where slot_id = v_assignment.slot_id
     limit 1;
  end if;

  if v_slot.id is null then
    raise exception 'Assignment slot not found';
  end if;

  select *
    into v_stimulus
    from public.advice_stimuli
   where stimulus_id = v_slot.stimulus_id
   limit 1;

  if v_stimulus.stimulus_id is null then
    raise exception 'Stimulus not found';
  end if;

  select coalesce(jsonb_agg(comment_value order by comment_order), '[]'::jsonb)
    into v_comments
    from (
      select value as comment_value, ordinality as comment_order
      from jsonb_array_elements(
        case
          when v_slot.condition = 'human_comments' then v_stimulus.human_comments
          else v_stimulus.llm_comments
        end
      ) with ordinality
      where ordinality <= p_feed_size
    ) comments;

  return jsonb_build_object(
    'assignmentId', v_assignment.assignment_id,
    'completionCode', p_completion_code,
    'contactEmail', p_contact_email,
    'status', v_assignment.status,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'screenedOutAt', v_assignment.screened_out_at,
    'slotId', v_slot.slot_id,
    'condition', v_slot.condition,
    'stimulus', jsonb_build_object(
      'id', v_stimulus.stimulus_id,
      'exposureTitle', v_stimulus.exposure_title,
      'exposureBody', v_stimulus.exposure_body,
      'friendTitle', v_stimulus.friend_title,
      'friendBody', v_stimulus.friend_body,
      'moralThemeMetadata', v_stimulus.moral_theme_metadata
    ),
    'comments', v_comments
  );
end;
$$;

create or replace function public.record_advice_comprehension_failure(
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
  v_assignment public.advice_assignments%rowtype;
begin
  if nullif(trim(p_assignment_id), '') is null then
    raise exception 'Missing assignment id';
  end if;

  select *
    into v_assignment
    from public.advice_assignments
   where assignment_id = p_assignment_id
   for update;

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

  update public.advice_assignments
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

  if v_assignment.status = 'screened_out' then
    update public.advice_slots
       set status = 'open',
           assignment_id = null,
           claimed_at = null
     where slot_id = v_assignment.slot_id
       and status = 'claimed';
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

create or replace function public.submit_advice_payload(
  p_assignment_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.advice_assignments%rowtype;
  v_prolific_pid text;
  v_study_id text;
  v_session_id text;
  v_slot_id text;
  v_condition text;
  v_stimulus_id text;
  v_advice_text text;
  v_advice_char_count integer;
  v_ease integer;
  v_fluency integer;
  v_confidence integer;
begin
  if nullif(trim(p_assignment_id), '') is null then
    raise exception 'Missing assignment id';
  end if;

  if p_payload is null then
    raise exception 'Missing payload';
  end if;

  select *
    into v_assignment
    from public.advice_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;

  if v_assignment.status = 'screened_out' then
    raise exception 'Assignment has been screened out';
  end if;

  v_prolific_pid := p_payload #>> '{participant,prolificPid}';
  v_study_id := p_payload #>> '{participant,studyId}';
  v_session_id := p_payload #>> '{participant,sessionId}';
  select slot_id, condition, stimulus_id
    into v_slot_id, v_condition, v_stimulus_id
    from public.advice_slots
   where slot_id = v_assignment.slot_id
   limit 1;

  if v_slot_id is null then
    raise exception 'Assignment slot not found';
  end if;

  v_advice_text := nullif(p_payload #>> '{response,adviceText}', '');
  v_advice_char_count := nullif(p_payload #>> '{response,adviceCharCount}', '')::integer;
  v_ease := nullif(p_payload #>> '{postTask,ease}', '')::integer;
  v_fluency := nullif(p_payload #>> '{postTask,fluency}', '')::integer;
  v_confidence := nullif(p_payload #>> '{postTask,confidence}', '')::integer;

  insert into public.advice_submissions (
    assignment_id,
    slot_id,
    prolific_pid,
    study_id,
    session_id,
    stimulus_id,
    condition,
    advice_text,
    advice_char_count,
    ease,
    fluency,
    confidence,
    payload,
    submitted_at
  )
  values (
    p_assignment_id,
    v_slot_id,
    v_prolific_pid,
    v_study_id,
    v_session_id,
    v_stimulus_id,
    v_condition,
    v_advice_text,
    v_advice_char_count,
    v_ease,
    v_fluency,
    v_confidence,
    p_payload,
    now()
  )
  on conflict (assignment_id) do update
    set slot_id = excluded.slot_id,
        prolific_pid = excluded.prolific_pid,
        study_id = excluded.study_id,
        session_id = excluded.session_id,
        stimulus_id = excluded.stimulus_id,
        condition = excluded.condition,
        advice_text = excluded.advice_text,
        advice_char_count = excluded.advice_char_count,
        ease = excluded.ease,
        fluency = excluded.fluency,
        confidence = excluded.confidence,
        payload = excluded.payload,
        submitted_at = excluded.submitted_at;

  update public.advice_assignments
     set status = 'submitted',
         submitted_at = now()
   where assignment_id = p_assignment_id;

  update public.advice_slots
     set status = 'submitted',
         submitted_at = now()
   where slot_id = v_assignment.slot_id;

  return jsonb_build_object('ok', true, 'assignmentId', p_assignment_id);
end;
$$;

grant usage on schema public to anon, authenticated;
grant execute on function public.claim_advice_assignment(
  text,
  text,
  text,
  text,
  text,
  integer
) to anon, authenticated;
grant execute on function public.record_advice_comprehension_failure(
  text,
  text,
  jsonb
) to anon, authenticated;
grant execute on function public.submit_advice_payload(text, jsonb)
  to anon, authenticated;
