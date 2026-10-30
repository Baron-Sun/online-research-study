// Public-anon integration probe; writes only explicitly synthetic preview sessions.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {requestSession,verifyMaterial} from '../src/original100-protocol.mjs';
import {MATERIAL_VERSION} from '../src/private100-content.mjs';
import {taskScreenFor} from '../src/original100-demographics.mjs';
const env=Object.fromEntries((await readFile(new URL('../.env.local',import.meta.url),'utf8')).trim().split('\n').map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
const config={url:env.VITE_SUPABASE_URL,anonKey:env.VITE_SUPABASE_ANON_KEY};
assert.equal(config.url,'https://kkfyoztlpjuvipqaoyig.supabase.co');
const pid=`qa-flow-v6-${randomUUID()}`;
const identity={pid,studyId:'matched100v6-preview',sessionId:pid,preview:true,token:randomBytes(32).toString('hex')};
const call=(action,payload={})=>requestSession(config,identity,action,payload);
const claimed=await call('claim',{consent:true,slot:'S001'});
await verifyMaterial(claimed);
assert.equal(claimed.version,MATERIAL_VERSION);
assert.equal(taskScreenFor(claimed),'instructions');
await assert.rejects(requestSession(config,{...identity,token:randomBytes(32).toString('hex')},'resume',{}));
await assert.rejects(call('navigate',{position:1}),/task understanding check/);
const checked=await call('comprehension_check',{event_id:randomUUID(),choice:'judgment_reasons',version:'task-comprehension-v1'});
assert.equal(taskScreenFor(checked),'task');
assert.equal(checked.position,1);
const words=n=>['SYNTHETIC','PREVIEW','TEST','ONLY',...Array(n-4).fill('word')].join(' ');
await call('save',{position:1,revision:0,answer:words(59)});
await assert.rejects(call('navigate',{position:2}),/at least 60/);
await call('save',{position:1,revision:1,answer:'nTa '+words(59)});
await call('navigate',{position:2});
await call('save',{position:2,revision:0,answer:words(60)});
await call('navigate',{position:3});
await call('save',{position:3,revision:0,answer:'INFO\n'+words(999)});
await call('navigate',{position:4});
await assert.rejects(call('complete',{revisions:[2,1,1],demographicsRevision:0}),/demographic/);
const atDemographics=await call('navigate',{position:5});
assert.equal(taskScreenFor(atDemographics),'demographics');
assert.ok(atDemographics.demographicsOpenedAt);
const partial={genderIdentity:'prefer-not-to-say',ageYears:null,englishProficiency:'',educationLevel:'',employmentStatus:''};
const partialSave=await call('save_demographics',{revision:0,demographics:partial});
assert.equal(partialSave.demographicsRevision,1);
assert.deepEqual((await call('resume')).demographics,partial);
await assert.rejects(call('complete',{revisions:[2,1,1],demographicsRevision:1}),/demographic/);
const full={...partial,ageYears:30,englishProficiency:'yes',educationLevel:'four-year-college-degree',employmentStatus:'employed'};
const raced=await Promise.allSettled([full,{...full,ageYears:31},{...full,ageYears:32}].map(d=>call('save_demographics',{revision:1,demographics:d})));
assert.equal(raced.filter(r=>r.status==='fulfilled').length,1);
const saved=await call('resume');
assert.equal(saved.demographicsRevision,2);
assert.equal(saved.position,5);
const retried=await call('save_demographics',{revision:1,demographics:saved.demographics});
assert.equal(retried.demographicsRevision,2);
await assert.rejects(call('complete',{revisions:[2,1,1],demographicsRevision:1}),/changed in another tab/);
const completed=await Promise.all([call('complete',{revisions:[2,1,1],demographicsRevision:2}),call('complete',{revisions:[2,1,1],demographicsRevision:2})]);
assert.ok(completed.every(p=>p.status==='completed'&&p.completionCode===null&&p.demographicsCompletedAt));
assert.equal(completed[0].completedAt,completed[1].completedAt);
assert.deepEqual(completed[0].demographics,saved.demographics);
await assert.rejects(call('save_demographics',{revision:2,demographics:partial}));
const privacy=[];
for(const table of ['matched100v5_participants','matched100v5_responses','matched100v5_completed_comments','matched100v5_completed_demographics']) {
  const response=await fetch(`${config.url}/rest/v1/${table}?select=*&limit=1`,{headers:{apikey:config.anonKey,Authorization:`Bearer ${config.anonKey}`}});
  assert.ok([401,403].includes(response.status));privacy.push({table,status:response.status});
}
const result={timestamp:new Date().toISOString(),version:MATERIAL_VERSION,syntheticPid:pid,previewId:claimed.id,
  checkGated:true,passedCheckRoutesToTask:true,shortDraftSaved:true,shortNavigationBlocked:true,
  singleParagraphAccepted:true,mixedCaseAccepted:true,noFormatGate:true,thousandWordsAccepted:true,
  demographicsRequired:true,demographicsResume:true,competingSaves:3,acceptedCompetingSaves:1,
  lostReceiptRetryIdempotent:true,staleCompletionRejected:true,completionIdempotent:true,
  demographicsPersistAfterCompletion:true,completedEditsLocked:true,previewHasNoCompletionCode:true,
  formalRecordsWritten:0,privacy};
await mkdir(new URL('../verification/',import.meta.url),{recursive:true});
await writeFile(new URL('../verification/matched100v6-live-api.json',import.meta.url),JSON.stringify(result,null,2));
console.log(JSON.stringify(result,null,2));
