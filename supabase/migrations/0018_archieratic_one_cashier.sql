-- 1) Нов вид събитие: Архиерейска Литургия (заема целия храм).
alter table public.events drop constraint if exists events_kind_check;
alter table public.events add constraint events_kind_check check (kind in
  ('krashtene','venchavka','pogrebenie','panihida','vodosvet','sluzhba','arhiereyska',
   'izpoved','maslosvet','kurban','drugo'));

-- 2) В един храм – само един касиер.
create or replace function public.set_member_permission(
  p_church uuid, p_user uuid, p_perm text, p_on boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  if p_perm <> all (array['cash']) then raise exception 'unknown_permission'; end if;
  if p_on and p_perm = 'cash' and exists (
       select 1 from church_members
        where church_id = p_church and user_id <> p_user and 'cash' = any (permissions)) then
    raise exception 'one_cashier';
  end if;
  update church_members
     set permissions = case
           when p_on then (select array_agg(distinct x) from unnest(permissions || p_perm) x)
           else array_remove(permissions, p_perm)
         end
   where church_id = p_church and user_id = p_user and status = 'active';
end;
$$;
