-- Patients and their dental records. Every row is synthetic, enforced by constraints.
-- Row level security (Fiona reviews line by line): staff see patients whose home location is theirs,
-- clinicians also see patients they have treated, org_admin sees all, patients see nothing until
-- their account is linked (section 04). Staff need a verified second factor; nobody deletes a record.

-- One patient per organisation, never per location.
create table public.patients (
  id                 uuid primary key default gen_random_uuid(),
  mrn                text not null unique check (mrn ~ '^NG[0-9]{7}$'),
  given_name         text not null,
  family_name        text not null,
  preferred_name     text,
  date_of_birth      date not null check (date_of_birth >= '1900-01-01'),
  sex_at_birth       text not null check (sex_at_birth in ('female', 'male', 'unknown')),
  home_location_id   uuid not null references public.locations (id) on delete restrict,
  email              text check (email ~ '^[a-z0-9._-]+@([a-z0-9-]+\.)*synthetic$'),     -- only .synthetic addresses
  phone              text check (phone ~ '^\+1[2-9][0-9]{2}55501[0-9]{2}$'),           -- only the fictional 555-01xx range
  preferred_language text not null default 'en' check (preferred_language in ('en', 'es')),
  deceased_at        timestamptz,
  is_synthetic       boolean not null default true check (is_synthetic),               -- E24: real patients cannot be stored
  is_canary          boolean not null default false,
  created_at         timestamptz not null default now()
);
create index patients_home_location_idx on public.patients (home_location_id);

create table public.encounters (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references public.patients (id) on delete restrict,
  location_id     uuid not null references public.locations (id) on delete restrict,
  practitioner_id uuid not null references public.practitioners (id) on delete restrict,
  occurred_at     timestamptz not null,
  kind            text not null check (kind in ('exam', 'hygiene', 'treatment', 'emergency', 'consultation')),
  reason          text
);
create index encounters_patient_idx on public.encounters (patient_id);
create index encounters_practitioner_patient_idx on public.encounters (practitioner_id, patient_id);

-- Universal Numbering System: permanent teeth 1 to 32, primary teeth A to T (E23).
create table public.tooth_conditions (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients (id) on delete restrict,
  encounter_id uuid references public.encounters (id) on delete restrict,
  tooth        text not null check (tooth ~ '^([1-9]|[12][0-9]|3[0-2]|[A-T])$'),
  surface      text check (surface ~ '^[MODBLFI]{1,5}$'),
  condition    text not null check (condition in ('caries', 'filled', 'crown', 'missing', 'implant', 'root_canal', 'fractured', 'sealant')),
  recorded_at  timestamptz not null
);
create index tooth_conditions_patient_idx on public.tooth_conditions (patient_id);

create table public.treatment_plans (
  id          uuid primary key default gen_random_uuid(),
  patient_id  uuid not null references public.patients (id) on delete restrict,
  location_id uuid not null references public.locations (id) on delete restrict,
  status      text not null check (status in ('proposed', 'accepted', 'in_progress', 'completed', 'declined')),
  created_at  timestamptz not null default now()
);
create index treatment_plans_patient_idx on public.treatment_plans (patient_id);

create table public.plan_phases (
  id       uuid primary key default gen_random_uuid(),
  plan_id  uuid not null references public.treatment_plans (id) on delete restrict,
  sequence int not null check (sequence > 0),
  name     text not null,
  unique (plan_id, sequence)
);

-- A procedure is always a service the location offers; fees are whole cents (money: line-by-line review).
create table public.dental_procedures (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references public.patients (id) on delete restrict,
  location_id     uuid not null,
  service_id      uuid not null,
  practitioner_id uuid references public.practitioners (id) on delete restrict,
  encounter_id    uuid references public.encounters (id) on delete restrict,
  plan_phase_id   uuid references public.plan_phases (id) on delete restrict,
  tooth           text check (tooth ~ '^([1-9]|[12][0-9]|3[0-2]|[A-T])$'),
  surface         text check (surface ~ '^[MODBLFI]{1,5}$'),
  status          text not null check (status in ('planned', 'completed')),
  fee_cents       integer not null check (fee_cents >= 0),
  performed_at    timestamptz,
  check ((status = 'completed') = (performed_at is not null)),
  foreign key (location_id, service_id) references public.location_services (location_id, service_id) on delete restrict
);
create index dental_procedures_patient_idx on public.dental_procedures (patient_id);

------------------------------------------------------------------------------------------
-- Access
------------------------------------------------------------------------------------------

-- Can the caller see this patient? Staff by home location, clinicians also by treatment, org_admin all.
create function private.can_see_patient(pid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_org_admin()
      or exists (select 1 from public.patients p
                  where p.id = pid and p.home_location_id in (select private.my_location_ids()))
      or (private.my_role() = 'clinician'
          and exists (select 1 from public.encounters e
                       where e.patient_id = pid and e.practitioner_id = private.current_practitioner_id()))
$$;
grant execute on function private.can_see_patient(uuid) to authenticated;

grant select on public.patients, public.encounters, public.tooth_conditions, public.treatment_plans,
  public.plan_phases, public.dental_procedures to authenticated;
grant insert, update on public.patients, public.encounters, public.tooth_conditions, public.treatment_plans,
  public.plan_phases, public.dental_procedures to authenticated;

do $$
declare t text;
begin
  foreach t in array array['patients', 'encounters', 'tooth_conditions', 'treatment_plans', 'plan_phases', 'dental_procedures'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format(
      'create policy staff_need_mfa on public.%I as restrictive for all to authenticated
         using ((select private.my_role()) is not null and (not (select private.is_staff()) or (select private.has_mfa())))
         with check ((select private.my_role()) is not null and (not (select private.is_staff()) or (select private.has_mfa())))', t);
    execute format('create trigger audit_row after insert or update or delete on public.%I
                    for each row execute function private.audit_row()', t);
  end loop;
end;
$$;

create policy read_patients on public.patients for select to authenticated
  using (private.can_see_patient(id));
-- Front desk and managers register and update patients who belong to their own locations.
create policy front_desk_writes_patients on public.patients for all to authenticated
  using ((select private.is_org_admin())
         or ((select private.my_role()) in ('receptionist', 'location_manager')
             and home_location_id in (select private.my_location_ids())))
  with check ((select private.is_org_admin())
         or ((select private.my_role()) in ('receptionist', 'location_manager')
             and home_location_id in (select private.my_location_ids())));

create policy read_encounters on public.encounters for select to authenticated using (private.can_see_patient(patient_id));
create policy read_tooth_conditions on public.tooth_conditions for select to authenticated using (private.can_see_patient(patient_id));
create policy read_treatment_plans on public.treatment_plans for select to authenticated using (private.can_see_patient(patient_id));
create policy read_plan_phases on public.plan_phases for select to authenticated
  using (exists (select 1 from public.treatment_plans tp where tp.id = plan_id and private.can_see_patient(tp.patient_id)));
create policy read_dental_procedures on public.dental_procedures for select to authenticated using (private.can_see_patient(patient_id));

-- Clinical writes are org_admin only for now; clinicians chart through the dentist desk (section 08).
create policy admin_writes_encounters on public.encounters for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));
create policy admin_writes_tooth_conditions on public.tooth_conditions for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));
create policy admin_writes_treatment_plans on public.treatment_plans for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));
create policy admin_writes_plan_phases on public.plan_phases for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));
create policy admin_writes_dental_procedures on public.dental_procedures for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));
