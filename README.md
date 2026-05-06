# Everyday Decision-Making Study App

This is a static React frontend for the Everyday Decision-Making Study.
It can be deployed to GitHub Pages.

The participant-facing title is intentionally neutral so the study does not
prime participants with the primary research question before debriefing.

The main app source lives in `src/App.jsx`. The root `App.js` file is a small
compatibility re-export.

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
gh repo create everyday-decision-making-study --public --source=. --remote=origin --push
```

For an existing repository:

```bash
git remote add origin https://github.com/<username>/<repo>.git
git push -u origin main
```

## Runtime Query Parameters

The app can run in demo mode, but real data collection should pass assignment and
submission settings through the URL:

```text
https://example.github.io/repo/?assignment_url=https%3A%2F%2Fapi.example.org%2Fassignment%2Fabc&submit_url=https%3A%2F%2Fapi.example.org%2Fsubmit&PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

The app also accepts:

- `api_base`: backend base URL with `/assignment`
- `assignment_id`
- `condition`
- `question_id`
- `generation`
- `chain_id`
- `participant_slot`
- `completion_code`

## Important Backend Note

GitHub Pages is static hosting. It can display the experiment, but it cannot
store responses or allocate the next transmission-chain assignment by itself.
For real data collection, connect `submit_url` and `assignment_url` to a backend
such as Supabase, Firebase, Google Apps Script, Qualtrics, or a small API server.

If `submit_url` is omitted, responses are saved only in the participant's browser
local storage. That mode is useful for demos, not for live crowdsourcing.
