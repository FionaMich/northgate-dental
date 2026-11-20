-- Password plus emailed code at every patient sign-in: the database, not the app, enforces both factors.
begin;
select plan(16);

-- A session as Supabase Auth would issue it: amr says how it was created (password or otp).
create function pg_temp.act(uid uuid, session uuid, method text) returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) values (session, uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1',
    'session_id', session, 'amr', json_build_array(json_build_object('method', method, 'timestamp', 0)))::text, true);
  set local role authenticated;
end;
$$;

-- An established patient (signed up yesterday) linked to Elena's record, and a brand-new sign-up.
insert into auth.users (id, email, aud, role, created_at, email_confirmed_at) values
  ('10000000-0000-4000-8000-000000000095', 'established@tests.synthetic', 'authenticated', 'authenticated', now() - interval '1 day', now() - interval '1 day'),
  ('10000000-0000-4000-8000-000000000096', 'brand.new@tests.synthetic', 'authenticated', 'authenticated', now(), now());
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000095', '30000000-0000-4000-8000-000000000001');

-- Step 1: password only.
select pg_temp.act('10000000-0000-4000-8000-000000000095', 'a0000000-0000-4000-8000-000000000001', 'password');
select is((select count(*)::int from patients), 0, 'E43: a password-only session reads no patient data');
select is(session_is_verified(), false, 'the app is told a code is still needed');
select throws_ok($$ select finish_sign_in_code() $$, '42501', null, 'a password session cannot mark itself verified');
select lives_ok($$ select start_sign_in_code() $$, 'the password step is recorded');
reset role;

-- Step 2: the emailed code creates a new session.
select pg_temp.act('10000000-0000-4000-8000-000000000095', 'b0000000-0000-4000-8000-000000000001', 'otp');
select is((select count(*)::int from patients), 0, 'before finishing, the code session still reads nothing');
select lives_ok($$ select finish_sign_in_code() $$, 'password then code: the session is verified');
select is((select count(*)::int from patients), 1, 'the verified session reads the patient''s own record');
select is(session_is_verified(), true, 'the app moves on');
reset role;

-- E46: another code session cannot reuse the proof; a stolen inbox alone gets nothing.
select pg_temp.act('10000000-0000-4000-8000-000000000095', 'c0000000-0000-4000-8000-000000000001', 'otp');
select throws_ok($$ select finish_sign_in_code() $$, '42501', null, 'a code without a fresh password step is refused (proof used once)');
select is((select count(*)::int from patients), 0, 'that session reads no patient data');
reset role;

-- A password step older than 10 minutes does not count.
select pg_temp.act('10000000-0000-4000-8000-000000000095', 'a0000000-0000-4000-8000-000000000002', 'password');
select start_sign_in_code();
reset role;
update private.password_proofs set proved_at = now() - interval '11 minutes';
select pg_temp.act('10000000-0000-4000-8000-000000000095', 'b0000000-0000-4000-8000-000000000002', 'otp');
select throws_ok($$ select finish_sign_in_code() $$, '42501', null, 'a stale password step is refused');
reset role;

-- A brand-new account: the sign-up code (with the password just chosen) verifies the first session only.
select pg_temp.act('10000000-0000-4000-8000-000000000096', 'd0000000-0000-4000-8000-000000000001', 'otp');
select lives_ok($$ select finish_sign_in_code() $$, 'a new sign-up''s first session is verified by its sign-up code');
reset role;
select pg_temp.act('10000000-0000-4000-8000-000000000096', 'd0000000-0000-4000-8000-000000000002', 'otp');
select throws_ok($$ select finish_sign_in_code() $$, '42501', null, 'later sessions of that account need the password step');
reset role;

-- Signing out deletes the session, and its verification with it.
delete from auth.sessions where id = 'b0000000-0000-4000-8000-000000000001';
select is((select count(*)::int from private.verified_sessions where session_id = 'b0000000-0000-4000-8000-000000000001'), 0,
  'sign-out removes the verification');

-- Linking also needs a verified session.
select pg_temp.act('10000000-0000-4000-8000-000000000096', 'd0000000-0000-4000-8000-000000000003', 'password');
select throws_ok($$ select link_by_birth_date('1990-01-01') $$, '42501', null, 'linking needs the emailed code too');
reset role;

set local role anon;
select throws_ok($$ select start_sign_in_code() $$, '42501', null, 'signed-out callers cannot start');
reset role;

select * from finish();
rollback;
