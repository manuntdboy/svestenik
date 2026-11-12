-- Начално салдо: колко пари има касата (и банката) в деня, в който започва да
-- се води в Кайрос. Отделна книга (Н-1), за да не изкривява приходите.
-- Еднократно: по едно на сметка (брой / банка). Въвежда го касиерът или
-- председателят, потвърждава другият (без касиер – влиза направо). Докато
-- чака, другият може да го върне и тогава се въвежда наново; веднъж влязло,
-- не се сторнира и не се сменя.
alter table public.cash_entries drop constraint if exists cash_entries_book_check;
alter table public.cash_entries add constraint cash_entries_book_check
  check (book in ('income', 'expense', 'transfer', 'opening'));

create or replace function public.cash_add(
  p_church uuid, p_book text, p_amount numeric, p_category text, p_category_other text,
  p_note text, p_account text, p_direction text, p_event uuid, p_date date)
returns public.cash_entries language plpgsql security definer set search_path = public, extensions as $$
declare
  r cash_entries;
  holder boolean := public.cash_holder(p_church);
  bank boolean := coalesce((select has_bank from cash_settings where church_id = p_church), false);
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
  if p_event is not null and not exists (select 1 from events where id = p_event and church_id = p_church) then
    raise exception 'not_found';
  end if;
  insert into cash_entries (church_id, book, amount, account, direction, category, category_other, note,
                            entry_date, event_id, created_by)
  values (p_church, p_book, round(p_amount, 2),
          case when p_book = 'transfer' then 'cash' else coalesce(p_account, 'cash') end,
          case when p_book = 'transfer' then coalesce(p_direction, 'to_bank') end,
          coalesce(nullif(trim(p_category), ''), 'Друго'), nullif(trim(p_category_other), ''),
          nullif(trim(p_note), ''), coalesce(p_date, current_date), p_event, auth.uid())
  returning * into r;
  if p_book = 'income' then
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
  if public.cash_cashier(o.church_id) is null then
    r := cash_book_in(r.id, 'single');
  end if;
  return r;
end;
$$;
