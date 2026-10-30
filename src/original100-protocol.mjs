import {MATERIAL_VERSION,SESSION_RPC} from './private100-content.mjs';
import {countWords,RESPONSE_MIN_WORDS,RESPONSE_MAX_WORDS,WORD_COUNT_VERSION} from './private100-word-minimum.mjs';
export const VERSION = MATERIAL_VERSION;
export function validComment(answer) {
  return countWords(answer) >= RESPONSE_MIN_WORDS;
}
export async function verifyMaterial(session) {
  const completedLegacy=session.status==='completed'&&session.version==='private100-study1matched-min60-20261026-v5';
  if (session.version !== VERSION && !completedLegacy) throw new Error('This link uses an earlier version of the task. Please reopen the current study link.');
  if (session.responseWordMinimum !== RESPONSE_MIN_WORDS || session.responseWordLimit !== RESPONSE_MAX_WORDS || session.wordCountVersion !== WORD_COUNT_VERSION) throw new Error('The response length settings do not match this task. Please reload.');
  if (session.posts?.length !== 3 || new Set(session.posts.map(p=>p.stimulusId)).size !== 3) {
    throw new Error('The assigned study material is incomplete. Please contact the researcher.');
  }
  for (const [index, post] of session.posts.entries()) {
    const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(post.prompt)))].map(x=>x.toString(16).padStart(2,'0')).join('');
    if (post.position !== index+1 || hash !== post.sha256) throw new Error('The assigned text failed its integrity check. Please reload.');
  }
  return session;
}
export async function requestSession(config, identity, action, payload = {}) {
  let lastError;
  for (let attempt=0; attempt<3; attempt++) {
    const controller = new AbortController();
    const timeout = setTimeout(()=>controller.abort(), 15000);
    try {
      const res = await fetch(`${config.url}/rest/v1/rpc/${SESSION_RPC}`, {
        method:'POST', signal:controller.signal,
        headers:{apikey:config.anonKey, Authorization:`Bearer ${config.anonKey}`, 'Content-Type':'application/json'},
        body:JSON.stringify({p_action:action,p_pid:identity.pid,p_study_id:identity.studyId,p_session_id:identity.sessionId,
          p_token:identity.token,p_preview:identity.preview,p_payload:payload})
      });
      const data = await res.json();
      if (!res.ok) {
        const err = new Error(data.message || 'The response could not be saved. Please try again.');
        err.retryable = res.status >= 500 || res.status === 429 || ['40001','40P01','55P03'].includes(data.code);
        throw err;
      }
      return data;
    } catch (error) {
      lastError = error;
      if (error.retryable === false || attempt === 2) throw error;
    } finally { clearTimeout(timeout); }
    await new Promise(resolve=>setTimeout(resolve,500*(attempt+1)));
  }
  throw lastError;
}
