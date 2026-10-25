# Original-prompt three-post study — preview

This is an additive route in the existing **Baron-Sun/online-research-study**
React/Vite/GitHub Pages application. It reuses the previous study's neutral
title, layout, CSS, blue controls, consent structure, and Supabase project.
Base: remote `main`, commit `bd200c8`. Local branch: `codex/original-100-preview`.

Local preview: http://127.0.0.1:5188/original-comments/?preview=1

`Preview controls` selects any of the 100 assignment slots or starts a fresh
test session. A normal preview refresh resumes the same slot and draft.
The new frontend is staged locally for review; the existing GitHub Pages
deployment has not been changed.

## Materials and allocation

- Source: the reviewed `prolific_original_100_20261024` CSV/JSONL package.
- 100 posts, 100 fixed participant slots, three distinct posts per slot.
- Each post occurs in exactly three different slots and once at each position.
- Original instructions plus **body only**, without a title or other comments.
- Original wording (including “You are an AI assistant…”) is preserved verbatim.
- Database and browser check SHA-256 for every assigned prompt.
- `supabase_original100_seed.sql` includes only stimuli and allocation, never
  historical participant comments, model responses, or judgment labels.

## Connected database

The existing Supabase project `kkfyoztlpjuvipqaoyig` contains the new isolated
`original100_*` tables and RPCs. Setup and seed were applied and verified on
2026-10-24 (Chicago). Existing study tables and RPCs were not modified.

Formal recruitment remains **closed**. The database contains 100 prompts and
300 assignment rows, with zero formal participants/comments at verification.
All retained test sessions use `mode='preview'` and explicit preview/QA IDs.

Participant writes go through `original100_session`, using a session capability
token. The stored token is hashed. Raw tables and the researcher export view
are inaccessible to anonymous/authenticated browser clients. Only the
participant's three assigned prompts and own responses are returned.

An explicit attention check now appears on the instructions page before the
first post: “To confirm that you are reading carefully, please select Blue for
this question.” Green, Blue and Yellow are the response options. The server
records each answer, correctness, version and timestamp. Retries of the same
request do not count twice. An incorrect answer prompts rereading and retry;
refresh preserves the recorded result. Task writes cannot begin until the
check is passed. This single check does not automatically exclude participants
or trigger payment rejection. It is unrelated to the moral judgments under
study. Apply `supabase_original100_attention.sql` to the already-connected
database, or use the updated full setup for a new database.

The user is reviewing a proposed neutral/private-response framing. No proposed
replacement prompt has been applied yet; stored Original prompts remain intact.

The allocator serializes claims/releases, prevents duplicate formal Prolific
IDs, and permits at most one active/completed formal participant per fixed slot.
Draft writes have revision checks. Final submission requires three correctly
formatted comments and the exact reviewed revisions; completion locks editing.

Replacement requires a researcher decision. In the Supabase SQL editor, call
`original100_release(participant_uuid, documented_reason)` for an excluded or
abandoned participant. This retains their raw responses and audit history,
excludes them from completed coverage, and reopens their exact slot. That
Prolific ID cannot claim a new slot. The next participant receives the same
three posts. There is no automatic time-based release while somebody may
still be writing.

For a de-identified completed dataset, use:

```sql
select participant_id, slot_id, position, stimulus_id, submission_id,
       prompt_sha256, comment, completed_at
from public.original100_completed_comments
order by stimulus_id, participant_id;
```

For coverage:

```sql
select p.stimulus_id, count(c.participant_id) as completed_comments,
       count(distinct c.participant_id) as distinct_participants
from public.original100_posts p
left join public.original100_completed_comments c using(stimulus_id)
group by p.stimulus_id order by p.stimulus_id;
```

## Verification

- Existing site's 67 tests pass; two additional material/integrity tests pass.
- Production build passes, including the GitHub Pages repository base path.
- SQL transaction rehearsal completes 100 people / 300 comments and checks
  three distinct people per post; duplicate identity, 101st arrival, wrong
  token, incomplete submit, stale draft, completed edit, and exclusion/refill
  assertions pass. **All formal rehearsal data/settings were rolled back.**
- Live public-API test: 16 concurrent claims for one QA identity produce one
  assignment; eight conflicting saves accept exactly one. Lost-receipt retries,
  duplicate final submission, page restoration, closed formal entry, and raw
  table denial pass. Synthetic comments are explicitly labeled as tests.
- Browser preview: consent → three actual assigned posts → autosave → refresh
  on post 2 → final review → completion. Mobile and desktop layouts inspected.

Scripts: `tests/original100.test.mjs`, `tests/original100-rehearsal.sql`, and
`tests/original100-live.mjs`. Local test evidence is in ignored `verification/`.
`.env.local` contains only the old site's existing public browser configuration
and is ignored. No privileged database credential is used in the frontend.

## Before recruitment

Review the preview and adapted consent text. Finalize the study duration,
reward, Prolific study ID and completion code. The preview consent deliberately
does not reuse the old study's $1.50 reward or 10–12-minute duration.
Then deploy this reviewed route through the existing GitHub Pages workflow and
configure the new study's settings. No Prolific study has been launched.

Future formal URL after deployment:

```text
https://baron-sun.github.io/online-research-study/original-comments/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

The consent draft is adapted from the prior website. Its approval flag remains
false until the research team reviews the final wording for this task.
