# Study 2 revised materials and reasons question

The 21 September 2026 release adopts the reviewed content-priority second draft
for AI comments in Posts 01–07, 09, 11 and 13. Of the 50 AI comments, 40 change
and 10 retain their original text. All 50 original leading verdict labels,
model/source positions, human comments, and post bodies are preserved.

The first new rating is:

**How similar were the reasons the comments gave for their judgments?**

0 — Not at all similar; 100 — Very similar.

The second remains:

**How much room for disagreement is there in this situation?**

0 — One clear right answer; 100 — Genuinely open to debate.

## Versions and recorded fields

- New materials: `content-priority-v2-20260921`.
- Historical materials: `original-comments-v1`.
- New question wording: `perception-questions-v2-reasons`.
- Historical wording: `perception-questions-v1`, or `none` before those items existed.

`material_version` is recorded for each assignment and submission. Full stimulus
rows are archived in the private `advice_transfer_material_versions` table. An
existing assignment continues to resolve to its archived text and hashes.
New phase snapshots and final payloads also record `materialVersion`.

The existing database field `perceived_consensus` / JSON key `perceivedConsensus`
stores the first rating. Under wording v2 it measures perceived **similarity of
reasons**, while v1 asked about **agreement among comments**. Interpret it using
`perception_questions_version`; do not treat the two wordings as the same item.
`room_for_disagreement` / `roomForDisagreement` retains its previous meaning.
Both ratings are integers from 0 to 100; null means unanswered, and zero is valid.

Existing sessions retain their question wording. Updated clients use
`claim_advice_transfer_assignment_revised`; the earlier entry point remains
available so a cached older client cannot be given unsupported questions.

Every comment needs a saved label choice, but agreement with the original label
is never required. Mismatches only show the original label. Initial and final
choices and the feedback history remain recorded.

## Material provenance

`study2_revised_materials_20260921.json` contains the exact deployed comments,
the original/candidate hashes, original indices and copied labels. The source
draft checksum is
`6f2387baef9dc34cb122335709845ffb87de5f03d2190d81fc2774aef7a6ebe4`.
The same assistant edited the original model outputs; this is not regeneration
by the original models. Original labels were preserved as editing constraints,
not independently reclassified. AI comments average 77.46 English word units
versus 72.74 for the human comments; 41/50 pairs are within ten words. These are
content-preserving length edits, not strictly equal-length stimuli. Independent
human coding and semantic/moral rescoring of this version have not been performed.

The historical 102-participant pilot and its analysis/cache files are retained.
No recruitment campaign, quota reset, or change to recruitment targets is part
of this release. New-version recruitment must be planned separately from those
historical quota counts.

## Deployment and checks

Apply `supabase_advice_transfer_revised_materials_20260921.sql` once, before the
client update. The migration archives original and revised materials, updates
only the intended AI text and hashes, checks the installed function definitions,
and verifies that historical records, quotas, settings, and human/post text are
unchanged. It aborts if a formal participant is currently active.

Run the existing test suite and production build. The rollback-only integration
test covers all 100 active comments, old-session recovery, two wording versions,
five deliberately incorrect label choices, refresh, and canonical submission
auditing. Use a fresh `qa-` identity or `review=1` to inspect the new version.
