-- =====================================================================
-- 1) Ревизия на склада: само проверка. Записва преброеното и колко е
--    било по книга, в отделен раздел; НЕ променя наличността и не влиза
--    в складовата книга.
-- 2) Дарител (по желание) към приход „Дарение“ в касата.
-- =====================================================================
create table public.stock_audits (
  id         uuid primary key default gen_random_uuid(),
  church_id  uuid not null references public.churches (id) on delete cascade,
  batch      uuid not null,
  item       text not null check (public.stock_item_ok(item)),
  counted    integer not null check (counted >= 0 and counted <= 100000),
  book_qty   integer not null,
  note       text check (char_length(note) <= 300),
  created_by uuid references auth.users (id) on delete set null default auth.uid(),
  created_at timestamptz not null default now()
);
create index stock_audits_church_idx on public.stock_audits (church_id, created_at);
alter table public.stock_audits enable row level security;
create policy stock_audits_select on public.stock_audits for select to authenticated
  using (public.has_permission(church_id, 'cash'));

create or replace function public.stock_audit(p_church uuid, p_batch uuid, p_item text, p_counted integer, p_note text)
returns public.stock_audits language plpgsql security definer set search_path = public, extensions as $$
declare
  r stock_audits;
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if not stock_item_ok(p_item) then raise exception 'bad_item'; end if;
  if p_counted is null or p_counted < 0 then raise exception 'bad_amount'; end if;
  insert into stock_audits (church_id, batch, item, counted, book_qty, note, created_by)
  values (p_church, p_batch, p_item, p_counted, public.stock_balance(p_church, p_item),
          nullif(trim(p_note), ''), auth.uid())
  returning * into r;
  return r;
end;
$$;
revoke execute on function public.stock_audit(uuid, uuid, text, integer, text) from public, anon;
grant execute on function public.stock_audit(uuid, uuid, text, integer, text) to authenticated;

alter table public.cash_entries add column donor text check (char_length(donor) <= 120);

-- Дарителят се добавя веднага след въвеждането (от въвелия или от касата).
create or replace function public.cash_set_donor(p_entry uuid, p_donor text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  r cash_entries;
begin
  select * into r from cash_entries where id = p_entry;
  if not found then raise exception 'not_found'; end if;
  if r.created_by <> auth.uid() and not public.cash_holder(r.church_id) then raise exception 'not_cash_holder'; end if;
  if r.book <> 'income' or r.category <> 'Дарение' then raise exception 'not_donation'; end if;
  update cash_entries set donor = nullif(trim(p_donor), '') where id = p_entry;
end;
$$;
revoke execute on function public.cash_set_donor(uuid, text) from public, anon;
grant execute on function public.cash_set_donor(uuid, text) to authenticated;
