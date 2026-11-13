-- =====================================================================
-- Ревизии: архив само за сведение (не влияе на склада и касата).
-- Председателят може да изтрие цяла ревизия.
-- =====================================================================

create or replace function public.stock_audit_delete(p_church uuid, p_batch uuid)
returns integer language plpgsql security definer set search_path = public, extensions as $$
declare
  n integer;
begin
  if not public.is_manager(p_church) then raise exception 'not_manager'; end if;
  delete from stock_audits where church_id = p_church and batch = p_batch;
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.stock_audit_delete(uuid, uuid) from public, anon;
grant execute on function public.stock_audit_delete(uuid, uuid) to authenticated;
