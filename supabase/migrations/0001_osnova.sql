-- =====================================================================
-- Приложение за свещеници – основа (версия 1)
-- Профили, храмове, членство с код за присъединяване, събития.
-- Пуска се веднъж в Supabase: SQL Editor -> New query -> Run.
-- =====================================================================

create extension if not exists citext;
create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Профили (по един за всеки акаунт)
-- ---------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  username    citext not null unique
              check (username ~ '^[a-zA-Z0-9._-]{3,30}$'),
  full_name   text   not null check (char_length(full_name) between 2 and 120),
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Храмове. Различават се по уникален номер (id), не по име.
-- ---------------------------------------------------------------------
create table public.churches (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(name) between 2 and 120),
  settlement    text not null check (char_length(settlement) between 2 and 80),
  municipality  text not null check (char_length(municipality) between 2 and 80),
  join_code     text not null unique,
  created_by    uuid references auth.users (id) on delete set null,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Членство: кой свещеник в кой храм и с каква роля.
-- manager = председател, priest = свещеник
-- ---------------------------------------------------------------------
create table public.church_members (
  church_id  uuid not null references public.churches (id) on delete cascade,
  user_id    uuid not null references auth.users (id) on delete cascade,
  role       text not null default 'priest' check (role in ('manager', 'priest')),
  joined_at  timestamptz not null default now(),
  primary key (church_id, user_id)
);
create index church_members_user_idx on public.church_members (user_id);

-- ---------------------------------------------------------------------
-- Събития (календарът идва в стъпка 2, но моделът и правилата са тук,
-- защото личните събития трябва да са защитени от самото начало).
-- ---------------------------------------------------------------------
create table public.events (
  id               uuid primary key default gen_random_uuid(),
  owner_id         uuid not null default auth.uid()
                   references auth.users (id) on delete cascade,
  church_id        uuid not null references public.churches (id) on delete cascade,
  kind             text not null check (kind in
                   ('krashtene','venchavka','pogrebenie','panihida','vodosvet','sluzhba','izpoved','maslosvet','kurban','drugo')),
  starts_at        timestamptz not null,
  duration_minutes integer not null default 30 check (duration_minutes between 15 and 720),
  for_whom         text check (char_length(for_whom) <= 200),
  contact_phone    text check (char_length(contact_phone) <= 40),
  outside_church   boolean not null default false,
  address          text check (char_length(address) <= 300),
  remind_minutes   integer check (remind_minutes between 0 and 10080),
  alarm            boolean not null default false,
  visibility       text not null default 'private' check (visibility in ('private','church')),
  note             text check (char_length(note) <= 2000),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index events_owner_time_idx  on public.events (owner_id, starts_at);
create index events_church_time_idx on public.events (church_id, starts_at) where visibility = 'church';

-- ---------------------------------------------------------------------
-- Помощни функции (security definer, за да няма рекурсия в правилата)
-- ---------------------------------------------------------------------
create or replace function public.is_member(p_church uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from church_members
                 where church_id = p_church and user_id = auth.uid());
$$;

create or replace function public.is_manager(p_church uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from church_members
                 where church_id = p_church and user_id = auth.uid() and role = 'manager');
$$;

create or replace function public.shares_church_with(p_user uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from church_members a
                 join church_members b on b.church_id = a.church_id
                 where a.user_id = auth.uid() and b.user_id = p_user);
$$;

-- Код от 6 знака без лесни за бъркане символи (без 0/O, 1/I/L).
create or replace function public.new_join_code()
returns text language plpgsql volatile set search_path = public as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  code text;
  i int;
begin
  loop
    code := '';
    for i in 1..6 loop
      code := code || substr(alphabet, 1 + (get_byte(gen_random_bytes(1), 0) % length(alphabet)), 1);
    end loop;
    exit when not exists (select 1 from churches where join_code = code);
  end loop;
  return code;
end;
$$;

-- ---------------------------------------------------------------------
-- Профил се създава автоматично при регистрация
-- (името и потребителското име идват от данните при регистрация).
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, username, full_name)
  values (new.id,
          lower(trim(new.raw_user_meta_data ->> 'username')),
          trim(new.raw_user_meta_data ->> 'full_name'));
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Свободно ли е потребителското име (проверка преди регистрация)
create or replace function public.username_available(p_username text)
returns boolean language sql stable security definer set search_path = public as $$
  select not exists (select 1 from profiles where username = lower(trim(p_username)));
