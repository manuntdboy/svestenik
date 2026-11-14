-- =====================================================================
-- Повече контрол за създателя (решаване на казуси в движение):
--  1) „Какво вижда“ – картина на приложението през очите на човек;
--  2) пробно известие – в edge функцията notify (type creator_test);
--  3) дневник на действията – кой какво направи и кога;
--  8) временно спиране на профил (банът е в edge функцията suspend_user);
--  9) каса: решаване на чакащ запис и отключване на месец – с бележка
--     „от създателя“ и известие до председателя и касиера.
-- =====================================================================

-- ---------------------------------------------------------------- 3) дневник
create table public.activity_log (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  actor_id    uuid references auth.users (id) on delete set null,
  target_id   uuid references auth.users (id) on delete set null,
  church_id   uuid references public.churches (id) on delete cascade,
  action      text not null,
  details     text
);
create index activity_log_at_idx on public.activity_log (at desc);
create index activity_log_actor_idx on public.activity_log (actor_id, at desc);
create index activity_log_target_idx on public.activity_log (target_id, at desc);
create index activity_log_church_idx on public.activity_log (church_id, at desc);
alter table public.activity_log enable row level security;
revoke all on public.activity_log from anon, authenticated;

create or replace function public.kind_bg(k text)
returns text language sql immutable as $$
  select case k when 'krashtene' then 'Кръщене' when 'venchavka' then 'Венчавка' when 'pogrebenie' then 'Погребение'
    when 'panihida' then 'Панихида' when 'vodosvet' then 'Водосвет' when 'sluzhba' then 'Служба'
    when 'arhiereyska' then 'Архиерейска литургия' when 'izpoved' then 'Изповед' when 'maslosvet' then 'Маслосвет'
    when 'kurban' then 'Курбан' else 'Друго' end;
$$;

create or replace function public.money_bg(a numeric)
returns text language sql immutable as $$
  select replace(trim(to_char(a, 'FM999999999990.00')), '.', ',') || ' €';
$$;

