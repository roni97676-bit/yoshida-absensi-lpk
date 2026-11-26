-- YOSHIDA GAKKOU — Tahap 2 permission/RLS hardening (REVIEW DRAFT)
-- DEPENDS ON: 20261126_tahap2_roles_master_REVIEWED_v2.sql
-- TARGET: dedicated PREVIEW project only. DO NOT RUN ON PRODUCTION.
-- Scope: app_docs policies, a byId metadata backfill, and a controlled student/history deletion RPC.
-- Before execution, compare the read-only diagnostics with the 2026-11-26 backup.
-- Assumed school timezone: Asia/Jakarta (attendance dates are Indonesian school dates).

begin;

-- Fail closed if this project is not at the expected post-v2 state or has unknown
-- app_docs policies that this reviewed policy set has not accounted for.
do $guard$
declare
  docs_rls boolean;
  docs_force_rls boolean;
  missing_helpers integer;
  unexpected_policies text[];
begin
  select c.relrowsecurity, c.relforcerowsecurity
    into docs_rls, docs_force_rls
  from pg_class c
  where c.oid = 'public.app_docs'::regclass;

  if docs_rls is distinct from true then
    raise exception 'ABORT: RLS is not enabled on public.app_docs.';
  end if;
  if docs_force_rls is true then
    raise exception 'ABORT: FORCE ROW LEVEL SECURITY is enabled on app_docs; review the SECURITY DEFINER deletion function owner before proceeding.';
  end if;

  select count(*) into missing_helpers
  from unnest(array[
    'public.yg_is_active()',
    'public.yg_is_admin()',
    'public.yg_can_manage_students()'
  ]) as expected(signature)
  where to_regprocedure(expected.signature) is null;

  if missing_helpers <> 0 then
    raise exception 'ABORT: expected post-v2 helper functions are missing.';
  end if;

  select array_agg(policyname order by policyname)
    into unexpected_policies
  from pg_policies
  where schemaname = 'public'
    and tablename = 'app_docs'
    and policyname not in (
      'active users delete shared docs',
      'active users insert shared docs',
      'active users read app docs',
      'active users update shared docs',
      'authorized users insert master data',
      'authorized users update master data',
      'stage2_read_master_data',
      'stage2_read_attendance',
      'stage2_read_grades',
      'stage2_read_presence',
      'stage2_read_audit',
      'stage2_insert_master_data',
      'stage2_insert_attendance',
      'stage2_insert_grades',
      'stage2_insert_presence',
      'stage2_insert_audit',
      'stage2_update_master_data',
      'stage2_update_attendance',
      'stage2_update_grades',
      'stage2_update_presence',
      'stage2_delete_students_classes',
      'stage2_delete_classes',
      'stage2_delete_batches_master',
      'stage2_delete_attendance',
      'stage2_delete_grades',
      'stage2_delete_presence'
    );

  if coalesce(array_length(unexpected_policies, 1), 0) > 0 then
    raise exception 'ABORT: unexpected app_docs policies exist: %. Review diagnostics first.', unexpected_policies;
  end if;

  if not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'app_users' and column_name = 'is_master'
  ) then
    raise exception 'ABORT: is_master column is missing; run the reviewed roles/master migration first.';
  end if;
end
$guard$;

-- Attribute old attendance/grade records to their original account when the
-- legacy byPhone value matches exactly one active/inactive app_users profile.
-- Ambiguous or unmatched records are intentionally left untouched.
with identities as (
  select id, lower(btrim(email)) as identity
  from public.app_users
  where nullif(btrim(email), '') is not null
  union all
  select id, lower(btrim(phone)) as identity
  from public.app_users
  where nullif(btrim(phone), '') is not null
), unique_identities as (
  select identity, min(id::text)::uuid as user_id
  from identities
  group by identity
  having count(distinct id) = 1
)
update public.app_docs d
set data = jsonb_set(d.data, '{byId}', to_jsonb(u.user_id::text), true),
    updated_at = now()
