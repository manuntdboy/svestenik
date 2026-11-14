-- =====================================================================
-- Създателят изтрива храм (тестови и несъществуващи храмове).
-- Изтрива се всичко на храма: членства, събития, каса, склад, чат,
-- дежурства, почивки. Профилите на хората остават. Всеки член получава
-- лично съобщение (карта с „ОК“ + известие). За сигурност се иска името.
-- =====================================================================

create or replace function public.creator_church_summary(p_church uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'name', (select name from churches where id = p_church),
    'members', (select count(*) from church_members where church_id = p_church),
    'events', (select count(*) from events where church_id = p_church),
    'cash', (select count(*) from cash_entries where church_id = p_church),
    'stock', (select count(*) from stock_moves where church_id = p_church),
    'chat', (select count(*) from chat_messages where church_id = p_church));
end;
$$;

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

revoke execute on function public.creator_church_summary(uuid) from public, anon;
revoke execute on function public.creator_delete_church(uuid, text) from public, anon;
grant execute on function public.creator_church_summary(uuid) to authenticated;
grant execute on function public.creator_delete_church(uuid, text) to authenticated;
