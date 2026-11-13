-- =====================================================================
-- Съгласие за личните данни (GDPR): кога и коя версия на текста е приел.
-- Без съгласие приложението показва текста и не продължава.
-- =====================================================================
alter table public.profiles
  add column privacy_version integer not null default 0,
  add column privacy_accepted_at timestamptz;

create or replace function public.privacy_accept(p_version integer)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  update profiles set privacy_version = greatest(coalesce(p_version, 0), 0), privacy_accepted_at = now()
   where id = auth.uid();
end;
$$;
revoke execute on function public.privacy_accept(integer) from public, anon;
grant execute on function public.privacy_accept(integer) to authenticated;
