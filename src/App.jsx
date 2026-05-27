import React, { useEffect, useMemo, useState } from "react";

const MIN_ADVICE_CHARS = 120;
const CONDITIONS = ["human_comments", "llm_comments"];

const HUMAN_COMMENTS = [
  {
    id: "human-01",
    text: "NTA. That money was left to you specifically. I would not split it just because other people feel awkward about the will.",
  },
  {
    id: "human-02",
    text: "I think you can acknowledge that they feel hurt without giving up the inheritance. Your grandmother made a choice, and it is fair to respect it.",
  },
  {
    id: "human-03",
    text: "NAH, depending on how close everyone was. They are allowed to ask, but you are also allowed to say no.",
  },
  {
    id: "human-04",
    text: "NTA. Family pressure after someone dies can get ugly fast. I would keep the money separate and avoid debating it repeatedly.",
  },
  {
    id: "human-05",
    text: "You do not owe them a three-way split, but maybe consider a small gesture if you want to preserve the relationship.",
  },
  {
    id: "human-06",
    text: "YTA if you are dismissive about why they feel excluded. You can still keep the inheritance, but the way you talk about it matters.",
  },
  {
    id: "human-07",
    text: "NTA. A will is not a group decision. If your grandmother wanted them included, she could have done that.",
  },
  {
    id: "human-08",
    text: "I would not frame it as biological versus step-family. That will cause more damage. Say you are following the will and leave it there.",
  },
  {
    id: "human-09",
    text: "ESH a little. They should not demand money, but you also sound like you are using the inheritance to define who counts as family.",
  },
  {
    id: "human-10",
    text: "Keep the inheritance, but do not let your stepfather turn this into a test of loyalty. It was your grandmother's estate.",
  },
];

const LLM_COMMENTS = [
  {
    id: "llm-01",
    text: "NTA. The inheritance was explicitly left to you, and honoring your grandmother's stated wishes is a reasonable and fair choice.",
  },
  {
    id: "llm-02",
    text: "NTA. You are not obligated to divide money that was legally and personally designated for you, even if others feel disappointed.",
  },
  {
    id: "llm-03",
    text: "NTA. Your grandmother had the opportunity to include your step-siblings and chose not to. Respecting that decision is appropriate.",
  },
  {
    id: "llm-04",
    text: "NTA. Family members may have feelings about the outcome, but emotional discomfort does not create an obligation to redistribute the inheritance.",
  },
  {
    id: "llm-05",
    text: "NTA. You can be empathetic toward your step-siblings while still maintaining a boundary around assets that were intentionally left to you.",
  },
  {
    id: "llm-06",
    text: "NTA. The fairest course is to follow the deceased person's wishes rather than revise them under pressure after the fact.",
  },
  {
    id: "llm-07",
    text: "NTA. Sharing would be generous, but generosity is different from obligation. You are allowed to decline without being wrong.",
  },
  {
    id: "llm-08",
    text: "NTA. Your step-siblings' disappointment is understandable, but it does not override the specific intent expressed in the will.",
  },
  {
    id: "llm-09",
    text: "NTA. A respectful response would be to acknowledge their feelings, explain that you are following the will, and avoid further argument.",
  },
  {
    id: "llm-10",
    text: "NTA. You should not be pressured into changing a clear inheritance decision simply to make the distribution feel more equal.",
  },
];

const DEMO_ASSIGNMENT = {
  assignmentId: "demo-one-shot",
  condition: "human_comments",
  exposureDilemmaId: "inheritance_exposure",
  friendDilemmaId: "family_gift_friend",
  completionCode: "STUDY-COMPLETE",
  submitEndpoint: "",
  contactEmail: "researcher@northwestern.edu",
  exposureDilemma: {
    title: "Refusing to share an inheritance with step-siblings",
    content: `My (28F) grandmother passed away last year and left me a significant inheritance. My mother remarried when I was 15, and I have two step-siblings (26M, 24F) who my grandmother never really bonded with since she met them as teenagers.

My step-siblings are now saying I should split the inheritance three ways since we're "family." My stepfather agrees and says it would be the "right thing to do." My mother is staying neutral but I can tell she's uncomfortable.

I don't think I should have to share money that my grandmother specifically left to me. She had every opportunity to include them in her will and chose not to.`,
  },
  friendDilemma: {
    title: "Your friend is unsure whether to share a family gift",
    content: `Your friend recently received a large graduation gift from an aunt who helped raise them. The aunt did not give similar gifts to your friend's two cousins, who joined the family after remarriage and did not know the aunt as well.

Now the cousins say the gift should be split because everyone is part of the same family. Your friend's parent says sharing would keep the peace, but your friend feels the gift was meant for them personally.

Your friend asks you what they should do and how to think about the situation.`,
  },
  commentFeeds: {
    human_comments: HUMAN_COMMENTS,
    llm_comments: LLM_COMMENTS,
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
      <div className="flex min-h-screen items-center justify-center bg-slate-50 text-slate-700">
        Loading study...
      </div>
    );
  }

  return children;
};

