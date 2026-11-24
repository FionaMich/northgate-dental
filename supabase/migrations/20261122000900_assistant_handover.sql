-- Section 10: the assistant hands a conversation to the team (Lisa benchmark: "what your team receives afterwards").
-- Line-by-line review (Fiona): assistant safety.
--
-- A patient's session (through the assistant service) may open one kind of task only: a handover with a short summary
-- in English, for the patient's own home clinic. The summary is written from the conversation's structured outcome and
-- capped in length; the conversation itself stays in the assistant's checkpoint store.

create table public.assistant_handovers (
  id         uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients (id) on delete restrict,
  category   text not null check (category in ('booking', 'billing', 'clinical_question', 'emergency', 'shop', 'other')),
  language   text not null check (char_length(language) between 2 and 8),
  summary    text not null check (char_length(summary) between 5 and 600),
  created_at timestamptz not null default now()
);
alter table public.assistant_handovers enable row level security;
create policy staff_need_mfa on public.assistant_handovers as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create trigger audit_row after insert or update or delete on public.assistant_handovers
  for each row execute function private.audit_row();
insert into private.audit_redacted_tables (table_name) values ('assistant_handovers') on conflict do nothing;
revoke all on public.assistant_handovers from anon, authenticated;
grant select on public.assistant_handovers to authenticated;
create policy patient_reads_own_handovers on public.assistant_handovers for select to authenticated
  using (patient_id in (select private.my_patient_ids()));
create policy staff_reads_handovers on public.assistant_handovers for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));

alter table public.staff_tasks drop constraint staff_tasks_kind_check,
  add constraint staff_tasks_kind_check check (kind in ('schedule_conflict', 'checkin_follow_up', 'billing_follow_up',
                                                        'shop_fulfilment', 'assistant_handover'));

create function public.request_handover(category text, language text, summary text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me   uuid := (select l.patient_id from public.patient_links l where l.profile_id = auth.uid());
  home uuid;
  h    uuid;
begin
  if not private.passes_patient_gate() or me is null then
    raise exception 'sign in with a linked patient record first' using errcode = 'insufficient_privilege';
  end if;
  select p.home_location_id into home from public.patients p where p.id = me;
  insert into public.assistant_handovers (patient_id, category, language, summary)
  values (me, request_handover.category, request_handover.language, left(btrim(request_handover.summary), 600))
  returning id into h;
  insert into public.staff_tasks (kind, location_id, reference_id, priority)
  values ('assistant_handover', home, h, case when category = 'emergency' then 'urgent'
                                             when category = 'clinical_question' then 'high' else 'normal' end);
  if category = 'emergency' then
    perform pgmq.send('urgent', jsonb_build_object('type', 'assistant_emergency', 'handover_id', h));
  end if;
  return h;
end;
$$;
revoke all on function public.request_handover(text, text, text) from public;
grant execute on function public.request_handover(text, text, text) to authenticated;
