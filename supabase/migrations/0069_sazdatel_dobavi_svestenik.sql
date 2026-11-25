-- Създателят добавя свещеник в храм (напр. храм, останал без никого –
-- тогава няма кой да одобри молба за влизане). Ако храмът е празен,
-- свещеникът става председател.

create or replace function public.creator_people_search(p_q text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  q text := btrim(coalesce(p_q, ''));
  qd text := regexp_replace(q, '[^0-9]', '', 'g');
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  if char_length(q) < 2 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'name')
    from (
      select jsonb_build_object(
        'user_id', p.id, 'username', p.username, 'name', p.full_name, 'rank', p.rank, 'phone', p.phone,
        'churches', (select string_agg(c.name || ' – ' || c.settlement
                                       || case when m.status = 'pending' then ' (чака)' else '' end, '; ')
                       from church_members m join churches c on c.id = m.church_id where m.user_id = p.id)
      ) as x
      from profiles p
      where p.full_name ilike '%' || q || '%' or p.username::text ilike '%' || q || '%'
         or (char_length(qd) >= 3 and regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') like '%' || qd || '%')
      limit 20
    ) t), '[]'::jsonb);
end;
$$;

create or replace function public.creator_add_member(p_church uuid, p_user uuid)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  cname text;
  uname text;
  chair uuid;
  st text;
  ids uuid[] := '{}';
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  select name into cname from churches where id = p_church;
  if cname is null then raise exception 'not_found'; end if;
  select coalesce(full_name, '—') into uname from profiles where id = p_user;
  if uname is null then raise exception 'not_found'; end if;
  select status into st from church_members where church_id = p_church and user_id = p_user;
  if st = 'active' then return ids; end if;
  select user_id into chair from church_members
   where church_id = p_church and role = 'manager' and status = 'active' and user_id <> p_user limit 1;
  insert into church_members (church_id, user_id, role, status)
  values (p_church, p_user, case when chair is null then 'manager' else 'priest' end, 'active')
  on conflict (church_id, user_id) do update
    set status = 'active', role = case when chair is null then 'manager' else 'priest' end;
  ids := ids || public.creator_notice(p_user, p_church,
           case when chair is null then 'Вие сте председател на „' || cname || '“'
                else 'Добавени сте в „' || cname || '“' end,
           'Създателят на Кайрос ви добави в храма.');
  if chair is not null then
    ids := ids || public.creator_notice(chair, p_church, 'Нов свещеник в „' || cname || '“',
             uname || ' е добавен в храма от създателя на Кайрос.');
  end if;
  return array_remove(ids, null);
end;
$$;

revoke execute on function public.creator_people_search(text) from public, anon;
revoke execute on function public.creator_add_member(uuid, uuid) from public, anon;
grant execute on function public.creator_people_search(text) to authenticated;
grant execute on function public.creator_add_member(uuid, uuid) to authenticated;
