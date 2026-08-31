import assert from "node:assert/strict";
import test from "node:test";
import {
  SCHEMA_VERSION,
  MIN_ADVICE_WORDS,
  MIN_GIST_WORDS,
  CORRECT_COMPREHENSION,
  JUDGMENT_LABELS,
  DEMOGRAPHIC_CODES,
  countEnglishWords,
  demographicsComplete,
  emptyDemographics,
  normalizeDemographics,
  scaleValue,
  judgmentsFor,
  labelsFromJudgments,
  phase1Complete,
  phase2Complete,
  emptyActiveTimings,
  normalizeActiveTimings,
  addActiveTime,
  activeRegion,
  restoreV4Draft,
} from "../src/advice-transfer-protocol.mjs";

const advice = ["NTA", ...Array(76).fill("word")].join(" ");
const gist24 = Array(24).fill("word").join(" ");
const gist25 = Array(25).fill("word").join(" ");
const validDemographics = {
  genderIdentity: "prefer-not-to-say",
  ageYears: 35,
  englishProficiency: "no-fluent",
  educationLevel: "graduate-or-professional-training",
  employmentStatus: "self-employed",
};
const assignment = {
  assignmentId: "qa-v4-unit-assignment",
  protocolVersion: SCHEMA_VERSION,
  commentOrder: [3, 0, 4, 2, 1],
  commentHashes: ["d", "a", "e", "c", "b"].map((letter) => letter.repeat(64)),
};
const makeDraft = (overrides = {}) => ({
  schemaVersion: SCHEMA_VERSION,
  assignmentId: assignment.assignmentId,
  screen: "exposure",
  agreed: true,
  comprehension: CORRECT_COMPREHENSION,
  savedAt: "2026-08-28T14:00:00Z",
  commentJudgments: judgmentsFor(assignment, JUDGMENT_LABELS),
  gistText: "The commenters disagree about responsibility.",
  gistDifficulty: 4,
  advice,
  effort: 3,
  confidence: 5,
  demographics: validDemographics,
  timings: { phase1ActiveTimeMs: 9000, gistActiveTimeMs: 3000, adviceResponseTimeMs: 5000 },
  ...overrides,
});
const phase1Snapshot = {
  schemaVersion: SCHEMA_VERSION,
  stage: "phase1",
  commentJudgments: judgmentsFor(assignment, JUDGMENT_LABELS),
  gistText: "The server-locked summary.",
  gistDifficulty: 2,
  timings: { phase1ActiveTimeMs: 12000, gistActiveTimeMs: 4000 },
};
const phase2Snapshot = {
  schemaVersion: SCHEMA_VERSION,
  stage: "phase2",
  adviceText: advice,
  effort: 6,
  confidence: 3,
  timings: { adviceResponseTimeMs: 16000 },
};
const phase1Locked = {
  ...assignment,
  phase1Snapshot,
  phase1LockedAt: "2026-08-28T14:01:00Z",
};
const fullyLocked = {
  ...phase1Locked,
  phase2Snapshot,
  phase2LockedAt: "2026-08-28T14:02:00Z",
};

test("v4 requires five valid classifications, at least 25 gist words, and a valid difficulty", () => {
  assert.equal(SCHEMA_VERSION, "advice-transfer-v4-gist");
  assert.equal(MIN_GIST_WORDS, 25);
  assert.equal(countEnglishWords(gist24), 24);
  assert.equal(countEnglishWords(gist25), 25);
  assert.equal(phase1Complete(JUDGMENT_LABELS, gist24, 4), false);
  assert.equal(phase1Complete(JUDGMENT_LABELS, gist25, 1), true);
  assert.equal(phase1Complete(JUDGMENT_LABELS, gist25, 7), true);
  for (const labels of [undefined, [], JUDGMENT_LABELS.slice(0, 4), [...JUDGMENT_LABELS, "NTA"], ["YTA", "NTA", "ESH", "NAH", ""]]) {
    assert.equal(phase1Complete(labels, gist25, 4), false);
  }
  for (const gist of ["", " ", "\t\n", null, undefined]) {
    assert.equal(phase1Complete(JUDGMENT_LABELS, gist, 4), false);
  }
  for (const invalid of [null, undefined, 0, 8, 3.5, "4", false, NaN, Infinity]) {
    assert.equal(scaleValue(invalid), null);
    assert.equal(phase1Complete(JUDGMENT_LABELS, gist25, invalid), false);
  }
});

