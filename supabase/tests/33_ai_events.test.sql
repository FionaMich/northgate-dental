-- Every assistant turn is logged to ai_events (AGENTS.md section 9): the shape of the turn, never its words. The
-- patient comes from the session; a patient reads only their own events; nobody edits or inserts rows directly.
begin;
select plan(8);

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
select lives_ok($$ select public.log_ai_event('chat', 'nl', 'confirm', array['find_slots', 'book_visit'],
                                              'ollama:gemma4', 'a1b2c3d4e5f6', 21450, 1830, 42) $$,
  'a signed-in patient''s turn is logged');
select throws_ok($$ select public.log_ai_event('chat', 'en', 'answered', array['my name is Elena'], 'm', 'v', 1, 0, 0) $$,
  '23514', null, 'a tool name is a name, so no sentence can ride along as one');
select throws_ok($$ select public.log_ai_event('chat', 'en', 'chatted', array[]::text[], 'm', 'v', 1, 0, 0) $$,
  '23514', null, 'only known outcomes');
select throws_ok($$ insert into ai_events (patient_id, channel, language, outcome, model, prompt_version, latency_ms)
                    values ('30000000-0000-4000-8000-000000000001', 'chat', 'en', 'answered', 'm', 'v', 1) $$,
  '42501', null, 'no direct inserts: only through log_ai_event');
select is((select count(*)::int from ai_events), 1, 'the patient reads their own event');
select throws_ok($$ update ai_events set outcome = 'answered' $$, '42501', null, 'nobody rewrites the log');
reset role;

select is((select patient_id from ai_events where language = 'nl'), '30000000-0000-4000-8000-000000000001'::uuid,
  'the patient comes from the session, never from an argument');

delete from private.verified_sessions where user_id = '10000000-0000-4000-8000-000000000014';
select set_config('request.jwt.claims', json_build_object('sub', '10000000-0000-4000-8000-000000000014', 'role', 'authenticated',
  'aal', 'aal1', 'session_id', '10000000-0000-4000-8000-000000000014')::text, true);
set local role authenticated;
select throws_ok($$ select public.log_ai_event('chat', 'en', 'answered', array[]::text[], 'm', 'v', 1, 0, 0) $$,
  '42501', null, 'a session without the emailed code logs nothing');
reset role;

select * from finish();
rollback;
