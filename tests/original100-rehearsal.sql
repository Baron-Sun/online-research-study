-- Rehearse the complete formal lifecycle, then roll back every synthetic record and setting.
begin;
set local statement_timeout='30s';
do $$
declare
 old_count bigint; item jsonb; first_id uuid; replacement jsonb; preview_item jsonb;
 i integer; j integer; pid text; token text; blocked boolean; original_slot text; legacy_item jsonb; failed_item jsonb; failed_slot text; check_event text;
begin
 select count(*) into old_count from public.advice_transfer_assignments;
 if (select recruitment_open from public.original100_settings where id) then raise exception 'Preflight requires recruitment closed'; end if;
 if (select count(*) from public.original100_participants where mode='formal')<>0 then raise exception 'Formal study already has records'; end if;
 if has_table_privilege('anon','public.original100_responses','select') or has_table_privilege('anon','public.original100_participants','select')
   or has_table_privilege('anon','public.original100_completed_comments','select')
   or has_function_privilege('anon','public.original100_release(uuid,text)','execute')
 then raise exception 'Raw data or admin operation is exposed'; end if;
 preview_item:=public.original100_session('claim','qa-sql-preview','qa-study','qa-session',repeat('a',64),true,'{"consent":true,"slot":"S001"}');
 if (select count(*) from public.original100_participants where mode='formal')<>0 then raise exception 'Preview consumed formal quota'; end if;
 update public.original100_settings set version='original100-20261024-v1' where id;
 legacy_item:=public.original100_session('claim','qa-legacy-material-version','qa-study','qa-session',repeat('c',64),true,'{"consent":true,"slot":"S001"}');
 update public.original100_settings set version='private100-20261024-v2' where id;
 if public.original100_session('resume','qa-legacy-material-version','qa-study','qa-session',repeat('c',64),true,'{}')->>'version'<>'original100-20261024-v1' then raise exception 'An existing session changed material version'; end if;
 if public.original100_session('resume','qa-legacy-material-version','qa-study','qa-session',repeat('c',64),true,'{}')->'posts'<>legacy_item->'posts' then raise exception 'Historical prompts changed'; end if;
 update public.original100_settings set recruitment_open=true,study_id='qa-sql-study',completion_code='QA_ROLLBACK',consent_approved=true where id;
 failed_item:=public.original100_session('claim',repeat('d',24),'qa-sql-study',repeat('d',24),repeat('d',64),false,'{"consent":true}');
 failed_slot:=failed_item->>'slot';check_event:=gen_random_uuid()::text;
 failed_item:=public.original100_session('comprehension_check',repeat('d',24),'qa-sql-study',repeat('d',24),repeat('d',64),false,jsonb_build_object('event_id',check_event,'choice','summarize','version','task-comprehension-v1'));
 failed_item:=public.original100_session('comprehension_check',repeat('d',24),'qa-sql-study',repeat('d',24),repeat('d',64),false,jsonb_build_object('event_id',check_event,'choice','summarize','version','task-comprehension-v1'));
 if (failed_item->'comprehensionCheck'->>'attempts')::integer<>1 then raise exception 'Retry counted twice'; end if;
 failed_item:=public.original100_session('comprehension_check',repeat('d',24),'qa-sql-study',repeat('d',24),repeat('d',64),false,jsonb_build_object('event_id',gen_random_uuid()::text,'choice','advice','version','task-comprehension-v1'));
 if failed_item->>'status'<>'screened_out' then raise exception 'Two incorrect answers did not end the session'; end if;
 if public.original100_session('claim',repeat('d',24),'qa-sql-study',repeat('d',24),repeat('d',64),false,'{"consent":true}')->>'status'<>'screened_out' then raise exception 'Screened identity reclaimed a place'; end if;
 for i in 1..100 loop
   pid:=lpad(to_hex(i),24,'0'); token:=repeat(md5('original100-qa-'||i),2);
   item:=public.original100_session('claim',pid,'qa-sql-study',pid,token,false,'{"consent":true}');
   if i=1 then
     if item->>'slot'<>failed_slot then raise exception 'Screened slot was not reopened'; end if;
     first_id:=(item->>'id')::uuid; original_slot:=item->>'slot';
     if public.original100_session('claim',pid,'qa-sql-study',pid,token,false,'{"consent":true}')->>'id'<>item->>'id' then raise exception 'Duplicate identity received another slot'; end if;
     blocked:=false;
     begin perform public.original100_session('complete',pid,'qa-sql-study',pid,token,false,'{"revisions":[0,0,0]}'); exception when others then blocked:=true; end;
     if not blocked then raise exception 'Incomplete submission accepted'; end if;
     blocked:=false;
     begin perform public.original100_session('resume',pid,'qa-sql-study',pid,repeat('f',64),false,'{}'); exception when others then blocked:=true; end;
     if not blocked then raise exception 'Wrong capability accepted'; end if;
   end if;
   perform public.original100_session('comprehension_check',pid,'qa-sql-study',pid,token,false,
     jsonb_build_object('event_id',gen_random_uuid()::text,'choice','judgment_reasons','version','task-comprehension-v1'));
   for j in 1..3 loop
     item:=public.original100_session('save',pid,'qa-sql-study',pid,token,false,
       jsonb_build_object('position',j,'revision',0,'answer',E'NTA\nSYNTHETIC SQL REHEARSAL ONLY. Participant '||i||', post position '||j||'.'));
   end loop;
   if i=1 then
     blocked:=false;
     begin perform public.original100_session('save',pid,'qa-sql-study',pid,token,false,'{"position":1,"revision":0,"answer":"NTA\nStale overwrite"}'); exception when others then blocked:=true; end;
     if not blocked then raise exception 'Stale draft overwrote a newer version'; end if;
     item:=public.original100_session('navigate',pid,'qa-sql-study',pid,token,false,'{"position":2}');
     if public.original100_session('resume',pid,'qa-sql-study',pid,token,false,'{}')->>'position'<>'2' then raise exception 'Position did not persist'; end if;
   end if;
   item:=public.original100_session('complete',pid,'qa-sql-study',pid,token,false,'{"revisions":[1,1,1]}');
   if item->>'status'<>'completed' then raise exception 'Completion failed'; end if;
   item:=public.original100_session('complete',pid,'qa-sql-study',pid,token,false,'{"revisions":[1,1,1]}');
 end loop;
 if (select count(*) from public.original100_completed_comments)<>300 then raise exception 'Wrong completion count'; end if;
 if exists(select stimulus_id from public.original100_completed_comments group by stimulus_id having count(*)<>3 or count(distinct prolific_pid)<>3) then raise exception 'Post coverage is not three distinct people'; end if;
 if exists(select prolific_pid from public.original100_completed_comments group by prolific_pid having count(distinct stimulus_id)<>3) then raise exception 'Participant received wrong post count'; end if;
 blocked:=false;
 begin perform public.original100_session('claim',repeat('f',24),'qa-sql-study',repeat('f',24),repeat('f',64),false,'{"consent":true}'); exception when others then blocked:=true; end;
 if not blocked then raise exception 'Participant 101 exceeded capacity'; end if;
 blocked:=false;
 begin perform public.original100_session('save',lpad('1',24,'0'),'qa-sql-study',lpad('1',24,'0'),repeat(md5('original100-qa-1'),2),false,'{"position":1,"revision":1,"answer":"NTA\nForbidden edit after submit"}'); exception when others then blocked:=true; end;
 if not blocked then raise exception 'Completed response was editable'; end if;
 perform public.original100_release(first_id,'Synthetic exclusion and replacement rehearsal');
 pid:=lpad(to_hex(1001),24,'0'); token:=repeat('b',64);
 replacement:=public.original100_session('claim',pid,'qa-sql-study',pid,token,false,'{"consent":true}');
 if replacement->>'slot'<>original_slot then raise exception 'Replacement did not inherit released slot'; end if;
 perform public.original100_session('comprehension_check',pid,'qa-sql-study',pid,token,false,
   jsonb_build_object('event_id',gen_random_uuid()::text,'choice','judgment_reasons','version','task-comprehension-v1'));
 for j in 1..3 loop
   perform public.original100_session('save',pid,'qa-sql-study',pid,token,false,jsonb_build_object('position',j,'revision',0,'answer',E'INFO\nSYNTHETIC REPLACEMENT REHEARSAL ONLY.'));
 end loop;
 perform public.original100_session('complete',pid,'qa-sql-study',pid,token,false,'{"revisions":[1,1,1]}');
 if (select count(*) from public.original100_completed_comments)<>300 or exists(select stimulus_id from public.original100_completed_comments group by stimulus_id having count(*)<>3 or count(distinct prolific_pid)<>3) then raise exception 'Replacement damaged coverage'; end if;
 if (select count(*) from public.original100_responses where participant_id=first_id)<>3 then raise exception 'Excluded raw responses were lost'; end if;
 blocked:=false;
 begin perform public.original100_session('claim',lpad('1',24,'0'),'qa-sql-study',lpad('1',24,'0'),repeat(md5('original100-qa-1'),2),false,'{"consent":true}'); exception when others then blocked:=true; end;
 if not blocked then raise exception 'Excluded identity returned as a new participant'; end if;
 if (select count(*) from public.advice_transfer_assignments)<>old_count then raise exception 'Historical assignments changed'; end if;
end $$;
select 'PASS: 100 completed people, 300 comments, 3 distinct people per post; version preservation, two-attempt check, slot refill, duplicate/capacity/token/stale/lock/privacy checks passed. All synthetic changes rolled back.' as rehearsal_result;
rollback;
