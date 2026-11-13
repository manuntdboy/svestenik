-- =====================================================================
-- Свещи по нови цени: 0,20 · 0,50 · 1 · 2 · 4 €.
-- Досегашните „0,40 €“ (само тестови записи) стават „0,50 €“.
-- =====================================================================

create or replace function public.stock_item_ok(p_item text)
returns boolean language sql immutable as $$
  select p_item in ('candle_020', 'candle_050', 'candle_1', 'candle_2', 'candle_4',
                    'cert_baptism', 'cert_wedding', 'diploma');
$$;

alter table public.stock_moves drop constraint if exists stock_moves_item_check;
alter table public.stock_audits drop constraint if exists stock_audits_item_check;

update public.stock_moves set item = 'candle_050' where item = 'candle_040';
update public.stock_audits set item = 'candle_050' where item = 'candle_040';
delete from public.stock_thresholds t
 where t.item = 'candle_040'
   and exists (select 1 from public.stock_thresholds x where x.church_id = t.church_id and x.item = 'candle_050');
update public.stock_thresholds set item = 'candle_050' where item = 'candle_040';

alter table public.stock_moves add constraint stock_moves_item_check check (public.stock_item_ok(item));
alter table public.stock_audits add constraint stock_audits_item_check check (public.stock_item_ok(item));
