-- =====================================================================
-- Чат: общ чат на храма и лични съобщения между колеги от един храм.
--  * само текст; пазят се до 6 месеца (по-старите се трият поетапно);
--  * „Заглуши“ – председателят вижда кой е заглушил общия чат;
--  * изтриване: своето съобщение, а председателят – всяко в общия чат;
--  * създателят включва чата за всички (app_config.chat_enabled).
-- =====================================================================

alter table public.app_config add column chat_enabled boolean not null default false;

create table public.chat_messages (
  id           uuid primary key default gen_random_uuid(),
  church_id    uuid not null references public.churches (id) on delete cascade,
  sender_id    uuid references auth.users (id) on delete set null,
  recipient_id uuid references auth.users (id) on delete cascade, -- null = общ чат на храма
  body         text not null check (char_length(body) between 1 and 2000),
  created_at   timestamptz not null default now()
);
create index chat_messages_church_idx on public.chat_messages (church_id, created_at);
alter table public.chat_messages enable row level security;
create policy chat_messages_select on public.chat_messages for select to authenticated
  using (public.is_member(church_id)
         and (recipient_id is null or sender_id = auth.uid() or recipient_id = auth.uid()));

-- Докъде е прочел всеки (thread = 'c' за общия чат или id на колегата).
create table public.chat_reads (
  user_id    uuid not null references auth.users (id) on delete cascade,
  church_id  uuid not null references public.churches (id) on delete cascade,
  thread     text not null,
  read_at    timestamptz not null default now(),
  primary key (user_id, church_id, thread)
);
alter table public.chat_reads enable row level security;
create policy chat_reads_select on public.chat_reads for select to authenticated using (user_id = auth.uid());

create table public.chat_mutes (
  user_id    uuid not null references auth.users (id) on delete cascade,
  church_id  uuid not null references public.churches (id) on delete cascade,
  thread     text not null,
  muted_at   timestamptz not null default now(),
  primary key (user_id, church_id, thread)
);
alter table public.chat_mutes enable row level security;
create policy chat_mutes_select on public.chat_mutes for select to authenticated
  using (user_id = auth.uid() or (thread = 'c' and public.is_manager(church_id)));

create or replace function public.chat_send(p_church uuid, p_recipient uuid, p_body text)
returns public.chat_messages language plpgsql security definer set search_path = public, extensions as $$
declare
  r chat_messages;
begin
  if not public.is_member(p_church) then raise exception 'not_member'; end if;
  if nullif(trim(p_body), '') is null then raise exception 'empty'; end if;
  if p_recipient is not null and (p_recipient = auth.uid()
     or not exists (select 1 from church_members where church_id = p_church and user_id = p_recipient and status = 'active')) then
    raise exception 'not_member';
  end if;
  insert into chat_messages (church_id, sender_id, recipient_id, body)
  values (p_church, auth.uid(), p_recipient, left(trim(p_body), 2000))
  returning * into r;
  -- Поетапно чистене: по-старите от 6 месеца в този храм.
  delete from chat_messages where church_id = p_church and created_at < now() - interval '6 months';
  -- Изпратилият е прочел разговора.
  insert into chat_reads (user_id, church_id, thread, read_at)
  values (auth.uid(), p_church, coalesce(p_recipient::text, 'c'), now())
  on conflict (user_id, church_id, thread) do update set read_at = now();
  return r;
end;
$$;

create or replace function public.chat_delete(p_id uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  r chat_messages;
begin
  select * into r from chat_messages where id = p_id;
  if not found then return; end if;
  if not (r.sender_id = auth.uid() or (r.recipient_id is null and public.is_manager(r.church_id))) then
    raise exception 'not_allowed';
  end if;
  delete from chat_messages where id = p_id;
end;
$$;

create or replace function public.chat_read(p_church uuid, p_thread text)
returns void language sql security definer set search_path = public, extensions as $$
  insert into chat_reads (user_id, church_id, thread, read_at) values (auth.uid(), p_church, p_thread, now())
  on conflict (user_id, church_id, thread) do update set read_at = now();
$$;

create or replace function public.chat_mute(p_church uuid, p_thread text, p_mute boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_member(p_church) then raise exception 'not_member'; end if;
  if p_mute then
    insert into chat_mutes (user_id, church_id, thread) values (auth.uid(), p_church, p_thread) on conflict do nothing;
  else
    delete from chat_mutes where user_id = auth.uid() and church_id = p_church and thread = p_thread;
  end if;
end;
$$;

create or replace function public.creator_set_chat(p_on boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  update app_config set chat_enabled = coalesce(p_on, false), updated_at = now();
end;
$$;

revoke execute on function public.chat_send(uuid, uuid, text) from public, anon;
revoke execute on function public.chat_delete(uuid) from public, anon;
revoke execute on function public.chat_read(uuid, text) from public, anon;
revoke execute on function public.chat_mute(uuid, text, boolean) from public, anon;
revoke execute on function public.creator_set_chat(boolean) from public, anon;
grant execute on function public.chat_send(uuid, uuid, text) to authenticated;
grant execute on function public.chat_delete(uuid) to authenticated;
grant execute on function public.chat_read(uuid, text) to authenticated;
grant execute on function public.chat_mute(uuid, text, boolean) to authenticated;
grant execute on function public.creator_set_chat(boolean) to authenticated;
