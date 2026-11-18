-- Изпитанията продължават само в храм „Тест“: всички членове на другите
-- (пробни) храмове минават в него като свещеници, а пробните храмове се трият.
-- Решено от създателя на 16.11.2026 – данните в тях са само пробни.
do $$
declare
  t uuid;
  n int;
begin
  select c.id into t from churches c join dioceses d on d.id = c.diocese_id
   where c.name = 'Тест' and d.name = 'Тест' order by c.created_at limit 1;
  if t is null then return; end if;  -- празна база (проверките в CI)
  -- Всички, които минават в „Тест“, стават от епархия „Тест“ (иначе пазачът
  -- „един човек – една епархия“ не ги пуска).
  update profiles p set diocese_id = (select diocese_id from churches where id = t)
   where p.id in (select user_id from church_members where status = 'active' and church_id <> t);
  insert into church_members (church_id, user_id, role, status)
  select distinct t, m.user_id, 'priest', 'active'
    from church_members m
   where m.church_id <> t and m.status = 'active'
  on conflict (church_id, user_id) do nothing;
  -- Предпазител: към 16.11 храмовете са 4 (Тест + 3 пробни). Ако са повече,
  -- значи има нов истински храм – тогава нищо не се трие.
  if (select count(*) from churches) > 4 then raise exception 'неочакван брой храмове – прегледай ръчно'; end if;
  -- Касата първо: събитие с приход в касата не се трие (защита от грешки).
  delete from cash_entries where church_id <> t;
  delete from churches where id <> t;
  get diagnostics n = row_count;
  insert into activity_log (action, details) values ('Изтри пробни храмове', n || ' храма; членовете са в „Тест“');
end $$;


-- Поправка: изтриването на храм от създателя се спъваше в същата защита.
create or replace function public.creator_delete_church(p_church uuid, p_name text)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  cname text;
  ids uuid[] := '{}';
  u uuid;
  members uuid[];
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  select name into cname from churches where id = p_church;
  if cname is null then raise exception 'not_found'; end if;
  if lower(trim(coalesce(p_name, ''))) <> lower(trim(cname)) then raise exception 'name_mismatch'; end if;
  select array_agg(user_id) into members from church_members where church_id = p_church and status = 'active';
  -- Касата първо: събитие с приход в касата не се трие (защита от грешки).
  delete from cash_entries where church_id = p_church;
  delete from churches where id = p_church;
  -- Съобщенията са без храм (храмът вече го няма), до всеки бивш член.
  foreach u in array coalesce(members, '{}') loop
    ids := ids || public.creator_notice(u, null, 'Храмът „' || cname || '“ е изтрит',
             'Създателят на Кайрос изтри храма (тестов или несъществуващ). Ако е грешка, свържете се с него.');
  end loop;
  insert into activity_log (actor_id, action, details) values (auth.uid(), 'Изтри храм', cname);
  return array_remove(ids, null);
end;
$$;
