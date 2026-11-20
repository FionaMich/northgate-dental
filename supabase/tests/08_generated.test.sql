-- Checks on the generated synthetic data (personas plus a sample), loaded before the tests run.
begin;
select plan(10);

create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  -- A fully signed-in session: password and emailed code (section 05).
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal, 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;

select set_eq(
  $$ select given_name from patients where id in ('30000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002',
       '30000000-0000-4000-8000-000000000003', '30000000-0000-4000-8000-000000000004', '30000000-0000-4000-8000-000000000005') $$,
  array['Elena', 'Marcus', 'Sofia', 'Ana', 'Omar'], 'the named personas are loaded with their fixed ids');
select is((select count(*)::int from patients where is_canary), 1, 'exactly one canary patient is loaded');
select isnt_empty($$ select 1 from patients where mrn >= 'NG0000100' $$, 'generated patients are loaded');
select is((select display_name from practitioners where profile_id = '10000000-0000-4000-8000-000000000011'),
  'Dr Mei Chen (synthetic orthodontist)', 'Dr Chen is the orthodontist');

select is_empty(
  $$ select 1 from dental_procedures d join services s on s.id = d.service_id join locations l on l.id = d.location_id
     where s.code = 'D6010' and l.code <> 'back-bay' $$,
  'implants appear only at Back Bay');
select is_empty(
  $$ select 1 from dental_procedures d join location_services ls using (location_id, service_id) where d.fee_cents <> ls.price_cents $$,
  'every fee equals the location''s price for that service');

-- The audit log saw every load, but holds no patient names, emails or birth dates.
select isnt_empty($$ select 1 from audit_log where table_name = 'patients' $$, 'loading patients was audited');
select is_empty(
  $$ select 1 from audit_log a join patients p on a.new_row::text like '%' || p.family_name || '%'
       or a.new_row::text like '%' || p.email || '%' or a.new_row::text like '%' || p.date_of_birth::text || '%'
     where a.table_name in ('patients', 'encounters', 'tooth_conditions', 'treatment_plans', 'plan_phases', 'dental_procedures') $$,
  'no audit entry for patient tables contains a patient''s name, email or birth date');

-- Row level security on generated data: the Cambridge receptionist sees Elena but not Marcus.
select pg_temp.act_as('10000000-0000-4000-8000-000000000003');
select isnt_empty($$ select 1 from public.patients where id = '30000000-0000-4000-8000-000000000001' $$, 'the Cambridge receptionist sees Elena');
select is_empty($$ select 1 from public.patients where id = '30000000-0000-4000-8000-000000000002' $$, 'the Cambridge receptionist does not see Marcus');
reset role;

select * from finish();
rollback;
