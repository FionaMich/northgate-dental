-- People: sign-in profiles with roles, practitioners, where they work, and the roster.
begin;
select plan(14);

select has_type('public', 'app_role', 'app_role type exists');
select has_table('public', 'profiles', 'profiles exists');
select has_table('public', 'practitioners', 'practitioners exists');
select has_table('public', 'practitioner_roles', 'practitioner_roles exists');
select has_table('public', 'staff_locations', 'staff_locations exists');
select has_table('public', 'staff_roster', 'staff_roster exists');

-- Synthetic test data, rolled back at the end.
insert into locations (id, code, name, time_zone) values
  ('00000000-0000-0000-0000-0000000000b1', 'back-bay', 'Back Bay', 'America/New_York'),
  ('00000000-0000-0000-0000-0000000000c1', 'cambridge', 'Cambridge', 'America/New_York');
insert into specialties (id, code, name) values
  ('00000000-0000-0000-0000-00000000005b', 'ortho', 'Orthodontics');
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000a001', 'admin@synthetic.test'),
  ('00000000-0000-0000-0000-00000000a002', 'receptionist@synthetic.test'),
  ('00000000-0000-0000-0000-00000000a003', 'orthodontist@synthetic.test');
insert into profiles (id, role, display_name) values
  ('00000000-0000-0000-0000-00000000a001', 'org_admin', 'Synthetic Admin'),
  ('00000000-0000-0000-0000-00000000a002', 'receptionist', 'Synthetic Receptionist'),
  ('00000000-0000-0000-0000-00000000a003', 'clinician', 'Synthetic Orthodontist');
insert into practitioners (id, profile_id, display_name, npi) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-00000000a003', 'Synthetic Orthodontist', '1234567893');

select throws_ok(
  $$ insert into practitioners (display_name, npi) values ('Bad NPI', '12AB') $$,
  '23514', null, 'an NPI must be ten digits'
);

insert into practitioner_roles (practitioner_id, location_id, specialty_id) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000005b');
select throws_ok(
  $$ insert into practitioner_roles (practitioner_id, location_id, specialty_id) values
     ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-00000000005b') $$,
  '23505', null, 'one role per practitioner, location and specialty'
);

-- E12: one person cannot be rostered in two places at once; back-to-back shifts are fine.
insert into staff_roster (practitioner_id, location_id, starts_at, ends_at) values
  ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000c1', '2026-12-01 13:00+00', '2026-12-01 17:00+00');
select throws_ok(
  $$ insert into staff_roster (practitioner_id, location_id, starts_at, ends_at) values
     ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', '2026-12-01 16:00+00', '2026-12-01 20:00+00') $$,
  '23P01', null, 'an overlapping shift at another location is refused'
);
select lives_ok(
  $$ insert into staff_roster (practitioner_id, location_id, starts_at, ends_at) values
     ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', '2026-12-01 17:00+00', '2026-12-01 21:00+00') $$,
  'a shift starting exactly when the last one ends is allowed'
);
select throws_ok(
  $$ insert into staff_roster (practitioner_id, location_id, starts_at, ends_at) values
     ('00000000-0000-0000-0000-0000000000d1', '00000000-0000-0000-0000-0000000000b1', '2026-12-02 17:00+00', '2026-12-02 09:00+00') $$,
  '23514', null, 'a shift that ends before it starts is refused'
);

-- E13: only an organisation administrator can change a role. A temporary open policy (rolled back)
-- isolates the role guard from the other row level security rules. Sessions are aal2, because staff
-- without a verified second factor are blocked before the guard is reached (T5).
create policy test_select_any on public.profiles for select to authenticated using (true);
create policy test_update_any on public.profiles for update to authenticated using (true) with check (true);

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a002", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select throws_ok(
  $$ update public.profiles set role = 'org_admin' where id = '00000000-0000-0000-0000-00000000a002' $$,
  '42501', null, 'a receptionist cannot promote themselves'
);
reset role;

select set_config('request.jwt.claims', '{"sub": "00000000-0000-0000-0000-00000000a001", "role": "authenticated", "aal": "aal2"}', true);
set local role authenticated;
select lives_ok(
  $$ update public.profiles set role = 'location_manager' where id = '00000000-0000-0000-0000-00000000a002' $$,
  'an organisation administrator can change a role'
);
reset role;

select is(
  (select role from profiles where id = '00000000-0000-0000-0000-00000000a002'),
  'location_manager'::app_role,
  'the administrator''s change was saved'
);

select * from finish();
rollback;
