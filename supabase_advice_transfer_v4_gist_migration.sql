-- Additive Study 2 v4 gist migration. No settings, seeds, existing answers, or quota counts are changed.
-- Apply before the v4 frontend. Legacy clients keep the original RPCs.
begin;


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

-- The old decision-difficulty measure is deliberately NOT reused for gist.
alter table public.advice_transfer_submissions alter column difficulty drop not null;

do $$
begin
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
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.advice_transfer_submissions'::regclass
      and conname = 'advice_transfer_submission_protocol_measures') then
    alter table public.advice_transfer_submissions
      add constraint advice_transfer_submission_protocol_measures check (
        (protocol_version <> 'advice-transfer-v4-gist' and difficulty is not null)
        or (
          protocol_version = 'advice-transfer-v4-gist'
          and difficulty is null
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
  end if;
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
  v_result jsonb := coalesce(p_payload, '{}'::jsonb);
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
    'phase1Snapshot', p_assignment.phase1_snapshot,
    'phase1LockedAt', p_assignment.phase1_locked_at,
    'phase2Snapshot', p_assignment.phase2_snapshot,
    'phase2LockedAt', p_assignment.phase2_locked_at,
    'difficulty', null
  );
  if p_assignment.phase1_snapshot is not null then
    v_result := v_result || jsonb_build_object(
      'commentJudgments', p_assignment.phase1_snapshot -> 'commentJudgments',
      'gistText', p_assignment.phase1_snapshot -> 'gistText',
      'gistDifficulty', p_assignment.phase1_snapshot -> 'gistDifficulty'
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
      'effort', p_assignment.phase2_snapshot -> 'effort',
      'confidence', p_assignment.phase2_snapshot -> 'confidence'
    );
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

-- The classification task must be based on the comment's reasoning rather
-- than an explicit AITA verdict token. Preserve the raw stored stimulus and
-- remove only the leading verdict label in the v4 participant presentation.
create or replace function public.advice_transfer_remove_judgment_labels(p_comment text)
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
             to_jsonb(encode(digest(cleaned.comment_text, 'sha256'), 'hex'))
             order by cleaned.position
           )
      into v_clean_comments, v_clean_hashes
      from (
        select ordinality as position,
               public.advice_transfer_remove_judgment_labels(value) as comment_text
          from jsonb_array_elements_text(v_response -> 'comments')
               with ordinality
      ) cleaned;

    -- New/unlocked v4 sessions adopt hashes of exactly what participants see.
    -- A historical locked session is never silently changed; if it predates
    -- this display rule, it continues to receive its original comments/hashes.
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
    end if;
  end if;

  return v_response || jsonb_build_object(
    'schemaVersion', v_assignment.protocol_version,
    'protocolVersion', v_assignment.protocol_version,
    'draftPayload', public.advice_transfer_locked_payload(v_assignment, v_assignment.draft_payload),
    'phase1Snapshot', v_assignment.phase1_snapshot,
    'phase1LockedAt', v_assignment.phase1_locked_at,
    'phase2Snapshot', v_assignment.phase2_snapshot,
    'phase2LockedAt', v_assignment.phase2_locked_at
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
      v_effort := public.advice_transfer_required_integer(p_payload -> 'effort', 'effort', 1, 7);
      v_confidence := public.advice_transfer_required_integer(p_payload -> 'confidence', 'confidence', 1, 7);
      v_advice_ms := public.advice_transfer_required_integer(
        v_timings -> 'adviceResponseTimeMs', 'adviceResponseTimeMs', 0, 2147483647
      );
      v_now := greatest(clock_timestamp(), v_assignment.phase1_locked_at);
      v_snapshot := jsonb_build_object(
        'schemaVersion', v_assignment.protocol_version,
        'stage', 'phase2',
        'adviceText', v_advice,
        'adviceWordCount', v_word_count,
        'adviceCharacterCount', char_length(v_advice),
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
  v_difficulty := nullif(p_payload ->> 'difficulty', '')::integer;
  v_effort := nullif(p_payload ->> 'effort', '')::integer;
  v_confidence := nullif(p_payload ->> 'confidence', '')::integer;
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
  if (v_assignment.protocol_version <> 'advice-transfer-v4-gist'
       and (v_difficulty is null or v_difficulty not between 1 and 7))
     or v_effort is null or v_effort not between 1 and 7
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
        'commentOrder', v_assignment.comment_order,
        'commentHashes', v_assignment.presented_comment_sha256,
        'exposurePostId', v_stimulus.exposure_post_id,
        'exposurePostSha256', v_stimulus.exposure_post_body_sha256,
        'targetPostId', v_stimulus.target_post_id,
        'targetPostSha256', v_stimulus.target_post_body_sha256,
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

revoke all on function public.claim_advice_transfer_assignment_v4(text, text, text, boolean, integer, text)
  from public;

revoke all on function public.save_advice_transfer_stage(text, text, text, jsonb)
  from public;

revoke all on function public.advice_transfer_required_integer(jsonb, text, integer, integer)
  from public;

revoke all on function public.advice_transfer_locked_payload(public.advice_transfer_assignments, jsonb)
  from public;

revoke all on function public.guard_advice_transfer_phase_snapshots()
  from public;

revoke all on function public.advice_transfer_remove_judgment_labels(text)
  from public;

grant execute on function public.claim_advice_transfer_assignment_v4(text, text, text, boolean, integer, text)
  to anon, authenticated;

grant execute on function public.save_advice_transfer_stage(text, text, text, jsonb)
  to anon, authenticated;

notify pgrst, 'reload schema';
commit;
