-- =====================================================================
-- Статистика на чата за създателя: изпратени, изтрити, изтекли (6 месеца)
-- и доставени / неуспешни известия за чата.
-- =====================================================================
create table public.chat_events (
  id        bigint generated always as identity primary key,
  at        timestamptz not null default now(),
  church_id uuid,
  kind      text not null check (kind in ('sent', 'deleted', 'expired')),
  private   boolean not null default false,
  n         integer not null default 1
);
create index chat_events_at_idx on public.chat_events (at);
alter table public.chat_events enable row level security;
revoke all on public.chat_events from anon, authenticated;

create or replace function public.chat_send(p_church uuid, p_recipient uuid, p_body text)
returns public.chat_messages language plpgsql security definer set search_path = public, extensions as $$
declare
  r chat_messages;
  old_n integer;
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
  insert into chat_events (church_id, kind, private) values (p_church, 'sent', p_recipient is not null);
  delete from chat_messages where church_id = p_church and created_at < now() - interval '6 months';
  get diagnostics old_n = row_count;
  if old_n > 0 then insert into chat_events (church_id, kind, n) values (p_church, 'expired', old_n); end if;
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
  insert into chat_events (church_id, kind, private) values (r.church_id, 'deleted', r.recipient_id is not null);
end;
$$;

create or replace function public.creator_chat_stats()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'sent_24', (select coalesce(sum(n), 0) from chat_events where kind = 'sent' and at > now() - interval '1 day'),
    'sent_7', (select coalesce(sum(n), 0) from chat_events where kind = 'sent' and at > now() - interval '7 days'),
    'sent_all', (select coalesce(sum(n), 0) from chat_events where kind = 'sent'),
    'private_7', (select coalesce(sum(n), 0) from chat_events where kind = 'sent' and private and at > now() - interval '7 days'),
    'deleted_7', (select coalesce(sum(n), 0) from chat_events where kind = 'deleted' and at > now() - interval '7 days'),
    'deleted_all', (select coalesce(sum(n), 0) from chat_events where kind = 'deleted'),
    'expired_all', (select coalesce(sum(n), 0) from chat_events where kind = 'expired'),
    'stored', (select count(*) from chat_messages),
    'mutes', (select count(*) from chat_mutes),
    'push_7', public.creator_notify_window_type(interval '7 days', 'chat')
  );
end;
$$;

-- Известията от един вид за период (доставени, неуспешни, стари телефони, без получател).
create or replace function public.creator_notify_window_type(p_since interval, p_type text)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'calls', count(*),
    'delivered', coalesce(sum((info->>'sent')::int) filter (where status = 200), 0),
    'no_recipient', count(*) filter (where status = 200 and coalesce((info->>'sent')::int, 0) = 0
                                       and public.notify_stale_count(info) = 0 and public.notify_fcm_real_errors(info) = 0),
    'stale', coalesce(sum(public.notify_stale_count(info)) filter (where status = 200), 0),
    'errors', count(*) filter (where public.notify_is_error(type, status, info))
  )
  from notify_log where type = p_type and at >= now() - p_since;
$$;
revoke execute on function public.creator_notify_window_type(interval, text) from public, anon, authenticated;
revoke execute on function public.creator_chat_stats() from public, anon;
grant execute on function public.creator_chat_stats() to authenticated;
