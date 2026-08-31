export const SCHEMA_VERSION = "advice-transfer-v4-gist";
export const MIN_ADVICE_WORDS = 77;
export const MIN_GIST_WORDS = 25;
export const JUDGMENT_LABELS = ["YTA", "NTA", "ESH", "NAH", "INFO"];
export const CORRECT_COMPREHENSION = "read-label-summarize";
export const DEMOGRAPHIC_CODES = Object.freeze({
  genderIdentity: ["male", "female", "other", "prefer-not-to-say"],
  englishProficiency: ["yes", "no-fluent", "no-mostly-fluent", "no-minimal-fluency"],
  educationLevel: [
    "no-school",
    "eighth-grade-or-less",
    "more-than-eighth-less-than-high-school",
    "high-school-degree-or-equivalent",
    "some-college",
    "four-year-college-degree",
    "graduate-or-professional-training",
  ],
  employmentStatus: ["employed", "self-employed", "student", "unemployed", "other"],
});

export const emptyDemographics = () => ({
  genderIdentity: "",
  ageYears: null,
  englishProficiency: "",
  educationLevel: "",
  employmentStatus: "",
});

export const normalizeDemographics = (value) => {
  const result = emptyDemographics();
  for (const key of ["genderIdentity", "englishProficiency", "educationLevel", "employmentStatus"]) {
    if (DEMOGRAPHIC_CODES[key].includes(value?.[key])) result[key] = value[key];
  }
  const age = Number(value?.ageYears);
  if (Number.isInteger(age) && age >= 18 && age <= 120) result.ageYears = age;
  return result;
};

export const demographicsComplete = (value) => {
  const normalized = normalizeDemographics(value);
  return normalized.genderIdentity !== "" &&
    normalized.ageYears !== null &&
    normalized.englishProficiency !== "" &&
    normalized.educationLevel !== "" &&
    normalized.employmentStatus !== "";
};

