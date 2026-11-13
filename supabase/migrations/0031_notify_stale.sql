-- =====================================================================
-- „Кайрос в числа“: стар/изтрит телефон (Firebase 404 – приложението е
-- преинсталирано, изтрито или данните са изчистени) не е грешка. Сървърът
-- сам маха такъв адрес и при следващото отваряне телефонът се записва наново.
-- Стари записи: 404 в fcm_errors; нови: поле „stale“.
-- =====================================================================

-- Колко стари телефона има в един ред от дневника.
create or replace function public.notify_stale_count(p_info jsonb)
returns integer language sql immutable as $$
  select coalesce((p_info->>'stale')::int, 0)
       + coalesce((select count(*)::int from jsonb_array_elements_text(
                     case when jsonb_typeof(p_info->'fcm_errors') = 'array' then p_info->'fcm_errors' else '[]'::jsonb end) e
                   where e = '404'), 0);
$$;

-- Колко истински грешки от Firebase (всичко освен 404).
create or replace function public.notify_fcm_real_errors(p_info jsonb)
returns integer language sql immutable as $$
  select coalesce((select count(*)::int from jsonb_array_elements_text(
                     case when jsonb_typeof(p_info->'fcm_errors') = 'array' then p_info->'fcm_errors' else '[]'::jsonb end) e
                   where e <> '404'), 0);
$$;

-- Ред, който е истинска грешка.
create or replace function public.notify_is_error(p_type text, p_status integer, p_info jsonb)
returns boolean language sql immutable as $$
  select p_type <> 'smoke'
     and (p_status not in (200, 401, 403, 409) or public.notify_fcm_real_errors(p_info) > 0);
$$;

revoke execute on function public.notify_stale_count(jsonb) from public, anon, authenticated;
revoke execute on function public.notify_fcm_real_errors(jsonb) from public, anon, authenticated;
revoke execute on function public.notify_is_error(text, integer, jsonb) from public, anon, authenticated;

create or replace function public.creator_notify_window(p_since interval)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'delivered', coalesce(sum((info->>'sent')::int) filter (where status = 200), 0),
    'calls', count(*) filter (where status = 200 and type <> 'smoke'),
    'no_recipient', count(*) filter (where status = 200 and coalesce((info->>'sent')::int, 0) = 0
                                       and public.notify_stale_count(info) = 0
                                       and public.notify_fcm_real_errors(info) = 0),
    'stale', coalesce(sum(public.notify_stale_count(info)) filter (where status = 200), 0),
    'refused', count(*) filter (where status in (401, 403, 409) or type = 'smoke'),
    'errors', count(*) filter (where public.notify_is_error(type, status, info))
  )
  from notify_log where at >= now() - p_since;
$$;
revoke execute on function public.creator_notify_window(interval) from public, anon, authenticated;

create or replace function public.creator_stats()
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return public.creator_stats_base() || jsonb_build_object(
    'notify', jsonb_build_object(
      'd1', public.creator_notify_window(interval '1 day'),
      'd7', public.creator_notify_window(interval '7 days'),
      'since', (select min(at) from notify_log)),
    'notify_by_type', coalesce((select jsonb_object_agg(type, n) from
                        (select type, sum(coalesce((info->>'sent')::int, 0)) n from notify_log
                          where at >= now() - interval '7 days' and status = 200 and type <> 'smoke'
                          group by type) k where n > 0), '{}'::jsonb),
    'notify_failed', coalesce((select jsonb_agg(jsonb_build_object(
                          'at', at, 'type', type, 'status', status,
                          'error', coalesce(info->>'error', 'fcm'),
                          'fcm', (select coalesce(jsonb_agg(e), '[]'::jsonb)
                                    from jsonb_array_elements(coalesce(info->'fcm_errors', '[]'::jsonb)) e
                                   where e::text <> '404')) order by at desc)
                        from (select * from notify_log
                               where public.notify_is_error(type, status, info)
                               order by at desc limit 8) f), '[]'::jsonb)
  );
end;
$$;
revoke execute on function public.creator_stats() from public, anon;
grant execute on function public.creator_stats() to authenticated;
