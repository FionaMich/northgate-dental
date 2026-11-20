-- Appointments: rules the database enforces, history, and who sees or books what.
begin;
select plan(34);

select has_table('public', 'appointments', 'appointments exists');
select has_table('public', 'appointment_events', 'appointment_events exists');
select has_table('public', 'availability_exceptions', 'availability_exceptions exists');
select has_table('public', 'location_travel', 'location_travel exists');

create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  -- A fully signed-in session: password and emailed code (section 05).
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal, 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
create function pg_temp.svc(c text) returns uuid language sql security definer as $$ select id from public.services where code = c $$;
create function pg_temp.dr(profile uuid) returns uuid language sql security definer as $$ select id from public.practitioners where profile_id = profile $$;
grant execute on function pg_temp.loc(text), pg_temp.svc(text), pg_temp.dr(uuid) to authenticated;

-- Dr Chen (profile ...011) at Cambridge; the Quincy dentist (profile ...013) at Quincy. Patients are personas.
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'),
   pg_temp.dr('10000000-0000-4000-8000-000000000011'), pg_temp.svc('D8090'), '2026-12-02 15:00+00', '2026-12-02 16:00+00', 'booked'),
  ('40000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), '2026-12-02 15:00+00', '2026-12-02 16:00+00', 'booked');

-- No double booking, enforced by the database.
select throws_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000005', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000011'),
          pg_temp.svc('D8090'), '2026-12-02 15:30+00', '2026-12-02 16:30+00', 'booked') $$,
  '23P01', null, 'a clinician cannot be booked twice at the same time');
select lives_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000005', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000011'),
          pg_temp.svc('D8090'), '2026-12-02 16:00+00', '2026-12-02 17:00+00', 'booked') $$,
  'back-to-back appointments are allowed');
update appointments set status = 'cancelled' where id = '40000000-0000-4000-8000-000000000002';
select lives_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000003', pg_temp.loc('quincy'), pg_temp.dr('10000000-0000-4000-8000-000000000013'),
          pg_temp.svc('D1110'), '2026-12-02 15:00+00', '2026-12-02 16:00+00', 'booked') $$,
  'a cancelled appointment frees its slot');
insert into appointments (patient_id, location_id, practitioner_id, service_id, resource_id, starts_at, ends_at, status)
values ('30000000-0000-4000-8000-000000000005', pg_temp.loc('back-bay'), pg_temp.dr('10000000-0000-4000-8000-000000000008'),
        pg_temp.svc('D6010'), (select id from resources where kind = 'cbct_scanner'), '2026-12-04 14:00+00', '2026-12-04 16:00+00', 'booked');
select throws_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, resource_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000001', pg_temp.loc('back-bay'), pg_temp.dr('10000000-0000-4000-8000-000000000009'),
          pg_temp.svc('D6010'), (select id from resources where kind = 'cbct_scanner'), '2026-12-04 15:00+00', '2026-12-04 17:00+00', 'booked') $$,
  '23P01', null, 'a room or machine cannot be booked twice at the same time');
select throws_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000012'),
          pg_temp.svc('D1110'), '2026-12-03 15:00+00', '2026-12-03 16:00+00', 'held') $$,
  '23514', null, 'a hold must say when it expires');
select throws_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000012'),
          pg_temp.svc('D6010'), '2026-12-03 15:00+00', '2026-12-03 17:00+00', 'booked') $$,
  '23514', null, 'a service the location does not offer cannot be booked there');
select throws_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000012'),
          pg_temp.svc('D1110'), '2026-12-03 16:00+00', '2026-12-03 15:00+00', 'booked') $$,
  '23514', null, 'an appointment cannot end before it starts');
select throws_ok($$ insert into location_travel (from_location, to_location, minutes) values (pg_temp.loc('quincy'), pg_temp.loc('quincy'), 10) $$,
  '23514', null, 'travel time is only between two different locations');

-- Rooms and clinicians must belong to the location; equipment must match the service (review fixes).
select throws_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, resource_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000012'),
          pg_temp.svc('D1110'), (select id from resources where kind = 'cbct_scanner'), '2026-12-09 15:00+00', '2026-12-09 16:00+00', 'booked') $$,
  '23514', null, 'a Cambridge appointment cannot hold Back Bay''s scanner');
select throws_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, resource_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000005', pg_temp.loc('back-bay'), pg_temp.dr('10000000-0000-4000-8000-000000000008'),
          pg_temp.svc('D6010'), (select r.id from resources r join locations l on l.id = r.location_id where l.code = 'back-bay' and r.kind = 'operatory' limit 1),
          '2026-12-10 14:00+00', '2026-12-10 16:00+00', 'booked') $$,
  '23514', null, 'an implant must use the CT scanner, not an ordinary room');
