"""Version the limited prompt and build an additive database migration."""
from pathlib import Path
import hashlib
import json

ROOT = Path(__file__).resolve().parents[1]
VERSION = 'private100-wordlimit-20261024-v3'
digest = lambda value: hashlib.sha256(value.encode()).hexdigest()
evidence = json.loads((ROOT/'private100-word-limit-evidence.json').read_text())
limit = evidence['word_limit']
assert limit == 61 and evidence['comment_count'] == 459801
instruction = f'Write no more than {limit} words in total, including the judgment label. You do not need to use the full word allowance.'
old_template = (ROOT/'private100_prompt_template.txt').read_text().rstrip('\n')
template = old_template.replace('\n\nJudgment labels:', '\n\n'+instruction+'\n\nJudgment labels:')
(ROOT/'private100_wordlimit_prompt_template.txt').write_text(template+'\n')
old_prompts = json.loads((ROOT/'supabase_private100_migration.sql').read_text().split('$materials$')[1])
old_manifest = json.loads((ROOT/'private100-material-manifest.json').read_text())
new_prompts = []
for old in old_prompts:
    old_prefix = old_template.split('{submission_body}')[0]
    assert old['prompt_text'].startswith(old_prefix)
    body = old['prompt_text'][len(old_prefix):]
    assert digest(body) == old['body_sha256']
    text = template.replace('{submission_body}',body)
    new_prompts.append(dict(stimulus_id=old['stimulus_id'], prompt_text=text,
        prompt_sha256=digest(text), body_sha256=old['body_sha256'],
        previous_prompt_sha256=old['prompt_sha256'], word_limit=limit))
assert len(new_prompts) == 100
manifest = dict(version=VERSION, prompt_id='private_independent_judgment_wordlimit_v1',
    word_limit=limit, word_count_version=evidence['count_version'],
    template_sha256=digest(template), source_evidence_sha256=digest((ROOT/'private100-word-limit-evidence.json').read_text()),
    assignment_rows=old_manifest['assignment_rows'], assignment_sha256=old_manifest['assignment_sha256'],
    posts=[{k:v for k,v in p.items() if k!='prompt_text'} for p in new_prompts])
(ROOT/'private100-wordlimit-material-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
old_stimuli = {p['stimulus_id']:p for p in map(json.loads,(ROOT.parent/'participant_stimuli_private_100.jsonl').read_text().splitlines())}
with (ROOT.parent/'participant_stimuli_private_wordlimit_100.jsonl').open('w') as stream:
    for prompt in new_prompts:
        output = dict(prompt, submission_id=old_stimuli[prompt['stimulus_id']]['submission_id'],
                      version=VERSION, prompt_id=manifest['prompt_id'], word_count_version=evidence['count_version'])
        stream.write(json.dumps(output,ensure_ascii=False)+'\n')
setup = (ROOT/'supabase_original100_setup.sql').read_text()
counter = setup[setup.index('create or replace function public.original100_word_count('):setup.index('-- All participant operations')]
rpc = setup[setup.index('create or replace function public.original100_session('):setup.index('-- Researcher-only release:')]
view = setup[setup.index('create or replace view public.original100_completed_comments as'):setup.index("notify pgrst,'reload schema';")]
payload = json.dumps(new_prompts,ensure_ascii=False)
assert '$materials$' not in payload
sql = '''-- Add 61-word maximum from the full Study 1 human baseline. Preserve all earlier sessions.
begin;
do $$ begin
 if (select recruitment_open from public.original100_settings where id)
   or exists(select 1 from public.original100_participants where mode='formal') then raise exception 'Apply before formal recruitment'; end if;
end $$;
alter table public.original100_materials add column if not exists word_limit integer check(word_limit>0);
create temporary table private100_limit_import (
 stimulus_id text, prompt_text text, prompt_sha256 text, body_sha256 text, previous_prompt_sha256 text, word_limit integer
) on commit drop;
alter table private100_limit_import enable row level security;
insert into private100_limit_import select * from jsonb_to_recordset($materials$'''+payload+'''$materials$::jsonb)
 as x(stimulus_id text,prompt_text text,prompt_sha256 text,body_sha256 text,previous_prompt_sha256 text,word_limit integer);
do $$ begin
 if (select count(*) from private100_limit_import)<>100 then raise exception 'Incomplete material'; end if;
 if exists(select 1 from private100_limit_import i left join public.original100_materials m on m.stimulus_id=i.stimulus_id and m.version='private100-20261024-v2'
   where m.stimulus_id is null or m.prompt_sha256<>i.previous_prompt_sha256 or m.body_sha256<>i.body_sha256
   or i.word_limit<>61 or i.prompt_sha256<>encode(extensions.digest(i.prompt_text,'sha256'),'hex')) then raise exception 'Source material or word limit mismatch'; end if;
end $$;
insert into public.original100_materials(version,stimulus_id,prompt_text,prompt_sha256,body_sha256,word_limit)
 select 'private100-wordlimit-20261024-v3',stimulus_id,prompt_text,prompt_sha256,body_sha256,word_limit from private100_limit_import on conflict do nothing;
do $$ begin
 if (select count(*) from public.original100_materials where version='private100-wordlimit-20261024-v3')<>100 then raise exception 'Incomplete material version'; end if;
 if exists(select 1 from private100_limit_import i join public.original100_materials m on m.stimulus_id=i.stimulus_id and m.version='private100-wordlimit-20261024-v3'
   where m.prompt_sha256<>i.prompt_sha256 or m.body_sha256<>i.body_sha256 or m.word_limit is distinct from i.word_limit) then raise exception 'Existing material versions are immutable'; end if;
end $$;
update public.original100_settings set version='private100-wordlimit-20261024-v3',consent_version='private100-wordlimit-preview-v3',consent_approved=false where id;
'''+counter+rpc+view+'''
notify pgrst,'reload schema';
commit;
select version,recruitment_open,(select count(*) from public.original100_materials where version='private100-wordlimit-20261024-v3' and word_limit=61) as limited_prompts,
 (select count(*) from public.original100_plan) as assignment_rows from public.original100_settings where id;
'''
(ROOT/'supabase_private100_wordlimit.sql').write_text(sql)
print(f'Built {len(new_prompts)} versioned prompts with a {limit}-word maximum; all bodies and assignments retained.')
