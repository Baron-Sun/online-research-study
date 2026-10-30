# Study 1 matched 100-post questionnaire

Public route: https://baron-sun.github.io/online-research-study/original-comments/

Researcher preview: https://baron-sun.github.io/online-research-study/original-comments/?preview=1

The interface omits preview labels and researcher controls. The `preview=1` URL
parameter still isolates test sessions from formal recruitment and exports. To
inspect a specific assignment, add `&slot=S001` through `&slot=S100` to the URL.

This route remains in the existing Baron-Sun/online-research-study site. It uses
material version `private100-study1matched-opinion-demographics-20261030-v6`, Supabase project
`kkfyoztlpjuvipqaoyig`, and the isolated `matched100v5_*` tables/RPCs. Earlier
`original100_*` and `matched100_*` preview records and all other studies are retained unchanged.
Browser session storage uses `matched100-v5`, preventing old drafts from being
reused with different posts.

## Current materials

The source is the validated `prolific_min60_noedit_100_20261026` package. Its
100 posts were matched to full Study 1 on historical semantic and moral-profile
diversity, six moral-theme patterns, dispersion, marginal distributions, lengths,
years and verdict agreement. The original 21 verdict-by-controversy stratum
quotas were retained. This is a deliberately matched stimulus set, not a random
sample or independent replication; future participant outcomes were not used.
The source package contains the frozen selection specification, code, complete
old/new comparisons and verification that all 600 historical response texts
match canonical Study 1. Historical responses are not included in the website
seed or participant interface.

`matched100v6-material-manifest.json` records the selected post IDs, exact prompt
and body hashes, source specification hash and all 300 assignments. Each of 100
slots contains three distinct posts. Every post occurs in three different slots,
once at each position. No pair of posts is repeated across participant slots.

The participant instructions retain the reviewed neutral private-response
framing, task-understanding question and minimum of 60 words, including the judgment
label, with no maximum word or character limit in the application. The full source body is preserved, including its original line endings.
The instruction does not ask participants to act as Reddit users. Responses are
not shown/rated by other participants or posted to a public discussion forum.

The 26 October update retains all 80 unaffected posts and replaces the 20 posts
containing EDIT/UPDATE tokens or their inflected or numbered forms, ignoring
case. Replacement candidates come from the same 10,000-post pool and the same
strata. The original four-family matching objective is applied only to those
20 positions. Original post bodies, all 21 stratum quotas, the 300-row assignment
structure and historical packages are preserved. Matching remains based on
historical outcomes, so it does not establish an independent replication.

The user requested a minimum of 60 words and no upper limit. This supersedes
the earlier 61-word maximum; it is a protocol decision, not a recalculated
mean. `private100-word-limit-evidence.json` and old SQL/material files remain
historical evidence only. The current protocol is in
`src/private100-word-minimum.mjs`, `private100_opinion_prompt_template.txt`, and
`matched100v6-material-manifest.json`.

Independent work instructions are bold. Participants are told that their
original thoughts are wanted, that there are no right or wrong answers, and
that copying and pasting is unavailable. Response boxes block paste and drop
events; this is an interface restriction, not a claim to detect AI use.

## Database and configuration

For a new matched cohort, apply `supabase_matched100v5_setup.sql`, then
`supabase_matched100v5_seed.sql`. `python3 scripts/build_matched100v5_materials.py`
rebuilds these files from the validated source package and checks source hashes.
The seed refuses to run with recruitment open or formal participant records.
Existing materials must exactly match; it does not overwrite another cohort.

Then apply `supabase_matched100v6_flow_migration.sql` for the current flow. It
requires zero formal participants, retains all 100 post bodies and 300 plan rows,
adds demographic storage, and versions the revised instruction text. Existing
active preview sessions are upgraded; completed earlier previews remain readable.
Recruitment is closed by the migration and must be reopened only after deployment
verification. `scripts/build_original100_flow_20261030.py` deterministically
rebuilds the migration, prompt template and manifest from the frozen v5 files.

The new Prolific study is `6adedc85cdd8f2835bd60f5a`. Its study ID and completion
code are configured privately in `matched100v5_settings`, not in public source.
Completion codes are returned only for completed formal sessions. Preview
sessions never return a Prolific completion code and do not consume formal slots.
Recruitment must stay closed until backend checks and deployment are verified.
Enabling the website does not publish the Prolific study or spend its budget.

