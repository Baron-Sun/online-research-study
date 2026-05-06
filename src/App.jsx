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
  assignmentId: "demo-assignment",
  condition: "human_ai",
  questionId: "demo_inheritance",
  generation: 2,
  chainId: "demo-chain-01",
  participantSlot: 1,
  completionCode: "AITA-DEMO-COMPLETE",
  submitEndpoint: "",
  contactEmail: "researcher@northwestern.edu",
  post: {
    title: "AITA for refusing to share my inheritance with my step-siblings?",
    content: `My (28F) grandmother passed away last year and left me a significant inheritance. My mother remarried when I was 15, and I have two step-siblings (26M, 24F) who my grandmother never really bonded with since she met them as teenagers.

My step-siblings are now saying I should split the inheritance three ways since we're "family." My stepfather agrees and says it would be the "right thing to do." My mother is staying neutral but I can tell she's uncomfortable.

I don't think I should have to share money that MY grandmother specifically left to ME. She had every opportunity to include them in her will and chose not to. AITA?`,
  },
  previousResponse: {
    id: "demo-prev-001",
    text: `NTA

Your grandmother made her wishes clear through her will. She specifically chose to leave her inheritance to you, and she deliberately did not include your step-siblings. That was her right and her decision to make.

Your step-siblings' sense of entitlement is misplaced. An inheritance is not a family lottery. It reflects the final wishes of the person who passed away, and your family should respect that.`,
  },
};

const accentClasses = {
  rose: {
    text: "text-rose-700",
    border: "border-rose-500",
    bg: "bg-rose-50",
    ring: "ring-rose-100",
  },
  emerald: {
    text: "text-emerald-700",
    border: "border-emerald-500",
    bg: "bg-emerald-50",
    ring: "ring-emerald-100",
  },
  amber: {
    text: "text-amber-700",
    border: "border-amber-500",
    bg: "bg-amber-50",
    ring: "ring-amber-100",
  },
  sky: {
    text: "text-sky-700",
    border: "border-sky-500",
    bg: "bg-sky-50",
    ring: "ring-sky-100",
  },
  violet: {
    text: "text-violet-700",
    border: "border-violet-500",
    bg: "bg-violet-50",
    ring: "ring-violet-100",
  },
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

const intFromParam = (params, key, fallback) => {
  const value = Number.parseInt(params.get(key), 10);
  return Number.isFinite(value) ? value : fallback;
};

const getProlificMeta = () => {
  const params = getQueryParams();
  return {
    prolificPid: params.get("PROLIFIC_PID") || params.get("prolific_pid") || "",
    studyId: params.get("STUDY_ID") || params.get("study_id") || "",
    sessionId: params.get("SESSION_ID") || params.get("session_id") || "",
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
    condition: params.get("condition") || assignment.condition,
    questionId: params.get("question_id") || assignment.questionId,
    generation: intFromParam(params, "generation", assignment.generation),
    chainId: params.get("chain_id") || assignment.chainId,
    participantSlot: intFromParam(
      params,
      "participant_slot",
      assignment.participantSlot
    ),
    completionCode: params.get("completion_code") || assignment.completionCode,
    submitEndpoint: params.get("submit_url") || assignment.submitEndpoint,
  };
};

const hasPreviousResponse = (assignment) =>
  Boolean(assignment?.previousResponse?.text?.trim());

const buildPayload = ({
  assignment,
  participant,
  response,
  postTask,
  timings,
  status,
}) => ({
  schemaVersion: "transmission-chain-frontend-v1",
  status,
  submittedAt: new Date().toISOString(),
  assignment: {
    assignmentId: assignment.assignmentId,
    condition: assignment.condition,
    questionId: assignment.questionId,
    generation: assignment.generation,
    chainId: assignment.chainId,
    participantSlot: assignment.participantSlot,
    previousResponseId: assignment.previousResponse?.id || null,
    previousResponseShown: hasPreviousResponse(assignment),
  },
  participant,
  response,
  postTask,
  timings,
  client: {
    userAgent: window.navigator.userAgent,
    language: window.navigator.language,
  },
});

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

  const key = `decision-study-${payload.assignment.assignmentId}-${Date.now()}`;
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
      : variant === "danger"
        ? "border border-rose-200 bg-white text-rose-700 hover:bg-rose-50 disabled:text-slate-400"
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
  <header className="mb-6 border-b border-slate-200 pb-5">
    <div className="flex flex-col gap-4 md:flex-row md:items-end md:justify-between">
      <div>
        <p className="mb-2 text-xs font-semibold uppercase tracking-[0.18em] text-slate-500">
          Northwestern University Research Study
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-slate-950 md:text-[2.4rem]">
          Everyday Decision-Making Study
        </h1>
      </div>
      <div className="rounded-lg border border-slate-200 bg-white px-4 py-3 text-sm text-slate-600 shadow-sm">
        <span className="font-semibold text-slate-900">Research Session</span>{" "}
        {assignment.assignmentId}
      </div>
    </div>
  </header>
);

