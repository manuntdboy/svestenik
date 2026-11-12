-- =====================================================================
-- Права в храма, които дава председателят.
-- 'cash' = касиер: достъп до данните на касата (модулът идва по-късно).
-- Председателят има всички права. Редовите свещеници – само дадените им.
-- =====================================================================

alter table public.church_members
  add column permissions text[] not null default '{}'
  check (permissions <@ array['cash']::text[]);

-- Има ли текущият потребител право [p_perm] в храма. Ползва се от
-- правилата за достъп на касата (и бъдещи модули).
create or replace function public.has_permission(p_church uuid, p_perm text)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (
    select 1 from church_members
    where church_id = p_church and user_id = auth.uid() and status = 'active'
      and (role = 'manager' or p_perm = any (permissions)));
$$;

-- Председателят дава или отнема право на свещеник от храма.
create or replace function public.set_member_permission(
  p_church uuid, p_user uuid, p_perm text, p_on boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  if p_perm <> all (array['cash']) then raise exception 'unknown_permission'; end if;
  update church_members
     set permissions = case
           when p_on then (select array_agg(distinct x) from unnest(permissions || p_perm) x)
           else array_remove(permissions, p_perm)
         end
   where church_id = p_church and user_id = p_user and status = 'active';
end;
$$;

revoke execute on function public.set_member_permission(uuid, uuid, text, boolean) from public, anon;
grant execute on function public.set_member_permission(uuid, uuid, text, boolean) to authenticated;
revoke execute on function public.has_permission(uuid, text) from public, anon;
grant execute on function public.has_permission(uuid, text) to authenticated;