create or replace function public.log_act(p_church uuid, p_target uuid, p_action text, p_details text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  insert into activity_log (actor_id, target_id, church_id, action, details)
  values (auth.uid(), p_target, p_church, p_action, left(p_details, 300));
  if random() < 0.005 then
    delete from activity_log where at < now() - interval '180 days';
  end if;
end;
$$;
revoke execute on function public.log_act(uuid, uuid, text, text) from public, anon, authenticated;

create or replace function public.trg_activity()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
declare
  n jsonb := case when tg_op = 'DELETE' then null else to_jsonb(new) end;
  o jsonb := case when tg_op = 'INSERT' then null else to_jsonb(old) end;
  r jsonb := coalesce(n, o);
  ch uuid := (r->>'church_id')::uuid;
  ev text;
  dd text;
begin
  if tg_table_name = 'events' then
    ev := kind_bg(r->>'kind') || ' · ' || to_char((r->>'starts_at')::timestamptz at time zone 'Europe/Sofia', 'DD.MM HH24:MI')
          || coalesce(' · ' || nullif(r->>'for_whom', ''), '');
    if tg_op = 'INSERT' then
      perform log_act(ch, (r->>'assignee_id')::uuid, 'Записа събитие', ev);
    elsif tg_op = 'DELETE' then
      perform log_act(ch, (r->>'assignee_id')::uuid, 'Изтри събитие', ev);
    elsif n->>'status' is distinct from o->>'status' then
      perform log_act(ch, (r->>'assignee_id')::uuid,
        case n->>'status' when 'done' then 'Отбеляза „проведено“' when 'cancelled' then 'Отмени събитие' else 'Върна събитието като предстоящо' end, ev);
    elsif n->>'assignment_status' is distinct from o->>'assignment_status' then
      perform log_act(ch, (r->>'assignee_id')::uuid,
        case n->>'assignment_status' when 'accepted' then 'Прие събитие' when 'declined' then 'Отказа събитие' else 'Възложи събитие' end,
        ev || coalesce(' · ' || nullif(n->>'decline_reason', ''), ''));
    elsif n->>'assignee_id' is distinct from o->>'assignee_id' then
      perform log_act(ch, (r->>'assignee_id')::uuid, 'Прехвърли събитие', ev);
    elsif (n - 'seen_at' - 'updated_at') <> (o - 'seen_at' - 'updated_at') then
      perform log_act(ch, (r->>'assignee_id')::uuid,
        case when n->>'starts_at' is distinct from o->>'starts_at' then 'Премести събитие' else 'Промени събитие' end, ev);
    end if;

  elsif tg_table_name = 'leave_requests' then
    dd := to_char((r->>'start_date')::date, 'DD.MM') || ' – ' || to_char((r->>'end_date')::date, 'DD.MM.YYYY');
    if tg_op = 'INSERT' then
      perform log_act(ch, (r->>'user_id')::uuid, 'Поиска почивка', dd);
    elsif tg_op = 'DELETE' then
      perform log_act(ch, (r->>'user_id')::uuid, 'Изтри заявка за почивка', dd);
    elsif n->>'status' is distinct from o->>'status' then
      perform log_act(ch, (r->>'user_id')::uuid,
        case n->>'status' when 'approved' then 'Одобри почивка' when 'rejected' then 'Отказа почивка'
                          when 'ended' then 'Прекрати почивка' else 'Промени почивка' end,
        dd || coalesce(' · ' || nullif(n->>'decision_note', ''), ''));
    end if;

  elsif tg_table_name = 'duties' then
    dd := to_char((r->>'start_date')::date, 'DD.MM') || ' – ' || to_char((r->>'end_date')::date, 'DD.MM.YYYY');
    if tg_op = 'INSERT' then
      perform log_act(ch, (r->>'user_id')::uuid, 'Добави дежурство', dd);
    elsif tg_op = 'DELETE' then
      perform log_act(ch, (r->>'user_id')::uuid, 'Изтри дежурство', dd);
    elsif (n - 'created_at') <> (o - 'created_at') then
      perform log_act(ch, (r->>'user_id')::uuid, 'Промени дежурство', dd);
    end if;

  elsif tg_table_name = 'duty_swaps' then
    if tg_op = 'INSERT' then
      perform log_act(ch, (r->>'to_user')::uuid, 'Предложи размяна на дежурство', null);
    elsif tg_op = 'UPDATE' and n->>'status' is distinct from o->>'status' then
      perform log_act(ch, (r->>'from_user')::uuid,
        case n->>'status' when 'chair' then 'Прие размяна (чака председателя)' when 'approved' then 'Одобри размяна'
                          when 'rejected' then 'Отказа размяна' when 'cancelled' then 'Отмени размяна' else 'Размяна' end,
        nullif(n->>'reason', ''));
    end if;

  elsif tg_table_name = 'cash_entries' then
    ev := case r->>'book' when 'income' then 'приход' when 'expense' then 'разход' else 'движение' end
          || ' ' || money_bg((r->>'amount')::numeric) || ' · ' || coalesce(r->>'category', '');
    if tg_op = 'INSERT' then
      perform log_act(ch, null, case when r->>'reverses' is not null then 'Сторно в касата' else 'Нов запис в касата' end, ev);
    elsif tg_op = 'UPDATE' and n->>'status' is distinct from o->>'status' then
      if n->>'status' = 'approved' and n->>'decided_by' is not null then
        perform log_act(ch, (r->>'created_by')::uuid, 'Одобри запис № ' || coalesce(n->>'number', '?'), ev);
      elsif n->>'status' = 'returned' then
        perform log_act(ch, (r->>'created_by')::uuid, 'Върна запис', ev || coalesce(' · ' || nullif(n->>'return_reason', ''), ''));
      end if;
    end if;

  elsif tg_table_name = 'cash_periods' then
    dd := to_char((r->>'month')::date, 'MM.YYYY');
    if tg_op = 'INSERT' then
      perform log_act(ch, null, 'Поиска приключване на месец', dd);
    elsif tg_op = 'DELETE' then
      perform log_act(ch, null, case when o->>'status' = 'closed' then 'Отключи месец' else 'Върна приключването на месец' end, dd);
    elsif n->>'status' is distinct from o->>'status' then
      perform log_act(ch, null, 'Приключи месец', dd);
    end if;

  elsif tg_table_name = 'stock_moves' then
    if tg_op = 'INSERT' then
      perform log_act(ch, null,
        case r->>'kind' when 'load' then 'Склад: зареди' when 'writeoff' then 'Склад: изписа' else 'Склад: за събитие' end,
        (r->>'item') || ' · ' || abs((r->>'qty')::int));
    end if;

  elsif tg_table_name = 'church_members' then
    if tg_op = 'INSERT' then
      perform log_act(ch, (r->>'user_id')::uuid,
        case when r->>'role' = 'manager' then 'Създаде храм' else 'Поиска влизане в храма' end, null);
    elsif tg_op = 'DELETE' then
      perform log_act(ch, (r->>'user_id')::uuid,
        case when auth.uid() = (r->>'user_id')::uuid then 'Излезе от храма' else 'Извади от храма' end, null);
    elsif n->>'status' is distinct from o->>'status' then
      perform log_act(ch, (r->>'user_id')::uuid, 'Одобри влизане в храма', null);
    elsif n->>'role' is distinct from o->>'role' then
      perform log_act(ch, (r->>'user_id')::uuid, 'Смени ролята',
        case n->>'role' when 'manager' then 'председател' else 'свещеник' end);
    elsif n->'permissions' is distinct from o->'permissions' then
      perform log_act(ch, (r->>'user_id')::uuid,
        case when (n->'permissions') ? 'cash' then 'Направи касиер' else 'Махна правото на касиер' end, null);
    end if;

  elsif tg_table_name = 'chat_messages' then
    if tg_op = 'INSERT' then
      perform log_act(ch, (r->>'recipient_id')::uuid,
        case when r->>'recipient_id' is null then 'Писа в чата на храма' else 'Писа лично съобщение' end, null);
    end if;
  end if;
  return null;
exception when others then
  return null; -- дневникът никога не спира истинското действие
end;
$$;

create trigger activity_events after insert or update or delete on public.events for each row execute function public.trg_activity();
create trigger activity_leaves after insert or update or delete on public.leave_requests for each row execute function public.trg_activity();
create trigger activity_duties after insert or update or delete on public.duties for each row execute function public.trg_activity();
create trigger activity_swaps after insert or update on public.duty_swaps for each row execute function public.trg_activity();
create trigger activity_cash after insert or update on public.cash_entries for each row execute function public.trg_activity();
create trigger activity_periods after insert or update or delete on public.cash_periods for each row execute function public.trg_activity();
create trigger activity_stock after insert on public.stock_moves for each row execute function public.trg_activity();
create trigger activity_members after insert or update or delete on public.church_members for each row execute function public.trg_activity();
create trigger activity_chat after insert on public.chat_messages for each row execute function public.trg_activity();

create or replace function public.creator_activity(p_user uuid default null, p_church uuid default null, p_limit integer default 150)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'at') desc) from (
    select jsonb_build_object('at', l.at, 'action', l.action, 'details', l.details,
             'actor', coalesce(pa.full_name, case when l.actor_id is null then 'система' else '—' end),
             'target', case when l.target_id is distinct from l.actor_id then pt.full_name end,
             'church', c.name,
             'by_creator', l.actor_id in (select user_id from app_creators)) x
      from activity_log l
      left join profiles pa on pa.id = l.actor_id
      left join profiles pt on pt.id = l.target_id
      left join churches c on c.id = l.church_id
     where (p_user is null or l.actor_id = p_user or l.target_id = p_user)
       and (p_church is null or l.church_id = p_church)
     order by l.at desc
     limit least(greatest(coalesce(p_limit, 150), 1), 500)) q), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- 8) спиране
