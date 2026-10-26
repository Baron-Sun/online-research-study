"""Prepare the reviewed Study 1 matched cohort in an isolated database namespace.

Archive all earlier cohorts unchanged. This generator reads only validated local
materials and writes SQL/source artifacts; it never contacts Prolific or Supabase.
Study ID and completion code are configured privately after deployment.
"""
from pathlib import Path
import hashlib
import json
import pandas as pd

ROOT=Path(__file__).resolve().parents[1]
PACKAGE=ROOT.parent.parent/'prolific_study1matched_100_20261025'
VERSION='private100-study1matched-20261026-v4'
hash_text=lambda value:hashlib.sha256(value.encode()).hexdigest()
validation=json.loads((PACKAGE/'validation.json').read_text())
assert validation['all_600_historical_texts_match_study1']
for name,digest in validation['files_sha256'].items():
    assert hashlib.sha256((PACKAGE/name).read_bytes()).hexdigest()==digest,name
source=[json.loads(line) for line in (PACKAGE/'participant_stimuli_private_wordlimit_100.jsonl').read_text().splitlines()]
assert len(source)==100 and len({p['submission_id'] for p in source})==100
template=(ROOT/'private100_wordlimit_prompt_template.txt').read_text().rstrip('\n')
assert template==(PACKAGE/'private100_wordlimit_prompt_template.txt').read_text().rstrip('\n')
posts=[]
for p in source:
    assert p['word_limit']==61 and hash_text(p['prompt_text'])==p['prompt_sha256']
    body=p['prompt_text'].split('\n\nSituation:\n',1)[1]
    assert hash_text(body)==p['body_sha256']
    assert template.replace('{submission_body}',body)==p['prompt_text']
    posts.append({k:p[k] for k in ['stimulus_id','submission_id','prompt_text','prompt_sha256','body_sha256','word_limit']})
long=pd.read_csv(PACKAGE/'assignments_long_300.csv')
plan=[dict(slot_id=r.participant_slot,position=int(r.position),stimulus_id=r.stimulus_id) for r in long.itertuples()]
assert len(plan)==300 and long.groupby('stimulus_id').participant_slot.nunique().eq(3).all()
assert long.groupby('participant_slot').stimulus_id.nunique().eq(3).all()
setup=(ROOT/'supabase_original100_setup.sql').read_text().replace('original100','matched100')
setup=setup.replace("default 'matched100-20261024-v1'",f"default '{VERSION}'")
setup=setup.replace("default 'matched100-preview-v1'","default 'private100-study1matched-v4'")
setup=setup.replace('private100-wordlimit-20261024-v3',VERSION).replace('10020261024','10020261026')
setup=setup.replace('-- Isolated Original-prompt study. No existing study tables or functions are changed.',
    '-- Isolated Study 1 matched cohort. Earlier original100_* and other studies remain unchanged.')
