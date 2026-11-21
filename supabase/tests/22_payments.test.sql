-- Visit payments (section 07 T5): the amount comes from the price list, a payment link is never opened twice, only a
-- correctly signed and recent Stripe event marks a payment paid, a repeated event has no effect, a wrong amount is
-- refused, the receipt goes on the queue with IDs only, and nobody signed in can write a payment.
begin;
select plan(17);

create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
create function pg_temp.svc(c text) returns uuid language sql security definer as $$ select id from public.services where code = c $$;
create function pg_temp.dr(profile uuid) returns uuid language sql security definer as $$ select id from public.practitioners where profile_id = profile $$;

delete from vault.secrets where name = 'stripe_webhook_secret';  -- rolled back with the test
select vault.create_secret('whsec_pgtap_only', 'stripe_webhook_secret');
create function pg_temp.sign(body text, secret text default 'whsec_pgtap_only', at bigint default extract(epoch from now())::bigint)
returns text language sql as $$
  select 't=' || at || ',v1=' || encode(extensions.hmac(at || '.' || body, secret, 'sha256'), 'hex')
$$;
create function pg_temp.completed(event_id text, session_id text, amount int) returns text language sql as $$
  select jsonb_build_object('id', event_id, 'type', 'checkout.session.completed', 'data', jsonb_build_object('object',
    jsonb_build_object('id', session_id, 'payment_status', 'paid', 'amount_total', amount, 'currency', 'usd',
                       'payment_intent', 'pi_' || event_id)))::text
$$;

insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('48000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), '2027-04-10 15:00+00', '2027-04-10 16:00+00', 'booked');

select is((select amount_cents from private.open_payment('48000000-0000-4000-8000-000000000001')),
  (select price_cents from location_services where location_id = pg_temp.loc('quincy') and service_id = pg_temp.svc('D1110')),
  'the amount is the location''s price for the service, not a number from the caller');
select is((select payment_id from private.open_payment('48000000-0000-4000-8000-000000000001')),
  (select id from payments where appointment_id = '48000000-0000-4000-8000-000000000001'),
  'asking for a payment link twice reuses the same payment');

select private.attach_checkout((select id from payments where appointment_id = '48000000-0000-4000-8000-000000000001'), 'cs_test_one');
select is((select stripe_checkout_session_id from payments where appointment_id = '48000000-0000-4000-8000-000000000001'),
  'cs_test_one', 'the Checkout Session is remembered');

select throws_ok($$ select private.record_stripe_event(pg_temp.completed('evt_1', 'cs_test_one', 1), pg_temp.sign('tampered')) $$,
  '42501', 'stripe signature check failed', 'a body that does not match its signature is refused');
select throws_ok($$ select private.record_stripe_event(pg_temp.completed('evt_1', 'cs_test_one', 1),
                    pg_temp.sign(pg_temp.completed('evt_1', 'cs_test_one', 1), 'whsec_someone_else')) $$,
  '42501', 'stripe signature check failed', 'a body signed with another secret is refused');
select throws_ok($$ select private.record_stripe_event(pg_temp.completed('evt_1', 'cs_test_one', 1),
                    pg_temp.sign(pg_temp.completed('evt_1', 'cs_test_one', 1), at => extract(epoch from now())::bigint - 600)) $$,
  '42501', 'stripe signature check failed', 'a correctly signed event older than five minutes is refused (replay)');
select throws_ok($$ select private.record_stripe_event(pg_temp.completed('evt_1', 'cs_test_one', 1),
                    pg_temp.sign(pg_temp.completed('evt_1', 'cs_test_one', 1))) $$,
  '23514', 'stripe collected a different amount than was asked for', 'a payment for the wrong amount is refused');
select is((select status from payments where appointment_id = '48000000-0000-4000-8000-000000000001'), 'pending',
  'and none of the refused events changed the payment');

create temp table amt on commit drop as
  select amount_cents a from payments where appointment_id = '48000000-0000-4000-8000-000000000001';
select is(private.record_stripe_event(pg_temp.completed('evt_2', 'cs_test_one', (select a from amt)),
                                      pg_temp.sign(pg_temp.completed('evt_2', 'cs_test_one', (select a from amt)))),
  'recorded', 'a correctly signed payment event is recorded');
select is((select status from payments where appointment_id = '48000000-0000-4000-8000-000000000001'), 'paid', 'and the payment is paid');
select is(private.record_stripe_event(pg_temp.completed('evt_2', 'cs_test_one', (select a from amt)),
                                      pg_temp.sign(pg_temp.completed('evt_2', 'cs_test_one', (select a from amt)))),
  'duplicate', 'the same event delivered again has no effect');
select is((select count(*)::int from pgmq.q_notifications where message ->> 'type' = 'receipt'
            and message ->> 'appointment_id' = '48000000-0000-4000-8000-000000000001'), 1, 'one receipt is queued');
select is((select array_agg(k order by k) from pgmq.q_notifications, jsonb_object_keys(message) k
            where message ->> 'type' = 'receipt' and message ->> 'appointment_id' = '48000000-0000-4000-8000-000000000001'),
  array['appointment_id', 'payment_id', 'type'], 'the receipt request carries IDs only');
select throws_ok($$ select private.open_payment('48000000-0000-4000-8000-000000000001') $$,
  '23505', 'this visit is already paid', 'a paid visit cannot get another payment link');

set local role authenticated;
select throws_ok($$ insert into payments (appointment_id, patient_id, amount_cents)
                    values ('48000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 1) $$,
  '42501', null, 'a signed-in user cannot write a payment');
select throws_ok($$ select private.record_stripe_event('{}', '') $$, '42501', null, 'or call the webhook function');
reset role;
select ok(has_function_privilege('northgate_payments', 'private.record_stripe_event(text, text, integer)', 'execute')
          and not has_function_privilege('northgate_payments', 'private.notification_context(uuid)', 'execute'),
  'the payments role may record Stripe events and read nothing about the patient');

select * from finish();
rollback;
