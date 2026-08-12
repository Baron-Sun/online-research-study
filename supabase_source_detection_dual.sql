-- Same-source, two-stimulus allocation for the /comment-source/ study.
-- Run after supabase_source_detection_formal.sql and the 13-post stimulus seed.
--
-- Design:
--   * 100 formal participant slots: 50 Human and 50 AI.
--   * Every participant receives two different primary posts.
--   * Both five-comment sets use the participant's single assigned condition.
--   * The 50 slots per condition yield exactly 10 exposures for every post.
--   * Test IDs are balanced separately and never consume formal slots.

begin;

alter table public.source_detection_assignments
  add column if not exists assignment_version integer not null default 1;

alter table public.source_detection_assignments
  add column if not exists stimulus_id_2 text;

alter table public.source_detection_assignments
  add column if not exists comment_order_2 jsonb;

alter table public.source_detection_assignments
  add column if not exists dual_slot_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'source_detection_assignments_stimulus_id_2_fkey'
       and conrelid = 'public.source_detection_assignments'::regclass
  ) then
    alter table public.source_detection_assignments
      add constraint source_detection_assignments_stimulus_id_2_fkey
      foreign key (stimulus_id_2)
      references public.source_detection_stimuli(stimulus_id);
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'source_detection_comment_order_2_five'
       and conrelid = 'public.source_detection_assignments'::regclass
  ) then
    alter table public.source_detection_assignments
      add constraint source_detection_comment_order_2_five
      check (
        comment_order_2 is null or
        (jsonb_typeof(comment_order_2) = 'array' and jsonb_array_length(comment_order_2) = 5)
      );
  end if;

  if not exists (
    select 1 from pg_constraint
     where conname = 'source_detection_two_distinct_stimuli'
       and conrelid = 'public.source_detection_assignments'::regclass
  ) then
    alter table public.source_detection_assignments
      add constraint source_detection_two_distinct_stimuli
      check (stimulus_id_2 is null or stimulus_id_2 <> stimulus_id);
  end if;
end;
$$;

create table if not exists public.source_detection_dual_slots (
  id uuid primary key default gen_random_uuid(),
  slot_id text not null unique,
  condition text not null check (condition in ('human', 'ai')),
  slot_index integer not null check (slot_index between 1 and 50),
  stimulus_id_1 text not null references public.source_detection_stimuli(stimulus_id),
  stimulus_id_2 text not null references public.source_detection_stimuli(stimulus_id),
  status text not null default 'open'
    check (status in ('open', 'claimed', 'submitted')),
  assignment_id text unique,
  claimed_at timestamptz,
  submitted_at timestamptz,
  created_at timestamptz not null default now(),
  unique (condition, slot_index),
  check (stimulus_id_1 <> stimulus_id_2)
);

-- Nine round-robin rounds cover every unordered pair once. The tenth round
-- repeats one perfect matching so every post appears exactly ten times.
with schedule(slot_index, pair_1, pair_2) as (
  values
    ( 1,  1, 10), ( 2,  2,  9), ( 3,  3,  8), ( 4,  4,  7), ( 5,  5,  6),
    ( 6,  1,  9), ( 7, 10,  8), ( 8,  2,  7), ( 9,  3,  6), (10,  4,  5),
    (11,  1,  8), (12,  9,  7), (13, 10,  6), (14,  2,  5), (15,  3,  4),
    (16,  1,  7), (17,  8,  6), (18,  9,  5), (19, 10,  4), (20,  2,  3),
    (21,  1,  6), (22,  7,  5), (23,  8,  4), (24,  9,  3), (25, 10,  2),
    (26,  1,  5), (27,  6,  4), (28,  7,  3), (29,  8,  2), (30,  9, 10),
    (31,  1,  4), (32,  5,  3), (33,  6,  2), (34,  7, 10), (35,  8,  9),
    (36,  1,  3), (37,  4,  2), (38,  5, 10), (39,  6,  9), (40,  7,  8),
    (41,  1,  2), (42,  3, 10), (43,  4,  9), (44,  5,  8), (45,  6,  7),
    (46,  1, 10), (47,  2,  9), (48,  3,  8), (49,  4,  7), (50,  5,  6)
),
conditions(condition) as (
  values ('human'::text), ('ai'::text)
)
insert into public.source_detection_dual_slots (
  slot_id, condition, slot_index, stimulus_id_1, stimulus_id_2
)
select
  'source-dual-' || conditions.condition || '-' || lpad(schedule.slot_index::text, 2, '0'),
  conditions.condition,
  schedule.slot_index,
  first_stimulus.stimulus_id,
  second_stimulus.stimulus_id
