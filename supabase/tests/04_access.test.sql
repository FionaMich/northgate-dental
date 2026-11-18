-- Who can see and change what, role by role. Each role gets allowed and denied cases.
begin;
delete from public.org_settings;
delete from public.organisation;
select plan(34);

-- Synthetic people and places, rolled back at the end.
insert into locations (id, code, name, time_zone) values
  ('00000000-0000-0000-0000-0000000000b1', 'test-back-bay', 'Back Bay', 'America/New_York'),
  ('00000000-0000-0000-0000-0000000000c1', 'test-cambridge', 'Cambridge', 'America/New_York'),
  ('00000000-0000-0000-0000-0000000000e1', 'test-quincy', 'Quincy', 'America/New_York');
insert into organisation (name) values ('Northgate Dental (synthetic)');
insert into location_hours (location_id, weekday, opens, closes) values
  ('00000000-0000-0000-0000-0000000000b1', 1, '08:00', '18:00'),
  ('00000000-0000-0000-0000-0000000000c1', 1, '09:00', '17:00'),
  ('00000000-0000-0000-0000-0000000000e1', 1, '07:00', '20:00');
insert into specialties (id, code, name) values ('00000000-0000-0000-0000-00000000005a', 'test-general', 'General dentistry');
insert into services (id, code, name, duration_minutes, specialty_id) values
  ('00000000-0000-0000-0000-0000000005e1', 'T1110', 'Adult cleaning', 60, '00000000-0000-0000-0000-00000000005a');
insert into location_services (location_id, service_id, price_cents) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000005e1', 13000),
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000005e1', 12000),
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000005e1', 11000);

insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000a001', 'admin@tests.synthetic'),
  ('00000000-0000-0000-0000-00000000a002', 'cambridge.receptionist@tests.synthetic'),
  ('00000000-0000-0000-0000-00000000a003', 'orthodontist@tests.synthetic'),
  ('00000000-0000-0000-0000-00000000a004', 'quincy.manager@tests.synthetic'),
  ('00000000-0000-0000-0000-00000000a005', 'patient@tests.synthetic'),
  ('00000000-0000-0000-0000-00000000a006', 'cambridge.manager@tests.synthetic'),
  ('00000000-0000-0000-0000-00000000a007', 'former.clinician@tests.synthetic'),
  ('00000000-0000-0000-0000-00000000a008', 'new.receptionist@tests.synthetic');
insert into profiles (id, role, display_name) values
  ('00000000-0000-0000-0000-00000000a001', 'org_admin', 'Synthetic Admin'),
  ('00000000-0000-0000-0000-00000000a002', 'receptionist', 'Synthetic Receptionist'),
  ('00000000-0000-0000-0000-00000000a003', 'clinician', 'Synthetic Orthodontist'),
  ('00000000-0000-0000-0000-00000000a004', 'location_manager', 'Synthetic Manager'),
  ('00000000-0000-0000-0000-00000000a005', 'patient', 'Synthetic Patient'),
  ('00000000-0000-0000-0000-00000000a006', 'location_manager', 'Synthetic Cambridge Manager'),
  ('00000000-0000-0000-0000-00000000a008', 'receptionist', 'Synthetic New Receptionist')
on conflict (id) do update set role = excluded.role, display_name = excluded.display_name;
insert into profiles (id, role, display_name, active) values
  ('00000000-0000-0000-0000-00000000a007', 'clinician', 'Synthetic Former Clinician', false)
on conflict (id) do update set role = excluded.role, display_name = excluded.display_name, active = excluded.active;
insert into staff_locations (profile_id, location_id) values
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-0000000000b1'),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-0000000000e1'),
  ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-0000000000c1'),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-0000000000e1');
insert into practitioners (id, profile_id, display_name) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-00000000a003', 'Synthetic Orthodontist'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-00000000a007', 'Synthetic Former Clinician');
insert into staff_roster (practitioner_id, location_id, starts_at, ends_at) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000c1', '2026-12-01 13:00+00', '2026-12-01 17:00+00'),
  ('00000000-0000-0000-0000-0000000000d2', '00000000-0000-0000-0000-0000000000e1', '2026-12-01 13:00+00', '2026-12-01 17:00+00');
-- A retired service whose prices were left active.
insert into services (id, code, name, duration_minutes, active) values
  ('00000000-0000-0000-0000-0000000005e2', 'T9999', 'Retired service', 30, false);
insert into location_services (location_id, service_id, price_cents) values
  ('00000000-0000-0000-0000-0000000000e1', '00000000-0000-0000-0000-0000000005e2', 5000);

