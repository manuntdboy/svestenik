-- =====================================================================
-- Почивки: свещеникът заявява, председателят одобрява или отказва.
-- Заявките вижда заявилият и председателят; одобрените – целият храм.
-- На свещеник в одобрена почивка колега не може да запише събитие.
-- =====================================================================

create table public.leave_requests (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references public.churches (id) on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  start_date  date not null,
  end_date    date not null,
  note        text check (char_length(note) <= 500),
  status      text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  decided_by  uuid references auth.users (id) on delete set null,
  decided_at  timestamptz,
  created_at  timestamptz not null default now(),
  check (end_date >= start_date and end_date - start_date <= 366)
);
create index leave_requests_church_idx on public.leave_requests (church_id, start_date);

alter table public.leave_requests enable row level security;

create policy leave_select on public.leave_requests for select to authenticated
  using (user_id = auth.uid()
         or public.is_manager(church_id)
         or (status = 'approved' and public.is_member(church_id)));

-- Нова заявка: само за себе си, в своя храм; винаги започва като „чака“.
create policy leave_insert on public.leave_requests for insert to authenticated
  with check (user_id = auth.uid() and public.is_member(church_id));

-- Заявилият оттегля своята чакаща заявка.
create policy leave_delete_own on public.leave_requests for delete to authenticated
  using (user_id = auth.uid() and status = 'pending');

create or replace function public.leave_guard()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if coalesce(current_setting('kairos.leave', true), '') = 'on' then return new; end if;
  if tg_op = 'INSERT' then
    new.status := 'pending';
    new.decided_by := null;
    new.decided_at := null;
  end if;
  return new;
end;
$$;
create trigger leave_guard before insert on public.leave_requests
  for each row execute function public.leave_guard();

-- Председателят решава заявката.
create or replace function public.decide_leave(p_request uuid, p_approve boolean)
returns public.leave_requests language plpgsql security definer set search_path = public, extensions as $$
declare
  r leave_requests;
begin
  select * into r from leave_requests where id = p_request for update;
  if not found then raise exception 'not_found'; end if;
  if not is_manager(r.church_id) then raise exception 'not_manager'; end if;
  perform set_config('kairos.leave', 'on', true);
  update leave_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now()
   where id = p_request returning * into r;
  perform set_config('kairos.leave', 'off', true);
  return r;
end;
$$;

-- Председателят може да отмени (изтрие) всяка заявка, вкл. одобрена.
create or replace function public.cancel_leave(p_request uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  r leave_requests;
begin
  select * into r from leave_requests where id = p_request;
  if not found then return; end if;
  if not (is_manager(r.church_id) or (r.user_id = auth.uid() and r.status = 'pending')) then
    raise exception 'not_allowed';
  end if;
  delete from leave_requests where id = p_request;
end;
$$;

-- В одобрена почивка ли е свещеникът на тази дата (в този храм).
create or replace function public.is_on_leave(p_church uuid, p_user uuid, p_day date)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from leave_requests
                 where church_id = p_church and user_id = p_user and status = 'approved'
                   and p_day between start_date and end_date);
$$;

-- Колега не може да запише събитие за свещеник в почивка.
create or replace function public.events_leave_guard()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.assignee_id <> auth.uid()
     and (tg_op = 'INSERT' or new.assignee_id is distinct from old.assignee_id
          or (new.starts_at at time zone 'Europe/Sofia')::date
             <> (old.starts_at at time zone 'Europe/Sofia')::date)
     and is_on_leave(new.church_id, new.assignee_id, (new.starts_at at time zone 'Europe/Sofia')::date) then
    raise exception 'assignee_on_leave';
  end if;
  return new;
end;
$$;
create trigger events_leave_guard before insert or update on public.events
  for each row execute function public.events_leave_guard();

revoke execute on function public.decide_leave(uuid, boolean) from public, anon;
revoke execute on function public.cancel_leave(uuid) from public, anon;
revoke execute on function public.is_on_leave(uuid, uuid, date) from public, anon;
grant execute on function public.decide_leave(uuid, boolean) to authenticated;
grant execute on function public.cancel_leave(uuid) to authenticated;
grant execute on function public.is_on_leave(uuid, uuid, date) to authenticated;