from unique_identities u
where d.collection in ('attendance', 'grades')
  and nullif(btrim(d.data->>'byId'), '') is null
  and lower(btrim(coalesce(d.data->>'byPhone', ''))) = u.identity;

-- Permission helpers. Master Admin bypasses ordinary permission flags.
create or replace function public.yg_has_permission(p_permission text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select case
    when p_permission is null or p_permission not in ('siswa', 'edit', 'rekap', 'export') then false
    else exists (
      select 1
      from public.app_users u
      where u.id = auth.uid()
        and u.active is true
        and (
          u.is_master is true
          or coalesce(u.perms @> jsonb_build_object(p_permission, true), false)
        )
    )
  end;
$$;

create or replace function public.yg_owns_app_doc(p_data jsonb)
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
        p_data->>'byId' = u.id::text
        or (
          nullif(btrim(p_data->>'byId'), '') is null
          and nullif(btrim(p_data->>'byPhone'), '') is not null
          and (
            lower(btrim(p_data->>'byPhone')) = lower(btrim(coalesce(u.email, '')))
            or lower(btrim(p_data->>'byPhone')) = lower(btrim(coalesce(u.phone, '')))
          )
        )
      )
  );
$$;

revoke all on function public.yg_has_permission(text) from public, anon;
revoke all on function public.yg_owns_app_doc(jsonb) from public, anon;
grant execute on function public.yg_has_permission(text) to authenticated;
grant execute on function public.yg_owns_app_doc(jsonb) to authenticated;

-- Student deletion is a controlled bundle operation. A user with siswa permission
-- cannot directly delete a student row and leave historical records orphaned.
create or replace function public.yg_delete_students_with_history(p_nis_list text[])
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_count integer;
  found_count integer;
  attendance_deleted integer := 0;
  grades_deleted integer := 0;
  students_deleted integer := 0;
begin
  if not public.yg_can_manage_students() then
    raise exception 'Akses ditolak: izin kelola siswa diperlukan.';
  end if;

  if p_nis_list is null then
    raise exception 'Daftar NIS wajib diisi.';
  end if;

  select count(distinct btrim(x))
    into requested_count
  from unnest(p_nis_list) as nis(value)
  where nullif(btrim(value), '') is not null;

  if requested_count < 1 or requested_count > 500 then
    raise exception 'Jumlah NIS harus antara 1 dan 500.';
  end if;

  select count(*)
    into found_count
  from public.app_docs d
  where d.collection = 'students'
    and d.id = any(p_nis_list);

  if found_count <> requested_count then
    raise exception 'Sebagian NIS tidak ditemukan; tidak ada data yang dihapus.';
  end if;

  delete from public.app_docs d
  where d.collection = 'attendance'
    and d.data->>'nis' = any(p_nis_list);
  get diagnostics attendance_deleted = row_count;

  delete from public.app_docs d
  where d.collection = 'grades'
    and d.data->>'nis' = any(p_nis_list);
  get diagnostics grades_deleted = row_count;

  delete from public.app_docs d
  where d.collection = 'students'
    and d.id = any(p_nis_list);
  get diagnostics students_deleted = row_count;

  return jsonb_build_object(
    'students_deleted', students_deleted,
    'attendance_deleted', attendance_deleted,
    'grades_deleted', grades_deleted
  );
end;
$$;

revoke all on function public.yg_delete_students_with_history(text[]) from public, anon;
grant execute on function public.yg_delete_students_with_history(text[]) to authenticated;

-- Replace the known backup policies. Unknown policies were rejected by the guard.
drop policy if exists "active users delete shared docs" on public.app_docs;
drop policy if exists "active users insert shared docs" on public.app_docs;
drop policy if exists "active users read app docs" on public.app_docs;
drop policy if exists "active users update shared docs" on public.app_docs;
drop policy if exists "authorized users insert master data" on public.app_docs;
drop policy if exists "authorized users update master data" on public.app_docs;

