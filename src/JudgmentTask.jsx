import React, { useEffect, useMemo, useState } from "react";

const MIN_REASONING_CHARS = 80;

const VOTES = [
  { code: "YTA", label: "You're the Asshole", accent: "rose" },
  { code: "NTA", label: "Not the Asshole", accent: "emerald" },
  { code: "ESH", label: "Everyone Sucks Here", accent: "amber" },
  { code: "NAH", label: "No Assholes Here", accent: "sky" },
  { code: "INFO", label: "Not Enough Info", accent: "violet" },
];

const DEMO_ASSIGNMENT = {
  assignmentId: "demo-judgment-assignment",
  completionCode: "JUDGMENT-DEMO-COMPLETE",
  submitEndpoint: "",
  contactEmail: "researcher@northwestern.edu",
  post: {
    id: "demo_inheritance",
    title: "AITA for refusing to share my inheritance with my step-siblings?",
    content: `My grandmother passed away last year and left me a significant inheritance. My mother remarried when I was 15, and I have two step-siblings who my grandmother met when they were already teenagers.

My step-siblings now say I should split the inheritance three ways because we are family. My stepfather agrees and says it would be the right thing to do. My mother is staying neutral, but I can tell she is uncomfortable.

I do not think I should have to share money that my grandmother specifically left to me. She had every opportunity to include them in her will and chose not to. AITA?`,
  },
  previousResponse: {
    id: "demo-prev-001",
    text: `NTA

Your grandmother made her wishes clear through her will. She specifically chose to leave the inheritance to you, and she deliberately did not include your step-siblings. That was her right and her decision to make.

Your step-siblings should respect that this money was meant for you.`,
  },
};

const accentClasses = {
  rose: "text-rose-700 border-rose-500 bg-rose-50 ring-rose-100",
  emerald: "text-emerald-700 border-emerald-500 bg-emerald-50 ring-emerald-100",
  amber: "text-amber-700 border-amber-500 bg-amber-50 ring-amber-100",
  sky: "text-sky-700 border-sky-500 bg-sky-50 ring-sky-100",
  violet: "text-violet-700 border-violet-500 bg-violet-50 ring-violet-100",
};

const TailwindLoader = ({ children }) => {
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    if (document.querySelector('script[src*="tailwindcss"]')) {
      setLoaded(true);
      return;
    }

    const script = document.createElement("script");
    script.src = "https://cdn.tailwindcss.com";
    script.onload = () => setLoaded(true);
    script.onerror = () => setLoaded(true);
    document.head.appendChild(script);
  }, []);

  if (!loaded) {
    return (
      <div className="min-h-screen bg-slate-50 text-slate-700 flex items-center justify-center">
        Loading study...
      </div>
    );
  }

  return children;
};

const getQueryParams = () => new URLSearchParams(window.location.search);

const getProlificMeta = () => {
  const params = getQueryParams();
  return {
    prolificPid: params.get("PROLIFIC_PID") || params.get("prolific_pid") || "",
    studyId: params.get("STUDY_ID") || params.get("study_id") || "",
    sessionId: params.get("SESSION_ID") || params.get("session_id") || "",
  };
};

const normalizeAssignment = (assignment) => {
  const post = assignment.post || assignment.submission || {};
  return {
    ...DEMO_ASSIGNMENT,
    ...assignment,
    post: {
      id: post.id || post.submission_id || post.post_id || "post",
      title: post.title || "Online post",
      content: post.content || post.body || post.selftext || post.text || "",
    },
    previousResponse: assignment.previousResponse || assignment.previous_response || null,
  };
};

const applyQueryOverrides = (assignment) => {
  const params = getQueryParams();
  return {
    ...assignment,
    assignmentId:
      params.get("assignment_id") ||
      params.get("assignment") ||
      assignment.assignmentId,
    completionCode: params.get("completion_code") || assignment.completionCode,
    contactEmail: params.get("contact_email") || assignment.contactEmail,
    submitEndpoint: params.get("submit_url") || assignment.submitEndpoint,
  };
};

const hasPreviousResponse = (assignment) =>
  Boolean(assignment?.previousResponse?.text?.trim());

