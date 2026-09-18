export const PERCEPTION_QUESTIONS_VERSION = "perception-questions-v1";
export const PERCEPTION_ITEMS = Object.freeze([
  {
    key: "perceivedConsensus",
    question: "To what extent did the comments agree with one another about how to think about this situation?",
    low: "Not at all", high: "Very much",
  },
  {
    key: "roomForDisagreement",
    introduction: "Some situations have one clear right answer. Others are ones where thoughtful people could genuinely see it differently.",
    question: "How much room for disagreement is there in this situation?",
    low: "One clear right answer", high: "Genuinely open to debate",
  },
]);

export const usesPerceptionQuestions = (assignment) =>
  assignment?.perceptionQuestionsVersion === PERCEPTION_QUESTIONS_VERSION;

export const percentageValue = (value) =>
  Number.isInteger(value) && value >= 0 && value <= 100 ? value : null;

export const emptyPerceptionResponses = () => ({
  perceivedConsensus: null, roomForDisagreement: null,
});

export const perceptionComplete = (assignment, answers) =>
  !usesPerceptionQuestions(assignment) ||
  PERCEPTION_ITEMS.every(({ key }) => percentageValue(answers?.[key]) !== null);

export const restorePerceptionResponses = (assignment, draft) => {
  if (!usesPerceptionQuestions(assignment)) return emptyPerceptionResponses();
  const source = assignment.phase1LockedAt ? assignment.phase1Snapshot : draft;
  return Object.fromEntries(PERCEPTION_ITEMS.map(({ key }) => [key, percentageValue(source?.[key])]));
};
