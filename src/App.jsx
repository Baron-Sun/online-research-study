import React, { useEffect, useMemo, useState } from "react";

const POSTS_PER_WORKER = 5;
const DEFAULT_COMPLETION_CODE = "RATING2026";
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

const RATING_ITEMS = [
  {
    key: "op_wrong",
    label: "Question 1",
    prompt:
      "To what extent do you think the OP (original poster) is in the wrong in this situation?",
    anchors: {
      1: "Definitely not in the wrong",
      4: "Unclear / both sides have a point",
      7: "Definitely in the wrong",
    },
  },
  {
    key: "ambivalence",
    label: "Question 2",
    prompt: "How torn or conflicted do you feel about who is in the wrong in this situation?",
    anchors: {
      1: "Not torn at all; the answer is clear to me",
      4: "Somewhat torn",
      7: "Extremely torn; I genuinely cannot decide",
    },
  },
  {
    key: "perceived_disagreement",
    label: "Question 3",
    prompt:
      "If 100 thoughtful people read this post, what would their responses look like?",
    anchors: {
      1: "Deep agreement - nearly everyone would respond the same way",
      4: "Moderate disagreement",
      7: "Deep disagreement; people would strongly oppose each other",
    },
  },
];

const SELF_RATING_ITEMS = RATING_ITEMS.slice(0, 2);
const OTHERS_RATING_ITEMS = RATING_ITEMS.slice(2);

const POST_TASK_DIFFICULTY_ITEM = {
  key: "disagreement_difficulty",
  label: "Post-task question",
  prompt: "How difficult was it to judge whether other people would disagree?",
  anchors: {
    1: "Not difficult at all",
    4: "Moderately difficult",
    7: "Extremely difficult",
  },
};

