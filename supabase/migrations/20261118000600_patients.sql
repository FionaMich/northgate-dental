-- Patients and their dental records. Every row is synthetic, enforced by constraints.
-- Row level security (reviewed and approved by Fiona 2026-11-18): staff see patients whose home location
-- is theirs or who have visited one of their locations, clinicians also see patients they have treated, org_admin sees all, patients see nothing until
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

-- Dates that depend on today are checked by trigger (check constraints must not depend on the clock).
create function private.check_patient_dates() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.date_of_birth > current_date then
    raise exception 'date of birth is in the future' using errcode = 'check_violation';
  end if;
  if new.deceased_at is not null and new.deceased_at::date < new.date_of_birth then
    raise exception 'date of death is before date of birth' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger patients_check_dates before insert or update of date_of_birth, deceased_at on public.patients
  for each row execute function private.check_patient_dates();

create table public.encounters (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references public.patients (id) on delete restrict,
  location_id     uuid not null references public.locations (id) on delete restrict,
  practitioner_id uuid not null references public.practitioners (id) on delete restrict,
  occurred_at     timestamptz not null,
  kind            text not null check (kind in ('exam', 'hygiene', 'treatment', 'emergency', 'consultation')),
  reason          text,
  unique (id, patient_id)          -- lets other records insist they belong to the same patient
);
create index encounters_patient_idx on public.encounters (patient_id);
create index encounters_practitioner_patient_idx on public.encounters (practitioner_id, patient_id);

-- Universal Numbering System: permanent teeth 1 to 32, primary teeth A to T (E23).
create table public.tooth_conditions (
  id           uuid primary key default gen_random_uuid(),
  patient_id   uuid not null references public.patients (id) on delete restrict,
  encounter_id uuid,
  tooth        text not null check (tooth ~ '^([1-9]|[12][0-9]|3[0-2]|[A-T])$'),
  surface      text check (surface ~ '^[MODBLFI]{1,5}$'),
  condition    text not null check (condition in ('caries', 'filled', 'crown', 'missing', 'implant', 'root_canal', 'fractured', 'sealant')),
  recorded_at  timestamptz not null,
  foreign key (encounter_id, patient_id) references public.encounters (id, patient_id) on delete restrict
);
create index tooth_conditions_patient_idx on public.tooth_conditions (patient_id);

create table public.treatment_plans (
  id          uuid primary key default gen_random_uuid(),
  patient_id  uuid not null references public.patients (id) on delete restrict,
  location_id uuid not null references public.locations (id) on delete restrict,
  status      text not null check (status in ('proposed', 'accepted', 'in_progress', 'completed', 'declined')),
  created_at  timestamptz not null default now(),
  unique (id, patient_id)
);
create index treatment_plans_patient_idx on public.treatment_plans (patient_id);

create table public.plan_phases (
  id         uuid primary key default gen_random_uuid(),
  plan_id    uuid not null,
  patient_id uuid not null,
  sequence   int not null check (sequence > 0),
  name       text not null,
  unique (plan_id, sequence),
  unique (id, patient_id),
  foreign key (plan_id, patient_id) references public.treatment_plans (id, patient_id) on delete restrict
);

-- A procedure is always a service the location offers, for the same patient as its visit and plan.
-- Fees are whole cents (money: line-by-line review).
create table public.dental_procedures (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references public.patients (id) on delete restrict,
  location_id     uuid not null,
  service_id      uuid not null,
  practitioner_id uuid references public.practitioners (id) on delete restrict,
  encounter_id    uuid,
  plan_phase_id   uuid,
  tooth           text check (tooth ~ '^([1-9]|[12][0-9]|3[0-2]|[A-T])$'),
  surface         text check (surface ~ '^[MODBLFI]{1,5}$'),
  status          text not null check (status in ('planned', 'completed')),
  fee_cents       integer not null check (fee_cents >= 0),
  performed_at    timestamptz,
  check ((status = 'completed') = (performed_at is not null)),
  foreign key (location_id, service_id) references public.location_services (location_id, service_id) on delete restrict,
  foreign key (encounter_id, patient_id) references public.encounters (id, patient_id) on delete restrict,
  foreign key (plan_phase_id, patient_id) references public.plan_phases (id, patient_id) on delete restrict
);
create index dental_procedures_patient_idx on public.dental_procedures (patient_id);

-- New plans may only use services the location still offers; completed history keeps old services.
create function private.check_procedure_service_active() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status = 'planned' and not exists (
       select 1 from public.location_services ls
        where ls.location_id = new.location_id and ls.service_id = new.service_id and ls.active) then
    raise exception 'the location does not currently offer this service' using errcode = 'check_violation';
  end if;
  return new;
