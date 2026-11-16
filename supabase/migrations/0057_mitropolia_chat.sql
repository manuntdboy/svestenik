-- Администрацията на митрополията: служители (счетоводител, деловодител…)
-- и чат „Митрополия“ – общ за администрацията (митрополит, секретар,
-- протосингел, служители) плюс лични разговори между тях. Наместниците не са
-- администрация. Съдържанието вижда само участникът в разговора.

alter table public.diocese_staff drop constraint diocese_staff_role_check;
alter table public.diocese_staff add constraint diocese_staff_role_check
  check (role in ('metropolitan', 'secretary', 'protosyngel', 'vicar', 'employee'));
alter table public.diocese_staff add column title text check (char_length(title) <= 60);
drop index public.diocese_staff_one_per_diocese;
create unique index diocese_staff_one_per_diocese on public.diocese_staff (diocese_id, role)
  where role in ('metropolitan', 'secretary', 'protosyngel');

-- Член на администрацията на епархията.
create or replace function public.is_admin_of(p_diocese uuid, p_user uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from diocese_staff where diocese_id = p_diocese and user_id = p_user
                  and role in ('metropolitan', 'secretary', 'protosyngel', 'employee'));
$$;

-- staff_set – и за служители (с титла).
drop function public.staff_set(uuid, text, uuid);
create or replace function public.staff_set(p_user uuid, p_role text, p_vicariate uuid default null,
                                           p_title text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  d uuid;
  vd uuid;
  label text;
  t text := nullif(btrim(coalesce(p_title, '')), '');
begin
  select diocese_id into d from profiles where id = p_user;
  if d is null then raise exception 'no_diocese'; end if;
  if p_role = 'metropolitan' then
    if not public.is_creator() then raise exception 'forbidden'; end if;
  elsif p_role in ('secretary', 'protosyngel', 'vicar', 'employee') then
    if not (public.is_creator() or public.is_metropolitan_of(d)) then raise exception 'forbidden'; end if;
  else
    raise exception 'bad_role';
  end if;
  if p_role = 'vicar' then
    select diocese_id into vd from vicariates where id = p_vicariate and not is_center;
    if vd is distinct from d then raise exception 'other_diocese'; end if;
    delete from diocese_staff where role = 'vicar' and vicariate_id = p_vicariate;
  elsif p_role = 'employee' then
    if t is null then raise exception 'bad_name'; end if;
    p_vicariate := null;
    delete from diocese_staff where user_id = p_user and role = 'employee';
  else
    p_vicariate := null;
    delete from diocese_staff where diocese_id = d and role = p_role;
  end if;
  insert into diocese_staff (diocese_id, user_id, role, vicariate_id, title)
  values (d, p_user, p_role, p_vicariate, case when p_role = 'employee' then left(t, 60) end);
  if p_role = 'metropolitan' then update profiles set rank = 'metropolitan' where id = p_user; end if;
  label := case p_role when 'metropolitan' then 'Митрополит' when 'secretary' then 'Секретар'
             when 'protosyngel' then 'Протосингел' when 'employee' then 'Служител · ' || t
             else 'Архиерейски наместник' end;
  insert into activity_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user, 'Длъжност в митрополията', label ||
          coalesce(' · ' || (select name from vicariates where id = p_vicariate), ''));
end;
$$;

-- Изгледът „Епархия“ (diocese_overview) остава за длъжностите над храмовете –
-- служителите го нямат (там няма клон за 'employee').

create table public.metro_messages (
  id           uuid primary key default gen_random_uuid(),
  diocese_id   uuid not null references public.dioceses (id) on delete cascade,
  sender_id    uuid references auth.users (id) on delete set null,
  recipient_id uuid references auth.users (id) on delete cascade, -- null = общ чат на администрацията
  body         text not null check (char_length(body) between 1 and 2000),
  created_at   timestamptz not null default now()
);
create index metro_messages_diocese_idx on public.metro_messages (diocese_id, created_at);
alter table public.metro_messages enable row level security;
create policy metro_messages_select on public.metro_messages for select to authenticated
  using (public.is_admin_of(diocese_id)
         and (recipient_id is null or sender_id = auth.uid() or recipient_id = auth.uid()));

create table public.metro_reads (
  user_id    uuid not null references auth.users (id) on delete cascade,
  diocese_id uuid not null references public.dioceses (id) on delete cascade,
  thread     text not null, -- 'c' – общият, иначе id на събеседника
  read_at    timestamptz not null default now(),
  primary key (user_id, diocese_id, thread)
);
alter table public.metro_reads enable row level security;
create policy metro_reads_select on public.metro_reads for select to authenticated using (user_id = auth.uid());

create or replace function public.metro_chat_send(p_diocese uuid, p_recipient uuid, p_body text)
returns public.metro_messages language plpgsql security definer set search_path = public, extensions as $$
declare
  r metro_messages;
