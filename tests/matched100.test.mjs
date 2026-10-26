import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {MATERIAL_VERSION,SESSION_NAMESPACE,SESSION_RPC} from '../src/private100-content.mjs';
import {requestSession,verifyMaterial} from '../src/original100-protocol.mjs';
const read=file=>readFile(new URL('../'+file,import.meta.url),'utf8');
const hash=text=>createHash('sha256').update(text).digest('hex');

test('the matched cohort has 100 distinct posts and balanced 100-by-3 assignments, with intact neutral minimum-60 prompts without EDIT or UPDATE',async()=>{
 const seed=await read('supabase_matched100v5_seed.sql');
 const posts=JSON.parse(seed.split('$materials$')[1]);
 const plan=JSON.parse(seed.split('$plan$')[1]);
 const manifest=JSON.parse(await read('matched100v5-material-manifest.json'));
 const template=(await read('private100_min60_prompt_template.txt')).trimEnd();
 assert.equal(manifest.version,MATERIAL_VERSION);
 assert.equal(manifest.database_namespace,'matched100v5');
 assert.equal(manifest.word_minimum,60);assert.equal(manifest.word_limit,null);
 assert.equal(posts.length,100);assert.equal(new Set(posts.map(p=>p.submission_id)).size,100);
 assert.equal(plan.length,300);assert.deepEqual(plan,manifest.plan);
 assert.equal(new Set(plan.map(p=>p.slot_id)).size,100);
 for(const p of posts){
  assert.deepEqual(Object.keys(p).sort(),['body_sha256','prompt_sha256','prompt_text','stimulus_id','submission_id','word_limit','word_minimum']);
  const body=p.prompt_text.split('\n\nSituation:\n').slice(1).join('\n\nSituation:\n');
  assert.equal(template.replace('{submission_body}',()=>body),p.prompt_text);
  assert.equal(hash(body),p.body_sha256);assert.equal(hash(p.prompt_text),p.prompt_sha256);assert.equal(p.word_minimum,60);assert.equal(p.word_limit,null);assert.doesNotMatch(body,/\b(?:edit(?:s|ed|[0-9]+)?|update(?:s|d|[0-9]+)?)\b/i);
  const assignments=plan.filter(a=>a.stimulus_id===p.stimulus_id);
  assert.equal(assignments.length,3);assert.equal(new Set(assignments.map(a=>a.slot_id)).size,3);
  assert.deepEqual(assignments.map(a=>a.position).sort(),[1,2,3]);
 }
 for(const slot of new Set(plan.map(p=>p.slot_id))){
  const assigned=plan.filter(p=>p.slot_id===slot);
  assert.equal(assigned.length,3);assert.equal(new Set(assigned.map(p=>p.stimulus_id)).size,3);
 }
 const session={version:MATERIAL_VERSION,responseWordMinimum:60,responseWordLimit:null,wordCountVersion:'whitespace-total-v1',
  posts:posts.slice(0,3).map((p,i)=>({position:i+1,stimulusId:p.stimulus_id,prompt:p.prompt_text,sha256:p.prompt_sha256}))};
 await verifyMaterial(session);
 await assert.rejects(verifyMaterial({...session,version:'private100-wordlimit-20261024-v3'}),/earlier version/);
 assert.equal(SESSION_NAMESPACE,'matched100-v5');
});

test('participant traffic goes to the isolated matched cohort RPC',async(t)=>{
 let captured;
 t.mock.method(globalThis,'fetch',async(url,options)=>{
  captured={url,payload:JSON.parse(options.body)};
  return {ok:true,json:async()=>({status:'active'})};
 });
 const identity={pid:'preview-test',studyId:'matched100v5-preview',sessionId:'preview-test',token:'a'.repeat(64),preview:true};
 await requestSession({url:'https://example.invalid',anonKey:'test'},identity,'claim',{consent:true,slot:'S001'});
 assert.equal(SESSION_RPC,'matched100v5_session');
 assert.equal(captured.url,'https://example.invalid/rest/v1/rpc/matched100v5_session');
 assert.equal(captured.payload.p_pid,identity.pid);assert.equal(captured.payload.p_preview,true);
 assert.deepEqual(captured.payload.p_payload,{consent:true,slot:'S001'});
});
