import test from 'node:test';
import assert from 'node:assert/strict';
import { usesLabelFeedback, feedbackForAssignment, labelsFromFeedback,
  feedbackComplete, restoredLabelSelection } from '../src/advice-transfer-label-feedback.mjs';

const assignment = {
  assignmentId: 'qa-assignment', labelFeedbackVersion: 'original-label-v1',
  commentOrder: [3, 0, 4, 2, 1], commentHashes: ['a', 'b', 'c', 'd', 'e'],
};
const records = assignment.commentOrder.map((commentIndex, index) => ({
  displayPosition: index + 1, commentIndex, commentSha256: assignment.commentHashes[index],
  originalLabel: 'NTA', firstLabel: 'YTA', finalLabel: 'YTA', feedbackOffered: true,
}));

test('feedback uses displayed order and the exact assigned text hash', () => {
  const corrupt = [
    { ...records[0], displayPosition: 0 },
    { ...records[1], commentIndex: 4 },
    { ...records[2], commentSha256: 'different-text' },
    { ...records[3], originalLabel: 'UNKNOWN' },
    { ...records[4], firstLabel: '' },
  ];
  assert.deepEqual(feedbackForAssignment(assignment, corrupt), []);
  assert.deepEqual(labelsFromFeedback(assignment, [...records].reverse()), Array(5).fill('YTA'));
});

test('all five saved choices are required, but agreement with the original labels is not', () => {
  const labels = Array(5).fill('YTA');
  assert.equal(feedbackComplete(assignment, labels, records), true);
  assert.equal(feedbackComplete(assignment, labels, records.slice(1)), false);
  assert.equal(feedbackComplete(assignment, ['NTA', ...labels.slice(1)], records), false);
  assert.equal(feedbackComplete(assignment, labels, null), false);
});

test('previous assignments retain the no-feedback flow', () => {
  const oldAssignment = { ...assignment, labelFeedbackVersion: 'none' };
  assert.equal(usesLabelFeedback(oldAssignment), false);
  assert.equal(usesLabelFeedback({}), false);
  assert.equal(feedbackComplete(oldAssignment, Array(5).fill('YTA'), []), true);
});

test('a pending selection resumes only for its exact unlocked assignment and comment', () => {
  const pending = {
    assignmentId: 'qa-assignment', eventId: 'one-logical-click', displayPosition: 2,
    commentIndex: 0, commentSha256: 'b', selectedLabel: 'ESH',
  };
  assert.equal(restoredLabelSelection(assignment, pending), pending);
  for (const patch of [
    { assignmentId: 'other' }, { eventId: '' }, { displayPosition: 6 },
    { commentIndex: 1 }, { commentSha256: 'other' }, { selectedLabel: 'unknown' },
  ]) assert.equal(restoredLabelSelection(assignment, { ...pending, ...patch }), null);
  assert.equal(restoredLabelSelection({ ...assignment, phase1LockedAt: 'locked' }, pending), null);
  assert.equal(restoredLabelSelection({ ...assignment, labelFeedbackVersion: 'none' }, pending), null);
});
