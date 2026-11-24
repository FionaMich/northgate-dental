-- Moving a visit is one step: the new visit is confirmed and the old one cancelled together, and the new visit records
-- which one it replaces (so the patient gets one "your visit has moved" email, not "booked" plus "cancelled").
begin;
select plan(8);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal2', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
create function pg_temp.svc(c text) returns uuid language sql security definer as $$ select id from public.services where code = c $$;
create function pg_temp.dr(profile uuid) returns uuid language sql security definer as $$ select id from public.practitioners where profile_id = profile $$;
create function pg_temp.at(t text) returns timestamptz language sql as $$
  select (date_trunc('week', current_date + 14)::date + t::time) at time zone 'America/New_York' $$;
grant execute on function pg_temp.loc(text), pg_temp.svc(text), pg_temp.dr(uuid), pg_temp.at(text) to authenticated;

insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001');
-- Elena's booked visit, and another patient's.
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('40000000-0000-4000-8000-0000000000a1', '30000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'),
   pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.svc('D1110'), pg_temp.at('15:00'), pg_temp.at('16:00'), 'booked'),
  ('40000000-0000-4000-8000-0000000000b1', '30000000-0000-4000-8000-000000000004', pg_temp.loc('cambridge'),
   pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.svc('D1110'), pg_temp.at('16:00'), pg_temp.at('17:00'), 'booked');

create temp table ids (k text primary key, id uuid);
grant all on ids to authenticated;
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
insert into ids values ('new', hold_slot(pg_temp.loc('cambridge'), pg_temp.svc('D1110'),
  pg_temp.dr('10000000-0000-4000-8000-000000000012'), pg_temp.at('09:00')));

select throws_ok($$ select reschedule_booking((select id from ids where k = 'new'), '40000000-0000-4000-8000-0000000000b1') $$,
  '22023', null, 'a patient cannot move into their slot by cancelling someone else''s visit');
select is((select status from appointments where id = (select id from ids where k = 'new')), 'held',
  'the refused step changes nothing: the new slot is still only held');

select lives_ok($$ select reschedule_booking((select id from ids where k = 'new'), '40000000-0000-4000-8000-0000000000a1') $$,
  'Elena moves her own visit');
reset role;
select results_eq($$ select status, replaces from appointments where id = (select id from ids where k = 'new') $$,
  $$ values ('booked', '40000000-0000-4000-8000-0000000000a1'::uuid) $$, 'the new visit is booked and names the visit it replaces');
select is((select status from appointments where id = '40000000-0000-4000-8000-0000000000a1'), 'cancelled', 'the old visit is cancelled');
select ok(not has_column_privilege('authenticated', 'public.appointments', 'replaces', 'update'),
  'patients cannot set "replaces" by hand, only through the reschedule step');
select results_eq($$ select moved_from, replaced_by from private.reschedule_of((select id from ids where k = 'new'))
                      union all select moved_from, replaced_by from private.reschedule_of('40000000-0000-4000-8000-0000000000a1') $$,
  $$ values (pg_temp.at('15:00'), null::uuid), (null::timestamptz, (select id from ids where k = 'new')) $$,
  'the worker learns the old time for the new visit, and that the old visit was moved, not simply cancelled');
select ok(has_function_privilege('northgate_worker', 'private.reschedule_of(uuid)', 'execute')
  and not has_table_privilege('northgate_worker', 'public.appointments', 'select'),
  'the worker reads only these two facts, not the appointments table');

select * from finish();
rollback;
