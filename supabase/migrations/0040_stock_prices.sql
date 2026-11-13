-- =====================================================================
-- Покупни цени в склада (без ДДС – храмът не е регистриран по ДДС).
--  * Всеки вид има текуща покупна цена (свещи – за кг, книжа – за брой).
--  * При зареждане цената се пази в самото движение (историята не се мени,
--    ако цената се промени по-късно) и става новата текуща цена.
-- =====================================================================

create table public.stock_prices (
  church_id  uuid not null references public.churches (id) on delete cascade,
  item       text not null check (public.stock_item_ok(item)),
  price      numeric(12, 2) not null check (price >= 0 and price <= 1000000),
  updated_by uuid references auth.users (id) on delete set null,
  updated_at timestamptz not null default now(),
  primary key (church_id, item)
);
alter table public.stock_prices enable row level security;
create policy stock_prices_select on public.stock_prices for select to authenticated
  using (public.has_permission(church_id, 'cash'));

alter table public.stock_moves add column unit_price numeric(12, 2) check (unit_price is null or unit_price >= 0);

create or replace function public.stock_set_price(p_church uuid, p_item text, p_price numeric)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if not stock_item_ok(p_item) then raise exception 'bad_item'; end if;
  if p_price is null then
    delete from stock_prices where church_id = p_church and item = p_item;
    return;
  end if;
  if p_price < 0 or p_price > 1000000 then raise exception 'bad_amount'; end if;
  insert into stock_prices (church_id, item, price, updated_by) values (p_church, p_item, round(p_price, 2), auth.uid())
  on conflict (church_id, item) do update set price = excluded.price, updated_by = excluded.updated_by, updated_at = now();
end;
$$;

-- Зареждане с цена (по желание). Старият вариант без цена продължава да работи.
drop function if exists public.stock_load(uuid, text, integer, text);
create or replace function public.stock_load(p_church uuid, p_item text, p_qty integer, p_note text, p_price numeric default null)
returns public.stock_moves language plpgsql security definer set search_path = public, extensions as $$
declare
  r stock_moves;
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if not stock_item_ok(p_item) then raise exception 'bad_item'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'bad_amount'; end if;
  if p_price is not null and (p_price < 0 or p_price > 1000000) then raise exception 'bad_amount'; end if;
  insert into stock_moves (church_id, item, qty, kind, note, created_by, decided_at, unit_price)
  values (p_church, p_item, p_qty, 'load', nullif(trim(p_note), ''), auth.uid(), now(), round(p_price, 2))
  returning * into r;
  if p_price is not null then perform stock_set_price(p_church, p_item, p_price); end if;
  return r;
end;
$$;

revoke execute on function public.stock_set_price(uuid, text, numeric) from public, anon;
revoke execute on function public.stock_load(uuid, text, integer, text, numeric) from public, anon;
grant execute on function public.stock_set_price(uuid, text, numeric) to authenticated;
grant execute on function public.stock_load(uuid, text, integer, text, numeric) to authenticated;
