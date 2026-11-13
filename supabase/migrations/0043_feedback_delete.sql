-- =====================================================================
-- Създателят изтрива отзиви (и снимките им), за да не се трупат.
-- Снимката се трие от приложението през хранилището (правило по-долу),
-- после редът – с creator_feedback_delete.
-- =====================================================================
create policy feedback_files_delete on storage.objects for delete to authenticated
  using (bucket_id = 'feedback' and public.is_creator());

create or replace function public.creator_feedback_delete(p_ids uuid[])
returns integer language plpgsql security definer set search_path = public, extensions as $$
declare
  n integer;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  delete from feedback where id = any (p_ids);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke execute on function public.creator_feedback_delete(uuid[]) from public, anon;
grant execute on function public.creator_feedback_delete(uuid[]) to authenticated;
