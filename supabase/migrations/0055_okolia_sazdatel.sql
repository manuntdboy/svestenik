-- Околията на храма: при създаване я избира председателят (от своята
-- епархия); после я сменя само създателят.
create or replace function public.create_church_in(p_name text, p_settlement text, p_municipality text,
                                                  p_vicariate uuid)
returns public.churches language plpgsql security definer set search_path = public, extensions as $$
declare
  c churches;
  vd uuid;
begin
  if auth.uid() is null then raise exception 'not_authenticated'; end if;
  select diocese_id into vd from vicariates where id = p_vicariate;
  if vd is null then raise exception 'not_found'; end if;
  if vd is distinct from (select diocese_id from profiles where id = auth.uid()) and not public.is_creator() then
    raise exception 'other_diocese';
  end if;
  insert into churches (name, settlement, municipality, join_code, created_by, diocese_id, vicariate_id)
  values (trim(p_name), trim(p_settlement), trim(p_municipality), new_join_code(), auth.uid(), vd, p_vicariate)
  returning * into c;
  insert into church_members (church_id, user_id, role) values (c.id, auth.uid(), 'manager');
  return c;
end;
$$;

-- Само създателят. Може да премести храма и в друга епархия, ако никой от
-- членовете не е от трета.
create or replace function public.church_set_vicariate(p_church uuid, p_vicariate uuid)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  vd uuid;
  cd uuid;
  vname text;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  select diocese_id, name into vd, vname from vicariates where id = p_vicariate;
  if vd is null then raise exception 'not_found'; end if;
  select diocese_id into cd from churches where id = p_church;
  if cd is distinct from vd then
    if exists (select 1 from church_members m join profiles p on p.id = m.user_id
                where m.church_id = p_church and p.diocese_id is not null and p.diocese_id <> vd
                  and not exists (select 1 from app_creators a where a.user_id = m.user_id)) then
      raise exception 'members_other_diocese';
    end if;
  end if;
  update churches set diocese_id = vd, vicariate_id = p_vicariate where id = p_church;
  perform log_act(p_church, null, 'Околия на храма', vname);
end;
$$;

revoke execute on function public.create_church_in(text, text, text, uuid) from public, anon;
grant execute on function public.create_church_in(text, text, text, uuid) to authenticated;
