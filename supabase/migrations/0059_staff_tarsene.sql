-- Добавяне в администрацията на митрополията: търсене по име или телефон
-- сред регистрираните в епархията, вместо да се помни потребителското име.
create or replace function public.staff_candidates(p_diocese uuid, p_q text)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
declare
  q text := btrim(coalesce(p_q, ''));
  qd text := regexp_replace(q, '[^0-9]', '', 'g');
begin
  if not (public.is_creator() or public.is_metropolitan_of(p_diocese)) then raise exception 'forbidden'; end if;
  if char_length(q) < 2 then return '[]'::jsonb; end if;
  return coalesce((
    select jsonb_agg(x order by x->>'name')
    from (
      select jsonb_build_object(
        'user_id', p.id, 'username', p.username, 'name', p.full_name, 'rank', p.rank, 'phone', p.phone,
        'church', (select c.name || ' – ' || c.settlement from church_members m join churches c on c.id = m.church_id
                    where m.user_id = p.id and m.status = 'active'
                    order by (c.id = p.primary_church) desc nulls last, m.joined_at limit 1),
        'staff', (select string_agg(s.role, ',') from diocese_staff s where s.user_id = p.id and s.diocese_id = p_diocese)
      ) as x
      from profiles p
      where p.diocese_id = p_diocese
        and (p.full_name ilike '%' || q || '%' or p.username::text ilike '%' || q || '%'
             or (char_length(qd) >= 3 and regexp_replace(coalesce(p.phone, ''), '[^0-9]', '', 'g') like '%' || qd || '%'))
      limit 20
    ) t), '[]'::jsonb);
end;
$$;
revoke execute on function public.staff_candidates(uuid, text) from public, anon;
grant execute on function public.staff_candidates(uuid, text) to authenticated;
