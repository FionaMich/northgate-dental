-- What the notification worker may read about a visit (section 07 T2): only the worker role may call it, and it returns
-- the minimum a message needs.
begin;
select plan(5);

select function_returns('private', 'notification_context', array['uuid'], 'setof record', 'the worker reads a visit through one narrow function');
select is((select array_agg(a order by a) from unnest(array(
  select unnest(proargnames[2:]) from pg_proc where proname = 'notification_context')) a),
  array['clinic_name', 'clinic_phone', 'email', 'first_name', 'language', 'patient_id', 'service_name', 'starts_at', 'status', 'time_zone'],
  'it returns first name, sign-in email, language, time, clinic, service and status: no surname, birth date, record number or address');
select ok(has_function_privilege('northgate_worker', 'private.notification_context(uuid)', 'execute'), 'the worker role may call it');
select ok(not has_function_privilege('authenticated', 'private.notification_context(uuid)', 'execute'), 'signed-in users may not');
select ok(exists (select 1 from pgmq.list_queues() where queue_name = 'dead_letter'), 'messages that keep failing have a dead-letter queue');

select * from finish();
rollback;
