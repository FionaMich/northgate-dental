-- W22 (section 07 T4): leave, closures, travel and double bookings are found once each, open one staff task, close
-- themselves when fixed, and only staff at the right location can see them.
begin;
select plan(13);

create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
create function pg_temp.svc(c text) returns uuid language sql security definer as $$ select id from public.services where code = c $$;
create function pg_temp.dr(profile uuid) returns uuid language sql security definer as $$ select id from public.practitioners where profile_id = profile $$;
create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal, 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;

-- Two Quincy visits a week apart with the Quincy dentist (...013).
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('49000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), now() + interval '3 days', now() + interval '3 days 1 hour', 'booked'),
  ('49000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), now() + interval '10 days', now() + interval '10 days 1 hour', 'booked');

select is(private.scan_schedule_conflicts(), 0, 'a clean schedule has no conflicts');

-- The dentist books leave over the first visit: the trigger finds it straight away.
insert into availability_exceptions (practitioner_id, starts_at, ends_at, kind, reason)
values (pg_temp.dr('10000000-0000-4000-8000-000000000013'), now() + interval '2 days', now() + interval '4 days', 'leave', 'Annual leave');
select is((select conflict_type from schedule_conflicts where appointment_id = '49000000-0000-4000-8000-000000000001'),
  'clinician_unavailable', 'leave over a booked visit is found as soon as it is entered');
select is((select count(*)::int from staff_tasks where kind = 'schedule_conflict'
            and appointment_id = '49000000-0000-4000-8000-000000000001' and done_at is null), 1, 'and opens one task for the clinic');
select is((select priority from staff_tasks where appointment_id = '49000000-0000-4000-8000-000000000001'), 'high', 'a high-severity conflict is a high-priority task');

select is(private.scan_schedule_conflicts(), 0, 'scanning again raises nothing new');
select is((select count(*)::int from schedule_conflicts where appointment_id = '49000000-0000-4000-8000-000000000001'), 1,
  'the same conflict is recorded once');

-- The clinic closes on the day of the second visit.
insert into location_closures (location_id, starts_at, ends_at, reason)
values (pg_temp.loc('quincy'), now() + interval '9 days 20 hours', now() + interval '10 days 20 hours', 'Water damage');
select is((select detail from schedule_conflicts where appointment_id = '49000000-0000-4000-8000-000000000002'),
  'Location closed: Water damage', 'a closure over a booked visit is found, with the reason and no patient details');

-- The leave is cancelled: that conflict and its task close themselves.
delete from availability_exceptions where reason = 'Annual leave';
select ok((select resolved_at is not null from schedule_conflicts where appointment_id = '49000000-0000-4000-8000-000000000001'),
  'when the leave is cancelled the conflict is resolved');
select ok((select done_at is not null from staff_tasks where appointment_id = '49000000-0000-4000-8000-000000000001'),
  'and its task is closed');

-- The same patient booked again 15 minutes after their first visit ends.
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('49000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), now() + interval '3 days 75 minutes', now() + interval '3 days 105 minutes', 'booked');
select is(private.scan_schedule_conflicts(), 1, 'the next scan finds the patient booked twice within 30 minutes');

-- Who can see it: Quincy's receptionist, not Back Bay's, and no patient.
select set_config('test.quincy', pg_temp.loc('quincy')::text, true);
select pg_temp.act_as('10000000-0000-4000-8000-000000000004');
select ok((select count(*) from staff_tasks) >= 2, 'Quincy''s receptionist sees Quincy''s tasks');
reset role;
select pg_temp.act_as('10000000-0000-4000-8000-000000000002');
select is((select count(*)::int from staff_tasks where location_id = current_setting('test.quincy')::uuid), 0, 'Back Bay''s receptionist does not');
reset role;
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001')
  on conflict do nothing;
select pg_temp.act_as('10000000-0000-4000-8000-000000000014', 'aal1');
select is((select count(*)::int from schedule_conflicts), 0, 'and a patient sees no conflicts, even about their own visit');
reset role;

select * from finish();
rollback;
