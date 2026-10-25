export const RESPONSE_WORD_LIMIT = 61;
export const WORD_COUNT_VERSION = 'whitespace-total-v1';
export const WORD_LIMIT_INSTRUCTION = `Write no more than ${RESPONSE_WORD_LIMIT} words in total, including the judgment label. You do not need to use the full word allowance.`;

export function countWords(value) {
  return String(value ?? '').split(/[\u0009-\u000d\u001c-\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+/u).filter(Boolean).length;
}
