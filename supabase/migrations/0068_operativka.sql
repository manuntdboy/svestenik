-- Оперативка на митрополита:
--  * бележки по дни – вижда ги и ги пише САМО митрополитът;
--  * „Възложи на…“ – на един или няколко души от администрацията; всеки
--    вижда само възложеното на него („Задачи от митрополита“);
--  * срок по желание; изпълнителят натиска „Изпълнено“ (с кратка бележка);
--    митрополитът може да „Върне“ задачата;
--  * задача до няколко души е готова, когато всички са я изпълнили.

create table public.metro_notes (
  id          uuid primary key default gen_random_uuid(),
  diocese_id  uuid not null references public.dioceses (id) on delete cascade,
  day         date not null,
  body        text not null check (char_length(body) between 1 and 500),
  deadline    timestamptz,
  deadline_has_time boolean not null default false,
  done_at     timestamptz,
  created_by  uuid references auth.users (id) on delete set null default auth.uid(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index metro_notes_diocese_idx on public.metro_notes (diocese_id, day);

create table public.metro_note_assignees (
  note_id     uuid not null references public.metro_notes (id) on delete cascade,
  user_id     uuid not null references auth.users (id) on delete cascade,
  done_at     timestamptz,
  done_note   text check (char_length(done_note) <= 300),
  returned_at timestamptz,
  return_note text check (char_length(return_note) <= 300),
  notified_at timestamptz,
  created_at  timestamptz not null default now(),
  primary key (note_id, user_id)
);
create index metro_note_assignees_user_idx on public.metro_note_assignees (user_id);

create or replace function public.metro_note_assigned_to_me(p_note uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from metro_note_assignees where note_id = p_note and user_id = auth.uid());
$$;

alter table public.metro_notes enable row level security;
alter table public.metro_note_assignees enable row level security;
create policy metro_notes_select on public.metro_notes for select to authenticated
  using (public.is_metropolitan_of(diocese_id) or public.metro_note_assigned_to_me(id));
-- Изпълнителят вижда само своя ред (не и кой друг е на задачата).
create policy metro_note_assignees_select on public.metro_note_assignees for select to authenticated
  using (user_id = auth.uid()
         or exists (select 1 from metro_notes n where n.id = note_id and public.is_metropolitan_of(n.diocese_id)));
revoke insert, update, delete on public.metro_notes, public.metro_note_assignees from anon, authenticated;
grant select on public.metro_notes, public.metro_note_assignees to authenticated;

-- Записва бележка (нова или промяна) с изпълнителите. Само митрополитът.
create or replace function public.metro_note_save(
  p_id uuid, p_day date, p_body text, p_deadline timestamptz, p_has_time boolean, p_users uuid[])
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  d uuid;
  b text := btrim(coalesce(p_body, ''));
  users uuid[] := coalesce((select array_agg(distinct x) from unnest(coalesce(p_users, '{}')) x), '{}');
  u uuid;
  nid uuid := p_id;
begin
  select diocese_id into d from diocese_staff where user_id = auth.uid() and role = 'metropolitan' limit 1;
  if d is null then raise exception 'forbidden'; end if;
  if b = '' then raise exception 'bad_name'; end if;
  if char_length(b) > 500 then raise exception 'too_long'; end if;
  if cardinality(users) > 20 then raise exception 'too_many'; end if;
  foreach u in array users loop
    if u = auth.uid() or not public.is_admin_of(d, u) then raise exception 'not_member'; end if;
  end loop;
  if nid is null then
    insert into metro_notes (diocese_id, day, body, deadline, deadline_has_time)
    values (d, coalesce(p_day, current_date), b, p_deadline, coalesce(p_has_time, false) and p_deadline is not null)
    returning id into nid;
  else
    update metro_notes set body = b, deadline = p_deadline,
           deadline_has_time = coalesce(p_has_time, false) and p_deadline is not null, updated_at = now()
     where id = nid and diocese_id = d;
    if not found then raise exception 'not_found'; end if;
    delete from metro_note_assignees where note_id = nid and not (user_id = any (users));
  end if;
  insert into metro_note_assignees (note_id, user_id)
  select nid, x from unnest(users) x
  on conflict do nothing;
  return nid;
end;
$$;

-- Митрополитът отмята (или връща) своя бележка.
create or replace function public.metro_note_done(p_id uuid, p_done boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update metro_notes set done_at = case when p_done then now() end, updated_at = now()
   where id = p_id and public.is_metropolitan_of(diocese_id);
  if not found then raise exception 'not_found'; end if;
end;
$$;

create or replace function public.metro_note_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from metro_notes where id = p_id and public.is_metropolitan_of(diocese_id);
  if not found then raise exception 'not_found'; end if;
end;
$$;

-- Изпълнителят: „Изпълнено“ (или „Не е готово“ – отмяна).
create or replace function public.metro_task_done(p_note uuid, p_done boolean, p_comment text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  c text := nullif(btrim(coalesce(p_comment, '')), '');
begin
  if c is not null and char_length(c) > 300 then raise exception 'too_long'; end if;
  update metro_note_assignees
     set done_at = case when p_done then now() end,
         done_note = case when p_done then c end
   where note_id = p_note and user_id = auth.uid();
  if not found then raise exception 'not_found'; end if;
end;
$$;

-- Митрополитът връща изпълнена задача на изпълнителя.
create or replace function public.metro_task_return(p_note uuid, p_user uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  r text := nullif(btrim(coalesce(p_reason, '')), '');
begin
  if r is not null and char_length(r) > 300 then raise exception 'too_long'; end if;
  if not exists (select 1 from metro_notes n where n.id = p_note and public.is_metropolitan_of(n.diocese_id)) then
    raise exception 'not_found';
  end if;
  update metro_note_assignees set done_at = null, done_note = null, returned_at = now(), return_note = r
   where note_id = p_note and user_id = p_user;
  if not found then raise exception 'not_found'; end if;
  update metro_notes set done_at = null, updated_at = now() where id = p_note;
end;
$$;

revoke execute on function public.metro_note_assigned_to_me(uuid) from public, anon;
revoke execute on function public.metro_note_save(uuid, date, text, timestamptz, boolean, uuid[]) from public, anon;
revoke execute on function public.metro_note_done(uuid, boolean) from public, anon;
revoke execute on function public.metro_note_delete(uuid) from public, anon;
revoke execute on function public.metro_task_done(uuid, boolean, text) from public, anon;
revoke execute on function public.metro_task_return(uuid, uuid, text) from public, anon;
grant execute on function public.metro_note_assigned_to_me(uuid) to authenticated;
grant execute on function public.metro_note_save(uuid, date, text, timestamptz, boolean, uuid[]) to authenticated;
grant execute on function public.metro_note_done(uuid, boolean) to authenticated;
grant execute on function public.metro_note_delete(uuid) to authenticated;
grant execute on function public.metro_task_done(uuid, boolean, text) to authenticated;
grant execute on function public.metro_task_return(uuid, uuid, text) to authenticated;
