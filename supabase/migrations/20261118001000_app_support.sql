-- What the patient app needs: a profile for every new sign-up, limits on parents' access to teenagers' records,
-- and coverage cards (rows plus photos in a private bucket).
-- Row level security and Storage policies: Fiona reviews line by line.

------------------------------------------------------------------------------------------
-- New sign-ups (E34): always a patient profile. Staff roles are only ever set by org_admin.
------------------------------------------------------------------------------------------

create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, role, display_name)
  values (new.id, 'patient', coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), 'Patient'))
  on conflict (id) do nothing;
  return null;
end;
$$;
-- Every new user; seeds and test fixtures then set staff roles with an upsert (as the database owner).
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

------------------------------------------------------------------------------------------
-- Teenagers (blueprint 33): parents of children aged 13 to 17 see names and appointments,
-- but not visits, charts or plans, unless org_settings.teen_proxy_full_access is true.
------------------------------------------------------------------------------------------

create function private.my_clinical_patient_ids() returns setof uuid
language sql stable security definer set search_path = '' as $$
  select l.patient_id from public.patient_links l where l.profile_id = auth.uid()
  union all
  select x.patient_id
    from public.patient_proxies x join public.patients p on p.id = x.patient_id
   where x.proxy_profile_id = auth.uid() and current_date < x.ends_on
     and (p.date_of_birth + interval '13 years' > current_date
          or coalesce((select (s.settings ->> 'teen_proxy_full_access')::boolean from public.org_settings s), false))
$$;
grant execute on function private.my_clinical_patient_ids() to authenticated;

do $$
declare t text;
begin
  foreach t in array array['encounters', 'tooth_conditions', 'treatment_plans', 'plan_phases', 'dental_procedures'] loop
    execute format('drop policy patient_reads_own_%s on public.%I', t, t);
    execute format('create policy patient_reads_own_%s on public.%I for select to authenticated
                    using (patient_id in (select private.my_clinical_patient_ids()))', t, t);
  end loop;
end;
$$;

------------------------------------------------------------------------------------------
-- Coverage cards. Patients (and parents) add cards; staff review them in the coverage queue (section 08).
------------------------------------------------------------------------------------------

create table public.coverages (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients (id) on delete restrict,
  payer_name   text not null,
  member_id    text not null,
  group_number text,
  front_path   text,          -- object names in the coverage-cards bucket, under the patient's folder
  back_path    text,
  status       text not null default 'pending_review' check (status in ('pending_review', 'verified', 'rejected')),
  created_by   uuid default auth.uid(),
  created_at   timestamptz not null default now(),
  check (front_path is null or front_path like patient_id::text || '/%'),
  check (back_path is null or back_path like patient_id::text || '/%')
);
create index coverages_patient_idx on public.coverages (patient_id);

alter table public.coverages enable row level security;
create policy staff_need_mfa on public.coverages as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create trigger audit_row after insert or update or delete on public.coverages
  for each row execute function private.audit_row();

revoke all on public.coverages from authenticated;
grant select on public.coverages to authenticated;
grant insert (patient_id, payer_name, member_id, group_number, front_path, back_path) on public.coverages to authenticated;
grant update (status) on public.coverages to authenticated;

create policy patient_reads_own_coverages on public.coverages for select to authenticated
  using (patient_id in (select private.my_patient_ids()));
create policy patient_adds_coverages on public.coverages for insert to authenticated
  with check (patient_id in (select private.my_patient_ids()));
create policy staff_reads_coverages on public.coverages for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
create policy front_desk_reviews_coverages on public.coverages for update to authenticated
  using ((select private.my_role()) in ('receptionist', 'location_manager', 'org_admin') and private.can_see_patient(patient_id))
  with check ((select private.my_role()) in ('receptionist', 'location_manager', 'org_admin') and private.can_see_patient(patient_id));

-- Private bucket: JPEG or PNG, up to 5 MB, one folder per patient id. No public URLs.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('coverage-cards', 'coverage-cards', false, 5242880, array['image/jpeg', 'image/png'])
on conflict (id) do nothing;

-- The patient id at the start of an object's name, or null when it is not a uuid.
create function private.card_patient(object_name text) returns uuid
language sql immutable set search_path = '' as $$
  select case when split_part(object_name, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(object_name, '/', 1)::uuid end
$$;
grant execute on function private.card_patient(text) to authenticated;

create policy coverage_cards_patient_read on storage.objects for select to authenticated
  using (bucket_id = 'coverage-cards' and private.card_patient(name) in (select private.my_patient_ids()));
create policy coverage_cards_patient_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'coverage-cards' and private.card_patient(name) in (select private.my_patient_ids()));
create policy coverage_cards_staff_read on storage.objects for select to authenticated
  using (bucket_id = 'coverage-cards' and private.is_staff() and private.passes_staff_gate()
         and private.can_see_patient(private.card_patient(name)));
