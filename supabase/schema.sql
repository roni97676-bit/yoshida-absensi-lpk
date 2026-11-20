-- LPK Yoshida Gakkou - isolated UAT schema
create extension if not exists pgcrypto;

create table if not exists public.app_users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  phone text,
  name text not null,
  role text not null default 'sensei' check (role in ('admin','sensei')),
  perms jsonb not null default '{}'::jsonb,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.app_docs (
  collection text not null,
  id text not null,
  data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  primary key (collection,id)
);
create index if not exists app_docs_collection_idx on public.app_docs(collection);

create or replace function public.yg_is_active()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.app_users u where u.id=auth.uid() and u.active=true); $$;

create or replace function public.yg_is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.app_users u where u.id=auth.uid() and u.active=true and u.role='admin'); $$;

create or replace function public.yg_can_manage_students()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.app_users u where u.id=auth.uid() and u.active=true and (u.role='admin' or coalesce((u.perms->>'siswa')::boolean,false))); $$;

alter table public.app_users enable row level security;
alter table public.app_docs enable row level security;

-- Do not expose application data to signed-out visitors.
revoke all on table public.app_users from anon, authenticated;
revoke all on table public.app_docs from anon, authenticated;
-- Signed-in users may read their own profile; admins may read the user directory.
grant select on table public.app_users to authenticated;
-- Signed-in active users use the shared application records; RLS policies below
-- determine which collections they may create, update, or delete.
grant select, insert, update, delete on table public.app_docs to authenticated;

drop policy if exists "active users can read user directory" on public.app_users;
drop policy if exists "users can read own profile and admins can read directory" on public.app_users;
create policy "users can read own profile and admins can read directory" on public.app_users for select to authenticated using (id = auth.uid() or public.yg_is_admin());

-- Authenticated active Sensei can read shared app data.
drop policy if exists "active users read app docs" on public.app_docs;
create policy "active users read app docs" on public.app_docs for select to authenticated using (public.yg_is_active());

-- Every active Sensei may create/update attendance, presence and audit entries.
drop policy if exists "active users insert shared docs" on public.app_docs;
create policy "active users insert shared docs" on public.app_docs for insert to authenticated
with check (public.yg_is_active() and collection in ('attendance','presence','audit','grades'));

drop policy if exists "active users update shared docs" on public.app_docs;
create policy "active users update shared docs" on public.app_docs for update to authenticated
using (public.yg_is_active() and collection in ('attendance','presence','grades'))
with check (public.yg_is_active() and collection in ('attendance','presence','grades'));

drop policy if exists "active users delete own presence or attendance" on public.app_docs;
drop policy if exists "active users delete shared docs" on public.app_docs;
create policy "active users delete shared docs" on public.app_docs for delete to authenticated
using (public.yg_is_active() and (collection in ('attendance','presence','grades') or (collection in ('students','classes') and public.yg_can_manage_students())));

-- Student/class master data writes are restricted to admin or Sensei with siswa permission.
drop policy if exists "authorized users insert master data" on public.app_docs;
create policy "authorized users insert master data" on public.app_docs for insert to authenticated
with check (public.yg_is_active() and collection in ('students','classes') and public.yg_can_manage_students());
drop policy if exists "authorized users update master data" on public.app_docs;
create policy "authorized users update master data" on public.app_docs for update to authenticated
using (public.yg_is_active() and collection in ('students','classes') and public.yg_can_manage_students())
with check (public.yg_is_active() and collection in ('students','classes') and public.yg_can_manage_students());

-- Realtime feeds used by the website.
do $$ begin
  alter publication supabase_realtime add table public.app_docs;
exception when duplicate_object then null;
when undefined_object then null;
end $$;
do $$ begin
  alter publication supabase_realtime add table public.app_users;
exception when duplicate_object then null;
when undefined_object then null;
end $$;
