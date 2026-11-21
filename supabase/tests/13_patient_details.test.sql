-- Patients choose their preferred clinic and give their home address from the app (section 05).
-- Only through update_my_details, only for records they may see, and audited without the values.
begin;
select plan(16);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  -- A fully signed-in session: password and emailed code (section 05).
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid where exists (select 1 from auth.sessions where id = uid) on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
grant execute on function pg_temp.loc(text) to authenticated;

-- Elena (...014) is linked to her record (...001); patient ...002 belongs to someone else.
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001');

select has_column('public', 'patients', 'address_line1', 'patients have a home address');
select has_function('public', 'update_my_details', array['uuid', 'uuid', 'text', 'text', 'text', 'text', 'text'],
  'the app saves details through one function');

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select lives_ok($$ select update_my_details('30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'),
  ' 12 Example Lane ', 'Apt 4', 'Quincy', 'ma', '02169') $$, 'a patient saves their own clinic and address');
select results_eq($$ select address_line1, address_line2, city, state, postal_code from patients
                     where id = '30000000-0000-4000-8000-000000000001' $$,
  $$ values ('12 Example Lane', 'Apt 4', 'Quincy', 'MA', '02169') $$, 'the address is trimmed and the state upper-cased');
select is((select home_location_id from patients where id = '30000000-0000-4000-8000-000000000001'), pg_temp.loc('quincy'),
  'the chosen clinic becomes the home location');
select isnt((select details_confirmed_at from patients where id = '30000000-0000-4000-8000-000000000001'), null,
  'the app knows the details were confirmed');

select throws_ok($$ select update_my_details('30000000-0000-4000-8000-000000000002', pg_temp.loc('quincy'),
  '1 Other Street', null, 'Boston', 'MA', '02116') $$, '42501', null, 'a patient cannot change someone else''s details');
select throws_ok($$ select update_my_details('30000000-0000-4000-8000-000000000001', gen_random_uuid(),
  '12 Example Lane', null, 'Quincy', 'MA', '02169') $$, '22023', null, 'the clinic must be one of ours');
select throws_ok($$ select update_my_details('30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'),
  '12 Example Lane', null, 'Quincy', 'MA', '2169') $$, '23514', null, 'a ZIP code must have five digits');
select throws_ok($$ select update_my_details('30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'),
  '12 Example Lane', null, '', 'MA', '02169') $$, '23514', null, 'an address is all or nothing');

-- Direct writes are still refused: patients have no update policy on patients.
update patients set city = 'Elsewhere' where id = '30000000-0000-4000-8000-000000000001';
select is((select city from patients where id = '30000000-0000-4000-8000-000000000001'), 'Quincy',
  'a patient cannot update their row directly');
reset role;

-- A closed clinic cannot be chosen.
update locations set active = false where code = 'back-bay';
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select throws_ok($$ select update_my_details('30000000-0000-4000-8000-000000000001', pg_temp.loc('back-bay'),
  '12 Example Lane', null, 'Quincy', 'MA', '02169') $$, '22023', null, 'a closed clinic cannot be chosen');
reset role;
update locations set active = true where code = 'back-bay';

-- Signed out: no access at all.
set local role anon;
select throws_ok($$ select update_my_details('30000000-0000-4000-8000-000000000001', null, null, null, null, null, null) $$,
  '42501', null, 'signed-out callers cannot use the function');
reset role;

-- Audit: who changed which columns, never the address itself.
select is((select actor_id from audit_log where table_name = 'patients' and row_pk = '30000000-0000-4000-8000-000000000001'
            and action = 'UPDATE' order by id desc limit 1), '10000000-0000-4000-8000-000000000014'::uuid,
  'the change is audited against the patient''s sign-in');
select ok((select new_row -> 'changed_columns' ? 'city' from audit_log where table_name = 'patients'
            and row_pk = '30000000-0000-4000-8000-000000000001' and action = 'UPDATE' order by id desc limit 1),
  'the audit names the changed columns');
select ok((select new_row::text not like '%Example Lane%' from audit_log where table_name = 'patients'
            and row_pk = '30000000-0000-4000-8000-000000000001' order by id desc limit 1),
  'the audit never holds the address');

select * from finish();
rollback;
