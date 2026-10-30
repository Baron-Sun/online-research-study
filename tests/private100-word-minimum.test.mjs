import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {countWords,RESPONSE_MIN_WORDS,RESPONSE_MAX_WORDS,WORD_LENGTH_INSTRUCTION} from '../src/private100-word-minimum.mjs';
import {validComment,verifyMaterial,VERSION} from '../src/original100-protocol.mjs';
const words=n=>'NTA\n'+Array(n-1).fill('word').join(' ');

test('responses need 60 total words; 59 cannot advance, while 60, 61, 1000 and very long responses are valid',()=>{
 assert.equal(RESPONSE_MIN_WORDS,60);assert.equal(RESPONSE_MAX_WORDS,null);
 assert.ok(WORD_LENGTH_INSTRUCTION.includes('at least 60'));assert.ok(WORD_LENGTH_INSTRUCTION.includes('no maximum'));
 assert.equal(validComment(words(59)),false);
 for(const n of [60,61,1000,60001]){assert.equal(countWords(words(n)),n);assert.equal(validComment(words(n)),true);}
 assert.equal(validComment('NTA'),false);
 assert.equal(validComment('NTA because '+Array(60).fill('word').join(' ')),true);
 assert.equal(countWords('\n\t\u00a0\ufeff'),0);
 assert.equal(countWords("NTA\r\nwell-known can't"),3);
 assert.equal(countWords('NTA\none\u00a0two\u2009three'),4);
});

test('the client refuses an old maximum or a mismatched minimum from the server',async()=>{
 const seed=await readFile(new URL('../supabase_matched100v6_flow_migration.sql',import.meta.url),'utf8');
 const posts=JSON.parse(seed.split('$materials$')[1]);
 const session={version:VERSION,responseWordMinimum:60,responseWordLimit:null,wordCountVersion:'whitespace-total-v1',
  posts:posts.slice(0,3).map((p,i)=>({position:i+1,stimulusId:p.stimulus_id,prompt:p.prompt_text,sha256:p.prompt_sha256}))};
 await verifyMaterial(session);
 for(const changed of [{responseWordMinimum:59},{responseWordMinimum:61},{responseWordLimit:61},{responseWordMinimum:undefined}]){
  await assert.rejects(verifyMaterial({...session,...changed}),/length settings/);
 }
});
