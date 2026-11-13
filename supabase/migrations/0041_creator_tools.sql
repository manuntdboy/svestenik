-- =====================================================================
-- Инструменти на създателя:
--  * смяна на председател отгоре;
--  * съобщения до всички / до храм (карта с „ОК“ + push);
--  * минимална версия (напомняне „обновете“);
--  * дневник на грешките от телефоните;
--  * обратна връзка в приложението (с по желание снимка на екрана);
--  * настройки по храм: каса, склад, второ одобрение;
--  * подготовка за изтриване на профил (събитията за колеги остават).
-- =====================================================================

-- ------------------------------------------------------------ настройки на приложението
create table public.app_config (
  id         boolean primary key default true check (id),
  min_build  integer not null default 0,
  updated_at timestamptz not null default now()
);
insert into public.app_config (id) values (true);
alter table public.app_config enable row level security;
create policy app_config_select on public.app_config for select to authenticated using (true);

create or replace function public.creator_set_min_build(p_build integer)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  update app_config set min_build = greatest(coalesce(p_build, 0), 0), updated_at = now();
end;
$$;

-- ------------------------------------------------------------ смяна на председател
create or replace function public.creator_set_chair(p_church uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  if not exists (select 1 from church_members where church_id = p_church and user_id = p_user and status = 'active') then
    raise exception 'not_member';
  end if;
  update church_members set role = 'priest' where church_id = p_church and role = 'manager' and user_id <> p_user;
  update church_members set role = 'manager', permissions = array_remove(permissions, 'cash')
   where church_id = p_church and user_id = p_user;
  update churches set pending_chair = null, chair_proposed_by = null where id = p_church;
end;
$$;

-- ------------------------------------------------------------ съобщения
create table public.announcements (
  id          uuid primary key default gen_random_uuid(),
  church_id   uuid references public.churches (id) on delete cascade, -- null = до всички
  title       text not null check (char_length(title) between 1 and 120),
  body        text check (char_length(body) <= 1000),
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now()
);
alter table public.announcements enable row level security;
create policy announcements_select on public.announcements for select to authenticated
  using (church_id is null or public.is_member(church_id) or public.is_creator());

create table public.announcement_seen (
  announcement_id uuid not null references public.announcements (id) on delete cascade,
  user_id         uuid not null references auth.users (id) on delete cascade,
  seen_at         timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
alter table public.announcement_seen enable row level security;
create policy announcement_seen_select on public.announcement_seen for select to authenticated
  using (user_id = auth.uid() or public.is_creator());

create or replace function public.creator_announce(p_title text, p_body text, p_church uuid default null)
returns public.announcements language plpgsql security definer set search_path = public, extensions as $$
declare
  r announcements;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  insert into announcements (church_id, title, body, created_by)
  values (p_church, trim(p_title), nullif(trim(p_body), ''), auth.uid())
  returning * into r;
  -- Създателят сам не вижда картата си.
  insert into announcement_seen (announcement_id, user_id) values (r.id, auth.uid());
  return r;
end;
$$;

create or replace function public.announcement_ack(p_id uuid)
returns void language sql security definer set search_path = public, extensions as $$
  insert into announcement_seen (announcement_id, user_id) values (p_id, auth.uid())
  on conflict do nothing;
$$;

-- ------------------------------------------------------------ грешки от телефоните
create table public.app_errors (
  id       bigint generated always as identity primary key,
  at       timestamptz not null default now(),
  user_id  uuid default auth.uid(),
  build    integer,
  screen   text check (char_length(screen) <= 120),
  message  text not null check (char_length(message) <= 600),
  stack    text check (char_length(stack) <= 2000)
);
create index app_errors_at_idx on public.app_errors (at);
alter table public.app_errors enable row level security;
revoke all on public.app_errors from anon, authenticated;

create or replace function public.report_error(p_build integer, p_screen text, p_message text, p_stack text)
returns bigint language plpgsql security definer set search_path = public, extensions as $$
declare
  n bigint;
begin
  if auth.uid() is null then return null; end if;
  -- Не повече от 30 на час от един човек.
  if (select count(*) from app_errors where user_id = auth.uid() and at > now() - interval '1 hour') >= 30 then
    return null;
  end if;
  insert into app_errors (build, screen, message, stack)
  values (p_build, left(p_screen, 120), left(coalesce(p_message, '?'), 600), left(p_stack, 2000))
  returning id into n;
  delete from app_errors where at < now() - interval '60 days';
  return n;
end;
$$;

-- ------------------------------------------------------------ обратна връзка
create table public.feedback (
  id          uuid primary key default gen_random_uuid(),
  at          timestamptz not null default now(),
  user_id     uuid default auth.uid() references auth.users (id) on delete set null,
  church_id   uuid references public.churches (id) on delete set null,
  build       integer,
  body        text not null check (char_length(body) between 1 and 2000),
  photo_path  text,
  done        boolean not null default false
);
alter table public.feedback enable row level security;
create policy feedback_insert on public.feedback for insert to authenticated with check (user_id = auth.uid());
create policy feedback_select on public.feedback for select to authenticated
  using (user_id = auth.uid() or public.is_creator());

create or replace function public.creator_feedback_done(p_id uuid, p_done boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  update feedback set done = coalesce(p_done, true) where id = p_id;
end;
$$;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('feedback', 'feedback', false, 8388608, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;
create policy feedback_files_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'feedback' and (storage.foldername(name))[1] = auth.uid()::text);
create policy feedback_files_select on storage.objects for select to authenticated
  using (bucket_id = 'feedback' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_creator()));

-- ------------------------------------------------------------ настройки по храм
alter table public.churches
  add column cash_enabled  boolean not null default true,
  add column stock_enabled boolean not null default true;

create or replace function public.creator_church_settings(p_church uuid, p_cash boolean, p_stock boolean, p_approvals_off boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  update churches set cash_enabled = coalesce(p_cash, cash_enabled), stock_enabled = coalesce(p_stock, stock_enabled)
   where id = p_church;
  if p_approvals_off is not null then
    insert into cash_settings (church_id, approvals_off) values (p_church, p_approvals_off)
    on conflict (church_id) do update set approvals_off = excluded.approvals_off, updated_at = now();
  end if;
end;
$$;

-- ------------------------------------------------------------ изтриване на профил
-- Вика се от сървърната функция delete_user (само за създателя) преди
-- самото изтриване: събитията, които изтриваният е записал за колеги,
-- минават към председателя на храма, за да не изчезнат от календара им.
create or replace function public.creator_prepare_delete(p_user uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if exists (
    select 1 from church_members m
     where m.user_id = p_user and m.role = 'manager' and m.status = 'active'
       and exists (select 1 from church_members o where o.church_id = m.church_id and o.user_id <> p_user and o.status = 'active')
  ) then
    raise exception 'is_chair';
  end if;
  update events e set owner_id = coalesce(
      (select user_id from church_members where church_id = e.church_id and role = 'manager' and status = 'active' limit 1),
      e.assignee_id)
   where e.owner_id = p_user and e.assignee_id <> p_user;
end;
$$;
revoke execute on function public.creator_prepare_delete(uuid) from public, anon, authenticated;

-- ------------------------------------------------------------ прегледът на създателя
create or replace function public.creator_extra()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'min_build', (select min_build from app_config),
    'errors_24', (select count(*) from app_errors where at > now() - interval '1 day'),
    'errors_7', (select count(*) from app_errors where at > now() - interval '7 days'),
    'errors', coalesce((select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('id', e.id, 'at', e.at, 'build', e.build, 'screen', e.screen,
                                  'message', e.message, 'stack', e.stack,
                                  'user', coalesce(p.full_name, '—')) x
          from app_errors e left join profiles p on p.id = e.user_id
         order by e.at desc limit 40) q), '[]'::jsonb),
    'feedback', coalesce((select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('id', f.id, 'at', f.at, 'build', f.build, 'body', f.body, 'photo', f.photo_path,
                                  'done', f.done, 'user', coalesce(p.full_name, '—'),
                                  'rank', p.rank, 'church', c.name) x
          from feedback f left join profiles p on p.id = f.user_id left join churches c on c.id = f.church_id
         order by f.at desc limit 60) q), '[]'::jsonb),
    'announcements', coalesce((select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('id', a.id, 'at', a.created_at, 'title', a.title, 'body', a.body,
                                  'church', c.name,
                                  'seen', (select count(*) - 1 from announcement_seen s where s.announcement_id = a.id)) x
          from announcements a left join churches c on c.id = a.church_id
         order by a.created_at desc limit 20) q), '[]'::jsonb),
    'church_settings', coalesce((select jsonb_object_agg(c.id::text, jsonb_build_object(
        'cash', c.cash_enabled, 'stock', c.stock_enabled,
        'approvals_off', coalesce((select approvals_off from cash_settings s where s.church_id = c.id), false)))
        from churches c), '{}'::jsonb)
  );