alter table public.profiles add column suspended_at timestamptz;

-- Спрян ли е профилът (банът на входа е в edge функцията suspend_user).
create or replace function public.is_suspended(p_user uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select suspended_at is not null from profiles where id = p_user), false);
$$;

create or replace function public.creator_people_flags()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_object_agg(id::text, jsonb_build_object('suspended_at', suspended_at))
                     from profiles where suspended_at is not null), '{}'::jsonb);
end;
$$;

-- ---------------------------------------------------------------- 1) „Какво вижда“
create or replace function public.creator_view_as(p_user uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  today date := (now() at time zone 'Europe/Sofia')::date;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'name', (select full_name from profiles where id = p_user),
    'username', (select username from profiles where id = p_user),
    'build', (select build from app_versions where user_id = p_user),
    'seen_at', (select seen_at from app_versions where user_id = p_user),
    'tokens', (select count(*) from device_tokens where user_id = p_user),
    'privacy_ok', coalesce((select privacy_version > 0 from profiles where id = p_user), false),
    'must_change_password', exists (select 1 from password_resets where user_id = p_user and changed_at is null),
    'suspended_at', (select suspended_at from profiles where id = p_user),
    'churches', coalesce((select jsonb_agg(jsonb_build_object(
        'id', c.id, 'name', c.name, 'status', m.status,
        'role', case when m.role = 'manager' then 'председател' when 'cash' = any (m.permissions) then 'касиер' else 'свещеник' end,
        -- какво чака от него (ако е председател / касиер)
        'join_pending', case when m.role = 'manager' then
             (select count(*) from church_members x where x.church_id = c.id and x.status = 'pending') end,
        'leaves_pending', case when m.role = 'manager' then
             (select count(*) from leave_requests l where l.church_id = c.id and l.status = 'pending') end,
        'swaps_pending', case when m.role = 'manager' then
             (select count(*) from duty_swaps s where s.church_id = c.id and s.status = 'chair') end,
        'cash_pending', case when m.role = 'manager' or 'cash' = any (m.permissions) then
             (select count(*) from cash_entries e where e.church_id = c.id and e.status = 'pending' and e.created_by <> p_user) end,
        'chat_unread', (select count(*) from chat_messages cm
                         where cm.church_id = c.id and cm.sender_id is distinct from p_user
                           and (cm.recipient_id is null or cm.recipient_id = p_user)
                           and cm.created_at > coalesce((select r.read_at from chat_reads r
                                where r.user_id = p_user and r.church_id = c.id
                                  and r.thread = case when cm.recipient_id is null then 'c' else cm.sender_id::text end),
                              '-infinity'))
      ) order by c.name)
      from church_members m join churches c on c.id = m.church_id where m.user_id = p_user), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object(
        'at', e.starts_at, 'kind', kind_bg(e.kind), 'for_whom', e.for_whom, 'church', c.name,
        'assignment', e.assignment_status, 'mine', e.owner_id = p_user and e.assignee_id <> p_user) order by e.starts_at)
      from events e join churches c on c.id = e.church_id
     where (e.assignee_id = p_user or e.owner_id = p_user) and e.status = 'planned'
       and e.starts_at >= now() - interval '2 hours' and e.starts_at < now() + interval '14 days'), '[]'::jsonb),
    'leaves', coalesce((select jsonb_agg(jsonb_build_object(
        'from', l.start_date, 'to', l.end_date, 'status', l.status, 'unseen', l.decision_seen_at is null and l.status <> 'pending')
        order by l.start_date desc)
      from leave_requests l where l.user_id = p_user and l.end_date >= today - 30), '[]'::jsonb),
    'duties', coalesce((select jsonb_agg(jsonb_build_object('from', d.start_date, 'to', d.end_date, 'church', c.name)
        order by d.start_date)
      from (select * from duties where user_id = p_user and end_date >= today order by start_date limit 4) d
      join churches c on c.id = d.church_id), '[]'::jsonb),
    'cards', jsonb_build_object(
      'announcements', coalesce((select jsonb_agg(a.title order by a.created_at)
          from announcements a
         where not exists (select 1 from announcement_seen s where s.announcement_id = a.id and s.user_id = p_user)
           and (a.recipient_id = p_user
                or (a.recipient_id is null and (a.church_id is null
                    or exists (select 1 from church_members m where m.church_id = a.church_id and m.user_id = p_user and m.status = 'active'))))),
        '[]'::jsonb),
      'cash_returned', (select count(*) from cash_entries e where e.created_by = p_user and e.status = 'returned' and e.return_seen_at is null),
      'to_confirm', (select count(*) from events e where e.assignee_id = p_user and e.assignment_status = 'pending' and e.status = 'planned'))
  );