const savePayload = async (assignment, payload) => {
  if (assignment.submitEndpoint) {
    const response = await fetch(assignment.submitEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });

    if (!response.ok) {
      throw new Error(`Submission failed with HTTP ${response.status}`);
    }

    return { mode: "remote" };
  }

  const key = `judgment-study-${payload.assignment.assignmentId}-${Date.now()}`;
  window.localStorage.setItem(key, JSON.stringify(payload));
  return { mode: "local", key };
};

const Page = ({ children, width = "max-w-7xl" }) => (
  <main className="min-h-screen bg-slate-50 text-slate-900">
    <div className={`mx-auto ${width} px-4 py-6 md:px-6 lg:px-8`}>
      {children}
    </div>
  </main>
);

const Panel = ({ children, className = "" }) => (
  <section
    className={`rounded-lg border border-slate-200 bg-white shadow-sm ${className}`}
  >
    {children}
  </section>
);

const Button = ({
  children,
  variant = "primary",
  disabled = false,
  className = "",
  ...props
}) => {
  const styles =
    variant === "primary"
      ? "bg-slate-900 text-white hover:bg-slate-800 disabled:bg-slate-300 disabled:text-slate-500"
      : "border border-slate-300 bg-white text-slate-700 hover:bg-slate-50 disabled:text-slate-400";

  return (
    <button
      disabled={disabled}
      className={`rounded-lg px-5 py-3 text-sm font-semibold transition ${styles} disabled:cursor-not-allowed ${className}`}
      {...props}
    >
      {children}
    </button>
  );
};

const FieldLabel = ({ children }) => (
  <label className="mb-2 block text-sm font-semibold text-slate-700">
    {children}
  </label>
);

const StudyHeader = ({ assignment }) => (
  <header className="mb-5 border-b border-slate-200 pb-5">
    <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
          Northwestern University Research Study
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-slate-950 md:text-[2.4rem]">
          Online Research Study
        </h1>
      </div>
      <div className="rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm text-slate-600 shadow-sm">
        <span className="font-semibold text-slate-900">Research Session</span>{" "}
        {assignment.assignmentId}
      </div>
    </div>
  </header>
);

const RatingScale = ({ value, onChange, left, right }) => (
  <div>
    <div className="grid grid-cols-7 gap-2">
      {[1, 2, 3, 4, 5, 6, 7].map((rating) => (
        <button
          key={rating}
          type="button"
          onClick={() => onChange(String(rating))}
          className={`rounded-lg border py-2 text-sm font-semibold transition ${
            value === String(rating)
              ? "border-slate-900 bg-slate-900 text-white"
              : "border-slate-300 bg-white text-slate-700 hover:bg-slate-50"
          }`}
        >
          {rating}
        </button>
      ))}
    </div>
    <div className="mt-2 flex justify-between text-xs text-slate-500">
      <span>{left}</span>
      <span>{right}</span>
    </div>
  </div>
);