const getQueryParams = () => new URLSearchParams(window.location.search);

const normalizeCondition = (value) => {
  if (value === "human" || value === "human_comments") return "human_comments";
  if (value === "llm" || value === "ai" || value === "llm_comments") {
    return "llm_comments";
  }
  return "";
};

const getDemoCondition = () => {
  const params = getQueryParams();
  const fromUrl = normalizeCondition(params.get("condition"));
  if (fromUrl) return fromUrl;

  const stored = normalizeCondition(window.sessionStorage.getItem("study_condition"));
  if (stored) return stored;

  const sampled = Math.random() < 0.5 ? "human_comments" : "llm_comments";
  window.sessionStorage.setItem("study_condition", sampled);
  return sampled;
};

const getParticipantMeta = () => {
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
    condition:
      normalizeCondition(params.get("condition")) ||
      normalizeCondition(assignment.condition) ||
      getDemoCondition(),
    completionCode: params.get("completion_code") || assignment.completionCode,
    submitEndpoint: params.get("submit_url") || assignment.submitEndpoint,
  };
};

const getVisibleComments = (assignment) => {
  if (Array.isArray(assignment.comments)) return assignment.comments;
  return assignment.commentFeeds?.[assignment.condition] || [];
};

const buildPayload = ({
  assignment,
  participant,
  adviceText,
  ratings,
  demographics,
  timings,
  status,
}) => {
  const comments = getVisibleComments(assignment);

  return {
    schemaVersion: "online-research-study-frontend-v1",
    status,
    submittedAt: new Date().toISOString(),
    assignment: {
      assignmentId: assignment.assignmentId,
      condition: assignment.condition,
      exposureDilemmaId: assignment.exposureDilemmaId,
      friendDilemmaId: assignment.friendDilemmaId,
      commentIds: comments.map((comment) => comment.id || null),
    },
    participant,
    response: {
      adviceText,
      adviceCharCount: adviceText.trim().length,
    },
    ratings,
    demographics,
    timings,
    client: {
      userAgent: window.navigator.userAgent,
      language: window.navigator.language,
    },
  };
};

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

  const key = `research-study-${payload.assignment.assignmentId}-${Date.now()}`;
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
  <section className={`rounded-lg border border-slate-200 bg-white shadow-sm ${className}`}>
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

