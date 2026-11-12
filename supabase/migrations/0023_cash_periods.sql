-- =====================================================================
-- Приключване на месец в касата + записи със задна дата.
--  * Касиерът натиска „Приключи месеца“, председателят одобрява (или връща
--    с причина). Без касиер председателят приключва сам („без второ одобрение“).
--  * Приключва се само минал месец, без чакащи записи в него.
--  * Запис с дата в приключен месец („задна дата“) винаги чака одобрение от
--    другия – дори под лимита и дори приход от касата. Без касиер се
--    разрешава, но е отбелязан.
-- =====================================================================

create table public.cash_periods (
  church_id     uuid not null references public.churches (id) on delete cascade,
  month         date not null check (extract(day from month) = 1),
  status        text not null default 'pending' check (status in ('pending', 'closed')),
  requested_by  uuid references auth.users (id) on delete set null,
  requested_at  timestamptz not null default now(),
  approved_by   uuid references auth.users (id) on delete set null,
  approved_at   timestamptz,
  single        boolean not null default false,
  primary key (church_id, month)
);
alter table public.cash_periods enable row level security;
create policy cash_periods_select on public.cash_periods for select to authenticated
  using (public.has_permission(church_id, 'cash'));

alter table public.cash_entries add column backdated boolean not null default false;

create or replace function public.cash_month_closed(p_church uuid, p_date date)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from cash_periods
                  where church_id = p_church and month = date_trunc('month', p_date)::date and status = 'closed');
$$;

-- cash_add: както досега + задна дата.
create or replace function public.cash_add(
  p_church uuid, p_book text, p_amount numeric, p_category text, p_category_other text,
  p_note text, p_account text, p_direction text, p_event uuid, p_date date)
returns public.cash_entries language plpgsql security definer set search_path = public, extensions as $$
declare
  r cash_entries;
  holder boolean := public.cash_holder(p_church);
  bank boolean := coalesce((select has_bank from cash_settings where church_id = p_church), false);
  d date := coalesce(p_date, current_date);
  closed boolean;
  auto text;
begin
  if not is_member(p_church) then raise exception 'not_member'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'bad_amount'; end if;
  if p_book not in ('income', 'expense', 'transfer', 'opening') then raise exception 'bad_book'; end if;
  if p_book <> 'income' and not holder then raise exception 'not_cash_holder'; end if;
  if p_book = 'opening' and exists (
       select 1 from cash_entries
        where church_id = p_church and book = 'opening' and account = coalesce(p_account, 'cash')
          and status <> 'returned') then
    raise exception 'opening_exists';
  end if;
  if (p_book = 'transfer' or coalesce(p_account, 'cash') = 'bank') and not bank then raise exception 'no_bank'; end if;
  if d > current_date + 1 then raise exception 'future_date'; end if;
  if p_event is not null and not exists (select 1 from events where id = p_event and church_id = p_church) then
    raise exception 'not_found';
  end if;
  closed := public.cash_month_closed(p_church, d);
  insert into cash_entries (church_id, book, amount, account, direction, category, category_other, note,
                            entry_date, event_id, created_by, backdated)
  values (p_church, p_book, round(p_amount, 2),
          case when p_book = 'transfer' then 'cash' else coalesce(p_account, 'cash') end,
          case when p_book = 'transfer' then coalesce(p_direction, 'to_bank') end,
          coalesce(nullif(trim(p_category), ''), 'Друго'), nullif(trim(p_category_other), ''),
          nullif(trim(p_note), ''), d, p_event, auth.uid(), closed)
  returning * into r;
  if closed then
    -- Задна дата: винаги второ одобрение; без касиер – влиза, отбелязано.
    if public.cash_cashier(p_church) is null and holder then r := cash_book_in(r.id, 'single'); end if;
  elsif p_book = 'income' then
    if holder then r := cash_book_in(r.id, 'holder'); end if;
  else
    auto := cash_auto_reason(p_church, p_book, p_amount);
    if auto is not null then r := cash_book_in(r.id, auto); end if;
  end if;
  return r;
end;
$$;

-- Сторно на запис от приключен месец – отбелязано като задна дата.
create or replace function public.cash_mark_backdated_reversal()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.reverses is not null and exists (
       select 1 from cash_entries o where o.id = new.reverses and public.cash_month_closed(o.church_id, o.entry_date)) then
    new.backdated := true;
  end if;
  return new;
end;
$$;
create trigger cash_backdated_reversal before insert on public.cash_entries
  for each row execute function public.cash_mark_backdated_reversal();

-- Касиерът иска приключване; без касиер председателят приключва сам.
create or replace function public.cash_close_request(p_church uuid, p_month date)
returns public.cash_periods language plpgsql security definer set search_path = public, extensions as $$
declare
  m date := date_trunc('month', p_month)::date;
  cashier uuid := public.cash_cashier(p_church);
  r cash_periods;
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if m >= date_trunc('month', current_date)::date then raise exception 'month_not_over'; end if;
  if cashier is not null and cashier <> auth.uid() then raise exception 'not_cashier'; end if;
  if exists (select 1 from cash_periods where church_id = p_church and month = m) then
    raise exception 'already_closed';
  end if;
  if exists (select 1 from cash_entries where church_id = p_church and status = 'pending'
               and date_trunc('month', entry_date)::date = m) then
    raise exception 'pending_in_month';
  end if;
  if cashier is null then
    insert into cash_periods (church_id, month, status, requested_by, approved_by, approved_at, single)
    values (p_church, m, 'closed', auth.uid(), auth.uid(), now(), true) returning * into r;
  else
    insert into cash_periods (church_id, month, requested_by) values (p_church, m, auth.uid()) returning * into r;
  end if;
  return r;
end;
$$;

-- Председателят одобрява (приключва) или връща (заявката се маха).
create or replace function public.cash_close_decide(p_church uuid, p_month date, p_approve boolean)
returns text language plpgsql security definer set search_path = public, extensions as $$
declare
  m date := date_trunc('month', p_month)::date;
  r cash_periods;
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  select * into r from cash_periods where church_id = p_church and month = m for update;
  if not found or r.status <> 'pending' then raise exception 'not_pending'; end if;
  if r.requested_by = auth.uid() then raise exception 'own_entry'; end if;
  if p_approve then
    update cash_periods set status = 'closed', approved_by = auth.uid(), approved_at = now()
     where church_id = p_church and month = m;
    return 'closed';
  end if;
  delete from cash_periods where church_id = p_church and month = m;
  return 'returned';
end;
$$;

revoke execute on function public.cash_month_closed(uuid, date) from public, anon;
revoke execute on function public.cash_close_request(uuid, date) from public, anon;
revoke execute on function public.cash_close_decide(uuid, date, boolean) from public, anon;
grant execute on function public.cash_month_closed(uuid, date) to authenticated;
grant execute on function public.cash_close_request(uuid, date) to authenticated;
grant execute on function public.cash_close_decide(uuid, date, boolean) to authenticated;
