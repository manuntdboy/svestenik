-- Касата приема суми до 12 цифри преди десетичната запетая
-- (999 999 999 999,99 €) – и за по-големи сметки в бъдеще.
alter table public.cash_entries drop constraint if exists cash_entries_amount_check;
alter table public.cash_entries alter column amount type numeric(16, 2);
alter table public.cash_entries
  add constraint cash_entries_amount_check check (amount <> 0 and abs(amount) <= 999999999999.99);
