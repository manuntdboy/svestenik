-- =====================================================================
-- Каса: Приходна и Разходна книга (в евро), по желание и банкова сметка.
--
-- Кой какво (вж. проектния документ „План за касата“):
--  * Приход въвежда всеки свещеник; влиза в книгата, когато касиерът го
--    приеме (ако няма касиер – председателят). Касиер/председател въвеждат
--    приход направо.
--  * Разход и движение с банката въвеждат само касиерът и председателят.
--    До лимита (100 € по подразбиране, и общо за деня на човек) влиза веднага;
--    над него чака другия от двамата. Ако няма касиер – влиза веднага,
--    отбелязано „без второ одобрение“.
--  * Записи не се трият: грешка се поправя със сторно (обратен запис с
--    причина), което минава през същото одобрение.
--  * Номерата в книгите (П-1…, Р-1…) се дават при влизане в книгата.
-- Всичко се пише само през функциите по-долу.
-- =====================================================================

create table public.cash_settings (
  church_id  uuid primary key references public.churches (id) on delete cascade,
  limit_eur  numeric(12, 2) not null default 100 check (limit_eur >= 0 and limit_eur <= 100000),
  has_bank   boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.cash_settings enable row level security;
create policy cash_settings_select on public.cash_settings for select to authenticated
  using (public.is_member(church_id));

create table public.cash_entries (
  id             uuid primary key default gen_random_uuid(),
  church_id      uuid not null references public.churches (id) on delete cascade,
  book           text not null check (book in ('income', 'expense', 'transfer')),
  number         integer,
  amount         numeric(12, 2) not null check (amount <> 0 and abs(amount) <= 10000000),
  account        text not null default 'cash' check (account in ('cash', 'bank')),
  direction      text check (direction in ('to_bank', 'from_bank')),
  category       text not null check (char_length(category) between 1 and 60),
  category_other text check (char_length(category_other) <= 120),
  note           text check (char_length(note) <= 500),
  entry_date     date not null default current_date,
  event_id       uuid references public.events (id) on delete set null,
  created_by     uuid not null default auth.uid() references auth.users (id) on delete set null,
  created_at     timestamptz not null default now(),
  status         text not null default 'pending' check (status in ('pending', 'approved', 'returned')),
  auto_reason    text check (auto_reason in ('holder', 'under_limit', 'single')),
  decided_by     uuid references auth.users (id) on delete set null,
  decided_at     timestamptz,
  return_reason  text check (char_length(return_reason) <= 300),
  reverses       uuid references public.cash_entries (id),
  reversed_by    uuid references public.cash_entries (id),
  check ((book = 'transfer') = (direction is not null)),
  check (reverses is null or amount < 0),
  unique (church_id, book, number)
);
create index cash_entries_church_idx on public.cash_entries (church_id, entry_date);
alter table public.cash_entries enable row level security;

-- Касата вижда целия храм само председателят и касиерът; свещеникът – своите записи.
create policy cash_entries_select on public.cash_entries for select to authenticated
  using (public.has_permission(church_id, 'cash') or created_by = auth.uid());

-- ---------------------------------------------------------------- помощни
-- Има ли назначен касиер (различен от председателя).
create or replace function public.cash_cashier(p_church uuid)
returns uuid language sql stable security definer set search_path = public, extensions as $$
  select user_id from church_members
   where church_id = p_church and status = 'active' and role <> 'manager' and 'cash' = any (permissions)
   limit 1;
$$;

create or replace function public.cash_holder(p_church uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select public.has_permission(p_church, 'cash');
$$;

-- Влизане в книгата: пореден номер за книгата в храма.
create or replace function public.cash_book_in(p_id uuid, p_auto text)
returns public.cash_entries language plpgsql security definer set search_path = public, extensions as $$
declare
  r cash_entries;
  n integer;
begin
  select * into r from cash_entries where id = p_id;
  perform 1 from churches where id = r.church_id for update;  -- един номер наведнъж
  select coalesce(max(number), 0) + 1 into n from cash_entries where church_id = r.church_id and book = r.book;
  update cash_entries
     set status = 'approved', number = n, auto_reason = p_auto,
         decided_by = case when p_auto is null then auth.uid() else null end,
         decided_at = now()
   where id = p_id returning * into r;
  if r.reverses is not null then
    update cash_entries set reversed_by = r.id where id = r.reverses;
  end if;
  return r;
end;
$$;
revoke execute on function public.cash_book_in(uuid, text) from public, anon, authenticated;

-- Влиза ли разходът/движението веднага (без второ одобрение)?
create or replace function public.cash_auto_reason(p_church uuid, p_book text, p_amount numeric)
returns text language plpgsql stable security definer set search_path = public, extensions as $$
declare
  lim numeric;
  today numeric;
begin
  if public.cash_cashier(p_church) is null then return 'single'; end if;
  if p_book <> 'expense' or p_amount <= 0 then return null; end if;
  select coalesce((select limit_eur from cash_settings where church_id = p_church), 100) into lim;
  select coalesce(sum(amount), 0) into today from cash_entries
   where church_id = p_church and created_by = auth.uid() and book = 'expense'
     and auto_reason = 'under_limit' and created_at::date = current_date;
  if p_amount <= lim and today + p_amount <= lim then return 'under_limit'; end if;
  return null;
end;
$$;

-- ---------------------------------------------------------------- действия
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
  if p_book not in ('income', 'expense', 'transfer') then raise exception 'bad_book'; end if;
  if p_book <> 'income' and not holder then raise exception 'not_cash_holder'; end if;
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

-- Кой може да реши чакащ запис:
--  приход от свещеник → касиерът (ако няма – председателят);
--  разход / движение / сторно → другият от двамата (не въвелият).
create or replace function public.cash_decide(p_entry uuid, p_approve boolean, p_reason text)
returns public.cash_entries language plpgsql security definer set search_path = public, extensions as $$
declare
  r cash_entries;
  cashier uuid;
  creator_holder boolean;
begin
  select * into r from cash_entries where id = p_entry for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'not_pending'; end if;
  if not public.cash_holder(r.church_id) then raise exception 'not_cash_holder'; end if;
  if r.created_by = auth.uid() then raise exception 'own_entry'; end if;
  cashier := public.cash_cashier(r.church_id);
  creator_holder := exists (select 1 from church_members where church_id = r.church_id and user_id = r.created_by
                              and status = 'active' and (role = 'manager' or 'cash' = any (permissions)));
  if r.book = 'income' and r.reverses is null and not creator_holder then
    if cashier is not null and cashier <> auth.uid() then raise exception 'not_cashier'; end if;
  end if;
  if p_approve then
    r := cash_book_in(r.id, null);
  else
    update cash_entries set status = 'returned', decided_by = auth.uid(), decided_at = now(),
                            return_reason = nullif(trim(p_reason), '')
     where id = r.id returning * into r;
  end if;
  return r;
end;
$$;

-- Сторно: обратен запис в същата книга; минава през същото одобрение.
create or replace function public.cash_reverse(p_entry uuid, p_reason text)
returns public.cash_entries language plpgsql security definer set search_path = public, extensions as $$
declare
  o cash_entries;
  r cash_entries;
begin
  select * into o from cash_entries where id = p_entry for update;
  if not found then raise exception 'not_found'; end if;
  if not public.cash_holder(o.church_id) then raise exception 'not_cash_holder'; end if;
  if o.status <> 'approved' or o.reverses is not null then raise exception 'not_reversible'; end if;
  if o.reversed_by is not null or exists (select 1 from cash_entries where reverses = o.id and status = 'pending') then
    raise exception 'already_reversed';
  end if;
  if nullif(trim(p_reason), '') is null then raise exception 'reason_required'; end if;
  insert into cash_entries (church_id, book, amount, account, direction, category, category_other, note,
                            entry_date, event_id, created_by, reverses)
  values (o.church_id, o.book, -o.amount, o.account, o.direction, o.category, o.category_other,
          'Сторно на ' || case o.book when 'income' then 'П-' when 'expense' then 'Р-' else 'Б-' end || o.number
            || ': ' || trim(p_reason),
          current_date, o.event_id, auth.uid(), o.id)
  returning * into r;
  if public.cash_cashier(o.church_id) is null then
    r := cash_book_in(r.id, 'single');
  end if;
  return r;
end;
$$;

create or replace function public.cash_save_settings(p_church uuid, p_limit numeric, p_has_bank boolean)
returns public.cash_settings language plpgsql security definer set search_path = public, extensions as $$
declare
  s cash_settings;
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  insert into cash_settings (church_id, limit_eur, has_bank, updated_at)
  values (p_church, coalesce(p_limit, 100), coalesce(p_has_bank, false), now())
  on conflict (church_id) do update
    set limit_eur = excluded.limit_eur, has_bank = excluded.has_bank, updated_at = now()
  returning * into s;
  return s;
end;
$$;

revoke execute on function public.cash_cashier(uuid) from public, anon;
revoke execute on function public.cash_holder(uuid) from public, anon;
revoke execute on function public.cash_auto_reason(uuid, text, numeric) from public, anon, authenticated;
revoke execute on function public.cash_add(uuid, text, numeric, text, text, text, text, text, uuid, date) from public, anon;
revoke execute on function public.cash_decide(uuid, boolean, text) from public, anon;
revoke execute on function public.cash_reverse(uuid, text) from public, anon;
revoke execute on function public.cash_save_settings(uuid, numeric, boolean) from public, anon;
grant execute on function public.cash_cashier(uuid) to authenticated;
grant execute on function public.cash_holder(uuid) to authenticated;
grant execute on function public.cash_add(uuid, text, numeric, text, text, text, text, text, uuid, date) to authenticated;
grant execute on function public.cash_decide(uuid, boolean, text) to authenticated;
grant execute on function public.cash_reverse(uuid, text) to authenticated;
grant execute on function public.cash_save_settings(uuid, numeric, boolean) to authenticated;
