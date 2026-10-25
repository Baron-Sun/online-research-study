import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const hash=x=>createHash('sha256').update(x).digest('hex');
test('private prompts replace the role framing while preserving every original body and assignment',async()=>{
 const oldSeed=await readFile(new URL('../supabase_original100_seed.sql',import.meta.url),'utf8');
 const migration=await readFile(new URL('../supabase_private100_migration.sql',import.meta.url),'utf8');
 const originals=JSON.parse(oldSeed.split('$materials$')[1]);
 const prompts=JSON.parse(migration.split('$materials$')[1]);
 const template=(await readFile(new URL('../private100_prompt_template.txt',import.meta.url),'utf8')).replace(/\n$/,'');
 const manifest=JSON.parse(await readFile(new URL('../private100-material-manifest.json',import.meta.url),'utf8'));
 assert.equal(manifest.version,'private100-20261024-v2');assert.equal(prompts.length,100);
 assert.equal(manifest.assignment_rows,300);assert.equal(manifest.template_sha256,hash(template));
 assert.equal(template.includes('AI assistant'),false);assert.equal(template.includes('Reddit'),false);
 for(const old of originals){
  const prompt=prompts.find(p=>p.stimulus_id===old.stimulus_id);
  const body=old.prompt_text.slice(old.prompt_text.indexOf('Submissions content here:\n\n')+'Submissions content here:\n\n'.length);
  assert.equal(prompt.prompt_text,template.replace('{submission_body}',body));
  assert.equal(prompt.body_sha256,hash(body));assert.equal(prompt.original_prompt_sha256,old.prompt_sha256);
  assert.equal(prompt.prompt_sha256,hash(prompt.prompt_text));
 }
 const plan=JSON.parse(await readFile(new URL('../original100-material-manifest.json',import.meta.url),'utf8')).plan;
 const canonical=JSON.stringify(plan.map(p=>Object.fromEntries(Object.entries(p).sort())),null,0).replaceAll(':',': ').replaceAll(',',', ');
 assert.equal(manifest.assignment_sha256,hash(canonical));
 assert.equal(new Set(plan.map(p=>p.slot_id)).size,100);
});
