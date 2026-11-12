-- =====================================================================
-- Потвърждение на събитие, записано за колега
-- accepted – прието (или записано за себе си); pending – чака свещеника;
-- declined – свещеникът е отказал, решава председателят.
-- Състоянието се сменя само през функциите по-долу.
-- =====================================================================

alter table public.events
  add column assignment_status text not null default 'accepted'
    check (assignment_status in ('pending', 'accepted', 'declined')),
  add column decline_reason text check (char_length(decline_reason) <= 500),
  add column proposed_substitute uuid references auth.users (id) on delete set null,
  add column declined_by uuid references auth.users (id) on delete set null;

-- Записано за друг → чака потвърждение; за себе си → прието.
-- Ръчна промяна на състоянието и полетата за отказ се пренебрегва –
-- позволена е само от функциите (те вдигат флага kairos.assignment).
create or replace function public.events_assignment_guard()
returns trigger language plpgsql set search_path = public, extensions as $$
declare
  via_function boolean := coalesce(current_setting('kairos.assignment', true), '') = 'on';
begin
  if tg_op = 'INSERT' then
    new.assignment_status := case when new.assignee_id = auth.uid() then 'accepted' else 'pending' end;
    new.decline_reason := null;
    new.proposed_substitute := null;
    new.declined_by := null;
    return new;
  end if;
  if via_function then
    return new;
  end if;
  if new.assignee_id is distinct from old.assignee_id then
    -- записалият сменя свещеника → новият трябва да потвърди
    new.assignment_status := case when new.assignee_id = auth.uid() then 'accepted' else 'pending' end;
    new.decline_reason := null;
    new.proposed_substitute := null;
    new.declined_by := null;
  else
    new.assignment_status := old.assignment_status;
    new.decline_reason := old.decline_reason;
    new.proposed_substitute := old.proposed_substitute;
    new.declined_by := old.declined_by;
  end if;
  return new;
end;
$$;

create trigger events_assignment_guard before insert or update on public.events
  for each row execute function public.events_assignment_guard();

-- Свещеникът отговаря: приема или отказва (с причина и заместник по желание).
create or replace function public.respond_assignment(
  p_event uuid, p_accept boolean, p_reason text default null, p_substitute uuid default null)
returns public.events language plpgsql security definer set search_path = public, extensions as $$
declare
  e events;
begin
  select * into e from events where id = p_event for update;
  if not found then raise exception 'not_found'; end if;
  if e.assignee_id <> auth.uid() then raise exception 'not_assignee'; end if;
  if e.assignment_status <> 'pending' then raise exception 'not_pending'; end if;
  if not p_accept and p_substitute is not null
     and (p_substitute = auth.uid() or not is_member_user(e.church_id, p_substitute)) then
    raise exception 'bad_substitute';
  end if;
  perform set_config('kairos.assignment', 'on', true);
  if p_accept then
    update events set assignment_status = 'accepted', decline_reason = null,
                      proposed_substitute = null, declined_by = null
     where id = p_event returning * into e;
  else
    update events set assignment_status = 'declined',
                      decline_reason = nullif(trim(coalesce(p_reason, '')), ''),
                      proposed_substitute = p_substitute,
                      declined_by = auth.uid()
     where id = p_event returning * into e;
  end if;
  perform set_config('kairos.assignment', 'off', true);
  return e;
end;
$$;

-- Председателят решава отказа: прехвърля на заместник или оставя на същия.
create or replace function public.resolve_decline(p_event uuid, p_assignee uuid)
returns public.events language plpgsql security definer set search_path = public, extensions as $$
declare
  e events;
begin
  select * into e from events where id = p_event for update;
  if not found then raise exception 'not_found'; end if;
  if not is_manager(e.church_id) then raise exception 'not_manager'; end if;
  if e.assignment_status <> 'declined' then raise exception 'not_declined'; end if;
  if not is_member_user(e.church_id, p_assignee) then raise exception 'bad_substitute'; end if;
  perform set_config('kairos.assignment', 'on', true);
  update events
     set assignee_id = p_assignee,
         visibility = 'church',
         -- оставено на същия → прието по решение на председателя;
         -- поето от председателя → прието; друг → чака неговото потвърждение
         assignment_status = case
           when p_assignee = e.declined_by or p_assignee = auth.uid() then 'accepted'
           else 'pending' end,
         proposed_substitute = null
   where id = p_event returning * into e;
  perform set_config('kairos.assignment', 'off', true);
  return e;
end;
$$;

revoke execute on function public.respond_assignment(uuid, boolean, text, uuid) from public, anon;
revoke execute on function public.resolve_decline(uuid, uuid) from public, anon;
grant execute on function public.respond_assignment(uuid, boolean, text, uuid) to authenticated;
grant execute on function public.resolve_decline(uuid, uuid) to authenticated;
