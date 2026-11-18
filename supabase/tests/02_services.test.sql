-- Specialties, services, prices per location (whole cents) and rooms or equipment.
begin;
delete from public.org_settings;
delete from public.organisation;
select plan(13);

select has_table('public', 'specialties', 'specialties exists');
select has_table('public', 'services', 'services exists');
select has_table('public', 'location_services', 'location_services exists');
select has_table('public', 'resources', 'resources exists');
select has_type('public', 'resource_kind', 'resource_kind type exists');

-- Synthetic test data, rolled back at the end.
insert into locations (id, code, name, time_zone) values
  ('00000000-0000-0000-0000-0000000000b1', 'test-back-bay', 'Back Bay', 'America/New_York');
insert into specialties (id, code, name) values
  ('00000000-0000-0000-0000-00000000005a', 'test-general', 'General dentistry');
insert into services (id, code, name, duration_minutes, specialty_id) values
  ('00000000-0000-0000-0000-0000000005e1', 'T1110', 'Adult cleaning', 60, '00000000-0000-0000-0000-00000000005a');

select throws_ok(
  $$ insert into services (code, name, duration_minutes) values ('T1110', 'Duplicate code', 30) $$,
  '23505', null, 'a service code is unique'
);
select throws_ok(
  $$ insert into services (code, name, duration_minutes) values ('T0000', 'No time', 0) $$,
  '23514', null, 'a service must take some time'
);

-- Money: whole cents in an integer, so $120.00 is 12000 and nothing is rounded.
insert into location_services (location_id, service_id, price_cents) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000005e1', 12000);
select is(
  (select price_cents from location_services where location_id = '00000000-0000-0000-0000-0000000000b1'),
  12000,
  'a price of $120.00 is stored as 12000 cents'
);

-- E10: a negative price is refused.
select throws_ok(
  $$ update location_services set price_cents = -1 where location_id = '00000000-0000-0000-0000-0000000000b1' $$,
  '23514', null, 'a negative price is refused'
);
select throws_ok(
  $$ insert into location_services (location_id, service_id, price_cents) values
     ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-0000000005e1', 9000) $$,
  '23505', null, 'one price per service per location'
);
select throws_ok(
  $$ delete from services where code = 'T1110' $$,
  '23503', null, 'a service that has prices cannot be deleted'
);

insert into resources (location_id, kind, name) values
  ('00000000-0000-0000-0000-0000000000b1', 'operatory', 'Operatory 1');
select throws_ok(
  $$ insert into resources (location_id, kind, name) values
     ('00000000-0000-0000-0000-0000000000b1', 'operatory', 'Operatory 1') $$,
  '23505', null, 'room names are unique within a location'
);
select throws_ok(
  $$ insert into resources (location_id, kind, name) values
     ('00000000-0000-0000-0000-0000000000b1', 'teleporter', 'Room X') $$,
  '22P02', null, 'an unknown kind of room or equipment is refused'
);

select * from finish();
rollback;
