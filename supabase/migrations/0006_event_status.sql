-- Състояние на събитието: предстои (planned), проведено (done), отменено (cancelled).
-- Отменените не се броят за застъпване и не напомнят; остават в календара за история.
alter table public.events
  add column status text not null default 'planned'
  check (status in ('planned', 'done', 'cancelled'));
