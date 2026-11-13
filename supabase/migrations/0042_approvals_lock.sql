-- =====================================================================
-- Тестовият режим „без второ одобрение“ се разрешава от създателя:
--  * изключен от създателя – второто одобрение е задължително и
--    председателят не може да го промени;
--  * включен от създателя – председателят сам го пуска и спира.
-- Сегашните храмове остават свободни (както досега); новите – задължително.
-- =====================================================================
alter table public.churches add column approvals_toggle_allowed boolean not null default false;
update public.churches set approvals_toggle_allowed = true;

create or replace function public.cash_save_settings(p_church uuid, p_limit numeric, p_has_bank boolean, p_approvals_off boolean)
returns public.cash_settings language plpgsql security definer set search_path = public, extensions as $$
declare
  s cash_settings;
  allowed boolean := coalesce((select approvals_toggle_allowed from churches where id = p_church), false);
  cur boolean := coalesce((select approvals_off from cash_settings where church_id = p_church), false);
begin
  if not is_manager(p_church) then raise exception 'not_manager'; end if;
  if coalesce(p_approvals_off, false) <> cur and not allowed then raise exception 'approvals_locked'; end if;
  insert into cash_settings (church_id, limit_eur, has_bank, approvals_off, updated_at)
  values (p_church, 100, coalesce(p_has_bank, false), coalesce(p_approvals_off, false), now())
  on conflict (church_id) do update
    set has_bank = excluded.has_bank, approvals_off = excluded.approvals_off, updated_at = now()
  returning * into s;
  return s;
end;
$$;

-- Създателят: включено = председателят може да ползва тестовия режим (и той
-- се пуска); изключено = второто одобрение е задължително и заключено.
create or replace function public.creator_church_settings(p_church uuid, p_cash boolean, p_stock boolean, p_approvals_off boolean)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  update churches set cash_enabled = coalesce(p_cash, cash_enabled), stock_enabled = coalesce(p_stock, stock_enabled),
                      approvals_toggle_allowed = coalesce(p_approvals_off, approvals_toggle_allowed)
   where id = p_church;
  if p_approvals_off is not null then
    insert into cash_settings (church_id, approvals_off) values (p_church, p_approvals_off)
    on conflict (church_id) do update set approvals_off = excluded.approvals_off, updated_at = now();
  end if;
end;
$$;

create or replace function public.creator_extra()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'min_build', (select min_build from app_config),
    'errors_24', (select count(*) from app_errors where at > now() - interval '1 day'),
    'errors_7', (select count(*) from app_errors where at > now() - interval '7 days'),
    'errors', coalesce((select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('id', e.id, 'at', e.at, 'build', e.build, 'screen', e.screen,
                                  'message', e.message, 'stack', e.stack,
                                  'user', coalesce(p.full_name, '—')) x
          from app_errors e left join profiles p on p.id = e.user_id
         order by e.at desc limit 40) q), '[]'::jsonb),
    'feedback', coalesce((select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('id', f.id, 'at', f.at, 'build', f.build, 'body', f.body, 'photo', f.photo_path,
                                  'done', f.done, 'user', coalesce(p.full_name, '—'),
                                  'rank', p.rank, 'church', c.name) x
          from feedback f left join profiles p on p.id = f.user_id left join churches c on c.id = f.church_id
         order by f.at desc limit 60) q), '[]'::jsonb),
    'announcements', coalesce((select jsonb_agg(x order by x->>'at' desc) from (
        select jsonb_build_object('id', a.id, 'at', a.created_at, 'title', a.title, 'body', a.body,
                                  'church', c.name,
                                  'seen', (select count(*) - 1 from announcement_seen s where s.announcement_id = a.id)) x
          from announcements a left join churches c on c.id = a.church_id
         order by a.created_at desc limit 20) q), '[]'::jsonb),
    'church_settings', coalesce((select jsonb_object_agg(c.id::text, jsonb_build_object(
        'cash', c.cash_enabled, 'stock', c.stock_enabled,
        'approvals_off', coalesce((select approvals_off from cash_settings s where s.church_id = c.id), false),
        'approvals_allowed', c.approvals_toggle_allowed))
        from churches c), '{}'::jsonb)
  );
end;
$$;
