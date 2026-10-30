export {emptyDemographics,normalizeDemographics,demographicsComplete} from './advice-transfer-protocol.mjs';
import {normalizeDemographics} from './advice-transfer-protocol.mjs';

export const sameDemographics=(left,right)=>JSON.stringify(normalizeDemographics(left))===JSON.stringify(normalizeDemographics(right));
export const taskScreenFor=(session)=>session.status==='screened_out'?'screened-out':
  session.status==='completed'?'complete':!session.comprehensionCheck?.passed?'instructions':
  session.position===5?'demographics':session.position===4?'review':'task';
