-- Наличността в склада не може да е отрицателна: изписване (ръчно или от
-- проведено кръщене/венчавка) се отказва, ако няма достатъчно.
create or replace function public.stock_balance(p_church uuid, p_item text)
returns integer language sql stable security definer set search_path = public, extensions as $$
  select coalesce(sum(qty), 0)::integer from stock_moves
   where church_id = p_church and item = p_item and status = 'approved';
$$;

-- Налично за изписване = наличност минус чакащите изписвания.
create or replace function public.stock_available(p_church uuid, p_item text)
returns integer language sql stable security definer set search_path = public, extensions as $$
  select coalesce(sum(qty) filter (where status = 'approved'), 0)::integer
       + coalesce(sum(qty) filter (where status = 'pending' and qty < 0), 0)::integer
    from stock_moves where church_id = p_church and item = p_item;
$$;
revoke execute on function public.stock_balance(uuid, text) from public, anon;
revoke execute on function public.stock_available(uuid, text) from public, anon;

create or replace function public.stock_writeoff(p_church uuid, p_item text, p_qty integer, p_note text)
returns public.stock_moves language plpgsql security definer set search_path = public, extensions as $$
declare
  r stock_moves;
  auto text;
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if not stock_item_ok(p_item) then raise exception 'bad_item'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'bad_amount'; end if;
  if nullif(trim(p_note), '') is null then raise exception 'reason_required'; end if;
  -- Наличността не пада под нула (броят се и чакащите изписвания).
  if public.stock_available(p_church, p_item) < p_qty then raise exception 'not_enough_stock'; end if;
  auto := case when public.cash_approvals_off(p_church) then 'off'
               when public.cash_cashier(p_church) is null then 'single' end;
  insert into stock_moves (church_id, item, qty, kind, note, created_by, status, auto_reason, decided_at)
  values (p_church, p_item, -p_qty, 'writeoff', trim(p_note), auth.uid(),
          case when auto is null then 'pending' else 'approved' end, auto,
          case when auto is null then null else now() end)
  returning * into r;
  return r;
end;
$$;

create or replace function public.stock_decide(p_move uuid, p_approve boolean, p_reason text)
returns public.stock_moves language plpgsql security definer set search_path = public, extensions as $$
declare
  r stock_moves;
begin
  select * into r from stock_moves where id = p_move for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'not_pending'; end if;
  if not public.cash_holder(r.church_id) then raise exception 'not_cash_holder'; end if;
  if r.created_by = auth.uid() then raise exception 'own_entry'; end if;
  if p_approve and public.stock_balance(r.church_id, r.item) + r.qty < 0 then raise exception 'not_enough_stock'; end if;
  update stock_moves
     set status = case when p_approve then 'approved' else 'returned' end,
         decided_by = auth.uid(), decided_at = now(),
         return_reason = case when p_approve then null else nullif(trim(p_reason), '') end
   where id = p_move returning * into r;
  return r;
end;
$$;

-- Автоматично движение за проведено кръщене/венчавка.
--  * Изписва се само вид, който храмът води (поне веднъж е зареждан).
--  * Ако няма достатъчно – отказва (събитието не става проведено).
--  * При връщане се връща точно изписаното за това събитие.
create or replace function public.stock_for_event(p_church uuid, p_event uuid, p_kind text, p_sign integer)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  need record;
  net integer;
begin
  if p_sign < 0 then
    for need in
      select * from (values ('krashtene', 'cert_baptism', 1), ('venchavka', 'cert_wedding', 2),
                            ('venchavka', 'diploma', 1)) v(kind, item, n)
       where v.kind = p_kind
    loop
      -- Видът не се води в този храм – не изписваме.
      continue when not exists (select 1 from stock_moves where church_id = p_church and item = need.item);
      if public.stock_available(p_church, need.item) < need.n then
        raise exception 'not_enough_stock: %', need.item;
      end if;
      insert into stock_moves (church_id, item, qty, kind, event_id, created_by, decided_at)
      values (p_church, need.item, -need.n, 'event', p_event, auth.uid(), now());
    end loop;
  else
    for need in
      select item, sum(qty)::integer as q from stock_moves
       where event_id = p_event and kind in ('event', 'event_return') and status = 'approved'
       group by item
    loop
      net := need.q;
      if net < 0 then
        insert into stock_moves (church_id, item, qty, kind, event_id, created_by, decided_at)
        values (p_church, need.item, -net, 'event_return', p_event, auth.uid(), now());
      end if;
    end loop;
  end if;
end;
$$;
revoke execute on function public.stock_for_event(uuid, uuid, text, integer) from public, anon, authenticated;
