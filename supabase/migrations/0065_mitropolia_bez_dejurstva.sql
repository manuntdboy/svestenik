-- Митрополията не вижда дежурствата на храмовете (решено 18.11.2026 –
-- вътрешният живот на храма не е за контрол отгоре). Остават адрес, Булстат.
create or replace function public.diocese_church(p_church uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.can_view_church_from_diocese(p_church) then raise exception 'forbidden'; end if;
  return (select jsonb_build_object(
      'id', c.id, 'name', c.name, 'settlement', c.settlement, 'municipality', c.municipality,
      'address', c.address, 'bulstat', c.bulstat, 'vicariate_id', c.vicariate_id)
    from churches c where c.id = p_church);
end;
$$;
