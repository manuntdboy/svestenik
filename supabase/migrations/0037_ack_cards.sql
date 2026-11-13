-- =====================================================================
-- Известие в самото приложение с бутон „ОК“:
--  * свещеникът вижда решението по почивката си (одобрена / неодобрена /
--    прекратена), докато не натисне „ОК“;
--  * създателят на запис в касата вижда, че му е върнат.
-- Старите решения се смятат за видени.
-- =====================================================================

alter table public.leave_requests add column decision_seen_at timestamptz;
alter table public.cash_entries add column return_seen_at timestamptz;

update public.leave_requests set decision_seen_at = now() where status <> 'pending';
update public.cash_entries set return_seen_at = now() where status = 'returned';

create or replace function public.leave_ack(p_request uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update leave_requests set decision_seen_at = now()
   where id = p_request and user_id = auth.uid();
end;
$$;

create or replace function public.cash_return_ack(p_entry uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  update cash_entries set return_seen_at = now()
   where id = p_entry and created_by = auth.uid() and status = 'returned';
end;
$$;

-- При ново решение / прекратяване картата се показва отново.
create or replace function public.leave_unseen_on_change()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.status is distinct from old.status or new.end_date is distinct from old.end_date then
    new.decision_seen_at := null;
  end if;
  return new;
end;
$$;
create trigger leave_unseen_on_change before update on public.leave_requests
  for each row execute function public.leave_unseen_on_change();

revoke execute on function public.leave_ack(uuid) from public, anon;
revoke execute on function public.cash_return_ack(uuid) from public, anon;
grant execute on function public.leave_ack(uuid) to authenticated;
grant execute on function public.cash_return_ack(uuid) to authenticated;
