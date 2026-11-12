-- Потвърждения за участие в Архиерейска Литургия: всеки свещеник в храма
-- получава известие и натиска „Приемам“. Виждат се от всички в храма.
create table public.event_confirmations (
  event_id     uuid not null references public.events (id) on delete cascade,
  user_id      uuid not null default auth.uid() references auth.users (id) on delete cascade,
  confirmed_at timestamptz not null default now(),
  primary key (event_id, user_id)
);
alter table public.event_confirmations enable row level security;

create policy event_confirmations_select on public.event_confirmations for select to authenticated
  using (exists (select 1 from events e
                 where e.id = event_id and e.visibility = 'church' and public.is_member(e.church_id)));
-- Записва се само през confirm_event (без пряко писане).

create or replace function public.confirm_event(p_event uuid)
returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare
  ev events;
  t timestamptz;
begin
  select * into ev from events where id = p_event;
  if not found then raise exception 'not_found'; end if;
  if ev.kind <> 'arhiereyska' or ev.visibility <> 'church' then raise exception 'not_church_event'; end if;
  if not is_member(ev.church_id) then raise exception 'not_member'; end if;
  insert into event_confirmations (event_id, user_id) values (p_event, auth.uid())
    on conflict (event_id, user_id) do nothing;
  select confirmed_at into t from event_confirmations where event_id = p_event and user_id = auth.uid();
  return t;
end;
$$;
revoke execute on function public.confirm_event(uuid) from public, anon;
grant execute on function public.confirm_event(uuid) to authenticated;

-- Архиерейската Литургия е винаги споделена с храма.
create or replace function public.events_archieratic_shared()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.kind = 'arhiereyska' then new.visibility := 'church'; end if;
  return new;
end;
$$;
create trigger events_archieratic_shared before insert or update on public.events
  for each row execute function public.events_archieratic_shared();
