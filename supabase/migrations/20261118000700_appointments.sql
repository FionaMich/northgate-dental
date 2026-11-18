-- Appointments, clinician leave, travel times between locations, and appointment history.
-- Row level security (Fiona reviews line by line): staff see appointments at their locations,
-- clinicians also see their own anywhere, org_admin sees all; patients see their own once linked (T2).
-- Front desk and managers book at their own locations; patients book through functions (T3). Nobody deletes.

create table public.location_travel (
  from_location uuid not null references public.locations (id) on delete restrict,
  to_location   uuid not null references public.locations (id) on delete restrict,
  minutes       int not null check (minutes > 0),
  primary key (from_location, to_location),
  check (from_location <> to_location)
);

create table public.availability_exceptions (
  id              uuid primary key default gen_random_uuid(),
  practitioner_id uuid not null references public.practitioners (id) on delete restrict,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  kind            text not null check (kind in ('leave', 'training', 'sick')),
  reason          text,
  check (ends_at > starts_at)
);
create index availability_exceptions_practitioner_idx on public.availability_exceptions (practitioner_id, starts_at);

-- Held, booked and arrived appointments block the clinician and the room; cancelled ones free them.
create table public.appointments (
  id              uuid primary key default gen_random_uuid(),
  patient_id      uuid not null references public.patients (id) on delete restrict,
  location_id     uuid not null,
  practitioner_id uuid not null references public.practitioners (id) on delete restrict,
  service_id      uuid not null,
  resource_id     uuid references public.resources (id) on delete restrict,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  status          text not null check (status in ('held', 'booked', 'arrived', 'completed', 'cancelled', 'no_show')),
  hold_expires_at timestamptz,
  booked_by       uuid,
  created_at      timestamptz not null default now(),
  check (ends_at > starts_at),
  check ((status = 'held') = (hold_expires_at is not null)),
  foreign key (location_id, service_id) references public.location_services (location_id, service_id) on delete restrict,
  exclude using gist (practitioner_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
    where (status in ('held', 'booked', 'arrived')),
  exclude using gist (resource_id with =, tstzrange(starts_at, ends_at, '[)') with &&)
    where (resource_id is not null and status in ('held', 'booked', 'arrived'))
);
create index appointments_patient_idx on public.appointments (patient_id);
create index appointments_location_start_idx on public.appointments (location_id, starts_at);

-- Every creation and status change, with who made it. Written by trigger only.
create table public.appointment_events (
  id             bigint generated always as identity primary key,
  appointment_id uuid not null references public.appointments (id) on delete restrict,
  occurred_at    timestamptz not null default now(),
  actor_id       uuid,
  from_status    text,
  to_status      text not null
);
create index appointment_events_appointment_idx on public.appointment_events (appointment_id);

create function private.record_appointment_event() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.appointment_events (appointment_id, actor_id, from_status, to_status)
    values (new.id, auth.uid(), case when tg_op = 'UPDATE' then old.status end, new.status);
  end if;
  return null;
end;
$$;
create trigger appointments_record_event after insert or update of status on public.appointments
  for each row execute function private.record_appointment_event();

-- Audit: any table holding a patient_id (or the patients table) records changed column names only,
-- never values, so new patient tables cannot leak details into the audit log by accident.
create or replace function private.audit_row() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  r   jsonb := coalesce(to_jsonb(new), to_jsonb(old));
  o   jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
  n   jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
  pii boolean := tg_table_name = 'patients' or r ? 'patient_id';
begin
  insert into public.audit_log (actor_id, actor_role, table_name, row_pk, action, old_row, new_row)
  values (
    auth.uid(),
    private.my_role(),
    tg_table_name,
    coalesce(r ->> 'id', concat_ws(':', r ->> 'location_id', r ->> 'service_id', r ->> 'profile_id', r ->> 'from_location', r ->> 'to_location')),
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

grant select on public.location_travel, public.availability_exceptions, public.appointments, public.appointment_events to authenticated;
grant insert, update on public.location_travel, public.availability_exceptions, public.appointments to authenticated;
grant delete on public.availability_exceptions to authenticated;

do $$
declare t text;
begin
  foreach t in array array['location_travel', 'availability_exceptions', 'appointments', 'appointment_events'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy staff_need_mfa on public.%I as restrictive for all to authenticated
                    using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()))', t);
    execute format('create trigger audit_row after insert or update or delete on public.%I
                    for each row execute function private.audit_row()', t);
  end loop;
end;
$$;

create policy read_location_travel on public.location_travel for select to authenticated
  using ((select private.my_role()) is not null);
create policy admin_writes_location_travel on public.location_travel for all to authenticated
  using ((select private.is_org_admin())) with check ((select private.is_org_admin()));

-- Leave: staff can see it; a clinician records their own; managers for clinicians working at their locations.
create policy read_availability_exceptions on public.availability_exceptions for select to authenticated
  using ((select private.is_staff()));
create policy manage_availability_exceptions on public.availability_exceptions for all to authenticated
  using ((select private.is_org_admin())
         or practitioner_id = (select private.current_practitioner_id())
         or exists (select 1 from public.practitioner_roles pr
                     where pr.practitioner_id = availability_exceptions.practitioner_id and private.manages(pr.location_id)))
  with check ((select private.is_org_admin())
         or practitioner_id = (select private.current_practitioner_id())
         or exists (select 1 from public.practitioner_roles pr
                     where pr.practitioner_id = availability_exceptions.practitioner_id and private.manages(pr.location_id)));

create policy read_appointments on public.appointments for select to authenticated
  using ((select private.is_org_admin())
         or location_id in (select private.my_location_ids())
         or practitioner_id = (select private.current_practitioner_id()));
create policy front_desk_books_appointments on public.appointments for all to authenticated
  using ((select private.is_org_admin())
         or ((select private.my_role()) in ('receptionist', 'location_manager') and location_id in (select private.my_location_ids())))
  with check ((select private.is_org_admin())
         or ((select private.my_role()) in ('receptionist', 'location_manager') and location_id in (select private.my_location_ids())));

create policy read_appointment_events on public.appointment_events for select to authenticated
  using (exists (select 1 from public.appointments a where a.id = appointment_id));  -- visible when the appointment is
