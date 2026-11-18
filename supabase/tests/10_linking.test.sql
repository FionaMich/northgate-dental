-- Patient linking: front desk issues a one-time code, the patient redeems it, and then sees only their own records.
begin;
select plan(24);

select has_table('public', 'patient_links', 'patient_links exists');
select has_table('public', 'patient_proxies', 'patient_proxies exists');
select has_table('public', 'link_invitations', 'link_invitations exists');

create function pg_temp.act_as(uid uuid, aal text default 'aal2') returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal)::text, true);
  set local role authenticated;
end;
$$;

-- Two extra synthetic patient sign-ins for the proxy and refusal cases.
insert into auth.users (id, email, aud, role) values
  ('10000000-0000-4000-8000-000000000091', 'parent@tests.synthetic', 'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000092', 'other@tests.synthetic',  'authenticated', 'authenticated');
insert into profiles (id, role, display_name) values
  ('10000000-0000-4000-8000-000000000091', 'patient', 'Synthetic Test Parent'),
  ('10000000-0000-4000-8000-000000000092', 'patient', 'Synthetic Test Other');

-- Elena (Cambridge persona) gets an appointment so we can check what she sees after linking.
insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
select '30000000-0000-4000-8000-000000000001', l.id, p.id, s.id, '2026-12-09 15:00+00', '2026-12-09 16:00+00', 'booked'
  from locations l, practitioners p, services s
 where l.code = 'cambridge' and p.profile_id = '10000000-0000-4000-8000-000000000012' and s.code = 'D1110';

-- Codes are issued by front desk staff who can see the patient, with 2FA.
create temp table codes (who text primary key, code text);
grant all on codes to authenticated;
select pg_temp.act_as('10000000-0000-4000-8000-000000000003');   -- Cambridge reception
insert into codes values ('elena', create_link_invitation('30000000-0000-4000-8000-000000000001'));
insert into codes values ('sofia', create_link_invitation('30000000-0000-4000-8000-000000000003', 'proxy'));
select throws_ok($$ select create_link_invitation('30000000-0000-4000-8000-000000000002') $$,
  '42501', null, 'front desk cannot issue a code for a patient they cannot see');                 -- Marcus is at Quincy
select throws_ok($$ select create_link_invitation('30000000-0000-4000-8000-000000000001', 'proxy') $$,
  '22023', null, 'a proxy code is refused for an adult');
select throws_ok($$ select code_hash from link_invitations $$, '42501', null, 'staff cannot read the stored hash');
reset role;
select pg_temp.act_as('10000000-0000-4000-8000-000000000003', 'aal1');
select throws_ok($$ select create_link_invitation('30000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'staff without 2FA cannot issue codes');
reset role;
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select throws_ok($$ select create_link_invitation('30000000-0000-4000-8000-000000000001') $$,
  '42501', null, 'a patient cannot issue codes');
reset role;

select is((select count(*)::int from link_invitations where code_hash = sha256(convert_to((select code from codes where who = 'elena'), 'UTF8'))),
  1, 'the code is stored only as its hash');
select is_empty($$ select 1 from audit_log where new_row::text like '%' || (select code from codes where who = 'elena') || '%'
                                           or new_row ? 'code_hash' and new_row ->> 'code_hash' is not null $$,
  'the audit log holds neither the code nor its hash');

-- Before linking the patient sees nothing (E30 still holds).
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select is_empty($$ select 1 from patients $$, 'no records before the code is redeemed');
select throws_ok($$ select redeem_link_invitation('WRONG-CODE') $$, '22023', null, 'a wrong code is refused');
select is(redeem_link_invitation((select code from codes where who = 'elena')), '30000000-0000-4000-8000-000000000001'::uuid,
  'the right code links the sign-in to the patient');
select results_eq($$ select id from patients $$, $$ values ('30000000-0000-4000-8000-000000000001'::uuid) $$,
  'a linked patient sees their own record and no one else''s');
select isnt_empty($$ select 1 from encounters $$, 'a linked patient sees their own visits');
select is((select count(*)::int from encounters where patient_id <> '30000000-0000-4000-8000-000000000001'), 0,
  'a linked patient sees no one else''s visits');
select is((select count(*)::int from appointments), 1, 'a linked patient sees their own appointments');
select isnt_empty($$ select 1 from appointment_events $$, 'a linked patient sees their own appointment history');
select results_eq($$ update patients set given_name = 'Changed' returning id $$, $$ select null::uuid where false $$,
  'a patient cannot change their record directly');
reset role;

-- A code works once only, and only for one sign-in.
select pg_temp.act_as('10000000-0000-4000-8000-000000000092');
select throws_ok(format('select redeem_link_invitation(%L)', (select code from codes where who = 'elena')),
  '22023', null, 'a used code is refused');
reset role;

-- Expired codes are refused.
update link_invitations set expires_at = now() - interval '1 second'
 where code_hash = sha256(convert_to((select code from codes where who = 'sofia'), 'UTF8'));
select pg_temp.act_as('10000000-0000-4000-8000-000000000091');
select throws_ok(format('select redeem_link_invitation(%L)', (select code from codes where who = 'sofia')),
  '22023', null, 'an expired code is refused');
reset role;

-- A parent with a proxy code sees the child until the child turns 18.
update link_invitations set expires_at = now() + interval '1 day'
 where code_hash = sha256(convert_to((select code from codes where who = 'sofia'), 'UTF8'));
select pg_temp.act_as('10000000-0000-4000-8000-000000000091');
select lives_ok(format('select redeem_link_invitation(%L)', (select code from codes where who = 'sofia')),
  'a parent redeems a proxy code for a child');
select results_eq($$ select id from patients $$, $$ values ('30000000-0000-4000-8000-000000000003'::uuid) $$,
  'the parent sees the child''s record');
reset role;
update patient_proxies set ends_on = current_date where proxy_profile_id = '10000000-0000-4000-8000-000000000091';
select pg_temp.act_as('10000000-0000-4000-8000-000000000091');
select is_empty($$ select 1 from patients $$, 'proxy access ends on the child''s 18th birthday');
reset role;

select * from finish();
rollback;