end;
$$;
create trigger dental_procedures_check_service before insert or update of status, location_id, service_id
  on public.dental_procedures for each row execute function private.check_procedure_service_active();

------------------------------------------------------------------------------------------
-- The staff gate, in one place: an active profile, and for staff a verified second factor.
-- Every table's restrictive staff_need_mfa policy now calls this one function.
------------------------------------------------------------------------------------------

create function private.passes_staff_gate() returns boolean
language sql stable security definer set search_path = '' as $$
  select private.my_role() is not null and (not private.is_staff() or private.has_mfa())
$$;
grant execute on function private.passes_staff_gate() to authenticated;

------------------------------------------------------------------------------------------
-- Audit: for patient tables, record which columns changed, never the values (no patient data in logs).
------------------------------------------------------------------------------------------

create or replace function private.audit_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  r   jsonb := coalesce(to_jsonb(new), to_jsonb(old));
  o   jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  n   jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  pii boolean := tg_table_name in ('patients', 'encounters', 'tooth_conditions', 'treatment_plans', 'plan_phases', 'dental_procedures');
begin
  insert into public.audit_log (actor_id, actor_role, table_name, row_pk, action, old_row, new_row)
  values (
    auth.uid(),
    private.my_role(),
    tg_table_name,
    coalesce(r ->> 'id', concat_ws(':', r ->> 'location_id', r ->> 'service_id', r ->> 'profile_id')),
    tg_op,
    case when pii then null else o end,
    case when pii then jsonb_build_object('changed_columns',
           (select coalesce(jsonb_agg(k.key order by k.key), '[]'::jsonb)
              from jsonb_each(coalesce(n, o)) k
             where tg_op <> 'UPDATE' or k.value is distinct from (o -> k.key)))
         else n end
  );
  return null;
end;
$$;

------------------------------------------------------------------------------------------
-- Access
------------------------------------------------------------------------------------------

create function private.treated_by_me(pid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.my_role() = 'clinician'
     and exists (select 1 from public.encounters e
                  where e.patient_id = pid and e.practitioner_id = private.current_practitioner_id())
$$;

-- Staff at the location where a visit happened also see that patient (check-in and follow-up).
create function private.visited_my_location(pid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.encounters e
                  where e.patient_id = pid and e.location_id in (select private.my_location_ids()))
$$;

-- For tables that hold only patient_id: look up the patient's home location once.
create function private.can_see_patient(pid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_org_admin()
      or exists (select 1 from public.patients p
                  where p.id = pid and p.home_location_id in (select private.my_location_ids()))
      or private.visited_my_location(pid)
      or private.treated_by_me(pid)
$$;
grant execute on function private.treated_by_me(uuid), private.visited_my_location(uuid), private.can_see_patient(uuid) to authenticated;

grant select on public.patients, public.encounters, public.tooth_conditions, public.treatment_plans,
  public.plan_phases, public.dental_procedures to authenticated;
-- Front desk may set demographic details only; mrn is set once, system fields (is_canary, is_synthetic, created_at) never.
grant insert (mrn, given_name, family_name, preferred_name, date_of_birth, sex_at_birth, home_location_id,
              email, phone, preferred_language) on public.patients to authenticated;
grant update (given_name, family_name, preferred_name, date_of_birth, sex_at_birth, home_location_id,
              email, phone, preferred_language, deceased_at) on public.patients to authenticated;
grant insert, update on public.encounters, public.tooth_conditions, public.treatment_plans,
  public.plan_phases, public.dental_procedures to authenticated;

do $$
declare t text;
begin
  foreach t in array array['patients', 'encounters', 'tooth_conditions', 'treatment_plans', 'plan_phases', 'dental_procedures'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create trigger audit_row after insert or update or delete on public.%I
                    for each row execute function private.audit_row()', t);
  end loop;
  -- Replace every copy of the staff gate, old tables included, with the single function.
  for t in select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
            where n.nspname = 'public' and c.relkind = 'r' loop
    execute format('drop policy if exists staff_need_mfa on public.%I', t);
    execute format('create policy staff_need_mfa on public.%I as restrictive for all to authenticated
                    using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()))', t);
  end loop;
end;
$$;

create policy read_patients on public.patients for select to authenticated
  using ((select private.is_org_admin())
         or home_location_id in (select private.my_location_ids())
         or private.visited_my_location(id)
         or private.treated_by_me(id));
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
create policy read_plan_phases on public.plan_phases for select to authenticated using (private.can_see_patient(patient_id));
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
