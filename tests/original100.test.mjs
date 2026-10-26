import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {validComment,commentFormatError,verifyMaterial,VERSION} from '../src/original100-protocol.mjs';
test('an over-minimum answer explains its missing label, and adding the label and newline clears the blocker',()=>{
 const reasoning=Array(86).fill('a').join(' ');
 assert.equal(validComment(reasoning),false);
 assert.match(commentFormatError(reasoning),/one judgment label on the first line/);
 assert.match(commentFormatError('NTA '+reasoning),/Press Enter/);
 for(const label of ['YTA','NTA','ESH','NAH','INFO']) {
  assert.match(commentFormatError(label+'\n  '),/Write your reasoning/);
  assert.equal(commentFormatError(label+'\n'+reasoning),'');
  assert.equal(validComment(label+'\n'+reasoning),true);
 }
 assert.equal(commentFormatError('NTA\nA short reason.'),'');
 assert.equal(validComment('NTA\nA short reason.'),false);
});
test('all judgment-label casing combinations are accepted without relaxing the label or newline requirement',()=>{
 const reasoning=Array(59).fill('word').join(' ');
 for(const label of ['YTA','NTA','ESH','NAH','INFO']) {
  for(let mask=0;mask<2**label.length;mask++) {
   const variant=[...label].map((letter,i)=>mask&(1<<i)?letter.toLowerCase():letter).join('');
   assert.equal(commentFormatError(variant+'\r\n'+reasoning),'');
   assert.equal(validComment(variant+'\r\n'+reasoning),true,variant);
  }
 }
 for(const label of ['not sure','nta.','yta/nta','NTAA']) assert.equal(validComment(label+'\n'+reasoning),false);
 assert.equal(validComment('nta '+reasoning),false);
 assert.equal(validComment('nta\n'+Array(58).fill('word').join(' ')),false);
});
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
 assert.ok(validComment('INFO\n'+Array(59).fill('word').join(' ')));
 for(const answer of ['NTA','NTA\n  ','Some thoughts\nNTA','NTA because...', 'YTA NTA\nreason']) assert.equal(validComment(answer),false);
 const text='Exact instruction\nPost'; const sha256=createHash('sha256').update(text).digest('hex');
 const session={version:VERSION,responseWordMinimum:60,responseWordLimit:null,wordCountVersion:'whitespace-total-v1',posts:[1,2,3].map(i=>({position:i,stimulusId:`P${i}`,prompt:text,sha256}))};
 await verifyMaterial(session);
 await assert.rejects(verifyMaterial({...session,posts:session.posts.map((p,i)=>i===0?{...p,prompt:p.prompt+' '}:p)}));
 await assert.rejects(verifyMaterial({...session,posts:[session.posts[0],session.posts[0],session.posts[2]]}));
});
