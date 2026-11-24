-- Team requests in Jira (ADR 0013): n8n claims each new handover once, sees only the allow-listed fields, and records
-- the Jira key; it never reads the handover itself (no names, no summary).
begin;
select plan(8);

insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001')
  on conflict do nothing;
select set_config('request.jwt.claims', json_build_object('sub', '10000000-0000-4000-8000-000000000014')::text, true);
insert into assistant_handovers (id, patient_id, category, language, summary) values
  ('70000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', 'billing', 'en', 'Patient asks about a balance.'),
  ('70000000-0000-4000-8000-000000000002', '30000000-0000-4000-8000-000000000001', 'booking', 'en', 'Patient wants a Saturday.');
insert into staff_tasks (kind, location_id, reference_id, priority)
  select 'assistant_handover', p.home_location_id, h.id, 'normal' from assistant_handovers h join patients p on p.id = h.patient_id
  where h.id::text like '70000000-%';

select ok(has_function_privilege('northgate_patient_actions', 'private.claim_handover_tickets(integer)', 'execute')
  and has_function_privilege('northgate_patient_actions', 'private.record_handover_ticket(uuid, text)', 'execute'),
  'n8n may call the two ticket functions');
select is((select count(*)::int from private.claim_handover_tickets(10) where handover_id::text like '70000000-%'), 2,
  'n8n claims each new handover');
select is((select count(*)::int from private.claim_handover_tickets(10) where handover_id::text like '70000000-%'), 0,
  'a second claim returns nothing: one ticket per handover');
select ok(not has_table_privilege('northgate_patient_actions', 'public.assistant_handovers', 'select')
  and not has_table_privilege('northgate_patient_actions', 'private.handover_tickets', 'select'),
  'n8n cannot read the handover summary or patient');
select lives_ok($$ select private.record_handover_ticket('70000000-0000-4000-8000-000000000001', 'NGD-1') $$,
  'n8n records the Jira key');

select is((select jira_key from private.handover_tickets where handover_id = '70000000-0000-4000-8000-000000000001'), 'NGD-1',
  'the key is stored against the handover');
select is(pg_get_function_result('private.claim_handover_tickets(integer)'::regprocedure),
  'TABLE(handover_id uuid, short_ref text, category text, clinic text, created_at timestamp with time zone)',
  'the ticket fields are an allow-list: no name, contact details or summary');
update private.handover_tickets set claimed_at = now() - interval '11 minutes'
  where handover_id = '70000000-0000-4000-8000-000000000002';
select is((select count(*)::int from private.claim_handover_tickets(10) where handover_id::text like '70000000-%'), 1,
  'a claim that never got a Jira key is offered again after 10 minutes');

select * from finish();
rollback;
