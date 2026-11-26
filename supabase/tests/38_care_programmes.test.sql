-- Continuous care, W24 to W28: consent first, fixed rules for every answer, quiet hours for nudges, check-up flags with
-- a booking offer that only a clinician can close, and summaries made of data points only.
begin;
select plan(17);

create function pg_temp.act_as(uid uuid, aal text default 'aal1') returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal, 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.boston(d date, t time) returns timestamptz language sql as $$ select (d + t) at time zone 'America/New_York' $$;
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001')
  on conflict do nothing;

-- the practice manager invites the patient to two programmes
select pg_temp.act_as('10000000-0000-4000-8000-000000000001', 'aal2');
insert into care_enrolments (id, patient_id, location_id, programme, starts_on, ends_on)
select '95000000-0000-4000-8000-000000000001', p.id, p.home_location_id, 'post_procedure', current_date - 5, current_date + 2
  from patients p where p.id = '30000000-0000-4000-8000-000000000001';
insert into care_enrolments (id, patient_id, location_id, programme, starts_on, ends_on, wear_target_hours)
select '95000000-0000-4000-8000-000000000002', p.id, p.home_location_id, 'aligners', current_date - 10, current_date + 60, 22
  from patients p where p.id = '30000000-0000-4000-8000-000000000001';
reset role;
insert into care_checkins (enrolment_id, patient_id, due_on)
  values ('95000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', current_date - 1);

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select throws_ok($$ select public.answer_care_checkin((select id from care_checkins limit 1), 2, 'better', '{}', null) $$,
  '42501', null, 'no check-in counts before the patient has joined (consent first)');
select lives_ok($$ select public.join_care_programme('95000000-0000-4000-8000-000000000001'),
                         public.join_care_programme('95000000-0000-4000-8000-000000000002') $$, 'the patient joins');
reset role;
select ok((select bool_and(consent_at is not null and status = 'active') from care_enrolments), 'joining records consent');

-- W24: at 10:30 in Boston today's check-in opens and one message goes on the queue; a second scan adds nothing
select is(private.claim_due_care(pg_temp.boston(current_date, '10:30')), 1, 'W24 opens today''s check-in');
select is(private.claim_due_care(pg_temp.boston(current_date, '10:40')), 0, 'once a day');

-- W25: pain at the threshold is a task; swelling spreading to the eye is the emergency path
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select is(public.answer_care_checkin((select id from care_checkins where due_on = current_date - 1), 8, 'same', '{}', null),
  'task', 'pain at the clinician''s threshold opens a care task');
select is(public.answer_care_checkin((select id from care_checkins where due_on = current_date), 5, 'worse', '{swelling}',
  'the swelling is spreading towards my eye'), 'emergency', 'a red flag takes the emergency path');
reset role;
select is((select count(*)::int from pgmq.q_urgent where message ->> 'type' = 'care_alert'), 1, 'and reaches the urgent queue with IDs only');
select ok((select bool_and(message::text not like '%eye%') from pgmq.q_urgent), 'never the patient''s words');

-- W28: the emergency raised a check-up flag, a care task and one booking offer
select is((select reason from care_flags where resolved_at is null), 'serious_side_effect', 'W28 flags the serious side effect');
select is((select count(*)::int from pgmq.q_notifications where message ->> 'kind' = 'offer'), 1, 'with one booking offer to the patient');

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select throws_ok($$ select public.resolve_care_flag((select id from care_flags limit 1), 'Seen the patient') $$,
  '42501', null, 'a patient cannot close a flag');
reset role;
select pg_temp.act_as('10000000-0000-4000-8000-000000000001', 'aal2');
select lives_ok($$ select public.resolve_care_flag((select id from care_flags limit 1), 'Called the patient; seen the same day, healing well') $$,
  'a clinician or manager records the outcome');
reset role;

-- W27: no nudge at night; aligner wear short for a week raises a flag and a nudge in the day
insert into aligner_wear (enrolment_id, patient_id, day, hours)
select '95000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', current_date - i, 15 from generate_series(1, 6) i;
select is(private.claim_due_nudges(pg_temp.boston(current_date, '23:00')), 0, 'quiet hours: nothing after 20:00');
select ok(private.claim_due_nudges(pg_temp.boston(current_date, '18:30')) >= 1, 'a nudge in the day');
select is((select reason from care_flags where resolved_at is null), 'missed_wear', 'a week of short wear is a check-up flag');

-- W26: the weekly summary is numbers from rows, nothing else
select private.write_care_summaries(date_trunc('week', current_date)::date);
select ok((select bool_and(summary ~ '^(Answered|Wear reported)') from care_summaries), 'summaries are built from the data points');

select * from finish();
rollback;
