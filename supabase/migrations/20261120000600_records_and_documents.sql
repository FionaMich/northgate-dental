-- Richer records (Fiona, 2026-11-20): patients see the names of the dentists who treated them or will see them,
-- and documents the practice shares (X-ray images, visit summaries, letters) in a private bucket.
-- Row level security and Storage policies: Fiona reviews line by line.

-- Dentist names: only practitioners on the patient's own visits or appointments (password plus code sessions only,
-- because both helper functions apply the patient gate).
create policy patient_reads_own_practitioners on public.practitioners for select to authenticated
  using (exists (select 1 from public.encounters e
                  where e.practitioner_id = practitioners.id and e.patient_id in (select private.my_clinical_patient_ids()))
         or exists (select 1 from public.appointments a
                     where a.practitioner_id = practitioners.id and a.patient_id in (select private.my_patient_ids())));

create table public.patient_documents (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients (id) on delete restrict,
  encounter_id uuid,
  kind         text not null check (kind in ('xray', 'visit_summary', 'letter')),
  title        text not null check (char_length(title) between 1 and 120),
  file_path    text not null unique,
  content_type text not null check (content_type in ('image/png', 'image/jpeg', 'application/pdf')),
  created_by   uuid default auth.uid(),
  shared_at    timestamptz not null default now(),
  check (file_path like patient_id::text || '/%'),
  foreign key (encounter_id, patient_id) references public.encounters (id, patient_id) on delete restrict
);
create index patient_documents_patient_idx on public.patient_documents (patient_id, shared_at desc);

alter table public.patient_documents enable row level security;
create policy staff_need_mfa on public.patient_documents as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create trigger audit_row after insert or update or delete on public.patient_documents
  for each row execute function private.audit_row();

revoke all on public.patient_documents from anon, authenticated;
grant select, insert on public.patient_documents to authenticated;

-- Clinical documents follow the clinical rule (parents of teenagers see them only if the organisation allows).
create policy patient_reads_own_documents on public.patient_documents for select to authenticated
  using (patient_id in (select private.my_clinical_patient_ids()));
create policy staff_reads_documents on public.patient_documents for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
create policy staff_shares_documents on public.patient_documents for insert to authenticated
  with check ((select private.my_role()) in ('clinician', 'receptionist', 'location_manager', 'org_admin')
              and private.can_see_patient(patient_id));

-- Private bucket: PNG, JPEG or PDF, up to 10 MB, one folder per patient ID. No public URLs; the app asks for
-- short-lived signed links.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('patient-documents', 'patient-documents', false, 10485760, array['image/png', 'image/jpeg', 'application/pdf'])
on conflict (id) do nothing;

create policy patient_documents_patient_read on storage.objects for select to authenticated
  using (bucket_id = 'patient-documents' and private.card_patient(name) in (select private.my_clinical_patient_ids()));
create policy patient_documents_staff_read on storage.objects for select to authenticated
  using (bucket_id = 'patient-documents' and private.is_staff() and private.passes_staff_gate()
         and private.can_see_patient(private.card_patient(name)));
create policy patient_documents_staff_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'patient-documents' and private.passes_staff_gate()
              and private.my_role() in ('clinician', 'receptionist', 'location_manager', 'org_admin')
              and private.can_see_patient(private.card_patient(name)));
