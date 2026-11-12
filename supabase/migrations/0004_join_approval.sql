-- =====================================================================
-- Одобрение от председателя
-- Свещеник, който се присъедини с кода, чака одобрение (status = 'pending').
-- Докато чака, не вижда нищо от храма. Председателят одобрява или отказва.
-- Досегашните членове остават одобрени.
-- =====================================================================

alter table public.church_members
  add column status text not null default 'active' check (status in ('pending', 'active'));

-- Само одобрените са членове.
create or replace function public.is_member(p_church uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from church_members
                 where church_id = p_church and user_id = auth.uid() and status = 'active');
$$;

create or replace function public.is_manager(p_church uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from church_members
                 where church_id = p_church and user_id = auth.uid()
                   and role = 'manager' and status = 'active');
$$;

create or replace function public.is_member_user(p_church uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from church_members
                 where church_id = p_church and user_id = p_user and status = 'active');
$$;

-- Профилите: виждам одобрените си колеги, а председателят вижда и чакащите.
create or replace function public.shares_church_with(p_user uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from church_members me
    join church_members other on other.church_id = me.church_id
    where me.user_id = auth.uid() and me.status = 'active' and other.user_id = p_user
      and (other.status = 'active' or me.role = 'manager'));
$$;

-- Има ли текущият потребител запис (и чакащ) в храма.
create or replace function public.has_membership(p_church uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from church_members where church_id = p_church and user_id = auth.uid());
$$;

-- Чакащият вижда своя запис и името на храма (за екрана „Чака одобрение“).
drop policy members_select on public.church_members;
create policy members_select on public.church_members for select to authenticated
  using (user_id = auth.uid() or public.is_member(church_id));

drop policy churches_select on public.churches;
create policy churches_select on public.churches for select to authenticated
  using (public.has_membership(id));

-- (Чакащият вижда и кода на храма, но той вече го знае – въвел го е.)

-- Присъединяване: чакащ запис.
create or replace function public.join_church(p_code text)
returns public.churches language plpgsql security definer set search_path = public, extensions as $$
declare
  c churches;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select * into c from churches
   where join_code = upper(regexp_replace(p_code, '[^A-Za-z0-9]', '', 'g'));
  if not found then raise exception 'invalid_code'; end if;
  insert into church_members (church_id, user_id, role, status)
  values (c.id, auth.uid(), 'priest', 'pending')
  on conflict (church_id, user_id) do nothing;
  return c;
end;
$$;

create or replace function public.approve_member(p_church uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  update church_members set status = 'active', joined_at = now()
   where church_id = p_church and user_id = p_user and status = 'pending';
end;
$$;

-- Отказ = премахване на чакащия запис (remove_member върши същото).

revoke execute on function public.approve_member(uuid, uuid) from public, anon;
grant execute on function public.approve_member(uuid, uuid) to authenticated;

-- ---------------------------------------------------------------------
-- Профил: собственото име може да се сменя (вече има правило за update).
-- Полета за по-късно (рожден ден, ръкоположение, снимка) ще дойдат тук.
-- ---------------------------------------------------------------------
