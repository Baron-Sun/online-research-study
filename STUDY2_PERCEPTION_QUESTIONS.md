# Study 2: two perception questions

Placement: Phase 1, directly after gist difficulty and before Continue to Phase 2.
Both questions use integer 0–100 sliders. A participant must actively choose a
value; the initial midpoint is not a recorded answer. Clicking the midpoint or
pressing Enter/Space on a focused slider records 50. Arrow, Home and End keys
also work. Answers autosave, restore after refresh, and lock with Phase 1.

1. **Perceived similarity of reasons (wording v2)**

   How similar were the reasons the comments gave for their judgments?

   0 — Not at all similar; 100 — Very similar.

2. **Room for disagreement**

   How much room for disagreement is there in this situation?

   0 — One clear right answer; 100 — Genuinely open to debate.

The first item concerns the reasons given in the comments. The second concerns the situation in
general. These are the two final items; breadth of considerations is not an
additional item. Existing difficulty, confidence, and timing measures remain.

Wording update (2026-09-19): removed the introductory paragraph before the room
for disagreement question. The question, scale anchors, and stored fields are
unchanged. The deployment commit records this wording change; the data schema
version remains `perception-questions-v1`.

Wording update (2026-09-21): new sessions use `perception-questions-v2-reasons`
and the reasons-similarity question above. Existing v1 sessions retain “To what
extent did the comments agree with one another about how to think about this
situation?” with Not at all / Very much anchors. See `STUDY2_REVISED_MATERIALS.md`
for deployment and the separate material-version record.

## Data fields

| Database column | Snapshot / JSON key | Meaning |
| --- | --- | --- |
| `perception_questions_version` | `perceptionQuestionsVersion` | `perception-questions-v2-reasons` for revised-entry assignments; `perception-questions-v1` for previous wording; `none` for sessions without these items. |
| `perceived_consensus` | `perceivedConsensus` | Integer 0–100. Under v2, higher means more similar reasons; under v1, higher means more agreement among comments. Use the question version when interpreting this field. |
| `room_for_disagreement` | `roomForDisagreement` | Participant's reported scope for disagreement about the situation, integer 0–100. Higher means more open to debate. |

These are recorded responses, not model scores. Zero is a valid response, not
missingness. Null means no locked response was collected, including historical
assignments that did not include the items. Editable answers are kept in the
normal local/server drafts until Phase 1 is saved. The server then stores the
canonical values in the assignment, immutable Phase 1 snapshot, and final
submission. Client-supplied final payload values cannot overwrite them.

The draft and phase timings also retain `perceivedConsensusLastChangedAt` and
`roomForDisagreementLastChangedAt` when available (client ISO timestamps, not
durations). Overall Phase 1 active time includes these extra items. The new
section is outside the gist focus region, and Phase 2 opinion timing is unchanged.
When comparing earlier and later cohorts, account for the question version and
the existing label-feedback version.

## Deployment and checks

Apply `supabase_advice_transfer_perception_20260918.sql` after the label-feedback
migration and before deploying the client. It adds columns, wrappers, and audit
triggers. Existing assignments retain their original question set when resumed.

Run `npm test`, `npm run build`, and the rollback-only acceptance script
`tests/advice-transfer-perception-integration.sql`. The latter checks 0/50/100,
missing/malformed values, atomic saves, immutable retries, refresh recovery,
legacy sessions, and canonical final submission values. All synthetic SQL test
records are rolled back. Use `qa-` or `review=1` for live UI checks.