test("B keeps the exact 77-word boundary and requires both post-task ratings", () => {
  assert.equal(MIN_ADVICE_WORDS, 77);
  assert.equal(countEnglishWords(advice), 77);
  assert.equal(countEnglishWords("don't re-open a post's thread"), 5);
  assert.equal(phase2Complete(advice, 1, 7), true);
  assert.equal(phase2Complete(Array(76).fill("word").join(" "), 4, 4), false);
  for (const invalid of [null, undefined, 0, 8, 1.1, "3", false]) {
    assert.equal(phase2Complete(advice, invalid, 4), false);
    assert.equal(phase2Complete(advice, 4, invalid), false);
  }
});

test("the five core demographics accept only the recorded Qualtrics response codes", () => {
  assert.equal(demographicsComplete(validDemographics), true);
  assert.deepEqual(normalizeDemographics(validDemographics), validDemographics);
  assert.deepEqual(normalizeDemographics(null), emptyDemographics());
  for (const ageYears of [null, "", 17, 121, 34.5, "35 years"]) {
    assert.equal(demographicsComplete({ ...validDemographics, ageYears }), false);
  }
  for (const [key, codes] of Object.entries(DEMOGRAPHIC_CODES)) {
    assert.ok(codes.length >= 4);
    assert.equal(demographicsComplete({ ...validDemographics, [key]: "invalid" }), false);
  }
  assert.equal(normalizeDemographics({ ...validDemographics, ageYears: "35" }).ageYears, 35);
});

test("classification records retain display position, original index, and the presented hash", () => {
  const records = judgmentsFor(assignment, JUDGMENT_LABELS);
  assert.equal(records.length, 5);
  records.forEach((record, index) => {
    assert.deepEqual(record, {
      displayPosition: index + 1,
      commentIndex: assignment.commentOrder[index],
      commentSha256: assignment.commentHashes[index],
      label: JUDGMENT_LABELS[index],
    });
  });
  assert.deepEqual(labelsFromJudgments(assignment, records), JUDGMENT_LABELS);
  assert.deepEqual(labelsFromJudgments(assignment, [...records].reverse()), JUDGMENT_LABELS);
});

test("a classification for another comment or an invalid label cannot restore as complete", () => {
  for (const replacement of [{ commentIndex: 1 }, { commentSha256: "f".repeat(64) }, { label: "UNKNOWN" }, { displayPosition: 5 }]) {
    const records = judgmentsFor(assignment, JUDGMENT_LABELS);
    records[0] = { ...records[0], ...replacement };
    const restored = labelsFromJudgments(assignment, records);
    assert.equal(restored[0], "");
    assert.equal(phase1Complete(restored, gist25, 4), false);
  }
  const missing = judgmentsFor(assignment, JUDGMENT_LABELS).slice(0, 4);
  assert.equal(phase1Complete(labelsFromJudgments(assignment, missing), gist25, 4), false);
});

test("active timing is limited to visible, editable task regions", () => {
  const state = { screen: "exposure", phase1Locked: false, phase2Locked: false, pending: false, gistFocused: false, visible: true };
  assert.equal(activeRegion(state), "phase1");
  assert.equal(activeRegion({ ...state, gistFocused: true }), "gist");
  assert.equal(activeRegion({ ...state, screen: "advice", phase1Locked: true }), "advice");
  for (const change of [{ visible: false }, { pending: true }, { phase1Locked: true }]) {
    assert.equal(activeRegion({ ...state, ...change }), null);
  }
  assert.equal(activeRegion({ ...state, screen: "advice", phase2Locked: true }), null);
  for (const screen of ["consent", "instructions", "phase2-instructions", "ratings", "funnel-purpose", "funnel-notice", "funnel-ai", "demographics", "complete"]) {
    assert.equal(activeRegion({ ...state, screen }), null);
  }
});

