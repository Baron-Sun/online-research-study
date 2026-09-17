# Study 2 material review — 16 September 2026

The user authorized whole-post replacements after reviewing the reserves:
Post 10 → Post 11 (1cufm4w, Airbnb family cooking), and
Post 08 → Post 13 (g54jtz, misleading classmates about an exam).
Keep the original identifiers. Do not relabel old responses or remove participants.

## Review decision

Both candidates are usable with the qualifications below. The review covered
both original posts and all 20 comments in their current five-model AI and
five-comment Human sets. No clear reversal of a central actor's identity or
event was found. This is a content review, not a participant pretest or evidence
that the replacements will produce a larger experimental effect.

| Material | Checks and remaining qualifications |
| --- | --- |
| Post 11 | The core dispute is use of a family's rented kitchen during a wedding trip. Human labels: 3 NTA, 1 YTA, 1 NAH; AI: 5 NTA. One Human comment claims widespread phone-detection monitoring and eviction without refund. Such occupancy technology existed before the post, but prevalence and an automatic no-refund outcome are unverified. Preserve this as a commenter's claim; do not describe it as established fact. |
| Post 13 | The core dispute is deliberately misleading classmates about exam content to benefit from the grading curve. Human labels: 3 YTA, 2 ESH; AI: 5 YTA. Human comments contain harsh language, including an explicitly non-clinical use of “sociopath.” Both sets criticize the writer, so verdict variation may be limited. Five encoded blank-line markers are removed only from the displayed body; raw text and hashes remain unchanged. |

The allocation change preserves each complete Human/AI comment set. It does
not select individual comments or change the leading-label removal rule.
Hidden original labels remain descriptive coding, not an exclusion criterion.
Because the replacements were selected after examining pilot results, use a
dated material revision for later collection and retain the original pilot
analysis. A future confirmatory study must fix its materials before collecting
its independent sample.

## Verification and application

The migration checks the reviewed body hashes and both comment arrays for all
four affected posts. It takes the admission lock and refuses to run while a
formal participant is active. It updates only allocation roles, active flags,
and audit metadata, then creates tokens for the new active cells using the
existing target. Before committing, it checks that all prior assignments,
submissions, quota tokens, recruitment settings, and raw materials are intact.

New active set: **01, 02, 03, 04, 05, 06, 07, 09, 11, 13**.
Inactive set: **08, 10, 12**. Post 12 remains the unused reserve.

The frontend change affects display only. Existing unit tests and the
production build pass. A direct check confirms exactly five blank-line
markers disappear from Post 13 and the other 12 post bodies display unchanged.

## Sources checked

- Current stimulus JSON and seed; current deployed assignment functions;
  live Supabase stimulus hashes and aggregate recruitment records.
- [Party Squasher, 2017: phone-based occupancy monitoring](https://www.partysquasher.com/party-squasher-news/the-vacation-rental-industry-now-has-a-gadget-to-keep-an-eye-on-occupancy-levels/).
- [Airbnb: additional guests](https://www.airbnb.com/help/article/1515).
- [Airbnb: ground rules for guests](https://www.airbnb.com/help/article/2894).

The external sources support the existence of occupancy monitoring and the
need to follow a listing's rules. They do not verify the broad prevalence or
guaranteed penalty asserted by the Human comment.
