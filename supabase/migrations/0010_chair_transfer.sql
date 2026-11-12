-- =====================================================================
-- Смяна на председателя
-- Председателят предлага свещеник от храма → свещеникът приема или отказва.
-- При приемане ролите се разменят: новият става председател, досегашният –
-- редови свещеник (правата му като касиер остават каквито са).
-- =====================================================================

alter table public.churches
  add column pending_chair uuid references auth.users (id) on delete set null,
  add column chair_proposed_by uuid references auth.users (id) on delete set null;

create or replace function public.propose_chair(p_church uuid, p_user uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  if p_user = auth.uid() then raise exception 'already_chair'; end if;
  if not is_member_user(p_church, p_user) then raise exception 'bad_substitute'; end if;
  update churches set pending_chair = p_user, chair_proposed_by = auth.uid() where id = p_church;
end;
$$;

create or replace function public.cancel_chair_transfer(p_church uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  update churches set pending_chair = null, chair_proposed_by = null where id = p_church;
end;
$$;

-- Предложеният отговаря. Връща кой е предложил (за известието).
create or replace function public.respond_chair(p_church uuid, p_accept boolean)
returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare
  c churches;
begin
  select * into c from churches where id = p_church for update;
  if not found then raise exception 'not_found'; end if;
  if c.pending_chair is distinct from auth.uid() then raise exception 'no_offer'; end if;
  if p_accept then
    if not is_member_user(p_church, auth.uid()) then raise exception 'not_member'; end if;
    update church_members set role = 'priest'
     where church_id = p_church and role = 'manager' and user_id <> auth.uid();
    update church_members set role = 'manager'
     where church_id = p_church and user_id = auth.uid();
  end if;
  update churches set pending_chair = null, chair_proposed_by = null where id = p_church;
  return c.chair_proposed_by;
end;
$$;

revoke execute on function public.propose_chair(uuid, uuid) from public, anon;
revoke execute on function public.cancel_chair_transfer(uuid) from public, anon;
revoke execute on function public.respond_chair(uuid, boolean) from public, anon;
grant execute on function public.propose_chair(uuid, uuid) to authenticated;
grant execute on function public.cancel_chair_transfer(uuid) to authenticated;
grant execute on function public.respond_chair(uuid, boolean) to authenticated;
