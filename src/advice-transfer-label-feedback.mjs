import { JUDGMENT_LABELS } from "./advice-transfer-protocol.mjs";

export const LABEL_FEEDBACK_VERSION = "original-label-v1";

export const usesLabelFeedback = (assignment) =>
  assignment?.labelFeedbackVersion === LABEL_FEEDBACK_VERSION;

// Accept only records tied to the exact displayed comment and permutation.
export const feedbackForAssignment = (assignment, records = []) =>
  Array.isArray(records) ? records.filter((record) => {
    const index = record?.displayPosition - 1;
    return Number.isInteger(index) && index >= 0 && index < 5 &&
      record.commentIndex === assignment.commentOrder[index] &&
      record.commentSha256 === assignment.commentHashes[index] &&
      JUDGMENT_LABELS.includes(record.originalLabel) &&
      JUDGMENT_LABELS.includes(record.firstLabel) &&
      JUDGMENT_LABELS.includes(record.finalLabel);
  }) : [];

export const labelsFromFeedback = (assignment, records) =>
  assignment.commentOrder.map((_, index) =>
    feedbackForAssignment(assignment, records)
      .find((record) => record.displayPosition === index + 1)?.finalLabel || "");

export const feedbackComplete = (assignment, labels, records) =>
  !usesLabelFeedback(assignment) ||
  labelsFromFeedback(assignment, records).every((label, index) =>
    JUDGMENT_LABELS.includes(label) && label === labels[index]);

export const restoredLabelSelection = (assignment, pending) => {
  if (!usesLabelFeedback(assignment) || assignment.phase1LockedAt || !pending) return null;
  const index = pending.displayPosition - 1;
  return pending.assignmentId === assignment.assignmentId &&
    Number.isInteger(index) && index >= 0 && index < 5 &&
    pending.commentIndex === assignment.commentOrder[index] &&
    pending.commentSha256 === assignment.commentHashes[index] &&
    JUDGMENT_LABELS.includes(pending.selectedLabel) &&
    typeof pending.eventId === "string" && pending.eventId.length > 0 && pending.eventId.length <= 128
    ? pending : null;
};
