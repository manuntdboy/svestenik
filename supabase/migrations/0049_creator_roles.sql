-- =====================================================================
-- Създателят сменя ролите на всеки човек и може да го извади от храм.
--  * роля в храма: председател / свещеник + отметка „касиер“;
--  * един председател и един касиер на храм (старият се сменя);
--  * човекът и председателят получават карта с „ОК“ и известие –
--    затова съобщенията вече могат да са до един човек (recipient_id).
-- =====================================================================

alter table public.announcements add column recipient_id uuid references auth.users (id) on delete cascade;
create index announcements_recipient_idx on public.announcements (recipient_id) where recipient_id is not null;

drop policy if exists announcements_select on public.announcements;
create policy announcements_select on public.announcements for select to authenticated
  using (public.is_creator()
         or (recipient_id is null and (church_id is null or public.is_member(church_id)))
         or recipient_id = auth.uid());

-- Лично съобщение (карта + известие); създателят не го вижда като свое.
create or replace function public.creator_notice(p_user uuid, p_church uuid, p_title text, p_body text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  v uuid;
begin
  if p_user is null or p_user = auth.uid() then return null; end if;
  insert into announcements (church_id, recipient_id, title, body, created_by)
  values (p_church, p_user, p_title, p_body, auth.uid()) returning id into v;
  insert into announcement_seen (announcement_id, user_id) values (v, auth.uid());
  return v;
end;
$$;
revoke execute on function public.creator_notice(uuid, uuid, text, text) from public, anon, authenticated;

-- Храмовете на човека с ролите му – за прозореца „Роли“.
create or replace function public.creator_user_churches(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'church_id', c.id, 'name', c.name, 'settlement', c.settlement, 'status', m.status,
      'chair', m.role = 'manager', 'cashier', 'cash' = any (m.permissions),
      'members', (select count(*) from church_members x where x.church_id = c.id and x.status = 'active'),
      'chair_name', (select coalesce(p.full_name, '—') from church_members x join profiles p on p.id = x.user_id
                      where x.church_id = c.id and x.role = 'manager' and x.user_id <> p_user limit 1),
      'cashier_name', (select coalesce(p.full_name, '—') from church_members x join profiles p on p.id = x.user_id
                        where x.church_id = c.id and 'cash' = any (x.permissions) and x.user_id <> p_user limit 1)
    ) order by c.name)
    from church_members m join churches c on c.id = m.church_id
   where m.user_id = p_user), '[]'::jsonb);
end;
$$;

-- Смяна на ролята. Връща id-тата на съобщенията (приложението праща известията).
create or replace function public.creator_set_role(p_church uuid, p_user uuid, p_chair boolean, p_cashier boolean)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  m church_members;
  cname text;
  uname text;
  old_chair uuid;
  old_cashier uuid;
  was_chair boolean;
  was_cashier boolean;
  ids uuid[] := '{}';
  what text;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  select * into m from church_members where church_id = p_church and user_id = p_user;
  if not found then raise exception 'not_member'; end if;
  if m.status <> 'active' then raise exception 'member_pending'; end if;
  select name into cname from churches where id = p_church;
  select coalesce(full_name, '—') into uname from profiles where id = p_user;
  was_chair := m.role = 'manager';
  was_cashier := 'cash' = any (m.permissions);
  p_cashier := coalesce(p_cashier, false) and not coalesce(p_chair, false); -- председателят не е касиер
  if was_chair and not p_chair then raise exception 'need_chair'; end if;
  if was_chair = p_chair and was_cashier = p_cashier then return ids; end if;

  select user_id into old_chair from church_members
   where church_id = p_church and role = 'manager' and user_id <> p_user limit 1;

  if p_chair and not was_chair then
    update church_members set role = 'priest' where church_id = p_church and role = 'manager' and user_id <> p_user;
    update church_members set role = 'manager', permissions = array_remove(permissions, 'cash')
     where church_id = p_church and user_id = p_user;
    update churches set pending_chair = null, chair_proposed_by = null where id = p_church;
    ids := ids || public.creator_notice(p_user, p_church, 'Вие сте председател на „' || cname || '“',
             'Създателят на Кайрос ви направи председател на храма.');
    if old_chair is not null then
      ids := ids || public.creator_notice(old_chair, p_church, 'Нов председател на „' || cname || '“',
               uname || ' вече е председател на храма. Вие оставате свещеник.');
    end if;
    return array_remove(ids, null);
  end if;

  -- Касиер: един на храм – старият губи правото.
  if p_cashier then
    select user_id into old_cashier from church_members
     where church_id = p_church and 'cash' = any (permissions) and user_id <> p_user limit 1;
    update church_members set permissions = array_remove(permissions, 'cash')
     where church_id = p_church and user_id <> p_user;
    update church_members set permissions = (select array_agg(distinct x) from unnest(permissions || 'cash'::text) x)
     where church_id = p_church and user_id = p_user;
    what := uname || ' е касиер на храма.';
    ids := ids || public.creator_notice(p_user, p_church, 'Вие сте касиер на „' || cname || '“',
             'Създателят на Кайрос ви направи касиер на храма.');
    if old_cashier is not null and old_cashier <> coalesce(old_chair, p_user) then
      ids := ids || public.creator_notice(old_cashier, p_church, 'Промяна в касата на „' || cname || '“',
               what || ' Вие вече не сте касиер.');
    end if;
  else
    update church_members set permissions = array_remove(permissions, 'cash')
     where church_id = p_church and user_id = p_user;
    what := uname || ' вече не е касиер.';
    ids := ids || public.creator_notice(p_user, p_church, 'Промяна в „' || cname || '“',
             'Създателят на Кайрос махна правото ви на касиер. Оставате свещеник.');
  end if;
  if old_chair is not null then
    ids := ids || public.creator_notice(old_chair, p_church, 'Промяна в „' || cname || '“', what);
  end if;
  return array_remove(ids, null);
end;
$$;

-- Изваждане от храм. Председателят не може да бъде изваден, докато има други в храма.
create or replace function public.creator_remove_member(p_church uuid, p_user uuid)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  m church_members;
  cname text;
  uname text;
  chair uuid;
  ids uuid[] := '{}';
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  select * into m from church_members where church_id = p_church and user_id = p_user;
  if not found then return ids; end if;
  if m.role = 'manager' and exists (select 1 from church_members
       where church_id = p_church and user_id <> p_user and status = 'active') then
    raise exception 'need_chair';
  end if;
  select name into cname from churches where id = p_church;
  select coalesce(full_name, '—') into uname from profiles where id = p_user;
  select user_id into chair from church_members where church_id = p_church and role = 'manager' and user_id <> p_user limit 1;
  delete from church_members where church_id = p_church and user_id = p_user;
  if m.status = 'active' then
    ids := ids || public.creator_notice(p_user, p_church, 'Извадени сте от „' || cname || '“',
             'Създателят на Кайрос ви извади от храма. Ако е грешка, свържете се с председателя.');
    ids := ids || public.creator_notice(chair, p_church, 'Промяна в „' || cname || '“',
             uname || ' вече не е в храма.');
  end if;
  return array_remove(ids, null);
end;
$$;

revoke execute on function public.creator_user_churches(uuid) from public, anon;
revoke execute on function public.creator_set_role(uuid, uuid, boolean, boolean) from public, anon;
revoke execute on function public.creator_remove_member(uuid, uuid) from public, anon;
grant execute on function public.creator_user_churches(uuid) to authenticated;
grant execute on function public.creator_set_role(uuid, uuid, boolean, boolean) to authenticated;
grant execute on function public.creator_remove_member(uuid, uuid) to authenticated;
