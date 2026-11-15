-- Основен храм: всеки свещеник си отбелязва един, който е най-отгоре в
-- списъка и с който се отваря приложението. Пази се на сървъра, за да важи
-- и на компютъра, и на нов телефон.
alter table public.profiles
  add column primary_church uuid references public.churches(id) on delete set null;

create or replace function public.set_primary_church(p_church uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if auth.uid() is null then raise exception 'forbidden'; end if;
  if p_church is not null and not exists (
       select 1 from church_members
        where church_id = p_church and user_id = auth.uid() and status = 'active') then
    raise exception 'not_member';
  end if;
  update profiles set primary_church = p_church where id = auth.uid();
end;
$$;
revoke execute on function public.set_primary_church(uuid) from public, anon;
grant execute on function public.set_primary_church(uuid) to authenticated;

-- Ако човекът напусне храма или бъде махнат – основният се изчиства.
create or replace function public.primary_church_cleanup()
returns trigger language plpgsql security definer set search_path = public, extensions as $$
begin
  if tg_op = 'DELETE' or new.status <> 'active' then
    update profiles set primary_church = null
     where id = old.user_id and primary_church = old.church_id;
  end if;
  return null;
end;
$$;
create trigger primary_church_cleanup after update of status or delete on public.church_members
  for each row execute function public.primary_church_cleanup();
