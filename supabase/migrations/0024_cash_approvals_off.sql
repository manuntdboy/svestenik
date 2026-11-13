-- =====================================================================
-- Временно: председателят може да изключи второто одобрение в касата
-- (за проба). Тогава всичко – приходи от свещеници, разходи над лимита,
-- банка, задна дата, сторно, приключване на месец – влиза веднага,
-- отбелязано „одобрението е изключено“ (auto_reason = 'off').
-- =====================================================================
alter table public.cash_settings add column approvals_off boolean not null default false;

alter table public.cash_entries drop constraint if exists cash_entries_auto_reason_check;
alter table public.cash_entries add constraint cash_entries_auto_reason_check
  check (auto_reason in ('holder', 'under_limit', 'single', 'off'));

create or replace function public.cash_approvals_off(p_church uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select coalesce((select approvals_off from cash_settings where church_id = p_church), false);
$$;
revoke execute on function public.cash_approvals_off(uuid) from public, anon;
grant execute on function public.cash_approvals_off(uuid) to authenticated;

-- Настройки с новия превключвател (старата форма с 3 параметъра остава за по-старите версии).
create or replace function public.cash_save_settings(p_church uuid, p_limit numeric, p_has_bank boolean, p_approvals_off boolean)
returns public.cash_settings language plpgsql security definer set search_path = public, extensions as $$
declare
  s cash_settings;
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  insert into cash_settings (church_id, limit_eur, has_bank, approvals_off, updated_at)
  values (p_church, 100, coalesce(p_has_bank, false), coalesce(p_approvals_off, false), now())
  on conflict (church_id) do update
    set has_bank = excluded.has_bank, approvals_off = excluded.approvals_off, updated_at = now()
  returning * into s;
  return s;
end;
$$;
revoke execute on function public.cash_save_settings(uuid, numeric, boolean, boolean) from public, anon;
grant execute on function public.cash_save_settings(uuid, numeric, boolean, boolean) to authenticated;

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
  if public.cash_approvals_off(p_church) then
    -- Тестов режим: без второ одобрение.
    r := cash_book_in(r.id, 'off');
  elsif closed then
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

create or replace function public.cash_reverse(p_entry uuid, p_reason text)
returns public.cash_entries language plpgsql security definer set search_path = public, extensions as $$
declare
  o cash_entries;
  r cash_entries;
begin
  select * into o from cash_entries where id = p_entry for update;
  if not found then raise exception 'not_found'; end if;
  if not public.cash_holder(o.church_id) then raise exception 'not_cash_holder'; end if;
  if o.status <> 'approved' or o.reverses is not null or o.book = 'opening' then raise exception 'not_reversible'; end if;
  if o.reversed_by is not null or exists (select 1 from cash_entries where reverses = o.id and status = 'pending') then
    raise exception 'already_reversed';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason_required'; end if;
  insert into cash_entries (church_id, book, amount, account, direction, category, category_other, note,
                            entry_date, event_id, created_by, reverses)
  values (o.church_id, o.book, -o.amount, o.account, o.direction, o.category, o.category_other,
          'Сторно на ' || case o.book when 'income' then 'П-' when 'expense' then 'Р-' when 'opening' then 'Н-' else 'Б-' end || o.number
            || ': ' || trim(p_reason),
          current_date, o.event_id, auth.uid(), o.id)
  returning * into r;
  if public.cash_approvals_off(o.church_id) then
    r := cash_book_in(r.id, 'off');
  elsif public.cash_cashier(o.church_id) is null then
    r := cash_book_in(r.id, 'single');
  end if;
  return r;
end;
$$;

create or replace function public.cash_close_request(p_church uuid, p_month date)
returns public.cash_periods language plpgsql security definer set search_path = public, extensions as $$
declare
  m date := date_trunc('month', p_month)::date;
  cashier uuid := public.cash_cashier(p_church);
  r cash_periods;
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if m >= date_trunc('month', current_date)::date then raise exception 'month_not_over'; end if;
  if cashier is not null and cashier <> auth.uid() and not public.cash_approvals_off(p_church) then
    raise exception 'not_cashier';
  end if;
  if exists (select 1 from cash_periods where church_id = p_church and month = m) then
    raise exception 'already_closed';
  end if;
  if exists (select 1 from cash_entries where church_id = p_church and status = 'pending'
               and date_trunc('month', entry_date)::date = m) then
    raise exception 'pending_in_month';
  end if;
  if cashier is null or public.cash_approvals_off(p_church) then
    insert into cash_periods (church_id, month, status, requested_by, approved_by, approved_at, single)
    values (p_church, m, 'closed', auth.uid(), auth.uid(), now(), true) returning * into r;
  else
    insert into cash_periods (church_id, month, requested_by) values (p_church, m, auth.uid()) returning * into r;
  end if;
  return r;
end;
$$;
