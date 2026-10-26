# Study 1 matched 100-post questionnaire

Public route: https://baron-sun.github.io/online-research-study/original-comments/

Researcher preview: https://baron-sun.github.io/online-research-study/original-comments/?preview=1

This route remains in the existing Baron-Sun/online-research-study site. It uses
material version `private100-study1matched-20261026-v4`, Supabase project
`kkfyoztlpjuvipqaoyig`, and the isolated `matched100_*` tables/RPCs. Earlier
`original100_*` preview records and all other studies are retained unchanged.
Browser session storage uses `matched100-v4`, preventing old drafts from being
reused with different posts.

## Current materials

The source is the validated `prolific_study1matched_100_20261025` package. Its
100 posts were matched to full Study 1 on historical semantic and moral-profile
diversity, six moral-theme patterns, dispersion, marginal distributions, lengths,
years and verdict agreement. The original 21 verdict-by-controversy stratum
quotas were retained. This is a deliberately matched stimulus set, not a random
sample or independent replication; future participant outcomes were not used.
The source package contains the frozen selection specification, code, complete
old/new comparisons and verification that all 600 historical response texts
match canonical Study 1. Historical responses are not included in the website
seed or participant interface.

`matched100-material-manifest.json` records the selected post IDs, exact prompt
and body hashes, source specification hash and all 300 assignments. Each of 100
slots contains three distinct posts. Every post occurs in three different slots,
once at each position. No pair of posts is repeated across participant slots.

The participant instructions retain the reviewed neutral private-response
framing, task-understanding question and 61-word maximum, including the judgment
label. The full source body is preserved, including its original line endings.
The instruction does not ask participants to act as Reddit users. Responses are
not shown/rated by other participants or posted to a public discussion forum.

The limit remains the rounded mean of all 459,801 original human comments in
Study 1: 27,977,852 whitespace-separated words / 459,801 = 60.847740653, rounded
to 61. `private100-word-limit-evidence.json` preserves its provenance. It is a
maximum, not a required response length or a match of length distributions.

## Database and configuration

For a new matched cohort, apply `supabase_matched100_setup.sql`, then
`supabase_matched100_seed.sql`. `python3 scripts/build_matched100_materials.py`
rebuilds these files from the validated source package and checks source hashes.
The seed refuses to run with recruitment open or formal participant records.
Existing materials must exactly match; it does not overwrite another cohort.

The new Prolific study is `6adedc85cdd8f2835bd60f5a`. Its study ID and completion
code are configured privately in `matched100_settings`, not in public source.
Completion codes are returned only for completed formal sessions. Preview
sessions never return a Prolific completion code and do not consume formal slots.
Recruitment must stay closed until backend checks and deployment are verified.
Enabling the website does not publish the Prolific study or spend its budget.

Use this URL in the Prolific external-study field:

```text
https://baron-sun.github.io/online-research-study/original-comments/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

The consent page refers to Prolific for duration and compensation, avoiding stale
values from earlier studies. The user's Prolific draft currently supplies those
settings. No AI or response-diversity hypothesis is stated to participants before
they complete the task.

## Collection and replacement

The RPC `matched100_session` serializes claims, checks the configured study ID,
prevents duplicate formal Prolific IDs, and binds each session to its own hashed
capability token. It exposes only the participant's assigned prompts and own
responses. Anonymous clients cannot read raw tables or researcher exports.

The task-understanding question permits two attempts. Its answer and version are
recorded, retries are idempotent, and refresh preserves the outcome. Two failures
end the session and reopen its slot; that identity cannot restart. No Prolific
payment rejection or account action is automated.

Over-limit drafts are saved, but both browser and database reject advancing or
submitting over 61 words. Final responses are locked. For an abandoned or excluded
formal participant, call the researcher-only `matched100_release(uuid, reason)`.
It preserves raw responses and the audit trail, excludes that participant from
completed coverage, and reopens exactly the same three-post slot.

For the de-identified completed dataset:

```sql
select participant_id, slot_id, position, stimulus_id, submission_id,
       prompt_version, prompt_sha256, comment, completed_at,
       comprehension_attempts, comprehension_passed_at,
       response_word_limit, response_word_count
from public.matched100_completed_comments
order by stimulus_id, participant_id;
```

Check collection coverage with:

```sql
select p.stimulus_id, count(c.participant_id) as completed_comments,
       count(distinct c.participant_id) as distinct_people
from public.matched100_posts p
left join public.matched100_completed_comments c using(stimulus_id)
group by p.stimulus_id order by p.stimulus_id;
```

## Verification

`npm test` passes 75 tests, including the new source-to-prompt and assignment
checks. The production build uses the GitHub Pages repository base path.
`tests/matched100-rehearsal.sql` exercises 100 formal completions, 300 comments,
three distinct people per post, duplicate identity/capability protection,
comprehension failure and refill, stale writes, completion-code return, capacity,
completed locks and exclusion/replacement. All formal test data and settings are
rolled back. `tests/matched100-live.mjs` uses only labeled preview sessions for
network/concurrency checks, 61/62-word boundaries and raw-table access denial.
Private configuration and execution receipts are in ignored `verification/`.

Earlier setup/migration files and material manifests are retained for historical
`original100_*` sessions. They must not be used to initialize the current matched
cohort; the current frontend intentionally rejects older material versions.