const DEMO_ASSIGNMENT = {
  assignmentId: "demo-rating-assignment",
  completionCode: "ONLINE-DEMO-COMPLETE",
  submitEndpoint: "",
  contactEmail: DEFAULT_CONTACT_EMAIL,
  posts: [
    {
      id: "demo_001",
      sourceBin: "medium",
      title: "AITA for not sharing my inheritance with my step-siblings?",
      body: `My grandmother passed away last year and left me a significant inheritance. My mother remarried when I was 15, and I have two step-siblings who my grandmother met when they were already teenagers.

My step-siblings now say I should split the inheritance three ways because we are family. My stepfather agrees and says it would be the right thing to do. My mother is staying neutral, but I can tell she is uncomfortable.

I do not think I should have to share money that my grandmother specifically left to me. She had every opportunity to include them in her will and chose not to. AITA?`,
    },
    {
      id: "demo_002",
      sourceBin: "high",
      title: "AITA for leaving a group trip after my friends changed the plan?",
      body: `I planned a weekend trip with four friends and booked a small cabin. The original plan was hiking, cooking dinner, and relaxing. Two days before the trip, they told me they had invited three more people I barely know and wanted to turn it into more of a party weekend.

I said that was not what I agreed to and asked them to keep the original plan. They said I was being controlling because everyone else was excited. I ended up canceling my share and not going.

Now they are upset because the cabin cost more per person without me. AITA?`,
    },
    {
      id: "demo_003",
      sourceBin: "low",
      title: "AITA for asking my roommate to replace food they ate?",
      body: `I live with two roommates. We normally buy our own groceries and label anything that is not shared. Last week I bought ingredients for lunches for the whole week and labeled the containers.

One roommate ate most of it over two days. When I asked them to replace it, they said they were short on money and thought I would not mind because I usually cook a lot. I said I needed that food for work lunches and asked them to pay me back when they could.

They said I was making a big deal out of food. AITA?`,
    },
    {
      id: "demo_004",
      sourceBin: "high",
      title: "AITA for telling my sister I would not attend her wedding?",
      body: `My sister is getting married next month. We have had a strained relationship for years, mostly because she often makes jokes about my career and relationship in front of other people.

At a family dinner she made another joke about me being the family disappointment. I told her privately afterward that it hurt and asked her to stop. She said I was too sensitive and that everyone knew she was joking.

I told her I did not want to attend the wedding if she could not treat me with basic respect. My parents say I am escalating things right before an important family event. AITA?`,
    },
    {
      id: "demo_005",
      sourceBin: "medium",
      title: "AITA for refusing to lend money to a friend again?",
      body: `A close friend has borrowed money from me several times over the past year. They usually pay it back, but often later than promised. Last month they asked for another loan to cover rent.

I told them I could not keep being their backup plan and suggested they talk to family or their landlord. They got upset and said I knew how stressful their situation was.

I feel bad because I technically could afford to help, but I also feel used. AITA?`,
    },
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

const useGlobalClipboardBlock = () => {
  useEffect(() => {
    const blockClipboard = (event) => {
      event.preventDefault();
      window.getSelection()?.removeAllRanges();
    };

    const blockedEvents = [
      "copy",
      "cut",
      "paste",
      "drop",
      "dragstart",
      "contextmenu",
    ];

    blockedEvents.forEach((eventName) => {
      document.addEventListener(eventName, blockClipboard, true);
    });

    return () => {
      blockedEvents.forEach((eventName) => {
        document.removeEventListener(eventName, blockClipboard, true);
      });
    };
  }, []);
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

const hashString = (input) => {
  let hash = 2166136261;
  for (let index = 0; index < input.length; index += 1) {
    hash ^= input.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
};

const seededRandom = (seed) => {
  let state = seed || 1;
  return () => {
    state = Math.imul(1664525, state) + 1013904223;
    return ((state >>> 0) / 4294967296);
  };
};

const seededShuffle = (items, seedText) => {
  const shuffled = [...items];
  const random = seededRandom(hashString(seedText));

  for (let index = shuffled.length - 1; index > 0; index -= 1) {
    const swapIndex = Math.floor(random() * (index + 1));
    [shuffled[index], shuffled[swapIndex]] = [shuffled[swapIndex], shuffled[index]];
  }

  return shuffled;
};

const normalizePost = (post, index) => ({
  id: String(post.id || post.submission_id || post.post_id || `post_${index + 1}`),
  title: post.title || `Post ${index + 1}`,
  body: post.body || post.content || post.selftext || post.text || "",
  sourceBin: post.sourceBin || post.bin || post.disagreement_bin || null,
  metadata: post.metadata || {},
});

const normalizeAssignment = (assignment) => {
  const posts = Array.isArray(assignment.posts)
    ? assignment.posts
    : Array.isArray(assignment.submissions)
      ? assignment.submissions
      : [];

  return {
    ...DEMO_ASSIGNMENT,
    ...assignment,
    posts: posts.map(normalizePost).filter((post) => post.body.trim()),
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
      import.meta.env.VITE_RATING_COMPLETION_CODE ||
      DEFAULT_COMPLETION_CODE,
    contactEmail:
      params.get("contact_email") ||
      import.meta.env.VITE_RESEARCH_CONTACT_EMAIL ||
      DEFAULT_CONTACT_EMAIL,
  };
};

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

const loadSupabaseAssignment = async ({ config, participant, count }) => {
  if (!participant.prolificPid) {
    throw new Error("Missing PROLIFIC_PID. Open this study from Prolific or add PROLIFIC_PID=test to the URL for testing.");
  }

  const data = await supabaseRpc(config, "claim_rating_assignment", {
    p_prolific_pid: participant.prolificPid,
    p_study_id: participant.studyId || null,
    p_session_id: participant.sessionId || null,
    p_posts_per_worker: count,
    p_completion_code: config.completionCode,
    p_contact_email: config.contactEmail,
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
    "record_rating_comprehension_failure",
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
    await supabaseRpc(assignment.backend.config, "submit_rating_payload", {
      p_assignment_id: assignment.assignmentId,
      p_payload: payload,
    });
    return { mode: "supabase" };
  }

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

  const key = `post-rating-study-${payload.assignment.assignmentId}-${Date.now()}`;
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

const ProgressBar = ({ current, total }) => (
  <div className="mb-5">
    <div className="mb-2 flex justify-between text-xs font-medium text-slate-500">
      <span>
        Post {Math.min(current + 1, total)} of {total}
      </span>
      <span>{Math.round(((current + 1) / total) * 100)}%</span>
    </div>
    <div className="h-2 overflow-hidden rounded-full bg-slate-200">
      <div
        className="h-full rounded-full bg-slate-900 transition-all"
        style={{ width: `${((current + 1) / total) * 100}%` }}
      />
    </div>
  </div>
);

const LikertItem = ({ item, value, onChange }) => (
  <div className="rounded-lg border border-slate-200 bg-slate-50 p-4">
    <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-slate-500">
      {item.label}
    </div>
    <p className="mb-3 text-sm font-semibold leading-6 text-slate-900">
      {item.prompt}
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
          aria-label={`${item.label}: ${score}`}
        >
          {score}
        </button>
      ))}
    </div>
    <div className="mt-2 grid grid-cols-3 gap-2 text-[11px] leading-4 text-slate-500">
      <span>1 - {item.anchors[1]}</span>
      <span className="text-center">4 - {item.anchors[4]}</span>
      <span className="text-right">7 - {item.anchors[7]}</span>
    </div>
  </div>
);

const isPostComplete = (postRating) =>
  RATING_ITEMS.every((item) => Boolean(postRating?.[item.key]));

const isSelfRatingComplete = (postRating) =>
  SELF_RATING_ITEMS.every((item) => Boolean(postRating?.[item.key]));

const isOthersRatingComplete = (postRating) =>
  OTHERS_RATING_ITEMS.every((item) => Boolean(postRating?.[item.key]));

const makeEmptyRatings = (posts) =>
  Object.fromEntries(posts.map((post) => [post.id, {}]));

const buildPayload = ({
  assignment,
  participant,
  posts,
  ratings,
  postFirstSeenAt,
  postTaskResponses,
  timings,
  status,
}) => ({
  schemaVersion: "post-controversiality-rating-v1",
  status,
  submittedAt: new Date().toISOString(),
  assignment: {
    assignmentId: assignment.assignmentId,
    completionCode: assignment.completionCode,
    postCount: posts.length,
    postIds: posts.map((post) => post.id),
  },
  participant,
  attentionCheck: null,
  postTaskResponses,
  ratings: posts.map((post, order) => ({
    postId: post.id,
    postTitle: post.title,
    sourceBin: post.sourceBin,
    order: order + 1,
    firstSeenAt: postFirstSeenAt[post.id] || null,
    responses: Object.fromEntries(
      RATING_ITEMS.map((item) => [
        item.key,
        ratings[post.id]?.[item.key] ? Number(ratings[post.id][item.key]) : null,
      ])
    ),
  })),
  timings: {
    ...timings,
    finalizedAt: new Date().toISOString(),
  },
  client: {
    userAgent: window.navigator.userAgent,
    language: window.navigator.language,
  },
});

const ConsentText = () => (
  <div className="max-h-[620px] overflow-y-auto whitespace-pre-wrap rounded-lg border border-slate-200 bg-slate-50 p-5 text-sm leading-6 text-slate-700">
    {INFORMED_CONSENT_TEXT}
  </div>
);

const ControversialityRatingTask = () => {
  useGlobalClipboardBlock();

  const [assignment, setAssignment] = useState(() =>
    applyQueryOverrides(normalizeAssignment(DEMO_ASSIGNMENT))
  );
  const [loadState, setLoadState] = useState("ready");
  const [loadError, setLoadError] = useState("");
  const [screen, setScreen] = useState("landing");
  const [agreed, setAgreed] = useState(false);
  const [comprehension, setComprehension] = useState("");
  const [comprehensionAttempts, setComprehensionAttempts] = useState(0);
  const [comprehensionError, setComprehensionError] = useState("");
  const [currentPostIndex, setCurrentPostIndex] = useState(0);
  const [ratingStage, setRatingStage] = useState("self");
  const [ratings, setRatings] = useState(() => makeEmptyRatings(DEMO_ASSIGNMENT.posts));
  const [postFirstSeenAt, setPostFirstSeenAt] = useState({});
  const [disagreementDifficulty, setDisagreementDifficulty] = useState("");
  const [studyPurpose, setStudyPurpose] = useState("");
  const [submissionState, setSubmissionState] = useState("idle");
  const [submissionError, setSubmissionError] = useState("");
  const [saveMode, setSaveMode] = useState("");
  const [timings, setTimings] = useState({
    loadedAt: new Date().toISOString(),
    screens: {},
  });

  const participant = useMemo(() => getProlificMeta(), []);

  const posts = useMemo(() => {
    const params = getQueryParams();
    const requestedCount = Number.parseInt(params.get("n_posts"), 10);
    const count = Number.isFinite(requestedCount) ? requestedCount : POSTS_PER_WORKER;
    const seed = [
      assignment.assignmentId,
      participant.prolificPid,
      participant.sessionId,
      participant.studyId,
    ].join("|");

    return seededShuffle(assignment.posts, seed).slice(0, count);
  }, [assignment, participant.prolificPid, participant.sessionId, participant.studyId]);

  const currentPost = posts[currentPostIndex] || posts[0];
  const completedCount = posts.filter((post) => isPostComplete(ratings[post.id])).length;
  const allPostsComplete = posts.length > 0 && completedCount === posts.length;
  const currentPostRatings = ratings[currentPost?.id] || {};
  const currentSelfComplete = isSelfRatingComplete(currentPostRatings);
  const currentOthersComplete = isOthersRatingComplete(currentPostRatings);
  const currentRatingItems =
    ratingStage === "self" ? SELF_RATING_ITEMS : OTHERS_RATING_ITEMS;

  useEffect(() => {
    const params = getQueryParams();
    const assignmentUrl = params.get("assignment_url");
    const postsUrl = params.get("posts_url");
    const apiBase = params.get("api_base");
    const assignmentId = params.get("assignment_id") || params.get("assignment");
    const requestedCount = Number.parseInt(params.get("n_posts"), 10);
    const count = Number.isFinite(requestedCount) ? requestedCount : POSTS_PER_WORKER;
    const supabaseConfig = getSupabaseConfig();

    if (!assignmentUrl && !postsUrl && !apiBase && !supabaseConfig) {
      if (participant.prolificPid) {
        setLoadState("error");
        setLoadError(
          "No backend is configured. Set Supabase environment variables or provide assignment_url and submit_url before launching on Prolific."
        );
      }
      return;
    }

    const loadAssignment = async () => {
      setLoadState("loading");
      setLoadError("");

      try {
        let remoteAssignment;

        if (supabaseConfig && !assignmentUrl && !postsUrl && !apiBase) {
          remoteAssignment = await loadSupabaseAssignment({
            config: supabaseConfig,
            participant,
            count,
          });
        } else {
          const url =
            assignmentUrl ||
            postsUrl ||
            `${apiBase.replace(/\/$/, "")}/assignment?assignment_id=${encodeURIComponent(
              assignmentId || ""
            )}&prolific_pid=${encodeURIComponent(participant.prolificPid)}`;
          const response = await fetch(url);

          if (!response.ok) {
            throw new Error(`Assignment request failed with HTTP ${response.status}`);
          }

          const data = await response.json();
          remoteAssignment = Array.isArray(data) ? { posts: data } : data;
        }

        const normalizedAssignment = applyQueryOverrides(
          normalizeAssignment(remoteAssignment)
        );
        const failureCount =
          Number(normalizedAssignment.comprehensionFailures) || 0;

        setAssignment(normalizedAssignment);
        setComprehensionAttempts(failureCount);
        setScreen(
          normalizedAssignment.status === "screened_out" || failureCount >= 2
            ? "comprehension_failed"
            : "landing"
        );
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
    setRatings((currentRatings) => ({
      ...makeEmptyRatings(posts),
      ...currentRatings,
    }));
  }, [posts]);

  useEffect(() => {
    if (!currentPost) return;
    setPostFirstSeenAt((current) => ({
      ...current,
      [currentPost.id]: current[currentPost.id] || new Date().toISOString(),
    }));
  }, [currentPost]);

  useEffect(() => {
    setTimings((current) => ({
      ...current,
      screens: {
        ...current.screens,
        [screen]: current.screens[screen] || new Date().toISOString(),
      },
    }));
  }, [screen]);

  const setRating = (postId, itemKey, value) => {
    setRatings((current) => ({
      ...current,
      [postId]: {
        ...current[postId],
        [itemKey]: value,
      },
    }));
  };

  const handleComprehensionChange = async (value) => {
    if (!value) {
      setComprehension("");
      return;
    }

    if (value === "own-and-others") {
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

  const goBackInTask = () => {
    if (ratingStage === "others") {
      setRatingStage("self");
      return;
    }

    if (currentPostIndex > 0) {
      setCurrentPostIndex((index) => Math.max(index - 1, 0));
      setRatingStage("others");
    }
  };

  const continueFromTaskStage = () => {
    if (ratingStage === "self") {
      setRatingStage("others");
      return;
    }

    if (currentPostIndex < posts.length - 1) {
      setCurrentPostIndex((index) => Math.min(index + 1, posts.length - 1));
      setRatingStage("self");
      return;
    }

    setScreen("review");
  };

  const submit = async () => {
    setSubmissionState("submitting");
    setSubmissionError("");

    const payload = buildPayload({
      assignment,
      participant,
      posts,
      ratings,
      postFirstSeenAt,
      postTaskResponses: {
        disagreementDifficulty: disagreementDifficulty
          ? Number(disagreementDifficulty)
          : null,
        studyPurpose: studyPurpose.trim(),
      },
      timings,
      status: "completed",
    });

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
              In this study, you will read {posts.length || POSTS_PER_WORKER}{" "}
              anonymous, public online posts about social dilemmas. For each
              post, read carefully, form your impression, and answer short
              questions. The questions are about how you would respond or how
              other readers would respond.
            </p>
            <div className="mt-6 grid gap-3 md:grid-cols-2">
              {[
                ["Task", `${posts.length || POSTS_PER_WORKER} posts`],
                ["Time", "Most participants take 10 minutes to complete the task."],
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
                You will read several posts from Reddit's r/AmITheAsshole
                forum. In these posts, people describe social dilemmas and ask
                readers to evaluate what happened.
              </p>
              <p>
                For each post, you will answer some questions about your own
                reaction and some questions about how other readers might
                respond. There are no right or wrong answers. Please answer
                honestly and choose the number that best matches your reaction.
              </p>
              <p>
                It's important that you don't use AI to answer these questions,
                since we want to understand how humans respond to these
                real-world dilemmas!
              </p>
              <p>
                Please read each post carefully and answer all questions before
                moving to the next post. You will complete{" "}
                {posts.length || POSTS_PER_WORKER} posts in total.
              </p>
            </div>
          </Panel>

          <Panel className="p-5 lg:sticky lg:top-6 lg:h-fit">
            <label className="mb-2 block text-sm font-semibold text-slate-700">
              Comprehension check
            </label>
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
              <option value="long-explanation">
                I will read only one post and write a long explanation about my
                feelings.
              </option>
              <option value="summarize">
                I will summarize each post without giving my own reaction, to
                test comprehension.
              </option>
              <option value="own-and-others">
                I will read each post and give my own reactions and judge how
                others would respond.
              </option>
              <option value="emotional-ratings">
                I will read 5 posts and provide emotional ratings based on
                people's feelings.
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
                disabled={comprehension !== "own-and-others"}
                onClick={() => {
                  setRatingStage("self");
                  setScreen("task");
                }}
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

    task: (
      <Page width="max-w-[1600px]">
        <StudyHeader assignment={assignment} />
        <ProgressBar current={currentPostIndex} total={posts.length} />
        <div className="grid gap-5 xl:grid-cols-[260px_minmax(0,1fr)_500px]">
          <Panel className="p-4 xl:sticky xl:top-6 xl:h-fit">
            <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-slate-500">
              Assigned Posts
            </h2>
            <div className="space-y-2">
              {posts.map((post, index) => {
                const complete = isPostComplete(ratings[post.id]);
                const active = index === currentPostIndex;
                const reachable = complete || index <= currentPostIndex;
                return (
                  <button
                    key={post.id}
                    type="button"
                    disabled={!reachable}
                    onClick={() => {
                      if (!reachable) return;
                      setCurrentPostIndex(index);
                      setRatingStage("self");
                    }}
                    className={`w-full rounded-lg border p-3 text-left text-sm transition ${
                      active
                        ? "border-slate-900 bg-slate-900 text-white"
                        : complete
                          ? "border-emerald-200 bg-emerald-50 text-slate-800"
                          : reachable
                            ? "border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
                            : "cursor-not-allowed border-slate-200 bg-slate-50 text-slate-400"
                    }`}
                  >
                    <span className="block font-semibold">Post {index + 1}</span>
                    <span className={active ? "text-slate-200" : "text-slate-500"}>
                      {complete ? "Complete" : "Incomplete"}
                    </span>
                  </button>
                );
              })}
            </div>
          </Panel>

          <Panel className="overflow-hidden">
            <div className="border-b border-slate-200 px-5 py-4">
              <p className="text-xs font-semibold uppercase tracking-wide text-slate-500">
                Post {currentPostIndex + 1} of {posts.length}
              </p>
              <h2 className="mt-2 text-xl font-semibold leading-7 text-slate-950">
                {currentPost?.title}
              </h2>
            </div>
            <div className="max-h-[70vh] overflow-y-auto p-5">
              <div className="whitespace-pre-line text-sm leading-7 text-slate-700">
                {currentPost?.body}
              </div>
            </div>
          </Panel>

          <Panel className="p-5 xl:sticky xl:top-6 xl:h-fit">
            <h2 className="mb-4 text-xl font-semibold text-slate-950">
              Your Ratings
            </h2>
            <div className="mb-4 rounded-lg border border-slate-200 bg-slate-50 p-4 text-sm leading-6 text-slate-700">
              {ratingStage === "self" ? (
                <p>
                  For these first few questions, please respond based on your
                  OWN reactions to the dilemma.
                </p>
              ) : (
                <p>
                  Now, we will ask you to think about how OTHERS would respond
                  to the dilemma.
                </p>
              )}
            </div>
            <div className="space-y-4">
              {currentRatingItems.map((item) => (
                <LikertItem
                  key={item.key}
                  item={item}
                  value={currentPostRatings[item.key] || ""}
                  onChange={(value) => setRating(currentPost.id, item.key, value)}
                />
              ))}
            </div>

            <div className="mt-5 flex gap-3">
              <Button
                variant="secondary"
                disabled={currentPostIndex === 0 && ratingStage === "self"}
                onClick={goBackInTask}
              >
                Back
              </Button>
              <Button
                className="flex-1"
                disabled={
                  ratingStage === "self"
                    ? !currentSelfComplete
                    : !currentOthersComplete
                }
                onClick={continueFromTaskStage}
              >
                {ratingStage === "self"
                  ? "Continue"
                  : currentPostIndex < posts.length - 1
                    ? "Next Post"
                    : "Review & Submit"}
              </Button>
            </div>
          </Panel>
        </div>
      </Page>
    ),

    review: (
      <Page width="max-w-5xl">
        <StudyHeader assignment={assignment} />
        <Panel className="p-6">
          <h2 className="mb-2 text-2xl font-semibold text-slate-950">
            Submit Study
          </h2>
          <p className="mb-6 text-sm leading-6 text-slate-600">
            You have completed {completedCount} of {posts.length} posts. Please
            answer the short post-task questions before submitting.
          </p>

          <div className="mb-6 overflow-hidden rounded-lg border border-slate-200">
            <table className="w-full text-left text-sm">
              <thead className="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
                <tr>
                  <th className="px-4 py-3">Post</th>
                  <th className="px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-slate-200">
                {posts.map((post, index) => (
                  <tr key={post.id}>
                    <td className="px-4 py-3 font-medium text-slate-800">
                      Post {index + 1}
                    </td>
                    <td className="px-4 py-3 text-slate-600">
                      {isPostComplete(ratings[post.id]) ? "Complete" : "Incomplete"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <div className="grid gap-4 md:grid-cols-[minmax(0,1fr)_minmax(0,1fr)]">
            <LikertItem
              item={POST_TASK_DIFFICULTY_ITEM}
              value={disagreementDifficulty}
              onChange={setDisagreementDifficulty}
            />

            <div className="rounded-lg border border-slate-200 bg-slate-50 p-4">
              <label className="mb-2 block text-xs font-semibold uppercase tracking-wide text-slate-500">
                Post-task question
              </label>
              <p className="mb-3 text-sm font-semibold leading-6 text-slate-900">
                What do you think this study was about?
              </p>
              <textarea
                value={studyPurpose}
                onChange={(event) => setStudyPurpose(event.target.value)}
                rows={6}
                className="w-full resize-none rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
                placeholder="Type your response here..."
              />
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
              disabled={
                !allPostsComplete ||
                !disagreementDifficulty ||
                !studyPurpose.trim() ||
                submissionState === "submitting"
              }
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
                Thank you for participating. This study measures how readers
                perceive disagreement and ambiguity in online posts.
              </p>
              <p>
                The broader goal is to create human ratings of post-level
                controversiality for later research.
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
            Your response has been submitted. Please return to the platform and
            enter the completion code below.
          </p>
          <div className="mx-auto mt-6 max-w-sm rounded-lg border border-slate-200 bg-slate-50 p-4">
            <div className="text-xs font-semibold uppercase tracking-wide text-slate-500">
              Completion Code
            </div>
            <div className="mt-2 font-mono text-lg font-semibold text-slate-950">
              {assignment.completionCode || "ONLINE-COMPLETE"}
            </div>
          </div>
        </Panel>
      </Page>
    ),
  };

  return screens[screen] || screens.landing;
};

export default function App() {
  return (
    <TailwindLoader>
      <ControversialityRatingTask />
    </TailwindLoader>
  );
}
