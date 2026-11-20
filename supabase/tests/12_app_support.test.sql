-- What the patient app needs from the database: new sign-ups, teenage proxy limits, coverage cards.
begin;
select plan(20);

create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  -- A fully signed-in session: password and emailed code (section 05).
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal, 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;

-- E34: a new sign-up gets a patient profile, whatever it asks for.
insert into auth.users (id, email, aud, role, raw_user_meta_data) values
  ('10000000-0000-4000-8000-000000000081', 'new@tests.synthetic', 'authenticated', 'authenticated',
   '{"display_name": "New Synthetic Patient", "role": "org_admin"}');

select results_eq($$ select role::text, display_name from profiles where id = '10000000-0000-4000-8000-000000000081' $$,
  $$ values ('patient', 'New Synthetic Patient') $$, 'a new sign-up becomes a patient, never staff');

-- Ana (...082) is a parent of Sofia (15) and of a synthetic 8-year-old.
insert into auth.users (id, email, aud, role) values ('10000000-0000-4000-8000-000000000082', 'ana@tests.synthetic', 'authenticated', 'authenticated');
insert into profiles (id, role, display_name) values ('10000000-0000-4000-8000-000000000082', 'patient', 'Synthetic Ana')
on conflict (id) do update set role = excluded.role, display_name = excluded.display_name;
insert into patients (id, mrn, given_name, family_name, date_of_birth, sex_at_birth, home_location_id, email)
select '30000000-0000-4000-8000-000000000098', 'NG0000098', 'Lucas', 'Reyes', current_date - interval '8 years', 'male', id, 'lucas@tests.synthetic'
  from locations where code = 'cambridge';
insert into patient_proxies (proxy_profile_id, patient_id, ends_on) values
  ('10000000-0000-4000-8000-000000000082', '30000000-0000-4000-8000-000000000003', '2029-06-15'),
  ('10000000-0000-4000-8000-000000000082', '30000000-0000-4000-8000-000000000098', (current_date + interval '10 years')::date);
insert into encounters (patient_id, location_id, practitioner_id, occurred_at, kind)
select k.pid, l.id, p.id, now() - interval '30 days', 'exam'
  from (values ('30000000-0000-4000-8000-000000000098'::uuid), ('30000000-0000-4000-8000-000000000003')) k(pid), locations l, practitioners p where l.code = 'cambridge' and p.profile_id = '10000000-0000-4000-8000-000000000012';
insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
select '30000000-0000-4000-8000-000000000003', l.id, p.id, s.id, now() + interval '20 days', now() + interval '20 days 45 minutes', 'booked'
  from locations l, practitioners p, services s
 where l.code = 'cambridge' and p.profile_id = '10000000-0000-4000-8000-000000000012' and s.code = 'D1120';

select pg_temp.act_as('10000000-0000-4000-8000-000000000082');
select is((select count(*)::int from patients), 2, 'a parent sees both children''s names for the person switcher');
select isnt_empty($$ select 1 from appointments where patient_id = '30000000-0000-4000-8000-000000000003' $$,
  'a parent sees a teenager''s appointments');
select is_empty($$ select 1 from encounters where patient_id = '30000000-0000-4000-8000-000000000003' $$,
  'a parent does not see a teenager''s visits by default');
select is_empty($$ select 1 from treatment_plans where patient_id = '30000000-0000-4000-8000-000000000003' $$,
  'a parent does not see a teenager''s treatment plans by default');
select isnt_empty($$ select 1 from encounters where patient_id = '30000000-0000-4000-8000-000000000098' $$,
  'a parent sees a young child''s visits');
reset role;
update org_settings set settings = settings || '{"teen_proxy_full_access": true}';
select pg_temp.act_as('10000000-0000-4000-8000-000000000082');
select isnt_empty($$ select 1 from encounters where patient_id = '30000000-0000-4000-8000-000000000003' $$,
  'an organisation can give parents full access to teenagers');
reset role;
update org_settings set settings = settings - 'teen_proxy_full_access';

-- Coverage cards: rows and files only under the patient's own folder.
select has_table('public', 'coverages', 'coverages exists');
select is((select public from storage.buckets where id = 'coverage-cards'), false, 'the card bucket is private');
select pg_temp.act_as('10000000-0000-4000-8000-000000000082');
select lives_ok($$ insert into coverages (patient_id, payer_name, member_id, front_path)
  values ('30000000-0000-4000-8000-000000000003', 'Synthetic Dental PPO', 'SYN123456', '30000000-0000-4000-8000-000000000003/front.jpg') $$,
  'a parent adds a card for their child');
select is((select status from coverages where patient_id = '30000000-0000-4000-8000-000000000003'), 'pending_review',
  'a new card waits for review');
select throws_ok($$ insert into coverages (patient_id, payer_name, member_id)
  values ('30000000-0000-4000-8000-000000000001', 'Synthetic Dental PPO', 'SYN999') $$,
  '42501', null, 'nobody adds a card for a patient they are not linked to');
select throws_ok($$ insert into coverages (patient_id, payer_name, member_id, status)
  values ('30000000-0000-4000-8000-000000000003', 'Synthetic Dental PPO', 'SYN1', 'verified') $$,
  '42501', null, 'a patient cannot mark their own card verified');
select lives_ok($$ insert into storage.objects (bucket_id, name)
  values ('coverage-cards', '30000000-0000-4000-8000-000000000003/front.jpg') $$,
  'a parent uploads into their child''s folder');
select throws_ok($$ insert into storage.objects (bucket_id, name)
  values ('coverage-cards', '30000000-0000-4000-8000-000000000001/front.jpg') $$,
  '42501', null, 'an upload into another patient''s folder is refused (E37)');
select throws_ok($$ insert into storage.objects (bucket_id, name)
  values ('coverage-cards', 'not-a-patient/front.jpg') $$,
  '42501', null, 'an upload outside any patient folder is refused');
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');   -- the seeded patient, linked to nobody
select is_empty($$ select 1 from coverages $$, 'an unlinked patient sees no cards');
select is_empty($$ select 1 from storage.objects where bucket_id = 'coverage-cards' $$, 'an unlinked patient sees no card files');
reset role;
select pg_temp.act_as('10000000-0000-4000-8000-000000000003');   -- Cambridge front desk, for the coverage queue
select isnt_empty($$ select 1 from coverages $$, 'front desk sees cards for patients at their location');
select isnt_empty($$ select 1 from storage.objects where bucket_id = 'coverage-cards' $$, 'front desk can open those card files');
reset role;

select * from finish();
rollback;