-- Act as a signed-in user. aal2 means the second factor has been verified.
create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal)::text, true);
  set local role authenticated;
end;
$$;

-- Structure: every table carries the staff 2FA rule, and signed-in users cannot truncate or alter tables.
select is_empty(
  $$ select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relkind = 'r'
       and not exists (select 1 from pg_policies p where p.schemaname = 'public' and p.tablename = c.relname
                        and p.policyname = 'staff_need_mfa' and p.permissive = 'RESTRICTIVE') $$,
  'every table in public has the restrictive staff_need_mfa policy'
);
select is_empty(
  $$ select table_name, privilege_type from information_schema.role_table_grants
     where grantee = 'authenticated' and table_schema = 'public'
       and privilege_type in ('TRUNCATE', 'REFERENCES', 'TRIGGER') $$,
  'signed-in users cannot truncate, reference or add triggers to any table'
);
select is_empty(
  $$ select a.privilege_type from pg_default_acl d join pg_namespace n on n.oid = d.defaclnamespace
     cross join lateral aclexplode(d.defaclacl) a
     where n.nspname = 'public' and d.defaclobjtype = 'r' and d.defaclrole = 'postgres'::regrole
       and a.grantee = 'authenticated'::regrole and a.privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE') $$,
  'tables created later start without write grants for signed-in users'
);

-- E18: signed out sees nothing.
set local role anon;
select throws_ok($$ select * from public.locations $$, '42501', null, 'signed-out users cannot read locations');
select throws_ok($$ select * from public.location_services $$, '42501', null, 'signed-out users cannot read prices');
reset role;

-- E04: the Cambridge receptionist sees Cambridge, not Quincy.
select pg_temp.act_as('00000000-0000-0000-0000-00000000a002');
select isnt_empty($$ select 1 from public.location_hours where location_id = '00000000-0000-0000-0000-0000000000c1' $$,
  'the Cambridge receptionist sees Cambridge hours');
select is_empty($$ select 1 from public.location_hours where location_id = '00000000-0000-0000-0000-0000000000e1' $$,
  'the Cambridge receptionist does not see Quincy hours');
select results_eq(
  $$ with u as (update public.location_services set price_cents = 1 where location_id = '00000000-0000-0000-0000-0000000000c1' returning 1) select count(*)::int from u $$,
  $$ values (0) $$,
  'a receptionist cannot change a price'
);

-- E13 under the real rules: own name yes, own role or active flag no.
select lives_ok($$ update public.profiles set display_name = 'Renamed Receptionist' where id = '00000000-0000-0000-0000-00000000a002' $$,
  'a user can change their own display name');
select throws_ok($$ update public.profiles set role = 'org_admin' where id = '00000000-0000-0000-0000-00000000a002' $$,
  '42501', null, 'a receptionist cannot promote themselves');
select throws_ok($$ update public.profiles set active = false where id = '00000000-0000-0000-0000-00000000a002' $$,
  '42501', null, 'a user cannot change their own active flag');
select throws_ok($$ update public.profiles set created_at = '2020-01-01' where id = '00000000-0000-0000-0000-00000000a002' $$,
  '42501', null, 'a user cannot rewrite when their account was created');
reset role;

-- E05: the same receptionist without the second factor sees nothing.
select pg_temp.act_as('00000000-0000-0000-0000-00000000a002', 'aal1');
select is_empty($$ select 1 from public.location_hours $$, 'staff without a verified second factor see no hours');
reset role;
select pg_temp.act_as('00000000-0000-0000-0000-00000000a001', 'aal1');
select results_eq(
  $$ with u as (update public.location_services set price_cents = 1 returning 1) select count(*)::int from u $$,
  $$ values (0) $$,
  'an administrator without a verified second factor cannot change a price'
);
reset role;
select pg_temp.act_as('00000000-0000-0000-0000-00000000a004', 'aal1');
select throws_ok($$ insert into public.location_closures (location_id, starts_at, ends_at, reason)
  values ('00000000-0000-0000-0000-0000000000e1', '2026-12-31 05:00+00', '2027-01-01 05:00+00', 'Holiday') $$,
  '42501', null, 'a manager without a verified second factor cannot write');
reset role;

-- Deactivated staff see nothing and change nothing, even through their own rows.
select pg_temp.act_as('00000000-0000-0000-0000-00000000a007', 'aal1');
select is_empty($$ select 1 from public.staff_roster $$, 'a deactivated clinician cannot read their old roster');
select results_eq(
  $$ with u as (update public.profiles set display_name = 'x' where id = '00000000-0000-0000-0000-00000000a007' returning 1) select count(*)::int from u $$,
  $$ values (0) $$,
  'a deactivated user cannot edit their own profile'
);
reset role;

