-- Кабинетът на владиката:
--  * „Повикай“ – митрополитът вика служител(и) от администрацията; те
--    отговарят „Идвам“ или „Не мога“.
--  * Календар на владиката – записват митрополитът и секретарят; записите
--    „само за мен“ вижда само митрополитът.
--  * Храм от епархията – адрес, Булстат и графикът на дежурствата (без
--    службите, почивките, касата и склада).

create or replace function public.is_secretary_of(p_diocese uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from diocese_staff where diocese_id = p_diocese and user_id = auth.uid()
                  and role = 'secretary');
$$;

-- ------------------------------------------------------------ повикване
create table public.metro_calls (
  id          uuid primary key default gen_random_uuid(),
  diocese_id  uuid not null references public.dioceses (id) on delete cascade,
  caller_id   uuid references auth.users (id) on delete set null,
  callee_id   uuid not null references auth.users (id) on delete cascade,
  note        text check (char_length(note) <= 200),
  answer      text check (answer in ('coming', 'cannot')),
  answered_at timestamptz,
  created_at  timestamptz not null default now()
);
create index metro_calls_callee_idx on public.metro_calls (callee_id, created_at);
create index metro_calls_caller_idx on public.metro_calls (caller_id, created_at);
alter table public.metro_calls enable row level security;
create policy metro_calls_select on public.metro_calls for select to authenticated
  using (caller_id = auth.uid() or callee_id = auth.uid());
revoke insert, update, delete on public.metro_calls from anon, authenticated;
grant select on public.metro_calls to authenticated;

-- Само митрополитът вика – и само хора от администрацията на своята епархия.
create or replace function public.metro_call(p_users uuid[], p_note text default null)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  d uuid;
  u uuid;
  n text := nullif(btrim(coalesce(p_note, '')), '');
  ids uuid[] := '{}';
  nid uuid;
begin
  select diocese_id into d from diocese_staff where user_id = auth.uid() and role = 'metropolitan' limit 1;
  if d is null then raise exception 'forbidden'; end if;
  if p_users is null or cardinality(p_users) = 0 then raise exception 'no_people'; end if;
  if cardinality(p_users) > 20 then raise exception 'too_many'; end if;
  if n is not null and char_length(n) > 200 then raise exception 'too_long'; end if;
  foreach u in array (select array_agg(distinct x) from unnest(p_users) x) loop
    if u = auth.uid() or not public.is_admin_of(d, u) then raise exception 'not_member'; end if;
    insert into metro_calls (diocese_id, caller_id, callee_id, note)
    values (d, auth.uid(), u, n) returning id into nid;
    ids := ids || nid;
  end loop;
  return ids;
end;
$$;

