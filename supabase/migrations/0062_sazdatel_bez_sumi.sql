-- Създателят не вижда суми: дневникът, чакащите записи и известията от
-- него показват само дата, час, автор и вид. Заключено тук, в сървъра –
-- приложението просто няма откъде да ги получи.

create or replace function public.creator_activity(p_user uuid default null, p_church uuid default null, p_limit integer default 150)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(x order by (x->>'at') desc) from (
    select jsonb_build_object('at', l.at, 'action', l.action,
             -- Касата: само видът (приход/разход/движение), без суми и бележки.
             'details', case when l.action in ('Нов запис в касата', 'Сторно в касата', 'Върна запис')
                               or l.action like 'Одобри запис%'
                             then substring(l.details from '^(приход|разход|движение)')
                             else l.details end,
             'actor', coalesce(pa.full_name, case when l.actor_id is null then 'система' else '—' end),
             'target', case when l.target_id is distinct from l.actor_id then pt.full_name end,
             'church', c.name,
             'by_creator', l.actor_id in (select user_id from app_creators)) x
      from activity_log l
      left join profiles pa on pa.id = l.actor_id
      left join profiles pt on pt.id = l.target_id
      left join churches c on c.id = l.church_id
     where (p_user is null or l.actor_id = p_user or l.target_id = p_user)
       and (p_church is null or l.church_id = p_church)
     order by l.at desc
     limit least(greatest(coalesce(p_limit, 150), 1), 500)) q), '[]'::jsonb);
end;
$$;

create or replace function public.creator_cash_overview(p_church uuid)
returns jsonb language plpgsql stable security definer set search_path = public, extensions as $$
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'pending', coalesce((select jsonb_agg(jsonb_build_object(
        'id', e.id, 'book', e.book, 'category', e.category,
        'date', e.entry_date, 'by', p.full_name, 'at', e.created_at, 'reverses', e.reverses is not null) order by e.created_at)
      from cash_entries e left join profiles p on p.id = e.created_by
     where e.church_id = p_church and e.status = 'pending'), '[]'::jsonb),
    'periods', coalesce((select jsonb_agg(jsonb_build_object('month', month, 'status', status) order by month desc)
      from cash_periods where church_id = p_church), '[]'::jsonb));
end;
$$;

create or replace function public.creator_cash_decide(p_entry uuid, p_approve boolean, p_reason text)
returns uuid[] language plpgsql security definer set search_path = public, extensions as $$
declare
  r cash_entries;
  what text;
begin
  if not public.is_creator() then raise exception 'forbidden'; end if;
  select * into r from cash_entries where id = p_entry for update;
  if not found then raise exception 'not_found'; end if;
  if r.status <> 'pending' then raise exception 'not_pending'; end if;
  if p_approve then
    r := cash_book_in(r.id, null);
    update cash_entries set by_creator = true where id = r.id returning * into r;
    what := 'Създателят на Кайрос одобри запис № ' || r.number;
  else
    update cash_entries set status = 'returned', decided_by = auth.uid(), decided_at = now(), by_creator = true,
                            return_reason = nullif(trim(p_reason), '')
     where id = r.id returning * into r;
    what := 'Създателят на Кайрос върна запис' || coalesce(' („' || r.return_reason || '“)', '');
  end if;
  return public.cash_staff_notice(r.church_id, 'Каса: решение от създателя',
    what || ': ' || case r.book when 'income' then 'приход' when 'expense' then 'разход' else 'движение' end
         || ', ' || r.category || '.');
end;
$$;
