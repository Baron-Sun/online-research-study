# Study 2: original comment labels

New same-post assignments made through `claim_advice_transfer_assignment_label_feedback`
use `original-label-v1`. Existing assignments keep `none`, even when resumed.

In Phase 1, selecting a label that differs from the original comment's leading
label shows: **The label given in the original comment was NTA.** The last word
is the actual original label. Selecting the matching label shows:
**Correct, the label given by the author was NTA.** This applies both to a
matching first choice and to a later corrected choice. Feedback is black text
and appears only once the server confirms the current selection. Changing a
correct answer to a mismatched answer restores the original-label hint.

Participants may keep their own choice. Neither continuation nor inclusion
requires agreement with the original label. Five saved choices are required.
The original label is an author's stated verdict, not an objectively correct
moral judgment. No labels for unanswered comments are included in the public
assignment response.

## Recorded fields

Assignments and submissions gain these fields:

| Field | Meaning |
| --- | --- |
| `label_feedback_version` | `none` for older assignments; `original-label-v1` for the new flow. |
| `comment_label_feedback` | Five per-comment records once all choices have been saved. Empty before any choice. |
| `comment_label_events` | Every accepted selection, in server order; retries with the same event ID count once. |

Each feedback record contains:

| Field | Meaning |
| --- | --- |
| `displayPosition` | Position the participant saw, from 1 to 5. |
| `commentIndex` | Position in the original condition's comment array, from 0 to 4. |
| `commentSha256` | SHA-256 of the assigned displayed text. |
| `originalLabel` | Hidden leading YTA, NTA, ESH, NAH, or INFO token in the raw source comment. |
| `firstLabel`, `firstSelectedAt` | First saved choice and server receipt timestamp; never replaced by a later choice. |
| `finalLabel`, `lastSelectedAt` | Latest saved choice and server receipt timestamp. Frozen with Phase 1. |
| `selectionCount` | Accepted selection events for this comment, excluding network retries. |
| `feedbackOffered` | Whether a mismatched choice ever caused the server to offer the original label. |
| `feedbackFirstOfferedAt` | First server timestamp for that offer; null when no hint has been offered. |

Each event stores `eventId`, `displayPosition`, `commentIndex`, `commentSha256`,
`selectedLabel`, `originalLabel`, `matchesOriginal`, and `recordedAt`. Timestamps
are server timestamps with UTC offsets. An offer does not prove that a hint was
rendered or read. A first choice on a later comment may follow feedback on an
earlier comment; the event sequence preserves that order.

The September 21, 2026 client adds positive confirmation without changing the
server's selection protocol (`original-label-v1`). Its final submission payload
records `clientAudit.labelFeedbackPresentationVersion` as
`original-label-confirmation-v2` for feedback-enabled assignments, or `none` for
older assignments without feedback. This identifies the submitting client; it
does not prove that any individual message was read. Earlier clients showed
only mismatch hints and did not include this presentation-version field.
`feedbackOffered` continues to track mismatch hints only, not positive
confirmation. Historical choices and feedback events are not rewritten.

The server copies the canonical records into the locked Phase 1 snapshot and
final submission payload. Existing `commentJudgments` contains final choices.
Use `firstLabel` to study initial agreement for each comment. Do not treat final
agreement after a hint as unaided comprehension. Report this protocol version
separately from the earlier no-feedback cohort: feedback may influence the gist
and final opinion as well as label choices.

## Deployment and checks

Apply `supabase_advice_transfer_label_feedback_20260918.sql` before deploying
the client. Recruitment settings, quota targets, and stimulus texts stay as
configured. The migration adds fields and RPCs and preserves the old RPCs.

Run `npm test` and `npm run build`. The rollback-only SQL test in
`tests/advice-transfer-label-feedback-integration.sql` checks all 100 active
comment mappings, first/corrected choices, idempotent retries, resumed legacy
assignments, phase locks, and final submission auditing. All synthetic test
records are rolled back. UI checks should use `qa-` or `preview-` identifiers.