$$;

-- ---------------------------------------------------------------------
-- Действия с храм (извикват се от приложението)
-- ---------------------------------------------------------------------
create or replace function public.create_church(p_name text, p_settlement text, p_municipality text)
returns public.churches language plpgsql security definer set search_path = public as $$
declare
  c churches;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into churches (name, settlement, municipality, join_code, created_by)
  values (trim(p_name), trim(p_settlement), trim(p_municipality), new_join_code(), auth.uid())
  returning * into c;
  insert into church_members (church_id, user_id, role) values (c.id, auth.uid(), 'manager');
  return c;
end;
$$;

create or replace function public.join_church(p_code text)
returns public.churches language plpgsql security definer set search_path = public as $$
declare
  c churches;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into c from churches
   where join_code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if not found then raise exception 'invalid_code'; end if;
  insert into church_members (church_id, user_id, role)
  values (c.id, auth.uid(), 'priest')
  on conflict (church_id, user_id) do nothing;
  return c;
end;
$$;

create or replace function public.regenerate_join_code(p_church uuid)
returns text language plpgsql security definer set search_path = public as $$
declare
  code text;
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  code := new_join_code();
  update churches set join_code = code where id = p_church;
  return code;
end;
$$;

create or replace function public.remove_member(p_church uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  if p_user = auth.uid() then raise exception 'cannot_remove_self'; end if;
  delete from church_members where church_id = p_church and user_id = p_user;
end;
$$;

create or replace function public.leave_church(p_church uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if is_manager(p_church) and (select count(*) from church_members
       where church_id = p_church and role = 'manager') = 1
     and (select count(*) from church_members where church_id = p_church) > 1 then
    raise exception 'last_manager';
  end if;
  delete from church_members where church_id = p_church and user_id = auth.uid();
end;
$$;

-- ---------------------------------------------------------------------
-- Правила за достъп по ред (RLS)
-- ---------------------------------------------------------------------
alter table public.profiles       enable row level security;
alter table public.churches       enable row level security;
alter table public.church_members enable row level security;
alter table public.events         enable row level security;

-- Профили: своя и на свещениците от общ храм
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or public.shares_church_with(id));
create policy profiles_update on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

-- Храмове: виждат се само от членовете. Създаване и промени – само през функциите.
create policy churches_select on public.churches for select to authenticated
  using (public.is_member(id));

-- Членство: виждат се членовете на своите храмове
create policy members_select on public.church_members for select to authenticated
  using (public.is_member(church_id));

-- Събития: личните – само собственикът; споделените – и свещениците от храма
create policy events_select on public.events for select to authenticated
  using (owner_id = auth.uid()
         or (visibility = 'church' and public.is_member(church_id)));
create policy events_insert on public.events for insert to authenticated
  with check (owner_id = auth.uid() and public.is_member(church_id));
create policy events_update on public.events for update to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid() and public.is_member(church_id));
-- Изтрива собственикът; председателят – само споделени събития в своя храм
create policy events_delete on public.events for delete to authenticated
  using (owner_id = auth.uid()
         or (visibility = 'church' and public.is_manager(church_id)));

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at := now(); return new; end;
$$;
create trigger events_touch before update on public.events
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- Права: функциите са само за влезли потребители (освен проверката за име)
-- ---------------------------------------------------------------------
revoke execute on function public.create_church(text, text, text)  from public, anon;
revoke execute on function public.join_church(text)                from public, anon;
revoke execute on function public.regenerate_join_code(uuid)       from public, anon;
revoke execute on function public.remove_member(uuid, uuid)        from public, anon;
revoke execute on function public.leave_church(uuid)               from public, anon;
revoke execute on function public.new_join_code()                  from public, anon, authenticated;
revoke execute on function public.handle_new_user()                from public, anon, authenticated;

grant execute on function public.create_church(text, text, text)  to authenticated;
grant execute on function public.join_church(text)                to authenticated;
grant execute on function public.regenerate_join_code(uuid)       to authenticated;
grant execute on function public.remove_member(uuid, uuid)        to authenticated;
grant execute on function public.leave_church(uuid)               to authenticated;
grant execute on function public.username_available(text)        to anon, authenticated;
