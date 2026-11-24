-- Queues and the transactional outbox (section 07 T1): events leave in the same transaction as the change, carry IDs
-- only, consumers ignore duplicates, reminders are claimed exactly once and respect quiet hours, and nobody but the
-- worker can read the queues or logs.
begin;
select plan(19);

create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
create function pg_temp.svc(c text) returns uuid language sql security definer as $$ select id from public.services where code = c $$;
create function pg_temp.dr(profile uuid) returns uuid language sql security definer as $$ select id from public.practitioners where profile_id = profile $$;

select ok(exists (select 1 from pgmq.list_queues() where queue_name = 'events'), 'the events queue exists');
select ok(exists (select 1 from pgmq.list_queues() where queue_name = 'notifications'), 'the notifications queue exists');
select ok(exists (select 1 from pgmq.list_queues() where queue_name = 'urgent'),
  'urgent clinical messages have their own queue, apart from bulk sends');

-- Quincy keeps New York time: 2027-03-10 15:00Z is 10:00 local.
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('47000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), '2027-03-10 15:00+00', '2027-03-10 16:00+00', 'booked');

select is((select count(*)::int from pgmq.q_events where message ->> 'appointment_id' = '47000000-0000-4000-8000-000000000001'), 1,
  'a booking puts one event on the queue, in the same transaction (the outbox)');
select is((select array_agg(k order by k) from pgmq.q_events, jsonb_object_keys(message) k
           where message ->> 'appointment_id' = '47000000-0000-4000-8000-000000000001'),
  array['appointment_id', 'from_status', 'to_status', 'version'],
  'the event carries IDs, version and status only: no name, contact details or clinical text');

insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('47000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000003', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), '2027-03-12 15:00+00', '2027-03-12 16:00+00', 'booked');
update appointments set status = 'cancelled' where id = '47000000-0000-4000-8000-000000000003';
select is((select max((message ->> 'version')::int) from pgmq.q_events
           where message ->> 'appointment_id' = '47000000-0000-4000-8000-000000000003'), 2,
  'each change sends the next version, so consumers can apply them in order');

select ok(private.mark_processed('test-consumer', 'events:1'), 'a consumer records a message the first time');
select ok(not private.mark_processed('test-consumer', 'events:1'), 'and the same message a second time has no effect');

-- 24 hours before 10:00 local is 10:00 local the day before.
select is((select count(*)::int from private.claim_due_reminders('2027-03-09 15:10+00')
           where appointment_id = '47000000-0000-4000-8000-000000000001' and kind = '24h'), 1, 'the 24 hour reminder is claimed when due');
select is((select count(*)::int from private.claim_due_reminders('2027-03-09 15:20+00')
           where appointment_id = '47000000-0000-4000-8000-000000000001'), 0, 'and never claimed twice');
select is((select count(*)::int from pgmq.q_notifications
           where message ->> 'appointment_id' = '47000000-0000-4000-8000-000000000001' and message ->> 'kind' = '24h'), 1,
  'a claimed reminder goes to the notifications queue once');
select is((select array_agg(k order by k) from pgmq.q_notifications, jsonb_object_keys(message) k
           where message ->> 'appointment_id' = '47000000-0000-4000-8000-000000000001'),
  array['appointment_id', 'kind', 'type'], 'the send request carries IDs only');

-- 08:30 local: the 6 hour reminder would fall at 02:30, inside quiet hours, so it goes the evening before at 20:00.
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('47000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), '2027-03-11 13:30+00', '2027-03-11 14:30+00', 'booked');
select is((select count(*)::int from private.claim_due_reminders('2027-03-11 06:40+00')
           where appointment_id = '47000000-0000-4000-8000-000000000002'), 0, 'nothing is sent during quiet hours (01:40 local)');
select is((select count(*)::int from private.claim_due_reminders('2027-03-11 01:10+00')
           where appointment_id = '47000000-0000-4000-8000-000000000002' and kind = '6h'), 1,
  'a reminder that falls in quiet hours goes the evening before (20:10 local)');

update appointments set status = 'cancelled' where id = '47000000-0000-4000-8000-000000000001';
select is((select count(*)::int from private.claim_due_reminders('2027-03-10 09:10+00')
           where appointment_id = '47000000-0000-4000-8000-000000000001'), 0, 'a cancelled visit gets no reminders');

select has_table('private', 'notification_log', 'sends are logged by template and provider ID');

set local role authenticated;
select throws_ok($$ select * from private.reminder_log $$, '42501', null, 'a signed-in user cannot read the reminder log');
select throws_ok($$ select * from pgmq.q_events $$, '42501', null, 'or the queues');
select throws_ok($$ select pgmq.send('notifications', '{}'::jsonb) $$, '42501', null, 'or put messages on them');
reset role;

select * from finish();
rollback;
