-- Създателят: в коя епархия е човек (за длъжностите – наместниците се
-- предлагат само от неговата епархия).
create or replace function public.creator_user_diocese(p_user uuid)
returns uuid language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return (select diocese_id from profiles where id = p_user);
end;
$$;
revoke execute on function public.creator_user_diocese(uuid) from public, anon;
grant execute on function public.creator_user_diocese(uuid) to authenticated;
