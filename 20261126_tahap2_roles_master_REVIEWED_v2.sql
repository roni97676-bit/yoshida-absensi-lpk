-- LPK Yoshida Gakkou — Tahap 2, reviewed migration v2
-- TARGET: Supabase PREVIEW project only. NEVER run on Production.
-- Precondition: take a fresh backup and run diagnostics/00_preview_readonly_audit_snapshot.sql.
-- This migration does not modify app_docs rows or any app_docs RLS policy.

begin;

-- Fail closed: require the expected owner identity and the backup's sole legacy admin.
do $migration_guard$
declare
  owner_count bigint;
  owner_email text;
  owner_role text;
  owner_active boolean;
  legacy_admin_count bigint;
  unsupported_role_count bigint;
begin
  select count(*) into owner_count
  from public.app_users
  where id = '860c2a25-63cb-4b86-af1b-f57e19a585ed'::uuid;

  if owner_count <> 1 then
    raise exception 'ABORT: expected exactly one Yoshida owner row; found %.', owner_count;
  end if;

  select lower(email), role, active
    into owner_email, owner_role, owner_active
  from public.app_users
  where id = '860c2a25-63cb-4b86-af1b-f57e19a585ed'::uuid;

  if owner_email is distinct from 'roni97676@gmail.com' then
    raise exception 'ABORT: owner UUID email does not match the audited backup.';
  end if;
  if owner_role is distinct from 'admin' then
    raise exception 'ABORT: expected owner role=admin; found %.', owner_role;
  end if;
  if owner_active is distinct from true then
    raise exception 'ABORT: owner account is not active as in the audited backup; review manually.';
  end if;

  select count(*) into legacy_admin_count
  from public.app_users
  where role = 'admin';

  if legacy_admin_count <> 1 then
    raise exception 'ABORT: expected exactly one legacy admin (the owner); found %.', legacy_admin_count;
  end if;

  select count(*) into unsupported_role_count
  from public.app_users
  where role is null or role not in ('sensei', 'admin', 'tester');

  if unsupported_role_count <> 0 then
    raise exception 'ABORT: % user rows have unsupported role values; review before migration.', unsupported_role_count;
  end if;
end
$migration_guard$;

-- Add/normalize the owner marker without silently promoting any account.
alter table public.app_users
  add column if not exists is_master boolean;

update public.app_users
set is_master = false
where is_master is null;

alter table public.app_users
  alter column is_master set default false,
  alter column is_master set not null;

-- Refuse to overwrite a different pre-existing owner marker.
do $master_guard$
declare other_master_count bigint;
begin
  select count(*) into other_master_count
  from public.app_users
  where is_master is true
    and id <> '860c2a25-63cb-4b86-af1b-f57e19a585ed'::uuid;
  if other_master_count <> 0 then
    raise exception 'ABORT: another account is already marked is_master=true; review manually.';
  end if;
end
$master_guard$;

-- Remove only this guard trigger while the migration establishes the intended owner marker.
drop trigger if exists yg_protect_master_flag on public.app_users;

update public.app_users
set is_master = true,
    updated_at = now()
where id = '860c2a25-63cb-4b86-af1b-f57e19a585ed'::uuid;

create unique index if not exists app_users_single_master_idx
  on public.app_users ((is_master)) where is_master = true;

-- Replace role-related CHECK constraints to allow the three ordinary account roles.
do $role_constraints$
declare c record;
begin
  for c in
    select conname
    from pg_constraint
    where conrelid = 'public.app_users'::regclass
      and contype = 'c'
      and pg_get_constraintdef(oid) ilike '%role%'
  loop
    execute format('alter table public.app_users drop constraint %I', c.conname);
  end loop;
end
$role_constraints$;

alter table public.app_users
  add constraint app_users_role_check
  check (role in ('sensei', 'admin', 'tester'));

-- Master Admin is the only account treated as system admin by these RLS helper functions.
create or replace function public.yg_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.app_users u
    where u.id = auth.uid()
      and u.active is true
      and u.is_master is true
  );
$$;

create or replace function public.yg_can_manage_students()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.app_users u
    where u.id = auth.uid()
      and u.active is true
      and (
        u.is_master is true
        or coalesce((u.perms ->> 'siswa')::boolean, false)
      )
  );
$$;

-- Prevent ordinary API updates from changing the Master Admin marker.
-- Owner transfer requires a deliberate database-operator action.
create or replace function public.yg_protect_master_flag()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.is_master is distinct from old.is_master then
    raise exception 'Master Admin flag changes require a deliberate database-operator procedure.';
  end if;
  return new;
end;
$$;

create trigger yg_protect_master_flag
before update of is_master on public.app_users
for each row
execute function public.yg_protect_master_flag();

commit;

-- POST-MIGRATION CHECKS (read-only; run separately after commit):
-- select id, email, role, active, is_master from public.app_users order by email;
-- select count(*) as master_count from public.app_users where is_master is true;
-- select pg_get_functiondef('public.yg_is_admin()'::regprocedure);
-- select pg_get_functiondef('public.yg_can_manage_students()'::regprocedure);
-- select pg_get_triggerdef(oid) from pg_trigger where tgname='yg_protect_master_flag' and not tgisinternal;
-- Re-run diagnostics/00_preview_readonly_audit_snapshot.sql and compare counts/policies.