assert 'original100_' not in setup[setup.index('begin;'):]
(ROOT/'supabase_matched100_setup.sql').write_text(setup)
post_json=json.dumps(posts,ensure_ascii=False)
plan_json=json.dumps(plan,ensure_ascii=False)
assert '$materials$' not in post_json and '$plan$' not in plan_json
seed='''-- Validated matched 100-post cohort. Seed only before recruitment.
begin;
do $$ begin
 if (select recruitment_open from public.matched100_settings where id)
    or exists(select 1 from public.matched100_participants where mode='formal')
 then raise exception 'Seed only before formal recruitment'; end if;
end $$;
create temporary table matched100_import(stimulus_id text,submission_id text,prompt_text text,prompt_sha256 text,body_sha256 text,word_limit integer) on commit drop;
alter table matched100_import enable row level security;
insert into matched100_import select * from jsonb_to_recordset($materials$'''+post_json+'''$materials$::jsonb)
 as x(stimulus_id text,submission_id text,prompt_text text,prompt_sha256 text,body_sha256 text,word_limit integer);
create temporary table matched100_plan_import(slot_id text,position integer,stimulus_id text) on commit drop;
alter table matched100_plan_import enable row level security;
insert into matched100_plan_import select * from jsonb_to_recordset($plan$'''+plan_json+'''$plan$::jsonb)
 as x(slot_id text,position integer,stimulus_id text);
do $$ begin
 if (select count(*) from matched100_import)<>100 or (select count(distinct submission_id) from matched100_import)<>100
   or (select count(*) from matched100_plan_import)<>300 then raise exception 'Material count mismatch'; end if;
 if exists(select 1 from matched100_import where word_limit<>61 or prompt_sha256<>encode(extensions.digest(prompt_text,'sha256'),'hex'))
   then raise exception 'Invalid material digest or word limit'; end if;
 if exists(select slot_id from matched100_plan_import group by slot_id having count(distinct stimulus_id)<>3)
   or exists(select stimulus_id from matched100_plan_import group by stimulus_id having count(distinct slot_id)<>3)
   or exists(select stimulus_id,position from matched100_plan_import group by stimulus_id,position having count(*)<>1)
 then raise exception 'Assignment is not balanced'; end if;
end $$;
insert into public.matched100_posts select stimulus_id,submission_id,prompt_text,prompt_sha256 from matched100_import on conflict do nothing;
insert into public.matched100_slots select distinct slot_id from matched100_plan_import on conflict do nothing;
insert into public.matched100_plan select * from matched100_plan_import on conflict do nothing;
insert into public.matched100_materials(version,stimulus_id,prompt_text,prompt_sha256,body_sha256,word_limit)
 select '''+f"'{VERSION}'"+''',stimulus_id,prompt_text,prompt_sha256,body_sha256,word_limit from matched100_import on conflict do nothing;
do $$ begin
 if (select count(*) from public.matched100_posts)<>100 or (select count(*) from public.matched100_slots)<>100
   or (select count(*) from public.matched100_plan)<>300 or (select count(*) from public.matched100_materials)<>100
 then raise exception 'Unexpected existing cohort'; end if;
 if exists(select 1 from matched100_import i join public.matched100_posts p using(stimulus_id)
   where i.submission_id<>p.submission_id or i.prompt_text<>p.prompt_text or i.prompt_sha256<>p.prompt_sha256)
   or exists(select 1 from matched100_import i join public.matched100_materials m using(stimulus_id)
   where i.prompt_text<>m.prompt_text or i.prompt_sha256<>m.prompt_sha256 or i.body_sha256<>m.body_sha256 or i.word_limit is distinct from m.word_limit)
 then raise exception 'Existing material differs; cohorts are immutable'; end if;
 if exists(select 1 from matched100_plan_import i left join public.matched100_plan p using(slot_id,position,stimulus_id) where p.slot_id is null)
 then raise exception 'Existing assignment differs'; end if;
end $$;
update public.matched100_settings set version='''+f"'{VERSION}'"+''',consent_version='private100-study1matched-v4' where id;
commit;
select version,recruitment_open,(select count(*) from public.matched100_posts) as posts,
 (select count(*) from public.matched100_plan) as assignment_rows from public.matched100_settings where id;
'''
(ROOT/'supabase_matched100_seed.sql').write_text(seed)
manifest=dict(version=VERSION,source_candidate_version=source[0]['version'],database_namespace='matched100',
    source_package='prolific_study1matched_100_20261025',selection_spec_sha256=validation['files_sha256']['selection_spec.json'],
    selection_method='Historically matched stimulus set, not a probability sample or independent replication.',
    template_sha256=hash_text(template),word_limit=61,posts=[{k:v for k,v in p.items() if k!='prompt_text'} for p in posts],plan=plan)
(ROOT/'matched100-material-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
rehearsal=(ROOT/'tests/original100-rehearsal.sql').read_text().replace('original100','matched100')
rehearsal=rehearsal.replace('private100-wordlimit-20261024-v3',VERSION)
start=rehearsal.index(" update public.matched100_settings set version='matched100-20261024-v1'")
end=rehearsal.index(' update public.matched100_settings set recruitment_open=true',start)
rehearsal=rehearsal[:start]+rehearsal[end:]
rehearsal=rehearsal.replace("if item->>'status'<>'completed' then", "if item->>'completionCode'<>'QA_ROLLBACK' then raise exception 'Completion code was not returned'; end if;\n   if item->>'status'<>'completed' then")
rehearsal=rehearsal.replace('legacy preservation, ','')
(ROOT/'tests/matched100-rehearsal.sql').write_text(rehearsal)
live=(ROOT/'tests/original100-live.mjs').read_text().replace('qa-original100-','qa-matched100-').replace("'original100-preview'","'matched100-preview'")
live=live.replace("['original100_participants','original100_responses','original100_completed_comments','original100_materials']", "['matched100_participants','matched100_responses','matched100_completed_comments','matched100_materials']")
live=live.replace('../verification/live-api.json','../verification/matched100-live-api.json')
(ROOT/'tests/matched100-live.mjs').write_text(live)
print(f'Prepared {len(posts)} immutable prompts and {len(plan)} assignments in matched100; version {VERSION}.')
