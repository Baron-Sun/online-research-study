"""Build an additive, versioned human-task migration from the reviewed source."""
from pathlib import Path
import csv, hashlib, json

root = Path(__file__).resolve().parents[1]
material = root.parent
version = 'private100-20261024-v2'
template = (root / 'private100_prompt_template.txt').read_text().rstrip('\n')
original_template = (material / 'original_prompt_template.txt').read_text()
original = {s['stimulus_id']: s for s in map(json.loads, (material / 'participant_stimuli_100.jsonl').read_text().splitlines())}
rows = list(csv.DictReader((material / 'selected_posts_100.csv').open(encoding='utf-8-sig', newline='')))
digest = lambda value: hashlib.sha256(value.encode('utf-8')).hexdigest()
posts, stimuli = [], []
for row in rows:
    source = original[row['stimulus_id']]
    assert source['prompt_text'] == original_template.replace('{submission_body}', row['body'])
    assert digest(source['prompt_text']) == source['prompt_sha256']
    prompt = template.replace('{submission_body}', row['body'])
    posts.append(dict(stimulus_id=row['stimulus_id'], prompt_text=prompt,
                      prompt_sha256=digest(prompt), body_sha256=digest(row['body']),
                      original_prompt_sha256=source['prompt_sha256']))
    stimuli.append(dict(stimulus_id=row['stimulus_id'], submission_id=row['submission_id'],
                        prompt_id='private_independent_judgment_v1', version=version,
                        prompt_text=prompt, prompt_sha256=digest(prompt), body_sha256=digest(row['body'])))
assert len(posts) == 100 and len({p['stimulus_id'] for p in posts}) == 100
assert 'You are an AI assistant' not in template and 'Reddit' not in template
(material / 'participant_stimuli_private_100.jsonl').write_text('\n'.join(json.dumps(s, ensure_ascii=False) for s in stimuli)+'\n')
plan = json.loads((root / 'original100-material-manifest.json').read_text())['plan']
(root / 'private100-material-manifest.json').write_text(json.dumps(dict(
    version=version, prompt_id='private_independent_judgment_v1',
    template_sha256=digest(template), posts=[{k:v for k,v in p.items() if k!='prompt_text'} for p in posts],
    assignment_rows=len(plan), assignment_sha256=digest(json.dumps(plan,sort_keys=True))), indent=2))

setup = (root / 'supabase_original100_setup.sql').read_text()
columns = setup[setup.index('-- Material versions are immutable;'):setup.index('alter table public.original100_settings enable')]
counter = setup[setup.index('create or replace function public.original100_word_count('):setup.index('-- All participant operations')]
rpc = setup[setup.index('create or replace function public.original100_session('):setup.index('-- Researcher-only release:')]
view = setup[setup.index('create or replace view public.original100_completed_comments as'):setup.index("notify pgrst,'reload schema';")]
payload = json.dumps(posts, ensure_ascii=False)
assert '$materials$' not in payload
seed = '''
create temporary table private100_material_import (
 stimulus_id text, prompt_text text, prompt_sha256 text, body_sha256 text, original_prompt_sha256 text
) on commit drop;
alter table private100_material_import enable row level security;
insert into private100_material_import select * from jsonb_to_recordset($materials$'''+payload+'''$materials$::jsonb)
 as x(stimulus_id text,prompt_text text,prompt_sha256 text,body_sha256 text,original_prompt_sha256 text);
do $$ begin
 if (select count(*) from private100_material_import)<>100
   or (select count(*) from public.original100_posts)<>100 then raise exception 'Expected the reviewed 100-post sample'; end if;
 if exists(select 1 from private100_material_import i left join public.original100_posts p using(stimulus_id)
   where p.stimulus_id is null or i.original_prompt_sha256<>p.prompt_sha256
   or p.prompt_sha256<>encode(extensions.digest(p.prompt_text,'sha256'),'hex')
   or i.prompt_sha256<>encode(extensions.digest(i.prompt_text,'sha256'),'hex')) then raise exception 'Material integrity mismatch'; end if;
end $$;
insert into public.original100_materials(version,stimulus_id,prompt_text,prompt_sha256,body_sha256)
 select 'original100-20261024-v1',p.stimulus_id,p.prompt_text,p.prompt_sha256,i.body_sha256
 from public.original100_posts p join private100_material_import i using(stimulus_id) on conflict do nothing;
insert into public.original100_materials(version,stimulus_id,prompt_text,prompt_sha256,body_sha256)
 select 'private100-20261024-v2',stimulus_id,prompt_text,prompt_sha256,body_sha256
 from private100_material_import on conflict do nothing;
do $$ begin
 if (select count(*) from public.original100_materials where version='private100-20261024-v2')<>100
   or (select count(*) from public.original100_materials where version='original100-20261024-v1')<>100
   then raise exception 'Material version incomplete'; end if;
 if exists(select 1 from public.original100_materials m join private100_material_import i using(stimulus_id)
   where m.body_sha256<>i.body_sha256 or
     (m.version='private100-20261024-v2' and m.prompt_sha256<>i.prompt_sha256) or
     (m.version='original100-20261024-v1' and m.prompt_sha256<>i.original_prompt_sha256))
   then raise exception 'Existing material versions are immutable'; end if;
 if (select count(*) from public.original100_plan)<>300
   or exists(select stimulus_id from public.original100_plan group by stimulus_id having count(*)<>3 or count(distinct slot_id)<>3)
   then raise exception 'Allocation changed'; end if;
end $$;
update public.original100_settings set version='private100-20261024-v2',
 consent_version='private100-preview-v2',consent_approved=false where id;
'''
preflight = '''-- Additive private-response condition. Original texts and earlier sessions are retained.
begin;
do $$ begin
 if (select recruitment_open from public.original100_settings where id)
   or exists(select 1 from public.original100_participants where mode='formal')
   then raise exception 'Apply this preview migration before formal recruitment'; end if;
end $$;
'''
suffix = '''
notify pgrst,'reload schema';
commit;
select version,recruitment_open,(select count(*) from public.original100_materials where version='private100-20261024-v2') as private_prompts,
 (select count(*) from public.original100_materials where version='original100-20261024-v1') as retained_original_prompts,
 (select count(*) from public.original100_plan) as assignments from public.original100_settings where id;
'''
(root / 'supabase_private100_migration.sql').write_text(preflight+columns+seed+counter+rpc+view+suffix)
print('Prepared 100 private-task prompts; all bodies and 300 assignment rows unchanged; Original texts retained.')
