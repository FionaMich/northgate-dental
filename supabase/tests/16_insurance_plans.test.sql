-- Insurance plans patients pick from (reference data, fictional commercial names, real public programmes).
begin;
select plan(7);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  -- A fully signed-in session: password and emailed code (section 05).
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;

insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001');

select has_table('public', 'insurance_plans', 'insurance plans exist');
select ok((select count(*) >= 8 from insurance_plans where active), 'a list of plans is ready to pick from');
select ok((select bool_and(kind in ('medicaid', 'medicare')) from insurance_plans where name ~ '^(MassHealth|Medicare)'),
  'only the public programmes keep their real names');

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select isnt_empty($$ select 1 from insurance_plans $$, 'a signed-in patient can read the plans');
select throws_ok($$ insert into insurance_plans (name, kind) values ('Made Up Plan', 'commercial') $$, '42501', null,
  'patients cannot add plans');
select lives_ok($$ insert into coverages (patient_id, plan_id, payer_name, member_id)
                   select '30000000-0000-4000-8000-000000000001', id, name, 'SYN123' from insurance_plans where kind = 'medicaid' limit 1 $$,
  'a patient adds a card by picking a plan, with no photos');
reset role;

set local role anon;
select throws_ok($$ select 1 from insurance_plans $$, '42501', null, 'signed-out callers cannot read the plans');
reset role;

select * from finish();
rollback;
