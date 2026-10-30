"""Version the existing 100 posts for the opinion + demographic survey flow."""
from pathlib import Path
from hashlib import sha256, md5
import json, re

ROOT = Path(__file__).resolve().parents[1]
OLD = 'private100-study1matched-min60-20261026-v5'
NEW = 'private100-study1matched-opinion-demographics-20261030-v6'
setup = (ROOT/'supabase_matched100v5_setup.sql').read_text()
match = re.search(r'create or replace function public\.matched100v5_session\([\s\S]*?as \$\$([\s\S]*?)\$\$;', setup)
old_body = match[1]
body = old_body

def edit(old, new, count=1):
    global body
    assert body.count(old) == count, (old, body.count(old))
    body = body.replace(old, new)

edit('check_event text; check_choice text; previous_check jsonb;', 'check_event text; check_choice text; previous_check jsonb; demographic_payload jsonb;')
edit("'claim','resume','save','navigate','complete','withdraw','attention_check','comprehension_check'", "'claim','resume','save','save_demographics','navigate','complete','withdraw','attention_check','comprehension_check'")
edit("('save','navigate','withdraw')", "('save','save_demographics','navigate','withdraw')")
edit("('save','navigate','complete')", "('save','save_demographics','navigate','complete')")
edit("'"+OLD+"')", "'"+OLD+"','"+NEW+"')", 2)
edit(" elsif p_action='navigate' then", """ elsif p_action='save_demographics' then
   demographic_payload:=p_payload->'demographics';
   if not public.matched100v5_valid_demographics(demographic_payload,false) then raise exception 'Please check your demographic responses.'; end if;
   if exists(select 1 from public.matched100v5_responses where participant_id=person.id
     and public.matched100v5_word_count(answer)<answer_word_minimum) then raise exception 'Please finish all three responses before the demographic questions.'; end if;
   if person.demographics_revision is distinct from (p_payload->>'revision')::integer
     and person.demographics<>demographic_payload then raise exception 'Newer demographic answers were saved in another tab. Reload before editing.'; end if;
   if person.demographics<>demographic_payload then
     update public.matched100v5_participants set demographics=demographic_payload,
       demographics_revision=demographics_revision+1,updated_at=now() where id=person.id;
   end if;
 elsif p_action='navigate' then""")
edit('pos not between 1 and 4', 'pos not between 1 and 5')
edit('set current_position=pos,updated_at=now()', 'set current_position=pos,demographics_opened_at=case when pos=5 then coalesce(demographics_opened_at,now()) else demographics_opened_at end,updated_at=now()')
edit("   update public.matched100v5_participants set status='completed',completed_at=now(),updated_at=now(),current_position=4 where id=person.id;", """   if person.material_version='"""+NEW+"""' then
     if not public.matched100v5_valid_demographics(person.demographics,true) then raise exception 'Please complete all five demographic questions before submitting.'; end if;
     if person.demographics_revision is distinct from (p_payload->>'demographicsRevision')::integer then raise exception 'Your demographic answers changed in another tab. Reload and review them before submitting.'; end if;
   end if;
   update public.matched100v5_participants set status='completed',completed_at=now(),updated_at=now(),current_position=5,
     demographics_completed_at=case when public.matched100v5_valid_demographics(demographics,true) then now() else null end where id=person.id;""")
edit("   'responseWordMinimum',answer_word_minimum", "   'demographics',p.demographics,'demographicsRevision',p.demographics_revision,\n   'demographicsOpenedAt',p.demographics_opened_at,'demographicsCompletedAt',p.demographics_completed_at,\n   'responseWordMinimum',answer_word_minimum")
function = match[0].replace(old_body,body)

old_template=(ROOT/'private100_min60_prompt_template.txt').read_text().rstrip('\n')
old_format='Please use this response format:\n1. Write exactly one of the labels below on the first line.\n2. On the next line, explain your reasoning.\n3. Do not add any text before the label.'
assert old_format in old_template
template=old_template.replace(old_format,'Begin with YTA, NTA, ESH, NAH, or INFO, then write your opinion and explain your reasoning. Judgment labels may be uppercase or lowercase.')
(ROOT/'private100_opinion_prompt_template.txt').write_text(template+'\n')
posts=json.loads((ROOT/'supabase_matched100v5_seed.sql').read_text().split('$materials$')[1])
for post in posts:
    original=post['prompt_text']
    assert sha256(original.encode()).hexdigest()==post['prompt_sha256']
    body_text=original.split('\n\nSituation:\n',1)[1]
    assert sha256(body_text.encode()).hexdigest()==post['body_sha256']
    assert old_template.replace('{submission_body}',body_text)==original
    post['prompt_text']=template.replace('{submission_body}',body_text)
    post['prompt_sha256']=sha256(post['prompt_text'].encode()).hexdigest()
