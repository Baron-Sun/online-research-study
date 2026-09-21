import test from 'node:test';
import assert from 'node:assert/strict';
import { percentageValue, emptyPerceptionResponses, perceptionComplete,
  restorePerceptionResponses, perceptionItemsFor, usesPerceptionQuestions,
  PERCEPTION_QUESTIONS_VERSION } from '../src/advice-transfer-perception.mjs';
const assignment = { perceptionQuestionsVersion: 'perception-questions-v1' };

test('perception ratings accept both endpoints and the midpoint, but never coerce missing answers', () => {
  for (const value of [0, 1, 50, 99, 100]) assert.equal(percentageValue(value), value);
  for (const value of [null, undefined, '', '0', '50', false, true, -1, 101, 0.5, NaN])
    assert.equal(percentageValue(value), null);
  assert.equal(perceptionComplete(assignment, emptyPerceptionResponses()), false);
  assert.equal(perceptionComplete(assignment, { perceivedConsensus: 0, roomForDisagreement: null }), false);
  assert.equal(perceptionComplete(assignment, { perceivedConsensus: 0, roomForDisagreement: 100 }), true);
});

test('new questions never become required or populated for old assignments', () => {
  assert.equal(perceptionComplete({ perceptionQuestionsVersion: 'none' }, {}), true);
  assert.deepEqual(restorePerceptionResponses({}, { perceivedConsensus: 50, roomForDisagreement: 50 }), emptyPerceptionResponses());
});

test('refresh restores zeros and the saved server snapshot overrides even a newer local draft', () => {
  const draft = { perceivedConsensus: 0, roomForDisagreement: 100 };
  assert.deepEqual(restorePerceptionResponses(assignment, draft), draft);
  const locked = { ...assignment, phase1LockedAt: 'locked', phase1Snapshot: draft };
  assert.deepEqual(restorePerceptionResponses(locked, { perceivedConsensus: 90, roomForDisagreement: 5 }), draft);
  assert.deepEqual(restorePerceptionResponses({ ...locked, phase1Snapshot: {} }, draft), emptyPerceptionResponses());
});

test('revised sessions require both ratings while legacy sessions retain their wording', () => {
  const revised = { perceptionQuestionsVersion: PERCEPTION_QUESTIONS_VERSION };
  const legacyItems = perceptionItemsFor(assignment);
  const revisedItems = perceptionItemsFor(revised);
  assert.notEqual(legacyItems[0].question, revisedItems[0].question);
  assert.notEqual(legacyItems[0].low, revisedItems[0].low);
  assert.deepEqual(legacyItems[1], revisedItems[1]);
  for (const session of [assignment, revised]) {
    assert.equal(usesPerceptionQuestions(session), true);
    assert.equal(perceptionComplete(session, emptyPerceptionResponses()), false);
    assert.equal(perceptionComplete(session, { perceivedConsensus: 0, roomForDisagreement: 100 }), true);
    assert.deepEqual(restorePerceptionResponses(session, { perceivedConsensus: 0, roomForDisagreement: 100 }),
      { perceivedConsensus: 0, roomForDisagreement: 100 });
  }
  assert.equal(usesPerceptionQuestions({ perceptionQuestionsVersion: 'unknown' }), false);
});
