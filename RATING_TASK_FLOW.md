# Rating Task Flow Summary

Last summarized: 2026-05-19

This document summarizes only the multi-post rating task currently implemented at `/ratings/`. It is an editable design document only and is not linked from the participant-facing website.

## Public Task Identity

Participant-facing title:

```text
Online Research Study
```

Use a neutral public title before debriefing. Do not use terms such as "Moral Judgment", "controversiality", or "disagreement rating" in the page title or pre-task headings if the goal is to avoid revealing the research purpose.

Task URL:

```text
https://baron-sun.github.io/online-research-study/ratings/
```

Current source file:

```text
src/App.jsx
```

## Task Goal

Participants read several anonymized r/AmITheAsshole-style posts and rate each post on four 1-7 scales. The current default is 5 posts per participant.

The task is intended to collect post-level ratings related to:

- How much the OP appears to be in the wrong.
- How strongly the participant feels about that response.
- How torn or conflicted the participant feels.
- How much disagreement the participant expects among thoughtful readers.

## Current Study Design Notes

These are design assumptions for assignment generation and data collection. The static GitHub Pages frontend does not enforce the full sampling plan by itself.

- Sample 100 submissions from each of the top 3 comment-disagreement label-ratio bins.
- Total submissions: 300.
- Human ratings per submission: 5.
- Submissions per human participant: 5.
- Required participants: 300.

Assignment logic implied by this design:

- Each participant receives 5 posts.
- Each submission should be assigned to 5 different participants.
- Backend or assignment generator should track exposure counts.
- The same participant should not rate the same submission more than once.

## Page Header

Every screen in the rating task shows:

```text
Northwestern University Research Study
Online Research Study
Research Session {assignmentId}
```

## Runtime Parameters

The app can run in demo mode, but real Prolific data collection should pass assignment and submission settings through URL query parameters.

Accepted parameters:

```text
assignment_url
posts_url
api_base
assignment_id
assignment
submit_url
completion_code
contact_email
n_posts
PROLIFIC_PID
STUDY_ID
SESSION_ID
```

Lowercase Prolific variants are also accepted:

```text
prolific_pid
study_id
session_id
```

If `submit_url` is missing, responses are saved only to the participant browser's local storage. That mode is for testing only, not live Prolific collection.

## Prolific Link Template

Use the `/ratings/` page, not the root portal.

```text
https://baron-sun.github.io/online-research-study/ratings/?assignment_url={ENCODED_ASSIGNMENT_URL}&submit_url={ENCODED_SUBMIT_URL}&PROLIFIC_PID={{%PROLIFIC_PID%}}&STUDY_ID={{%STUDY_ID%}}&SESSION_ID={{%SESSION_ID%}}
```

Optional overrides:

```text
completion_code=COMPLETE123
contact_email=researcher@northwestern.edu
n_posts=5
```

## Demo Assignment

Demo values currently used when no backend assignment is provided:

```json
{
  "assignmentId": "demo-rating-assignment",
  "completionCode": "ONLINE-DEMO-COMPLETE",
  "contactEmail": "researcher@northwestern.edu"
}
```

Default number of posts:

```text
5
```

## Full Participant Flow

Current screen order:

1. Landing
2. Consent
3. Instructions and comprehension check
4. Rating task
5. Review and attention check
6. Debrief
7. Completion code

## Screen 1: Landing

Main text:

```text
Study Overview
In this study, you will read {postCount} anonymized online posts. For each post, you will answer four short questions about your response and how you think other readers might respond.
```

Info cards:

```text
Task
{postCount} posts

Time
About 8 minutes
```

Side panel:

```text
Session Ready
After consent and instructions, the task will open in this browser window.

Platform ID: {PROLIFIC_PID or "Not detected"}

Begin Study
```

If assignment loading fails:

```text
Could not load assignment: {loadError}
```

Button:

```text
Begin Study
```

## Screen 2: Consent

Heading:

```text
Informed Consent
```

Consent text:

```text
TODO: Paste official IRB-approved informed consent text here.

Notes to update before launch:
- Study duration should say about 8 minutes.
- Payment amount should match the final Prolific payment.
- Final participation instruction should match the actual button text in the task.
- Contact information should use the approved researcher contact email.
```

Consent checkbox:

```text
I have read and understood the information above. I am 18 years or older and voluntarily agree to participate.
```

Buttons:

```text
Back
I Agree
```

Validation:

- Participant must check the consent box before continuing.

## Screen 3: Instructions

Heading:

```text
Instructions
```

Instruction text:

```text
You will read several short posts adapted from Reddit's r/AmITheAsshole forum. In these posts, people describe social dilemmas and ask readers to evaluate what happened.

For each post, your job is to give your own reaction and rate how divided you think thoughtful readers would be. There are no right or wrong answers. Please answer honestly and choose the number that best matches your reaction.

Please read each post carefully and answer all questions before moving to the next post. You will complete {postCount} posts in total.
```

Comprehension check label:

```text
Comprehension check
```

Comprehension check question:

```text
What will you be doing in this task?
```

Dropdown placeholder and options:

```text
Select the correct statement
A. I will read only one post and write a long explanation.
B. I will summarize each post without giving my own reaction.
C. I will read each post and rate how divided thoughtful readers might be about it.
D. I will try to guess which answer the researchers want.
```

Correct answer:

```text
C. I will read each post and rate how divided thoughtful readers might be about it.
```

Buttons:

```text
Back
Start Task
```

Validation:

- Participant must choose the correct comprehension-check answer.

## Screen 4: Rating Task

Layout:

- Left panel: assigned post list.
- Center panel: current post title and text.
- Right panel: four rating questions.

Progress text:

```text
Post {currentPostNumber} of {postCount}
{progressPercent}%
```