drop policy if exists stage2_read_master_data on public.app_docs;
drop policy if exists stage2_read_attendance on public.app_docs;
drop policy if exists stage2_read_grades on public.app_docs;
drop policy if exists stage2_read_presence on public.app_docs;
drop policy if exists stage2_read_audit on public.app_docs;
drop policy if exists stage2_insert_master_data on public.app_docs;
drop policy if exists stage2_insert_attendance on public.app_docs;
drop policy if exists stage2_insert_grades on public.app_docs;
drop policy if exists stage2_insert_presence on public.app_docs;
drop policy if exists stage2_insert_audit on public.app_docs;
drop policy if exists stage2_update_master_data on public.app_docs;
drop policy if exists stage2_update_attendance on public.app_docs;
drop policy if exists stage2_update_grades on public.app_docs;
drop policy if exists stage2_update_presence on public.app_docs;
drop policy if exists stage2_delete_students_classes on public.app_docs;
drop policy if exists stage2_delete_classes on public.app_docs;
drop policy if exists stage2_delete_batches_master on public.app_docs;
drop policy if exists stage2_delete_attendance on public.app_docs;
drop policy if exists stage2_delete_grades on public.app_docs;
drop policy if exists stage2_delete_presence on public.app_docs;

-- Read access: everyone active can read roster/master data needed for daily teaching;
-- historical/whole-class attendance and grade data require rekap/edit, except own grades.
create policy stage2_read_master_data
on public.app_docs for select to authenticated
using (
  public.yg_is_active()
  and collection in ('students', 'classes', 'batches')
);

create policy stage2_read_attendance
on public.app_docs for select to authenticated
using (
  public.yg_is_active()
  and collection = 'attendance'
  and (
    public.yg_is_admin()
    or public.yg_has_permission('rekap')
    or public.yg_has_permission('edit')
    or data->>'date' = to_char(timezone('Asia/Jakarta', now())::date, 'YYYY-MM-DD')
  )
);

create policy stage2_read_grades
on public.app_docs for select to authenticated
using (
  public.yg_is_active()
  and collection = 'grades'
  and (
    public.yg_is_admin()
    or public.yg_has_permission('rekap')
    or public.yg_has_permission('edit')
    or public.yg_owns_app_doc(data)
  )
);

create policy stage2_read_presence
on public.app_docs for select to authenticated
using (
  collection = 'presence'
  and (
    public.yg_is_admin()
    or exists (
      select 1 from public.app_users u
      where u.id = auth.uid()
        and u.active is true
        and u.email = app_docs.id
    )
  )
);

create policy stage2_read_audit
on public.app_docs for select to authenticated
using (collection = 'audit' and public.yg_is_admin());

-- Inserts: attribute activity to the authenticated profile, not a client-supplied name.
create policy stage2_insert_master_data
on public.app_docs for insert to authenticated
with check (
  public.yg_is_active()
  and collection in ('students', 'classes', 'batches')
  and public.yg_can_manage_students()
);

create policy stage2_insert_attendance
on public.app_docs for insert to authenticated
with check (
  public.yg_is_active()
  and collection = 'attendance'
  and data->>'byId' = auth.uid()::text
  and (
    data->>'date' = to_char(timezone('Asia/Jakarta', now())::date, 'YYYY-MM-DD')
    or public.yg_has_permission('edit')
  )
);

create policy stage2_insert_grades
on public.app_docs for insert to authenticated
with check (
  public.yg_is_active()
  and collection = 'grades'
  and data->>'byId' = auth.uid()::text
);

create policy stage2_insert_presence
on public.app_docs for insert to authenticated
with check (
  collection = 'presence'
  and data->>'byId' = auth.uid()::text
  and exists (
    select 1 from public.app_users u
    where u.id = auth.uid() and u.active is true and u.email = app_docs.id
  )
);

create policy stage2_insert_audit
on public.app_docs for insert to authenticated
with check (
  public.yg_is_active()
  and collection = 'audit'
  and data->>'byId' = auth.uid()::text
);

