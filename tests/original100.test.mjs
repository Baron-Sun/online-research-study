import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {validComment,verifyMaterial,VERSION} from '../src/original100-protocol.mjs';
test('all 100 exact Original prompts and fixed assignment rows match the reviewed source',async()=>{
 const manifest=JSON.parse(await readFile(new URL('../original100-material-manifest.json',import.meta.url),'utf8'));
 const seed=await readFile(new URL('../supabase_original100_seed.sql',import.meta.url),'utf8');
 const source=JSON.parse(seed.split('$materials$')[1]);
 assert.equal(source.length,100);assert.equal(manifest.plan.length,300);
 for(const item of source){
  assert.equal(createHash('sha256').update(item.prompt_text).digest('hex'),item.prompt_sha256);
  assert.equal(manifest.posts.find(p=>p.stimulus_id===item.stimulus_id).prompt_sha256,item.prompt_sha256);
  const rows=manifest.plan.filter(p=>p.stimulus_id===item.stimulus_id);
  assert.equal(rows.length,3);assert.equal(new Set(rows.map(p=>p.slot_id)).size,3);
  assert.equal(new Set(rows.map(p=>p.position)).size,3);
 }
 for(const slot of new Set(manifest.plan.map(p=>p.slot_id))) assert.equal(new Set(manifest.plan.filter(p=>p.slot_id===slot).map(p=>p.stimulus_id)).size,3);
});
test('client rejects missing reasoning, malformed format, duplicate or altered stimuli',async()=>{
 assert.ok(validComment('INFO\nI would need more information.'));
 for(const answer of ['NTA','NTA\n  ','Some thoughts\nNTA','NTA because...', 'YTA NTA\nreason']) assert.equal(validComment(answer),false);
 const text='Exact instruction\nPost'; const sha256=createHash('sha256').update(text).digest('hex');
 const session={version:VERSION,responseWordLimit:61,wordCountVersion:'whitespace-total-v1',posts:[1,2,3].map(i=>({position:i,stimulusId:`P${i}`,prompt:text,sha256}))};
 await verifyMaterial(session);
 await assert.rejects(verifyMaterial({...session,posts:session.posts.map((p,i)=>i===0?{...p,prompt:p.prompt+' '}:p)}));
 await assert.rejects(verifyMaterial({...session,posts:[session.posts[0],session.posts[0],session.posts[2]]}));
});