Left panel heading:

```text
Assigned Posts
```

Post status labels:

```text
Post 1
Complete
Incomplete
```

Center panel:

```text
Post {currentPostNumber} of {postCount}
{post.title}
{post.body}
```

Right panel heading:

```text
Your Ratings
```

Navigation buttons:

```text
Back
Next Post
Review & Submit
```

Validation:

- All four ratings must be answered for the current post before moving forward with `Next Post`.
- Desired behavior: participants should complete posts in order, answering all questions for the current post before moving to the next.
- All assigned posts must be complete before `Review & Submit`.
- Post order is randomized deterministically using assignment ID and participant metadata.

## Rating Items

All four items are shown in fixed order for each post.

### Question 1: OP Wrongness

Internal key:

```text
op_wrong
```

Participant-facing prompt:

```text
To what extent do you think the OP (original poster) is in the wrong in this situation?
```

Scale:

```text
1 - Definitely not in the wrong
2
3
4 - Unclear / both sides have a point
5
6
7 - Definitely in the wrong
```

### Question 2: Conviction

Internal key:

```text
conviction
```

Participant-facing prompt:

```text
How strongly do you feel about your response above?
```

Scale:

```text
1 - Not strongly at all
2
3
4 - Moderately strongly
5
6
7 - Extremely strongly
```

### Question 3: Personal Ambivalence

Internal key:

```text
ambivalence
```

Participant-facing prompt:

```text
How torn or conflicted do you feel about your response to the OP?
```

Scale:

```text
1 - Not torn at all; the answer is clear to me
2
3
4 - Somewhat torn
5
6
7 - Extremely torn; I genuinely cannot decide
```

### Question 4: Perceived Disagreement

Internal key:

```text
perceived_disagreement
```

Participant-facing prompt:

```text
If 100 thoughtful people read this post, what would their responses look like?
```

Scale:

```text
1 - Nearly all would reach the same response
2
3
4 - Mixed; many different views
5
6
7 - People would split into clearly opposed camps
```

## Screen 5: Review And Submit

Heading:

```text
Submit Study
```

Review text:

```text
You have completed {completedCount} of {postCount} posts. Please answer the attention check before submitting.
```

Review table headers:

```text
Post
Status
```

Status values:

```text
Complete
Incomplete
```

Attention check:

```text
Attention check: please select "blue".
```

Options:

```text
Select one
Red
Blue
Green
```

Buttons:

```text
Back
Submit
Submitting...
```

Validation:

- All posts must be complete.
- Attention check must be `Blue`.

## Screen 6: Debrief

Heading:

```text
Debriefing
```

Debrief text:

```text
Thank you for participating. This study measures how readers perceive disagreement and ambiguity in online posts.

The broader goal is to create human ratings of post-level controversiality for later research.

If you have questions or concerns, contact {contactEmail}.
```

If no `submit_url` was configured:

```text
Demo mode: this response was saved to browser local storage because no submit_url was configured.
```

Button:

```text
Continue
```

## Screen 7: Complete

Completion text:

```text
Study Complete
Your response has been submitted. Please return to the crowdsourcing platform and enter the completion code below.

Completion Code
{completionCode}
```

Fallback completion code:

```text
ONLINE-COMPLETE
```

## Assignment JSON

Expected assignment format:

```json
{
  "assignmentId": "worker-batch-001",
  "completionCode": "COMPLETE123",
  "contactEmail": "researcher@northwestern.edu",
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

Supported alternative field names:

- `posts` can also be `submissions`.
- Post ID can be `id`, `submission_id`, or `post_id`.
- Post body can be `body`, `content`, `selftext`, or `text`.
- Bin can be `sourceBin`, `bin`, or `disagreement_bin`.

## Submitted Payload

Schema version:

```text
post-controversiality-rating-v1
```

Payload structure:

```json
{
  "schemaVersion": "post-controversiality-rating-v1",
  "status": "completed",
  "submittedAt": "ISO timestamp",
  "assignment": {
    "assignmentId": "string",
    "completionCode": "string",
    "postCount": 5,
    "postIds": ["post_id_1", "post_id_2"]
  },
  "participant": {
    "prolificPid": "string",
    "studyId": "string",
    "sessionId": "string"
  },
  "attentionCheck": "blue",
  "ratings": [
    {
      "postId": "string",
      "postTitle": "string",
      "sourceBin": "low|medium|high|null",
      "order": 1,
      "firstSeenAt": "ISO timestamp",
      "responses": {
        "op_wrong": 1,
        "conviction": 1,
        "ambivalence": 1,
        "perceived_disagreement": 1
      }
    }
  ],
  "timings": {
    "loadedAt": "ISO timestamp",
    "screens": {},
    "finalizedAt": "ISO timestamp"
  },
  "client": {
    "userAgent": "string",
    "language": "string"
  }
}
```

## Editing Checklist

Before using the rating task for live Prolific data collection, review:

- Public title and pre-task wording: keep neutral if the purpose should remain masked.
- Consent wording: replace with IRB-approved language.
- Time estimate: confirm whether about 8 minutes is realistic for 5 posts.
- Rating item wording: confirm whether "response" should be changed to "judgment" or another neutral term.
- Scale anchors: confirm the 1, 4, and 7 anchors.
- Comprehension check: confirm it matches the task.
- Attention check: decide whether to keep, remove, or replace.
- Completion code: match Prolific study setup.
- `assignment_url`: must assign 5 posts per participant or respect `n_posts`.
- `submit_url`: must save the payload server-side.
- Backend assignment logic: must ensure 5 ratings per submission.
- Debrief wording: disclose the true purpose only after submission.
- Data schema: confirm field names match the analysis script.
