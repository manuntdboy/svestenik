-- =====================================================================
-- Личен профил на свещеника: три имена, дата на раждане, дата на
-- ръкоположение, имен ден и снимка. Вижда и променя само собственикът.
-- (Името за календара – profiles.full_name – остава видимо за колегите.)
-- Без ЕГН и други чувствителни данни.
-- =====================================================================

create table public.profile_details (
  user_id          uuid primary key default auth.uid() references auth.users (id) on delete cascade,
  three_names      text check (char_length(three_names) <= 150),
  birth_date       date check (birth_date between '1900-01-01' and '2100-12-31'),
  ordination_date  date check (ordination_date between '1900-01-01' and '2100-12-31'),
  name_day_month   smallint check (name_day_month between 1 and 12),
  name_day_day     smallint check (name_day_day between 1 and 31),
  photo_path       text check (char_length(photo_path) <= 300),
  updated_at       timestamptz not null default now(),
  check ((name_day_month is null) = (name_day_day is null))
);

alter table public.profile_details enable row level security;

create policy profile_details_select on public.profile_details for select to authenticated
  using (user_id = auth.uid());
create policy profile_details_insert on public.profile_details for insert to authenticated
  with check (user_id = auth.uid());
create policy profile_details_update on public.profile_details for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy profile_details_delete on public.profile_details for delete to authenticated
  using (user_id = auth.uid());

create trigger profile_details_touch before update on public.profile_details
  for each row execute function public.touch_updated_at();

-- ---------------------------------------------------------------------
-- Снимки: частно хранилище „avatars“. Всеки има своя папка <user_id>/
-- и само той може да чете, качва, сменя и трие файловете в нея.
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public = false,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

create policy avatars_select_own on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_insert_own on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_update_own on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
create policy avatars_delete_own on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