end;
$$;

revoke execute on function public.creator_set_min_build(integer) from public, anon;
revoke execute on function public.creator_set_chair(uuid, uuid) from public, anon;
revoke execute on function public.creator_announce(text, text, uuid) from public, anon;
revoke execute on function public.announcement_ack(uuid) from public, anon;
revoke execute on function public.report_error(integer, text, text, text) from public, anon;
revoke execute on function public.creator_feedback_done(uuid, boolean) from public, anon;
revoke execute on function public.creator_church_settings(uuid, boolean, boolean, boolean) from public, anon;
revoke execute on function public.creator_extra() from public, anon;
grant execute on function public.creator_set_min_build(integer) to authenticated;
grant execute on function public.creator_set_chair(uuid, uuid) to authenticated;
grant execute on function public.creator_announce(text, text, uuid) to authenticated;
grant execute on function public.announcement_ack(uuid) to authenticated;
grant execute on function public.report_error(integer, text, text, text) to authenticated;
grant execute on function public.creator_feedback_done(uuid, boolean) to authenticated;
grant execute on function public.creator_church_settings(uuid, boolean, boolean, boolean) to authenticated;
grant execute on function public.creator_extra() to authenticated;

grant execute on function public.creator_prepare_delete(uuid) to service_role;

-- Членовете на храм (за „Смени председателя“ от създателя).
create or replace function public.creator_church_members(p_church uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('id', m.user_id, 'name', p.full_name, 'rank', p.rank,
                                                        'role', m.role, 'status', m.status) order by p.full_name)
                     from church_members m join profiles p on p.id = m.user_id
                    where m.church_id = p_church), '[]'::jsonb);
end;
$$;
revoke execute on function public.creator_church_members(uuid) from public, anon;
grant execute on function public.creator_church_members(uuid) to authenticated;
