-- The audit log: every change to every table is recorded, and nobody can alter the record.
begin;
select plan(11);

create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal)::text, true);
  set local role authenticated;
end;
$$;

select has_table('public', 'audit_log', 'audit_log exists');
select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r' and c.relname <> 'audit_log'
       and not exists (select 1 from pg_trigger t where t.tgrelid = c.oid and t.tgname = 'audit_row') $$,
  'every table except the audit log itself is audited'
);

-- E08: the seeded administrator changes a Back Bay price.
select pg_temp.act_as('10000000-0000-4000-8000-000000000001');
update public.location_services set price_cents = 13500
 where location_id = (select id from public.locations where code = 'back-bay')
   and service_id = (select id from public.services where code = 'D1110');
reset role;

select is(
  (select count(*)::int from audit_log where table_name = 'location_services' and action = 'UPDATE'),
  1, 'a price change writes exactly one audit row');
select is(
  (select (old_row ->> 'price_cents') || ' -> ' || (new_row ->> 'price_cents') from audit_log
    where table_name = 'location_services' and action = 'UPDATE'),
  '13000 -> 13500', 'the audit row keeps the old and the new price');
select is(
  (select actor_id::text || ' ' || actor_role::text from audit_log where table_name = 'location_services' and action = 'UPDATE'),
  '10000000-0000-4000-8000-000000000001 org_admin', 'the audit row records who made the change and in which role');

-- E09: nobody signed in can alter, remove or forge the record, not even the administrator.
select pg_temp.act_as('10000000-0000-4000-8000-000000000001');
select throws_ok($$ update public.audit_log set new_row = '{}' $$, '42501', null, 'the administrator cannot edit the audit log');
select throws_ok($$ delete from public.audit_log $$, '42501', null, 'the administrator cannot delete from the audit log');
select throws_ok($$ insert into public.audit_log (table_name, row_pk, action) values ('x', 'x', 'INSERT') $$,
  '42501', null, 'nobody can write an audit row by hand');
select isnt_empty($$ select 1 from public.audit_log $$, 'the administrator can read the audit log');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000003');
select is_empty($$ select 1 from public.audit_log $$, 'a receptionist cannot read the audit log');
reset role;

set local role service_role;
select throws_ok($$ delete from public.audit_log $$, '42501', null, 'server code cannot delete from the audit log either');
reset role;

select * from finish();
rollback;
