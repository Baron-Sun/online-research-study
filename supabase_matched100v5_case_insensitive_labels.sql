-- Accept any letter casing for the five judgment labels; preserve response text.
-- Only the validator changes. Existing responses, materials and assignments stay intact.
begin;

create or replace function public.matched100v5_valid_answer(a text) returns boolean
language sql immutable set search_path=public,pg_temp as $$
 select coalesce(upper(btrim(split_part(replace(a,E'\r\n',E'\n'),E'\n',1))) in ('YTA','NTA','ESH','NAH','INFO')
   and strpos(a,E'\n')>0 and length(btrim(substring(a from strpos(a,E'\n')+1), E' \t\r\n'))>0,false);
$$;
revoke all on function public.matched100v5_valid_answer(text) from public,anon,authenticated;

do $$
declare
 label text; variant text; mask integer; letter_index integer; checked integer:=0;
begin
 foreach label in array array['YTA','NTA','ESH','NAH','INFO'] loop
  for mask in 0..(1 << length(label))-1 loop
   variant:='';
   for letter_index in 0..length(label)-1 loop
    variant:=variant || case when (mask & (1 << letter_index))=0
      then substr(label,letter_index+1,1) else lower(substr(label,letter_index+1,1)) end;
   end loop;
   if not public.matched100v5_valid_answer(variant || E'\nTest reasoning.')
     or not public.matched100v5_valid_answer(variant || E'\r\nTest reasoning.') then
    raise exception 'Judgment casing check failed for %',variant;
   end if;
   checked:=checked+1;
  end loop;
 end loop;
 if checked<>48 then raise exception 'Incomplete casing coverage'; end if;
 if public.matched100v5_valid_answer(null)
   or public.matched100v5_valid_answer(repeat('a ',86))
   or public.matched100v5_valid_answer('nta because ' || repeat('word ',60))
   or public.matched100v5_valid_answer(E'nta\n  ')
   or public.matched100v5_valid_answer(E'nta.\nTest reasoning.') then
  raise exception 'Malformed response unexpectedly accepted';
 end if;
end;
$$;

commit;

select jsonb_build_object(
 'validator_updated',true,
 'casing_variants_checked',48,
 'lowercase_accepted',public.matched100v5_valid_answer(E'nta\nTest reasoning.'),
 'mixed_case_accepted',public.matched100v5_valid_answer(E'nTa\nTest reasoning.'),
 'minimum_word_counts',(select jsonb_agg(distinct word_minimum) from public.matched100v5_materials),
 'response_word_limits',(select jsonb_agg(distinct word_limit) from public.matched100v5_materials)
) as validation;
