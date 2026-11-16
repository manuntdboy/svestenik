-- Митрополията: длъжности и изглед „Епархия“.
-- Митрополит, секретар и протосингел – по един на епархия; архиерейски
-- наместник – по един на духовна околия. Митрополита оторизира само
-- създателят; останалите – създателят или митрополитът на епархията.
-- Изгледът показва храмовете и свещениците (сан, длъжност, телефон), но
-- НЕ касата, склада, почивките и службите.

alter table public.profiles drop constraint if exists profiles_rank_check;
alter table public.profiles add constraint profiles_rank_check check (rank in (
  'deacon', 'hierodeacon', 'protodeacon', 'archdeacon',
  'priest', 'hieromonk', 'archpriest', 'stavrophor', 'archimandrite', 'bishop', 'metropolitan'));

create table public.diocese_staff (
  diocese_id   uuid not null references public.dioceses (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  role         text not null check (role in ('metropolitan', 'secretary', 'protosyngel', 'vicar')),
  vicariate_id uuid references public.vicariates (id) on delete cascade,
  created_at   timestamptz not null default now(),
  check ((role = 'vicar') = (vicariate_id is not null))
);
create unique index diocese_staff_one_per_diocese on public.diocese_staff (diocese_id, role) where role <> 'vicar';
create unique index diocese_staff_one_per_vicariate on public.diocese_staff (vicariate_id) where role = 'vicar';
create unique index diocese_staff_user_role on public.diocese_staff (user_id, role, coalesce(vicariate_id, diocese_id));

alter table public.diocese_staff enable row level security;
-- Кой заема длъжностите в епархията не е тайна.
create policy diocese_staff_read on public.diocese_staff for select to authenticated using (true);
revoke insert, update, delete on public.diocese_staff from anon, authenticated;
grant select on public.diocese_staff to authenticated;

create or replace function public.is_metropolitan_of(p_diocese uuid)
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from diocese_staff where diocese_id = p_diocese and user_id = auth.uid()
                  and role = 'metropolitan');
$$;

-- Назначава човек на длъжност в неговата епархия (замества досегашния).
create or replace function public.staff_set(p_user uuid, p_role text, p_vicariate uuid default null)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  d uuid;
  vd uuid;
  label text;
begin
  select diocese_id into d from profiles where id = p_user;
  if d is null then raise exception 'no_diocese'; end if;
  if p_role = 'metropolitan' then
    if not public.is_creator() then raise exception 'forbidden'; end if;
  elsif p_role in ('secretary', 'protosyngel', 'vicar') then
    if not (public.is_creator() or public.is_metropolitan_of(d)) then raise exception 'forbidden'; end if;
  else
    raise exception 'bad_role';
  end if;
  if p_role = 'vicar' then
    select diocese_id into vd from vicariates where id = p_vicariate and not is_center;
    if vd is distinct from d then raise exception 'other_diocese'; end if;
    delete from diocese_staff where role = 'vicar' and vicariate_id = p_vicariate;
  else
    p_vicariate := null;
    delete from diocese_staff where diocese_id = d and role = p_role;
  end if;
  insert into diocese_staff (diocese_id, user_id, role, vicariate_id) values (d, p_user, p_role, p_vicariate);
  if p_role = 'metropolitan' then update profiles set rank = 'metropolitan' where id = p_user; end if;
  label := case p_role when 'metropolitan' then 'Митрополит' when 'secretary' then 'Секретар'
             when 'protosyngel' then 'Протосингел' else 'Архиерейски наместник' end;
  insert into activity_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user, 'Длъжност в митрополията', label ||
          coalesce(' · ' || (select name from vicariates where id = p_vicariate), ''));
end;
$$;

-- Освобождава длъжност.
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
  insert into activity_log (actor_id, target_id, action, details)
  values (auth.uid(), p_user, 'Освободен от длъжност в митрополията', p_role);
end;
$$;

-- Изглед „Епархия“: разделите (център и околии) → храмовете → свещениците.
-- Митрополит и секретар – цялата епархия; протосингел – центъра; наместник –
-- своята околия; създателят – всяка епархия.
create or replace function public.diocese_overview(p_diocese uuid default null)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  d uuid := p_diocese;
  scope uuid[];
  full_view boolean := false;
begin
  if d is null then
    select diocese_id into d from diocese_staff where user_id = auth.uid() order by
      case role when 'metropolitan' then 0 when 'secretary' then 1 when 'protosyngel' then 2 else 3 end limit 1;
  end if;
  if d is null then raise exception 'forbidden'; end if;
  if public.is_creator() or exists (select 1 from diocese_staff where diocese_id = d and user_id = auth.uid()
                                     and role in ('metropolitan', 'secretary')) then
    full_view := true;
  else
    select array_agg(case when s.role = 'vicar' then s.vicariate_id
                          else (select v.id from vicariates v where v.diocese_id = d and v.is_center) end)
      into scope
      from diocese_staff s where s.diocese_id = d and s.user_id = auth.uid() and s.role in ('protosyngel', 'vicar');
    if scope is null then raise exception 'forbidden'; end if;
  end if;
  return jsonb_build_object(
    'diocese', (select jsonb_build_object('id', id, 'name', name) from dioceses where id = d),
    'staff', coalesce((select jsonb_agg(jsonb_build_object(
        'user_id', s.user_id, 'role', s.role, 'vicariate_id', s.vicariate_id,
        'name', p.full_name, 'rank', p.rank, 'phone', p.phone))
      from diocese_staff s join profiles p on p.id = s.user_id where s.diocese_id = d), '[]'::jsonb),
    'sections', coalesce((select jsonb_agg(jsonb_build_object(
        'id', v.id, 'name', v.name, 'is_center', v.is_center,
        'churches', coalesce((select jsonb_agg(jsonb_build_object(
            'id', c.id, 'name', c.name, 'settlement', c.settlement, 'address', c.address,
            'priests', coalesce((select jsonb_agg(jsonb_build_object(
                'user_id', p.id, 'name', p.full_name, 'rank', p.rank, 'phone', p.phone,
                'chair', m.role = 'manager', 'cashier', 'cash' = any (m.permissions))
                order by (m.role = 'manager') desc, p.full_name)
              from church_members m join profiles p on p.id = m.user_id
              where m.church_id = c.id and m.status = 'active'), '[]'::jsonb))
            order by c.settlement, c.name)
          from churches c where c.vicariate_id = v.id), '[]'::jsonb))
        order by v.is_center desc, v.sort)
      from vicariates v where v.diocese_id = d and (full_view or v.id = any (scope))), '[]'::jsonb));
end;
$$;

revoke execute on function public.is_metropolitan_of(uuid) from public, anon;
revoke execute on function public.staff_set(uuid, text, uuid) from public, anon;
revoke execute on function public.staff_remove(uuid, text, uuid) from public, anon;
revoke execute on function public.diocese_overview(uuid) from public, anon;
grant execute on function public.is_metropolitan_of(uuid) to authenticated;
grant execute on function public.staff_set(uuid, text, uuid) to authenticated;
grant execute on function public.staff_remove(uuid, text, uuid) to authenticated;
grant execute on function public.diocese_overview(uuid) to authenticated;
