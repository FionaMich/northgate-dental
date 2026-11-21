-- Linking without a front-desk code: the sign-up email (already proved by the emailed code) must match
-- exactly one adult record, and the patient confirms that record's date of birth. Five misses lock it.
begin;
select plan(15);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  -- A fully signed-in session: password and emailed code (section 05).
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;

-- Elena's record (...001) uses elena.marsh.1@personas.northgate.synthetic and was born 1988-04-12.
insert into auth.users (id, email, aud, role, email_confirmed_at) values
  ('10000000-0000-4000-8000-000000000091', 'Elena.Marsh.1@personas.northgate.synthetic', 'authenticated', 'authenticated', now()),
  ('10000000-0000-4000-8000-000000000092', 'second.record@unconfirmed.synthetic', 'authenticated', 'authenticated', null),
  ('10000000-0000-4000-8000-000000000093', 'nobody@tests.synthetic', 'authenticated', 'authenticated', now());
-- A second adult record, for an unconfirmed sign-up and for the lock-out test.
update patients set email = 'second.record@unconfirmed.synthetic'
 where id = (select id from patients where id <> '30000000-0000-4000-8000-000000000001' and date_of_birth < current_date - interval '18 years' order by mrn limit 1);

select has_function('public', 'link_by_birth_date', array['date'], 'patients can link with their date of birth');

select pg_temp.act_as('10000000-0000-4000-8000-000000000093');
select is(link_by_birth_date('1988-04-12'), 'no_match', 'no record uses this email: no match');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000092');
select is(link_by_birth_date((select date_of_birth from patients where email = 'second.record@unconfirmed.synthetic')),
  'no_match', 'an email that was never confirmed links nothing');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000091');
select is(link_by_birth_date('1988-04-13'), 'no_match', 'the wrong date of birth does not link');
select is_empty($$ select 1 from patient_links where profile_id = '10000000-0000-4000-8000-000000000091' $$, 'nothing is linked after a miss');
select is(link_by_birth_date('1988-04-12'), 'linked', 'matching email (any case) and date of birth links the record');
select is((select patient_id from patient_links where profile_id = '10000000-0000-4000-8000-000000000091'),
  '30000000-0000-4000-8000-000000000001'::uuid, 'the account is linked to Elena''s record');
select is(link_by_birth_date('1988-04-12'), 'linked', 'asking again is harmless');
select is((select count(*)::int from patients), 1, 'Elena now sees her own record, and only hers');
reset role;

-- Five misses lock this route for the day, even if the sixth guess is right.
update auth.users set email_confirmed_at = now() where id = '10000000-0000-4000-8000-000000000092';
select pg_temp.act_as('10000000-0000-4000-8000-000000000092');
select is(link_by_birth_date(('1900-01-0' || n)::date), 'no_match', 'miss ' || n) from generate_series(1, 3) n;  -- the unconfirmed attempt above was miss 1
select is(link_by_birth_date('1900-01-05'), 'locked', 'the fifth miss locks it');
select is(link_by_birth_date((select date_of_birth from patients where email = 'second.record@unconfirmed.synthetic')),
  'locked', 'once locked, even the right date of birth is refused (the front desk can still link)');
reset role;

set local role anon;
select throws_ok($$ select link_by_birth_date('1988-04-12') $$, '42501', null, 'signed-out callers cannot use it');
reset role;

select * from finish();
rollback;
