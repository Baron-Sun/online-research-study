# September 21 pilot: 200 new participants

Prolific study: `6ab145947e9c974c2b6cf1cd`.

The new pilot has 10 active posts × 2 conditions × 10 participants = 200 independent quota slots. Active original post IDs are 1–7, 9, 11 and 13. The material version is `content-priority-v2-20260921`; perception wording is `perception-questions-v2-reasons`. Matching comment labels receive positive confirmation; matching is not required to continue or enter the analysis.

The Prolific draft specifies 200 participants, $3.00 each, an estimated 12 minutes, and 15 simultaneous participants. At the checked academic fee, the total is $800. The new consent text states 200 people and $3.00; historical formal sessions retain the earlier consent text. The draft excludes participants from AI Homogeneity Experiment 1 and requires US nationality, US residence and English as the primary language. Submissions are reviewed manually and each participant may participate once.

## Formal link

```text
https://baron-sun.github.io/online-research-study/advice-transfer/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}&completion_code=CXB1PONQ
```

## Separate quota accounting

Apply `supabase_advice_transfer_pilot200_20260921.sql` once, after the revised-materials migration. It adds `study_id` to the quota ledger and makes the unique key `(study_id, stimulus_id, condition, slot_index)`. Existing token IDs, owners and states are preserved under the historical study ID `6a9b2d61ae180a9b2920551b`. The new study receives 200 additional unused tokens; the 102 historical responses do not count toward them.

`formal_study_id` selects the active recruitment cohort. The allocator, standby promotion and `advice_transfer_formal_cell_progress` are scoped to that study. New formal arrivals must carry the correct study ID, and participants who completed an earlier version are blocked. Historical completed sessions can still resume. Token ownership cannot cross study or stimulus/condition boundaries. Quota tables and progress remain private.

The target is **200 quota-bearing completions**, including pending review. Returns or invalid responses can require replacement recruitment. Completed standby responses remain separate from primary quota counts unless a same-cell vacancy is available. A 200-place Prolific study is not a guarantee of 200 valid primary observations after review.

```sql
select * from public.advice_transfer_formal_cell_progress;
select study_id, count(*) from public.advice_transfer_submissions
where not is_test group by study_id;
```

Do not rerun older setup/migration files over the current functions: they predate cohort-scoped quotas. Closing `formal_recruitment_open` pauses new allocation without deleting responses. This backend preparation does not publish the Prolific draft or pay participants; the researcher performs the final launch.

## Verification

The rollback-only test `tests/advice-transfer-pilot200-integration.sql` uses the real allocator to reserve 200 distinct participants across 20 cells. It checks the capacity limit, standby replacement after withdrawal, rejection of old participants and wrong study IDs, cross-study token guards, all 100 stimulus exposures, saving with all five labels incorrect, refresh recovery, canonical submission and duplicate-submission handling. It verifies fingerprints of historical assignments, submissions and tokens and rolls back all synthetic records. This is an allocation/functional test, not a claim that 200 simultaneous browser sessions were load-tested. Existing concurrency/retry tests and the 15-person Prolific limit provide separate safeguards.
