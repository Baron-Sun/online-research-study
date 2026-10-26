// Explicit integration probe. Uses only the existing public anon key and synthetic preview IDs.
// Never opens recruitment or writes formal participant records.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomBytes,randomUUID} from 'node:crypto';
import {requestSession,verifyMaterial} from '../src/original100-protocol.mjs';
const env=Object.fromEntries((await readFile(new URL('../.env.local',import.meta.url),'utf8')).trim().split('\n').map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
const config={url:env.VITE_SUPABASE_URL,anonKey:env.VITE_SUPABASE_ANON_KEY};
assert.equal(config.url,'https://kkfyoztlpjuvipqaoyig.supabase.co');
const pid=`qa-matched100-concurrency-${Date.now()}`;
const identity={pid,studyId:'matched100-preview',sessionId:pid,preview:true,token:randomBytes(32).toString('hex')};
const call=(action,payload)=>requestSession(config,identity,action,payload);
const claimed=await Promise.all(Array.from({length:16},()=>call('claim',{consent:true,slot:'S001'})));
assert.equal(new Set(claimed.map(p=>p.id)).size,1);
await verifyMaterial(claimed[0]);
await assert.rejects(requestSession(config,{...identity,token:randomBytes(32).toString('hex')},'resume',{}));
await assert.rejects(call('navigate',{position:1}),/task understanding check/);
await assert.rejects(call('save',{position:1,revision:0,answer:'NTA\nCannot save before the check.'}),/task understanding check/);
const wrongCheck={event_id:randomUUID(),choice:'summarize',version:'task-comprehension-v1'};
const attempts=await Promise.all(Array.from({length:8},()=>call('comprehension_check',wrongCheck)));
assert.ok(attempts.every(r=>r.comprehensionCheck.attempts===1&&!r.comprehensionCheck.passed));
assert.equal((await call('resume',{})).comprehensionCheck.attempts,1);
await assert.rejects(call('comprehension_check',{...wrongCheck,choice:'judgment_reasons'}),/already recorded/);
const passed=await call('comprehension_check',{event_id:randomUUID(),choice:'judgment_reasons',version:'task-comprehension-v1'});
assert.deepEqual(passed.comprehensionCheck,{version:'task-comprehension-v1',attempts:2,passed:true,failed:false,remainingAttempts:0});
assert.equal((await call('resume',{})).comprehensionCheck.passed,true);
await assert.rejects(call('attention_check',{event_id:randomUUID(),choice:'blue',version:'attention-v1-blue'}),/earlier task version/);
const failedIdentity={...identity,pid:pid+'-fail',sessionId:pid+'-fail',token:randomBytes(32).toString('hex')};
const failCall=(action,payload)=>requestSession(config,failedIdentity,action,payload);
await failCall('claim',{consent:true,slot:'S001'});
let failed=await failCall('comprehension_check',{event_id:randomUUID(),choice:'advice',version:'task-comprehension-v1'});
assert.equal(failed.comprehensionCheck.remainingAttempts,1);
const failedAttempt={event_id:randomUUID(),choice:'label_only',version:'task-comprehension-v1'};
const failureRetries=await Promise.all(Array.from({length:8},()=>failCall('comprehension_check',failedAttempt)));
assert.ok(failureRetries.every(r=>r.status==='screened_out'&&r.comprehensionCheck.attempts===2));
assert.equal((await failCall('resume',{})).status,'screened_out');
assert.equal((await failCall('comprehension_check',{event_id:randomUUID(),choice:'judgment_reasons',version:'task-comprehension-v1'})).status,'screened_out');
assert.equal((await failCall('save',{position:1,revision:0,answer:'NTA\nForbidden after screening'})).posts[0].answer,'');
const raced=await Promise.allSettled(Array.from({length:8},(_,i)=>call('save',{position:1,revision:0,answer:`NTA\nSYNTHETIC API CONCURRENCY TEST ONLY. Writer ${i}.`})));
assert.equal(raced.filter(r=>r.status==='fulfilled').length,1);
let current=await call('resume',{});
assert.equal(current.posts[0].revision,1);
await call('save',{position:1,revision:0,answer:current.posts[0].answer}); // Lost receipt retry.
await assert.rejects(call('complete',{revisions:[1,0,0]}));
for(const position of [2,3]) await call('save',{position,revision:0,answer:'INFO\nSYNTHETIC API TEST ONLY. This is not a research response.'});
await call('navigate',{position:2});
assert.equal((await call('resume',{})).position,2);
const completed=await Promise.all([call('complete',{revisions:[1,1,1]}),call('complete',{revisions:[1,1,1]})]);
assert.ok(completed.every(r=>r.status==='completed'&&r.completionCode===null));
await assert.rejects(call('save',{position:1,revision:1,answer:'NTA\nForbidden edit'}));
const limitedIdentity={...identity,pid:pid+'-words',sessionId:pid+'-words',token:randomBytes(32).toString('hex')};
const limitCall=(action,payload)=>requestSession(config,limitedIdentity,action,payload);
const limited=await limitCall('claim',{consent:true,slot:'S001'});
assert.equal(limited.responseWordLimit,61);assert.equal(limited.wordCountVersion,'whitespace-total-v1');
await limitCall('comprehension_check',{event_id:randomUUID(),choice:'judgment_reasons',version:'task-comprehension-v1'});
const makeWords=n=>'INFO\nSYNTHETIC WORD LIMIT TEST '+Array(n-5).fill('word').join(' ');
await limitCall('save',{position:1,revision:0,answer:makeWords(62)});
assert.equal((await limitCall('resume',{})).posts[0].answer,makeWords(62));
await assert.rejects(limitCall('navigate',{position:2}),/61 words or fewer/);
for(const position of [2,3]) await limitCall('save',{position,revision:0,answer:'INFO\nSYNTHETIC WORD LIMIT TEST ONLY.'});
await assert.rejects(limitCall('complete',{revisions:[1,1,1]}),/61 words or fewer/);
await limitCall('save',{position:1,revision:1,answer:makeWords(61)});
assert.equal((await limitCall('navigate',{position:4})).position,4);
assert.equal((await limitCall('complete',{revisions:[2,1,1]})).status,'completed');
await assert.rejects(requestSession(config,{...identity,pid:'a'.repeat(24),studyId:'not-launched',sessionId:'b'.repeat(24),preview:false},'claim',{consent:true}));
const privacy=[];
for(const table of ['matched100_participants','matched100_responses','matched100_completed_comments','matched100_materials']) {
 const response=await fetch(`${config.url}/rest/v1/${table}?select=*&limit=1`,{headers:{apikey:config.anonKey,Authorization:`Bearer ${config.anonKey}`}});
 assert.ok([401,403].includes(response.status));privacy.push({table,status:response.status});
}
const result={timestamp:new Date().toISOString(),project:'kkfyoztlpjuvipqaoyig',syntheticPid:pid,previewId:claimed[0].id,
  concurrentIdenticalClaims:16,uniqueAssignments:1,competingSaves:8,acceptedCompetingSaves:1,
  wrongTokenRejected:true,staleWriteRejected:true,idempotentRetry:true,incompleteSubmitRejected:true,
  comprehensionGateEnforced:true,comprehensionFailurePersisted:true,comprehensionRetryIdempotent:true,comprehensionPassedAfterCorrection:true,twoFailuresEndSession:true,originalColorCheckRejected:true,
  positionRestored:true,concurrentFinalSubmissionsIdempotent:true,completedAnswersLocked:true,formalEntryClosed:true,
  responseWordLimit:61,overLimitDraftRetained:true,overLimitNavigationBlocked:true,overLimitFinalBlocked:true,exactLimitAccepted:true,privacy};
await mkdir(new URL('../verification/',import.meta.url),{recursive:true});
await writeFile(new URL('../verification/matched100-live-api.json',import.meta.url),JSON.stringify(result,null,2));
console.log(JSON.stringify(result,null,2));
