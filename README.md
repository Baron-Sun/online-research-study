# Online Research Study App

Static React frontend for a one-shot exposure experiment.

The participant-facing title is intentionally generic. The task shows one
scenario, a feed of written responses, and then a related scenario where the
participant writes advice for a friend. The experimental condition is stored in
the payload but not shown to participants.

## Local Development

```bash
npm install
npm run dev
```

## GitHub Pages Deployment

GitHub Pages is configured through `.github/workflows/deploy.yml`.

```bash
git push
```

The public page is:

```text
https://baron-sun.github.io/online-research-study/
```

## Runtime Parameters

The app can run in demo mode. For real data collection, pass assignment and
submission settings through the URL:

```text
https://baron-sun.github.io/online-research-study/?assignment_url=https%3A%2F%2Fapi.example.org%2Fassignment%2Fabc&submit_url=https%3A%2F%2Fapi.example.org%2Fsubmit&PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

Accepted query parameters:

- `assignment_url`: URL returning an assignment JSON object
- `api_base`: backend base URL with `/assignment`
- `assignment_id`
- `condition`: `human_comments` or `llm_comments`
- `submit_url`: POST endpoint for final payload
- `completion_code`

## Assignment JSON

```json
{
  "assignmentId": "worker-001",
  "condition": "human_comments",
  "completionCode": "COMPLETE123",
  "contactEmail": "researcher@northwestern.edu",
  "exposureDilemmaId": "exposure_001",
  "friendDilemmaId": "friend_001",
  "exposureDilemma": {
    "title": "Scenario title",
    "content": "Scenario text"
  },
  "friendDilemma": {
    "title": "Related scenario title",
    "content": "Related scenario text"
  },
  "comments": [
    { "id": "comment_001", "text": "First response shown in the feed." }
  ]
}
```

For demo mode, the app contains built-in human and LLM response feeds and
randomly assigns a condition within the browser session unless `condition` is
provided in the URL.

## Backend Note

GitHub Pages is static hosting. It can display the experiment, but it cannot
store responses or manage assignments by itself. For live crowdsourcing, connect
`assignment_url` and `submit_url` to a backend such as Supabase, Firebase,
Google Apps Script, Qualtrics, or a small API server.

If `submit_url` is omitted, responses are saved only in the participant's browser
local storage. That mode is useful for demos, not for live data collection.
