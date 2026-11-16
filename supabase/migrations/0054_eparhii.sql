-- Епархии и духовни околии. Всеки храм е в една епархия и една околия
-- (или в „епархийския център“ – отделен раздел, напр. „Стара Загора“).
-- Всеки човек е в една епархия; не може да влезе в храм от чужда.
-- Служебната епархия „Тест“ не се показва при регистрация.

create table public.dioceses (
  id     uuid primary key default gen_random_uuid(),
  name   text not null unique,
  sort   int  not null default 0,
  hidden boolean not null default false
);

create table public.vicariates (
  id         uuid primary key default gen_random_uuid(),
  diocese_id uuid not null references public.dioceses (id) on delete cascade,
  name       text not null check (char_length(btrim(name)) between 2 and 80),
  is_center  boolean not null default false,
  sort       int not null default 0,
  unique (diocese_id, name)
);
create index vicariates_diocese_idx on public.vicariates (diocese_id);

alter table public.dioceses enable row level security;
alter table public.vicariates enable row level security;
-- Списъците са публични (нужни още при регистрация); пише се само през функции.
create policy dioceses_read on public.dioceses for select to anon, authenticated using (true);
create policy vicariates_read on public.vicariates for select to anon, authenticated using (true);
revoke insert, update, delete on public.dioceses, public.vicariates from anon, authenticated;
grant select on public.dioceses, public.vicariates to anon, authenticated;

alter table public.churches
  add column diocese_id   uuid references public.dioceses (id),
  add column vicariate_id uuid references public.vicariates (id) on delete set null;
alter table public.profiles
  add column diocese_id uuid references public.dioceses (id);

-- Епархиите на БПЦ и центровете им; околиите на Старозагорска и Пловдивска.
do $$
declare
  d uuid;
  r record;
  v text;
  i int;
begin
  for r in select * from (values
      (1, 'Софийска епархия', 'София', false),
      (2, 'Пловдивска епархия', 'Пловдив', false),
      (3, 'Варненска и Великопреславска епархия', 'Варна', false),
      (4, 'Великотърновска епархия', 'Велико Търново', false),
      (5, 'Видинска епархия', 'Видин', false),
      (6, 'Врачанска епархия', 'Враца', false),
      (7, 'Доростолска епархия', 'Силистра', false),
      (8, 'Ловчанска епархия', 'Ловеч', false),
      (9, 'Неврокопска епархия', 'Гоце Делчев', false),
      (10, 'Плевенска епархия', 'Плевен', false),
      (11, 'Русенска епархия', 'Русе', false),
      (12, 'Сливенска епархия', 'Сливен', false),
      (13, 'Старозагорска епархия', 'Стара Загора', false),
      (14, 'Западно- и Средноевропейска епархия', 'Берлин', false),
      (15, 'Американска, Канадска и Австралийска епархия', 'Ню Йорк', false),
      (99, 'Тест', 'Тест', true)
    ) as t(sort, name, center, hidden)
  loop
    insert into dioceses (name, sort, hidden) values (r.name, r.sort, r.hidden) returning id into d;
    insert into vicariates (diocese_id, name, is_center, sort) values (d, r.center, true, 0);
    i := 0;
    foreach v in array case r.name
        when 'Старозагорска епархия' then array['Казанлъшка', 'Новозагорска', 'Свиленградска', 'Харманлийска', 'Чирпанска']
        when 'Пловдивска епархия' then array['Асеновградска', 'Ивайловградска', 'Карловска', 'Пазарджишка',
                                             'Панагюрска', 'Пещерска', 'Смолянска', 'Хасковска']
        when 'Тест' then array['Тестова']
        else array[]::text[] end
    loop
      i := i + 1;
      insert into vicariates (diocese_id, name, sort) values (d, v || ' духовна околия', i);
    end loop;
  end loop;
end $$;

-- Всичко досегашно е в „Тест“.
update public.profiles set diocese_id = (select id from dioceses where name = 'Тест');
update public.churches set diocese_id = (select id from dioceses where name = 'Тест'),
  vicariate_id = (select v.id from vicariates v join dioceses d on d.id = v.diocese_id
                   where d.name = 'Тест' and v.is_center);

-- Нов профил: епархията идва от регистрацията (скритите не се приемат).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  d uuid;
begin
  begin
    d := nullif(new.raw_user_meta_data ->> 'diocese_id', '')::uuid;
  exception when others then d := null;
  end;
  if d is not null and not exists (select 1 from dioceses where id = d and not hidden) then d := null; end if;
  insert into profiles (id, username, full_name, diocese_id)
  values (new.id,
          lower(trim(new.raw_user_meta_data ->> 'username')),
          trim(new.raw_user_meta_data ->> 'full_name'),
          d);
  return new;
end;
$$;

-- Нов храм: в епархията на създателя (стари версии на приложението не я
-- подават), околия по подразбиране – епархийският център.
create or replace function public.churches_place_default()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if new.diocese_id is null then
    select diocese_id into new.diocese_id from profiles where id = coalesce(new.created_by, auth.uid());
  end if;
  if new.diocese_id is null then
    select id into new.diocese_id from dioceses where name = 'Тест';
  end if;
  if new.vicariate_id is null then
    select id into new.vicariate_id from vicariates where diocese_id = new.diocese_id and is_center limit 1;
  end if;
  return new;
