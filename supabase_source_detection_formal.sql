-- Formal 10-post x 2-source allocation for the /comment-source/ Prolific study.
-- Prerequisite: run the original source-detection schema and 13-post seed first.
-- This migration is idempotent and preserves existing assignments/submissions.

begin;

-- Only the ten preregistered primary stimuli are eligible for formal allocation.
update public.source_detection_stimuli
   set active = (pair_role = 'primary'),
       updated_at = now();

create table if not exists public.source_detection_slots (
  id uuid primary key default gen_random_uuid(),
  slot_id text not null unique,
  stimulus_id text not null references public.source_detection_stimuli(stimulus_id),
  condition text not null check (condition in ('human', 'ai')),
  slot_index integer not null check (slot_index between 1 and 5),
  status text not null default 'open'
    check (status in ('open', 'claimed', 'submitted')),
  assignment_id text unique,
  claimed_at timestamptz,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (stimulus_id, condition, slot_index)
);

insert into public.source_detection_slots (
  slot_id,
  stimulus_id,
  condition,
  slot_index
)
select
  'source-' || s.stimulus_id || '-' || c.condition || '-' ||
    lpad(slot_number::text, 2, '0'),
  s.stimulus_id,
  c.condition,
  slot_number
from public.source_detection_stimuli s
cross join (values ('human'::text), ('ai'::text)) as c(condition)
cross join generate_series(1, 5) as slots(slot_number)
where s.pair_role = 'primary'
on conflict (stimulus_id, condition, slot_index) do nothing;

alter table public.source_detection_assignments
  add column if not exists slot_id text;

alter table public.source_detection_assignments
  add column if not exists comprehension_failures integer not null default 0;

alter table public.source_detection_assignments
  add column if not exists last_comprehension_failure_at timestamptz;

alter table public.source_detection_assignments
  add column if not exists last_comprehension_failure_option text;

alter table public.source_detection_assignments
  add column if not exists screened_out_at timestamptz;

alter table public.source_detection_assignments
  add column if not exists exclusion_reason text;

alter table public.source_detection_assignments
  add column if not exists excluded_at timestamptz;

alter table public.source_detection_assignments
  drop constraint if exists source_detection_assignments_status_check;

alter table public.source_detection_assignments
  add constraint source_detection_assignments_status_check
  check (status in ('claimed', 'submitted', 'screened_out', 'excluded', 'abandoned'));

do $$
begin
  if not exists (
    select 1
      from pg_constraint
     where conname = 'source_detection_assignments_slot_id_fkey'
       and conrelid = 'public.source_detection_assignments'::regclass
  ) then
    alter table public.source_detection_assignments
      add constraint source_detection_assignments_slot_id_fkey
      foreign key (slot_id) references public.source_detection_slots(slot_id);
  end if;
end;
$$;

alter table public.source_detection_submissions
  add column if not exists slot_id text;

alter table public.source_detection_submissions
  add column if not exists validity_status text not null default 'pending';

alter table public.source_detection_submissions
  add column if not exists reviewed_at timestamptz;

alter table public.source_detection_submissions
  add column if not exists exclusion_reason text;

alter table public.source_detection_submissions
  drop constraint if exists source_detection_submissions_validity_status_check;

alter table public.source_detection_submissions
  add constraint source_detection_submissions_validity_status_check
  check (validity_status in ('pending', 'valid', 'excluded'));

create index if not exists source_detection_slots_status_cell_idx
  on public.source_detection_slots (status, stimulus_id, condition);

create index if not exists source_detection_assignments_slot_idx
  on public.source_detection_assignments (slot_id)
  where slot_id is not null;

alter table public.source_detection_slots enable row level security;
revoke all on public.source_detection_slots from anon, authenticated;

