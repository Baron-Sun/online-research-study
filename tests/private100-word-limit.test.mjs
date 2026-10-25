import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {countWords,RESPONSE_WORD_LIMIT,WORD_LIMIT_INSTRUCTION} from '../src/private100-word-limit.mjs';
import {validComment,verifyMaterial,VERSION} from '../src/original100-protocol.mjs';
const read=async file=>readFile(new URL('../'+file,import.meta.url),'utf8');
const hash=x=>createHash('sha256').update(x).digest('hex');

test('the limit is the rounded mean of all Study 1 human comments, with the source and denominator recorded',async()=>{
 const source=JSON.parse(await read('private100-word-limit-evidence.json'));
 assert.equal(source.source,'aita_unified_153k.parquet');
 assert.deepEqual(source.columns,['comment_1_body','comment_2_body','comment_3_body']);
 assert.equal(source.comment_count,source.post_count*3);
 assert.equal(source.comment_count,459801);
 assert.equal(source.total_words,27977852);
 assert.equal(source.mean_words,source.total_words/source.comment_count);
 assert.equal(source.word_limit,Math.round(source.mean_words));
 assert.equal(RESPONSE_WORD_LIMIT,source.word_limit);
});

test('61 words including the label are accepted; 62 are retained as invalid drafts; Unicode spaces and contractions count consistently',()=>{
 assert.equal(countWords(''),0);
 assert.equal(countWords('\n\t\u00a0\ufeff'),0);
 assert.equal(countWords("NTA\r\nwell-known can't"),3);
 assert.equal(countWords('NTA\none\u00a0two\u2009three'),4);
 const within='NTA\n'+Array(60).fill('word').join(' ');
 assert.equal(countWords(within),61);assert.ok(validComment(within));
 assert.equal(countWords(within+' extra'),62);assert.equal(validComment(within+' extra'),false);
 assert.equal(validComment('NTA'),false);
});

test('all 100 limited prompts preserve the prior bodies and plan, and a mismatched server limit fails closed',async()=>{
 const old=JSON.parse((await read('supabase_private100_migration.sql')).split('$materials$')[1]);
 const current=JSON.parse((await read('supabase_private100_wordlimit.sql')).split('$materials$')[1]);
 const manifest=JSON.parse(await read('private100-wordlimit-material-manifest.json'));
 const priorManifest=JSON.parse(await read('private100-material-manifest.json'));
 const template=(await read('private100_wordlimit_prompt_template.txt')).trimEnd();
 assert.equal(current.length,100);assert.equal(manifest.version,VERSION);
 assert.equal(manifest.assignment_sha256,priorManifest.assignment_sha256);
 assert.equal(manifest.template_sha256,hash(template));
 assert.ok(template.includes(WORD_LIMIT_INSTRUCTION));
 for(const prompt of current){
   const previous=old.find(p=>p.stimulus_id===prompt.stimulus_id);
   const body=previous.prompt_text.split('\n\nSituation:\n').slice(1).join('\n\nSituation:\n');
   assert.equal(prompt.prompt_text,template.replace('{submission_body}',body));
   assert.equal(prompt.word_limit,RESPONSE_WORD_LIMIT);
   assert.equal(prompt.previous_prompt_sha256,previous.prompt_sha256);
   assert.equal(prompt.body_sha256,hash(body));assert.equal(prompt.prompt_sha256,hash(prompt.prompt_text));
 }
 const session={version:VERSION,responseWordLimit:61,wordCountVersion:'whitespace-total-v1',posts:current.slice(0,3).map((p,i)=>({position:i+1,stimulusId:p.stimulus_id,prompt:p.prompt_text,sha256:p.prompt_sha256}))};
 await verifyMaterial(session);
 await assert.rejects(verifyMaterial({...session,responseWordLimit:62}),/length settings/);
});
