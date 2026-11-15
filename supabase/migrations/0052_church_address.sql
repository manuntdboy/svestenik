-- Точен адрес и Булстат на храма. Виждат ги всички членове (през
-- обичайното правило за четене на храма); променя ги председателят или
-- създателят – само през функцията, с запис в дневника.
alter table public.churches
  add column address text check (char_length(address) <= 200),
  add column bulstat text check (bulstat ~ '^([0-9]{9}|[0-9]{13})$');

create or replace function public.church_set_info(p_church uuid, p_address text, p_bulstat text)
returns void language plpgsql security definer set search_path = public, extensions as $$
declare
  a text := nullif(btrim(regexp_replace(coalesce(p_address, ''), '\s+', ' ', 'g')), '');
  b text := nullif(regexp_replace(coalesce(p_bulstat, ''), '[^0-9]', '', 'g'), '');
begin
  if not (public.is_manager(p_church) or public.is_creator()) then raise exception 'not_manager'; end if;
  if a is not null and char_length(a) > 200 then raise exception 'address_too_long'; end if;
  if b is not null and b !~ '^([0-9]{9}|[0-9]{13})$' then raise exception 'bad_bulstat'; end if;
  update churches set address = a, bulstat = b where id = p_church;
  if not found then raise exception 'not_found'; end if;
  perform log_act(p_church, null, 'Адрес и Булстат на храма',
                  coalesce(a, '—') || ' · ' || coalesce(b, '—'));
end;
$$;
revoke execute on function public.church_set_info(uuid, text, text) from public, anon;
grant execute on function public.church_set_info(uuid, text, text) to authenticated;

-- Създателят вижда адреса и Булстата в прегледа на храма (за да ги поправи).
create or replace function public.creator_church_summary(p_church uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'name', (select name from churches where id = p_church),
    'address', (select address from churches where id = p_church),
    'bulstat', (select bulstat from churches where id = p_church),
    'members', (select count(*) from church_members where church_id = p_church),
    'events', (select count(*) from events where church_id = p_church),
    'cash', (select count(*) from cash_entries where church_id = p_church),
    'stock', (select count(*) from stock_moves where church_id = p_church),
    'chat', (select count(*) from chat_messages where church_id = p_church));
end;
$$;
