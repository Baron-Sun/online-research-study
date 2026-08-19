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
  assert.match(client, /The earlier discussion is no longer available/);
  assert.doesNotMatch(client, /modelLabel|deepseek_v3|gpt_oss_120b|glm_4_6_direct/);
});

test("the client enforces two-strike screening, clipboard blocking and 50 words", async () => {
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
  assert.match(client, /wordCount < 50/);
  assert.match(client, /\[A-Za-z0-9\]\+\(\?:\['-\]\[A-Za-z0-9\]\+\)\*/);

  const count = (value) =>
    value.match(/[A-Za-z0-9]+(?:['-][A-Za-z0-9]+)*/g)?.length || 0;
  assert.equal(count(Array(49).fill("word").join(" ")), 49);
  assert.equal(count(Array(50).fill("word").join(" ")), 50);
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

test("100 least-filled test claims produce five assignments in every primary cell", () => {
  const cells = Array.from({ length: 10 }, (_, pairIndex) =>
    ["human", "ai"].map((condition) => ({
      pairNumber: pairIndex + 1,
      condition,
      occupied: 0,
    })),
  ).flat();

  for (let participant = 0; participant < 100; participant += 1) {
    const minimum = Math.min(...cells.map(({ occupied }) => occupied));
    const tied = cells.filter(({ occupied }) => occupied === minimum);
    tied[participant % tied.length].occupied += 1;
  }

  assert.equal(cells.length, 20);
  assert.ok(cells.every(({ occupied }) => occupied === 5));
  assert.equal(
    cells.filter(({ condition }) => condition === "human").reduce((sum, cell) => sum + cell.occupied, 0),
    50,
  );
  assert.equal(
    cells.filter(({ condition }) => condition === "ai").reduce((sum, cell) => sum + cell.occupied, 0),
    50,
  );
});
