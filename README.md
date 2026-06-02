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

Use separate crowdsourcing studies or separate study links for these pages.

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
3. In Supabase Table Editor, import `prolific_aita_rating_batch_300.csv` into
   the `rating_posts` table.
4. In GitHub, open this repository's `Settings > Secrets and variables >
   Actions > Variables` and add:

```text
VITE_SUPABASE_URL=https://YOUR_PROJECT_ID.supabase.co
VITE_SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
VITE_RATING_COMPLETION_CODE=RATING2026
VITE_RESEARCH_CONTACT_EMAIL=william.brady@kellogg.northwestern.edu
```

5. Re-run the GitHub Pages workflow or push to `main`.

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

The Supabase RPC assigns 5 posts per participant, reuses the same assignment if
the participant refreshes, and saves the final payload to `rating_submissions`.
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
2. Import one-shot exposure stimuli into `advice_stimuli`. Each row should
   include one exposure dilemma, one similar friend dilemma, 5 human comments,
   and 5 LLM comments.
3. Import balanced assignable rows into `advice_slots`, with one row per
   participant slot and `condition` set to either `human_comments` or
   `llm_comments`.
4. Add `VITE_ADVICE_COMPLETION_CODE=ADVICE2026` as a GitHub Actions variable if
   you want to override the default completion code, then redeploy.

For local testing:

```text
http://localhost:5173/advice/?PROLIFIC_PID=test-worker-001&STUDY_ID=test-study&SESSION_ID=test-session
```

For Prolific External Study Link:

```text
https://baron-sun.github.io/online-research-study/advice/?PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

The RPC assigns one stimulus/feed per participant, reuses the same assignment
after refresh, stores two-strike comprehension screenouts, and saves final
responses to `advice_submissions`.