end;
$$;

-- ---------------------------------------------------------------- 9) каса
alter table public.cash_entries add column by_creator boolean not null default false;

create or replace function public.cash_staff_notice(p_church uuid, p_title text, p_body text)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  ids uuid[] := '{}';
  u uuid;
begin
  for u in select user_id from church_members
            where church_id = p_church and status = 'active' and (role = 'manager' or 'cash' = any (permissions)) loop
    ids := ids || public.creator_notice(u, p_church, p_title, p_body);
  end loop;
  return array_remove(ids, null);
end;
$$;
revoke execute on function public.cash_staff_notice(uuid, text, text) from public, anon, authenticated;

create or replace function public.creator_cash_overview(p_church uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'pending', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'book', e.book, 'amount', e.amount, 'category', e.category, 'note', e.note,
        'date', e.entry_date, 'by', p.full_name, 'at', e.created_at, 'reverses', e.reverses is not null) order by e.created_at)
      from cash_entries e left join profiles p on p.id = e.created_by
     where e.church_id = p_church and e.status = 'pending'), '[]'::jsonb),
    'periods', coalesce((select jsonb_agg(jsonb_build_object('month', month, 'status', status) order by month desc)
      from cash_periods where church_id = p_church), '[]'::jsonb));
end;
$$;

