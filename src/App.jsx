import React, { useEffect, useMemo, useState } from "react";

const POSTS_PER_WORKER = 5;

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
    key: "conviction",
    label: "Question 2",
    prompt: "How strongly do you feel about your response above?",
    anchors: {
      1: "Not strongly at all",
      4: "Moderately strongly",
      7: "Extremely strongly",
    },
  },
  {
    key: "ambivalence",
    label: "Question 3",
    prompt: "How torn or conflicted do you feel about your response to the OP?",
    anchors: {
      1: "Not torn at all; the answer is clear to me",
      4: "Somewhat torn",
      7: "Extremely torn; I genuinely cannot decide",
    },
  },
  {
    key: "perceived_disagreement",
    label: "Question 4",
    prompt:
      "If 100 thoughtful people read this post, what would their responses look like?",
    anchors: {
      1: "Nearly all would reach the same response",
      4: "Mixed; many different views",
      7: "People would split into clearly opposed camps",
    },
  },
];

const DEMO_ASSIGNMENT = {
  assignmentId: "demo-rating-assignment",
  completionCode: "ONLINE-DEMO-COMPLETE",
  submitEndpoint: "",
  contactEmail: "researcher@northwestern.edu",
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

const makeEmptyRatings = (posts) =>
  Object.fromEntries(posts.map((post) => [post.id, {}]));

const buildPayload = ({
  assignment,
  participant,
  posts,
  ratings,
  postFirstSeenAt,
  attentionCheck,
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
  attentionCheck,
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

const ControversialityRatingTask = () => {
  const [assignment, setAssignment] = useState(() =>
    applyQueryOverrides(normalizeAssignment(DEMO_ASSIGNMENT))
  );
  const [loadState, setLoadState] = useState("ready");
  const [loadError, setLoadError] = useState("");
  const [screen, setScreen] = useState("landing");
  const [agreed, setAgreed] = useState(false);
  const [comprehension, setComprehension] = useState("");
  const [currentPostIndex, setCurrentPostIndex] = useState(0);
  const [ratings, setRatings] = useState(() => makeEmptyRatings(DEMO_ASSIGNMENT.posts));
  const [postFirstSeenAt, setPostFirstSeenAt] = useState({});
  const [attentionCheck, setAttentionCheck] = useState("");
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

  useEffect(() => {
    const params = getQueryParams();
    const assignmentUrl = params.get("assignment_url");
    const postsUrl = params.get("posts_url");
    const apiBase = params.get("api_base");
    const assignmentId = params.get("assignment_id") || params.get("assignment");

    if (!assignmentUrl && !postsUrl && !apiBase) return;

    const loadAssignment = async () => {
      setLoadState("loading");
      setLoadError("");

      try {
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
        const remoteAssignment = Array.isArray(data) ? { posts: data } : data;
        setAssignment(applyQueryOverrides(normalizeAssignment(remoteAssignment)));
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

  const submit = async () => {
    setSubmissionState("submitting");
    setSubmissionError("");

    const payload = buildPayload({
      assignment,
      participant,
      posts,
      ratings,
      postFirstSeenAt,
      attentionCheck,
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
              anonymized online posts. For each post, you will answer four short
              questions about your response and how you think other readers might
              respond.
            </p>
            <div className="mt-6 grid gap-3 md:grid-cols-3">
              {[
                ["Task", `${posts.length || POSTS_PER_WORKER} posts`],
                ["Time", "About 8 to 12 minutes"],
                ["Data", "Research use only"],
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
            <div className="max-h-[560px] overflow-y-auto rounded-lg border border-slate-200 bg-slate-50 p-5 text-sm leading-6 text-slate-700">
              <p>
                <strong>Study title:</strong> Online Research Study
              </p>
              <p className="mt-4">
                <strong>Purpose:</strong> This research examines how people read
                and respond to written online posts.
              </p>
              <p className="mt-4">
                <strong>Procedures:</strong> You will read several anonymized
                posts and answer four short questions after each post.
              </p>
              <p className="mt-4">
                <strong>Risks:</strong> Some posts may involve sensitive social
                situations, including family issues, finances, or relationship
                disagreements. You may stop at any time.
              </p>
              <p className="mt-4">
                <strong>Confidentiality:</strong> Your study response will be
                stored without your name. Crowdsourcing platform IDs may be used
                only for payment, duplicate prevention, and data quality checks.
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
                  "Read each post carefully",
                  "Each post describes a situation from the perspective of the person who wrote it.",
                ],
                [
                  "Answer in order",
                  "For each post, answer the four questions in the order shown.",
                ],
                [
                  "Use the full scale",
                  "There are no right or wrong answers. Choose the number that best matches your reaction.",
                ],
                [
                  "Finish all posts",
                  `You will rate ${posts.length || POSTS_PER_WORKER} posts before submitting the study.`,
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
            <label className="mb-2 block text-sm font-semibold text-slate-700">
              Comprehension check
            </label>
            <select
              value={comprehension}
              onChange={(event) => setComprehension(event.target.value)}
              className="w-full rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
            >
              <option value="">Select the correct statement</option>
              <option value="single">I will rate only one post.</option>
              <option value="all-posts">
                I will read all assigned posts and answer four questions for each.
              </option>
            </select>

            <div className="mt-5 flex gap-3">
              <Button variant="secondary" onClick={() => setScreen("consent")}>
                Back
              </Button>
              <Button
                className="flex-1"
                disabled={comprehension !== "all-posts"}
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
                return (
                  <button
                    key={post.id}
                    type="button"
                    onClick={() => setCurrentPostIndex(index)}
                    className={`w-full rounded-lg border p-3 text-left text-sm transition ${
                      active
                        ? "border-slate-900 bg-slate-900 text-white"
                        : complete
                          ? "border-emerald-200 bg-emerald-50 text-slate-800"
                          : "border-slate-200 bg-white text-slate-700 hover:bg-slate-50"
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
            <div className="space-y-4">
              {RATING_ITEMS.map((item) => (
                <LikertItem
                  key={item.key}
                  item={item}
                  value={ratings[currentPost?.id]?.[item.key] || ""}
                  onChange={(value) => setRating(currentPost.id, item.key, value)}
                />
              ))}
            </div>

            <div className="mt-5 flex gap-3">
              <Button
                variant="secondary"
                disabled={currentPostIndex === 0}
                onClick={() => setCurrentPostIndex((index) => Math.max(index - 1, 0))}
              >
                Back
              </Button>
              {currentPostIndex < posts.length - 1 ? (
                <Button
                  className="flex-1"
                  disabled={!isPostComplete(ratings[currentPost?.id])}
                  onClick={() =>
                    setCurrentPostIndex((index) => Math.min(index + 1, posts.length - 1))
                  }
                >
                  Next Post
                </Button>
              ) : (
                <Button
                  className="flex-1"
                  disabled={!allPostsComplete}
                  onClick={() => setScreen("review")}
                >
                  Review & Submit
                </Button>
              )}
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
            answer the attention check before submitting.
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

          <label className="mb-2 block text-sm font-semibold text-slate-700">
            Attention check: please select "blue".
          </label>
          <select
            value={attentionCheck}
            onChange={(event) => setAttentionCheck(event.target.value)}
            className="w-full max-w-sm rounded-lg border border-slate-300 bg-white px-3 py-3 text-sm text-slate-800 focus:border-slate-900 focus:outline-none focus:ring-2 focus:ring-slate-100"
          >
            <option value="">Select one</option>
            <option value="red">Red</option>
            <option value="blue">Blue</option>
            <option value="green">Green</option>
          </select>

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
                attentionCheck !== "blue" ||
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
