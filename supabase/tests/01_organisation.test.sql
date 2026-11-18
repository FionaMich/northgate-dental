-- Organisation, locations, opening hours, closures and settings inheritance.
begin;
select plan(17);

select has_table('public', 'organisation', 'organisation exists');
select has_table('public', 'locations', 'locations exists');
select has_table('public', 'location_hours', 'location_hours exists');
select has_table('public', 'location_closures', 'location_closures exists');
select has_table('public', 'org_settings', 'org_settings exists');
select has_table('public', 'location_settings', 'location_settings exists');
select has_view('public', 'effective_location_settings', 'effective_location_settings exists');

-- Synthetic test data, rolled back at the end.
insert into organisation (name) values ('Northgate Dental (synthetic)');
select throws_ok(
  $$ insert into organisation (name) values ('A second organisation') $$,
  '23505', null, 'there is only ever one organisation row'
);

insert into locations (id, code, name, time_zone) values
  ('00000000-0000-0000-0000-0000000000b1', 'back-bay', 'Back Bay', 'America/New_York'),
  ('00000000-0000-0000-0000-0000000000a1', 'quincy', 'Quincy', 'America/New_York');

select throws_ok(
  $$ insert into locations (code, name, time_zone) values ('mars', 'Mars', 'Mars/Olympus_Mons') $$,
  '22023', null, 'an unknown time zone is refused'
);

-- E07: the override wins key by key; keys without an override come from the organisation.
insert into org_settings (settings) values ('{"cancellation_hours": 24, "language": "en"}');
insert into location_settings (location_id, overrides) values
  ('00000000-0000-0000-0000-0000000000a1', '{"language": "es"}');

select is(
  (select settings from effective_location_settings where location_id = '00000000-0000-0000-0000-0000000000b1'),
  '{"cancellation_hours": 24, "language": "en"}'::jsonb,
  'a location without overrides gets the organisation defaults'
);
select is(
  (select settings from effective_location_settings where location_id = '00000000-0000-0000-0000-0000000000a1'),
  '{"cancellation_hours": 24, "language": "es"}'::jsonb,
  'a location override replaces only its own keys'
);

-- E11: closing time must be after opening time.
select throws_ok(
  $$ insert into location_hours (location_id, weekday, opens, closes)
     values ('00000000-0000-0000-0000-0000000000b1', 1, '17:00', '09:00') $$,
  '23514', null, 'closing before opening is refused'
);

insert into location_hours (location_id, weekday, opens, closes)
  values ('00000000-0000-0000-0000-0000000000b1', 1, '08:00', '18:00');

select throws_ok(
  $$ insert into location_hours (location_id, weekday, opens, closes)
     values ('00000000-0000-0000-0000-0000000000b1', 1, '12:00', '20:00') $$,
  '23P01', null, 'overlapping hours for one location and weekday are refused'
);

-- E15: hours are local clock times; the time zone turns them into the right instant either side of the clock change.
select is(
  (select ('2026-03-02'::date + h.opens) at time zone l.time_zone
     from location_hours h join locations l on l.id = h.location_id
    where l.code = 'back-bay' and h.weekday = 1),
  '2026-03-02 13:00:00+00'::timestamptz,
  '08:00 at Back Bay is 13:00 UTC before daylight saving starts'
);
select is(
  (select ('2026-03-09'::date + h.opens) at time zone l.time_zone
     from location_hours h join locations l on l.id = h.location_id
    where l.code = 'back-bay' and h.weekday = 1),
  '2026-03-09 12:00:00+00'::timestamptz,
  '08:00 at Back Bay is 12:00 UTC after daylight saving starts'
);

select throws_ok(
  $$ insert into location_closures (location_id, starts_at, ends_at, reason)
     values ('00000000-0000-0000-0000-0000000000b1', '2026-12-25 17:00+00', '2026-12-25 09:00+00', 'Holiday') $$,
  '23514', null, 'a closure that ends before it starts is refused'
);

-- E17: a location with history cannot be deleted; it is deactivated instead.
select throws_ok(
  $$ delete from locations where code = 'back-bay' $$,
  '23503', null, 'a location with opening hours cannot be deleted'
);

select * from finish();
rollback;
