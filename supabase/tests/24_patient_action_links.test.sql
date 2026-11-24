-- Links in patient emails (section 07 T4 and T6): cancel within policy and only once; check-ins screened for red flags
-- with an urgent task; check-ins and statements scheduled once each; pay links follow the payment; only hashes stored.
begin;
select plan(26);

create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
create function pg_temp.svc(c text) returns uuid language sql security definer as $$ select id from public.services where code = c $$;
create function pg_temp.dr(profile uuid) returns uuid language sql security definer as $$ select id from public.practitioners where profile_id = profile $$;

-- A visit in 5 days (cancellable), one in 10 hours (inside the 24-hour window) and one completed yesterday morning.
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status) values
  ('4a000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), now() + interval '5 days', now() + interval '5 days 1 hour', 'booked'),
  ('4a000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), now() + interval '10 hours', now() + interval '11 hours', 'booked'),
  ('4a000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000003', pg_temp.loc('quincy'),
   pg_temp.dr('10000000-0000-4000-8000-000000000013'), pg_temp.svc('D1110'), '2027-01-10 14:00+00', '2027-01-10 15:00+00', 'completed');

create temp table tok (name text primary key, token text);
insert into tok values
  ('cancel', private.issue_action_token('4a000000-0000-4000-8000-000000000001', 'cancel')),
  ('late',   private.issue_action_token('4a000000-0000-4000-8000-000000000002', 'cancel')),
  ('fine',   private.issue_action_token('4a000000-0000-4000-8000-000000000003', 'checkin', '1d')),
  ('worry',  private.issue_action_token('4a000000-0000-4000-8000-000000000003', 'checkin', '3d'));
create function pg_temp.t(n text) returns text language sql as $$ select token from tok where name = n $$;

select ok(not exists (select 1 from private.action_tokens where token_hash = convert_to(pg_temp.t('cancel'), 'UTF8')),
  'the token itself is never stored, only its hash');
select is((select array_agg(a.attname::text order by a.attname) from pg_attribute a
            where a.attrelid = 'private.action_tokens'::regclass and a.attnum > 0 and not a.attisdropped
              and a.attname ~ 'token'), array['token_hash'], 'the table has no column for the token itself');

-- W03 cancel
select is((select state from private.describe_action(pg_temp.t('cancel'), 'cancel')), 'ok', 'a fresh cancel link is usable');
select is((select clinic_name from private.describe_action(pg_temp.t('cancel'), 'cancel')), 'Northgate Dental, Quincy',
  'the page shows the clinic, and no patient name');
select is((select status from appointments where id = '4a000000-0000-4000-8000-000000000001'), 'booked',
  'opening the link (describe) changes nothing');
select is(private.cancel_by_token(pg_temp.t('cancel')), 'cancelled', 'the button cancels the visit');
select is((select status from appointments where id = '4a000000-0000-4000-8000-000000000001'), 'cancelled', 'and it is cancelled');
select is((select count(*)::int from pgmq.q_events where message ->> 'appointment_id' = '4a000000-0000-4000-8000-000000000001'
            and message ->> 'to_status' = 'cancelled'), 1, 'which goes through the outbox like any cancellation');
select is(private.cancel_by_token(pg_temp.t('cancel')), 'used', 'a link works once');
select is(private.cancel_by_token(pg_temp.t('late')), 'too_late', 'inside the cancellation window the link refuses');
select is((select status from appointments where id = '4a000000-0000-4000-8000-000000000002'), 'booked', 'and the visit stays booked');
select is(private.cancel_by_token('made-up-token'), 'unknown', 'a made-up link does nothing');
select is(private.cancel_by_token(pg_temp.t('fine')), 'unknown', 'a check-in link cannot cancel a visit');

-- W11 red flags (rules, not a model)
select is(private.red_flags('All good, a little sore'), '{}'::text[], 'ordinary soreness raises no flag');
select is(private.red_flags('The bleeding won''t stop and it is hard to swallow'),
  array['breathing_or_swallowing', 'heavy_bleeding'], 'bleeding that will not stop and trouble swallowing are flagged');

-- W11 check-ins
select is((select state from private.record_checkin(pg_temp.t('fine'), 'fine', '')), 'recorded', 'a "fine" check-in is recorded');
select is((select count(*)::int from staff_tasks where appointment_id = '4a000000-0000-4000-8000-000000000003'), 0,
  'and opens no task');
select is((select red_flags from private.record_checkin(pg_temp.t('worry'), 'concern', 'My face swelling is spreading to my eye')),
  array['spreading_swelling'], 'a concern with spreading swelling is flagged');
select is((select priority from staff_tasks where appointment_id = '4a000000-0000-4000-8000-000000000003' and kind = 'checkin_follow_up'),
  'urgent', 'a red flag opens an urgent task for the clinic');
select is((select array_agg(k order by k) from pgmq.q_urgent, jsonb_object_keys(message) k
            where message ->> 'appointment_id' = '4a000000-0000-4000-8000-000000000003'),
  array['appointment_id', 'checkin_id', 'type'], 'and goes on the urgent queue with IDs only, never the note');
select is((select state from private.record_checkin(pg_temp.t('worry'), 'fine', '')), 'unusable', 'a check-in link works once');

-- Scheduling: check-ins at 10:00 clinic time on days 1 and 3 (Quincy is UTC-5 in January).
select is((select count(*)::int from private.claim_due_checkins('2027-01-11 15:30+00') where day = '1d'), 1, 'the day-1 check-in is claimed at 10:30 local');
select is((select count(*)::int from private.claim_due_checkins('2027-01-11 15:40+00')), 0, 'and only once');

-- W06 statements: an unpaid balance on the completed visit.
insert into payments (id, appointment_id, patient_id, amount_cents) values
  ('4b000000-0000-4000-8000-000000000001', '4a000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000003', 11000);
select is(private.claim_due_statements('2027-01-24 15:30+00'), 1, 'the day-14 statement reminder is queued');
select is(private.claim_due_statements('2027-02-14 15:30+00'), 1, 'and on day 35 the clinic gets a billing task instead');
select is((select count(*)::int from staff_tasks where kind = 'billing_follow_up' and reference_id = '4b000000-0000-4000-8000-000000000001'), 1,
  'one billing task for the balance');

select * from finish();
rollback;