const JudgmentTask = () => {
  const [assignment, setAssignment] = useState(() =>
    applyQueryOverrides(normalizeAssignment(DEMO_ASSIGNMENT))
  );
  const [loadState, setLoadState] = useState("ready");
  const [loadError, setLoadError] = useState("");
  const [screen, setScreen] = useState("landing");
  const [agreed, setAgreed] = useState(false);
  const [comprehension, setComprehension] = useState("");
  const [selectedVote, setSelectedVote] = useState("");
  const [reasoning, setReasoning] = useState("");
  const [confidence, setConfidence] = useState("");
  const [influence, setInfluence] = useState("");
  const [sourceGuess, setSourceGuess] = useState("");
  const [attentionCheck, setAttentionCheck] = useState("");
  const [submissionState, setSubmissionState] = useState("idle");
  const [submissionError, setSubmissionError] = useState("");
  const [saveMode, setSaveMode] = useState("");
  const [timings, setTimings] = useState({
    loadedAt: new Date().toISOString(),
    screens: {},
  });

  const participant = useMemo(() => getProlificMeta(), []);
  const previousShown = hasPreviousResponse(assignment);
  const canStartTask =
    comprehension ===
    (previousShown ? "independent-with-prior" : "independent-no-prior");
  const canContinue =
    selectedVote && reasoning.trim().length >= MIN_REASONING_CHARS;
  const canSubmit =
    confidence &&
    (previousShown ? influence && sourceGuess : true) &&
    attentionCheck === "blue";

  useEffect(() => {
    const params = getQueryParams();
    const assignmentUrl = params.get("assignment_url");
    const apiBase = params.get("api_base");
    const assignmentId = params.get("assignment_id") || params.get("assignment");

    if (!assignmentUrl && !apiBase) return;

    const loadAssignment = async () => {
      setLoadState("loading");
      setLoadError("");

      try {
        const url =
          assignmentUrl ||
          `${apiBase.replace(/\/$/, "")}/assignment?assignment_id=${encodeURIComponent(
            assignmentId || ""
          )}&prolific_pid=${encodeURIComponent(participant.prolificPid)}`;
        const response = await fetch(url);

        if (!response.ok) {
          throw new Error(`Assignment request failed with HTTP ${response.status}`);
        }

        const data = await response.json();
        setAssignment(applyQueryOverrides(normalizeAssignment(data)));
        setScreen("landing");
      } catch (error) {
        setLoadState("error");
        setLoadError(error.message);
      } finally {
        setLoadState((current) => (current === "error" ? "error" : "ready"));
      }
    };

    loadAssignment();
  }, [participant.prolificPid]);

  useEffect(() => {
    setTimings((current) => ({
      ...current,
      screens: {
        ...current.screens,
        [screen]: current.screens[screen] || new Date().toISOString(),
      },
    }));
  }, [screen]);

  const submit = async () => {
    setSubmissionState("submitting");
    setSubmissionError("");

    const payload = {
      schemaVersion: "single-post-judgment-task-v1",
      status: "completed",
      submittedAt: new Date().toISOString(),
      assignment: {
        assignmentId: assignment.assignmentId,
        completionCode: assignment.completionCode,
        postId: assignment.post.id,
        previousResponseId: assignment.previousResponse?.id || null,
        previousResponseShown: previousShown,
      },
      participant,
      response: {
        verdict: selectedVote,
        reasoning: reasoning.trim(),
        reasoningCharCount: reasoning.trim().length,
      },
      postTask: {
        confidence: Number(confidence),
        influence: previousShown ? Number(influence) : null,
        sourceGuess: previousShown ? sourceGuess : "no_prior",
        attentionCheck,
      },
      timings: {
        ...timings,
        finalizedAt: new Date().toISOString(),
      },
      client: {
        userAgent: window.navigator.userAgent,
        language: window.navigator.language,
      },
    };

    try {
      const result = await savePayload(assignment, payload);
      setSaveMode(result.mode);
      setSubmissionState("saved");
      setScreen("debrief");
    } catch (error) {
      setSubmissionState("error");
      setSubmissionError(error.message);
    }
  };

  const screens = {
    landing: (
      <Page>
        <StudyHeader assignment={assignment} />
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_360px]">
          <Panel className="p-6">
            <h2 className="mb-3 text-2xl font-semibold tracking-tight text-slate-950">
              Study Overview
            </h2>
            <p className="max-w-4xl text-base leading-7 text-slate-700">
              In this study, you will read one anonymized online post and provide
              a brief written response. The study takes about 5 to 10 minutes.
            </p>
          </Panel>
          <Panel className="p-5">
            <h3 className="mb-2 text-base font-semibold text-slate-950">
              Session Ready
            </h3>
            <p className="text-sm leading-6 text-slate-600">
              After consent and instructions, the task will open in this browser
              window.
            </p>
            <div className="mt-4 rounded-lg border border-slate-200 bg-slate-50 p-3 text-sm text-slate-700">
              <span className="font-semibold">Platform ID:</span>{" "}
              {participant.prolificPid || "Not detected"}
            </div>
            {loadState === "error" && (
              <div className="mt-4 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
                Could not load assignment: {loadError}
              </div>
            )}
            <Button
              className="mt-5 w-full"
              disabled={loadState === "loading" || loadState === "error"}
              onClick={() => setScreen("consent")}
            >
              Begin Study
            </Button>
          </Panel>
        </div>
      </Page>
    ),

    consent: (
      <Page width="max-w-6xl">
        <StudyHeader assignment={assignment} />
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_360px]">
          <Panel className="p-6">
            <h2 className="mb-4 text-2xl font-semibold text-slate-950">
              Informed Consent
            </h2>
            <div className="max-h-[560px] overflow-y-auto rounded-lg border border-slate-200 bg-slate-50 p-5 text-sm leading-6 text-slate-700">
              <p>
                <strong>Study title:</strong> Online Research Study
              </p>
              <p className="mt-4">
                <strong>Purpose:</strong> This research examines how people read
                and respond to written online posts.
              </p>
              <p className="mt-4">
                <strong>Procedures:</strong> You will read one anonymized post,
                answer a category question, and write a short explanation.
              </p>
              <p className="mt-4">
                <strong>Risks:</strong> Some posts may involve sensitive social
                situations. You may stop at any time.
              </p>
              <p className="mt-4">
                <strong>Contact:</strong> For questions about this research,
                contact {assignment.contactEmail || "researcher@northwestern.edu"}.
              </p>
            </div>
          </Panel>

          <Panel className="p-5 lg:sticky lg:top-6 lg:h-fit">
            <h3 className="text-base font-semibold text-slate-950">
              Consent Confirmation
            </h3>
            <label className="mt-5 flex items-start gap-3 rounded-lg border border-slate-200 bg-slate-50 p-4 text-sm text-slate-700">
              <input
                type="checkbox"
                checked={agreed}
                onChange={(event) => setAgreed(event.target.checked)}
                className="mt-1 h-4 w-4 rounded border-slate-300 text-slate-900 focus:ring-slate-900"
              />
              <span>
                I have read and understood the information above. I am 18 years
                or older and voluntarily agree to participate.
              </span>
            </label>
            <div className="mt-6 flex gap-3">
              <Button variant="secondary" onClick={() => setScreen("landing")}>
                Back
              </Button>
              <Button
                className="flex-1"
                disabled={!agreed}
                onClick={() => setScreen("instructions")}
              >
                I Agree
              </Button>
            </div>
          </Panel>
        </div>
      </Page>
    ),

    instructions: (
      <Page width="max-w-6xl">
        <StudyHeader assignment={assignment} />
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_420px]">
          <Panel className="p-6">
            <h2 className="mb-4 text-2xl font-semibold text-slate-950">
              Instructions
            </h2>
            <div className="grid gap-3 md:grid-cols-2">
              {[
                [
                  "Read the post carefully",
                  "The post describes a situation from the perspective of the person who wrote it.",
                ],
                [
                  previousShown ? "Consider the prior response" : "Begin directly",
                  previousShown
                    ? "You will see one response from an earlier round. Treat it as context, not as an answer key."
                    : "No prior response is shown in this assignment.",
                ],
                [
                  "Choose a category",
                  "Select one standard response category independently.",
                ],
                [
                  "Explain your response",
                  "Write a short explanation in your own words.",
                ],
              ].map(([title, body], index) => (
                <div
                  key={title}
                  className="grid grid-cols-[44px_1fr] gap-4 rounded-lg border border-slate-200 bg-slate-50 p-4"
                >
                  <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-white text-sm font-semibold text-slate-700 shadow-sm">
                    {index + 1}
                  </div>
                  <div>
                    <h3 className="font-semibold text-slate-950">{title}</h3>
                    <p className="mt-1 text-sm leading-6 text-slate-600">
                      {body}
                    </p>
                  </div>
                </div>
              ))}
            </div>
          </Panel>

          <Panel className="p-5 lg:sticky lg:top-6 lg:h-fit">
            <FieldLabel>Comprehension check</FieldLabel>
            <select
              value={comprehension}
              onChange={(event) => setComprehension(event.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
            >
              <option value="">Select the correct statement</option>
              {previousShown ? (
                <>
                  <option value="copy-prior">
                    I should copy the prior response as closely as possible.
                  </option>
                  <option value="independent-with-prior">
                    I should read the post and prior response, then give my own
                    response.
                  </option>
                </>
              ) : (
                <>
                  <option value="wait-prior">
                    I cannot answer unless I see a prior response.
                  </option>
                  <option value="independent-no-prior">
                    I should read the post and give my own response.
                  </option>
                </>
              )}
            </select>
            <div className="mt-5 flex gap-3">
              <Button variant="secondary" onClick={() => setScreen("consent")}>
                Back
              </Button>
              <Button
                className="flex-1"
                disabled={!canStartTask}
                onClick={() => setScreen("task")}
              >
                Start Task
              </Button>
            </div>
          </Panel>
        </div>
      </Page>
    ),

    task: (
      <Page width="max-w-[1600px]">
        <StudyHeader assignment={assignment} />
        <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_440px]">
          <div className="grid gap-5 lg:grid-cols-2">
            <Panel className="overflow-hidden">
              <div className="border-b border-slate-200 px-5 py-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Online Post
                </p>
                <h2 className="mt-2 text-xl font-semibold leading-7 text-slate-950">
                  {assignment.post.title}
                </h2>
              </div>
              <div className="p-5">
                <div className="whitespace-pre-line text-sm leading-7 text-slate-700">
                  {assignment.post.content}
                </div>
              </div>
            </Panel>

            {previousShown ? (
              <Panel className="overflow-hidden">
                <div className="border-b border-slate-200 px-5 py-4">
                  <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    Prior Response
                  </p>
                  <h3 className="mt-1 text-base font-semibold text-slate-950">
                    Response from an earlier round of the study
                  </h3>
                </div>
                <div className="p-5">
                  <div className="whitespace-pre-line text-sm leading-7 text-slate-700">
                    {assignment.previousResponse.text}
                  </div>
                </div>
              </Panel>
            ) : (
              <div className="rounded-lg border border-slate-200 bg-white p-5 text-sm leading-6 text-slate-600 shadow-sm">
                No prior response is shown.
              </div>
            )}
          </div>

          <Panel className="p-5 xl:sticky xl:top-6 xl:h-fit">
            <h2 className="mb-4 text-xl font-semibold text-slate-950">
              Your Response
            </h2>

            <div>
              <FieldLabel>Select a response category</FieldLabel>
              <div className="grid grid-cols-2 gap-2">
                {VOTES.map((vote) => {
                  const selected = selectedVote === vote.code;
                  return (
                    <button
                      key={vote.code}
                      type="button"
                      onClick={() => setSelectedVote(vote.code)}
                      className={`rounded-lg border p-3 text-left transition ${
                        selected
                          ? `${accentClasses[vote.accent]} ring-2`
                          : "border-slate-300 bg-white hover:bg-slate-50"
                      }`}
                    >
                      <span className="block font-mono font-bold">{vote.code}</span>
                      <span className="text-xs text-slate-600">{vote.label}</span>
                    </button>
                  );
                })}
              </div>
            </div>

            <div className="mt-5">
              <FieldLabel>Explain your response</FieldLabel>
              <textarea
                value={reasoning}
                onChange={(event) => setReasoning(event.target.value)}
                placeholder={
                  previousShown
                    ? "Write your own explanation. You may agree or disagree with the prior response, but your response should be your own."
                    : "Write your own explanation about the post."
                }
                className="h-64 w-full resize-none rounded-lg border border-slate-300 bg-white p-4 text-sm leading-6 text-slate-800 placeholder:text-slate-400 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100 xl:h-[320px]"
              />
              <div className="mt-2 flex justify-between text-xs">
                <span className="text-slate-500">
                  Minimum {MIN_REASONING_CHARS} characters
                </span>
                <span
                  className={
                    reasoning.trim().length >= MIN_REASONING_CHARS
                      ? "font-semibold text-emerald-700"
                      : "text-slate-500"
                  }
                >
                  {reasoning.trim().length} characters
                </span>
              </div>
            </div>

            <Button
              className="mt-6 w-full"
              disabled={!canContinue}
              onClick={() => setScreen("questions")}
            >
              Continue
            </Button>
          </Panel>
        </div>
      </Page>
    ),

    questions: (
      <Page width="max-w-6xl">
        <StudyHeader assignment={assignment} />
        <Panel className="p-6">
          <h2 className="mb-2 text-2xl font-semibold text-slate-950">
            Follow-up Questions
          </h2>
          <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_420px]">
            <div className="space-y-6">
              <div>
                <FieldLabel>How confident are you in your response?</FieldLabel>
                <RatingScale
                  value={confidence}
                  onChange={setConfidence}
                  left="Not confident"
                  right="Very confident"
                />
              </div>
              {previousShown && (
                <div>
                  <FieldLabel>
                    How much did the prior response influence your response?
                  </FieldLabel>
                  <RatingScale
                    value={influence}
                    onChange={setInfluence}
                    left="Not at all"
                    right="A great deal"
                  />
                </div>
              )}
            </div>

            <div className="space-y-5">
              {previousShown && (
                <div>
                  <FieldLabel>
                    What do you think the prior response came from?
                  </FieldLabel>
                  <select
                    value={sourceGuess}
                    onChange={(event) => setSourceGuess(event.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
                  >
                    <option value="">Select one</option>
                    <option value="human">A human participant</option>
                    <option value="ai">An AI system</option>
                    <option value="not_sure">Not sure</option>
                  </select>
                </div>
              )}
              <div>
                <FieldLabel>Attention check: please select "blue".</FieldLabel>
                <select
                  value={attentionCheck}
                  onChange={(event) => setAttentionCheck(event.target.value)}
                  className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
                >
                  <option value="">Select one</option>
                  <option value="red">Red</option>
                  <option value="blue">Blue</option>
                  <option value="green">Green</option>
                </select>
              </div>
            </div>
          </div>

          {submissionState === "error" && (
            <div className="mt-5 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
              {submissionError}
            </div>
          )}

          <div className="mt-6 flex gap-3">
            <Button variant="secondary" onClick={() => setScreen("task")}>
              Back
            </Button>
            <Button
              disabled={!canSubmit || submissionState === "submitting"}
              onClick={submit}
            >
              {submissionState === "submitting" ? "Submitting..." : "Submit"}
            </Button>
          </div>
        </Panel>
      </Page>
    ),

    debrief: (
      <Page width="max-w-5xl">
        <StudyHeader assignment={assignment} />
        <Panel className="p-6">
          <h2 className="mb-4 text-2xl font-semibold text-slate-950">
            Debriefing
          </h2>
          <div className="grid gap-5 text-sm leading-6 text-slate-700 md:grid-cols-2">
            <div className="space-y-4">
              <p>
                Thank you for participating. This study examines how people make
                and explain judgments about online social situations.
              </p>
              <p>
                Some prior responses in this research may be generated by AI
                systems rather than human participants. This detail was not fully
                disclosed before the task because knowing the source could change
                how participants evaluate the post and prior response.
              </p>
            </div>
            <div className="space-y-4">
              <p>
                If you have questions or concerns, contact{" "}
                {assignment.contactEmail || "researcher@northwestern.edu"}.
              </p>
              {saveMode === "local" && (
                <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-amber-900">
                  Demo mode: this response was saved to browser local storage
                  because no submit_url was configured.
                </div>
              )}
            </div>
          </div>
          <Button className="mt-6" onClick={() => setScreen("complete")}>
            Continue
          </Button>
        </Panel>
      </Page>
    ),

    complete: (
      <Page width="max-w-2xl">
        <Panel className="p-8 text-center">
          <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-lg bg-emerald-50 text-2xl font-semibold text-emerald-700">
            ✓
          </div>
          <h2 className="text-2xl font-semibold text-slate-950">
            Study Complete
          </h2>
          <p className="mx-auto mt-3 max-w-md text-sm leading-6 text-slate-600">
            Your response has been submitted. Please return to the crowdsourcing
            platform and enter the completion code below.
          </p>
          <div className="mx-auto mt-6 max-w-sm rounded-lg border border-slate-200 bg-slate-50 p-4">
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Completion Code
            </div>
            <div className="mt-2 select-all font-mono text-lg font-semibold text-slate-950">
              {assignment.completionCode || "JUDGMENT-COMPLETE"}
            </div>
          </div>
        </Panel>
      </Page>
    ),
  };

  return screens[screen] || screens.landing;
};

export default function JudgmentTaskApp() {
  return (
    <TailwindLoader>
      <JudgmentTask />
    </TailwindLoader>
  );
}
