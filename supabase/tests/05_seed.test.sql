-- The synthetic seed: three locations from the blueprint, services and prices, rooms, staff and one test user per role.
begin;
select plan(11);

select ok((select is_synthetic and name ilike '%synthetic%' from organisation), 'the organisation is marked and named synthetic');
select set_eq($$ select code from locations $$, array['back-bay', 'cambridge', 'quincy'], 'the three Northgate locations are seeded');
select is_empty(
  $$ select l.code from locations l where not exists (select 1 from location_hours h where h.location_id = l.id) $$,
  'every location has opening hours');
select is((select count(*)::int from resources r join locations l on l.id = r.location_id where l.code = 'back-bay' and r.kind = 'operatory'), 4, 'Back Bay has four operatories');
select is((select count(*)::int from resources r join locations l on l.id = r.location_id where l.code = 'cambridge' and r.kind = 'operatory'), 3, 'Cambridge has three operatories');
select is((select count(*)::int from resources r join locations l on l.id = r.location_id where l.code = 'quincy' and r.kind = 'operatory'), 2, 'Quincy has two operatories');
select is_empty(
  $$ select s.code, l.code from location_services ls join services s on s.id = ls.service_id join locations l on l.id = ls.location_id
     where s.requires_resource is not null
       and not exists (select 1 from resources r where r.location_id = ls.location_id and r.kind = s.requires_resource and r.active) $$,
  'a service needing equipment is only offered where that equipment exists');
select is_empty($$ select 1 from location_services where price_cents <= 0 $$, 'every seeded price is above zero');
select set_eq($$ select distinct role::text from profiles $$,
  array['patient', 'receptionist', 'clinician', 'location_manager', 'org_admin'], 'there is a test user for every role');
select is(
  (select count(distinct pr.location_id)::int from practitioner_roles pr join practitioners p on p.id = pr.practitioner_id
    where p.display_name ilike '%orthodontist%'),
  2, 'the orthodontist works at two locations');
select is_empty(
  $$ select p.display_name from profiles p where p.role <> 'patient' and p.role <> 'org_admin'
       and not exists (select 1 from staff_locations sl where sl.profile_id = p.id) $$,
  'every location-based staff member is assigned to a location');

select * from finish();
rollback;
