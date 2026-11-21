-- Paying in the app: only for your own visit, only from a fully signed-in session, at the price-list amount.
begin;
select plan(5);

create function pg_temp.act_as(uid uuid, verified boolean default true) returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  if verified then
    insert into private.verified_sessions (session_id, user_id) select uid, uid on conflict do nothing;
  end if;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;

-- Elena (...014) is linked to record ...001; record ...002 belongs to someone else.
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001')
  on conflict do nothing;
insert into appointments (id, patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
select x.id::uuid, x.patient::uuid, l.id, pr.id, s.id, now() + x.at, now() + x.at + interval '1 hour', 'booked'
  from (values ('4c000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', interval '4 days'),
               ('4c000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000002', interval '5 days')) x (id, patient, at)
  join locations l on l.code = 'quincy'
  join practitioners pr on pr.profile_id = '10000000-0000-4000-8000-000000000013'
  join services s on s.code = 'D1110';

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select ok(length(public.start_my_payment('4c000000-0000-4000-8000-000000000001')) = 32, 'a patient gets a pay link for their own visit');
select throws_ok($$ select public.start_my_payment('4c000000-0000-4000-8000-000000000002') $$, '42501', null,
  'but not for someone else''s');
reset role;
select is((select amount_cents from payments where appointment_id = '4c000000-0000-4000-8000-000000000001'),
  (select price_cents from location_services ls join locations l on l.id = ls.location_id join services s on s.id = ls.service_id
    where l.code = 'quincy' and s.code = 'D1110'), 'the amount is the price-list amount');
select is((select purpose from private.action_tokens where appointment_id = '4c000000-0000-4000-8000-000000000001'), 'pay',
  'the link is a pay link');

delete from private.verified_sessions where user_id = '10000000-0000-4000-8000-000000000014';
select pg_temp.act_as('10000000-0000-4000-8000-000000000014', false);
select throws_ok($$ select public.start_my_payment('4c000000-0000-4000-8000-000000000001') $$, '42501', null,
  'a session without the emailed sign-in code cannot start a payment');
reset role;

select * from finish();
rollback;
