# Online Research Study App

This is a static React frontend for separate crowdsourcing tasks.
It can be deployed to GitHub Pages.

The participant-facing title is intentionally neutral so the study does not
prime participants with the primary research question before debriefing.

The root page is a researcher-facing portal. Participant-facing task links are
separate pages.

## Task Pages

- `/advice/`: one-shot advice exposure task
- `/judgment/`: single-post response task
- `/ratings/`: multi-post rating task
- `/comment-source/`: two-post, same-source comment-likelihood task
- `/advice-transfer/`: Study 2 A-to-B moral-advice transfer task

Use separate crowdsourcing studies or separate study links for these pages.

## Comment-source pretest

The formal comment-source task uses 10 primary posts crossed with two
between-participant comment-source conditions. Each participant is assigned
once to Human or AI, then sees two different posts whose five-comment sets both
come from that assigned source. Supabase creates 50 two-post participant slots
per condition, for 100 valid participants and 200 item ratings in total. Every
post receives exactly 10 ratings per condition. Three reserve posts remain
inactive. Test IDs beginning with `test-`, `preview-`, or `qa-` are balanced
separately and never consume a formal slot.

The participant flow is overview → informed consent → instructions and
attention check → two sequential post ratings → completion. The two post and
comment orders are fixed for that participant across refreshes. Incorrect
attention-check answers are persisted in Supabase. The first failure allows one
retry; the second marks the assignment `screened_out`, permanently ends that
participant session, and reopens the exact formal quota slot. Copy, cut, paste, drag/drop,
and the context menu are disabled throughout the participant page.

All 130 stored exposure comments are normalized to plain ASCII: emoji,
decorative Unicode punctuation, and Markdown formatting symbols are removed,
while ordinary English punctuation and wording are retained. Regenerate the
stimulus JSON and seed with the prototype's `scripts/build_stimuli.py` before
applying the seed to Supabase.

Run `supabase_source_detection_formal.sql` after the original 13-post
source-detection schema and seed, then run
`supabase_source_detection_dual.sql`. The first migration restricts formal
allocation to the 10 primary posts and installs the persisted two-strike
attention check. The second creates 100 same-source, two-post participant slots
and replaces the assignment, submission, review, and progress routines. An
excluded, abandoned, or twice-screened participant reopens the exact two-post
slot for replacement recruitment.

For Prolific External Study Link:

```text
https://baron-sun.github.io/online-research-study/comment-source/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}&completion_code=YOUR_PROLIFIC_CODE
```

For a test session, use a unique test ID and optionally add `debug=1`:

```text
https://baron-sun.github.io/online-research-study/comment-source/?PROLIFIC_PID=test-review-001&STUDY_ID=source-pretest&SESSION_ID=review-001&debug=1
```

## Study 2 advice-transfer task

The formal Study 2 task crosses 10 active A/B dilemma pairs with two masked
comment-source conditions. A participant reads dilemma A and five Human or five
AI comments, then writes advice for the related but different dilemma B. The
three reserve pairs remain inactive.

Run `supabase_advice_transfer_setup.sql`, then
`supabase_advice_transfer_seed.sql`. The setup is safe to rerun on the preview
database: it preserves assignments and submissions while upgrading the formal
allocator, renewable leases, draft autosave, idempotent submission, review
status, and progress view.

Formal recruitment is closed by default. Set the number of usable responses
required in each of the 20 pair-by-condition cells before opening recruitment.
For example, a balanced target of 100 usable responses means 5 per cell:

```sql
update public.advice_transfer_settings
   set setting_value = '5'::jsonb, updated_at = now()
 where setting_key = 'formal_target_per_cell';

update public.advice_transfer_settings
   set setting_value = 'true'::jsonb, updated_at = now()
 where setting_key = 'formal_recruitment_open';
```

To close new allocation without interrupting already assigned participants,
set `formal_recruitment_open` back to `false`. Monitor cell completion and
active leases with:

```sql
select * from public.advice_transfer_formal_cell_progress;
```

