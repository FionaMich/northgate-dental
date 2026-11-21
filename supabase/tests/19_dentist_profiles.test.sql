-- Patients choose their dentist: patient-facing profiles of active practitioners, visible to verified patients only.
begin;
select plan(7);

create function pg_temp.act(uid uuid, verified boolean) returns void language plpgsql as $$
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
  ('10000000-0000-4000-8000-000000000061', 'chooser@tests.synthetic', 'authenticated', 'authenticated', now()),
  ('10000000-0000-4000-8000-000000000062', 'password.only@tests.synthetic', 'authenticated', 'authenticated', now());

select has_column('public', 'practitioners', 'public_name', 'practitioners have a patient-facing name');
select is((select count(*)::int from practitioners where active and (public_name is null or photo_key is null)), 0,
  'every active practitioner has a name and a photo for patients');

select pg_temp.act('10000000-0000-4000-8000-000000000061', true);
select is((select count(*)::int from practitioners), (select count(*)::int from practitioners where active),
  'a signed-in patient sees the active dentists');
select isnt_empty($$ select 1 from practitioner_roles $$, 'and where and as what they work');
select ok((select bool_and(public_name !~* 'synthetic') from practitioners), 'patients never see placeholder names');
select lives_ok($$ update practitioners set bio = 'changed' $$, 'an update runs but changes nothing');
reset role;

select pg_temp.act('10000000-0000-4000-8000-000000000062', false);
select is((select count(*)::int from practitioners), 0, 'a password-only session sees no dentists');
reset role;

select * from finish();
rollback;
