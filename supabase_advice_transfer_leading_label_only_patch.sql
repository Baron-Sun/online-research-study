-- Additive Study 2 presentation patch.
-- New assignments remove only a verdict abbreviation at the very beginning
-- of each displayed comment. Verdict abbreviations later in the comment are
-- preserved verbatim. Existing assignments retain the exact presentation
-- whose hashes were stored when they were first claimed.
begin;

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

notify pgrst, 'reload schema';
commit;
