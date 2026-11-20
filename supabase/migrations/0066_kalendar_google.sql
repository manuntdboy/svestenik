-- Календарът в Google Calendar / iPhone: лична тайна връзка (iCal абонамент).
-- Само за четене. „Нова връзка“ спира старата веднага.
create table public.calendar_feeds (
  user_id    uuid primary key references auth.users (id) on delete cascade,
  token      text not null unique,
  scope      text not null default 'mine' check (scope in ('mine', 'church')),
  with_names boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.calendar_feeds enable row level security;
create policy calendar_feeds_select on public.calendar_feeds for select to authenticated
  using (user_id = auth.uid());
revoke insert, update, delete on public.calendar_feeds from anon, authenticated;
grant select on public.calendar_feeds to authenticated;

create or replace function public.calendar_feed_get()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare f calendar_feeds;
begin
  if auth.uid() is null then raise exception 'forbidden'; end if;
  insert into calendar_feeds (user_id, token)
  values (auth.uid(), encode(gen_random_bytes(24), 'hex'))
  on conflict (user_id) do nothing;
  select * into f from calendar_feeds where user_id = auth.uid();
  return jsonb_build_object('token', f.token, 'scope', f.scope, 'with_names', f.with_names);
end;
$$;

create or replace function public.calendar_feed_set(p_scope text, p_with_names boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if p_scope not in ('mine', 'church') then raise exception 'bad_value'; end if;
  perform public.calendar_feed_get();
  update calendar_feeds set scope = p_scope, with_names = coalesce(p_with_names, false) where user_id = auth.uid();
end;
$$;

create or replace function public.calendar_feed_reset()
returns jsonb language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.calendar_feed_get();
  update calendar_feeds set token = encode(gen_random_bytes(24), 'hex'), created_at = now() where user_id = auth.uid();
  return public.calendar_feed_get();
end;
$$;

-- Данните за връзката – вика се само от сървъра (функцията ical).
create or replace function public.calendar_feed_data(p_token text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare f calendar_feeds;
begin
  select * into f from calendar_feeds where token = p_token;
  if f.user_id is null or char_length(p_token) < 32 then return null; end if;
  return jsonb_build_object(
    'with_names', f.with_names,
    'events', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', e.id, 'kind', e.kind, 'starts_at', e.starts_at, 'minutes', e.duration_minutes,
        'for_whom', e.for_whom, 'outside', e.outside_church, 'address', e.address,
        'church', c.name, 'settlement', c.settlement, 'church_address', c.address,
        'mine', e.assignee_id = f.user_id or e.owner_id = f.user_id,
        'priest', (select p.full_name from profiles p where p.id = e.assignee_id),
        'rank', (select p.rank from profiles p where p.id = e.assignee_id),
        'status', e.status) order by e.starts_at)
      from events e join churches c on c.id = e.church_id
      where e.starts_at > now() - interval '30 days' and e.starts_at < now() + interval '400 days'
        and coalesce(e.status, 'planned') <> 'cancelled'
        and exists (select 1 from church_members m where m.church_id = e.church_id
                     and m.user_id = f.user_id and m.status = 'active')
        and (e.assignee_id = f.user_id or e.owner_id = f.user_id
             or (f.scope = 'church' and e.visibility = 'church'))), '[]'::jsonb),
    'duties', coalesce((
      select jsonb_agg(jsonb_build_object('id', d.id, 'start', d.start_date, 'end', d.end_date,
                                          'church', c.name, 'priest', p.full_name, 'rank', p.rank,
                                          'mine', d.user_id = f.user_id))
      from duties d join churches c on c.id = d.church_id join profiles p on p.id = d.user_id
      where d.end_date >= current_date - 30
        and exists (select 1 from church_members m where m.church_id = d.church_id
                     and m.user_id = f.user_id and m.status = 'active')
        and (d.user_id = f.user_id or f.scope = 'church')), '[]'::jsonb),
    'leaves', coalesce((
      select jsonb_agg(jsonb_build_object('id', l.id, 'start', l.start_date, 'end', l.end_date, 'church', c.name))
      from leave_requests l join churches c on c.id = l.church_id
      where l.user_id = f.user_id and l.status = 'approved' and l.end_date >= current_date - 30), '[]'::jsonb));
end;
$$;

revoke execute on function public.calendar_feed_get() from public, anon;
revoke execute on function public.calendar_feed_set(text, boolean) from public, anon;
revoke execute on function public.calendar_feed_reset() from public, anon;
revoke execute on function public.calendar_feed_data(text) from public, anon, authenticated;
grant execute on function public.calendar_feed_get() to authenticated;
grant execute on function public.calendar_feed_set(text, boolean) to authenticated;
grant execute on function public.calendar_feed_reset() to authenticated;
grant execute on function public.calendar_feed_data(text) to service_role;