The allocator never treats historical page opens as completed quota. A
participant receives a renewable assignment lease, the browser sends a
heartbeat every minute, unfinished responses are saved both locally and in
Supabase, and final submission retries safely. Expired, screened-out, excluded,
or withdrawn attempts therefore do not permanently consume capacity.

Use this Prolific External Study Link:

```text
https://baron-sun.github.io/online-research-study/advice-transfer/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}&completion_code=YOUR_PROLIFIC_CODE
```

For launch, use single submission and limit simultaneous participant access to
15 rather than Unlimited. Start with 10 paid participants, verify Supabase
submissions and the progress view, and then increase places while retaining the
same concurrency limit.

## Local Development

```bash
npm install
npm run dev
```

## GitHub Pages Deployment

1. Create a new GitHub repository. A clean repository is strongly recommended.
2. Push this app folder to the repository's `main` branch.
3. In GitHub, open `Settings > Pages`.
4. Set `Source` to `GitHub Actions`.
5. Push to `main`; the included workflow will build and deploy the app.

For a user/organization Pages site, name the repository `<username>.github.io`.
For a project Pages site, any repository name is fine; Vite will set the base path
automatically in GitHub Actions.

With GitHub CLI, after `gh auth login`, one typical path is:

```bash
gh repo create online-research-study --public --source=. --remote=origin --push
```

For an existing repository:

```bash
git remote add origin https://github.com/<username>/<repo>.git
git push -u origin main
```

## Runtime Query Parameters

The app can run in demo mode, but real data collection should use a backend for
assignment and response storage. For `/ratings/` and `/advice/`, the current
recommended backend is Supabase. For `/judgment/`, the older
`assignment_url`/`submit_url` mode is still supported.

```text
https://example.github.io/repo/?assignment_url=https%3A%2F%2Fapi.example.org%2Fassignment%2Fabc&submit_url=https%3A%2F%2Fapi.example.org%2Fsubmit&PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

The app also accepts:

- `api_base`: backend base URL with `/assignment`
- `assignment_id`
- `posts_url`: URL returning either an array of posts or an assignment object
- `n_posts`: number of posts to show; default is 5
- `completion_code`
- `contact_email`

## Ratings Assignment JSON

For `/ratings/`, `assignment_url` should return:

```json
{
  "assignmentId": "worker-batch-001",
  "completionCode": "COMPLETE123",
  "contactEmail": "william.brady@kellogg.northwestern.edu",
  "posts": [
    {
      "id": "submission_id",
      "title": "Post title",
      "body": "Post text",
      "sourceBin": "low|medium|high"
    }
  ]
}
```

The app randomizes post order deterministically using assignment and participant
metadata, then submits one JSON payload containing one rating object per post.

## Judgment Assignment JSON

For `/judgment/`, `assignment_url` should return:

```json
{
  "assignmentId": "judgment-worker-001",
  "completionCode": "COMPLETE123",
  "contactEmail": "william.brady@kellogg.northwestern.edu",
  "post": {
    "id": "submission_id",
    "title": "Post title",
    "content": "Post text"
  },
  "previousResponse": {
    "id": "previous_response_id",
    "text": "Optional prior response text"
  }
}
```

## Important Backend Note

GitHub Pages is static hosting. It can display the experiment, but it cannot
store responses or allocate the next study assignment by itself.
For real data collection, connect `submit_url` and `assignment_url` to a backend
such as Supabase, Firebase, Google Apps Script, Qualtrics, or a small API server.

If `submit_url` is omitted, responses are saved only in the participant's browser
local storage. That mode is useful for demos, not for live crowdsourcing.

## Supabase Backend For `/ratings/`

The ratings task can use Supabase directly through the browser. No extra npm
package is required.

1. Create a Supabase project.
2. Open `SQL Editor` and run `supabase_setup.sql`.
3. Generate the full153k v1 import files with
   `python3 scripts/prepare_full153k_imports.py`.
4. In Supabase Table Editor, import
   `supabase_import/full153k_v1/rating_posts_import_full153k_v1.csv` into the
   `rating_posts` table.
5. Import
   `supabase_import/full153k_v1/rating_assignment_slots_import_full153k_v1.csv`
   into the `rating_assignment_slots` table. This file contains 180 fixed
   five-post assignments: each of the 300 posts appears exactly 3 times, each
   topic appears 90 times, each controversy bucket appears 300 times, and each
   topic x controversy cell appears 30 times.
6. In GitHub, open this repository's `Settings > Secrets and variables >
   Actions > Variables` and add:

```text
VITE_SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
VITE_RATING_COMPLETION_CODE=RATING2026
VITE_RESEARCH_CONTACT_EMAIL=william.brady@kellogg.northwestern.edu
```

7. Re-run the GitHub Pages workflow or push to `main`.

For local testing, copy `.env.example` to `.env.local` and fill in the same
values, then run:

```bash
npm run dev
```

Open the ratings task with a test Prolific ID:

```text
http://localhost:5173/ratings/?PROLIFIC_PID=test-worker-001&STUDY_ID=test-study&SESSION_ID=test-session
```

For Prolific External Study Link, use:

```text
https://baron-sun.github.io/online-research-study/ratings/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

