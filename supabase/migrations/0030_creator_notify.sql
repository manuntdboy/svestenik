-- =====================================================================
-- „Кайрос в числа“: известията по вид на резултата вместо общо „неуспешни“.
--  * доставени   – колко телефона реално са получили известие
--  * без получател – само до себе си / човек без записан телефон (не е грешка)
--  * отказани    – опит без вход или без права (401/403/409) – защита;
--                  сред тях проверките на сървъра от GitHub (вид „smoke“)
--  * грешки      – само истинските: сървърът, Firebase или грешна заявка
-- =====================================================================

alter function public.creator_stats() rename to creator_stats_base;
revoke execute on function public.creator_stats_base() from public, anon, authenticated;

create or replace function public.creator_notify_window(p_since interval)
returns jsonb language sql stable security definer set search_path = public, extensions as $$
  select jsonb_build_object(
    'delivered', coalesce(sum((info->>'sent')::int) filter (where status = 200), 0),
    'calls', count(*) filter (where status = 200 and type <> 'smoke'),
    'no_recipient', count(*) filter (where status = 200 and coalesce((info->>'sent')::int, 0) = 0
                                       and coalesce(jsonb_array_length(info->'fcm_errors'), 0) = 0),
    'refused', count(*) filter (where status in (401, 403, 409) or type = 'smoke'),
    'errors', count(*) filter (where type <> 'smoke' and (status not in (200, 401, 403, 409)
                                 or coalesce(jsonb_array_length(info->'fcm_errors'), 0) > 0))
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
                          'fcm', info->'fcm_errors') order by at desc)
                        from (select * from notify_log
                               where type <> 'smoke' and (status not in (200, 401, 403, 409)
                                     or coalesce(jsonb_array_length(info->'fcm_errors'), 0) > 0)
                               order by at desc limit 8) f), '[]'::jsonb)
  );
end;
$$;
revoke execute on function public.creator_stats() from public, anon;
grant execute on function public.creator_stats() to authenticated;
