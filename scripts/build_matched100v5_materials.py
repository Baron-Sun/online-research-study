"""Build the min-60/no-maximum, no-EDIT cohort without changing prior records."""
from pathlib import Path
from hashlib import sha256
import json
import re
import pandas as pd

ROOT=Path(__file__).resolve().parents[1]
PACKAGE=ROOT.parent.parent/'prolific_min60_noedit_100_20261026'
VERSION='private100-study1matched-min60-20261026-v5'
PRIOR_VERSION='private100-study1matched-20261026-v4'
NS='matched100v5'
validation=json.loads((PACKAGE/'validation.json').read_text())
assert validation['all_600_historical_texts_match_study1'] and validation['edit_update_tokens']==0
for name,digest in validation['files_sha256'].items():
    assert sha256((PACKAGE/name).read_bytes()).hexdigest()==digest,name
source=[json.loads(x) for x in (PACKAGE/'participant_stimuli_min60_100.jsonl').read_text().splitlines()]
template=(PACKAGE/'private100_min60_prompt_template.txt').read_text().rstrip('\n')
(ROOT/'private100_min60_prompt_template.txt').write_text(template+'\n')
posts=[]
for p in source:
    assert p['version']==VERSION and p['word_minimum']==60 and p['word_limit'] is None
    body=p['prompt_text'].split('\n\nSituation:\n',1)[1]
    assert template.replace('{submission_body}',body)==p['prompt_text']
    assert sha256(body.encode()).hexdigest()==p['body_sha256']
    assert sha256(p['prompt_text'].encode()).hexdigest()==p['prompt_sha256']
    assert not re.search(r'\b(?:edit(?:s|ed|[0-9]+)?|update(?:s|d|[0-9]+)?)\b',body,re.I)
    posts.append({k:p[k] for k in ['stimulus_id','submission_id','prompt_text','prompt_sha256','body_sha256','word_minimum','word_limit']})
long=pd.read_csv(PACKAGE/'assignments_long_300.csv')
plan=[dict(slot_id=r.participant_slot,position=int(r.position),stimulus_id=r.stimulus_id) for r in long.itertuples()]
setup=(ROOT/'supabase_matched100_setup.sql').read_text().replace('matched100',NS).replace(PRIOR_VERSION,VERSION)
setup=setup.replace('private100-study1matched-v4','private100-study1matched-min60-v5').replace('10020261026','510020261026')
setup=setup.replace("answer text not null default '' check(octet_length(answer)<=250000)","answer text not null default ''")
setup=setup.replace(' or octet_length(answer_text)>250000','')
setup=setup.replace('add column if not exists word_limit integer check(word_limit>0);',
    'add column if not exists word_limit integer check(word_limit is null);\nalter table public.matched100v5_materials add column if not exists word_minimum integer not null default 60 check(word_minimum=60);')
setup=setup.replace('answer_word_limit','answer_word_minimum')
setup=setup.replace('select max(word_limit) into answer_word_minimum','select min(word_minimum) into answer_word_minimum')
setup=setup.replace('_word_count(answer)>answer_word_minimum','_word_count(answer)<answer_word_minimum')
setup=setup.replace('Each response must be % words or fewer, including the judgment label. Your draft is saved; please shorten it before',
    'Each response must contain at least % words, including the judgment label. Your draft is saved; please add more detail before')
setup=setup.replace("'responseWordLimit',answer_word_minimum", "'responseWordMinimum',answer_word_minimum,'responseWordLimit',null")
setup=setup.replace('m.word_limit as response_word_limit,', 'm.word_minimum as response_word_minimum,m.word_limit as response_word_limit,')
setup=setup.replace('Please start a new preview for the updated task.', 'Please reopen the current study link for the updated task.')
setup=setup.replace('Unknown preview slot.', 'Unknown assignment.')
assert '250000' not in setup and 'words or fewer' not in setup and PRIOR_VERSION not in setup
(ROOT/'supabase_matched100v5_setup.sql').write_text(setup)
seed=(ROOT/'supabase_matched100_seed.sql').read_text().replace('matched100',NS).replace(PRIOR_VERSION,VERSION)
seed=seed.replace('private100-study1matched-v4','private100-study1matched-min60-v5')
parts=seed.split('$materials$');assert len(parts)==3
seed=parts[0]+'$materials$'+json.dumps(posts,ensure_ascii=False)+'$materials$'+parts[2]
parts=seed.split('$plan$');assert len(parts)==3
seed=parts[0]+'$plan$'+json.dumps(plan,ensure_ascii=False)+'$plan$'+parts[2]
seed=seed.replace('body_sha256 text,word_limit integer','body_sha256 text,word_minimum integer,word_limit integer')
seed=seed.replace('where word_limit<>61 or', 'where word_minimum<>60 or word_limit is not null or')
seed=seed.replace('body_sha256,word_limit)', 'body_sha256,word_minimum,word_limit)')
seed=seed.replace('body_sha256,word_limit from', 'body_sha256,word_minimum,word_limit from')
seed=seed.replace('or i.word_limit is distinct from m.word_limit', 'or i.word_minimum is distinct from m.word_minimum or i.word_limit is distinct from m.word_limit')
assert 'word_limit<>61' not in seed and '"word_limit": 61' not in seed
(ROOT/'supabase_matched100v5_seed.sql').write_text(seed)
manifest=dict(version=VERSION,database_namespace=NS,source_package=PACKAGE.name,
    selection_spec_sha256=validation['files_sha256']['selection_spec.json'],
    selection_method='Historical matching with all 80 unaffected posts fixed and 20 same-stratum replacements; no new participant outcomes used.',
    retained_posts=80,replaced_posts=20,edit_update_tokens=0,word_minimum=60,word_limit=None,
    template_sha256=sha256(template.encode()).hexdigest(),posts=[{k:v for k,v in p.items() if k!='prompt_text'} for p in posts],plan=plan)
