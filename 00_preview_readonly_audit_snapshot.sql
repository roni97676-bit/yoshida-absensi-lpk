-- READ-ONLY diagnostic for the dedicated Supabase PREVIEW project.
-- Run this in Supabase SQL Editor. It performs one SELECT only; it does not write data.
-- Confirm the selected project is PREVIEW before running. Do not run against Production.

with snapshot as (
  select jsonb_build_object(
    'captured_at_utc', (now() at time zone 'utc'),
    'database', current_database(),
    'server_version', current_setting('server_version'),
    'database_timezone', current_setting('TimeZone'),
    'tables', coalesce((
      select jsonb_agg(jsonb_build_object(
        'table_name', c.relname,
        'rls_enabled', c.relrowsecurity,
        'rls_forced', c.relforcerowsecurity
      ) order by c.relname)
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relkind = 'r'
        and c.relname in ('app_docs', 'app_users')
    ), '[]'::jsonb),
    'columns', coalesce((
      select jsonb_agg(jsonb_build_object(
        'table_name', table_name,
        'ordinal_position', ordinal_position,
        'column_name', column_name,
        'data_type', data_type,
        'is_nullable', is_nullable,
        'column_default', column_default
      ) order by table_name, ordinal_position)
      from information_schema.columns
      where table_schema = 'public'
        and table_name in ('app_docs', 'app_users')
    ), '[]'::jsonb),
    'constraints', coalesce((
      select jsonb_agg(jsonb_build_object(
        'table_name', c.relname,
        'constraint_name', con.conname,
        'constraint_type', con.contype,
        'definition', pg_get_constraintdef(con.oid, true)
      ) order by c.relname, con.conname)
      from pg_constraint con
      join pg_class c on c.oid = con.conrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('app_docs', 'app_users')
    ), '[]'::jsonb),
    'indexes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'table_name', t.relname,
        'index_name', i.relname,
        'index_definition', pg_get_indexdef(ix.indexrelid),
        'is_unique', ix.indisunique,
        'is_primary', ix.indisprimary
      ) order by t.relname, i.relname)
      from pg_index ix
      join pg_class t on t.oid = ix.indrelid
      join pg_class i on i.oid = ix.indexrelid
      join pg_namespace n on n.oid = t.relnamespace
      where n.nspname = 'public'
        and t.relname in ('app_docs', 'app_users')
    ), '[]'::jsonb),
    'policies', coalesce((
      select jsonb_agg(jsonb_build_object(
        'table_name', tablename,
        'policy_name', policyname,
        'permissive', permissive,
        'roles', roles,
        'command', cmd,
        'using', qual,
        'with_check', with_check
      ) order by tablename, policyname)
      from pg_policies
      where schemaname = 'public'
        and tablename in ('app_docs', 'app_users')
    ), '[]'::jsonb),
    'functions', coalesce((
      select jsonb_agg(jsonb_build_object(
        'signature', p.oid::regprocedure::text,
        'security_definer', p.prosecdef,
        'volatility', p.provolatile,
        'config', p.proconfig,
        'definition', pg_get_functiondef(p.oid),
        'anon_can_execute', has_function_privilege('anon', p.oid, 'EXECUTE'),
        'authenticated_can_execute', has_function_privilege('authenticated', p.oid, 'EXECUTE'),
        'service_role_can_execute', has_function_privilege('service_role', p.oid, 'EXECUTE')
      ) order by p.proname)
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('yg_is_active', 'yg_is_admin', 'yg_can_manage_students', 'yg_protect_master_flag', 'yg_has_permission', 'yg_owns_app_doc', 'yg_delete_students_with_history')
    ), '[]'::jsonb),
    'triggers', coalesce((
      select jsonb_agg(jsonb_build_object(
        'table_name', c.relname,
        'trigger_name', t.tgname,
        'definition', pg_get_triggerdef(t.oid, true)
      ) order by c.relname, t.tgname)
      from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('app_docs', 'app_users')
        and not t.tgisinternal
    ), '[]'::jsonb),
    'table_grants', coalesce((
      select jsonb_agg(jsonb_build_object(
        'table_name', table_name,
        'grantee', grantee,
        'privilege_type', privilege_type,
        'is_grantable', is_grantable
      ) order by table_name, grantee, privilege_type)
      from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name in ('app_docs', 'app_users')
        and grantee in ('anon', 'authenticated', 'service_role')
    ), '[]'::jsonb),
    'data_counts', jsonb_build_object(
      'app_docs_total', (select count(*) from public.app_docs),
      'app_docs_by_collection', coalesce((
        select jsonb_object_agg(collection, n)
        from (select collection, count(*) as n from public.app_docs group by collection) x
      ), '{}'::jsonb),
      'app_users_total', (select count(*) from public.app_users),
      'app_users_by_role', coalesce((
        select jsonb_object_agg(coalesce(role, '<NULL>'), n)
        from (select role, count(*) as n from public.app_users group by role) x
      ), '{}'::jsonb),
      'legacy_admin_count', (select count(*) from public.app_users where role = 'admin'),
      'master_count', (select count(*) from public.app_users u where coalesce((to_jsonb(u) ->> 'is_master')::boolean, false) is true),
      'attendance_missing_by_id', (select count(*) from public.app_docs where collection = 'attendance' and nullif(data->>'byId','') is null),
      'grades_missing_by_id', (select count(*) from public.app_docs where collection = 'grades' and nullif(data->>'byId','') is null),
      'audited_owner_row_matches', exists (
        select 1 from public.app_users
        where id = '860c2a25-63cb-4b86-af1b-f57e19a585ed'::uuid
          and lower(email) = 'roni97676@gmail.com'
          and active is true
          and role = 'admin'
      )
    )
  ) as report
)
select jsonb_pretty(report) as preview_audit_snapshot
from snapshot;