const Progress = ({ current }) => {
  const steps = ["Consent", "Instructions", "Task", "Questions", "Debrief"];
  const index = steps.indexOf(current);
  return (
    <div className="mb-5">
      <div className="mb-2 flex justify-between text-xs font-medium text-slate-500">
        {steps.map((step, i) => (
          <span key={step} className={i <= index ? "text-slate-900" : ""}>
            {step}
          </span>
        ))}
      </div>
      <div className="h-2 overflow-hidden rounded-full bg-slate-200">
        <div
          className="h-full rounded-full bg-slate-900 transition-all"
          style={{ width: `${Math.max(((index + 1) / steps.length) * 100, 8)}%` }}
        />
      </div>
    </div>
  );
};

const RatingScale = ({ value, onChange, labelLeft, labelRight }) => (
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
      <span>{labelLeft}</span>
      <span>{labelRight}</span>
    </div>
  </div>
);

const TextBlock = ({ children }) => (
  <div className="whitespace-pre-line text-sm leading-6 text-slate-700">
    {children}
  </div>
);

const MoralJudgmentExperiment = () => {
  const [assignment, setAssignment] = useState(() =>
    applyQueryOverrides(DEMO_ASSIGNMENT)
  );
  const [loadState, setLoadState] = useState("ready");
  const [loadError, setLoadError] = useState("");
  const [currentScreen, setCurrentScreen] = useState("landing");
  const [agreed, setAgreed] = useState(false);
  const [comprehension, setComprehension] = useState("");
  const [selectedVote, setSelectedVote] = useState("");
  const [reasoning, setReasoning] = useState("");
  const [confidence, setConfidence] = useState("");
  const [influence, setInfluence] = useState("");
  const [sourceGuess, setSourceGuess] = useState("");
  const [attentionCheck, setAttentionCheck] = useState("");
  const [ageRange, setAgeRange] = useState("");
  const [gender, setGender] = useState("");
  const [nativeEnglish, setNativeEnglish] = useState("");
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
  const canSubmitTask =
    selectedVote && reasoning.trim().length >= MIN_REASONING_CHARS;
  const canSubmitPostTask =
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

        const remoteAssignment = await response.json();
        setAssignment(applyQueryOverrides(remoteAssignment));
        setLoadState("ready");
      } catch (error) {
        setLoadState("error");
        setLoadError(error.message);
      }
    };

    loadAssignment();
  }, [participant.prolificPid]);

  useEffect(() => {
    setTimings((current) => ({
      ...current,
      screens: {
        ...current.screens,
        [currentScreen]: current.screens[currentScreen] || new Date().toISOString(),
      },
    }));
  }, [currentScreen]);

  const submitPayload = async (status, extra = {}) => {
    setSubmissionState("submitting");
    setSubmissionError("");

    const payload = buildPayload({
      assignment,
      participant,
      status,
      response: {
        verdict: status === "completed" ? selectedVote : null,
        reasoning: status === "completed" ? reasoning.trim() : "",
        reasoningCharCount:
          status === "completed" ? reasoning.trim().length : 0,
        ...extra.response,
      },
      postTask: {
        confidence,
        influence: previousShown ? influence : "not_applicable",
        sourceGuess: previousShown ? sourceGuess : "no_prior",
        attentionCheck,
        demographics: {
          ageRange,
          gender,
          nativeEnglish,
        },
        ...extra.postTask,
      },
      timings: {
        ...timings,
        finalizedAt: new Date().toISOString(),
      },
    });

    try {
      const result = await savePayload(assignment, payload);
      setSaveMode(result.mode);
      setSubmissionState("saved");
      setCurrentScreen("debrief");
    } catch (error) {
      setSubmissionState("error");
      setSubmissionError(error.message);
    }
  };

  const screens = {
    landing: (
      <Page>
        <StudyHeader assignment={assignment} />
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_360px] xl:grid-cols-[minmax(0,1fr)_400px]">
          <Panel className="p-6">
            <h2 className="mb-3 text-2xl font-semibold tracking-tight text-slate-950">
              Study Overview
            </h2>
            <p className="max-w-4xl text-base leading-7 text-slate-700">
              This study examines how people reason about everyday interpersonal
              situations. You will read one anonymized scenario and provide your
              own decision and written explanation.
            </p>
            <div className="mt-6 grid gap-3 md:grid-cols-3">
              {[
                [
                  "Your task",
                  "Read one dilemma and explain your judgment in your own words.",
                ],
                [
                  "Estimated time",
                  "Most participants finish in about 5 to 10 minutes.",
                ],
                [
                  "Confidentiality",
                  "Responses are stored without your name and used for research.",
                ],
              ].map(([label, value]) => (
                <div
                  key={label}
                  className="rounded-lg border border-slate-200 bg-slate-50 p-4"
                >
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    {label}
                  </div>
                  <div className="mt-2 text-sm leading-6 text-slate-700">
                    {value}
                  </div>
                </div>
              ))}
            </div>
          </Panel>
          <Panel className="p-5">
            <h3 className="mb-2 text-base font-semibold text-slate-950">
              Session Ready
            </h3>
            <p className="text-sm leading-6 text-slate-600">
              After consent and instructions, the study interface will open in
              this browser window. Your response will be linked to this research
              session for data quality and payment processing.
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
              onClick={() => setCurrentScreen("consent")}
            >
              Begin Study
            </Button>
          </Panel>
        </div>
      </Page>
    ),

    consent: (
      <Page width="max-w-6xl">
        <Progress current="Consent" />
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_360px]">
          <Panel className="p-6">
            <h2 className="mb-4 text-2xl font-semibold text-slate-950">
              Informed Consent
            </h2>
            <div className="max-h-[560px] overflow-y-auto rounded-lg border border-slate-200 bg-slate-50 p-5 text-sm leading-6 text-slate-700">
              <p>
                <strong>Study title:</strong> Everyday Decision-Making Study
              </p>
              <p className="mt-4">
                <strong>Purpose:</strong> This research examines how judgments
                and written explanations change as people consider everyday
                interpersonal situations.
              </p>
              <p className="mt-4">
                <strong>Procedures:</strong> You will read an anonymized
                scenario and, if available, one response from an earlier round
                of the study. You will then provide your own decision and
                explanation.
              </p>
              <p className="mt-4">
                <strong>Risks:</strong> Some scenarios may involve interpersonal
                conflict, family issues, finances, or relationship disagreements.
                You may skip the scenario if it causes discomfort.
              </p>
              <p className="mt-4">
                <strong>Confidentiality:</strong> Your study response will be
                stored without your name. Crowdsourcing platform IDs may be used
                only for payment, duplicate prevention, and data quality checks.
              </p>
              <p className="mt-4">
                <strong>Voluntary participation:</strong> Your participation is
                voluntary. You may stop at any time without penalty.
              </p>
              <p className="mt-4">
                <strong>Contact:</strong> For questions about this research, contact{" "}
                {assignment.contactEmail || "researcher@northwestern.edu"}.
              </p>
            </div>
          </Panel>

          <Panel className="p-5 lg:sticky lg:top-6 lg:h-fit">
            <h3 className="text-base font-semibold text-slate-950">
              Consent Confirmation
            </h3>
            <p className="mt-2 text-sm leading-6 text-slate-600">
              Please confirm that you understand the study information before
              continuing.
            </p>
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
              <Button
                variant="secondary"
                onClick={() => setCurrentScreen("landing")}
              >
                Back
              </Button>
              <Button
                className="flex-1"
                disabled={!agreed}
                onClick={() => setCurrentScreen("instructions")}
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
        <Progress current="Instructions" />
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_420px]">
          <Panel className="p-6">
            <h2 className="mb-4 text-2xl font-semibold text-slate-950">
              Instructions
            </h2>
            <div className="grid gap-3 md:grid-cols-2">
              {[
                [
                  "Read the dilemma",
                  "The scenario comes from an anonymized online discussion about an everyday interpersonal situation.",
                ],
                [
                  previousShown ? "Consider the prior response" : "Begin the chain",
                  previousShown
                    ? "You will see one response from an earlier round. Treat it as context, not as an answer key."
                    : "This assignment begins a new chain, so you will only see the original scenario.",
                ],
                [
                  "Provide your verdict",
                  "Choose one standard AITA category and make your judgment independently.",
                ],
                [
                  "Explain your reasoning",
                  "Write a short justification in your own words. Your reasoning is the main research material.",
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

          <div className="space-y-5">
            <Panel className="p-4">
              <h3 className="mb-3 text-sm font-semibold text-slate-950">
                Voting Categories
              </h3>
              <div className="grid gap-2">
                {VOTES.map((vote) => {
                  const accent = accentClasses[vote.accent];
                  return (
                    <div
                      key={vote.code}
                      className={`rounded-lg border p-3 ${accent.bg} ${accent.border}`}
                    >
                      <span className={`font-mono font-bold ${accent.text}`}>
                        {vote.code}
                      </span>
                      <span className="ml-2 text-sm text-slate-700">
                        {vote.label}
                      </span>
                    </div>
                  );
                })}
              </div>
            </Panel>

            <Panel className="p-4">
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
                      I should read the scenario and prior response, then give my
                      own judgment.
                    </option>
                  </>
                ) : (
                  <>
                    <option value="wait-prior">
                      I cannot answer unless I see a prior response.
                    </option>
                    <option value="independent-no-prior">
                      I should read the scenario and give my own judgment.
                    </option>
                  </>
                )}
              </select>

              <div className="mt-5 flex gap-3">
                <Button
                  variant="secondary"
                  onClick={() => setCurrentScreen("consent")}
                >
                  Back
                </Button>
                <Button
                  className="flex-1"
                  disabled={!canStartTask}
                  onClick={() => setCurrentScreen("task")}
                >
                  Start Task
                </Button>
              </div>
            </Panel>
          </div>
        </div>
      </Page>
    ),

    task: (
      <Page width="max-w-[1600px]">
        <Progress current="Task" />
        <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_440px]">
          <div className="grid gap-5 lg:grid-cols-2">
            <Panel className="overflow-hidden">
              <div className="border-b border-slate-200 px-5 py-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Original Dilemma
                </p>
                <h2 className="mt-2 text-xl font-semibold leading-7 text-slate-950">
                  {assignment.post.title}
                </h2>
              </div>
              <div className="p-5">
                <TextBlock>{assignment.post.content}</TextBlock>
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
                  <TextBlock>{assignment.previousResponse.text}</TextBlock>
                </div>
              </Panel>
            ) : (
              <div className="rounded-lg border border-slate-200 bg-white p-5 text-sm leading-6 text-slate-600 shadow-sm">
                This assignment begins a new chain. No prior response is shown.
              </div>
            )}
          </div>

          <Panel className="p-5 xl:sticky xl:top-6 xl:h-fit">
            <h2 className="mb-4 text-xl font-semibold text-slate-950">
              Your Judgment
            </h2>

            <div>
              <FieldLabel>Select your verdict</FieldLabel>
              <div className="grid grid-cols-2 gap-2">
                {VOTES.map((vote) => {
                  const accent = accentClasses[vote.accent];
                  const selected = selectedVote === vote.code;
                  return (
                    <button
                      key={vote.code}
                      type="button"
                      onClick={() => setSelectedVote(vote.code)}
                      className={`rounded-lg border p-3 text-left transition ${
                        selected
                          ? `${accent.border} ${accent.bg} ring-2 ${accent.ring}`
                          : "border-slate-300 bg-white hover:bg-slate-50"
                      }`}
                    >
                      <span className={`block font-mono font-bold ${accent.text}`}>
                        {vote.code}
                      </span>
                      <span className="text-xs text-slate-600">{vote.label}</span>
                    </button>
                  );
                })}
              </div>
            </div>

            <div className="mt-5">
              <FieldLabel>Explain your reasoning</FieldLabel>
              <textarea
                value={reasoning}
                onChange={(event) => setReasoning(event.target.value)}
                placeholder={
                  previousShown
                    ? "Write your own reasoning. You may agree or disagree with the prior response, but your judgment should be your own."
                    : "Write your own reasoning about the original dilemma."
                }
                className="h-64 w-full resize-none rounded-lg border border-slate-300 bg-white p-4 text-sm leading-6 text-slate-800 placeholder:text-slate-400 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100 xl:h-[340px]"
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

            {submissionState === "error" && (
              <div className="mt-4 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
                {submissionError}
              </div>
            )}

            <div className="mt-6 flex flex-col gap-3 sm:flex-row">
              <Button
                variant="danger"
                className="sm:w-1/3"
                disabled={submissionState === "submitting"}
                onClick={() =>
                  submitPayload("skipped", {
                    response: { skipReason: "participant_discomfort_or_choice" },
                    postTask: {
                      confidence: "",
                      influence: "",
                      sourceGuess: "",
                      attentionCheck: "",
                    },
                  })
                }
              >
                Skip Scenario
              </Button>
              <Button
                className="sm:flex-1"
                disabled={!canSubmitTask || submissionState === "submitting"}
                onClick={() => setCurrentScreen("postTask")}
              >
                Continue
              </Button>
            </div>
          </Panel>
        </div>
      </Page>
    ),

    postTask: (
      <Page width="max-w-6xl">
        <Progress current="Questions" />
        <Panel className="p-6">
          <h2 className="mb-2 text-2xl font-semibold text-slate-950">
            Follow-up Questions
          </h2>
          <p className="mb-6 text-sm leading-6 text-slate-600">
            Please answer these brief questions about your judgment and the
            information you saw.
          </p>

          <div className="grid gap-6 lg:grid-cols-[minmax(0,1fr)_420px]">
            <div className="space-y-6">
              <div>
                <FieldLabel>How confident are you in your judgment?</FieldLabel>
                <RatingScale
                  value={confidence}
                  onChange={setConfidence}
                  labelLeft="Not confident"
                  labelRight="Very confident"
                />
              </div>

              {previousShown ? (
                <div>
                  <FieldLabel>
                    How much did the prior response influence your judgment?
                  </FieldLabel>
                  <RatingScale
                    value={influence}
                    onChange={setInfluence}
                    labelLeft="Not at all"
                    labelRight="A great deal"
                  />
                </div>
              ) : (
                <div className="rounded-lg border border-slate-200 bg-slate-50 p-4 text-sm leading-6 text-slate-600">
                  No prior response was shown in this assignment, so influence
                  questions are not applicable.
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

              <div className="grid gap-4 sm:grid-cols-3 lg:grid-cols-1">
                <div>
                  <FieldLabel>Age range optional</FieldLabel>
                  <select
                    value={ageRange}
                    onChange={(event) => setAgeRange(event.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800"
                  >
                    <option value="">Prefer not to say</option>
                    <option value="18-24">18-24</option>
                    <option value="25-34">25-34</option>
                    <option value="35-44">35-44</option>
                    <option value="45-54">45-54</option>
                    <option value="55+">55+</option>
                  </select>
                </div>
                <div>
                  <FieldLabel>Gender optional</FieldLabel>
                  <select
                    value={gender}
                    onChange={(event) => setGender(event.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800"
                  >
                    <option value="">Prefer not to say</option>
                    <option value="woman">Woman</option>
                    <option value="man">Man</option>
                    <option value="nonbinary">Non-binary</option>
                    <option value="self_describe">Self-describe</option>
                  </select>
                </div>
                <div>
                  <FieldLabel>Native English optional</FieldLabel>
                  <select
                    value={nativeEnglish}
                    onChange={(event) => setNativeEnglish(event.target.value)}
                    className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800"
                  >
                    <option value="">Prefer not to say</option>
                    <option value="yes">Yes</option>
                    <option value="no">No</option>
                  </select>
                </div>
              </div>
            </div>
          </div>

          {submissionState === "error" && (
            <div className="mt-5 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
              {submissionError}
            </div>
          )}

          <div className="mt-6 flex gap-3">
            <Button variant="secondary" onClick={() => setCurrentScreen("task")}>
              Back
            </Button>
            <Button
              disabled={!canSubmitPostTask || submissionState === "submitting"}
              onClick={() => submitPayload("completed")}
            >
              {submissionState === "submitting" ? "Submitting..." : "Submit"}
            </Button>
          </div>
        </Panel>
      </Page>
    ),

    debrief: (
      <Page width="max-w-5xl">
        <Progress current="Debrief" />
        <Panel className="p-6">
          <h2 className="mb-4 text-2xl font-semibold text-slate-950">
            Debriefing
          </h2>
          <div className="grid gap-5 text-sm leading-6 text-slate-700 md:grid-cols-2">
            <div className="space-y-4">
              <p>
                Thank you for participating. This study examines how moral and
                normative judgments change as responses circulate through
                transmission chains.
              </p>
              <p>
                The broader research question is whether different communication
                environments preserve or compress the range of perspectives
                people bring to everyday moral dilemmas.
              </p>
            </div>
            <div className="space-y-4">
              <p>
                Some prior responses in this research may be generated by AI
                systems rather than human participants. This detail was not fully
                disclosed before the task because knowing the source could change
                how participants evaluate the scenario and prior response.
              </p>
              <p>
                If you have questions or concerns, contact{" "}
                {assignment.contactEmail || "researcher@northwestern.edu"}.
              </p>
            </div>
          </div>

          {saveMode === "local" && (
            <div className="mt-5 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
              Demo mode: this response was saved to browser local storage
              because no submit_url was configured.
            </div>
          )}

          <Button className="mt-6" onClick={() => setCurrentScreen("complete")}>
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
              {assignment.completionCode || "AITA-COMPLETE"}
            </div>
          </div>
        </Panel>
      </Page>
    ),
  };

  return screens[currentScreen] || screens.landing;
};

export default function App() {
  return (
    <TailwindLoader>
      <MoralJudgmentExperiment />
    </TailwindLoader>
  );
}