from schedule
cross join conditions
join public.source_detection_stimuli first_stimulus
  on first_stimulus.pair_number = schedule.pair_1
 and first_stimulus.pair_role = 'primary'
join public.source_detection_stimuli second_stimulus
  on second_stimulus.pair_number = schedule.pair_2
 and second_stimulus.pair_role = 'primary'
on conflict (condition, slot_index) do nothing;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'source_detection_assignments_dual_slot_id_fkey'
       and conrelid = 'public.source_detection_assignments'::regclass
  ) then
    alter table public.source_detection_assignments
      add constraint source_detection_assignments_dual_slot_id_fkey
      foreign key (dual_slot_id)
      references public.source_detection_dual_slots(slot_id);
  end if;
end;
$$;

alter table public.source_detection_submissions
  add column if not exists stimulus_id_2 text;

alter table public.source_detection_submissions
  add column if not exists pair_number_2 integer;

alter table public.source_detection_submissions
  add column if not exists pair_role_2 text;

alter table public.source_detection_submissions
  add column if not exists comment_order_2 jsonb;

alter table public.source_detection_submissions
  add column if not exists comment_hashes_2 jsonb;

alter table public.source_detection_submissions
  add column if not exists rating_2 integer;

alter table public.source_detection_submissions
  add column if not exists response_time_ms_2 integer;

alter table public.source_detection_submissions
  add column if not exists total_response_time_ms integer;

alter table public.source_detection_submissions
  add column if not exists dual_slot_id text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conname = 'source_detection_submissions_rating_2_check'
       and conrelid = 'public.source_detection_submissions'::regclass
  ) then
    alter table public.source_detection_submissions
      add constraint source_detection_submissions_rating_2_check
      check (rating_2 is null or rating_2 between 1 and 7);
  end if;
end;
$$;

create index if not exists source_detection_dual_slots_status_condition_idx
  on public.source_detection_dual_slots (status, condition, slot_index);

create index if not exists source_detection_assignments_dual_slot_idx
  on public.source_detection_assignments (dual_slot_id)
  where dual_slot_id is not null;

alter table public.source_detection_dual_slots enable row level security;
revoke all on public.source_detection_dual_slots from anon, authenticated;

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
  v_dual_slot public.source_detection_dual_slots%rowtype;
  v_stimulus_1 public.source_detection_stimuli%rowtype;
  v_stimulus_2 public.source_detection_stimuli%rowtype;
  v_assignment_id text;
  v_selected_condition text;
  v_selected_ids text[];
  v_selected_stimulus_1 text;
  v_selected_stimulus_2 text;
  v_comment_order_1 jsonb;
  v_comment_order_2 jsonb;
  v_source_comments_1 jsonb;
  v_source_hashes_1 jsonb;
  v_source_comments_2 jsonb;
  v_source_hashes_2 jsonb;
  v_ordered_comments_1 jsonb;
  v_ordered_hashes_1 jsonb;
  v_ordered_comments_2 jsonb;
  v_ordered_hashes_2 jsonb;
  v_item_1 jsonb;
  v_item_2 jsonb;
  v_items jsonb;
  v_result jsonb;