-- Updates: class/student/batch data require siswa permission; current-day attendance
-- is editable by active users, historical attendance requires edit permission.
create policy stage2_update_master_data
on public.app_docs for update to authenticated
using (
  public.yg_is_active()
  and collection in ('students', 'classes', 'batches')
  and public.yg_can_manage_students()
)
with check (
  public.yg_is_active()
  and collection in ('students', 'classes', 'batches')
  and public.yg_can_manage_students()
);

create policy stage2_update_attendance
on public.app_docs for update to authenticated
using (
  public.yg_is_active()
  and collection = 'attendance'
  and (
    public.yg_is_admin()
    or public.yg_has_permission('edit')
    or data->>'date' = to_char(timezone('Asia/Jakarta', now())::date, 'YYYY-MM-DD')
  )
)
with check (
  public.yg_is_active()
  and collection = 'attendance'
  and data->>'byId' = auth.uid()::text
  and (
    data->>'date' = to_char(timezone('Asia/Jakarta', now())::date, 'YYYY-MM-DD')
    or public.yg_has_permission('edit')
  )
);

create policy stage2_update_grades
on public.app_docs for update to authenticated
using (
  public.yg_is_active()
  and collection = 'grades'
  and (
    public.yg_is_admin()
    or public.yg_has_permission('edit')
    or public.yg_owns_app_doc(data)
  )
)
with check (
  public.yg_is_active()
  and collection = 'grades'
  and data->>'byId' = auth.uid()::text
);

create policy stage2_update_presence
on public.app_docs for update to authenticated
using (
  collection = 'presence'
  and exists (
    select 1 from public.app_users u
    where u.id = auth.uid() and u.active is true and u.email = app_docs.id
  )
)
with check (
  collection = 'presence'
  and data->>'byId' = auth.uid()::text
  and exists (
    select 1 from public.app_users u
    where u.id = auth.uid() and u.active is true and u.email = app_docs.id
  )
);

-- Deletes: students/classes require siswa permission; batch deletion stays Master-only.
-- Student deletion also removes its attendance and grade history from the UI.
create policy stage2_delete_classes
on public.app_docs for delete to authenticated
using (
  public.yg_is_active()
  and collection = 'classes'
  and public.yg_can_manage_students()
);
-- No direct DELETE policy for students: use yg_delete_students_with_history().

create policy stage2_delete_batches_master
on public.app_docs for delete to authenticated
using (collection = 'batches' and public.yg_is_admin());

create policy stage2_delete_attendance
on public.app_docs for delete to authenticated
using (
  public.yg_is_active()
  and collection = 'attendance'
  and (
    public.yg_is_admin()
    or public.yg_has_permission('edit')
    or data->>'date' = to_char(timezone('Asia/Jakarta', now())::date, 'YYYY-MM-DD')
  )
);

create policy stage2_delete_grades
on public.app_docs for delete to authenticated
using (
  public.yg_is_active()
  and collection = 'grades'
  and (
    public.yg_is_admin()
    or public.yg_has_permission('edit')
    or public.yg_owns_app_doc(data)
  )
);

create policy stage2_delete_presence
on public.app_docs for delete to authenticated
using (
  collection = 'presence'
  and exists (
    select 1 from public.app_users u
    where u.id = auth.uid() and u.active is true and u.email = app_docs.id
  )
);

commit;

-- READ-ONLY post-checks (run after commit on PREVIEW):
-- select collection, count(*) from public.app_docs group by collection order by collection;
-- select collection, count(*) filter (where data->>'byId' is null) as missing_by_id
-- from public.app_docs where collection in ('attendance','grades') group by collection;
-- select * from pg_policies where schemaname='public' and tablename='app_docs' order by policyname;
-- Confirm that a Sensei without edit cannot read/write past attendance or edit others' grades.
-- Confirm that a Sensei with edit can do both, and an ordinary user can still mark today's attendance.