create or replace function public.metro_call_answer(p_id uuid, p_answer text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_answer not in ('coming', 'cannot') then raise exception 'bad_answer'; end if;
  update metro_calls set answer = p_answer, answered_at = now()
   where id = p_id and callee_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
end;
$$;

-- ------------------------------------------------------- календар на владиката
create table public.metro_events (
  id          uuid primary key default gen_random_uuid(),
  diocese_id  uuid not null references public.dioceses (id) on delete cascade,
  starts_at   timestamptz not null,
  ends_at     timestamptz,
  all_day     boolean not null default false,
  title       text not null check (char_length(title) between 1 and 150),
  place       text check (char_length(place) <= 200),
  note        text check (char_length(note) <= 1000),
  private     boolean not null default false,
  created_by  uuid references auth.users (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at)
);
create index metro_events_diocese_idx on public.metro_events (diocese_id, starts_at);
alter table public.metro_events enable row level security;
create policy metro_events_select on public.metro_events for select to authenticated
  using (public.is_metropolitan_of(diocese_id) or (not private and public.is_secretary_of(diocese_id)));
revoke insert, update, delete on public.metro_events from anon, authenticated;
grant select on public.metro_events to authenticated;

create or replace function public.metro_event_save(
  p_id uuid, p_diocese uuid, p_starts timestamptz, p_ends timestamptz, p_all_day boolean,
  p_title text, p_place text, p_note text, p_private boolean)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  metro boolean := public.is_metropolitan_of(p_diocese);
  t text := btrim(coalesce(p_title, ''));
  old metro_events;
  nid uuid;
begin
  if not (metro or public.is_secretary_of(p_diocese)) then raise exception 'forbidden'; end if;
  if t = '' then raise exception 'bad_name'; end if;
  if p_starts is null or (p_ends is not null and p_ends < p_starts) then raise exception 'bad_dates'; end if;
  if coalesce(p_private, false) and not metro then raise exception 'forbidden'; end if;
  if p_id is null then
    insert into metro_events (diocese_id, starts_at, ends_at, all_day, title, place, note, private)
    values (p_diocese, p_starts, p_ends, coalesce(p_all_day, false), t,
            nullif(btrim(coalesce(p_place, '')), ''), nullif(btrim(coalesce(p_note, '')), ''),
            coalesce(p_private, false))
    returning id into nid;
    return nid;
  end if;
  select * into old from metro_events where id = p_id and diocese_id = p_diocese;
  if old.id is null or (old.private and not metro) then raise exception 'not_found'; end if;
  update metro_events set starts_at = p_starts, ends_at = p_ends, all_day = coalesce(p_all_day, false),
         title = t, place = nullif(btrim(coalesce(p_place, '')), ''),
         note = nullif(btrim(coalesce(p_note, '')), ''), private = coalesce(p_private, false),
         updated_at = now()
   where id = p_id;
  return p_id;
end;
$$;

create or replace function public.metro_event_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  e metro_events;
begin
  select * into e from metro_events where id = p_id;
  if e.id is null then raise exception 'not_found'; end if;
  if not (public.is_metropolitan_of(e.diocese_id) or (not e.private and public.is_secretary_of(e.diocese_id))) then
    raise exception 'not_found';
  end if;
  delete from metro_events where id = p_id;
end;
$$;

-- ------------------------------------------------------- храм от епархията
-- Кой вижда храма „отгоре“: създателят, митрополитът и секретарят (цялата
-- епархия), протосингелът (центъра), наместникът (своята околия).
create or replace function public.can_view_church_from_diocese(p_church uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select public.is_creator() or exists (
    select 1 from churches c join diocese_staff s on s.diocese_id = c.diocese_id and s.user_id = auth.uid()
     where c.id = p_church and (
       s.role in ('metropolitan', 'secretary')
       or (s.role = 'vicar' and s.vicariate_id = c.vicariate_id)
       or (s.role = 'protosyngel' and exists (select 1 from vicariates v where v.id = c.vicariate_id and v.is_center))));
$$;

create or replace function public.diocese_church(p_church uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.can_view_church_from_diocese(p_church) then raise exception 'forbidden'; end if;
  return (select jsonb_build_object(
      'id', c.id, 'name', c.name, 'settlement', c.settlement, 'municipality', c.municipality,
      'address', c.address, 'bulstat', c.bulstat, 'vicariate_id', c.vicariate_id,
      'duties', coalesce((select jsonb_agg(jsonb_build_object(
          'user_id', d.user_id, 'name', p.full_name, 'rank', p.rank,
          'start_date', d.start_date, 'end_date', d.end_date) order by d.start_date)
        from duties d join profiles p on p.id = d.user_id
        where d.church_id = c.id and d.end_date >= public.duty_today() - 1
          and d.start_date <= public.duty_today() + 120), '[]'::jsonb))
    from churches c where c.id = p_church);
end;
$$;

revoke execute on function public.is_secretary_of(uuid) from public, anon;
revoke execute on function public.metro_call(uuid[], text) from public, anon;
revoke execute on function public.metro_call_answer(uuid, text) from public, anon;
revoke execute on function public.metro_event_save(uuid, uuid, timestamptz, timestamptz, boolean, text, text, text, boolean) from public, anon;
revoke execute on function public.metro_event_delete(uuid) from public, anon;
revoke execute on function public.can_view_church_from_diocese(uuid) from public, anon;
revoke execute on function public.diocese_church(uuid) from public, anon;
grant execute on function public.is_secretary_of(uuid) to authenticated;
grant execute on function public.metro_call(uuid[], text) to authenticated;
grant execute on function public.metro_call_answer(uuid, text) to authenticated;
grant execute on function public.metro_event_save(uuid, uuid, timestamptz, timestamptz, boolean, text, text, text, boolean) to authenticated;
grant execute on function public.metro_event_delete(uuid) to authenticated;
grant execute on function public.can_view_church_from_diocese(uuid) to authenticated;
grant execute on function public.diocese_church(uuid) to authenticated;