end;
$$;
create trigger churches_place_default before insert on public.churches
  for each row execute function public.churches_place_default();

-- Пазач: човек влиза само в храм от своята епархия. Без епархия (стара
-- версия при регистрация) – поема епархията на храма. Създателят – навсякъде.
create or replace function public.members_same_diocese()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  cd uuid;
  ud uuid;
begin
  if exists (select 1 from app_creators where user_id = new.user_id) then return new; end if;
  select diocese_id into cd from churches where id = new.church_id;
  select diocese_id into ud from profiles where id = new.user_id;
  if cd is null then return new; end if;
  if ud is null then
    update profiles set diocese_id = cd where id = new.user_id;
  elsif ud <> cd then
    raise exception 'other_diocese';
  end if;
  return new;
end;
$$;
create trigger members_same_diocese before insert on public.church_members
  for each row execute function public.members_same_diocese();

-- Околията на храма: председателят (в своята епархия) или създателят.
-- Създателят може да премести храма и в друга епархия, ако никой от членовете
-- не е от трета.
create or replace function public.church_set_vicariate(p_church uuid, p_vicariate uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  vd uuid;
  cd uuid;
  vname text;
begin
  if not (public.is_manager(p_church) or public.is_creator()) then raise exception 'not_manager'; end if;
  select diocese_id, name into vd, vname from vicariates where id = p_vicariate;
  if vd is null then raise exception 'not_found'; end if;
  select diocese_id into cd from churches where id = p_church;
  if cd is distinct from vd then
    if not public.is_creator() then raise exception 'other_diocese'; end if;
    if exists (select 1 from church_members m join profiles p on p.id = m.user_id
                where m.church_id = p_church and p.diocese_id is not null and p.diocese_id <> vd
                  and not exists (select 1 from app_creators a where a.user_id = m.user_id)) then
      raise exception 'members_other_diocese';
    end if;
  end if;
  update churches set diocese_id = vd, vicariate_id = p_vicariate where id = p_church;
  perform log_act(p_church, null, 'Околия на храма', vname);
end;
$$;

-- Създателят сменя епархията на човек: той напуска храмовете от старата
-- (не може, ако е председател там – първо се сменя председателят).
create or replace function public.creator_set_user_diocese(p_user uuid, p_diocese uuid)
returns int language plpgsql security definer set search_path = public, extensions as $$
declare
  n int;
  dname text;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  select name into dname from dioceses where id = p_diocese;
  if dname is null then raise exception 'not_found'; end if;
  if exists (select 1 from church_members m join churches c on c.id = m.church_id
              where m.user_id = p_user and m.role = 'manager' and c.diocese_id <> p_diocese) then
    raise exception 'is_chair';
  end if;
  delete from church_members m using churches c
   where c.id = m.church_id and m.user_id = p_user and c.diocese_id <> p_diocese;
  get diagnostics n = row_count;
  update profiles set diocese_id = p_diocese where id = p_user;
  insert into activity_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user, 'Смени епархия', dname || case when n > 0 then ' · напусна ' || n || ' храм(а)' else '' end);
  return n;
end;
$$;

-- Създателят добавя или преименува околия.
create or replace function public.creator_vicariate_save(p_diocese uuid, p_id uuid, p_name text)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  nm text := btrim(regexp_replace(coalesce(p_name, ''), '\s+', ' ', 'g'));
  vid uuid;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  if char_length(nm) < 2 then raise exception 'bad_name'; end if;
  if p_id is null then
    insert into vicariates (diocese_id, name, sort)
    values (p_diocese, nm, coalesce((select max(sort) + 1 from vicariates where diocese_id = p_diocese), 1))
    returning id into vid;
  else
    update vicariates set name = nm where id = p_id returning id into vid;
    if vid is null then raise exception 'not_found'; end if;
  end if;
  return vid;
exception when unique_violation then
  raise exception 'name_taken';
end;
$$;

revoke execute on function public.churches_place_default() from public, anon, authenticated;
revoke execute on function public.members_same_diocese() from public, anon, authenticated;
revoke execute on function public.church_set_vicariate(uuid, uuid) from public, anon;
revoke execute on function public.creator_set_user_diocese(uuid, uuid) from public, anon;
revoke execute on function public.creator_vicariate_save(uuid, uuid, text) from public, anon;
grant execute on function public.church_set_vicariate(uuid, uuid) to authenticated;
grant execute on function public.creator_set_user_diocese(uuid, uuid) to authenticated;
grant execute on function public.creator_vicariate_save(uuid, uuid, text) to authenticated;

-- Прегледът на храма за създателя – и с епархията и околията.
create or replace function public.creator_church_summary(p_church uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'name', (select name from churches where id = p_church),
    'address', (select address from churches where id = p_church),
    'bulstat', (select bulstat from churches where id = p_church),
    'diocese_id', (select diocese_id from churches where id = p_church),
    'vicariate_id', (select vicariate_id from churches where id = p_church),
    'members', (select count(*) from church_members where church_id = p_church),
    'events', (select count(*) from events where church_id = p_church),
    'cash', (select count(*) from cash_entries where church_id = p_church),
    'stock', (select count(*) from stock_moves where church_id = p_church),
    'chat', (select count(*) from chat_messages where church_id = p_church));
end;
$$;