-- E06: the orthodontist works at Cambridge and Back Bay.
select pg_temp.act_as('00000000-0000-0000-0000-00000000a003');
select is((select count(distinct location_id)::int from public.location_hours), 2,
  'the orthodontist sees hours for both of their locations');
select is_empty($$ select 1 from public.location_hours where location_id = '00000000-0000-0000-0000-0000000000e1' $$,
  'the orthodontist does not see Quincy');
reset role;

-- Location manager: writes at their own location only; prices are not theirs to change.
select pg_temp.act_as('00000000-0000-0000-0000-00000000a004');
select lives_ok($$ insert into public.location_closures (location_id, starts_at, ends_at, reason)
  values ('00000000-0000-0000-0000-0000000000e1', '2026-12-25 05:00+00', '2026-12-26 05:00+00', 'Holiday') $$,
  'the Quincy manager can close Quincy');
select throws_ok($$ insert into public.location_closures (location_id, starts_at, ends_at, reason)
  values ('00000000-0000-0000-0000-0000000000c1', '2026-12-25 05:00+00', '2026-12-26 05:00+00', 'Holiday') $$,
  '42501', null, 'the Quincy manager cannot close Cambridge');
select results_eq(
  $$ with u as (update public.location_services set price_cents = 1 where location_id = '00000000-0000-0000-0000-0000000000e1' returning 1) select count(*)::int from u $$,
  $$ values (0) $$,
  'a location manager cannot change a price'
);
select lives_ok($$ insert into public.staff_locations (profile_id, location_id)
  values ('00000000-0000-0000-0000-00000000a008', '00000000-0000-0000-0000-0000000000e1') $$,
  'the Quincy manager can assign a receptionist to Quincy');
select throws_ok($$ insert into public.staff_locations (profile_id, location_id)
  values ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-0000000000e1') $$,
  '42501', null, 'a manager cannot give another manager control of their location');
select throws_ok($$ insert into public.staff_locations (profile_id, location_id)
  values ('00000000-0000-0000-0000-00000000a008', '00000000-0000-0000-0000-0000000000c1') $$,
  '42501', null, 'the Quincy manager cannot assign staff to Cambridge');
select lives_ok($$ insert into public.staff_roster (practitioner_id, location_id, starts_at, ends_at)
  values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000e1', '2026-12-03 13:00+00', '2026-12-03 17:00+00') $$,
  'the Quincy manager can roster a clinician at Quincy');
select throws_ok($$ insert into public.staff_roster (practitioner_id, location_id, starts_at, ends_at)
  values ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000c1', '2026-12-04 13:00+00', '2026-12-04 17:00+00') $$,
  '42501', null, 'the Quincy manager cannot roster anyone at Cambridge');
reset role;

-- E14: a patient sees public information at active locations but no staff data, and needs no second factor.
select pg_temp.act_as('00000000-0000-0000-0000-00000000a005', 'aal1');
select is((select count(*)::int from public.location_services where service_id = '00000000-0000-0000-0000-0000000005e1'), 3, 'a patient sees prices at every active location');
select is_empty($$ select 1 from public.location_services where service_id = '00000000-0000-0000-0000-0000000005e2' $$,
  'a patient does not see prices for a retired service');
select is_empty($$ select 1 from public.staff_roster $$, 'a patient cannot see the staff roster');
select isnt_empty($$ select 1 from public.organisation $$, 'a patient can read the organisation name');
reset role;

-- Administrator: changes prices; cannot delete a location (E17).
select pg_temp.act_as('00000000-0000-0000-0000-00000000a001');
select results_eq(
  $$ with u as (update public.location_services set price_cents = 12500 where location_id = '00000000-0000-0000-0000-0000000000c1' returning 1) select count(*)::int from u $$,
  $$ values (1) $$,
  'the administrator can change a price'
);
select throws_ok(
  $$ delete from public.locations where code = 'test-quincy' $$,
  '42501', null, 'nobody can delete a location, not even the administrator'
);

-- E16: removing the receptionist from Cambridge removes access at once.
delete from public.staff_locations
 where profile_id = '00000000-0000-0000-0000-00000000a002' and location_id = '00000000-0000-0000-0000-0000000000c1';
reset role;
select pg_temp.act_as('00000000-0000-0000-0000-00000000a002');
select is_empty($$ select 1 from public.location_hours $$, 'a receptionist removed from Cambridge no longer sees it');
reset role;

select * from finish();
rollback;