begin
  p_prolific_pid := nullif(trim(p_prolific_pid), '');
  p_study_id := nullif(trim(p_study_id), '');
  p_session_id := nullif(trim(p_session_id), '');

  if p_prolific_pid is null then
    raise exception 'Missing PROLIFIC_PID';
  end if;

  perform pg_advisory_xact_lock(hashtext('source_detection_assignment_v2'));

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

  -- Upgrade an unfinished legacy test assignment in place so old review links
  -- continue to work after the two-item launch.
  if v_assignment.id is not null
     and v_assignment.status = 'claimed'
     and v_assignment.is_test
     and v_assignment.stimulus_id_2 is null then
    with exposure_counts as (
      select exposed.stimulus_id, count(*) as exposure_count
      from (
        select stimulus_id
          from public.source_detection_assignments
         where is_test = true
           and condition = v_assignment.condition
           and status in ('claimed', 'submitted')
        union all
        select stimulus_id_2
          from public.source_detection_assignments
         where is_test = true
           and condition = v_assignment.condition
           and status in ('claimed', 'submitted')
           and stimulus_id_2 is not null
      ) exposed
      group by exposed.stimulus_id
    )
    select stimulus.stimulus_id
      into v_selected_stimulus_2
      from public.source_detection_stimuli stimulus
      left join exposure_counts counts
        on counts.stimulus_id = stimulus.stimulus_id
     where stimulus.active = true
       and stimulus.pair_role = 'primary'
       and stimulus.stimulus_id <> v_assignment.stimulus_id
     order by coalesce(counts.exposure_count, 0), random()
     limit 1;

    select jsonb_agg(comment_index order by random())
      into v_comment_order_2
      from generate_series(0, 4) indexes(comment_index);

    update public.source_detection_assignments
       set stimulus_id_2 = v_selected_stimulus_2,
           comment_order_2 = v_comment_order_2,
           assignment_version = 2
     where assignment_id = v_assignment.assignment_id
     returning * into v_assignment;
  end if;

  if v_assignment.id is null then
    if coalesce(p_is_test, false) then
      -- Balance test participants by condition first.
      with conditions(condition) as (
        values ('human'::text), ('ai'::text)
      ),
      condition_counts as (
        select condition, count(*) as participant_count
          from public.source_detection_assignments
         where is_test = true
           and status in ('claimed', 'submitted')
         group by condition
      )
      select conditions.condition
        into v_selected_condition
        from conditions
        left join condition_counts counts using (condition)
       order by coalesce(counts.participant_count, 0), random()
       limit 1;

      -- Then choose two distinct posts with the fewest test exposures in that
      -- condition. This keeps previews balanced without consuming formal slots.
      with exposure_counts as (
        select exposed.stimulus_id, count(*) as exposure_count
          from (
            select stimulus_id
              from public.source_detection_assignments
             where is_test = true
               and condition = v_selected_condition
               and status in ('claimed', 'submitted')
            union all
            select stimulus_id_2
              from public.source_detection_assignments
             where is_test = true
               and condition = v_selected_condition
               and status in ('claimed', 'submitted')
               and stimulus_id_2 is not null
          ) exposed
         group by exposed.stimulus_id
      )
      select array_agg(selected.stimulus_id order by selected.exposure_count, selected.tie_break)
        into v_selected_ids
        from (
          select stimulus.stimulus_id,
                 coalesce(counts.exposure_count, 0) as exposure_count,
                 random() as tie_break
            from public.source_detection_stimuli stimulus
            left join exposure_counts counts
              on counts.stimulus_id = stimulus.stimulus_id
           where stimulus.active = true
             and stimulus.pair_role = 'primary'
           order by coalesce(counts.exposure_count, 0), tie_break
           limit 2
        ) selected;

      v_selected_stimulus_1 := v_selected_ids[1];
      v_selected_stimulus_2 := v_selected_ids[2];
    else
      -- Keep Human and AI participant counts equal throughout recruitment.
      with conditions(condition) as (
        values ('human'::text), ('ai'::text)
      ),
      occupied as (
        select condition,
               count(*) filter (where status in ('claimed', 'submitted')) as participant_count,
               count(*) filter (where status = 'open') as open_count
          from public.source_detection_dual_slots
         group by condition
      )
      select conditions.condition
        into v_selected_condition
        from conditions
        join occupied using (condition)
       where occupied.open_count > 0
       order by occupied.participant_count, random()
       limit 1;

      -- At partial sample sizes, prefer a slot whose two posts currently have
      -- the fewest exposures. The complete 50-slot schedule is exactly balanced.
      with exposure_counts as (
        select exposed.stimulus_id, count(*) as exposure_count
          from (
            select stimulus_id_1 as stimulus_id
              from public.source_detection_dual_slots
             where condition = v_selected_condition
               and status in ('claimed', 'submitted')
            union all
            select stimulus_id_2
              from public.source_detection_dual_slots
             where condition = v_selected_condition
               and status in ('claimed', 'submitted')
          ) exposed
         group by exposed.stimulus_id
      )
      select slots.*
        into v_dual_slot
        from public.source_detection_dual_slots slots
        left join exposure_counts first_count
          on first_count.stimulus_id = slots.stimulus_id_1
        left join exposure_counts second_count
          on second_count.stimulus_id = slots.stimulus_id_2
       where slots.condition = v_selected_condition
         and slots.status = 'open'
       order by greatest(
                  coalesce(first_count.exposure_count, 0),
                  coalesce(second_count.exposure_count, 0)
                ),
                coalesce(first_count.exposure_count, 0) +
                  coalesce(second_count.exposure_count, 0),
                random(),
                slots.slot_index
       for update of slots skip locked
       limit 1;

      if v_dual_slot.id is null then
        raise exception 'No available two-item source-detection slots';
      end if;

      -- Randomize which of the two posts appears first, independent of comment order.
      if random() < 0.5 then
        v_selected_stimulus_1 := v_dual_slot.stimulus_id_1;
        v_selected_stimulus_2 := v_dual_slot.stimulus_id_2;
      else
        v_selected_stimulus_1 := v_dual_slot.stimulus_id_2;
        v_selected_stimulus_2 := v_dual_slot.stimulus_id_1;
      end if;
    end if;

    if v_selected_stimulus_1 is null or v_selected_stimulus_2 is null then
      raise exception 'No available two-item source-detection assignment';
    end if;
    if v_selected_stimulus_1 = v_selected_stimulus_2 then
      raise exception 'Two-item assignment must contain different posts';
    end if;

    select jsonb_agg(comment_index order by random())
      into v_comment_order_1
      from generate_series(0, 4) indexes(comment_index);
    select jsonb_agg(comment_index order by random())
      into v_comment_order_2
      from generate_series(0, 4) indexes(comment_index);

    v_assignment_id := 'source-' || replace(gen_random_uuid()::text, '-', '');

    insert into public.source_detection_assignments (
      assignment_id, prolific_pid, study_id, session_id,
      stimulus_id, condition, comment_order, is_test, slot_id,
      assignment_version, stimulus_id_2, comment_order_2, dual_slot_id
    )
    values (
      v_assignment_id, p_prolific_pid, p_study_id, p_session_id,
      v_selected_stimulus_1, v_selected_condition, v_comment_order_1,
      coalesce(p_is_test, false), null,
      2, v_selected_stimulus_2, v_comment_order_2,
      case when coalesce(p_is_test, false) then null else v_dual_slot.slot_id end
    )
    returning * into v_assignment;

    if not coalesce(p_is_test, false) then
      update public.source_detection_dual_slots
         set status = 'claimed',
             assignment_id = v_assignment.assignment_id,
             claimed_at = now(),
             submitted_at = null
       where slot_id = v_dual_slot.slot_id;
    end if;
  end if;

  select * into v_stimulus_1
    from public.source_detection_stimuli
   where stimulus_id = v_assignment.stimulus_id;

  if v_stimulus_1.stimulus_id is null then
    raise exception 'Assigned first stimulus is unavailable';
  end if;

  v_source_comments_1 := case when v_assignment.condition = 'human'
    then v_stimulus_1.human_comments else v_stimulus_1.ai_comments end;
  v_source_hashes_1 := case when v_assignment.condition = 'human'
    then v_stimulus_1.human_comment_sha256 else v_stimulus_1.ai_comment_sha256 end;

  select
    jsonb_agg(v_source_comments_1 -> ordered.index_text::integer order by ordered.position),
    jsonb_agg(v_source_hashes_1 -> ordered.index_text::integer order by ordered.position)
    into v_ordered_comments_1, v_ordered_hashes_1
    from jsonb_array_elements_text(v_assignment.comment_order)
      with ordinality as ordered(index_text, position);

  v_item_1 := jsonb_build_object(
    'itemIndex', 1,
    'pairNumber', v_stimulus_1.pair_number,
    'pairRole', v_stimulus_1.pair_role,
    'postId', v_stimulus_1.stimulus_id,
    'postTitle', v_stimulus_1.post_title,
    'postBody', v_stimulus_1.post_body,
    'postBodySha256', v_stimulus_1.post_body_sha256,
    'comments', coalesce(v_ordered_comments_1, '[]'::jsonb),
    'commentHashes', coalesce(v_ordered_hashes_1, '[]'::jsonb),
    'commentOrder', v_assignment.comment_order
  );

  v_items := jsonb_build_array(v_item_1);

  if v_assignment.stimulus_id_2 is not null then
    select * into v_stimulus_2
      from public.source_detection_stimuli
     where stimulus_id = v_assignment.stimulus_id_2;

    if v_stimulus_2.stimulus_id is null then
      raise exception 'Assigned second stimulus is unavailable';
    end if;

    v_source_comments_2 := case when v_assignment.condition = 'human'
      then v_stimulus_2.human_comments else v_stimulus_2.ai_comments end;
    v_source_hashes_2 := case when v_assignment.condition = 'human'
      then v_stimulus_2.human_comment_sha256 else v_stimulus_2.ai_comment_sha256 end;

    select
      jsonb_agg(v_source_comments_2 -> ordered.index_text::integer order by ordered.position),
      jsonb_agg(v_source_hashes_2 -> ordered.index_text::integer order by ordered.position)
      into v_ordered_comments_2, v_ordered_hashes_2
      from jsonb_array_elements_text(v_assignment.comment_order_2)
        with ordinality as ordered(index_text, position);

    v_item_2 := jsonb_build_object(
      'itemIndex', 2,
      'pairNumber', v_stimulus_2.pair_number,
      'pairRole', v_stimulus_2.pair_role,
      'postId', v_stimulus_2.stimulus_id,
      'postTitle', v_stimulus_2.post_title,
      'postBody', v_stimulus_2.post_body,
      'postBodySha256', v_stimulus_2.post_body_sha256,
      'comments', coalesce(v_ordered_comments_2, '[]'::jsonb),
      'commentHashes', coalesce(v_ordered_hashes_2, '[]'::jsonb),
      'commentOrder', v_assignment.comment_order_2
    );
    v_items := v_items || jsonb_build_array(v_item_2);
  end if;

  v_result := jsonb_build_object(
    'assignmentId', v_assignment.assignment_id,
    'assignmentVersion', v_assignment.assignment_version,
    'status', v_assignment.status,
    'submittedAt', v_assignment.submitted_at,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'screenedOutAt', v_assignment.screened_out_at,
    'itemCount', jsonb_array_length(v_items),
    'items', v_items
  );

  if v_assignment.is_test then
    v_result := v_result || jsonb_build_object('debugCondition', v_assignment.condition);
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
  if p_assignment_id is null then raise exception 'Missing assignment id'; end if;
  if p_selected_option is null then raise exception 'Missing selected option'; end if;

  perform pg_advisory_xact_lock(hashtext('source_detection_assignment_v2'));

  select * into v_assignment
    from public.source_detection_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then raise exception 'Assignment not found'; end if;
  if v_assignment.status = 'submitted' then
    return jsonb_build_object(
      'ok', true, 'assignmentId', v_assignment.assignment_id,
      'status', v_assignment.status,
      'comprehensionFailures', v_assignment.comprehension_failures,
      'screenedOut', false
    );
  end if;
  if v_assignment.status = 'screened_out' then
    return jsonb_build_object(
      'ok', true, 'assignmentId', v_assignment.assignment_id,
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
         status = case when comprehension_failures + 1 >= 2
           then 'screened_out' else status end,
         screened_out_at = case when comprehension_failures + 1 >= 2
           then coalesce(screened_out_at, now()) else screened_out_at end
   where assignment_id = p_assignment_id
   returning * into v_assignment;

  if v_assignment.status = 'screened_out' then
    if v_assignment.slot_id is not null then
      update public.source_detection_slots
         set status = 'open', assignment_id = null,
             claimed_at = null, submitted_at = null
       where slot_id = v_assignment.slot_id
         and assignment_id = v_assignment.assignment_id
         and status = 'claimed';
    end if;
    if v_assignment.dual_slot_id is not null then
      update public.source_detection_dual_slots
         set status = 'open', assignment_id = null,
             claimed_at = null, submitted_at = null
       where slot_id = v_assignment.dual_slot_id
         and assignment_id = v_assignment.assignment_id
         and status = 'claimed';
    end if;
  end if;

  return jsonb_build_object(
    'ok', true, 'assignmentId', v_assignment.assignment_id,
    'status', v_assignment.status,
    'comprehensionFailures', v_assignment.comprehension_failures,
    'screenedOut', v_assignment.status = 'screened_out',
    'slotReopened', v_assignment.status = 'screened_out'
      and (v_assignment.slot_id is not null or v_assignment.dual_slot_id is not null)
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
  v_stimulus_1 public.source_detection_stimuli%rowtype;
  v_stimulus_2 public.source_detection_stimuli%rowtype;
  v_payload_pid text;
  v_rating_1_text text;
  v_rating_2_text text;
  v_rating_1 integer;
  v_rating_2 integer;
  v_response_time_1_text text;
  v_response_time_2_text text;
  v_total_response_time_text text;
  v_response_time_1 integer;
  v_response_time_2 integer;
  v_total_response_time integer;
  v_source_hashes_1 jsonb;
  v_source_hashes_2 jsonb;
  v_ordered_hashes_1 jsonb;
  v_ordered_hashes_2 jsonb;
begin
  p_assignment_id := nullif(trim(p_assignment_id), '');
  if p_assignment_id is null then raise exception 'Missing assignment id'; end if;
  if p_payload is null or jsonb_typeof(p_payload) <> 'object' then
    raise exception 'Missing response payload';
  end if;

  select * into v_assignment
    from public.source_detection_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then raise exception 'Assignment not found'; end if;
  if v_assignment.status in ('screened_out', 'excluded', 'abandoned') then
    raise exception 'This research session is no longer active';
  end if;
  if v_assignment.assignment_version < 2 or v_assignment.stimulus_id_2 is null then
    raise exception 'This assignment does not contain two stimuli';
  end if;

  v_payload_pid := nullif(trim(p_payload #>> '{participant,prolificPid}'), '');
  if v_payload_pid is null or v_payload_pid <> v_assignment.prolific_pid then
    raise exception 'Participant does not match assignment';
  end if;

  if jsonb_typeof(p_payload -> 'responses') <> 'array'
     or jsonb_array_length(p_payload -> 'responses') <> 2 then
    raise exception 'Exactly two item responses are required';
  end if;

  v_rating_1_text := p_payload #>> '{responses,0,rating}';
  v_rating_2_text := p_payload #>> '{responses,1,rating}';
  if v_rating_1_text is null or v_rating_1_text !~ '^[1-7]$'
     or v_rating_2_text is null or v_rating_2_text !~ '^[1-7]$' then
    raise exception 'Both ratings must be integers from 1 to 7';
  end if;
  v_rating_1 := v_rating_1_text::integer;
  v_rating_2 := v_rating_2_text::integer;

  if p_payload #>> '{assignment,items,0,postId}' <> v_assignment.stimulus_id
     or p_payload #>> '{assignment,items,1,postId}' <> v_assignment.stimulus_id_2 then
    raise exception 'Submitted post order does not match assignment';
  end if;

  v_response_time_1_text := p_payload #>> '{responses,0,responseTimeMs}';
  v_response_time_2_text := p_payload #>> '{responses,1,responseTimeMs}';
  v_total_response_time_text := p_payload #>> '{timing,responseTimeMs}';

  if v_response_time_1_text is not null then
    if v_response_time_1_text !~ '^[0-9]+$' or v_response_time_1_text::bigint > 86400000 then
      raise exception 'First response time is invalid';
    end if;
    v_response_time_1 := v_response_time_1_text::integer;
  end if;
  if v_response_time_2_text is not null then
    if v_response_time_2_text !~ '^[0-9]+$' or v_response_time_2_text::bigint > 86400000 then
      raise exception 'Second response time is invalid';
    end if;
    v_response_time_2 := v_response_time_2_text::integer;
  end if;
  if v_total_response_time_text is not null then
    if v_total_response_time_text !~ '^[0-9]+$' or v_total_response_time_text::bigint > 86400000 then
      raise exception 'Total response time is invalid';
    end if;
    v_total_response_time := v_total_response_time_text::integer;
  end if;

  select * into v_stimulus_1
    from public.source_detection_stimuli
   where stimulus_id = v_assignment.stimulus_id;
  select * into v_stimulus_2
    from public.source_detection_stimuli
   where stimulus_id = v_assignment.stimulus_id_2;

  if v_stimulus_1.stimulus_id is null or v_stimulus_2.stimulus_id is null then
    raise exception 'Assigned stimulus not found';
  end if;

  v_source_hashes_1 := case when v_assignment.condition = 'human'
    then v_stimulus_1.human_comment_sha256 else v_stimulus_1.ai_comment_sha256 end;
  v_source_hashes_2 := case when v_assignment.condition = 'human'
    then v_stimulus_2.human_comment_sha256 else v_stimulus_2.ai_comment_sha256 end;

  select jsonb_agg(v_source_hashes_1 -> ordered.index_text::integer order by ordered.position)
    into v_ordered_hashes_1
    from jsonb_array_elements_text(v_assignment.comment_order)
      with ordinality as ordered(index_text, position);
  select jsonb_agg(v_source_hashes_2 -> ordered.index_text::integer order by ordered.position)
    into v_ordered_hashes_2
    from jsonb_array_elements_text(v_assignment.comment_order_2)
      with ordinality as ordered(index_text, position);

  insert into public.source_detection_submissions (
    assignment_id, prolific_pid, study_id, session_id,
    stimulus_id, pair_number, pair_role, condition,
    comment_order, comment_hashes, rating, response_time_ms,
    is_test, payload, submitted_at, slot_id,
    stimulus_id_2, pair_number_2, pair_role_2,
    comment_order_2, comment_hashes_2, rating_2, response_time_ms_2,
    total_response_time_ms, dual_slot_id
  )
  values (
    v_assignment.assignment_id, v_assignment.prolific_pid,
    v_assignment.study_id, v_assignment.session_id,
    v_assignment.stimulus_id, v_stimulus_1.pair_number,
    v_stimulus_1.pair_role, v_assignment.condition,
    v_assignment.comment_order, coalesce(v_ordered_hashes_1, '[]'::jsonb),
    v_rating_1, v_response_time_1,
    v_assignment.is_test, p_payload, now(), v_assignment.slot_id,
    v_assignment.stimulus_id_2, v_stimulus_2.pair_number,
    v_stimulus_2.pair_role, v_assignment.comment_order_2,
    coalesce(v_ordered_hashes_2, '[]'::jsonb), v_rating_2,
    v_response_time_2, v_total_response_time, v_assignment.dual_slot_id
  )
  on conflict (assignment_id) do update
    set rating = excluded.rating,
        response_time_ms = excluded.response_time_ms,
        stimulus_id_2 = excluded.stimulus_id_2,
        pair_number_2 = excluded.pair_number_2,
        pair_role_2 = excluded.pair_role_2,
        comment_order_2 = excluded.comment_order_2,
        comment_hashes_2 = excluded.comment_hashes_2,
        rating_2 = excluded.rating_2,
        response_time_ms_2 = excluded.response_time_ms_2,
        total_response_time_ms = excluded.total_response_time_ms,
        dual_slot_id = excluded.dual_slot_id,
        payload = excluded.payload,
        submitted_at = excluded.submitted_at;

  update public.source_detection_assignments
     set status = 'submitted', submitted_at = now()
   where assignment_id = v_assignment.assignment_id
   returning * into v_assignment;

  if v_assignment.dual_slot_id is not null then
    update public.source_detection_dual_slots
       set status = 'submitted', submitted_at = now()
     where slot_id = v_assignment.dual_slot_id
       and assignment_id = v_assignment.assignment_id;
  end if;

  return jsonb_build_object(
    'ok', true, 'assignmentId', v_assignment.assignment_id,
    'status', v_assignment.status, 'submittedAt', v_assignment.submitted_at,
    'responseCount', 2
  );
end;
$$;

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

  if p_assignment_id is null then raise exception 'Missing assignment id'; end if;
  if p_decision is null or p_decision not in ('valid', 'excluded', 'abandoned') then
    raise exception 'Decision must be valid, excluded, or abandoned';
  end if;

  perform pg_advisory_xact_lock(hashtext('source_detection_assignment_v2'));
  select * into v_assignment
    from public.source_detection_assignments
   where assignment_id = p_assignment_id
   for update;

  if v_assignment.id is null then raise exception 'Assignment not found'; end if;
  if v_assignment.is_test then raise exception 'Test assignments do not occupy formal quota slots'; end if;

  if p_decision = 'valid' then
    if v_assignment.status <> 'submitted' then
      raise exception 'Only an active submitted assignment can be marked valid';
    end if;
    if not exists (
      select 1 from public.source_detection_submissions
       where assignment_id = p_assignment_id and rating_2 is not null
    ) then
      raise exception 'Two item responses must be submitted before validation';
    end if;

    update public.source_detection_submissions
       set validity_status = 'valid', reviewed_at = now(), exclusion_reason = null
     where assignment_id = p_assignment_id;

    return jsonb_build_object(
      'ok', true, 'assignmentId', p_assignment_id,
      'decision', 'valid', 'slotReopened', false
    );
  end if;

  update public.source_detection_submissions
     set validity_status = 'excluded', reviewed_at = now(), exclusion_reason = p_reason
   where assignment_id = p_assignment_id;

  update public.source_detection_assignments
     set status = p_decision, exclusion_reason = p_reason, excluded_at = now()
   where assignment_id = p_assignment_id;

  if v_assignment.slot_id is not null then
    update public.source_detection_slots
       set status = 'open', assignment_id = null,
           claimed_at = null, submitted_at = null
     where slot_id = v_assignment.slot_id and assignment_id = p_assignment_id;
  end if;
  if v_assignment.dual_slot_id is not null then
    update public.source_detection_dual_slots
       set status = 'open', assignment_id = null,
           claimed_at = null, submitted_at = null
     where slot_id = v_assignment.dual_slot_id and assignment_id = p_assignment_id;
  end if;

  return jsonb_build_object(
    'ok', true, 'assignmentId', p_assignment_id, 'decision', p_decision,
    'slotReopened', v_assignment.slot_id is not null or v_assignment.dual_slot_id is not null
  );
end;
$$;

create or replace view public.source_detection_cell_progress
with (security_invoker = true)
as
with slot_exposures as (
  select slot_id, condition, status, assignment_id, stimulus_id_1 as stimulus_id
    from public.source_detection_dual_slots
  union all
  select slot_id, condition, status, assignment_id, stimulus_id_2 as stimulus_id
    from public.source_detection_dual_slots
)
select
  stimuli.pair_number,
  stimuli.stimulus_id,
  cells.condition,
  count(exposures.slot_id)::integer as target_slots,
  count(exposures.slot_id) filter (where exposures.status = 'open')::integer as open_slots,
  count(exposures.slot_id) filter (where exposures.status = 'claimed')::integer as claimed_slots,
  count(exposures.slot_id) filter (where exposures.status = 'submitted')::integer as submitted_slots,
  count(submissions.assignment_id) filter (
    where submissions.validity_status = 'pending'
  )::integer as pending_review,
  count(submissions.assignment_id) filter (
    where submissions.validity_status = 'valid'
  )::integer as valid_responses
from public.source_detection_stimuli stimuli
cross join (values ('human'::text), ('ai'::text)) as cells(condition)
left join slot_exposures exposures
  on exposures.stimulus_id = stimuli.stimulus_id
 and exposures.condition = cells.condition
left join public.source_detection_submissions submissions
  on submissions.assignment_id = exposures.assignment_id
where stimuli.pair_role = 'primary'
group by stimuli.pair_number, stimuli.stimulus_id, cells.condition;

create or replace view public.source_detection_condition_progress
with (security_invoker = true)
as
select
  condition,
  count(*)::integer as target_participants,
  count(*) filter (where status = 'open')::integer as open_participants,
  count(*) filter (where status = 'claimed')::integer as claimed_participants,
  count(*) filter (where status = 'submitted')::integer as submitted_participants
from public.source_detection_dual_slots
group by condition;

revoke all on public.source_detection_cell_progress from anon, authenticated;
revoke all on public.source_detection_condition_progress from anon, authenticated;

revoke execute on function public.claim_source_detection_assignment(text, text, text, boolean) from public;
revoke execute on function public.submit_source_detection_payload(text, jsonb) from public;
revoke execute on function public.record_source_detection_comprehension_failure(text, text, jsonb) from public;
revoke execute on function public.review_source_detection_assignment(text, text, text) from public;

grant execute on function public.claim_source_detection_assignment(text, text, text, boolean) to anon, authenticated;
grant execute on function public.submit_source_detection_payload(text, jsonb) to anon, authenticated;
grant execute on function public.record_source_detection_comprehension_failure(text, text, jsonb) to anon, authenticated;
grant execute on function public.review_source_detection_assignment(text, text, text) to service_role;

commit;

-- Expected after setup:
-- select * from public.source_detection_condition_progress order by condition;
-- select * from public.source_detection_cell_progress order by pair_number, condition;
