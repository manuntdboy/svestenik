-- Дневник на известията: само служебни данни (вид, код, брой получатели,
-- устройства и изпратени, грешка). Без имена и без токени.
-- Пише и чете само сървърът (няма правила за потребителите).
create table public.notify_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  type text not null,
  status int not null,
  info jsonb
);
alter table public.notify_log enable row level security;
revoke all on public.notify_log from anon, authenticated;

-- Пазим две седмици.
create or replace function public.notify_log_trim()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  delete from notify_log where at < now() - interval '14 days';
  return new;
end;
$$;
create trigger notify_log_trim after insert on public.notify_log
  for each statement execute function public.notify_log_trim();
