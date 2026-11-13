-- Проведено събитие със записан приход в касата не може да се върне като
-- предстоящо (или да се изтрие) – иначе приходът ще се запише втори път.
-- Първо се сторнира приходът (или касиерът го връща), после събитието.
create or replace function public.events_income_lock()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if old.status = 'done'
     and (tg_op = 'DELETE' or new.status <> 'done')
     and exists (select 1 from cash_entries c
                  where c.event_id = old.id and c.status <> 'returned'
                    and c.reverses is null and c.reversed_by is null) then
    raise exception 'event_has_income';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
create trigger events_income_lock before update of status or delete on public.events
  for each row execute function public.events_income_lock();
