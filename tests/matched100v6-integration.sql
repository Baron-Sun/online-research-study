-- Run after the v6 migration. All synthetic preview and formal records roll back.
begin;
do $$
declare
 s jsonb; final_result jsonb; demo jsonb; partial_demo jsonb;
 pid text:='qa-flow-'||gen_random_uuid()::text;
 formal_pid text:=substr(md5(gen_random_uuid()::text),1,24);
 formal_session text:=substr(md5(gen_random_uuid()::text),1,24);
 configured_study text; configured_code text;
 blocked boolean; i integer; a text;
begin
 demo:='{"genderIdentity":"prefer-not-to-say","ageYears":35,"englishProficiency":"no-fluent","educationLevel":"graduate-or-professional-training","employmentStatus":"student"}'::jsonb;
 partial_demo:='{"genderIdentity":"prefer-not-to-say","ageYears":null,"englishProficiency":"","educationLevel":"","employmentStatus":""}'::jsonb;
 if not public.matched100v5_valid_demographics(demo,true) or not public.matched100v5_valid_demographics(partial_demo,false)
   or public.matched100v5_valid_demographics(partial_demo,true) then raise exception 'Demographic completeness validation failed'; end if;
 for i in 17..121 loop
  if public.matched100v5_valid_demographics(jsonb_set(demo,'{ageYears}',to_jsonb(i)),true) is distinct from (i between 18 and 120) then raise exception 'Invalid demographic age boundary'; end if;
 end loop;
 if public.matched100v5_valid_demographics(jsonb_set(demo,'{ageYears}','20.5'),true)
  or public.matched100v5_valid_demographics(jsonb_set(demo,'{genderIdentity}','"invalid"'),true)
  or public.matched100v5_valid_demographics(demo||'{"unexpected":"value"}',true) then raise exception 'Invalid demographic input accepted'; end if;
 s:=public.matched100v5_session('claim',pid,'qa-flow-study',pid,repeat('a',64),true,'{"consent":true}');
 if s->>'version'<>'private100-study1matched-opinion-demographics-20261030-v6' then raise exception 'Wrong material version'; end if;
 blocked:=false;
 begin perform public.matched100v5_session('navigate',pid,'qa-flow-study',pid,repeat('a',64),true,'{"position":1}'); exception when others then blocked:=true; end;
 if not blocked then raise exception 'Understanding check bypassed'; end if;
 s:=public.matched100v5_session('comprehension_check',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('event_id',gen_random_uuid()::text,'choice','judgment_reasons','version','task-comprehension-v1'));
 if not (s->'comprehensionCheck'->>'passed')::boolean or s->>'position'<>'1' then raise exception 'Successful check did not reach task state'; end if;
 a:='nta '||repeat('synthetic ',58);
 perform public.matched100v5_session('save',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('position',1,'answer',a,'revision',0));
 blocked:=false;
 begin perform public.matched100v5_session('navigate',pid,'qa-flow-study',pid,repeat('a',64),true,'{"position":2}'); exception when others then if sqlerrm not like '%at least 60%' then raise; end if; blocked:=true; end;
 if not blocked then raise exception '59-word answer advanced'; end if;
 for i in 1..3 loop
  a:=case i when 1 then 'nTa '||repeat('synthetic ',59) when 2 then repeat('synthetic ',60) else E'INFO\n'||repeat('synthetic ',59) end;
  s:=public.matched100v5_session('save',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('position',i,'answer',a,'revision',case when i=1 then 1 else 0 end));
  perform public.matched100v5_session('navigate',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('position',i+1));
 end loop;
 s:=public.matched100v5_session('navigate',pid,'qa-flow-study',pid,repeat('a',64),true,'{"position":5}');
 if s->>'position'<>'5' or s->>'demographicsOpenedAt' is null then raise exception 'Demographic screen not persisted'; end if;
 blocked:=false;
 begin perform public.matched100v5_session('complete',pid,'qa-flow-study',pid,repeat('a',64),true,'{"revisions":[2,1,1],"demographicsRevision":0}'); exception when others then if sqlerrm not like '%five demographic%' then raise; end if; blocked:=true; end;
 if not blocked then raise exception 'Completion accepted missing demographics'; end if;
 s:=public.matched100v5_session('save_demographics',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('demographics',partial_demo,'revision',0));
 if s->'demographics'<>partial_demo or s->>'demographicsRevision'<>'1' then raise exception 'Partial demographics not saved'; end if;
 s:=public.matched100v5_session('resume',pid,'qa-flow-study',pid,repeat('a',64),true,'{}');
 if s->>'position'<>'5' or s->'demographics'<>partial_demo then raise exception 'Demographic recovery failed'; end if;
 s:=public.matched100v5_session('save_demographics',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('demographics',demo,'revision',1));
 -- Same payload with a stale revision is an idempotent lost-receipt retry.
 s:=public.matched100v5_session('save_demographics',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('demographics',demo,'revision',1));
 if s->>'demographicsRevision'<>'2' then raise exception 'Demographic retry wrote twice'; end if;
 blocked:=false;
 begin perform public.matched100v5_session('save_demographics',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('demographics',partial_demo,'revision',1)); exception when others then blocked:=true; end;
 if not blocked then raise exception 'Stale demographic overwrite accepted'; end if;
 blocked:=false;
 begin perform public.matched100v5_session('complete',pid,'qa-flow-study',pid,repeat('a',64),true,'{"revisions":[2,1,1],"demographicsRevision":1}'); exception when others then blocked:=true; end;
 if not blocked then raise exception 'Stale demographic final submission accepted'; end if;
 final_result:=public.matched100v5_session('complete',pid,'qa-flow-study',pid,repeat('a',64),true,'{"revisions":[2,1,1],"demographicsRevision":2}');
 if final_result->>'status'<>'completed' or final_result->>'completionCode' is not null or final_result->'demographics'<>demo or final_result->>'demographicsCompletedAt' is null then raise exception 'Preview completion failed'; end if;
 s:=public.matched100v5_session('complete',pid,'qa-flow-study',pid,repeat('a',64),true,'{"revisions":[2,1,1],"demographicsRevision":2}');
 if s<>final_result then raise exception 'Repeated final submission was not idempotent'; end if;
 blocked:=false;
 begin perform public.matched100v5_session('save_demographics',pid,'qa-flow-study',pid,repeat('a',64),true,jsonb_build_object('demographics',partial_demo,'revision',2)); exception when others then blocked:=true; end;
 if not blocked then raise exception 'Completed demographics could be edited'; end if;

 select study_id,completion_code into configured_study,configured_code from public.matched100v5_settings where id;
 update public.matched100v5_settings set recruitment_open=true where id;
 s:=public.matched100v5_session('claim',formal_pid,configured_study,formal_session,repeat('b',64),false,'{"consent":true}');
 perform public.matched100v5_session('comprehension_check',formal_pid,configured_study,formal_session,repeat('b',64),false,jsonb_build_object('event_id',gen_random_uuid()::text,'choice','judgment_reasons','version','task-comprehension-v1'));
 for i in 1..3 loop
  perform public.matched100v5_session('save',formal_pid,configured_study,formal_session,repeat('b',64),false,jsonb_build_object('position',i,'answer','nta '||repeat('synthetic ',59),'revision',0));
 end loop;
 perform public.matched100v5_session('navigate',formal_pid,configured_study,formal_session,repeat('b',64),false,'{"position":5}');
 perform public.matched100v5_session('save_demographics',formal_pid,configured_study,formal_session,repeat('b',64),false,jsonb_build_object('demographics',demo,'revision',0));
 s:=public.matched100v5_session('complete',formal_pid,configured_study,formal_session,repeat('b',64),false,'{"revisions":[1,1,1],"demographicsRevision":1}');
 if s->>'completionCode' is distinct from configured_code then raise exception 'Configured completion code not returned'; end if;
 if (select count(*) from public.matched100v5_completed_comments where prolific_pid=formal_pid)<>3
  or (select count(*) from public.matched100v5_completed_demographics where prolific_pid=formal_pid and age_years=35 and gender_identity='prefer-not-to-say')<>1 then raise exception 'Research export incomplete'; end if;
 if has_table_privilege('anon','public.matched100v5_completed_demographics','select')
   or has_table_privilege('anon','public.matched100v5_participants','select') then raise exception 'Raw demographic data exposed'; end if;
end $$;
select 'PASS: paragraph responses, minimum 60, required demographics, recovery, concurrency, completion and private exports' as acceptance;
rollback;
