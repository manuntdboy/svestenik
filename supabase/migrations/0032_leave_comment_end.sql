-- =====================================================================
-- Почивки:
--  * при решение председателят може да напише коментар (вижда го
--    свещеникът и идва в известието);
--  * председателят може да прекрати одобрена почивка: ако още не е
--    започнала – отменя се цялата („ended“); ако тече – последният ден
--    става вчера (първоначалният край се пази в planned_end).
-- Нищо не се трие – остава в историята.
-- =====================================================================

alter table public.leave_requests
  drop constraint if exists leave_requests_status_check;
alter table public.leave_requests
  add constraint leave_requests_status_check check (status in ('pending', 'approved', 'rejected', 'ended'));

alter table public.leave_requests
  add column decision_note text check (char_length(decision_note) <= 300),
  add column ended_by      uuid references auth.users (id) on delete set null,
  add column ended_at      timestamptz,
  add column end_note      text check (char_length(end_note) <= 300),
  add column planned_end   date;

drop function if exists public.decide_leave(uuid, boolean);

create or replace function public.decide_leave(p_request uuid, p_approve boolean, p_note text default null)
returns public.leave_requests language plpgsql security definer set search_path = public, extensions as $$
declare
  r leave_requests;
begin
  select * into r from leave_requests where id = p_request for update;
  if not found then raise exception 'not_found'; end if;
  if not is_manager(r.church_id) then raise exception 'not_manager'; end if;
  if r.status <> 'pending' then raise exception 'not_pending'; end if;
  update leave_requests
     set status = case when p_approve then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(),
         decision_note = left(nullif(trim(p_note), ''), 300)
   where id = p_request returning * into r;
  return r;
end;
$$;

create or replace function public.end_leave(p_request uuid, p_note text default null)
returns public.leave_requests language plpgsql security definer set search_path = public, extensions as $$
declare
  r leave_requests;
  today date := (now() at time zone 'Europe/Sofia')::date;
begin
  select * into r from leave_requests where id = p_request for update;
  if not found then raise exception 'not_found'; end if;
  if not is_manager(r.church_id) then raise exception 'not_manager'; end if;
  if r.status <> 'approved' then raise exception 'not_approved'; end if;
  if r.end_date < today then raise exception 'leave_over'; end if;
  if r.start_date >= today then
    update leave_requests
       set status = 'ended', ended_by = auth.uid(), ended_at = now(),
           end_note = left(nullif(trim(p_note), ''), 300)
     where id = p_request returning * into r;
  else
    update leave_requests
       set planned_end = end_date, end_date = today - 1,
           ended_by = auth.uid(), ended_at = now(),
           end_note = left(nullif(trim(p_note), ''), 300)
     where id = p_request returning * into r;
  end if;
  return r;
end;
$$;

revoke execute on function public.decide_leave(uuid, boolean, text) from public, anon;
revoke execute on function public.end_leave(uuid, text) from public, anon;
grant execute on function public.decide_leave(uuid, boolean, text) to authenticated;
grant execute on function public.end_leave(uuid, text) to authenticated;
