-- =====================================================================
-- Събитие за колега и push известия
-- - assignee_id: свещеникът, който ще извърши събитието (по подразбиране
--   този, който го записва). owner_id остава този, който го е записал.
-- - Събитие за колега винаги е споделено с храма.
-- - Редактират записалият и свещеникът; трие записалият и председателят.
-- - device_tokens: устройствата, на които да идват push известия.
-- =====================================================================

alter table public.events
  add column assignee_id uuid references auth.users (id) on delete cascade;
update public.events set assignee_id = owner_id where assignee_id is null;
alter table public.events alter column assignee_id set default auth.uid();
alter table public.events alter column assignee_id set not null;

alter table public.events
  add constraint events_assigned_is_shared
  check (assignee_id = owner_id or visibility = 'church');

create index events_assignee_time_idx on public.events (assignee_id, starts_at);

-- Членува ли даден потребител в храма (за проверка на избрания свещеник).
create or replace function public.is_member_user(p_church uuid, p_user uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from church_members where church_id = p_church and user_id = p_user);
$$;

-- Записалият не може да бъде сменен при редакция.
create or replace function public.events_keep_owner()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  new.owner_id := old.owner_id;
  return new;
end;
$$;
create trigger events_keep_owner before update on public.events
  for each row execute function public.events_keep_owner();

drop policy events_select on public.events;
create policy events_select on public.events for select to authenticated
  using (owner_id = auth.uid()
         or assignee_id = auth.uid()
         or (visibility = 'church' and public.is_member(church_id)));

drop policy events_insert on public.events;
create policy events_insert on public.events for insert to authenticated
  with check (owner_id = auth.uid()
              and public.is_member(church_id)
              and public.is_member_user(church_id, assignee_id));

drop policy events_update on public.events;
create policy events_update on public.events for update to authenticated
  using (owner_id = auth.uid() or assignee_id = auth.uid())
  with check ((owner_id = auth.uid() or assignee_id = auth.uid())
              and public.is_member(church_id)
              and public.is_member_user(church_id, assignee_id));

-- ---------------------------------------------------------------------
-- Устройства за push известия
-- ---------------------------------------------------------------------
create table public.device_tokens (
  token       text primary key,
  user_id     uuid not null references auth.users (id) on delete cascade,
  platform    text not null default 'android',
  updated_at  timestamptz not null default now()
);
create index device_tokens_user_idx on public.device_tokens (user_id);
alter table public.device_tokens enable row level security;
create policy device_tokens_own on public.device_tokens for select to authenticated
  using (user_id = auth.uid());

-- Записва устройството на текущия потребител (ако телефонът е бил на друг
-- профил, старият запис се премахва).
create or replace function public.register_device(p_token text, p_platform text default 'android')
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into device_tokens (token, user_id, platform, updated_at)
  values (p_token, auth.uid(), coalesce(p_platform, 'android'), now())
  on conflict (token) do update
    set user_id = excluded.user_id, platform = excluded.platform, updated_at = now();
end;
$$;

create or replace function public.unregister_device(p_token text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from device_tokens where token = p_token and user_id = auth.uid();
end;
$$;

revoke execute on function public.register_device(text, text) from public, anon;
revoke execute on function public.unregister_device(text)    from public, anon;
grant execute on function public.register_device(text, text) to authenticated;
grant execute on function public.unregister_device(text)    to authenticated;
