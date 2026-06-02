import React, { useEffect, useMemo, useState } from "react";

const MIN_ADVICE_CHARS = 80;
const FEED_COMMENT_COUNT = 5;
const DEFAULT_COMPLETION_CODE = "ADVICE2026";
const DEFAULT_CONTACT_EMAIL = "william.brady@kellogg.northwestern.edu";

const INFORMED_CONSENT_TEXT = `Principal Investigator: William J. Brady

Supported By: This research is supported by Northwestern University’s Kellogg School of Management, approved by NU IRB on 11/9/22, IRB #: STU00218134

Key Information about this research study
The following is a short summary of this study to help you decide whether to be a part of this study. Information that is more detailed is explained later on in this form.

	•	The purpose of this study is to gain a deeper understanding of your attitudes, beliefs, and opinions on various topics.
	•	You will be asked to complete a set of questionnaires. You may also be asked to do activities like judging messages written in different contexts.
	•	We expect that you will be in this research study for around 8 minutes.
	•	The primary potential risk of participation is emotional distress from thinking about politically charged issues.
	•	The main benefit of being in this study is contributing to the scientific understanding of how the mind works and society functions.
	•	We cannot tell you every detail of this study ahead of time, but if you are willing to participate under these conditions, we will explain the procedure to you fully after your participation

Why am I being asked to take part in this research study?
We are asking you to take part in this research study because you at least 18 years of age and are living in the U.S. and because we are interested in your opinions and experiences.

How many people will be in this study?
We expect about 600 people will be in this research study.

What should I know about participating in a research study?
	•	Whether or not you take part is up to you.
	•	You can choose not to take part.
	•	You can agree to take part and later change your mind.
	•	Your decision will not be held against you.
	•	You can ask all the questions you want before you decide.
	•	You do not have to answer any question you do not want to answer.

What happens if I say, “Yes, I want to be in this research”?
If you agree to participate, you will complete a research survey. The survey asks about your agreement or disagreement with various statements, along with free-response items. The topics include your attitudes and opinions about various topics, including your personal relationships and your political views. It includes some comprehension questions intended to make sure you understand information you have read.

Will being in this study help me in any way?
We cannot promise any benefits to you or others from your taking part in this research. However, possible benefits include the inherent interest value you may find in responding to the surveys and the value in contributing to society’s understanding of the human mind.

Is there any way being in this study could be bad for me?
We do not foresee any risk in participating in this study. If you choose to participate, the effects should be comparable to those you would experience from completing a task and answering questions for few minutes using a mouse and keyboard (or using your smartphone). It is possible that you might be uncomfortable answering certain questions; if that happens, you may simply leave them blank. A possible risk for any research is that confidentiality could be compromised—that people outside the study might get hold of confidential study information. We will do everything we can to minimize this risk, as described in more detail later in this form.

What happens if I do not want to be in this research, or I change my mind later?
Participation in this research is voluntary. You may decide to participate or not to participate. If you do not want to be in this study or withdraw from the study at any point, your decision will not affect your compensation or relationship with Northwestern University in any way. You can leave the research at any time and it will not be held against you.

How will the researchers protect my information?
Data will be collected anonymously and will not be labeled with any identifying information. Moreover, data will be stored electronically on a password protected cloud storage service. The collection of information about participants is limited to the amount necessary to achieve the aims of research, so that no unneeded information is being collected.

Who will have access to the information collected during this research study?
Efforts will be made to limit the use and disclosure of your personal information, including research study records, to people who have a need to review this information. We cannot promise complete secrecy.

There are reasons why information about you may be used or seen by other people beyond the research team during or after this study.

Examples include:
University officials, government officials, study funders, auditors, and the Institutional Review Board may need access to the study information to make sure the study is done in a safe and appropriate manner.

How might the information collected in this study be shared in the future?
We will keep the information we collect about you during this research study for study recordkeeping. Your name and other information that can directly identify you will be stored securely and separately from the rest of the research information we collect from you.

De-identified data from this study may be shared with the research community, with journals in which study results are published, and with databases and data repositories used for research. We will remove or code any personal information that could directly identify you before the study data are shared. Despite these measures, we cannot guarantee the anonymity of your personal data.

The results of this study could be shared in articles and presentations, but will not include any information that identifies you unless you give permission for use of information that identifies you in articles and presentations.

Will I be paid or given anything for taking part in this study?
You will receive $1.50 for your participation in this 8-minute study.

Who can I talk to?
If you have questions, concerns, or complaints, you can contact the Principal Investigator, William Brady, at william.brady@kellogg.northwestern.edu (or, if email doesn’t work for you, via phone at 704-904-6420.

This research has been reviewed and approved by an Institutional Review Board (“IRB”) – an IRB is a committee that protects the rights of people who participate in research studies. You may contact the IRB by phone at (312) 503-9338 or by email at irb@northwestern.edu if:
	•	Your questions, concerns, or complaints are not being answered by the research team.
	•	You cannot reach the research team.
	•	You want to talk to someone besides the research team.
	•	You have questions about your rights as a research participant.
	•	You want to get information or provide input about this research.

Consent
If you want a copy of this consent for your records, you can print it from the screen.

If you cannot print the consent and would like a copy for your records, contact the Principal Investigator with the contact information above.

If you wish to participate, please click the “I Agree” button and you will be taken to the survey.

If you do not wish to participate in this study, please select “I Disagree” or select X in the corner of your browser.`;

