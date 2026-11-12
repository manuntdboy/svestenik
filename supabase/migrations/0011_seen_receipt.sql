-- „Видяно“: кога свещеникът е отворил молбата за потвърждение.
-- Слага се само от него (функцията mark_event_seen), веднъж за молба;
-- нулира се, когато събитието се прехвърли на друг свещеник.
alter table public.events add column seen_at timestamptz;

create or replace function public.events_seen_guard()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if coalesce(current_setting('kairos.seen', true), '') = 'on' then return new; end if;
  if tg_op = 'INSERT' then
    new.seen_at := null;
  elsif new.assignee_id is distinct from old.assignee_id then
    new.seen_at := null;
  else
    new.seen_at := old.seen_at;
  end if;
  return new;
end;
$$;
create trigger events_seen_guard before insert or update on public.events
  for each row execute function public.events_seen_guard();

create or replace function public.mark_event_seen(p_event uuid)
returns timestamptz language plpgsql security definer set search_path = public, extensions as $$
declare
  t timestamptz;
begin
  perform set_config('kairos.seen', 'on', true);
  update events set seen_at = coalesce(seen_at, now())
   where id = p_event and assignee_id = auth.uid() and assignee_id <> owner_id
   returning seen_at into t;
  perform set_config('kairos.seen', 'off', true);
  return t;
end;
$$;

revoke execute on function public.mark_event_seen(uuid) from public, anon;
grant execute on function public.mark_event_seen(uuid) to authenticated;
