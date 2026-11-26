-- The public website (section 08): visitors read the public catalogue through one function, and send an enquiry
-- through another that checks consent and limits repeats; enquiries are a task for the chosen clinic, read by staff only.
begin;
select plan(9);

set local role anon;
select ok((select jsonb_array_length(public.public_catalogue() -> 'services')) >= 10, 'a visitor sees the services');
select ok((select (public.public_catalogue() -> 'locations' -> 0 ->> 'name') is not null), 'and the clinics with their hours');
select ok((select public.public_catalogue()::text not like '%patient%'), 'and nothing about patients');
select lives_ok($$ select public.submit_lead('Ada Visitor', 'ada@example.com', null, 'quincy', 'D1110',
                                            'Do you see children on Saturdays?', true) $$, 'a visitor sends an enquiry');
select throws_ok($$ select public.submit_lead('Ada Visitor', 'ada@example.com', null, 'quincy', null, 'Hello there', false) $$,
  '22023', null, 'no enquiry without consent to be contacted');
select throws_ok($$ select public.submit_lead('Ada', 'not-an-email', null, 'quincy', null, 'Hello there', true) $$,
  '22023', null, 'an email address must look like one');
select public.submit_lead('Ada Visitor', 'ada@example.com', null, 'quincy', null, 'Second', true);
select public.submit_lead('Ada Visitor', 'ada@example.com', null, 'quincy', null, 'Third', true);
select throws_ok($$ select public.submit_lead('Ada Visitor', 'ada@example.com', null, 'quincy', null, 'Fourth', true) $$,
  '54000', null, 'at most three enquiries a day from one address');
select throws_ok($$ select count(*) from public.leads $$, '42501', null, 'visitors cannot read enquiries');
reset role;

select is((select count(*)::int from staff_tasks t join leads l on l.id = t.reference_id
            where t.kind = 'website_lead' and t.location_id = (select id from locations where code = 'quincy')), 3,
  'each enquiry is a task for the chosen clinic');

select * from finish();
rollback;