create or replace function public.claim_source_detection_assignment(
  p_prolific_pid text,
  p_study_id text default null,
  p_session_id text default null,
  p_is_test boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.source_detection_assignments%rowtype;
  v_slot public.source_detection_slots%rowtype;
  v_stimulus public.source_detection_stimuli%rowtype;
  v_assignment_id text;
  v_selected_stimulus_id text;
  v_selected_condition text;
  v_comment_order jsonb;
  v_source_comments jsonb;
  v_source_hashes jsonb;
  v_ordered_comments jsonb;
  v_ordered_hashes jsonb;
  v_result jsonb;
begin
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  p_study_id := nullif(trim(p_study_id), '');
  p_session_id := nullif(trim(p_session_id), '');

  if p_prolific_pid is null then
    raise exception 'Missing PROLIFIC_PID';
  end if;

  perform pg_advisory_xact_lock(hashtext('source_detection_assignment'));

  select *
    into v_assignment
    from public.source_detection_assignments
   where prolific_pid = p_prolific_pid
     and coalesce(study_id, '') = coalesce(p_study_id, '')
     and coalesce(session_id, '') = coalesce(p_session_id, '')
   order by created_at desc
   limit 1;

  if v_assignment.id is not null
     and v_assignment.status in ('excluded', 'abandoned') then
    raise exception 'This research session is no longer active';
  end if;

  if v_assignment.id is null then
    if coalesce(p_is_test, false) then
      -- Test/preview IDs never consume one of the 100 formal quota slots.
      with cells as (
        select s.stimulus_id, c.condition
          from public.source_detection_stimuli s
          cross join (values ('human'::text), ('ai'::text)) as c(condition)
         where s.active = true
           and s.pair_role = 'primary'
      ),
      cell_counts as (
        select stimulus_id, condition, count(*) as assigned_count
          from public.source_detection_assignments
         where is_test = true
           and status in ('claimed', 'submitted')
         group by stimulus_id, condition
      )
      select c.stimulus_id, c.condition
        into v_selected_stimulus_id, v_selected_condition
        from cells c
        left join cell_counts counts
          on counts.stimulus_id = c.stimulus_id
         and counts.condition = c.condition
       order by coalesce(counts.assigned_count, 0) asc, random()
       limit 1;
    else
      -- Formal participants draw from exactly five slots in each of 20 cells.
      with cell_counts as (
        select
          stimulus_id,
          condition,
          count(*) filter (where status in ('claimed', 'submitted')) as occupied_count
        from public.source_detection_slots
        group by stimulus_id, condition
      )
      select slots.*
        into v_slot
        from public.source_detection_slots slots
        join public.source_detection_stimuli stimuli
          on stimuli.stimulus_id = slots.stimulus_id
        left join cell_counts counts
          on counts.stimulus_id = slots.stimulus_id
         and counts.condition = slots.condition
       where slots.status = 'open'
         and stimuli.active = true
         and stimuli.pair_role = 'primary'
       order by coalesce(counts.occupied_count, 0) asc, random(), slots.slot_index
       for update of slots skip locked
       limit 1;

      v_selected_stimulus_id := v_slot.stimulus_id;
      v_selected_condition := v_slot.condition;
    end if;

    if v_selected_stimulus_id is null then
      raise exception 'No available source-detection assignment slots';
    end if;

    select jsonb_agg(comment_index order by random())
      into v_comment_order
      from generate_series(0, 4) as indexes(comment_index);

    v_assignment_id := 'source-' || replace(gen_random_uuid()::text, '-', '');

    insert into public.source_detection_assignments (
      assignment_id,
      prolific_pid,
      study_id,
      session_id,
      stimulus_id,
      condition,
      comment_order,
      is_test,
      slot_id
    )
    values (
      v_assignment_id,
      p_prolific_pid,
      p_study_id,
      p_session_id,
      v_selected_stimulus_id,
      v_selected_condition,
      v_comment_order,
      coalesce(p_is_test, false),
      case when coalesce(p_is_test, false) then null else v_slot.slot_id end
    )
    returning * into v_assignment;

    if not coalesce(p_is_test, false) then
      update public.source_detection_slots
         set status = 'claimed',
             assignment_id = v_assignment.assignment_id,
             claimed_at = now(),
             submitted_at = null
       where slot_id = v_slot.slot_id
       returning * into v_slot;
    end if;
  end if;

  select *
    into v_stimulus
    from public.source_detection_stimuli
   where stimulus_id = v_assignment.stimulus_id
   limit 1;

  if v_stimulus.stimulus_id is null then
    raise exception 'Assigned stimulus is unavailable';
  end if;

  v_source_comments := case
    when v_assignment.condition = 'human' then v_stimulus.human_comments
    else v_stimulus.ai_comments
  end;
  v_source_hashes := case
    when v_assignment.condition = 'human' then v_stimulus.human_comment_sha256
    else v_stimulus.ai_comment_sha256
  end;

  select
    jsonb_agg(v_source_comments -> ordered.index_text::integer order by ordered.position),
    jsonb_agg(v_source_hashes -> ordered.index_text::integer order by ordered.position)
    into v_ordered_comments, v_ordered_hashes
    from jsonb_array_elements_text(v_assignment.comment_order)
      with ordinality as ordered(index_text, position);

  v_result := jsonb_build_object(
    'assignmentId', v_assignment.assignment_id,
    'status', v_assignment.status,
    'submittedAt', v_assignment.submitted_at,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'screenedOutAt', v_assignment.screened_out_at,
    'pairNumber', v_stimulus.pair_number,
    'pairRole', v_stimulus.pair_role,
    'postId', v_stimulus.stimulus_id,
    'postTitle', v_stimulus.post_title,
    'postBody', v_stimulus.post_body,
    'postBodySha256', v_stimulus.post_body_sha256,
    'comments', coalesce(v_ordered_comments, '[]'::jsonb),
    'commentHashes', coalesce(v_ordered_hashes, '[]'::jsonb),
    'commentOrder', v_assignment.comment_order
  );

  -- Source condition is omitted for formal participants, including from the
  -- network response. Researchers can reveal it only with a test/preview ID.
  if v_assignment.is_test then
    v_result := v_result || jsonb_build_object(
      'debugCondition', v_assignment.condition
    );
  end if;

  return v_result;
end;
$$;

create or replace function public.record_source_detection_comprehension_failure(
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
  v_assignment public.source_detection_assignments%rowtype;
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  p_selected_option := nullif(trim(p_selected_option), '');

  if p_assignment_id is null then
    raise exception 'Missing assignment id';
  end if;
  if p_selected_option is null then
    raise exception 'Missing selected option';
  end if;

  perform pg_advisory_xact_lock(hashtext('source_detection_assignment'));

  select *
    into v_assignment
    from public.source_detection_assignments
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

  if v_assignment.status = 'screened_out' then
    return jsonb_build_object(
      'ok', true,
      'assignmentId', v_assignment.assignment_id,
      'status', v_assignment.status,
      'comprehensionFailures', v_assignment.comprehension_failures,
      'screenedOut', true
    );
  end if;

  if v_assignment.status in ('excluded', 'abandoned') then
    raise exception 'This research session is no longer active';
  end if;

  update public.source_detection_assignments
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

  if v_assignment.status = 'screened_out'
     and v_assignment.slot_id is not null then
    update public.source_detection_slots
       set status = 'open',
           assignment_id = null,
           claimed_at = null,
           submitted_at = null
     where slot_id = v_assignment.slot_id
       and assignment_id = v_assignment.assignment_id
       and status = 'claimed';
  end if;

  return jsonb_build_object(
    'ok', true,
    'assignmentId', v_assignment.assignment_id,
    'status', v_assignment.status,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'screenedOut', v_assignment.status = 'screened_out',
    'slotReopened', v_assignment.status = 'screened_out'
      and v_assignment.slot_id is not null
  );
end;
$$;

create or replace function public.submit_source_detection_payload(
  p_assignment_id text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_assignment public.source_detection_assignments%rowtype;
  v_stimulus public.source_detection_stimuli%rowtype;
  v_payload_pid text;
  v_rating_text text;
  v_rating integer;
  v_response_time_text text;
  v_response_time_ms integer;
  v_source_hashes jsonb;
  v_ordered_hashes jsonb;
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  if p_assignment_id is null then
    raise exception 'Missing assignment id';
  end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Missing response payload';
  end if;

  select *
    into v_assignment
    from public.source_detection_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.status in ('screened_out', 'excluded', 'abandoned') then
    raise exception 'This research session is no longer active';
  end if;

  v_payload_pid := nullif(trim(p_payload #>> '{participant,prolificPid}'), '');
  if v_payload_pid is null or v_payload_pid <> v_assignment.prolific_pid then
    raise exception 'Participant does not match assignment';
  end if;

  v_rating_text := p_payload #>> '{response,rating}';
  if v_rating_text is null or v_rating_text !~ '^[1-7]$' then
    raise exception 'Rating must be an integer from 1 to 7';
  end if;
  v_rating := v_rating_text::integer;

  v_response_time_text := p_payload #>> '{timing,responseTimeMs}';
  if v_response_time_text is not null then
    if v_response_time_text !~ '^[0-9]+$' then
      raise exception 'Response time must be a nonnegative integer';
    end if;
    if v_response_time_text::bigint > 86400000 then
      raise exception 'Response time exceeded the allowed range';
    end if;
    v_response_time_ms := v_response_time_text::integer;
  end if;

  select *
    into v_stimulus
    from public.source_detection_stimuli
   where stimulus_id = v_assignment.stimulus_id
   limit 1;

  if v_stimulus.stimulus_id is null then
    raise exception 'Assigned stimulus not found';
  end if;

  v_source_hashes := case
    when v_assignment.condition = 'human' then v_stimulus.human_comment_sha256
    else v_stimulus.ai_comment_sha256
  end;

  select jsonb_agg(v_source_hashes -> ordered.index_text::integer order by ordered.position)
    into v_ordered_hashes
    from jsonb_array_elements_text(v_assignment.comment_order)
      with ordinality as ordered(index_text, position);

  insert into public.source_detection_submissions (
    assignment_id,
    prolific_pid,
    study_id,
    session_id,
    stimulus_id,
    pair_number,
    pair_role,
    condition,
    comment_order,
    comment_hashes,
    rating,
    response_time_ms,
    is_test,
    payload,
    submitted_at,
    slot_id
  )
  values (
    v_assignment.assignment_id,
    v_assignment.prolific_pid,
    v_assignment.study_id,
    v_assignment.session_id,
    v_assignment.stimulus_id,
    v_stimulus.pair_number,
    v_stimulus.pair_role,
    v_assignment.condition,
    v_assignment.comment_order,
    coalesce(v_ordered_hashes, '[]'::jsonb),
    v_rating,
    v_response_time_ms,
    v_assignment.is_test,
    p_payload,
    now(),
    v_assignment.slot_id
  )
  on conflict (assignment_id) do update
    set rating = excluded.rating,
        response_time_ms = excluded.response_time_ms,
        payload = excluded.payload,
        submitted_at = excluded.submitted_at;

  update public.source_detection_assignments
     set status = 'submitted',
         submitted_at = now()
   where assignment_id = v_assignment.assignment_id
   returning * into v_assignment;

  if v_assignment.slot_id is not null then
    update public.source_detection_slots
       set status = 'submitted',
           submitted_at = now()
     where slot_id = v_assignment.slot_id
       and assignment_id = v_assignment.assignment_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'assignmentId', v_assignment.assignment_id,
    'status', v_assignment.status,
    'submittedAt', v_assignment.submitted_at
  );
end;
$$;

-- Researcher-only review helper. A valid decision retains the quota slot;
-- excluded/abandoned decisions reopen that exact post x source vacancy.
create or replace function public.review_source_detection_assignment(
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
  v_assignment public.source_detection_assignments%rowtype;
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

  perform pg_advisory_xact_lock(hashtext('source_detection_assignment'));

  select *
    into v_assignment
    from public.source_detection_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then
    raise exception 'Assignment not found';
  end if;
  if v_assignment.is_test then
    raise exception 'Test assignments do not occupy formal quota slots';
  end if;

  if p_decision = 'valid' then
    if v_assignment.status <> 'submitted' then
      raise exception 'Only an active submitted assignment can be marked valid';
    end if;
    if not exists (
      select 1
        from public.source_detection_submissions
       where assignment_id = p_assignment_id
    ) then
      raise exception 'A response must be submitted before it can be marked valid';
    end if;

    update public.source_detection_submissions
       set validity_status = 'valid',
           reviewed_at = now(),
           exclusion_reason = null
     where assignment_id = p_assignment_id;

    return jsonb_build_object(
      'ok', true,
      'assignmentId', p_assignment_id,
      'decision', 'valid',
      'slotReopened', false
    );
  end if;

  update public.source_detection_submissions
     set validity_status = 'excluded',
         reviewed_at = now(),
         exclusion_reason = p_reason
   where assignment_id = p_assignment_id;

  update public.source_detection_assignments
     set status = p_decision,
         exclusion_reason = p_reason,
         excluded_at = now()
   where assignment_id = p_assignment_id;

  if v_assignment.slot_id is not null then
    update public.source_detection_slots
       set status = 'open',
           assignment_id = null,
           claimed_at = null,
           submitted_at = null
     where slot_id = v_assignment.slot_id
       and assignment_id = p_assignment_id;
  end if;

  return jsonb_build_object(
    'ok', true,
    'assignmentId', p_assignment_id,
    'decision', p_decision,
    'slotReopened', v_assignment.slot_id is not null
  );
end;
$$;

create or replace view public.source_detection_cell_progress
with (security_invoker = true)
as
select
  stimuli.pair_number,
  stimuli.stimulus_id,
  cells.condition,
  count(slots.slot_id)::integer as target_slots,
  count(slots.slot_id) filter (where slots.status = 'open')::integer as open_slots,
  count(slots.slot_id) filter (where slots.status = 'claimed')::integer as claimed_slots,
  count(slots.slot_id) filter (where slots.status = 'submitted')::integer as submitted_slots,
  count(submissions.assignment_id) filter (
    where submissions.validity_status = 'pending'
  )::integer as pending_review,
  count(submissions.assignment_id) filter (
    where submissions.validity_status = 'valid'
  )::integer as valid_responses
from public.source_detection_stimuli stimuli
cross join (values ('human'::text), ('ai'::text)) as cells(condition)
left join public.source_detection_slots slots
  on slots.stimulus_id = stimuli.stimulus_id
 and slots.condition = cells.condition
left join public.source_detection_submissions submissions
  on submissions.assignment_id = slots.assignment_id
where stimuli.pair_role = 'primary'
group by stimuli.pair_number, stimuli.stimulus_id, cells.condition;

revoke all on public.source_detection_cell_progress from anon, authenticated;

revoke execute on function public.claim_source_detection_assignment(
  text, text, text, boolean
) from public;
revoke execute on function public.submit_source_detection_payload(
  text, jsonb
) from public;
revoke execute on function public.record_source_detection_comprehension_failure(
  text, text, jsonb
) from public;
revoke execute on function public.review_source_detection_assignment(
  text, text, text
) from public;

grant execute on function public.claim_source_detection_assignment(
  text, text, text, boolean
) to anon, authenticated;
grant execute on function public.submit_source_detection_payload(
  text, jsonb
) to anon, authenticated;
grant execute on function public.record_source_detection_comprehension_failure(
  text, text, jsonb
) to anon, authenticated;
grant execute on function public.review_source_detection_assignment(
  text, text, text
) to service_role;

commit;

-- Expected after setup:
-- select pair_number, condition, target_slots, open_slots,
--        claimed_slots, submitted_slots, pending_review, valid_responses
-- from public.source_detection_cell_progress
-- order by pair_number, condition;