const DEMO_ASSIGNMENT = {
  assignmentId: "demo-advice-assignment",
  completionCode: "ADVICE-DEMO-COMPLETE",
  contactEmail: DEFAULT_CONTACT_EMAIL,
  slotId: "demo-slot-human",
  condition: "human_comments",
  status: "claimed",
  comprehensionFailures: 0,
  stimulus: {
    id: "demo_family_help",
    exposureTitle: "AITA for not helping my sibling move after they ignored my boundaries?",
    exposureBody: `My sibling asked me to spend my only free weekend helping them move apartments. I said I could help for a few hours, but not the whole weekend, because I had already made plans and needed some rest after a difficult work week.

They got upset and said family should show up when needed. I reminded them that they had refused to help me several times in the past and often dismissed my boundaries. Now my parents say I should put the conflict aside because moving is stressful.

I feel guilty, but I also feel like I am always expected to be available. AITA?`,
    friendTitle: "Your friend is unsure whether to help a cousin who often ignores their limits",
    friendBody: `Your friend says their cousin asked them to give up an entire weekend to help with a last-minute move. Your friend wants to be supportive, but the cousin has repeatedly ignored their boundaries and rarely helps in return.

Your friend could help for part of the day, but not the whole weekend. Their family is pressuring them to be more generous because the cousin is stressed. Your friend asks what advice you would give.`,
    moralThemeMetadata: {
      themes: ["relational obligation", "fairness", "boundaries"],
      pairType: "demo",
    },
  },
  comments: [
    "You can care about family and still have limits. I would offer the amount of help you honestly can give and be clear that the rest of the weekend is not available.",
    "Helping for a few hours sounds reasonable. The issue is not whether moving is stressful, it is whether one person gets to demand unlimited time from everyone else.",
    "I would tell them that family support should go both ways. If they usually ignore your needs, it is fair to protect your own time.",
    "You are not obligated to cancel your whole weekend. Offer a concrete window, then let them decide whether that help is useful.",
    "It might be worth separating the old resentment from the current request. Still, that does not mean you have to give more than you can handle.",
    "I would help a little if you want to keep peace, but I would not reward guilt-tripping by giving up the entire weekend.",
    "Your parents can help if they think the move requires more support. They should not volunteer your time for you.",
    "A boundary is only real if you keep it when someone is disappointed. A few hours of help is already a compromise.",
    "I would be calm and direct: I can help Saturday morning, but I cannot do the full weekend. No long debate needed.",
    "Family obligations matter, but they do not erase fairness. You can be kind without becoming the default person everyone leans on.",
  ],
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

const getSupabaseConfig = () => {
  const params = getQueryParams();
  const url =
    params.get("supabase_url") ||
    import.meta.env.VITE_SUPABASE_URL ||
    "";
  const anonKey =
    params.get("supabase_anon_key") ||
    params.get("supabase_key") ||
    import.meta.env.VITE_SUPABASE_ANON_KEY ||
    "";

  if (!url || !anonKey) return null;

  return {
    url: url.replace(/\/$/, ""),
    anonKey,
    completionCode:
      params.get("completion_code") ||
      import.meta.env.VITE_ADVICE_COMPLETION_CODE ||
      DEFAULT_COMPLETION_CODE,
    contactEmail:
      params.get("contact_email") ||
      import.meta.env.VITE_RESEARCH_CONTACT_EMAIL ||
      DEFAULT_CONTACT_EMAIL,
  };
};

const normalizeAssignment = (assignment) => ({
  ...DEMO_ASSIGNMENT,
  ...assignment,
  stimulus: {
    ...DEMO_ASSIGNMENT.stimulus,
    ...(assignment.stimulus || {}),
  },
  comments: Array.isArray(assignment.comments)
    ? assignment.comments.slice(0, FEED_COMMENT_COUNT)
    : DEMO_ASSIGNMENT.comments,
});

const supabaseRpc = async (config, fnName, body) => {
  const response = await fetch(`${config.url}/rest/v1/rpc/${fnName}`, {
    method: "POST",
    headers: {
      apikey: config.anonKey,
      Authorization: `Bearer ${config.anonKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  const data = text ? JSON.parse(text) : null;

  if (!response.ok) {
    throw new Error(data?.message || `Supabase request failed with HTTP ${response.status}`);
  }

  return data;
};

const claimAdviceAssignment = async ({ config, participant }) => {
  if (!participant.prolificPid) {
    throw new Error("Missing PROLIFIC_PID. Open this study from Prolific or add PROLIFIC_PID=test to the URL for testing.");
  }

  const data = await supabaseRpc(config, "claim_advice_assignment", {
    p_prolific_pid: participant.prolificPid,
    p_study_id: participant.studyId || null,
    p_session_id: participant.sessionId || null,
    p_completion_code: config.completionCode,
    p_contact_email: config.contactEmail,
    p_feed_size: FEED_COMMENT_COUNT,
  });

  return {
    ...data,
    backend: {
      type: "supabase",
      config,
    },
  };
};

const recordComprehensionFailure = async ({ assignment, participant, selectedOption }) => {
  const fallbackAttempts = (Number(assignment.comprehensionFailures) || 0) + 1;

  if (assignment.backend?.type !== "supabase") {
    return {
      comprehensionFailures: fallbackAttempts,
      screenedOut: fallbackAttempts >= 2,
    };
  }

  return supabaseRpc(
    assignment.backend.config,
    "record_advice_comprehension_failure",
    {
      p_assignment_id: assignment.assignmentId,
      p_selected_option: selectedOption,
      p_payload: {
        participant,
        selectedOption,
        occurredAt: new Date().toISOString(),
        userAgent: window.navigator.userAgent,
      },
    }
  );
};

const savePayload = async (assignment, payload) => {
  if (assignment.backend?.type === "supabase") {
    await supabaseRpc(assignment.backend.config, "submit_advice_payload", {
      p_assignment_id: assignment.assignmentId,
      p_payload: payload,
    });
    return { mode: "supabase" };
  }

  const key = `advice-study-${payload.assignment.assignmentId}-${Date.now()}`;
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

const ConsentText = () => (
  <div className="max-h-[620px] overflow-y-auto whitespace-pre-wrap rounded-lg border border-slate-200 bg-slate-50 p-5 text-sm leading-6 text-slate-700">
    {INFORMED_CONSENT_TEXT}
  </div>
);

const FieldLabel = ({ children }) => (
  <label className="mb-2 block text-sm font-semibold text-slate-700">
    {children}
  </label>
);

const SourceTextBlock = ({ children, className = "", onBlockedCopy }) => {
  const blockCopy = (event) => {
    event.preventDefault();
    window.getSelection()?.removeAllRanges();
    onBlockedCopy?.();
  };

  return (
    <div
      className={`select-none ${className}`}
      onCopy={blockCopy}
      onCut={blockCopy}
      onContextMenu={(event) => event.preventDefault()}
    >
      {children}
    </div>
  );
};

const LikertItem = ({ label, prompt, value, onChange, left, center, right }) => (
  <div className="rounded-lg border border-slate-200 bg-slate-50 p-4">
    <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
      {label}
    </div>
    <p className="mb-3 text-sm font-semibold leading-6 text-slate-900">
      {prompt}
    </p>
    <div className="grid grid-cols-7 gap-1.5">
      {[1, 2, 3, 4, 5, 6, 7].map((score) => (
        <button
          key={score}
          type="button"
          onClick={() => onChange(String(score))}
          className={`h-10 rounded-lg border text-sm font-semibold transition ${
            value === String(score)
              ? "border-slate-900 bg-slate-900 text-white"
              : "border-slate-300 bg-white text-slate-700 hover:bg-slate-100"
          }`}
          aria-label={`${label}: ${score}`}
        >
          {score}
        </button>
      ))}
    </div>
    <div className="mt-2 grid grid-cols-3 gap-2 text-[11px] leading-4 text-slate-500">
      <span>1 - {left}</span>
      <span className="text-center">4 - {center}</span>
      <span className="text-right">7 - {right}</span>
    </div>
  </div>
);

const CommentFeed = ({ comments, onBlockedCopy }) => (
  <SourceTextBlock onBlockedCopy={onBlockedCopy} className="space-y-3">
    {comments.map((comment, index) => (
      <article
        key={`${index}-${comment.slice(0, 24)}`}
        className="rounded-lg border border-slate-200 bg-slate-50 p-4"
      >
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
          Comment {index + 1}
        </div>
        <p className="whitespace-pre-line text-sm leading-6 text-slate-700">
          {comment}
        </p>
      </article>
    ))}
  </SourceTextBlock>
);

const AdviceTask = () => {
  const [assignment, setAssignment] = useState(() => normalizeAssignment(DEMO_ASSIGNMENT));
  const [loadState, setLoadState] = useState("ready");
  const [loadError, setLoadError] = useState("");
  const [screen, setScreen] = useState("landing");
  const [agreed, setAgreed] = useState(false);
  const [comprehension, setComprehension] = useState("");
  const [comprehensionAttempts, setComprehensionAttempts] = useState(0);
  const [comprehensionError, setComprehensionError] = useState("");
  const [adviceText, setAdviceText] = useState("");
  const [ease, setEase] = useState("");
  const [fluency, setFluency] = useState("");
  const [confidence, setConfidence] = useState("");
  const [copyWarning, setCopyWarning] = useState("");
  const [pasteWarning, setPasteWarning] = useState("");
  const [submissionState, setSubmissionState] = useState("idle");
  const [submissionError, setSubmissionError] = useState("");
  const [saveMode, setSaveMode] = useState("");
  const [timings, setTimings] = useState({
    loadedAt: new Date().toISOString(),
    screens: {},
  });

  const participant = useMemo(() => getProlificMeta(), []);
  const canSubmit =
    adviceText.trim().length >= MIN_ADVICE_CHARS &&
    ease &&
    fluency &&
    confidence;

  useEffect(() => {
    const supabaseConfig = getSupabaseConfig();

    if (!supabaseConfig) {
      if (participant.prolificPid) {
        setLoadState("error");
        setLoadError(
          "No backend is configured. Set Supabase environment variables before launching on Prolific."
        );
      }
      return;
    }

    const loadAssignment = async () => {
      setLoadState("loading");
      setLoadError("");

      try {
        const remoteAssignment = await claimAdviceAssignment({
          config: supabaseConfig,
          participant,
        });
        const normalizedAssignment = normalizeAssignment(remoteAssignment);
        const failureCount = Number(normalizedAssignment.comprehensionFailures) || 0;

        setAssignment(normalizedAssignment);
        setComprehensionAttempts(failureCount);

        if (normalizedAssignment.status === "screened_out" || failureCount >= 2) {
          setScreen("comprehension_failed");
        } else if (normalizedAssignment.status === "submitted") {
          setScreen("complete");
        } else {
          setScreen("landing");
        }
      } catch (error) {
        setLoadState("error");
        setLoadError(error.message);
      } finally {
        setLoadState((current) => (current === "error" ? "error" : "ready"));
      }
    };

    loadAssignment();
  }, [participant.prolificPid, participant.sessionId, participant.studyId]);

  useEffect(() => {
    setTimings((current) => ({
      ...current,
      screens: {
        ...current.screens,
        [screen]: current.screens[screen] || new Date().toISOString(),
      },
    }));
  }, [screen]);

  const handleBlockedCopy = () => {
    setCopyWarning("Please use your own words instead of copying text from the study materials.");
  };

  const handleComprehensionChange = async (value) => {
    if (!value) {
      setComprehension("");
      return;
    }

    if (value === "own-advice") {
      setComprehension(value);
      setComprehensionError("");
      return;
    }

    let nextAttempts = comprehensionAttempts + 1;
    let screenedOut = nextAttempts >= 2;

    try {
      const result = await recordComprehensionFailure({
        assignment,
        participant,
        selectedOption: value,
      });

      nextAttempts =
        Number(result.comprehensionFailures) ||
        Number(result.attempts) ||
        nextAttempts;
      screenedOut =
        Boolean(result.screenedOut) ||
        result.status === "screened_out" ||
        nextAttempts >= 2;

      setAssignment((current) => ({
        ...current,
        status: result.status || (screenedOut ? "screened_out" : current.status),
        comprehensionFailures: nextAttempts,
      }));
    } catch (error) {
      setComprehension("");
      setComprehensionError(
        "Could not save the comprehension-check result. Please refresh and try again."
      );
      return;
    }

    setComprehensionAttempts(nextAttempts);
    setComprehension("");

    if (screenedOut) {
      setScreen("comprehension_failed");
      return;
    }

    setComprehensionError("Incorrect, please try again.");
    window.alert("Incorrect, please try again.");
  };

  const submit = async () => {
    setSubmissionState("submitting");
    setSubmissionError("");

    const payload = {
      schemaVersion: "one-shot-advice-exposure-v1",
      status: "completed",
      submittedAt: new Date().toISOString(),
      assignment: {
        assignmentId: assignment.assignmentId,
        completionCode: assignment.completionCode,
        slotId: assignment.slotId,
        condition: assignment.condition,
        stimulusId: assignment.stimulus.id,
      },
      participant,
      stimulus: {
        id: assignment.stimulus.id,
        moralThemeMetadata: assignment.stimulus.moralThemeMetadata || {},
        exposureTitle: assignment.stimulus.exposureTitle,
        friendTitle: assignment.stimulus.friendTitle,
        commentCount: assignment.comments.length,
      },
      response: {
        adviceText: adviceText.trim(),
        adviceCharCount: adviceText.trim().length,
      },
      postTask: {
        ease: Number(ease),
        fluency: Number(fluency),
        confidence: Number(confidence),
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
              In this study, you will read one anonymous, public online post
              about a social dilemma, along with several comments about it. You
              will then write advice for a friend facing a similar situation and
              answer a few short follow-up questions.
            </p>
            <div className="mt-6 grid gap-3 md:grid-cols-2">
              {[
                ["Task", `1 post, ${FEED_COMMENT_COUNT} prior comments, and 1 advice response`],
                ["Time", "Most participants take 8 to 10 minutes."],
              ].map(([label, value]) => (
                <div
                  key={label}
                  className="rounded-lg border border-slate-200 bg-slate-50 p-4"
                >
                  <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                    {label}
                  </div>
                  <div className="mt-2 text-sm font-semibold text-slate-900">
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
            <ConsentText />
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
              <Button
                variant="secondary"
                onClick={() => {
                  setAgreed(false);
                  setScreen("declined");
                }}
              >
                I Disagree
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

    declined: (
      <Page width="max-w-2xl">
        <Panel className="p-8">
          <h2 className="text-2xl font-semibold text-slate-950">
            Participation Declined
          </h2>
          <p className="mt-4 text-sm leading-6 text-slate-600">
            You have chosen not to participate in this study. You may close this
            browser window or return to the crowdsourcing platform.
          </p>
          <Button className="mt-6" variant="secondary" onClick={() => setScreen("consent")}>
            Back to Consent
          </Button>
        </Panel>
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
            <div className="space-y-4 rounded-lg border border-slate-200 bg-slate-50 p-5 text-sm leading-7 text-slate-700">
              <p>
                You will read a public online post about a social dilemma and a
                set of comments about that situation.
              </p>
              <p>
                Next, you will imagine that a friend has a similar but different
                dilemma and needs advice. You can use what you read, or come up
                with your own advice. Please write the advice in your own words.
              </p>
              <p>
                Please do not use outside tools, copy text from the study
                materials, or paste text into your response. We are interested
                in your own reaction after reading the materials.
              </p>
            </div>
          </Panel>

          <Panel className="p-5 lg:sticky lg:top-6 lg:h-fit">
            <FieldLabel>Comprehension check</FieldLabel>
            <p className="mb-3 text-sm leading-6 text-slate-600">
              To make sure we're on the same page, select what you will be doing
              in this task:
            </p>
            <select
              value={comprehension}
              onChange={(event) => handleComprehensionChange(event.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
            >
              <option value="">Select the correct statement</option>
              <option value="copy-comment">
                I will copy one of the comments exactly into my answer.
              </option>
              <option value="rate-comments">
                I will rate each comment instead of writing advice.
              </option>
              <option value="own-advice">
                I will read a dilemma and comments, then write my own advice for
                a friend with a similar dilemma.
              </option>
              <option value="summarize-only">
                I will only summarize the first post and stop there.
              </option>
            </select>
            {comprehensionError && (
              <div className="mt-3 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
                {comprehensionError}
              </div>
            )}
            <div className="mt-5 flex gap-3">
              <Button variant="secondary" onClick={() => setScreen("consent")}>
                Back
              </Button>
              <Button
                className="flex-1"
                disabled={comprehension !== "own-advice"}
                onClick={() => setScreen("exposure")}
              >
                Start Task
              </Button>
            </div>
          </Panel>
        </div>
      </Page>
    ),

    comprehension_failed: (
      <Page width="max-w-2xl">
        <Panel className="p-8">
          <h2 className="text-2xl font-semibold text-slate-950">
            Study Ended
          </h2>
          <p className="mt-4 text-sm leading-6 text-slate-600">
            You did not pass the comprehension check, so this study has ended.
            Please return to the platform. No completion code is available.
          </p>
        </Panel>
      </Page>
    ),

    exposure: (
      <Page width="max-w-[1500px]">
        <StudyHeader assignment={assignment} />
        <div className="grid gap-5 xl:grid-cols-[minmax(0,1fr)_560px]">
          <Panel className="overflow-hidden">
            <div className="border-b border-slate-200 px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Online Post
              </p>
              <h2 className="mt-2 text-xl font-semibold leading-7 text-slate-950">
                {assignment.stimulus.exposureTitle}
              </h2>
            </div>
            <SourceTextBlock onBlockedCopy={handleBlockedCopy} className="p-5">
              <div className="whitespace-pre-line text-sm leading-7 text-slate-700">
                {assignment.stimulus.exposureBody}
              </div>
            </SourceTextBlock>
          </Panel>

          <Panel className="p-5">
            <h2 className="mb-3 text-xl font-semibold text-slate-950">
              Comments
            </h2>
            <p className="mb-4 text-sm leading-6 text-slate-600">
              Please read these comments carefully before continuing.
            </p>
            <div className="max-h-[68vh] overflow-y-auto pr-1">
              <CommentFeed
                comments={assignment.comments}
                onBlockedCopy={handleBlockedCopy}
              />
            </div>
          </Panel>
        </div>

        {copyWarning && (
          <div className="mt-4 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
            {copyWarning}
          </div>
        )}

        <div className="mt-5 flex justify-end">
          <Button onClick={() => setScreen("advice")}>Continue</Button>
        </div>
      </Page>
    ),

    advice: (
      <Page width="max-w-6xl">
        <StudyHeader assignment={assignment} />
        <div className="grid gap-5 lg:grid-cols-[minmax(0,1fr)_460px]">
          <Panel className="overflow-hidden">
            <div className="border-b border-slate-200 px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Friend's Dilemma
              </p>
              <h2 className="mt-2 text-xl font-semibold leading-7 text-slate-950">
                {assignment.stimulus.friendTitle}
              </h2>
            </div>
            <SourceTextBlock onBlockedCopy={handleBlockedCopy} className="p-5">
              <div className="whitespace-pre-line text-sm leading-7 text-slate-700">
                {assignment.stimulus.friendBody}
              </div>
            </SourceTextBlock>
          </Panel>

          <Panel className="p-5 lg:sticky lg:top-6 lg:h-fit">
            <h2 className="mb-3 text-xl font-semibold text-slate-950">
              Write Advice
            </h2>
            <p className="mb-4 rounded-lg border border-slate-200 bg-slate-50 p-4 text-sm leading-6 text-slate-700">
              Imagine your friend has a similar dilemma and needs advice. You
              can use what you read, or come up with your own advice.
            </p>
            <textarea
              value={adviceText}
              onChange={(event) => setAdviceText(event.target.value)}
              onPaste={(event) => {
                event.preventDefault();
                setPasteWarning("Please type your advice in your own words instead of pasting text.");
              }}
              onDrop={(event) => event.preventDefault()}
              className="h-64 w-full resize-none rounded-lg border border-slate-300 bg-white p-4 text-sm leading-6 text-slate-800 placeholder:text-slate-400 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
              placeholder="Write the advice you would give your friend..."
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
            {pasteWarning && (
              <div className="mt-3 rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
                {pasteWarning}
              </div>
            )}
            <div className="mt-5 flex gap-3">
              <Button variant="secondary" onClick={() => setScreen("exposure")}>
                Back
              </Button>
              <Button
                className="flex-1"
                disabled={adviceText.trim().length < MIN_ADVICE_CHARS}
                onClick={() => setScreen("questions")}
              >
                Continue
              </Button>
            </div>
          </Panel>
        </div>
      </Page>
    ),

    questions: (
      <Page width="max-w-5xl">
        <StudyHeader assignment={assignment} />
        <Panel className="p-6">
          <h2 className="mb-2 text-2xl font-semibold text-slate-950">
            Follow-up Questions
          </h2>
          <p className="mb-6 text-sm leading-6 text-slate-600">
            Please answer these short questions about the advice you just wrote.
          </p>
          <div className="grid gap-4">
            <LikertItem
              label="Question 1"
              prompt="How easy or difficult was it to come up with advice for your friend?"
              value={ease}
              onChange={setEase}
              left="Very difficult"
              center="Neither easy nor difficult"
              right="Very easy"
            />
            <LikertItem
              label="Question 2"
              prompt="How smoothly did the advice come to mind?"
              value={fluency}
              onChange={setFluency}
              left="Not smoothly at all"
              center="Moderately smoothly"
              right="Very smoothly"
            />
            <LikertItem
              label="Question 3"
              prompt="How confident are you in the advice you gave?"
              value={confidence}
              onChange={setConfidence}
              left="Not confident at all"
              center="Moderately confident"
              right="Very confident"
            />
          </div>

          {submissionState === "error" && (
            <div className="mt-5 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-800">
              {submissionError}
            </div>
          )}

          <div className="mt-6 flex gap-3">
            <Button variant="secondary" onClick={() => setScreen("advice")}>
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
                Thank you for participating. This study examines how people use
                advice they have read when giving advice about a similar social
                dilemma.
              </p>
              <p>
                Some comment sets in this research may come from human-written
                comments, and others may come from language model outputs. This
                detail was not disclosed before the task because knowing the
                source could change how participants process the comments.
              </p>
            </div>
            <div className="space-y-4">
              <p>
                If you have questions or concerns, contact{" "}
                {assignment.contactEmail || DEFAULT_CONTACT_EMAIL}.
              </p>
              {saveMode === "local" && (
                <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-amber-900">
                  Demo mode: this response was saved to browser local storage
                  because no backend was configured.
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
            Your response has been submitted. Please return to the platform and
            enter the completion code below.
          </p>
          <div className="mx-auto mt-6 max-w-sm rounded-lg border border-slate-200 bg-slate-50 p-4">
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Completion Code
            </div>
            <div className="mt-2 select-all font-mono text-lg font-semibold text-slate-950">
              {assignment.completionCode || DEFAULT_COMPLETION_CODE}
            </div>
          </div>
        </Panel>
      </Page>
    ),
  };

  return screens[screen] || screens.landing;
};

export default function AdviceTaskApp() {
  return (
    <TailwindLoader>
      <AdviceTask />
    </TailwindLoader>
  );
}
