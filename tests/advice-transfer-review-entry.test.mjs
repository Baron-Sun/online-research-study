import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { ensureSharedReviewParticipant } from "../src/advice-transfer-review-entry.mjs";

const makeLocation = (url) => {
  const parsed = new URL(url);
  return {
    pathname: parsed.pathname,
    search: parsed.search,
    hash: parsed.hash,
  };
};

const makeHistory = () => ({
  state: { existing: true },
  calls: [],
  replaceState(state, title, url) {
    this.calls.push({ state, title, url });
  },
});

const makeCrypto = (...values) => ({
  randomUUID() {
    assert.ok(values.length, "test crypto ran out of UUID values");
    return values.shift();
  },
});

test("a bare shared review URL becomes an independent test-mode identity", () => {
  const location = makeLocation("https://example.test/advice-transfer/?review=1#phase");
  const history = makeHistory();
  const result = ensureSharedReviewParticipant({
    location,
    history,
    cryptoProvider: makeCrypto("participant-uuid", "session-uuid"),
  });

  assert.deepEqual(
    { prolificPid: result.prolificPid, studyId: result.studyId, sessionId: result.sessionId },
    {
      prolificPid: "qa-review-participant-uuid",
      studyId: "study2-v4-review",
      sessionId: "qa-review-session-session-uuid",
    },
  );
  assert.equal(history.calls.length, 1);
  const rewritten = new URL(history.calls[0].url, "https://example.test");
  assert.equal(rewritten.searchParams.get("review"), "1");
  assert.equal(rewritten.searchParams.get("PROLIFIC_PID"), result.prolificPid);
  assert.equal(rewritten.searchParams.get("STUDY_ID"), result.studyId);
  assert.equal(rewritten.searchParams.get("SESSION_ID"), result.sessionId);
  assert.equal(rewritten.hash, "#phase");
});

test("separate openings of the same shared URL receive separate assignments", () => {
  const first = ensureSharedReviewParticipant({
    location: makeLocation("https://example.test/advice-transfer/?review=1"),
    history: makeHistory(),
    cryptoProvider: makeCrypto("first-participant", "first-session"),
  });
  const second = ensureSharedReviewParticipant({
    location: makeLocation("https://example.test/advice-transfer/?review=1"),
    history: makeHistory(),
    cryptoProvider: makeCrypto("second-participant", "second-session"),
  });

  assert.notEqual(first.prolificPid, second.prolificPid);
  assert.notEqual(first.sessionId, second.sessionId);
});

test("refresh after rewriting preserves the generated review identity", () => {
  const firstHistory = makeHistory();
  const first = ensureSharedReviewParticipant({
    location: makeLocation("https://example.test/advice-transfer/?review=1"),
    history: firstHistory,
    cryptoProvider: makeCrypto("persistent-participant", "persistent-session"),
  });
  const refreshHistory = makeHistory();
  const refresh = ensureSharedReviewParticipant({
    location: makeLocation(`https://example.test${first.nextUrl}`),
    history: refreshHistory,
    cryptoProvider: makeCrypto("unused-participant", "unused-session"),
  });

  assert.equal(refresh, null);
  assert.equal(refreshHistory.calls.length, 0);
});

test("explicit Prolific and QA identities are never rewritten", () => {
  for (const pid of ["formal-participant", "qa-explicit-reviewer"]) {
    const history = makeHistory();
    const result = ensureSharedReviewParticipant({
      location: makeLocation(
        `https://example.test/advice-transfer/?review=1&PROLIFIC_PID=${pid}&STUDY_ID=existing&SESSION_ID=existing`,
      ),
      history,
      cryptoProvider: makeCrypto("unused-participant", "unused-session"),
    });
    assert.equal(result, null);
    assert.equal(history.calls.length, 0);
  }
});

test("ordinary URLs without the review flag retain the missing-ID behavior", () => {
  const history = makeHistory();
  const result = ensureSharedReviewParticipant({
    location: makeLocation("https://example.test/advice-transfer/"),
    history,
    cryptoProvider: makeCrypto("unused-participant", "unused-session"),
  });

  assert.equal(result, null);
  assert.equal(history.calls.length, 0);
});

test("the task prepares a shared review identity before reading participant parameters", async () => {
  const client = await readFile(
    new URL("../src/AdviceTransferTask.jsx", import.meta.url),
    "utf8",
  );
  assert.match(
    client,
    /ensureSharedReviewParticipant\(\);\s+const participant = getParticipant\(\);/,
  );
});
