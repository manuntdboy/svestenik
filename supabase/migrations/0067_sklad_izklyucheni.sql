-- Склад: артикули, които храмът не държи (напр. кръщелни в малък храм), се
-- изключват – не се показват и не светят червено. Включват се пак по всяко време.
alter table public.stock_thresholds add column if not exists hidden boolean not null default false;
alter table public.stock_thresholds alter column min_qty drop not null;  -- null = границата по подразбиране

create or replace function public.stock_set_hidden(p_church uuid, p_item text, p_hidden boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if not stock_item_ok(p_item) then raise exception 'bad_item'; end if;
  insert into stock_thresholds (church_id, item, min_qty, hidden) values (p_church, p_item, null, coalesce(p_hidden, false))
  on conflict (church_id, item) do update set hidden = excluded.hidden;
end;
$$;
revoke execute on function public.stock_set_hidden(uuid, text, boolean) from public, anon;
grant execute on function public.stock_set_hidden(uuid, text, boolean) to authenticated;
