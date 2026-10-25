// Explicit integration probe. Uses only the existing public anon key and synthetic preview IDs.
// Never opens recruitment or writes formal participant records.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {requestSession,verifyMaterial} from '../src/original100-protocol.mjs';
const env=Object.fromEntries((await readFile(new URL('../.env.local',import.meta.url),'utf8')).trim().split('\n').map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
const config={url:env.VITE_SUPABASE_URL,anonKey:env.VITE_SUPABASE_ANON_KEY};
assert.equal(config.url,'https://kkfyoztlpjuvipqaoyig.supabase.co');
const pid=`qa-original100-concurrency-${Date.now()}`;
const identity={pid,studyId:'original100-preview',sessionId:pid,preview:true,token:randomBytes(32).toString('hex')};
const call=(action,payload)=>requestSession(config,identity,action,payload);
const claimed=await Promise.all(Array.from({length:16},()=>call('claim',{consent:true,slot:'S001'})));
assert.equal(new Set(claimed.map(p=>p.id)).size,1);
await verifyMaterial(claimed[0]);
await assert.rejects(requestSession(config,{...identity,token:randomBytes(32).toString('hex')},'resume',{}));
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
await assert.rejects(requestSession(config,{...identity,pid:'a'.repeat(24),studyId:'not-launched',sessionId:'b'.repeat(24),preview:false},'claim',{consent:true}));
const privacy=[];
for(const table of ['original100_participants','original100_responses','original100_completed_comments']) {
 const response=await fetch(`${config.url}/rest/v1/${table}?select=*&limit=1`,{headers:{apikey:config.anonKey,Authorization:`Bearer ${config.anonKey}`}});
 assert.ok([401,403].includes(response.status));privacy.push({table,status:response.status});
}
const result={timestamp:new Date().toISOString(),project:'kkfyoztlpjuvipqaoyig',syntheticPid:pid,previewId:claimed[0].id,
  concurrentIdenticalClaims:16,uniqueAssignments:1,competingSaves:8,acceptedCompetingSaves:1,
  wrongTokenRejected:true,staleWriteRejected:true,idempotentRetry:true,incompleteSubmitRejected:true,
  positionRestored:true,concurrentFinalSubmissionsIdempotent:true,completedAnswersLocked:true,formalEntryClosed:true,privacy};
await mkdir(new URL('../verification/',import.meta.url),{recursive:true});
await writeFile(new URL('../verification/live-api.json',import.meta.url),JSON.stringify(result,null,2));
console.log(JSON.stringify(result,null,2));