manifest=json.loads((ROOT/'matched100v5-material-manifest.json').read_text())
manifest.update(version=NEW,previous_version=OLD,template_sha256=sha256(template.encode()).hexdigest(),
 response_format_validation='word minimum only',demographics_version='advice-transfer-v4-five-fields',
 posts=[{k:v for k,v in p.items() if k!='prompt_text'} for p in posts])
(ROOT/'matched100v6-material-manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')

schema="""-- Additive survey flow update. No formal participants may exist at activation.
-- Existing preview responses, earlier material versions and the 300-row plan are retained.
begin;
select pg_advisory_xact_lock(510020261026);
do $$ begin
 if exists(select 1 from public.matched100v5_participants where mode='formal') then
  raise exception 'Formal participants already exist; preserve their flow before applying this migration.';
 end if;
 if (select md5(prosrc) from pg_proc where oid='public.matched100v5_session(text,text,text,text,text,boolean,jsonb)'::regprocedure)
   not in ('OLD_MD5','NEW_MD5') then raise exception 'The live session function changed; review it before migration.'; end if;
end $$;
update public.matched100v5_settings set recruitment_open=false where id;
alter table public.matched100v5_participants add column if not exists demographics jsonb not null default '{}';
alter table public.matched100v5_participants add column if not exists demographics_revision integer not null default 0;
alter table public.matched100v5_participants add column if not exists demographics_opened_at timestamptz;
alter table public.matched100v5_participants add column if not exists demographics_completed_at timestamptz;
alter table public.matched100v5_participants drop constraint if exists matched100v5_participants_current_position_check;
alter table public.matched100v5_participants add constraint matched100v5_participants_current_position_check check(current_position between 1 and 5);

-- Formatting is guidance, not a submission gate. Word minimum remains enforced in the RPC.
create or replace function public.matched100v5_valid_answer(a text) returns boolean
language sql immutable set search_path=public,pg_temp as $$
 select length(btrim(coalesce(a,'')))>0;
$$;

create or replace function public.matched100v5_valid_demographics(d jsonb,p_complete boolean default false) returns boolean
language plpgsql immutable set search_path=public,pg_temp as $$
declare k text; allowed text[]; v text;
begin
 if jsonb_typeof(d) is distinct from 'object' then return false; end if;
 if (select count(*) from jsonb_object_keys(d))<>5 then return false; end if;
 foreach k in array array['genderIdentity','englishProficiency','educationLevel','employmentStatus'] loop
  if jsonb_typeof(d->k) is distinct from 'string' then return false; end if;
  v:=d->>k;
  allowed:=case k
   when 'genderIdentity' then array['male','female','other','prefer-not-to-say']
   when 'englishProficiency' then array['yes','no-fluent','no-mostly-fluent','no-minimal-fluency']
   when 'educationLevel' then array['no-school','eighth-grade-or-less','more-than-eighth-less-than-high-school','high-school-degree-or-equivalent','some-college','four-year-college-degree','graduate-or-professional-training']
   when 'employmentStatus' then array['employed','self-employed','student','unemployed','other'] end;
  if v='' then if p_complete then return false; end if;
  elsif not(v=any(allowed)) then return false; end if;
 end loop;
 if jsonb_typeof(d->'ageYears')='null' then return not p_complete; end if;
 if jsonb_typeof(d->'ageYears') is distinct from 'number' then return false; end if;
 if d->>'ageYears' !~ '^[0-9]+$' then return false; end if;
 return (d->>'ageYears')::numeric between 18 and 120;
end $$;
revoke all on function public.matched100v5_valid_answer(text) from public,anon,authenticated;
revoke all on function public.matched100v5_valid_demographics(jsonb,boolean) from public,anon,authenticated;
""".replace('OLD_MD5',md5(old_body.encode()).hexdigest()).replace('NEW_MD5',md5(body.encode()).hexdigest())
materials="""
create temp table flow_materials on commit drop as
 select * from jsonb_to_recordset($materials$MATERIALS$materials$::jsonb)
 as p(stimulus_id text,submission_id text,prompt_text text,prompt_sha256 text,body_sha256 text,word_minimum integer,word_limit integer);
alter table flow_materials enable row level security;
revoke all on flow_materials from public,anon,authenticated;
do $$ begin
 if (select count(*) from flow_materials)<>100
   or (select count(*) from public.matched100v5_plan)<>300 then raise exception 'Incomplete material or allocation plan'; end if;
 if exists(select 1 from flow_materials f left join public.matched100v5_materials m
   on m.stimulus_id=f.stimulus_id and m.version='OLD_VERSION'
   where m.stimulus_id is null or m.body_sha256<>f.body_sha256
   or encode(sha256(convert_to(f.prompt_text,'UTF8')),'hex')<>f.prompt_sha256
   or f.word_minimum<>60 or f.word_limit is not null) then raise exception 'Material integrity check failed'; end if;
end $$;
insert into public.matched100v5_materials(version,stimulus_id,prompt_text,prompt_sha256,body_sha256,word_minimum,word_limit)
 select 'NEW_VERSION',stimulus_id,prompt_text,prompt_sha256,body_sha256,word_minimum,word_limit from flow_materials
 on conflict(version,stimulus_id) do nothing;
do $$ begin
 if exists(select 1 from flow_materials f join public.matched100v5_materials m on m.stimulus_id=f.stimulus_id and m.version='NEW_VERSION'
   where f.prompt_text<>m.prompt_text or f.prompt_sha256<>m.prompt_sha256 or f.body_sha256<>m.body_sha256) then
  raise exception 'An existing material version has different content'; end if;
end $$;
insert into public.matched100v5_events(participant_id,action,detail)
 select id,'survey_flow_updated',jsonb_build_object('from',material_version,'to','NEW_VERSION')
 from public.matched100v5_participants where mode='preview' and status='active' and material_version<>'NEW_VERSION';
update public.matched100v5_participants set material_version='NEW_VERSION'
 where mode='preview' and status='active';
update public.matched100v5_settings set version='NEW_VERSION' where id;
""".replace('MATERIALS',json.dumps(posts,ensure_ascii=False)).replace('OLD_VERSION',OLD).replace('NEW_VERSION',NEW)
view="""
create or replace view public.matched100v5_completed_demographics as
 select p.id as participant_id,p.prolific_pid,p.study_id,p.session_id,p.slot_id,p.material_version,
   p.demographics->>'genderIdentity' as gender_identity,
   (p.demographics->>'ageYears')::integer as age_years,
   p.demographics->>'englishProficiency' as english_proficiency,
   p.demographics->>'educationLevel' as education_level,
   p.demographics->>'employmentStatus' as employment_status,
   p.demographics_revision,p.demographics_opened_at,p.demographics_completed_at,p.completed_at
 from public.matched100v5_participants p where p.mode='formal' and p.status='completed';
revoke all on public.matched100v5_completed_demographics from anon,authenticated;
grant select on public.matched100v5_completed_demographics to service_role;
notify pgrst,'reload schema';
commit;
select jsonb_build_object('version',(select version from public.matched100v5_settings where id),
 'recruitment_open',(select recruitment_open from public.matched100v5_settings where id),
 'posts',(select count(*) from public.matched100v5_materials where version='NEW_VERSION'),
 'assignment_rows',(select count(*) from public.matched100v5_plan),
 'formal_participants',(select count(*) from public.matched100v5_participants where mode='formal')) as migration_result;
""".replace('NEW_VERSION',NEW)
(ROOT/'supabase_matched100v6_flow_migration.sql').write_text(schema+'\n'+function+'\n'+materials+view)
print(json.dumps({'version':NEW,'posts':len(posts),'assignments':len(manifest['plan']),'prior_session_source_md5':md5(old_body.encode()).hexdigest(),'new_session_source_md5':md5(body.encode()).hexdigest()}))
