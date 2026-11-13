-- =====================================================================
-- График на дежурствата.
--  * Председателят задава дежурства: свещеник + начало и край (ръчно –
--    всеки храм сменя в различен ден), поотделно или серия по ред.
--  * Вижда ги целият храм; датите в календара са в цвета на дежурния.
--  * Размяна: свещеникът предлага → колегата приема → председателят
--    одобрява (ако единият от двамата е председател – стига съгласието).
--  * Всяка промяна оставя ред в duty_log – от него сървърът пише известието.
-- =====================================================================

create table public.duties (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references public.churches (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  start_date  date not null,
  end_date    date not null,
  note        text check (char_length(note) <= 200),
  created_by  uuid references auth.users (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  check (end_date >= start_date and end_date - start_date <= 62)
);
create index duties_church_idx on public.duties (church_id, start_date);
alter table public.duties enable row level security;
create policy duties_select on public.duties for select to authenticated
  using (public.is_member(church_id));

create table public.duty_log (
  id          bigint generated always as identity primary key,
  church_id   uuid not null,
  user_id     uuid not null,
  kind        text not null check (kind in ('assigned', 'removed', 'changed')),
  start_date  date not null,
  end_date    date not null,
  by_user     uuid,
  at          timestamptz not null default now()
);
alter table public.duty_log enable row level security;
revoke all on public.duty_log from anon, authenticated;

create table public.duty_swaps (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid not null references public.churches (id) on delete cascade,
  from_duty   uuid not null references public.duties (id) on delete cascade,
  to_duty     uuid not null references public.duties (id) on delete cascade,
  from_user   uuid not null references auth.users (id) on delete cascade,
  to_user     uuid not null references auth.users (id) on delete cascade,
  note        text check (char_length(note) <= 300),
  status      text not null default 'peer' check (status in ('peer', 'chair', 'approved', 'rejected', 'cancelled')),
  peer_at     timestamptz,
  decided_by  uuid references auth.users (id) on delete set null,
  decided_at  timestamptz,
  reason      text check (char_length(reason) <= 300),
  created_at  timestamptz not null default now()
);
create index duty_swaps_church_idx on public.duty_swaps (church_id, created_at);
alter table public.duty_swaps enable row level security;
create policy duty_swaps_select on public.duty_swaps for select to authenticated
  using (from_user = auth.uid() or to_user = auth.uid() or public.is_manager(church_id));

-- ------------------------------------------------------------ помощни
create or replace function public.duty_today()
returns date language sql stable as $$ select (now() at time zone 'Europe/Sofia')::date $$;

create or replace function public.duty_check(p_church uuid, p_user uuid, p_start date, p_end date, p_except uuid)
returns void language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if p_start is null or p_end is null or p_end < p_start then raise exception 'bad_dates'; end if;
  if p_end - p_start > 62 then raise exception 'duty_too_long'; end if;
  if not exists (select 1 from church_members where church_id = p_church and user_id = p_user and status = 'active') then
    raise exception 'not_member';
  end if;
  if exists (select 1 from duties where church_id = p_church and id is distinct from p_except
              and start_date <= p_end and end_date >= p_start) then
    raise exception 'duty_overlap';
  end if;
end;
$$;

create or replace function public.duty_log_add(p_church uuid, p_user uuid, p_kind text, p_start date, p_end date)
returns jsonb language sql security definer set search_path = public, extensions as $$
  insert into duty_log (church_id, user_id, kind, start_date, end_date, by_user)
  values (p_church, p_user, p_kind, p_start, p_end, auth.uid())
  returning jsonb_build_object('log_id', id, 'user_id', user_id);
$$;
revoke execute on function public.duty_check(uuid, uuid, date, date, uuid) from public, anon, authenticated;
revoke execute on function public.duty_log_add(uuid, uuid, text, date, date) from public, anon, authenticated;

-- ------------------------------------------------------------ дежурства
-- Връщат списък {log_id, user_id} – за известията.
create or replace function public.duty_add(p_church uuid, p_user uuid, p_start date, p_end date, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_manager(p_church) then raise exception 'not_manager'; end if;
  perform duty_check(p_church, p_user, p_start, p_end, null);
  insert into duties (church_id, user_id, start_date, end_date, note)
  values (p_church, p_user, p_start, p_end, left(nullif(trim(p_note), ''), 200));
  return jsonb_build_array(duty_log_add(p_church, p_user, 'assigned', p_start, p_end));
end;
$$;

create or replace function public.duty_update(p_duty uuid, p_user uuid, p_start date, p_end date, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  d duties;
  res jsonb := '[]'::jsonb;
begin
  select * into d from duties where id = p_duty for update;
  if not found then raise exception 'not_found'; end if;
  if not public.is_manager(d.church_id) then raise exception 'not_manager'; end if;
  perform duty_check(d.church_id, p_user, p_start, p_end, d.id);
  update duties set user_id = p_user, start_date = p_start, end_date = p_end,
                    note = left(nullif(trim(p_note), ''), 200)
   where id = p_duty;
  if p_user <> d.user_id then
    res := res || duty_log_add(d.church_id, d.user_id, 'removed', d.start_date, d.end_date)
               || duty_log_add(d.church_id, p_user, 'assigned', p_start, p_end);
    -- Отворени размени за това дежурство отпадат.
    update duty_swaps set status = 'cancelled' where (from_duty = p_duty or to_duty = p_duty) and status in ('peer', 'chair');
  elsif p_start <> d.start_date or p_end <> d.end_date then
    res := res || duty_log_add(d.church_id, p_user, 'changed', p_start, p_end);
  end if;
  return res;
end;
$$;

create or replace function public.duty_delete(p_duty uuid)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  d duties;
begin
  select * into d from duties where id = p_duty for update;
  if not found then raise exception 'not_found'; end if;
  if not public.is_manager(d.church_id) then raise exception 'not_manager'; end if;
  delete from duties where id = p_duty;
  if d.end_date < duty_today() then return '[]'::jsonb; end if; -- минало – без известие
  return jsonb_build_array(duty_log_add(d.church_id, d.user_id, 'removed', d.start_date, d.end_date));
end;
$$;

-- Серия: от p_start, по p_days дни, свещениците по ред, p_count пъти.
create or replace function public.duty_series(p_church uuid, p_start date, p_days integer, p_users uuid[], p_count integer)
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare
  res jsonb := '[]'::jsonb;
  i integer;
  s date;
  u uuid;
  n integer := coalesce(array_length(p_users, 1), 0);
begin
  if not public.is_manager(p_church) then raise exception 'not_manager'; end if;
  if p_days is null or p_days < 1 or p_days > 31 then raise exception 'bad_dates'; end if;
  if n = 0 or p_count is null or p_count < 1 or p_count > 104 then raise exception 'bad_series'; end if;
  for i in 0 .. p_count - 1 loop
    s := p_start + i * p_days;
    u := p_users[(i % n) + 1];
    perform duty_check(p_church, u, s, s + p_days - 1, null);
    insert into duties (church_id, user_id, start_date, end_date) values (p_church, u, s, s + p_days - 1);
    res := res || duty_log_add(p_church, u, 'assigned', s, s + p_days - 1);
  end loop;
  return res;
end;
$$;

-- ------------------------------------------------------------ размени
create or replace function public.duty_swap_apply(p_swap uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  w duty_swaps;
begin
  select * into w from duty_swaps where id = p_swap;
  update duties set user_id = w.to_user where id = w.from_duty;
  update duties set user_id = w.from_user where id = w.to_duty;
  update duty_swaps set status = 'approved', decided_by = auth.uid(), decided_at = now() where id = p_swap;
  update duty_swaps set status = 'cancelled'
   where id <> p_swap and status in ('peer', 'chair')
     and (from_duty in (w.from_duty, w.to_duty) or to_duty in (w.from_duty, w.to_duty));
end;
$$;
revoke execute on function public.duty_swap_apply(uuid) from public, anon, authenticated;

create or replace function public.duty_swap_request(p_from uuid, p_to uuid, p_note text default null)
returns public.duty_swaps language plpgsql security definer set search_path = public, extensions as $$
declare
  a duties;
  b duties;
  r duty_swaps;
begin
  select * into a from duties where id = p_from;
  select * into b from duties where id = p_to;
  if a.id is null or b.id is null then raise exception 'not_found'; end if;
  if a.user_id <> auth.uid() then raise exception 'not_yours'; end if;
  if a.church_id <> b.church_id or b.user_id = a.user_id then raise exception 'bad_swap'; end if;
  if a.end_date < duty_today() or b.end_date < duty_today() then raise exception 'duty_past'; end if;
  if exists (select 1 from duty_swaps where status in ('peer', 'chair')
              and (from_duty in (p_from, p_to) or to_duty in (p_from, p_to))) then
    raise exception 'swap_exists';
  end if;
  insert into duty_swaps (church_id, from_duty, to_duty, from_user, to_user, note)
  values (a.church_id, p_from, p_to, a.user_id, b.user_id, left(nullif(trim(p_note), ''), 300))
  returning * into r;
  return r;
end;
$$;

-- Колегата отговаря. Ако единият е председател – съгласието стига.
create or replace function public.duty_swap_peer(p_swap uuid, p_accept boolean)
returns public.duty_swaps language plpgsql security definer set search_path = public, extensions as $$
declare
  w duty_swaps;
begin
  select * into w from duty_swaps where id = p_swap for update;
  if not found then raise exception 'not_found'; end if;
  if w.to_user <> auth.uid() then raise exception 'not_yours'; end if;
  if w.status <> 'peer' then raise exception 'not_pending'; end if;
  if not p_accept then
    update duty_swaps set status = 'rejected', peer_at = now() where id = p_swap returning * into w;
    return w;
  end if;
  update duty_swaps set peer_at = now() where id = p_swap;
  if public.is_manager(w.church_id)
     or exists (select 1 from church_members where church_id = w.church_id and user_id = w.from_user
                  and role = 'manager' and status = 'active') then
    perform duty_swap_apply(p_swap);
  else
    update duty_swaps set status = 'chair' where id = p_swap;
  end if;
  select * into w from duty_swaps where id = p_swap;
  return w;
end;
$$;

create or replace function public.duty_swap_decide(p_swap uuid, p_approve boolean, p_reason text default null)
returns public.duty_swaps language plpgsql security definer set search_path = public, extensions as $$
declare
  w duty_swaps;
begin
  select * into w from duty_swaps where id = p_swap for update;
  if not found then raise exception 'not_found'; end if;
  if not public.is_manager(w.church_id) then raise exception 'not_manager'; end if;
  if w.status <> 'chair' then raise exception 'not_pending'; end if;
  update duty_swaps set reason = left(nullif(trim(p_reason), ''), 300) where id = p_swap;
  if p_approve then
    perform duty_swap_apply(p_swap);
  else
    update duty_swaps set status = 'rejected', decided_by = auth.uid(), decided_at = now() where id = p_swap;
  end if;
  select * into w from duty_swaps where id = p_swap;
  return w;
end;
$$;

create or replace function public.duty_swap_cancel(p_swap uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  w duty_swaps;
begin
  select * into w from duty_swaps where id = p_swap for update;
  if not found then raise exception 'not_found'; end if;
  if w.from_user <> auth.uid() then raise exception 'not_yours'; end if;
  if w.status not in ('peer', 'chair') then raise exception 'not_pending'; end if;
  update duty_swaps set status = 'cancelled' where id = p_swap;
end;
$$;

revoke execute on function public.duty_add(uuid, uuid, date, date, text) from public, anon;
revoke execute on function public.duty_update(uuid, uuid, date, date, text) from public, anon;
revoke execute on function public.duty_delete(uuid) from public, anon;
revoke execute on function public.duty_series(uuid, date, integer, uuid[], integer) from public, anon;
revoke execute on function public.duty_swap_request(uuid, uuid, text) from public, anon;
revoke execute on function public.duty_swap_peer(uuid, boolean) from public, anon;
revoke execute on function public.duty_swap_decide(uuid, boolean, text) from public, anon;
revoke execute on function public.duty_swap_cancel(uuid) from public, anon;
grant execute on function public.duty_add(uuid, uuid, date, date, text) to authenticated;
grant execute on function public.duty_update(uuid, uuid, date, date, text) to authenticated;
grant execute on function public.duty_delete(uuid) to authenticated;
grant execute on function public.duty_series(uuid, date, integer, uuid[], integer) to authenticated;
grant execute on function public.duty_swap_request(uuid, uuid, text) to authenticated;
grant execute on function public.duty_swap_peer(uuid, boolean) to authenticated;
grant execute on function public.duty_swap_decide(uuid, boolean, text) to authenticated;
grant execute on function public.duty_swap_cancel(uuid) to authenticated;
