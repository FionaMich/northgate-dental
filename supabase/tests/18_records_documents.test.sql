-- Richer records: patients see the names of dentists who treated them, and documents the practice shares.
begin;
select plan(13);

create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  -- A fully signed-in session: password and emailed code (section 05).
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal, 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;

-- Elena (...014) is linked to her record (...001), which has visits with a dentist.
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001');
insert into patient_documents (patient_id, encounter_id, kind, title, file_path, content_type)
select e.patient_id, e.id, 'xray', 'Bitewing X-ray', e.patient_id || '/bitewing.png', 'image/png'
  from encounters e where e.patient_id = '30000000-0000-4000-8000-000000000001' limit 1;
insert into patient_documents (patient_id, kind, title, file_path, content_type)
values ('30000000-0000-4000-8000-000000000002', 'letter', 'Someone else''s letter', '30000000-0000-4000-8000-000000000002/letter.pdf', 'application/pdf');

select has_table('public', 'patient_documents', 'patient documents exist');
select is((select public from storage.buckets where id = 'patient-documents'), false, 'the documents bucket is private');
select throws_ok($$ insert into patient_documents (patient_id, kind, title, file_path, content_type)
                   values ('30000000-0000-4000-8000-000000000001', 'xray', 'Wrong folder', 'elsewhere/x.png', 'image/png') $$,
  '23514', null, 'a document must live in its patient''s folder');
select throws_ok($$ insert into patient_documents (patient_id, kind, title, file_path, content_type)
                   values ('30000000-0000-4000-8000-000000000001', 'xray', 'Script', '30000000-0000-4000-8000-000000000001/x.html', 'text/html') $$,
  '23514', null, 'only images and PDFs');

select pg_temp.act_as('10000000-0000-4000-8000-000000000014', 'aal1');
select isnt_empty($$ select 1 from practitioners p join encounters e on e.practitioner_id = p.id $$,
  'a patient sees the name of the dentist who treated them');
select is((select count(*)::int from practitioners), (select count(distinct practitioner_id)::int from encounters),
  'and only those dentists');
select is((select count(*)::int from patient_documents), 1, 'a patient sees their own documents, not anyone else''s');
select throws_ok($$ insert into patient_documents (patient_id, kind, title, file_path, content_type)
                   values ('30000000-0000-4000-8000-000000000001', 'letter', 'Mine', '30000000-0000-4000-8000-000000000001/a.pdf', 'application/pdf') $$,
  '42501', null, 'patients cannot add practice documents');
select ok((select count(*) = 0 from storage.objects o where o.bucket_id = 'patient-documents'
            and private.card_patient(o.name) <> '30000000-0000-4000-8000-000000000001'),
  'storage shows no other patient''s files');
reset role;

-- Staff: the front desk at the patient's clinic sees and adds documents; a password-only patient sees nothing.
select pg_temp.act_as('10000000-0000-4000-8000-000000000001');   -- org_admin with 2FA
select lives_ok($$ insert into patient_documents (patient_id, kind, title, file_path, content_type)
                   values ('30000000-0000-4000-8000-000000000001', 'visit_summary', 'Visit summary', '30000000-0000-4000-8000-000000000001/s.pdf', 'application/pdf') $$,
  'staff share a document with the patient');
select is((select count(*)::int from patient_documents where patient_id = '30000000-0000-4000-8000-000000000001'), 2, 'staff see the patient''s documents');
reset role;

insert into auth.sessions (id, user_id) values ('e0000000-0000-4000-8000-000000000014', '10000000-0000-4000-8000-000000000014');
select set_config('request.jwt.claims', json_build_object('sub', '10000000-0000-4000-8000-000000000014', 'role', 'authenticated',
  'session_id', 'e0000000-0000-4000-8000-000000000014')::text, true);
set local role authenticated;
select is((select count(*)::int from patient_documents), 0, 'a session without the emailed code sees no documents');
select is((select count(*)::int from practitioners), 0, 'and no dentist names');
reset role;

select * from finish();
rollback;
