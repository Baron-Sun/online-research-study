import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {countWords,RESPONSE_WORD_LIMIT,WORD_LIMIT_INSTRUCTION} from '../src/private100-word-limit.mjs';
const read=async file=>readFile(new URL('../'+file,import.meta.url),'utf8');
const hash=x=>createHash('sha256').update(x).digest('hex');

test('the archived v3 limit is the rounded mean of all Study 1 human comments, with the source and denominator recorded',async()=>{
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

test('archived v3 limited prompts preserve their prior bodies and plan',async()=>{
 const old=JSON.parse((await read('supabase_private100_migration.sql')).split('$materials$')[1]);
 const current=JSON.parse((await read('supabase_private100_wordlimit.sql')).split('$materials$')[1]);
 const manifest=JSON.parse(await read('private100-wordlimit-material-manifest.json'));
 const priorManifest=JSON.parse(await read('private100-material-manifest.json'));
 const template=(await read('private100_wordlimit_prompt_template.txt')).trimEnd();
 assert.equal(current.length,100);assert.equal(manifest.version,'private100-wordlimit-20261024-v3');
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
});
