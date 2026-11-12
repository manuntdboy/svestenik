-- Лимитът за разход без одобрение е фиксиран: 100 € на ден на човек.
-- Не се променя от приложението (настройките пазят само банковата сметка).
update public.cash_settings set limit_eur = 100;
alter table public.cash_settings add constraint cash_settings_fixed_limit check (limit_eur = 100);

create or replace function public.cash_auto_reason(p_church uuid, p_book text, p_amount numeric)
returns text language plpgsql stable security definer set search_path = public, extensions as $$
declare
  lim constant numeric := 100;
  today numeric;
begin
  if public.cash_cashier(p_church) is null then return 'single'; end if;
  if p_book <> 'expense' or p_amount <= 0 then return null; end if;
  select coalesce(sum(amount), 0) into today from cash_entries
   where church_id = p_church and created_by = auth.uid() and book = 'expense'
     and auto_reason = 'under_limit' and created_at::date = current_date;
  if p_amount <= lim and today + p_amount <= lim then return 'under_limit'; end if;
  return null;
end;
$$;

create or replace function public.cash_save_settings(p_church uuid, p_limit numeric, p_has_bank boolean)
returns public.cash_settings language plpgsql security definer set search_path = public, extensions as $$
declare
  s cash_settings;
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  insert into cash_settings (church_id, limit_eur, has_bank, updated_at)
  values (p_church, 100, coalesce(p_has_bank, false), now())
  on conflict (church_id) do update set has_bank = excluded.has_bank, updated_at = now()
  returning * into s;
  return s;
end;
$$;
