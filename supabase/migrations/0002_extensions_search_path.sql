-- В Supabase pgcrypto и citext са в схема `extensions`, а функциите търсеха
-- само в `public` – затова „gen_random_bytes(integer) does not exist“.
-- Добавяме `extensions` в пътя за търсене на всички наши функции.

alter function public.new_join_code()                              set search_path = public, extensions;
alter function public.is_member(uuid)                              set search_path = public, extensions;
alter function public.is_manager(uuid)                             set search_path = public, extensions;
alter function public.shares_church_with(uuid)                     set search_path = public, extensions;
alter function public.handle_new_user()                            set search_path = public, extensions;
alter function public.username_available(text)                     set search_path = public, extensions;
alter function public.create_church(text, text, text)              set search_path = public, extensions;
alter function public.join_church(text)                            set search_path = public, extensions;
alter function public.regenerate_join_code(uuid)                   set search_path = public, extensions;
alter function public.remove_member(uuid, uuid)                    set search_path = public, extensions;
alter function public.leave_church(uuid)                           set search_path = public, extensions;
