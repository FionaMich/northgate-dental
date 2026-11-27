-- The kill switch: an organisation admin with two-factor turns Nora off for everyone; a patient's session can read
-- the switch (the assistant checks it before every turn) but never change it.
begin;
select plan(4);

create function pg_temp.act_as(uid uuid, aal text) returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', aal, 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001')
  on conflict do nothing;

select pg_temp.act_as('10000000-0000-4000-8000-000000000014', 'aal1');
select ok(public.assistant_enabled(), 'Nora is on unless someone turns her off');
update org_settings set settings = settings || '{"assistant_enabled": false}';
reset role;
select ok((select coalesce((settings ->> 'assistant_enabled')::boolean, true) from org_settings), 'a patient cannot turn Nora off');

select pg_temp.act_as('10000000-0000-4000-8000-000000000001', 'aal2');   -- the seeded organisation admin
update org_settings set settings = settings || '{"assistant_enabled": false}';
reset role;

select pg_temp.act_as('10000000-0000-4000-8000-000000000014', 'aal1');
select ok(not public.assistant_enabled(), 'after the admin turns her off, the assistant sees it');
reset role;
select is((select count(*)::int from audit_log where table_name = 'org_settings' and action = 'UPDATE'), 1,
  'the switch is audited');

select * from finish();
rollback;