select throws_ok($$ insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000013'),
          pg_temp.svc('D1110'), '2026-12-09 15:00+00', '2026-12-09 16:00+00', 'booked') $$,
  '23514', null, 'a clinician cannot be booked at a location where they do not work');

-- History and audit.
select is((select count(*)::int from appointment_events where appointment_id = '40000000-0000-4000-8000-000000000002'), 2,
  'creating and cancelling an appointment are both kept in its history');
select is_empty($$ select 1 from audit_log where table_name = 'appointments' and new_row::text like '%30000000-0000-4000-8000%' $$,
  'audit entries for appointments do not copy patient identifiers');
select results_eq($$ select version from appointment_events where appointment_id = '40000000-0000-4000-8000-000000000002' order by version $$,
  $$ values (1), (2) $$, 'each change to an appointment carries the next version number');

-- Who sees what.
select pg_temp.act_as('10000000-0000-4000-8000-000000000003');
select isnt_empty($$ select 1 from public.appointments where id = '40000000-0000-4000-8000-000000000001' $$, 'the Cambridge receptionist sees Cambridge appointments');
select is_empty($$ select 1 from public.appointments where id = '40000000-0000-4000-8000-000000000002' $$, 'but not Quincy appointments');
select lives_ok($$ insert into public.appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000012'),
          pg_temp.svc('D1110'), '2026-12-07 15:00+00', '2026-12-07 16:00+00', 'booked') $$, 'the Cambridge receptionist can book at Cambridge');
select throws_ok($$ insert into public.appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000002', pg_temp.loc('quincy'), pg_temp.dr('10000000-0000-4000-8000-000000000013'),
          pg_temp.svc('D1110'), '2026-12-07 15:00+00', '2026-12-07 16:00+00', 'booked') $$,
  '42501', null, 'the Cambridge receptionist cannot book at Quincy');
select throws_ok($$ delete from public.appointments where id = '40000000-0000-4000-8000-000000000001' $$, '42501', null, 'nobody deletes an appointment; it is cancelled');
select is((select booked_by::text from public.appointments where starts_at = '2026-12-07 15:00+00' and location_id = pg_temp.loc('cambridge')),
  '10000000-0000-4000-8000-000000000003', 'a booking records who made it, taken from the session');
select throws_ok($$ insert into public.appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
  values ('30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000012'),
          pg_temp.svc('D1110'), '2026-12-08 15:00+00', '2026-12-08 16:00+00', 'held') $$,
  '23514', null, 'front desk cannot create holds directly; holds come only from the booking function');
select throws_ok($$ update public.appointments set patient_id = '30000000-0000-4000-8000-000000000003' where id = '40000000-0000-4000-8000-000000000001' $$,
  '42501', null, 'front desk cannot move an appointment to another patient');
update appointments set status = 'completed' where id = '40000000-0000-4000-8000-000000000001';
select throws_ok($$ update public.appointments set status = 'booked' where id = '40000000-0000-4000-8000-000000000001' $$,
  '23514', null, 'a completed appointment cannot go back to booked');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000011');
select isnt_empty($$ select 1 from public.appointments where id = '40000000-0000-4000-8000-000000000001' $$, 'Dr Chen sees her own appointments');
select lives_ok($$ insert into public.availability_exceptions (practitioner_id, starts_at, ends_at, kind, reason)
  values (pg_temp.dr('10000000-0000-4000-8000-000000000011'), '2026-12-21 05:00+00', '2026-12-22 05:00+00', 'leave', 'Synthetic leave') $$,
  'a clinician can record their own leave');
select throws_ok($$ insert into public.availability_exceptions (practitioner_id, starts_at, ends_at, kind, reason)
  values (pg_temp.dr('10000000-0000-4000-8000-000000000013'), '2026-12-21 05:00+00', '2026-12-22 05:00+00', 'leave', 'Not mine') $$,
  '42501', null, 'a clinician cannot record leave for someone else');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000004');
select is_empty($$ select 1 from public.availability_exceptions $$, 'a receptionist cannot read clinicians'' leave or its reasons');
reset role;
select is_empty($$ select 1 from audit_log where table_name = 'availability_exceptions' and new_row::text like '%Synthetic leave%' $$,
  'leave reasons are not copied into the audit log');

select pg_temp.act_as('10000000-0000-4000-8000-000000000013');
select is_empty($$ select 1 from public.appointments where id = '40000000-0000-4000-8000-000000000001' $$, 'the Quincy dentist does not see Dr Chen''s Cambridge appointments');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000014', 'aal1');
select is_empty($$ select 1 from public.appointments $$, 'a patient account that is not linked sees no appointments');
reset role;

select * from finish();
rollback;
