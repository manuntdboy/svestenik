-- =====================================================================
-- Създател: общ преглед на приложението (регистрирани, храмове, употреба,
-- известия). Вижда го само профилът в app_creators. Таблицата се попълва
-- от GitHub (секрет AUTHOR_EMAIL) – имейлът не е в кода.
-- =====================================================================

create table public.app_creators (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.app_creators enable row level security;
revoke all on public.app_creators from anon, authenticated;

-- Коя версия ползва всеки (записва се от приложението, най-много на 30 мин).
create table public.app_versions (
  user_id uuid primary key references auth.users (id) on delete cascade,
  build   integer not null check (build >= 0 and build < 1000000),
  seen_at timestamptz not null default now()
);
alter table public.app_versions enable row level security;
revoke all on public.app_versions from anon, authenticated;

create or replace function public.report_version(p_build integer)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  insert into app_versions (user_id, build, seen_at)
  values (auth.uid(), greatest(least(coalesce(p_build, 0), 999999), 0), now())
  on conflict (user_id) do update set build = excluded.build, seen_at = excluded.seen_at;
end;
$$;

create or replace function public.is_creator()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from app_creators where user_id = auth.uid());
$$;

create or replace function public.creator_stats()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  res jsonb;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;

  with last_seen as (
    select u.id,
           greatest(u.last_sign_in_at,
                    (select max(s.updated_at) from auth.sessions s where s.user_id = u.id),
                    (select max(d.updated_at) from device_tokens d where d.user_id = u.id),
                    (select v.seen_at from app_versions v where v.user_id = u.id)) as at
      from auth.users u
  )
  select jsonb_build_object(
    'generated_at', now(),
    'totals', jsonb_build_object(
      'users',           (select count(*) from auth.users),
      'new_7',           (select count(*) from auth.users where created_at >= now() - interval '7 days'),
      'new_30',          (select count(*) from auth.users where created_at >= now() - interval '30 days'),
      'active_1',        (select count(*) from last_seen where at >= now() - interval '1 day'),
      'active_7',        (select count(*) from last_seen where at >= now() - interval '7 days'),
      'active_30',       (select count(*) from last_seen where at >= now() - interval '30 days'),
      'with_push',       (select count(distinct user_id) from device_tokens),
      'no_church',       (select count(*) from auth.users u
                           where not exists (select 1 from church_members m where m.user_id = u.id and m.status = 'active')),
      'churches',        (select count(*) from churches),
      'members_pending', (select count(*) from church_members where status = 'pending'),
      'events',          (select count(*) from events),
      'events_7',        (select count(*) from events where created_at >= now() - interval '7 days'),
      'events_30',       (select count(*) from events where created_at >= now() - interval '30 days'),
      'events_upcoming', (select count(*) from events where starts_at >= now() and coalesce(status, 'planned') = 'planned'),
      'events_done',     (select count(*) from events where status = 'done'),
      'cash',            (select count(*) from cash_entries),
      'cash_30',         (select count(*) from cash_entries where created_at >= now() - interval '30 days'),
      'cash_pending',    (select count(*) from cash_entries where status = 'pending'),
      'stock',           (select count(*) from stock_moves),
      'stock_30',        (select count(*) from stock_moves where created_at >= now() - interval '30 days'),
      'leaves',          (select count(*) from leave_requests),
      'leaves_pending',  (select count(*) from leave_requests where status = 'pending'),
      'notify_24',       (select count(*) from notify_log where at >= now() - interval '1 day'),
      'notify_fail_24',  (select count(*) from notify_log where at >= now() - interval '1 day' and status <> 200),
      'notify_7',        (select count(*) from notify_log where at >= now() - interval '7 days'),
      'notify_fail_7',   (select count(*) from notify_log where at >= now() - interval '7 days' and status <> 200)
    ),
    'versions', coalesce((select jsonb_object_agg(build::text, n) from
                        (select build, count(*) n from app_versions group by build) k), '{}'::jsonb),
    'events_by_kind', coalesce((select jsonb_object_agg(kind, n) from
                        (select kind, count(*) n from events
                          where created_at >= now() - interval '30 days' group by kind) k), '{}'::jsonb),
    'notify_by_type', coalesce((select jsonb_object_agg(type, n) from
                        (select type, count(*) n from notify_log
                          where at >= now() - interval '7 days' group by type) k), '{}'::jsonb),
    'notify_failed', coalesce((select jsonb_agg(jsonb_build_object('at', at, 'type', type, 'status', status) order by at desc)
                        from (select * from notify_log where status <> 200 order by at desc limit 8) f), '[]'::jsonb),
    'users', coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
        select jsonb_build_object(
          'id', u.id,
          'name', coalesce(p.full_name, u.raw_user_meta_data->>'full_name', '—'),
          'rank', p.rank,
          'username', p.username,
          'email', u.email,
          'phone', p.phone,
          'created_at', u.created_at,
          'last_seen', ls.at,
          'build', (select v.build from app_versions v where v.user_id = u.id),
          'push', exists (select 1 from device_tokens d where d.user_id = u.id),
          'events', (select count(*) from events e where e.owner_id = u.id),
          'churches', coalesce((select jsonb_agg(jsonb_build_object(
                         'name', c.name,
                         'role', case when m.role = 'manager' then 'chair'
                                      when 'cash' = any (m.permissions) then 'cashier' else 'priest' end,
                         'status', m.status) order by c.name)
                       from church_members m join churches c on c.id = m.church_id
                      where m.user_id = u.id), '[]'::jsonb)
        ) x
          from auth.users u
          left join profiles p on p.id = u.id
          left join last_seen ls on ls.id = u.id) q), '[]'::jsonb),
    'churches', coalesce((select jsonb_agg(x order by x->>'name') from (
        select jsonb_build_object(
          'id', c.id,
          'name', c.name,
          'settlement', c.settlement,
          'created_at', c.created_at,
          'active', (select count(*) from church_members m where m.church_id = c.id and m.status = 'active'),
          'pending', (select count(*) from church_members m where m.church_id = c.id and m.status = 'pending'),
          'chair', (select p.full_name from church_members m join profiles p on p.id = m.user_id
                     where m.church_id = c.id and m.role = 'manager' and m.status = 'active' limit 1),
          'cashier', (select p.full_name from profiles p where p.id = public.cash_cashier(c.id)),
          'events', (select count(*) from events e where e.church_id = c.id),
          'events_30', (select count(*) from events e where e.church_id = c.id
                         and e.created_at >= now() - interval '30 days'),
          'cash', (select count(*) from cash_entries ce where ce.church_id = c.id),
          'stock', (select count(*) from stock_moves sm where sm.church_id = c.id)
        ) x from churches c) q), '[]'::jsonb)
  ) into res;
  return res;
end;
$$;

revoke execute on function public.report_version(integer) from public, anon;
grant execute on function public.report_version(integer) to authenticated;
revoke execute on function public.is_creator() from public, anon;
revoke execute on function public.creator_stats() from public, anon;
grant execute on function public.is_creator() to authenticated;
grant execute on function public.creator_stats() to authenticated;
