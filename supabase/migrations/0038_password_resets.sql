-- =====================================================================
-- Забравена парола: председателят дава временна парола (сървърна функция
-- reset_password). Тук се пази кой, на кого и кога; докато свещеникът не
-- смени паролата си, приложението го кара да я смени.
-- =====================================================================

create table public.password_resets (
  id          bigint generated always as identity primary key,
  church_id   uuid references public.churches (id) on delete set null,
  user_id     uuid not null references auth.users (id) on delete cascade,
  by_user     uuid references auth.users (id) on delete set null,
  at          timestamptz not null default now(),
  changed_at  timestamptz
);
create index password_resets_user_idx on public.password_resets (user_id, at);
alter table public.password_resets enable row level security;
revoke all on public.password_resets from anon, authenticated;

-- Трябва ли да сменя паролата (има временна, която още не е сменил).
create or replace function public.password_must_change()
returns boolean language sql stable security definer set search_path = public, extensions as $$
  select exists (select 1 from password_resets where user_id = auth.uid() and changed_at is null);
$$;

-- Извиква се след успешна смяна на паролата.
create or replace function public.password_changed()
returns void language sql security definer set search_path = public, extensions as $$
  update password_resets set changed_at = now() where user_id = auth.uid() and changed_at is null;
$$;

revoke execute on function public.password_must_change() from public, anon;
revoke execute on function public.password_changed() from public, anon;
grant execute on function public.password_must_change() to authenticated;
grant execute on function public.password_changed() to authenticated;
