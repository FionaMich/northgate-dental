-- Patients and their dental records: synthetic-only rules, chart rules, and who can see whom.
begin;
select plan(27);

select has_table('public', 'patients', 'patients exists');
select has_table('public', 'encounters', 'encounters exists');
select has_table('public', 'tooth_conditions', 'tooth_conditions exists');
select has_table('public', 'treatment_plans', 'treatment_plans exists');
select has_table('public', 'plan_phases', 'plan_phases exists');
select has_table('public', 'dental_procedures', 'dental_procedures exists');

create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.loc(c text) returns uuid language sql as $$ select id from public.locations where code = c $$;

-- Fixture patients (synthetic, rolled back): one at Cambridge, two at Quincy; the orthodontist treated one of them at Back Bay.
insert into patients (id, mrn, given_name, family_name, date_of_birth, sex_at_birth, home_location_id, email, phone) values
  ('20000000-0000-4000-8000-000000000001', 'NG9000001', 'Test', 'Cambridge', '1990-01-01', 'female', pg_temp.loc('cambridge'), 'cambridge@test.synthetic', '+16175550101'),
  ('20000000-0000-4000-8000-000000000002', 'NG9000002', 'Test', 'TreatedQuincy', '1985-05-05', 'male', pg_temp.loc('quincy'), 'treated@test.synthetic', '+16175550102'),
  ('20000000-0000-4000-8000-000000000003', 'NG9000003', 'Test', 'UntreatedQuincy', '1970-07-07', 'male', pg_temp.loc('quincy'), 'untreated@test.synthetic', '+16175550103');
insert into encounters (patient_id, location_id, practitioner_id, occurred_at, kind) values
  ('20000000-0000-4000-8000-000000000002', pg_temp.loc('back-bay'),
   (select id from practitioners where profile_id = '10000000-0000-4000-8000-000000000011'), '2026-06-02 14:00+00', 'consultation');

-- E24 and E27: only synthetic patients with fictional contact details.
select throws_ok($$ insert into patients (mrn, given_name, family_name, date_of_birth, sex_at_birth, home_location_id, is_synthetic)
  values ('NG9000009', 'Real', 'Person', '1990-01-01', 'female', pg_temp.loc('quincy'), false) $$,
  '23514', null, 'a patient that is not synthetic is refused');
select throws_ok($$ insert into patients (mrn, given_name, family_name, date_of_birth, sex_at_birth, home_location_id, email)
  values ('NG9000009', 'Real', 'Email', '1990-01-01', 'female', pg_temp.loc('quincy'), 'someone@gmail.com') $$,
  '23514', null, 'a real-looking email address is refused');
select throws_ok($$ insert into patients (mrn, given_name, family_name, date_of_birth, sex_at_birth, home_location_id, phone)
  values ('NG9000009', 'Real', 'Phone', '1990-01-01', 'female', pg_temp.loc('quincy'), '+16179871234') $$,
  '23514', null, 'a phone number outside the fictional 555-01xx range is refused');

-- E23: Universal tooth numbers only.
select throws_ok($$ insert into tooth_conditions (patient_id, tooth, condition, recorded_at)
  values ('20000000-0000-4000-8000-000000000001', '33', 'caries', now()) $$, '23514', null, 'tooth 33 does not exist');
select throws_ok($$ insert into tooth_conditions (patient_id, tooth, condition, recorded_at)
  values ('20000000-0000-4000-8000-000000000001', 'Z', 'caries', now()) $$, '23514', null, 'primary teeth run from A to T');
select lives_ok($$ insert into tooth_conditions (patient_id, tooth, condition, recorded_at)
  values ('20000000-0000-4000-8000-000000000001', 'A', 'sealant', now()) $$, 'primary tooth A is accepted');

-- Procedures: a completed one needs a date, fees are whole non-negative cents, and only services offered at that location.
select throws_ok($$ insert into dental_procedures (patient_id, location_id, service_id, status, fee_cents)
  values ('20000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), (select id from services where code = 'D1110'), 'completed', 12000) $$,
  '23514', null, 'a completed procedure must say when it was done');
select throws_ok($$ insert into dental_procedures (patient_id, location_id, service_id, status, fee_cents)
  values ('20000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), (select id from services where code = 'D1110'), 'planned', -1) $$,
  '23514', null, 'a negative fee is refused');
select throws_ok($$ insert into dental_procedures (patient_id, location_id, service_id, status, fee_cents)
  values ('20000000-0000-4000-8000-000000000001', pg_temp.loc('cambridge'), (select id from services where code = 'D6010'), 'planned', 320000) $$,
  '23503', null, 'an implant cannot be planned at Cambridge, which does not offer it');

-- E29: the Cambridge receptionist sees Cambridge patients only.
select pg_temp.act_as('10000000-0000-4000-8000-000000000003');
select isnt_empty($$ select 1 from public.patients where id = '20000000-0000-4000-8000-000000000001' $$, 'the Cambridge receptionist sees a Cambridge patient');
select is_empty($$ select 1 from public.patients where id = '20000000-0000-4000-8000-000000000002' $$, 'the Cambridge receptionist does not see a Quincy patient');
select is_empty($$ select 1 from public.encounters where patient_id = '20000000-0000-4000-8000-000000000002' $$, 'nor that patient''s visits');
select throws_ok($$ insert into public.patients (mrn, given_name, family_name, date_of_birth, sex_at_birth, home_location_id)
  values ('NG9000010', 'New', 'Patient', '2000-01-01', 'female', (select '00000000-0000-0000-0000-000000000000'::uuid)) $$,
  '42501', null, 'the Cambridge receptionist cannot register a patient at another location');
select throws_ok($$ delete from public.patients where id = '20000000-0000-4000-8000-000000000001' $$, '42501', null, 'nobody deletes a patient record');
reset role;

-- Clinicians also see patients they have treated, wherever those patients belong.
select pg_temp.act_as('10000000-0000-4000-8000-000000000011');
select isnt_empty($$ select 1 from public.patients where id = '20000000-0000-4000-8000-000000000002' $$, 'the orthodontist sees a Quincy patient they treated');
select is_empty($$ select 1 from public.patients where id = '20000000-0000-4000-8000-000000000003' $$, 'the orthodontist does not see a Quincy patient they never treated');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000004');
select is((select count(*)::int from public.patients where id::text like '20000000-%'), 2, 'the Quincy receptionist sees both Quincy patients');
reset role;

-- E30, E05, E18: patients before linking, staff without 2FA, and signed-out users see nothing.
select pg_temp.act_as('10000000-0000-4000-8000-000000000014', 'aal1');
select is_empty($$ select 1 from public.patients $$, 'a patient cannot read records before their account is linked');
reset role;
select pg_temp.act_as('10000000-0000-4000-8000-000000000004', 'aal1');
select is_empty($$ select 1 from public.patients $$, 'staff without a verified second factor see no patients');
reset role;
set local role anon;
select throws_ok($$ select * from public.patients $$, '42501', null, 'signed-out users cannot read patients');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000001');
select is((select count(*)::int from public.patients where id::text like '20000000-%'), 3, 'the administrator sees every patient');
reset role;

select * from finish();
rollback;
