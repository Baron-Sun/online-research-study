import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const read = (path) => readFile(new URL(path, root), "utf8");

test("registers an isolated advice-transfer route without replacing existing studies", async () => {
  const [vite, page, entry] = await Promise.all([
    read("vite.config.js"),
    read("advice-transfer/index.html"),
    read("src/advice-transfer.jsx"),
  ]);

  for (const route of [
    "advice/index.html",
    "judgment/index.html",
    "ratings/index.html",
    "comment-source/index.html",
    "advice-transfer/index.html",
  ]) {
    assert.match(vite, new RegExp(route.replace(".", "\\.")));
  }
  assert.match(page, /<title>Online Research Study<\/title>/);
  assert.match(page, /\/src\/advice-transfer\.jsx/);
  assert.match(entry, /AdviceTransferTask/);
});

test("the client implements masked five-comment exposure and A-to-B advice", async () => {
  const client = await read("src/AdviceTransferTask.jsx");

  assert.match(client, /claim_advice_transfer_assignment/);
  assert.match(client, /record_advice_transfer_comprehension_failure/);
  assert.match(client, /submit_advice_transfer_payload/);
  assert.match(client, /value\.comments\.length !== 5/);
  assert.match(client, /value\.exposurePost\.postId === value\.targetPost\.postId/);
  assert.match(client, /Object\.prototype\.hasOwnProperty\.call\(value, "condition"\)/);
  assert.match(client, /related but\s*\n?\s*different/);
  assert.match(client, /Imagine you are commenting on this post in Reddit’s r\/AmItheAsshole community/);
  assert.doesNotMatch(client, /respond as you normally would/i);
  assert.match(client, /First, give one judgment label: YTA, NTA, ESH, NAH, or INFO/);
  assert.match(client, /Begin your advice\s*\n?\s*response with exactly one/);
  for (const label of ["YTA", "NTA", "ESH", "NAH", "INFO"]) {
    assert.match(client, new RegExp(`${label} —`));
  }
  assert.doesNotMatch(client, /close friend|your friend/i);
  assert.doesNotMatch(client, /adviceTransferLocked|preventBack|window\.history\.pushState/);
  for (const backLabel of [
    ">Back<",
    "Back to consent",
    "Back to instructions",
    "Back to advice",
    "Back to ratings",
    "Back to previous question",
  ]) {
    assert.match(client, new RegExp(backLabel));
  }
  assert.match(client, /studyStartedAt: current\.studyStartedAt \|\| time/);
  assert.match(client, /The second Reddit post/);
  assert.match(client, /The earlier discussion is no longer available/);
  assert.doesNotMatch(client, /modelLabel|deepseek_v3|gpt_oss_120b|glm_4_6_direct/);
});

