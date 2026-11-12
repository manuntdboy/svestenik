-- Личният профил (три имена, дати, имен ден) и снимката вече се виждат и от
-- свещениците в общ храм (същото правило като за името – shares_church_with).
-- Променя ги пак само собственикът.
drop policy profile_details_select on public.profile_details;
create policy profile_details_select on public.profile_details for select to authenticated
  using (user_id = auth.uid() or public.shares_church_with(user_id));

-- Снимки: колегите могат да ги четат. Папката е <user_id>/…
create or replace function public.can_see_avatar(p_name text)
returns boolean language plpgsql stable security definer set search_path = public, extensions as $$
declare
  folder text := split_part(p_name, '/', 1);
begin
  if folder !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    return false;
  end if;
  return folder::uuid = auth.uid() or shares_church_with(folder::uuid);
end;
$$;
revoke execute on function public.can_see_avatar(text) from public, anon;
grant execute on function public.can_see_avatar(text) to authenticated;

create policy avatars_select_colleagues on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and public.can_see_avatar(name));