If the Prolific completion code is not set with
`VITE_RATING_COMPLETION_CODE`, append it to the study URL:

```text
https://baron-sun.github.io/online-research-study/ratings/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}&completion_code=YOUR_PROLIFIC_CODE
```

After a successful Supabase save, the final page sends participants to
`https://app.prolific.com/submissions/complete?cc=YOUR_PROLIFIC_CODE`.

The Supabase RPC assigns the next open row from `rating_assignment_slots`,
reuses the same assignment if the participant refreshes, and saves the final
payload to `rating_submissions`. The frontend never samples rating posts; the
fixed database slot determines the five posts.
Comprehension-check failures are also stored on `rating_assignments`: after two
incorrect choices, the assignment is marked `screened_out`, and reopening the
same Prolific link will show the study-ended screen with no completion code.

For the current controversiality-rating task, each post has three required
ratings: OP wrongness, personal ambivalence, and perceived disagreement. The
final page asks two soft post-task questions instead of a color attention check.
On Prolific, mark the study as sensitive content, set the expected time to 10
minutes, and pilot with about 10 participants before full launch.

## Supabase Backend For `/advice/`

The advice exposure task uses separate `advice_*` tables and RPCs, so it does
not change or depend on the ratings task tables.

1. Open `SQL Editor` and run `supabase_advice_setup.sql`.
2. Generate the full153k v1 import files with
   `python3 scripts/prepare_full153k_imports.py`.
3. Import one-shot exposure stimuli into `advice_stimuli`. Each row should
   include one exposure dilemma, one related second dilemma, human comments,
   and LLM comments. For the full153k v1 launch files, human-condition slots
   show 5 comments and LLM-condition slots show 3 comments.
4. Import balanced assignable rows into `advice_slots`, with one row per
   participant slot and `condition` set to either `human_comments` or
   `llm_comments`.
5. Add `VITE_ADVICE_COMPLETION_CODE=C164ME01` as a GitHub Actions variable if
   you want to override the default completion code, then redeploy.

For local testing:

```text
http://localhost:5173/advice/?PROLIFIC_PID=test-worker-001&STUDY_ID=test-study&SESSION_ID=test-session
```

For Prolific External Study Link:

```text
https://baron-sun.github.io/online-research-study/advice/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

If the Prolific completion code is not set with
`VITE_ADVICE_COMPLETION_CODE`, append it to the study URL:

```text
https://baron-sun.github.io/online-research-study/advice/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}&completion_code=YOUR_PROLIFIC_CODE
```

After a successful Supabase save, the final page sends participants to
`https://app.prolific.com/submissions/complete?cc=YOUR_PROLIFIC_CODE`.

The RPC assigns one stimulus/feed per participant, reuses the same assignment
after refresh, stores two-strike comprehension screenouts, and saves final
responses to `advice_submissions`.