test("the client enforces two-strike screening, clipboard blocking and the 77-word minimum", async () => {
  const [client, css, baseCss, consent] = await Promise.all([
    read("src/AdviceTransferTask.jsx"),
    read("src/advice-transfer.css"),
    read("src/source-detection.css"),
    read("src/advice-transfer-consent.js"),
  ]);

  assert.match(consent, /about 10–12 minutes/);
  assert.match(consent, /does not promise a fixed payment/);
  assert.match(client, /failures >= 2/);
  assert.match(client, /same participant ID cannot restart/i);
  for (const eventName of ["copy", "cut", "paste", "drop", "dragstart", "contextmenu"]) {
    assert.match(client, new RegExp(`"${eventName}"`));
  }
  assert.match(baseCss, /user-select: none/);
  assert.match(css, /user-select: text/);
  assert.match(client, /MIN_ADVICE_WORDS = 77/);
  assert.match(client, /wordCount < MIN_ADVICE_WORDS/);
  assert.match(client, /\[A-Za-z0-9\]\+\(\?:\['-\]\[A-Za-z0-9\]\+\)\*/);

  const count = (value) =>
    value.match(/[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*/g)?.length || 0;
  assert.equal(count(Array(76).fill("word").join(" ")), 76);
  assert.equal(count(Array(77).fill("word").join(" ")), 77);
});

test("all ratings and the three-stage funnel are required and saved", async () => {
  const client = await read("src/AdviceTransferTask.jsx");

  for (const field of [
    "difficulty",
    "effort",
    "confidence",
    "purposeGuess",
    "commentsStoodOut",
    "commentsStoodOutDetails",
    "aiGeneratedBelief",
    "aiLikelihood",
  ]) {
    assert.match(client, new RegExp(field));
  }
  assert.match(client, /Not at all difficult/);
  assert.match(client, /Extremely difficult/);
  assert.match(client, /Not at all effortful/);
  assert.match(client, /Extremely effortful/);
  assert.match(client, /Not at all confident/);
  assert.match(client, /Extremely confident/);
  assert.match(client, /Question 1 of 3/);
  assert.match(client, /Question 2 of 3/);
  assert.match(client, /Question 3 of 3/);
  assert.match(client, /exposureTimeMs/);
  assert.match(client, /adviceResponseTimeMs/);
  assert.match(client, /firstInputAt/);
  assert.match(client, /lastEditAt/);
});

test("the Study 2 client survives traffic bursts and interrupted final saves", async () => {
  const [client, css] = await Promise.all([
    read("src/AdviceTransferTask.jsx"),
    read("src/advice-transfer.css"),
  ]);

  assert.match(client, /heartbeat_advice_transfer_assignment/);
  assert.match(client, /save_advice_transfer_draft/);
  assert.match(client, /withdraw_advice_transfer_assignment/);
  assert.match(client, /mark_advice_transfer_departure/);
  assert.match(client, /admissionStatus === "waiting"/);
  assert.match(client, /Current queue position/);
  assert.match(client, /HEARTBEAT_INTERVAL_MS = 30_000/);
  assert.match(client, /keepalive: true/);
  assert.match(client, /AbortController/);
  assert.match(client, /data === null/);
  assert.match(client, /result\.saved === false/);
  assert.match(client, /result\.active === false/);
  assert.match(client, /p_draft_payload: draftPayload/);
  assert.match(client, /event\?\.persisted/);
  assert.match(client, /Complete study on Prolific/);
  assert.match(client, /sessionId \|\| "session" : "formal"/);
  assert.match(client, /CLAIM_RETRY_DELAYS_MS/);
  assert.match(client, /SUBMIT_RETRY_DELAYS_MS/);
  assert.match(client, /pendingSubmission/);
  assert.match(client, /Retry submission/);
  assert.match(client, /window\.localStorage/);
  assert.match(css, /transfer-save-status/);
});

test("the formal database enforces hard per-cell quota tokens and standby promotion", async () => {
  const schema = await read("supabase_advice_transfer_setup.sql");

  assert.match(schema, /formal_target_per_cell/);
  assert.match(schema, /assignment_lease_minutes/);
  assert.match(schema, /reclaim_expired_advice_transfer_assignments/);
  assert.match(schema, /lease_expires_at/);
  assert.match(schema, /validity_status in \('pending', 'valid'\)/);
  assert.match(schema, /heartbeat_advice_transfer_assignment/);
  assert.match(schema, /save_advice_transfer_draft/);
  assert.match(schema, /review_advice_transfer_assignment/);
  assert.match(schema, /advice_transfer_formal_cell_progress/);
  assert.match(schema, /create table if not exists public\.advice_transfer_quota_tokens/);
  assert.match(schema, /create table if not exists public\.advice_transfer_waitlist/);
  assert.match(schema, /state in \('available', 'reserved', 'pending', 'valid'\)/);
  assert.match(schema, /promote_advice_transfer_standby/);
  assert.match(schema, /quota_invariant_ok/);
  assert.match(schema, /advice_transfer_admission_v3/);
  assert.match(schema, /unique \(prolific_pid, study_id\)/);
  assert.match(schema, /where not is_test/);
  assert.match(schema, /guard_advice_transfer_target_reduction/);
  assert.match(schema, /advice_transfer_assignment_quota_token_unique/);
  assert.match(schema, /drop view if exists public\.advice_transfer_formal_cell_progress/);
  assert.match(schema, /queued\.study_id = coalesce\(p_study_id, ''\)/);
  assert.match(schema, /The selected Study 2 quota token was no longer available/);
  assert.match(schema, /advice_word_count >= 77/);
  assert.match(schema, /v_word_count < 77/);
});

test("the rollback-only database acceptance script covers the full replacement lifecycle", async () => {
  const integration = await read("tests/advice-transfer-integration.sql");
  assert.match(integration, /^begin;/m);
  assert.match(integration, /admissionStatus' <> 'waiting'/);
  assert.match(integration, /reclaim_expired_advice_transfer_assignments/);
  assert.match(integration, /late old browser should initially be standby/);
  assert.match(integration, /review_advice_transfer_assignment[\s\S]*'excluded'/);
  assert.match(integration, /quota_committed > target_per_cell/);
  assert.match(integration, /^rollback;/m);
  assert.match(integration, /integration_passed_and_rolled_back/);
});

const buildQuotaSimulation = (target = 5) => {
  const cells = Array.from({ length: 20 }, (_, index) => ({
    index,
    tokens: Array.from({ length: target }, () => ({ state: "available", owner: null })),
    standby: [],
  }));
  const participants = new Map();

  const invariant = () => {
    for (const cell of cells) {
      assert.equal(cell.tokens.length, target);
      assert.ok(cell.tokens.every(({ state }) => ["available", "reserved", "pending", "valid"].includes(state)));
      assert.ok(cell.tokens.filter(({ state }) => state !== "available").length <= target);
      assert.equal(new Set(cell.tokens.filter(({ owner }) => owner).map(({ owner }) => owner)).size,
        cell.tokens.filter(({ owner }) => owner).length);
    }
  };

  const claim = (participantId) => {
    if (participants.has(participantId)) return participants.get(participantId);
    const eligible = cells.filter((cell) => cell.tokens.some(({ state }) => state === "available"));
    if (!eligible.length) {
      const cell = cells.slice().sort((a, b) => a.standby.length - b.standby.length || a.index - b.index)[0];
      const record = { participantId, cell: cell.index, kind: "waiting", status: "waiting" };
      participants.set(participantId, record);
      return record;
    }
    const cell = eligible.slice().sort((a, b) =>
      a.tokens.filter(({ state }) => state !== "available").length -
        b.tokens.filter(({ state }) => state !== "available").length || a.index - b.index)[0];
    const token = cell.tokens.find(({ state }) => state === "available");
    token.state = "reserved";
    token.owner = participantId;
    const record = { participantId, cell: cell.index, kind: "quota", status: "claimed" };
    participants.set(participantId, record);
    invariant();
    return record;
  };

  const toStandby = (participantId) => {
    const record = participants.get(participantId);
    assert.equal(record.kind, "waiting");
    record.kind = "standby";
    record.status = "claimed";
    cells[record.cell].standby.push(participantId);
    return record;
  };

  const release = (participantId) => {
    const record = participants.get(participantId);
    const cell = cells[record.cell];
    const token = cell.tokens.find(({ owner }) => owner === participantId);
    if (token?.state === "reserved") {
      token.state = "available";
      token.owner = null;
    }
    record.status = "abandoned";
    const nextId = cell.standby.find((id) => participants.get(id).status === "claimed");
    if (nextId) {
      const next = participants.get(nextId);
      token.state = "reserved";
      token.owner = nextId;
      next.kind = "quota";
    }
    invariant();
  };

  const submit = (participantId) => {
    const record = participants.get(participantId);
    const cell = cells[record.cell];
    const token = cell.tokens.find(({ owner }) => owner === participantId);
    record.status = "submitted";
    record.countsTowardQuota = Boolean(token && record.kind === "quota");
    if (record.countsTowardQuota) token.state = "pending";
    invariant();
  };

  return { cells, participants, claim, toStandby, release, submit, invariant };
};

test("a 100-person burst reserves exactly five observations in every formal cell", () => {
  const simulation = buildQuotaSimulation();
  for (let index = 0; index < 100; index += 1) simulation.claim(`P${index}`);
  simulation.invariant();
  assert.ok(simulation.cells.every((cell) => cell.tokens.every(({ state }) => state === "reserved")));
  assert.equal(simulation.claim("P0"), simulation.participants.get("P0"));
  assert.equal(simulation.participants.size, 100, "the same Prolific ID cannot receive a second assignment");
});

test("extra arrivals wait, replacements inherit released tokens, and late tabs never double count", () => {
  const simulation = buildQuotaSimulation();
  for (let index = 0; index < 100; index += 1) simulation.claim(`P${index}`);
  for (let index = 100; index < 110; index += 1) simulation.toStandby(simulation.claim(`P${index}`).participantId);

  const returning = Array.from({ length: 10 }, (_, index) => `P${index}`);
  returning.forEach((participantId) => simulation.release(participantId));
  simulation.invariant();

  const promoted = [...simulation.participants.values()].filter(
    ({ kind, participantId }) => kind === "quota" && /^P10\d$/.test(participantId),
  );
  assert.equal(promoted.length, 10);
  promoted.forEach(({ participantId }) => simulation.submit(participantId));

  returning.forEach((participantId) => simulation.submit(participantId));
  assert.ok(returning.every((participantId) => !simulation.participants.get(participantId).countsTowardQuota));
  assert.equal(simulation.cells.reduce((sum, cell) =>
    sum + cell.tokens.filter(({ state }) => state !== "available").length, 0), 100);
});
