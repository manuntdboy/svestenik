-- Длъжността „митрополит“ помни предишния сан и го връща при освобождаване
-- (за проба създателят може да се сложи митрополит и после да се върне).
alter table public.profiles add column if not exists rank_before_metro text;

create or replace function public.staff_set(p_user uuid, p_role text, p_vicariate uuid default null,
                                           p_title text default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  d uuid;
  vd uuid;
  label text;
  t text := nullif(btrim(coalesce(p_title, '')), '');
begin
  select diocese_id into d from profiles where id = p_user;
  if d is null then raise exception 'no_diocese'; end if;
  if p_role = 'metropolitan' then
    if not public.is_creator() then raise exception 'forbidden'; end if;
  elsif p_role in ('secretary', 'protosyngel', 'vicar', 'employee') then
    if not (public.is_creator() or public.is_metropolitan_of(d)) then raise exception 'forbidden'; end if;
  else
    raise exception 'bad_role';
  end if;
  if p_role = 'vicar' then
    select diocese_id into vd from vicariates where id = p_vicariate and not is_center;
    if vd is distinct from d then raise exception 'other_diocese'; end if;
    delete from diocese_staff where role = 'vicar' and vicariate_id = p_vicariate;
  elsif p_role = 'employee' then
    if t is null then raise exception 'bad_name'; end if;
    p_vicariate := null;
    delete from diocese_staff where user_id = p_user and role = 'employee';
  else
    p_vicariate := null;
    -- Досегашният митрополит на епархията си връща предишния сан.
    if p_role = 'metropolitan' then
      update profiles pr set rank = pr.rank_before_metro, rank_before_metro = null
       where pr.id in (select user_id from diocese_staff where diocese_id = d and role = 'metropolitan'
                        and user_id <> p_user)
         and pr.rank = 'metropolitan';
    end if;
    delete from diocese_staff where diocese_id = d and role = p_role;
  end if;
  insert into diocese_staff (diocese_id, user_id, role, vicariate_id, title)
  values (d, p_user, p_role, p_vicariate, case when p_role = 'employee' then left(t, 60) end);
  if p_role = 'metropolitan' then
    update profiles set rank_before_metro = case when rank = 'metropolitan' then rank_before_metro else rank end,
                        rank = 'metropolitan'
     where id = p_user;
  end if;
  label := case p_role when 'metropolitan' then 'Митрополит' when 'secretary' then 'Секретар'
             when 'protosyngel' then 'Протосингел' when 'employee' then 'Служител · ' || t
             else 'Архиерейски наместник' end;
  insert into activity_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user, 'Длъжност в митрополията', label ||
          coalesce(' · ' || (select name from vicariates where id = p_vicariate), ''));
end;
$$;

create or replace function public.staff_remove(p_user uuid, p_role text, p_vicariate uuid default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  d uuid;
begin
  select diocese_id into d from diocese_staff
   where user_id = p_user and role = p_role and vicariate_id is not distinct from p_vicariate;
  if d is null then raise exception 'not_found'; end if;
  if p_role = 'metropolitan' and not public.is_creator() then raise exception 'forbidden'; end if;
  if not (public.is_creator() or public.is_metropolitan_of(d)) then raise exception 'forbidden'; end if;
  delete from diocese_staff
   where user_id = p_user and role = p_role and vicariate_id is not distinct from p_vicariate;
  if p_role = 'metropolitan' then
    update profiles set rank = rank_before_metro, rank_before_metro = null
     where id = p_user and rank = 'metropolitan';
  end if;
  insert into activity_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user, 'Освободен от длъжност в митрополията', p_role);
end;
$$;