export const countEnglishWords = (value) =>
  String(value || "").match(/[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*/g)?.length || 0;

export const scaleValue = (value) =>
  Number.isInteger(value) && value >= 1 && value <= 7 ? value : null;

export const judgmentsFor = (assignment, labels) =>
  assignment.commentOrder.map((commentIndex, index) => ({
    displayPosition: index + 1,
    commentIndex,
    commentSha256: assignment.commentHashes[index],
    label: labels[index] || "",
  }));

export const labelsFromJudgments = (assignment, judgments) =>
  assignment.commentOrder.map((commentIndex, index) => {
    const record = Array.isArray(judgments)
      ? judgments.find((entry) => entry?.displayPosition === index + 1)
      : null;
    return record?.commentIndex === commentIndex &&
      record?.commentSha256 === assignment.commentHashes[index] &&
      JUDGMENT_LABELS.includes(record?.label)
      ? record.label
      : "";
  });

export const phase1Complete = (labels, gistText, gistDifficulty) =>
  Array.isArray(labels) && labels.length === 5 &&
  labels.every((label) => JUDGMENT_LABELS.includes(label)) &&
  countEnglishWords(gistText) >= MIN_GIST_WORDS &&
  scaleValue(gistDifficulty) !== null;

export const phase2Complete = (advice, effort, confidence) =>
  countEnglishWords(advice) >= MIN_ADVICE_WORDS &&
  scaleValue(effort) !== null && scaleValue(confidence) !== null;

export const emptyActiveTimings = () => ({
  phase1ActiveTimeMs: 0,
  gistActiveTimeMs: 0,
  adviceResponseTimeMs: 0,
});

export const normalizeActiveTimings = (value) => {
  const result = emptyActiveTimings();
  for (const key of Object.keys(result)) {
    if (Number.isSafeInteger(value?.[key]) && value[key] >= 0) result[key] = value[key];
  }
  result.gistActiveTimeMs = Math.min(result.gistActiveTimeMs, result.phase1ActiveTimeMs);
  return result;
};

// Called only for a visible, editable task region. Gist focus is a subset of
// Phase 1; B excludes post-task ratings, other pages, and hidden-tab intervals.
export const addActiveTime = (timings, region, milliseconds) => {
  const result = normalizeActiveTimings(timings);
  const duration = Math.max(0, Math.round(Number(milliseconds) || 0));
  if (region === "phase1" || region === "gist") result.phase1ActiveTimeMs += duration;
  if (region === "gist") result.gistActiveTimeMs += duration;
  if (region === "advice") result.adviceResponseTimeMs += duration;
  return result;
};

export const activeRegion = ({ screen, phase1Locked, phase2Locked, pending, gistFocused, visible }) => {
  if (!visible || pending) return null;
  if (screen === "exposure" && !phase1Locked) return gistFocused ? "gist" : "phase1";
  if (screen === "advice" && !phase2Locked) return "advice";
  return null;
};

export const DRAFTABLE_SCREENS = new Set([
  "overview", "consent", "instructions", "phase2-instructions", "exposure",
  "advice", "ratings", "funnel-purpose", "funnel-notice", "funnel-ai", "demographics",
]);

// Locks are trusted ONLY from the server assignment, never from device drafts.
// A later stale device timestamp cannot erase an earlier committed snapshot.
export const restoreV4Draft = (assignment, drafts) => {
  const candidates = drafts.filter((draft) =>
    draft?.schemaVersion === SCHEMA_VERSION &&
    draft.assignmentId === assignment.assignmentId &&
    DRAFTABLE_SCREENS.has(draft.screen),
  ).sort((a, b) => (Date.parse(b.savedAt) || 0) - (Date.parse(a.savedAt) || 0));
  const draft = candidates[0] || {};
  const phase1 = assignment.phase1Snapshot || null;
  const phase2 = assignment.phase2Snapshot || null;
  const phase1LockedAt = phase1 ? assignment.phase1LockedAt : null;
  const phase2LockedAt = phase2 ? assignment.phase2LockedAt : null;
  let screen = draft.screen || (phase2 ? "funnel-purpose" : phase1 ? "advice" : "overview");
  const agreed = Boolean(draft.agreed || phase1);
  const comprehension = draft.comprehension === CORRECT_COMPREHENSION || phase1
    ? CORRECT_COMPREHENSION : "";
  const pendingStage = draft.pendingStage?.payload?.schemaVersion === SCHEMA_VERSION &&
    ["phase1", "phase2"].includes(draft.pendingStage?.stage) &&
    !(draft.pendingStage.stage === "phase1" ? phase1 : phase2)
    ? draft.pendingStage : null;
  const pendingSubmission = draft.pendingSubmission?.schemaVersion === SCHEMA_VERSION &&
    draft.pendingSubmission?.assignmentId === assignment.assignmentId && phase2 &&
    demographicsComplete(draft.pendingSubmission?.demographics)
    ? draft.pendingSubmission : null;
  if (!["overview"].includes(screen) && !agreed) screen = "consent";
  else if (!["overview", "consent", "instructions"].includes(screen) && !comprehension) screen = "instructions";
  else if (["advice", "ratings", "funnel-purpose", "funnel-notice", "funnel-ai", "demographics"].includes(screen) && !phase1) screen = "exposure";
  else if ((screen.startsWith("funnel-") || screen === "demographics") && !phase2) screen = "ratings";
  if (pendingStage) screen = pendingStage.stage === "phase1" ? "exposure" : "ratings";
  // A lost stage ACK must advance after reload, unless the user explicitly
  // navigated back after a previously confirmed save.
  if (draft.pendingStage?.stage === "phase1" && phase1) screen = phase2 ? "funnel-purpose" : "advice";
  if (draft.pendingStage?.stage === "phase2" && phase2) screen = "funnel-purpose";
  if (pendingSubmission) screen = "demographics";
  const timings = {
    ...(draft.timings || {}),
    ...(phase1?.timings || {}),
    ...(phase2?.timings || {}),
  };
  if (phase1) {
    timings.phase1ActiveTimeMs = phase1.timings.phase1ActiveTimeMs;
    timings.gistActiveTimeMs = phase1.timings.gistActiveTimeMs;
  }
  if (phase2) timings.adviceResponseTimeMs = phase2.timings.adviceResponseTimeMs;
  return {
    ...draft,
    screen, agreed, comprehension, pendingStage, pendingSubmission,
    commentJudgments: phase1?.commentJudgments || draft.commentJudgments || [],
    gistText: String(phase1?.gistText ?? draft.gistText ?? ""),
    gistDifficulty: scaleValue(phase1?.gistDifficulty ?? draft.gistDifficulty),
    advice: String(phase2?.adviceText ?? draft.advice ?? ""),
    effort: scaleValue(phase2?.effort ?? draft.effort),
    confidence: scaleValue(phase2?.confidence ?? draft.confidence),
    demographics: normalizeDemographics(draft.demographics),
    phase1Snapshot: phase1, phase1LockedAt,
    phase2Snapshot: phase2, phase2LockedAt,
    timings: normalizeActiveTimings(timings),
    timestamps: { ...(draft.timestamps || {}), ...timings, phase1LockedAt, phase2LockedAt },
  };
};