Use this URL in the Prolific external-study field:

```text
https://baron-sun.github.io/online-research-study/original-comments/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

At the user's request, the consent page reuses the earlier study's wording,
changing only the reward and sample size as needed for this study: $3.00 and
100 people. The original 10–12-minute duration and all other wording are retained.
No AI or response-diversity hypothesis is stated to participants before they
complete the task.

The 30 October update makes judgment labels instructional rather than a format
validation gate. The placeholder is “Begin with YTA, NTA, ESH, NAH, or INFO, then
write your opinion...”. Both browser and database enforce only the 60-word
minimum; they do not require line breaks, a separate label line, or capitalization.
The older case-insensitive-label migration is historical and must not be applied
after the v6 flow migration.

A successful task-understanding check opens the first situation immediately.
After reviewing the three responses, participants complete the exact five-question
“About you” section copied from `AdviceTransferTask.jsx`: gender identity, age,
English proficiency, education, and employment. Wording, choices, order, and field
markup match the reference. Demographic drafts autosave and restore on refresh;
optimistic revisions prevent conflicting tabs from overwriting newer answers.
The final submission requires all five fields and locks responses and demographics
together before returning the Prolific completion code.

## Collection and replacement

The RPC `matched100v5_session` serializes claims, checks the configured study ID,
prevents duplicate formal Prolific IDs, and binds each session to its own hashed
capability token. It exposes only the participant's assigned prompts and own
responses. Anonymous clients cannot read raw tables or researcher exports.

The task-understanding question permits two attempts. Its answer and version are
recorded, retries are idempotent, and refresh preserves the outcome. Two failures
end the session and reopen its slot; that identity cannot restart. No Prolific
payment rejection or account action is automated.

Short drafts are saved, but both browser and database reject advancing or
submitting fewer than 60 words. Responses of 60 words or more have no application
upper length limit. Final responses are locked. For an abandoned or excluded
formal participant, call the researcher-only `matched100v5_release(uuid, reason)`.
It preserves raw responses and the audit trail, excludes that participant from
completed coverage, and reopens exactly the same three-post slot.

For the de-identified completed dataset:

```sql
select participant_id, slot_id, position, stimulus_id, submission_id,
       prompt_version, prompt_sha256, comment, completed_at,
       comprehension_attempts, comprehension_passed_at,
       response_word_minimum, response_word_limit, response_word_count
from public.matched100v5_completed_comments
order by stimulus_id, participant_id;
```

The private `matched100v5_completed_demographics` view contains one row per
completed formal participant. Join to comments on `participant_id`; select only
the demographic fields needed for analysis. Preview records are excluded from
both exports, and neither export is readable with public client credentials.

Check collection coverage with:

```sql
select p.stimulus_id, count(c.participant_id) as completed_comments,
       count(distinct c.participant_id) as distinct_people
from public.matched100v5_posts p
left join public.matched100v5_completed_comments c using(stimulus_id)
group by p.stimulus_id order by p.stimulus_id;
```

## Verification

`npm test` passes 80 tests, including the new source-to-prompt and assignment
checks. The production build uses the GitHub Pages repository base path.
The historical `tests/matched100v5-rehearsal.sql` exercised 100 formal completions, 300 comments,
three distinct people per post, duplicate identity/capability protection,
comprehension failure and refill, stale writes, completion-code return, capacity,
completed locks and exclusion/replacement, short-draft preservation and blocking,
exactly 60 words, and acceptance of a 60,001-word response. All formal test data and settings are
rolled back. For the current flow, `tests/matched100v6-integration.sql` exercises
preview and formal completion inside a rolled-back transaction, demographic
validation/recovery/conflicts, single-paragraph responses, word boundaries and
private exports. `tests/matched100v6-live.mjs` uses only labeled preview sessions
for network checks, 59/60-word boundaries, 1,000-word submissions, demographic
save conflicts and raw-table access denial. Old v5 probes are archived and do not
include the required demographic step.
Private configuration and execution receipts are in ignored `verification/`.

Earlier setup/migration files and material manifests are retained for historical
`original100_*` sessions. They must not be used to initialize the current matched
cohort; the current frontend intentionally rejects older material versions.
