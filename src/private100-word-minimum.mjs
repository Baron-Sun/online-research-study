export {countWords,WORD_COUNT_VERSION} from './private100-word-limit.mjs';
export const RESPONSE_MIN_WORDS = 60;
export const RESPONSE_MAX_WORDS = null;
export const WORD_LENGTH_INSTRUCTION = `Write at least ${RESPONSE_MIN_WORDS} words in total, including the judgment label. There is no maximum word limit.`;