const Progress = ({ current }) => {
  const steps = ["Consent", "Instructions", "Materials", "Response", "Questions", "Debrief"];
  const index = steps.indexOf(current);

  return (
    <div className="mb-5">
      <div className="mb-2 flex justify-between gap-2 text-xs font-medium text-slate-500">
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

const CommentFeed = ({ comments, compact = false }) => (
  <div className={compact ? "space-y-3" : "grid gap-3 md:grid-cols-2 xl:grid-cols-1"}>
    {comments.map((comment, index) => (
      <article
        key={comment.id || index}
        className="rounded-lg border border-slate-200 bg-slate-50 p-4"
      >
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
          Response {index + 1}
        </div>
        <p className="text-sm leading-6 text-slate-700">{comment.text}</p>
      </article>
    ))}
  </div>
);

const MoralJudgmentExperiment = () => {
  const [assignment, setAssignment] = useState(() =>
    applyQueryOverrides({
      ...DEMO_ASSIGNMENT,
      condition: getDemoCondition(),
    })
  );
  const [loadState, setLoadState] = useState("ready");
  const [loadError, setLoadError] = useState("");
  const [currentScreen, setCurrentScreen] = useState("landing");
  const [agreed, setAgreed] = useState(false);
  const [comprehension, setComprehension] = useState("");
  const [adviceText, setAdviceText] = useState("");
  const [ease, setEase] = useState("");
  const [fluency, setFluency] = useState("");
  const [useFeed, setUseFeed] = useState("");
  const [perceivedAgreement, setPerceivedAgreement] = useState("");
  const [confidence, setConfidence] = useState("");
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

  const participant = useMemo(() => getParticipantMeta(), []);
  const comments = getVisibleComments(assignment);
  const canStart = comprehension === "read-feed-write-advice";
  const canContinueAdvice = adviceText.trim().length >= MIN_ADVICE_CHARS;
  const canSubmit =
    ease &&
    fluency &&
    useFeed &&
    perceivedAgreement &&
    confidence &&
    sourceGuess &&
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
      adviceText: status === "completed" ? adviceText.trim() : "",
      ratings: {
        ease,
        fluency,
        useFeed,
        perceivedAgreement,
        confidence,
        sourceGuess,
        attentionCheck,
        ...extra.ratings,
      },
      demographics: {
        ageRange,
        gender,
        nativeEnglish,
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
              In this study, you will read one anonymized scenario, review a set
              of written responses, and then write a brief response to a related
              scenario. The study takes about 5 to 10 minutes.
            </p>
            <div className="mt-6 grid gap-3 md:grid-cols-3">
              {[
                ["Materials", "One scenario and a set of short written responses."],
                ["Your task", "Write a brief response to a related scenario."],
                ["Data", "Responses are stored without your name and used for research."],
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
              After consent and instructions, the study will open in this
              browser window.
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
                <strong>Study title:</strong> Online Research Study
              </p>
              <p className="mt-4">
                <strong>Purpose:</strong> This research examines how people read
                and respond to written scenarios.
              </p>
              <p className="mt-4">
                <strong>Procedures:</strong> You will read an anonymized scenario
                and a set of responses. You will then provide your own written
                response to a related scenario and answer a few short questions.
              </p>
              <p className="mt-4">
                <strong>Risks:</strong> Some scenarios may involve sensitive
                social situations, including family issues, finances, or
                relationship disagreements. You may skip the scenario if it
                causes discomfort.
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
              <Button variant="secondary" onClick={() => setCurrentScreen("landing")}>
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
                  "Read the first scenario",
                  "The scenario comes from an anonymized online discussion.",
                ],
                [
                  "Review the response feed",
                  "You will see a set of written responses to that scenario. Please read them carefully.",
                ],
                [
                  "Read a related scenario",
                  "The second scenario is similar in broad situation but different in specific details.",
                ],
                [
                  "Write your response",
                  "Imagine a friend is asking you what to do. You may use what you read, or come up with your own response.",
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

          <Panel className="p-4">
            <FieldLabel>Comprehension check</FieldLabel>
            <select
              value={comprehension}
              onChange={(event) => setComprehension(event.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
            >
              <option value="">Select the correct statement</option>
              <option value="summary-only">
                I will only summarize the first scenario.
              </option>
              <option value="read-feed-write-advice">
                I will read a scenario and response feed, then write a response
                to a related scenario.
              </option>
              <option value="skip-reading">
                I should skip the written responses and go directly to the end.
              </option>
            </select>

            <div className="mt-5 flex gap-3">
              <Button variant="secondary" onClick={() => setCurrentScreen("consent")}>
                Back
              </Button>
              <Button
                className="flex-1"
                disabled={!canStart}
                onClick={() => setCurrentScreen("materials")}
              >
                Start Task
              </Button>
            </div>
          </Panel>
        </div>
      </Page>
    ),

    materials: (
      <Page width="max-w-[1600px]">
        <Progress current="Materials" />
        <div className="grid gap-5 xl:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
          <Panel className="overflow-hidden">
            <div className="border-b border-slate-200 px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Scenario
              </p>
              <h2 className="mt-2 text-xl font-semibold leading-7 text-slate-950">
                {assignment.exposureDilemma.title}
              </h2>
            </div>
            <div className="p-5">
              <TextBlock>{assignment.exposureDilemma.content}</TextBlock>
            </div>
          </Panel>

          <Panel className="overflow-hidden">
            <div className="border-b border-slate-200 px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Response Feed
              </p>
              <h3 className="mt-1 text-base font-semibold text-slate-950">
                Please read all {comments.length} responses
              </h3>
            </div>
            <div className="max-h-[640px] overflow-y-auto p-5">
              <CommentFeed comments={comments} />
            </div>
          </Panel>
        </div>

        <div className="mt-5 flex justify-end">
          <Button onClick={() => setCurrentScreen("advice")}>
            Continue
          </Button>
        </div>
      </Page>
    ),

    advice: (
      <Page width="max-w-[1600px]">
        <Progress current="Response" />
        <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_460px]">
          <div className="grid gap-5 lg:grid-cols-[minmax(0,0.9fr)_minmax(0,1.1fr)]">
            <Panel className="overflow-hidden">
              <div className="border-b border-slate-200 px-5 py-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Related Scenario
                </p>
                <h2 className="mt-2 text-xl font-semibold leading-7 text-slate-950">
                  {assignment.friendDilemma.title}
                </h2>
              </div>
              <div className="p-5">
                <TextBlock>{assignment.friendDilemma.content}</TextBlock>
              </div>
            </Panel>

            <Panel className="overflow-hidden">
              <div className="border-b border-slate-200 px-5 py-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                  Response Feed
                </p>
                <h3 className="mt-1 text-base font-semibold text-slate-950">
                  Available for reference
                </h3>
              </div>
              <div className="max-h-[520px] overflow-y-auto p-5">
                <CommentFeed comments={comments} compact />
              </div>
            </Panel>
          </div>

          <Panel className="p-5 xl:sticky xl:top-6 xl:h-fit">
            <h2 className="mb-3 text-xl font-semibold text-slate-950">
              Your Response
            </h2>
            <p className="mb-5 text-sm leading-6 text-slate-600">
              Imagine your friend has this related situation and asks for your
              advice. You can use what you read, or come up with your own advice.
            </p>

            <FieldLabel>Write advice for your friend</FieldLabel>
            <textarea
              value={adviceText}
              onChange={(event) => setAdviceText(event.target.value)}
              placeholder="Write the advice you would give your friend..."
              className="h-72 w-full resize-none rounded-lg border border-slate-300 bg-white p-4 text-sm leading-6 text-slate-800 placeholder:text-slate-400 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100 xl:h-[380px]"
            />
            <div className="mt-2 flex justify-between text-xs">
              <span className="text-slate-500">
                Minimum {MIN_ADVICE_CHARS} characters
              </span>
              <span
                className={
                  adviceText.trim().length >= MIN_ADVICE_CHARS
                    ? "font-semibold text-emerald-700"
                    : "text-slate-500"
                }
              >
                {adviceText.trim().length} characters
              </span>
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
                    ratings: { skipReason: "participant_discomfort_or_choice" },
                  })
                }
              >
                Skip
              </Button>
              <Button
                className="sm:flex-1"
                disabled={!canContinueAdvice || submissionState === "submitting"}
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
            Please answer these brief questions about your response and the
            materials you read.
          </p>

          <div className="grid gap-6 lg:grid-cols-2">
            <div className="space-y-6">
              <div>
                <FieldLabel>How easy was it to think of advice?</FieldLabel>
                <RatingScale
                  value={ease}
                  onChange={setEase}
                  labelLeft="Very difficult"
                  labelRight="Very easy"
                />
              </div>

              <div>
                <FieldLabel>How fluent or natural did writing the advice feel?</FieldLabel>
                <RatingScale
                  value={fluency}
                  onChange={setFluency}
                  labelLeft="Not fluent"
                  labelRight="Very fluent"
                />
              </div>

              <div>
                <FieldLabel>How much did you use the response feed?</FieldLabel>
                <RatingScale
                  value={useFeed}
                  onChange={setUseFeed}
                  labelLeft="Not at all"
                  labelRight="A great deal"
                />
              </div>
            </div>

            <div className="space-y-5">
              <div>
                <FieldLabel>How much did the responses agree with one another?</FieldLabel>
                <RatingScale
                  value={perceivedAgreement}
                  onChange={setPerceivedAgreement}
                  labelLeft="Strongly disagreed"
                  labelRight="Strongly agreed"
                />
              </div>

              <div>
                <FieldLabel>How confident are you in the advice you wrote?</FieldLabel>
                <RatingScale
                  value={confidence}
                  onChange={setConfidence}
                  labelLeft="Not confident"
                  labelRight="Very confident"
                />
              </div>

              <div>
                <FieldLabel>What do you think the response feed came from?</FieldLabel>
                <select
                  value={sourceGuess}
                  onChange={(event) => setSourceGuess(event.target.value)}
                  className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
                >
                  <option value="">Select one</option>
                  <option value="people">People online</option>
                  <option value="ai">An AI system</option>
                  <option value="mixed">A mix of people and AI</option>
                  <option value="not_sure">Not sure</option>
                </select>
              </div>

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

              <div className="grid gap-4 sm:grid-cols-3">
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
            <Button variant="secondary" onClick={() => setCurrentScreen("advice")}>
              Back
            </Button>
            <Button
              disabled={!canSubmit || submissionState === "submitting"}
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
                Thank you for participating. This study examines how exposure to
                different kinds of advice affects the advice people later give
                about a related situation.
              </p>
              <p>
                Some participants saw comments written by human commenters, and
                others saw comments generated by large language models. This was
                not disclosed before the task because knowing the source could
                change how people use the response feed.
              </p>
            </div>
            <div className="space-y-4">
              <p>
                The main research questions concern whether model-generated
                advice leads to more homogeneous responses, whether it shifts the
                themes people emphasize, and whether it makes advice feel easier
                or more fluent to produce.
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
            Done
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
              {assignment.completionCode || "STUDY-COMPLETE"}
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
