-- New patients register themselves in the app (no front-desk code). Verified sessions only, adults only,
-- one record per account, and never a second record for an email that already has one.
begin;
select plan(12);

create function pg_temp.act(uid uuid, verified boolean default true) returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) values (uid, uid) on conflict do nothing;
  if verified then
    insert into private.verified_sessions (session_id, user_id) values (uid, uid) on conflict do nothing;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;

insert into auth.users (id, email, aud, role, email_confirmed_at) values
  ('10000000-0000-4000-8000-000000000071', 'Someone@Gmail.com', 'authenticated', 'authenticated', now()),
  ('10000000-0000-4000-8000-000000000072', 'new.person@tests.synthetic', 'authenticated', 'authenticated', now()),
  ('10000000-0000-4000-8000-000000000073', 'elena.marsh.1@personas.northgate.synthetic', 'authenticated', 'authenticated', now()),
  ('10000000-0000-4000-8000-000000000074', 'not.yet@tests.synthetic', 'authenticated', 'authenticated', now());

select has_function('public', 'register_new_patient', array['text', 'text', 'date', 'text'], 'patients can register themselves');

select pg_temp.act('10000000-0000-4000-8000-000000000074', false);
select throws_ok($$ select register_new_patient('Not', 'Yet', '1990-01-01', 'female') $$, '42501', null,
  'a session without the emailed code cannot register');
reset role;

select pg_temp.act('10000000-0000-4000-8000-000000000071');
select throws_ok($$ select register_new_patient('Young', 'Person', (current_date - interval '15 years')::date, 'female') $$, '22023', null,
  'under-18s are registered by a parent at the practice');
select throws_ok($$ select register_new_patient('Jordan', 'Lee', '1990-05-01', 'other') $$, '22023', null, 'sex at birth must be a known value');
select throws_ok($$ select register_new_patient(' ', 'Lee', '1990-05-01', 'male') $$, '22023', null, 'a name is required');
select lives_ok($$ select register_new_patient(' Jordan ', 'Lee', '1990-05-01', 'male') $$, 'an adult registers');
select ok((select mrn ~ '^NG9[0-9]{6}$' from patients p join patient_links l on l.patient_id = p.id
            where l.profile_id = '10000000-0000-4000-8000-000000000071'), 'app records use their own number range');
select results_eq($$ select given_name, email, details_confirmed_at is null from patients $$,
  $$ values ('Jordan', null::text, true) $$, 'the patient sees the new record; a non-synthetic email is not copied; clinic and address come next');
select throws_ok($$ select register_new_patient('Jordan', 'Lee', '1990-05-01', 'male') $$, '22023', null, 'one record per account');
reset role;

select pg_temp.act('10000000-0000-4000-8000-000000000072');
select lives_ok($$ select register_new_patient('New', 'Person', '1985-02-02', 'unknown') $$, 'a synthetic test address registers too');
select is((select email from patients where given_name = 'New' and family_name = 'Person'), 'new.person@tests.synthetic',
  'a synthetic email is kept on the record');
reset role;

-- Someone whose email is already on a record must confirm their date of birth instead of creating a duplicate.
select pg_temp.act('10000000-0000-4000-8000-000000000073');
select throws_ok($$ select register_new_patient('Elena', 'Marsh', '1988-04-12', 'female') $$, '22023', null,
  'no duplicate record for an email that already has one');
reset role;

select * from finish();
rollback;
