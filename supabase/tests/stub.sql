-- Минимална „Supabase“ за тестове: роли, auth, разширенията в схема
-- extensions и хранилище. Само за тестовата база, не за сървъра.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
create schema extensions;
create extension pgcrypto schema extensions;
create extension citext schema extensions;
select set_config('search_path', '"$user", public, extensions', false) \g /dev/null
do $$ begin execute format('alter database %I set search_path = "$user", public, extensions', current_database()); end $$;

create schema auth;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb default '{}',
  created_at timestamptz default now(),
  last_sign_in_at timestamptz
);
create table auth.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  updated_at timestamptz default now()
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create schema storage;
create table storage.buckets (id text primary key, name text, public boolean,
  file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(),
  bucket_id text, name text, owner uuid default auth.uid());
alter table storage.objects enable row level security;
create function storage.foldername(name text) returns text[] language sql immutable as $$
  select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1]
$$;

grant usage on schema auth, extensions, public, storage to anon, authenticated;
grant all on storage.objects to authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