(ROOT/'matched100v5-material-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
# Preserve the complete allocator rehearsal and give every completed synthetic
# response enough words. The dedicated boundary probe below tests short drafts.
rehearsal=(ROOT/'tests/matched100-rehearsal.sql').read_text().replace('matched100',NS)
rehearsal=rehearsal.replace("if item->>'responseWordLimit'<>'61'", "if item->>'responseWordMinimum'<>'60' or item->'responseWordLimit'<>'null'::jsonb")
rehearsal=rehearsal.replace("||j||'.'", "||j||'. '||repeat('synthetic ',60)")
rehearsal=rehearsal.replace("E'INFO\\nSYNTHETIC REPLACEMENT REHEARSAL ONLY.'", "E'INFO\\nSYNTHETIC REPLACEMENT REHEARSAL ONLY. '||repeat('synthetic ',60)")
rehearsal=rehearsal.replace('61-word setting','minimum 60 words with no maximum')
marker="select 'PASS:"
boundary="""do $$
declare item jsonb; blocked boolean; n integer; answer_text text;
begin
 item:=public.matched100v5_session('claim','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,'{"consent":true}');
 perform public.matched100v5_session('comprehension_check','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,jsonb_build_object('event_id',gen_random_uuid()::text,'choice','judgment_reasons','version','task-comprehension-v1'));
 answer_text:=E'INFO\\n'||repeat('word ',58);
 if public.matched100v5_word_count(answer_text)<>59 then raise exception 'Wrong short fixture'; end if;
 perform public.matched100v5_session('save','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,jsonb_build_object('position',1,'revision',0,'answer',answer_text));
 item:=public.matched100v5_session('resume','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,'{}');
 if item->'posts'->0->>'answer'<>answer_text then raise exception 'Short draft lost'; end if;
 blocked:=false;
 begin perform public.matched100v5_session('navigate','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,'{"position":2}'); exception when others then if sqlerrm not like '%at least 60%' then raise; end if; blocked:=true; end;
 if not blocked then raise exception 'Short response advanced'; end if;
 for n in 2..3 loop
  perform public.matched100v5_session('save','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,jsonb_build_object('position',n,'revision',0,'answer',E'INFO\\n'||repeat('word ',59)));
 end loop;
 blocked:=false;
 begin perform public.matched100v5_session('complete','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,'{"revisions":[1,1,1]}'); exception when others then if sqlerrm not like '%at least 60%' then raise; end if; blocked:=true; end;
 if not blocked then raise exception 'Short response submitted'; end if;
 perform public.matched100v5_session('save','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,jsonb_build_object('position',1,'revision',1,'answer',E'INFO\\n'||repeat('word ',59)));
 item:=public.matched100v5_session('navigate','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,'{"position":2}');
 if item->>'position'<>'2' then raise exception 'Exactly 60 rejected'; end if;
 -- More than 61 words and more than the former 250k-byte application guard.
 perform public.matched100v5_session('save','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,jsonb_build_object('position',2,'revision',1,'answer',E'INFO\\n'||repeat('word ',60000)));
 item:=public.matched100v5_session('complete','qa-sql-word-boundaries','qa-study','qa-session',repeat('c',64),true,'{"revisions":[2,2,1]}');
 if item->>'status'<>'completed' then raise exception 'Long response rejected'; end if;
end $$;
"""
rehearsal=rehearsal.replace(marker,boundary+marker)
(ROOT/'tests/matched100v5-rehearsal.sql').write_text(rehearsal)
print('Prepared v5 schema, 100 exact prompts, 300 allocations, manifest and rollback rehearsal.')
