import test from 'node:test';
import assert from 'node:assert/strict';
import { scaleValue, ratingScaleFor, RATING_SCALE_100, LEGACY_RATING_SCALE, SCHEMA_VERSION,
  phase1Complete, phase2Complete, restoreV4Draft } from '../src/advice-transfer-protocol.mjs';

test('rating versions reject missing, noninteger, out-of-range and unknown values', () => {
  for (const value of [0, 1, 50, 100]) assert.equal(scaleValue(value, RATING_SCALE_100), value);
  for (const value of [null, undefined, '', '50', true, NaN, -1, 101, 50.5]) assert.equal(scaleValue(value, RATING_SCALE_100), null);
  for (const value of [1, 4, 7]) assert.equal(scaleValue(value), value);
  for (const value of [0, 8, 100]) assert.equal(scaleValue(value), null);
  assert.equal(scaleValue(5, 'unknown'), null);
  assert.equal(ratingScaleFor({}), LEGACY_RATING_SCALE);
});
test('phase completion accepts zero and 100 only with the new assigned scale', () => {
  const labels = ['YTA','NTA','ESH','NAH','INFO'];
  const text = 'word '.repeat(80);
  assert.equal(phase1Complete(labels,text,0,RATING_SCALE_100),true);
  assert.equal(phase1Complete(labels,text,100,RATING_SCALE_100),true);
  assert.equal(phase1Complete(labels,text,null,RATING_SCALE_100),false);
  assert.equal(phase1Complete(labels,text,0),false);
  assert.equal(phase2Complete(text,null,0,100,'opinion_difficulty',RATING_SCALE_100),true);
  assert.equal(phase2Complete(text,null,0,100,'opinion_difficulty'),false);
  assert.equal(phase2Complete(text,null,null,100,'opinion_difficulty',RATING_SCALE_100),false);
});
test('refresh restores server-locked zero and 100 without changing units', () => {
  const assignment = {assignmentId:'qa',ratingScaleVersion:RATING_SCALE_100,
    phase1Snapshot:{gistText:'saved gist',gistDifficulty:0,commentJudgments:[],timings:{phase1ActiveTimeMs:100,gistActiveTimeMs:50}},
    phase1LockedAt:'2026-09-24T12:00:00Z',
    phase2Snapshot:{adviceText:'saved opinion',difficulty:100,effort:null,confidence:0,timings:{adviceResponseTimeMs:10}},
    phase2LockedAt:'2026-09-24T12:01:00Z'};
  const result = restoreV4Draft(assignment,[]);
  assert.equal(result.gistDifficulty,0); assert.equal(result.opinionDifficulty,100); assert.equal(result.confidence,0);
  const stale = {assignmentId:'qa',schemaVersion:SCHEMA_VERSION,screen:'overview',gistDifficulty:7};
  assert.equal(restoreV4Draft({assignmentId:'qa',ratingScaleVersion:RATING_SCALE_100},[stale]).gistDifficulty,null);
  assert.equal(restoreV4Draft({assignmentId:'qa'},[stale]).gistDifficulty,7);
});