test("gist is a subset of phase 1 and B time never includes the post-task survey", () => {
  const initial = emptyActiveTimings();
  let timing = addActiveTime(initial, "phase1", 1500);
  timing = addActiveTime(timing, "gist", 2500);
  timing = addActiveTime(timing, "advice", 7000);
  timing = addActiveTime(timing, null, 90000);
  assert.deepEqual(timing, { phase1ActiveTimeMs: 4000, gistActiveTimeMs: 2500, adviceResponseTimeMs: 7000 });
  assert.deepEqual(initial, emptyActiveTimings(), "timing updates are immutable");
  assert.deepEqual(addActiveTime(timing, "advice", -10), timing);
  assert.deepEqual(normalizeActiveTimings({ phase1ActiveTimeMs: 100, gistActiveTimeMs: 200, adviceResponseTimeMs: -1 }),
    { phase1ActiveTimeMs: 100, gistActiveTimeMs: 100, adviceResponseTimeMs: 0 });
  assert.deepEqual(normalizeActiveTimings({ phase1ActiveTimeMs: "10", gistActiveTimeMs: NaN, adviceResponseTimeMs: Infinity }), emptyActiveTimings());
});

test("restoration chooses the newest matching v4 draft, never legacy or another assignment", () => {
  const restored = restoreV4Draft(assignment, [
    makeDraft({ savedAt: "2026-08-28T14:00:10Z", gistText: "new v4" }),
    makeDraft({ schemaVersion: "advice-transfer-v3-admission", savedAt: "2099-01-01", gistText: "legacy" }),
    makeDraft({ assignmentId: "another-person", savedAt: "2099-01-01", gistText: "another person" }),
    makeDraft({ gistText: "old v4" }),
  ]);
  assert.equal(restored.gistText, "new v4");
  assert.equal(restored.schemaVersion, SCHEMA_VERSION);
  const blank = restoreV4Draft(assignment, [makeDraft({ schemaVersion: "advice-transfer-v3-admission" })]);
  assert.equal(blank.screen, "overview");
  assert.equal(blank.gistText, "");
  assert.equal(blank.advice, "");
  assert.equal(blank.phase1Snapshot, null);
});

test("server snapshots override newer stale local responses, timestamps, and forged locks", () => {
  const stale = makeDraft({
    savedAt: "2099-01-01T00:00:00Z", screen: "funnel-ai",
    gistText: "overwrite", gistDifficulty: 7, advice: "overwrite", effort: 1, confidence: 7,
    commentJudgments: judgmentsFor(assignment, Array(5).fill("INFO")),
    phase1LockedAt: "2099-01-01", phase2LockedAt: "2099-01-01",
    timings: { phase1ActiveTimeMs: 999999, gistActiveTimeMs: 99999, adviceResponseTimeMs: 999999 },
  });
  const restored = restoreV4Draft(fullyLocked, [stale]);
  assert.equal(restored.gistText, phase1Snapshot.gistText);
  assert.equal(restored.gistDifficulty, phase1Snapshot.gistDifficulty);
  assert.deepEqual(restored.commentJudgments, phase1Snapshot.commentJudgments);
  assert.equal(restored.advice, advice);
  assert.equal(restored.effort, phase2Snapshot.effort);
  assert.equal(restored.confidence, phase2Snapshot.confidence);
  assert.equal(restored.phase1LockedAt, fullyLocked.phase1LockedAt);
  assert.equal(restored.phase2LockedAt, fullyLocked.phase2LockedAt);
  assert.deepEqual(restored.timings, { phase1ActiveTimeMs: 12000, gistActiveTimeMs: 4000, adviceResponseTimeMs: 16000 });
  const forged = restoreV4Draft(assignment, [{ ...stale, phase1Snapshot, phase2Snapshot }]);
  assert.equal(forged.phase1Snapshot, null);
  assert.equal(forged.phase2Snapshot, null);
  assert.equal(forged.phase1LockedAt, null);
  assert.equal(forged.screen, "exposure");
});

test("optional timing context in one phase cannot override the other phase's validated duration", () => {
  const restored = restoreV4Draft({
    ...fullyLocked,
    phase1Snapshot: { ...phase1Snapshot, timings: { ...phase1Snapshot.timings, adviceResponseTimeMs: 999999 } },
    phase2Snapshot: { ...phase2Snapshot, timings: { ...phase2Snapshot.timings, phase1ActiveTimeMs: 999999, gistActiveTimeMs: 999999 } },
  }, [makeDraft({ screen: "funnel-ai" })]);
  assert.deepEqual(restored.timings, { phase1ActiveTimeMs: 12000, gistActiveTimeMs: 4000, adviceResponseTimeMs: 16000 });
});