begin
  if not public.is_admin_of(p_diocese) then raise exception 'not_member'; end if;
  if nullif(trim(p_body), '') is null then raise exception 'empty'; end if;
  if p_recipient is not null and (p_recipient = auth.uid() or not public.is_admin_of(p_diocese, p_recipient)) then
    raise exception 'not_member';
  end if;
  insert into metro_messages (diocese_id, sender_id, recipient_id, body)
  values (p_diocese, auth.uid(), p_recipient, left(trim(p_body), 2000))
  returning * into r;
  delete from metro_messages where diocese_id = p_diocese and created_at < now() - interval '6 months';
  insert into metro_reads (user_id, diocese_id, thread, read_at)
  values (auth.uid(), p_diocese, coalesce(p_recipient::text, 'c'), now())
  on conflict (user_id, diocese_id, thread) do update set read_at = now();
  return r;
end;
$$;

create or replace function public.metro_chat_read(p_diocese uuid, p_thread text)
returns void language sql security definer set search_path = public, extensions as $$
  insert into metro_reads (user_id, diocese_id, thread, read_at) values (auth.uid(), p_diocese, p_thread, now())
  on conflict (user_id, diocese_id, thread) do update set read_at = now();
$$;

create or replace function public.metro_chat_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  r metro_messages;
begin
  select * into r from metro_messages where id = p_id;
  if not found then return; end if;
  if not (r.sender_id = auth.uid() or (r.recipient_id is null and public.is_metropolitan_of(r.diocese_id))) then
    raise exception 'not_allowed';
  end if;
  delete from metro_messages where id = p_id;
end;
$$;

revoke execute on function public.is_admin_of(uuid, uuid) from public, anon;
revoke execute on function public.staff_set(uuid, text, uuid, text) from public, anon;
revoke execute on function public.metro_chat_send(uuid, uuid, text) from public, anon;
revoke execute on function public.metro_chat_read(uuid, text) from public, anon;
revoke execute on function public.metro_chat_delete(uuid) from public, anon;
grant execute on function public.is_admin_of(uuid, uuid) to authenticated;
grant execute on function public.staff_set(uuid, text, uuid, text) to authenticated;
grant execute on function public.metro_chat_send(uuid, uuid, text) to authenticated;
grant execute on function public.metro_chat_read(uuid, text) to authenticated;
grant execute on function public.metro_chat_delete(uuid) to authenticated;
grant select on public.metro_messages, public.metro_reads to authenticated;

-- Хората в администрацията (за чата) – виждат ги само членовете ѝ.
create or replace function public.metro_admin_people(p_diocese uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not (public.is_admin_of(p_diocese) or public.is_creator()) then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'user_id', s.user_id, 'name', p.full_name, 'rank', p.rank, 'role', s.role, 'title', s.title)
      order by case s.role when 'metropolitan' then 0 when 'secretary' then 1 when 'protosyngel' then 2 else 3 end,
               p.full_name)
    from diocese_staff s join profiles p on p.id = s.user_id
    where s.diocese_id = p_diocese and s.role in ('metropolitan', 'secretary', 'protosyngel', 'employee')), '[]'::jsonb);
end;
$$;
revoke execute on function public.metro_admin_people(uuid) from public, anon;
grant execute on function public.metro_admin_people(uuid) to authenticated;

-- Служител по потребителско име (служителите обикновено не са в храм, затова
-- не се виждат в изгледа „Епархия“). Трябва да е от същата епархия.
create or replace function public.staff_add_employee(p_diocese uuid, p_username text, p_title text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  u uuid;
begin
  if not (public.is_creator() or public.is_metropolitan_of(p_diocese)) then raise exception 'forbidden'; end if;
  select id into u from profiles where username = lower(trim(coalesce(p_username, '')));
  if u is null then raise exception 'user_not_found'; end if;
  if (select diocese_id from profiles where id = u) is distinct from p_diocese then raise exception 'other_diocese'; end if;
  perform public.staff_set(u, 'employee', null, p_title);
  return u;
end;
$$;
revoke execute on function public.staff_add_employee(uuid, text, text) from public, anon;
grant execute on function public.staff_add_employee(uuid, text, text) to authenticated;

-- Назначаване по потребителско име – и за секретар/протосингел, които може
-- да са цивилни (без храм, затова ги няма в изгледа „Епархия“).
create or replace function public.staff_add(p_diocese uuid, p_username text, p_role text, p_title text default null)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  u uuid;
begin
  if p_role not in ('secretary', 'protosyngel', 'employee') then raise exception 'bad_role'; end if;
  if not (public.is_creator() or public.is_metropolitan_of(p_diocese)) then raise exception 'forbidden'; end if;
  select id into u from profiles where username = lower(trim(coalesce(p_username, '')));
  if u is null then raise exception 'user_not_found'; end if;
  if (select diocese_id from profiles where id = u) is distinct from p_diocese then raise exception 'other_diocese'; end if;
  perform public.staff_set(u, p_role, null, p_title);
  return u;
end;
$$;
revoke execute on function public.staff_add(uuid, text, text, text) from public, anon;
grant execute on function public.staff_add(uuid, text, text, text) to authenticated;