create or replace function public.creator_cash_decide(p_entry uuid, p_approve boolean, p_reason text)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  r cash_entries;
  what text;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  select * into r from cash_entries where id = p_entry for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'not_pending'; end if;
  if p_approve then
    r := cash_book_in(r.id, null);
    update cash_entries set by_creator = true where id = r.id returning * into r;
    what := 'Създателят на Кайрос одобри запис № ' || r.number;
  else
    update cash_entries set status = 'returned', decided_by = auth.uid(), decided_at = now(), by_creator = true,
                            return_reason = nullif(trim(p_reason), '')
     where id = r.id returning * into r;
    what := 'Създателят на Кайрос върна запис' || coalesce(' („' || r.return_reason || '“)', '');
  end if;
  return public.cash_staff_notice(r.church_id, 'Каса: решение от създателя',
    what || ': ' || case r.book when 'income' then 'приход' when 'expense' then 'разход' else 'движение' end
         || ' ' || money_bg(r.amount) || ', ' || r.category || '.');
end;
$$;

create or replace function public.creator_cash_reopen(p_church uuid, p_month date)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  m date := date_trunc('month', p_month)::date;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  delete from cash_periods where church_id = p_church and month = m;
  if not found then raise exception 'not_found'; end if;
  return public.cash_staff_notice(p_church, 'Каса: отключен месец',
    'Създателят на Кайрос отключи ' || to_char(m, 'MM.YYYY') || ' – записите в него могат да се поправят. '
    || 'След това месецът се приключва отново.');
end;
$$;

revoke execute on function public.creator_activity(uuid, uuid, integer) from public, anon;
revoke execute on function public.creator_people_flags() from public, anon;
revoke execute on function public.creator_view_as(uuid) from public, anon;
revoke execute on function public.creator_cash_overview(uuid) from public, anon;
revoke execute on function public.creator_cash_decide(uuid, boolean, text) from public, anon;
revoke execute on function public.creator_cash_reopen(uuid, date) from public, anon;
revoke execute on function public.is_suspended(uuid) from public, anon;
grant execute on function public.creator_activity(uuid, uuid, integer) to authenticated;
grant execute on function public.creator_people_flags() to authenticated;
grant execute on function public.creator_view_as(uuid) to authenticated;
grant execute on function public.creator_cash_overview(uuid) to authenticated;
grant execute on function public.creator_cash_decide(uuid, boolean, text) to authenticated;
grant execute on function public.creator_cash_reopen(uuid, date) to authenticated;
grant execute on function public.is_suspended(uuid) to authenticated;
grant execute on function public.is_suspended(uuid) to service_role;