test("draft restoration cannot skip consent, comprehension, or uncommitted phase boundaries", () => {
  assert.equal(restoreV4Draft(assignment, [makeDraft({ screen: "advice", agreed: false })]).screen, "consent");
  assert.equal(restoreV4Draft(assignment, [makeDraft({ screen: "advice", comprehension: "" })]).screen, "instructions");
  assert.equal(restoreV4Draft(assignment, [makeDraft({ screen: "funnel-ai" })]).screen, "exposure");
  assert.equal(restoreV4Draft(phase1Locked, [makeDraft({ screen: "funnel-ai" })]).screen, "ratings");
  assert.equal(restoreV4Draft(fullyLocked, []).screen, "funnel-purpose");
});

test("lost stage acknowledgements advance from committed server snapshots without resaving", () => {
  const phase1Pending = { stage: "phase1", payload: { schemaVersion: SCHEMA_VERSION, gistText: "original captured intent" } };
  const before = restoreV4Draft(assignment, [makeDraft({ pendingStage: phase1Pending })]);
  assert.deepEqual(before.pendingStage, phase1Pending);
  assert.equal(before.screen, "exposure");
  const after = restoreV4Draft(phase1Locked, [makeDraft({ pendingStage: phase1Pending })]);
  assert.equal(after.pendingStage, null);
  assert.equal(after.screen, "advice");
  assert.equal(after.gistText, phase1Snapshot.gistText);
  const phase2Pending = { stage: "phase2", payload: { schemaVersion: SCHEMA_VERSION, adviceText: advice } };
  assert.equal(restoreV4Draft(phase1Locked, [makeDraft({ pendingStage: phase2Pending })]).screen, "ratings");
  const after2 = restoreV4Draft(fullyLocked, [makeDraft({ pendingStage: phase2Pending })]);
  assert.equal(after2.pendingStage, null);
  assert.equal(after2.screen, "funnel-purpose");
});

test("explicit read-only Back navigation is preserved after acknowledged locks", () => {
  assert.equal(restoreV4Draft(phase1Locked, [makeDraft({ screen: "exposure" })]).screen, "exposure");
  assert.equal(restoreV4Draft(fullyLocked, [makeDraft({ screen: "advice" })]).screen, "advice");
  assert.equal(restoreV4Draft(fullyLocked, [makeDraft({ screen: "ratings" })]).screen, "ratings");
});

test("pending final submission recovers only for its matching v4 assignment after both locks and completed demographics", () => {
  const pendingSubmission = { schemaVersion: SCHEMA_VERSION, assignmentId: assignment.assignmentId, purposeGuess: "fixed final intent", demographics: validDemographics };
  const draft = makeDraft({ screen: "demographics", pendingSubmission });
  const restored = restoreV4Draft(fullyLocked, [draft]);
  assert.deepEqual(restored.pendingSubmission, pendingSubmission);
  assert.equal(restored.screen, "demographics");
  assert.equal(restoreV4Draft(phase1Locked, [draft]).pendingSubmission, null);
  assert.equal(restoreV4Draft(fullyLocked, [makeDraft({ pendingSubmission: { ...pendingSubmission, assignmentId: "another-person" } })]).pendingSubmission, null);
  assert.equal(restoreV4Draft(fullyLocked, [makeDraft({ pendingSubmission: { ...pendingSubmission, schemaVersion: "advice-transfer-v3-admission" } })]).pendingSubmission, null);
  assert.equal(restoreV4Draft(fullyLocked, [makeDraft({ pendingSubmission: { ...pendingSubmission, demographics: emptyDemographics() } })]).pendingSubmission, null);
  assert.equal(restoreV4Draft(assignment, [makeDraft({ pendingStage: { stage: "phase1", payload: { schemaVersion: "advice-transfer-v3-admission" } } })]).pendingStage, null);
});

test("a pending final submission takes precedence over a leftover acknowledged stage intent", () => {
  const pendingSubmission = { schemaVersion: SCHEMA_VERSION, assignmentId: assignment.assignmentId, purposeGuess: "fixed final intent", demographics: validDemographics };
  const restored = restoreV4Draft(fullyLocked, [makeDraft({
    screen: "demographics",
    pendingSubmission,
    pendingStage: { stage: "phase2", payload: { schemaVersion: SCHEMA_VERSION, adviceText: advice } },
  })]);
  assert.equal(restored.pendingStage, null);
  assert.deepEqual(restored.pendingSubmission, pendingSubmission);
  assert.equal(restored.screen, "demographics");
});
