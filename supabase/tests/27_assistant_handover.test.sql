-- The assistant's handover: a signed-in patient opens one task for their own clinic, urgent for emergencies; nobody
-- else's patient, and no other kind of task.
begin;
select plan(6);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001')
  on conflict do nothing;

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select set_config('test.h1', public.request_handover('billing', 'es', 'Patient asks why the balance is higher than expected.')::text, true);
select set_config('test.h2', public.request_handover('emergency', 'en', 'Patient reported swelling spreading to the eye.')::text, true);
select throws_ok($$ select public.request_handover('rubbish', 'en', 'x x x x x x') $$, '23514', null, 'only known categories');
reset role;

select is((select location_id from staff_tasks where reference_id = current_setting('test.h1')::uuid),
  (select home_location_id from patients where id = '30000000-0000-4000-8000-000000000001'),
  'the task goes to the patient''s own clinic');
select is((select priority from staff_tasks where reference_id = current_setting('test.h2')::uuid), 'urgent',
  'an emergency handover is urgent');
select is((select count(*)::int from pgmq.q_urgent where message ->> 'handover_id' = current_setting('test.h2')), 1,
  'and goes on the urgent queue with its ID only');
select is((select patient_id from assistant_handovers where id = current_setting('test.h1')::uuid),
  '30000000-0000-4000-8000-000000000001'::uuid, 'the patient comes from the session, never from an argument');

-- The same person without the emailed sign-in code: the session is not verified.
delete from private.verified_sessions where user_id = '10000000-0000-4000-8000-000000000014';
select set_config('request.jwt.claims', json_build_object('sub', '10000000-0000-4000-8000-000000000014', 'role', 'authenticated',
  'aal', 'aal1', 'session_id', '10000000-0000-4000-8000-000000000014')::text, true);
set local role authenticated;
select throws_ok($$ select public.request_handover('other', 'en', 'Hello there team') $$, '42501', null,
  'a session without the emailed code cannot open tasks');
reset role;

select * from finish();
rollback;
