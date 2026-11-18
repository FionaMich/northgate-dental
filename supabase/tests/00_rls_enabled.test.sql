-- Rules that must hold for every table and function in public, now and for everything added later.
begin;
select plan(4);

select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity $$,
  'every table in public has row level security enabled'
);

select is_empty(
  $$ select table_name, privilege_type from information_schema.role_table_grants
     where grantee = 'anon' and table_schema = 'public' $$,
  'signed-out users (anon) have no privileges on any table in public'
);

select is_empty(
  $$ select 1 from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
     where n.nspname = 'public' and d.defaclobjtype = 'r'
       and d.defaclrole = 'postgres'::regrole  -- migrations create tables as postgres
       and exists (select 1 from aclexplode(d.defaclacl) a where a.grantee = 'anon'::regrole) $$,
  'tables created later in public are not granted to anon by default'
);

-- Every role is in PUBLIC, so the default must be taken from PUBLIC, not only from anon.
create function public.probe_default_privileges() returns int language sql as 'select 1';
select ok(
  not has_function_privilege('anon', 'public.probe_default_privileges()', 'execute'),
  'functions created later in public cannot be run by signed-out users (anon)'
);

select * from finish();
rollback;
