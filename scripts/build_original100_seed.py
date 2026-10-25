from pathlib import Path
import json,csv,hashlib
root=Path(__file__).resolve().parents[1]
material=root.parent
rows=list(csv.DictReader((material/'selected_posts_100.csv').open(encoding='utf-8-sig')))
stimuli=[json.loads(s) for s in (material/'participant_stimuli_100.jsonl').read_text().splitlines()]
ids={r['stimulus_id']:r['submission_id'] for r in rows}
posts=[]
for s in stimuli:
 assert hashlib.sha256(s['prompt_text'].encode()).hexdigest()==s['prompt_sha256']
 posts.append(dict(stimulus_id=s['stimulus_id'], submission_id=ids[s['stimulus_id']],prompt_text=s['prompt_text'],prompt_sha256=s['prompt_sha256']))
plan=[dict(slot_id=r['participant_slot'],position=int(r['position']),stimulus_id=r['stimulus_id']) for r in csv.DictReader((material/'assignments_long_300.csv').open(encoding='utf-8-sig'))]
assert len(posts)==100 and len(plan)==300
for p in posts: assert sum(x['stimulus_id']==p['stimulus_id'] for x in plan)==3
for slot in {x['slot_id'] for x in plan}: assert len({x['stimulus_id'] for x in plan if x['slot_id']==slot})==3
pjson=json.dumps(posts,ensure_ascii=False); ajson=json.dumps(plan)
assert '$materials$' not in pjson
sql='''-- Immutable sample and fixed assignment table, generated from the reviewed CSV/JSONL.
begin;
insert into public.original100_posts select * from jsonb_to_recordset($materials$'''+pjson+'''$materials$::jsonb)
 as x(stimulus_id text,submission_id text,prompt_text text,prompt_sha256 text) on conflict do nothing;
insert into public.original100_slots select 'S'||lpad(n::text,3,'0') from generate_series(1,100) n on conflict do nothing;
insert into public.original100_plan select * from jsonb_to_recordset($materials$'''+ajson+'''$materials$::jsonb)
 as x(slot_id text,position integer,stimulus_id text) on conflict do nothing;
do $$ begin
 if (select count(*) from public.original100_posts)<>100 or (select count(*) from public.original100_plan)<>300 then raise exception 'Wrong material counts'; end if;
 if exists(select 1 from public.original100_posts where prompt_sha256<>encode(extensions.digest(prompt_text,'sha256'),'hex')) then raise exception 'Prompt hash mismatch'; end if;
 if exists(select stimulus_id from public.original100_plan group by stimulus_id having count(*)<>3 or count(distinct slot_id)<>3 or count(distinct position)<>3) then raise exception 'Post allocation mismatch'; end if;
 if exists(select slot_id from public.original100_plan group by slot_id having count(distinct stimulus_id)<>3) then raise exception 'Participant allocation mismatch'; end if;
end $$;
commit;
select (select count(*) from public.original100_posts) as posts,(select count(*) from public.original100_slots) as participant_slots,(select count(*) from public.original100_plan) as assignments,(select recruitment_open from public.original100_settings where id) as recruitment_open;
'''
(root/'supabase_original100_seed.sql').write_text(sql)
(root/'original100-material-manifest.json').write_text(json.dumps({'version':'original100-20261024-v1','posts':[{k:v for k,v in p.items() if k!='prompt_text'} for p in posts],'plan':plan},indent=2))
print(f'Generated {len(posts)} exact prompts, {len(plan)} fixed assignments; seed {len(sql.encode())} bytes')
