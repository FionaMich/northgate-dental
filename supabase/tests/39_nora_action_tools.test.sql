-- Nora's action tools (published by n8n's MCP Server Trigger): links only for your own visit, from a verified session;
-- one email a day; a reschedule link moves the visit once, in one step, outside the cancellation window, to a free time.
begin;
select plan(18);

create function pg_temp.act_as(uid uuid, verified boolean default true) returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  if verified then
    insert into private.verified_sessions (session_id, user_id) select uid, uid on conflict do nothing;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.queued(t text) returns bigint language sql security definer as $$
  select count(*) from pgmq.q_notifications where message ->> 'type' = t $$;

-- Elena (...014) is linked to record ...001; record ...002 belongs to someone else. Visit 3 is inside the window.
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001')
  on conflict do nothing;
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
select x.id::uuid, x.patient::uuid, l.id, pr.id, s.id, date_trunc('hour', now()) + x.at, date_trunc('hour', now()) + x.at + interval '1 hour', 'booked'
  from (values ('4d000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', interval '6 days'),
               ('4d000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', interval '7 days'),
               ('4d000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000001', interval '5 hours')) x (id, patient, at)
  join locations l on l.code = 'quincy'
  join practitioners pr on pr.profile_id = '10000000-0000-4000-8000-000000000013'
  join services s on s.code = 'D1110';

-- send_payment_link
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select ok(length(public.send_my_payment_link('4d000000-0000-4000-8000-000000000001')) = 32, 'a patient gets a pay link for their own visit');
select throws_ok($$ select public.send_my_payment_link('4d000000-0000-4000-8000-000000000002') $$, '42501', null,
  'but never for someone else''s visit');
reset role;
select is(pg_temp.queued('paylink'), 1::bigint, 'one payment email is queued');
select ok((select message ->> 'kind' ~ '^\d{4}-\d{2}-\d{2}$' from pgmq.q_notifications where message ->> 'type' = 'paylink'),
  'keyed by day, so the worker sends at most one a day per visit');
select is((select count(*) from pgmq.q_notifications q, jsonb_each_text(q.message) e where e.value ~ '^[A-Za-z0-9_-]{32}$'), 0::bigint,
  'no link token travels in a queue message');

-- send_reschedule_link
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select lives_ok($$ select public.send_my_reschedule_link('4d000000-0000-4000-8000-000000000001') $$, 'a patient asks for a reschedule link');
select throws_ok($$ select public.send_my_reschedule_link('4d000000-0000-4000-8000-000000000003') $$, '23514', null,
  'inside the cancellation window the link is refused (call the clinic)');
select throws_ok($$ select public.send_my_reschedule_link('4d000000-0000-4000-8000-000000000002') $$, '42501', null,
  'someone else''s visit is refused');
reset role;
select is(pg_temp.queued('movelink'), 1::bigint, 'one reschedule email is queued');

delete from private.verified_sessions where user_id = '10000000-0000-4000-8000-000000000014';
select pg_temp.act_as('10000000-0000-4000-8000-000000000014', false);
select throws_ok($$ select public.send_my_reschedule_link('4d000000-0000-4000-8000-000000000001') $$, '42501', null,
  'a session without the emailed sign-in code cannot ask for links');
reset role;

-- the page and the button run as n8n's database role, with nobody signed in (as on the server)
select set_config('request.jwt.claims', '', true);
grant northgate_patient_actions to postgres;   -- rolled back with the test
create temp table tok as select private.issue_action_token('4d000000-0000-4000-8000-000000000001', 'reschedule') as t,
                               private.issue_action_token('4d000000-0000-4000-8000-000000000003', 'reschedule') as late;
grant select on tok to northgate_patient_actions;
set local role northgate_patient_actions;   -- the work runs as n8n's role; the checks run after, as the test owner
create temp table page as select * from private.reschedule_options((select t from tok));
create temp table late as select * from private.reschedule_options((select late from tok));
create temp table pick as select (o ->> 'at')::timestamptz as at from page, jsonb_array_elements(page.options) o limit 1;
create temp table moves as
  select 1 as n, private.move_by_token((select t from tok), now() + interval '3 hours') as r
  union all select 2, private.move_by_token((select t from tok), (select at from pick))
  union all select 3, private.move_by_token((select t from tok), (select at from pick) + interval '1 day');
reset role;
select is((select state from page), 'ok', 'a fresh reschedule link is usable');
select ok(jsonb_array_length((select options from page)) between 1 and 8,
  'the page offers between 1 and 8 free times, with nobody signed in');
select is((select state from late), 'too_late', 'a visit inside the cancellation window cannot be moved by link');
select is((select r from moves where n = 1), 'taken', 'a time inside the cancellation window is refused');
select is((select r from moves where n = 2), 'moved', 'the button moves the visit');
select is((select r from moves where n = 3), 'used', 'a link works once');
select is((select status from appointments where id = '4d000000-0000-4000-8000-000000000001'), 'cancelled',
  'the old visit is cancelled');
select is((select count(*) from appointments where replaces = '4d000000-0000-4000-8000-000000000001' and status = 'booked'
                                                and starts_at = (select at from pick)), 1::bigint,
  'and the new one is booked at the chosen time, recording the visit it replaces');

select * from finish();
rollback;
