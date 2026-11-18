-- Slots and booking: slots come from each clinician's weekly template in the location's local time;
-- a patient holds a slot for 10 minutes, then confirms or lets it go.
begin;
select plan(23);

create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
create function pg_temp.svc(c text) returns uuid language sql security definer as $$ select id from public.services where code = c $$;
create function pg_temp.dr(profile uuid) returns uuid language sql security definer as $$ select id from public.practitioners where profile_id = profile $$;
-- A Monday two weeks ahead, and a local Cambridge time on it.
create function pg_temp.monday() returns date language sql as $$ select date_trunc('week', current_date + 14)::date $$;
create function pg_temp.at(t text) returns timestamptz language sql as $$ select (pg_temp.monday() + t::time) at time zone 'America/New_York' $$;
grant execute on function pg_temp.loc(text), pg_temp.svc(text), pg_temp.dr(uuid), pg_temp.monday(), pg_temp.at(text) to authenticated;

-- The seeded patient sign-in (...014) is Elena; the Cambridge paediatric dentist (...012) works Mondays 09:00 to 17:00.
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001');

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select is((select count(*)::int from available_slots(pg_temp.loc('cambridge'), pg_temp.svc('D1110'), pg_temp.monday(), 1)), 15,
  'an hour-long cleaning has 15 half-hourly starts in a 09:00 to 17:00 day');
select is((select min(starts_at) from available_slots(pg_temp.loc('cambridge'), pg_temp.svc('D1110'), pg_temp.monday(), 1)),
  pg_temp.at('09:00'), 'slots follow the location''s local time');
select is_empty($$ select 1 from available_slots(pg_temp.loc('cambridge'), pg_temp.svc('D1110'), current_date - 7, 7) where starts_at <= now() $$,
  'no slot is offered in the past');
select isnt_empty($$ select 1 from available_slots(pg_temp.loc('back-bay'), pg_temp.svc('D6010'), pg_temp.monday(), 7) where resource_id is not null $$,
  'an implant slot comes with the CBCT scanner');
select is_empty($$ select 1 from available_slots(pg_temp.loc('quincy'), pg_temp.svc('D9110'), pg_temp.monday(), 7) $$,
  'emergency appointments are not offered for self-booking');
reset role;

-- Taken time and leave remove slots.
insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
values ('30000000-0000-4000-8000-000000000004', pg_temp.loc('cambridge'), pg_temp.dr('10000000-0000-4000-8000-000000000012'),
        pg_temp.svc('D1110'), pg_temp.at('10:00'), pg_temp.at('11:00'), 'booked');
insert into availability_exceptions (practitioner_id, starts_at, ends_at, kind)
values (pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('14:00'), pg_temp.at('17:00'), 'training');
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select is((select count(*)::int from available_slots(pg_temp.loc('cambridge'), pg_temp.svc('D1110'), pg_temp.monday(), 1)), 6,
  'booked time and leave are not offered');

-- Hold, confirm, cancel.
create temp table ids (k text primary key, id uuid);
grant all on ids to authenticated;
insert into ids values ('a', hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('09:00')));
select results_eq($$ select status, patient_id, hold_expires_at between now() + interval '9 minutes' and now() + interval '10 minutes'
                      from appointments where id = (select id from ids where k = 'a') $$,
  $$ values ('held', '30000000-0000-4000-8000-000000000001'::uuid, true) $$,
  'a hold is for the signed-in patient and lasts 10 minutes');
select is((select count(*)::int from available_slots(pg_temp.loc('cambridge'), pg_temp.svc('D1110'), pg_temp.monday(), 1)), 5,
  'a held slot is not offered to others');
select throws_ok($$ select hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('10:30')) $$, '23P01', null, 'a taken slot cannot be held');
select throws_ok($$ select hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('09:10')) $$, '23P01', null, 'a time that is not a slot cannot be held');
select throws_ok($$ select hold_slot(pg_temp.loc('quincy'), pg_temp.svc('D9110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.at('09:00')) $$, '42501', null, 'emergency appointments cannot be self-booked');
select throws_ok($$ select hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('12:00'), '30000000-0000-4000-8000-000000000002') $$,
  '42501', null, 'a patient cannot book for someone they are not linked to');

-- A new hold replaces the patient's earlier one, so nobody can sit on many slots.
insert into ids values ('b', hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('12:00')));
select is((select status from appointments where id = (select id from ids where k = 'a')), 'cancelled',
  'a new hold releases the earlier one');
select lives_ok($$ select confirm_booking((select id from ids where k = 'b')) $$, 'the patient confirms their hold');
select results_eq($$ select status, hold_expires_at from appointments where id = (select id from ids where k = 'b') $$,
  $$ values ('booked', null::timestamptz) $$, 'a confirmed hold is booked');
select results_eq($$ select version, to_status from appointment_events where appointment_id = (select id from ids where k = 'b') order by version $$,
  $$ values (1, 'held'), (2, 'booked') $$, 'history records the hold and the booking with versions');
select lives_ok($$ select cancel_appointment((select id from ids where k = 'b')) $$, 'the patient cancels');
select is((select count(*)::int from available_slots(pg_temp.loc('cambridge'), pg_temp.svc('D1110'), pg_temp.monday(), 1)), 6,
  'a cancelled booking frees its slots');
reset role;

-- Expired holds cannot be confirmed and are released before the next hold.
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
insert into ids values ('c', hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('13:00')));
reset role;
update appointments set hold_expires_at = now() - interval '1 second' where id = (select id from ids where k = 'c');
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select throws_ok($$ select confirm_booking((select id from ids where k = 'c')) $$, '22023', null, 'an expired hold cannot be confirmed');
reset role;
select pg_temp.act_as('10000000-0000-4000-8000-000000000092', 'aal1');
select throws_ok($$ select hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('13:00')) $$, '42501', null, 'a sign-in with no profile cannot hold');
reset role;
select is(release_expired_holds(), 1, 'expired holds are released');
select is((select status from appointments where id = (select id from ids where k = 'c')), 'cancelled', 'a released hold is cancelled');

-- Staff use the front desk screens, not the patient booking functions.
select pg_temp.act_as('10000000-0000-4000-8000-000000000003');
select throws_ok($$ select hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('15:00'), '30000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'staff cannot use the patient hold');
reset role;

select * from finish();
rollback;
