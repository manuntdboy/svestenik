-- =====================================================================
-- Склад: „Свещи“ (в цели килограми) и „Ценни книжа“ (на брой).
-- Води се като касата – само председателят и касиерът.
--  * Зареждане: влиза веднага; другият получава известие.
--  * Ръчно изписване: чака одобрение от другия (без касиер – влиза,
--    отбелязано; при изключено одобрение в касата – също влиза).
--  * Проведено кръщене → −1 кръщелно; проведена венчавка → −2 венчални
--    и −1 грамота. Автоматично, без одобрение; при връщане/отмяна/изтриване
--    на проведеното събитие бланките се връщат.
--  * Всеки вид има своя граница за предупреждение (настройва се).
-- =====================================================================

create table public.stock_moves (
  id            uuid primary key default gen_random_uuid(),
  church_id     uuid not null references public.churches (id) on delete cascade,
  item          text not null check (item in
                  ('candle_040', 'candle_1', 'candle_4', 'cert_baptism', 'cert_wedding', 'diploma')),
  qty           integer not null check (qty <> 0 and abs(qty) <= 100000),
  kind          text not null check (kind in ('load', 'writeoff', 'event', 'event_return')),
  event_id      uuid,
  note          text check (char_length(note) <= 300),
  created_by    uuid references auth.users (id) on delete set null default auth.uid(),
  created_at    timestamptz not null default now(),
  status        text not null default 'approved' check (status in ('pending', 'approved', 'returned')),
  auto_reason   text check (auto_reason in ('single', 'off')),
  decided_by    uuid references auth.users (id) on delete set null,
  decided_at    timestamptz,
  return_reason text check (char_length(return_reason) <= 300)
);
create index stock_moves_church_idx on public.stock_moves (church_id, item);
alter table public.stock_moves enable row level security;
create policy stock_moves_select on public.stock_moves for select to authenticated
  using (public.has_permission(church_id, 'cash'));

create table public.stock_thresholds (
  church_id uuid not null references public.churches (id) on delete cascade,
  item      text not null,
  min_qty   integer not null check (min_qty >= 0 and min_qty <= 100000),
  primary key (church_id, item)
);
alter table public.stock_thresholds enable row level security;
create policy stock_thresholds_select on public.stock_thresholds for select to authenticated
  using (public.has_permission(church_id, 'cash'));

create or replace function public.stock_item_ok(p_item text)
returns boolean language sql immutable as $$
  select p_item in ('candle_040', 'candle_1', 'candle_4', 'cert_baptism', 'cert_wedding', 'diploma');
$$;

-- Зареждане: веднага.
create or replace function public.stock_load(p_church uuid, p_item text, p_qty integer, p_note text)
returns public.stock_moves language plpgsql security definer set search_path = public, extensions as $$
declare
  r stock_moves;
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if not stock_item_ok(p_item) then raise exception 'bad_item'; end if;
  if p_qty is null or p_qty <= 0 then raise exception 'bad_amount'; end if;
  insert into stock_moves (church_id, item, qty, kind, note, created_by, decided_at)
  values (p_church, p_item, p_qty, 'load', nullif(trim(p_note), ''), auth.uid(), now())
  returning * into r;
  return r;
end;
$$;

-- Ръчно изписване: чака другия.
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
  update stock_moves
     set status = case when p_approve then 'approved' else 'returned' end,
         decided_by = auth.uid(), decided_at = now(),
         return_reason = case when p_approve then null else nullif(trim(p_reason), '') end
   where id = p_move returning * into r;
  return r;
end;
$$;

create or replace function public.stock_set_threshold(p_church uuid, p_item text, p_min integer)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.cash_holder(p_church) then raise exception 'not_cash_holder'; end if;
  if not stock_item_ok(p_item) then raise exception 'bad_item'; end if;
  insert into stock_thresholds (church_id, item, min_qty) values (p_church, p_item, greatest(coalesce(p_min, 0), 0))
  on conflict (church_id, item) do update set min_qty = excluded.min_qty;
end;
$$;

-- Автоматично изписване при проведено кръщене / венчавка.
create or replace function public.stock_for_event(p_church uuid, p_event uuid, p_kind text, p_sign integer)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  k text := case when p_sign < 0 then 'event' else 'event_return' end;
begin
  if p_kind = 'krashtene' then
    insert into stock_moves (church_id, item, qty, kind, event_id, created_by, decided_at)
    values (p_church, 'cert_baptism', p_sign, k, p_event, auth.uid(), now());
  elsif p_kind = 'venchavka' then
    insert into stock_moves (church_id, item, qty, kind, event_id, created_by, decided_at)
    values (p_church, 'cert_wedding', 2 * p_sign, k, p_event, auth.uid(), now()),
           (p_church, 'diploma', p_sign, k, p_event, auth.uid(), now());
  end if;
end;
$$;
revoke execute on function public.stock_for_event(uuid, uuid, text, integer) from public, anon, authenticated;

create or replace function public.events_stock()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_op = 'INSERT' then
    if new.status = 'done' then perform stock_for_event(new.church_id, new.id, new.kind, -1); end if;
    return new;
  elsif tg_op = 'UPDATE' then
    if old.status = 'done' and (new.status <> 'done' or new.kind <> old.kind) then
      perform stock_for_event(old.church_id, old.id, old.kind, 1);
    end if;
    if new.status = 'done' and (old.status <> 'done' or new.kind <> old.kind) then
      perform stock_for_event(new.church_id, new.id, new.kind, -1);
    end if;
    return new;
  else
    if old.status = 'done' then perform stock_for_event(old.church_id, old.id, old.kind, 1); end if;
    return old;
  end if;
end;
$$;
create trigger events_stock after insert or update of status, kind or delete on public.events
  for each row execute function public.events_stock();

revoke execute on function public.stock_load(uuid, text, integer, text) from public, anon;
revoke execute on function public.stock_writeoff(uuid, text, integer, text) from public, anon;
revoke execute on function public.stock_decide(uuid, boolean, text) from public, anon;
revoke execute on function public.stock_set_threshold(uuid, text, integer) from public, anon;
grant execute on function public.stock_load(uuid, text, integer, text) to authenticated;
grant execute on function public.stock_writeoff(uuid, text, integer, text) to authenticated;
grant execute on function public.stock_decide(uuid, boolean, text) to authenticated;
grant execute on function public.stock_set_threshold(uuid, text, integer) to authenticated;
