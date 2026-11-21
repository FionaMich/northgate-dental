-- Section 07 T4: the receptionist's task inbox, and W22, the schedule conflict scanner.
--
-- staff_tasks is the one inbox the portal (section 08) shows: schedule conflicts, check-ins that need a clinician
-- and balances that need billing follow-up all land here, each pointing at an appointment by ID.
-- detect_schedule_conflicts() finds visits that can no longer happen as booked; scan_schedule_conflicts() records
-- each one once and opens a task, closes conflicts that have gone away, and runs every 15 minutes and after every
-- change to leave or closures. Nothing is sent to a patient from here: a person decides (blueprint: approval first).

create table public.staff_tasks (
  id             uuid primary key default gen_random_uuid(),
  kind           text not null check (kind in ('schedule_conflict', 'checkin_follow_up', 'billing_follow_up')),
  appointment_id uuid not null references public.appointments (id) on delete cascade,
  location_id    uuid not null references public.locations (id) on delete restrict,
  reference_id   uuid,                         -- the conflict, check-in or payment behind the task
  priority       text not null default 'normal' check (priority in ('urgent', 'high', 'normal')),
  created_at     timestamptz not null default now(),
  done_at        timestamptz,
  done_by        uuid references public.profiles (id) on delete set null,
  unique (kind, reference_id)
);
create index staff_tasks_open_idx on public.staff_tasks (location_id, created_at) where done_at is null;

alter table public.staff_tasks enable row level security;
create trigger audit_row after insert or update or delete on public.staff_tasks
  for each row execute function private.audit_row();
create policy staff_need_mfa on public.staff_tasks as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
revoke all on public.staff_tasks from anon, authenticated;
grant select, update (done_at, done_by) on public.staff_tasks to authenticated;
-- Staff see and close the tasks of the locations they work at; patients see none.
create policy staff_reads_tasks on public.staff_tasks for select to authenticated
  using (private.is_staff() and (private.is_org_admin() or location_id in (select private.my_location_ids())));
create policy staff_closes_tasks on public.staff_tasks for update to authenticated
  using (private.is_staff() and (private.is_org_admin() or location_id in (select private.my_location_ids())))
  with check (done_by = auth.uid());

create table public.schedule_conflicts (
  id             uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments (id) on delete cascade,
  conflict_type  text not null check (conflict_type in ('clinician_unavailable', 'location_closed', 'travel_time', 'patient_overlap')),
  severity       text not null check (severity in ('high', 'medium')),
  detail         text not null,                 -- the reason, never patient details
  found_at       timestamptz not null default now(),
  resolved_at    timestamptz,
  unique (appointment_id, conflict_type)        -- the same conflict is never raised twice
);
alter table public.schedule_conflicts enable row level security;
create trigger audit_row after insert or update or delete on public.schedule_conflicts
  for each row execute function private.audit_row();
create policy staff_need_mfa on public.schedule_conflicts as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
revoke all on public.schedule_conflicts from anon, authenticated;
grant select on public.schedule_conflicts to authenticated;
create policy staff_reads_conflicts on public.schedule_conflicts for select to authenticated
  using (private.is_staff() and exists (
    select 1 from public.appointments a where a.id = appointment_id
       and (private.is_org_admin() or a.location_id in (select private.my_location_ids()))));

-- Every conflict between p_from and p_to: one row per appointment and conflict type.
create function private.detect_schedule_conflicts(p_from timestamptz, p_to timestamptz)
returns table (conflict_type text, appointment_id uuid, severity text, detail text)
language sql stable security definer set search_path = '' as $$
  -- booked while the clinician is on leave, training or off sick
  select distinct on (a.id) 'clinician_unavailable', a.id, 'high', 'Clinician unavailable: ' || x.kind
  from public.appointments a
  join public.availability_exceptions x on x.practitioner_id = a.practitioner_id
   and tstzrange(x.starts_at, x.ends_at) && tstzrange(a.starts_at, a.ends_at)
  where a.status in ('held', 'booked') and a.starts_at >= p_from and a.starts_at < p_to
  union all
  -- the clinic is closed at that time
  select distinct on (a.id) 'location_closed', a.id, 'high', 'Location closed: ' || c.reason
  from public.appointments a
  join public.location_closures c on c.location_id = a.location_id
   and tstzrange(c.starts_at, c.ends_at) && tstzrange(a.starts_at, a.ends_at)
  where a.status in ('held', 'booked') and a.starts_at >= p_from and a.starts_at < p_to
  union all
  -- the clinician cannot get from the previous visit's location in time
  select distinct on (b.id) 'travel_time', b.id, 'medium', 'Less than ' || t.minutes || ' minutes to travel from the previous visit'
  from public.appointments a
  join public.appointments b on b.practitioner_id = a.practitioner_id and b.location_id <> a.location_id
   and b.starts_at >= a.ends_at
  join public.location_travel t on t.from_location = a.location_id and t.to_location = b.location_id
   and b.starts_at < a.ends_at + t.minutes * interval '1 minute'
  where a.status = 'booked' and b.status = 'booked' and b.starts_at >= p_from and b.starts_at < p_to
  union all
  -- the same patient booked within 30 minutes of another visit
  select distinct on (b.id) 'patient_overlap', b.id, 'medium', 'Within 30 minutes of another visit for the same patient'
  from public.appointments a
  join public.appointments b on b.patient_id = a.patient_id and b.id <> a.id and b.starts_at >= a.starts_at
   and tstzrange(a.starts_at, a.ends_at + interval '30 minutes') && tstzrange(b.starts_at, b.ends_at)
  where a.status = 'booked' and b.status = 'booked' and b.starts_at >= p_from and b.starts_at < p_to
$$;

-- W22: record new conflicts once (with a task), close the ones that no longer apply. Returns how many are new.
create function private.scan_schedule_conflicts(p_from timestamptz default now(), p_to timestamptz default now() + interval '30 days')
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  added integer;
begin
  with detected as (select * from private.detect_schedule_conflicts(p_from, p_to)),
  ins as (
    insert into public.schedule_conflicts (appointment_id, conflict_type, severity, detail)
    select d.appointment_id, d.conflict_type, d.severity, d.detail from detected d
    on conflict (appointment_id, conflict_type) do update
      set resolved_at = null, detail = excluded.detail, found_at = case when schedule_conflicts.resolved_at is null
                                                                     then schedule_conflicts.found_at else now() end
      where schedule_conflicts.resolved_at is not null or schedule_conflicts.detail <> excluded.detail
    returning id, appointment_id, severity, (xmax = 0) as is_new
  ),
  tasks as (
    insert into public.staff_tasks (kind, appointment_id, location_id, reference_id, priority)
    select 'schedule_conflict', i.appointment_id, a.location_id, i.id, case i.severity when 'high' then 'high' else 'normal' end
      from ins i join public.appointments a on a.id = i.appointment_id
    on conflict (kind, reference_id) do update set done_at = null, done_by = null
    returning 1
  )
  select count(*) filter (where is_new) into added from ins;  -- tasks runs too: data-changing CTEs always run

  -- Conflicts in the window that were not found again have been fixed (leave cancelled, visit moved or cancelled).
  update public.schedule_conflicts sc set resolved_at = now()
    from public.appointments a
   where a.id = sc.appointment_id and sc.resolved_at is null
     and a.starts_at >= p_from and a.starts_at < p_to
     and not exists (select 1 from private.detect_schedule_conflicts(p_from, p_to) d
                      where d.appointment_id = sc.appointment_id and d.conflict_type = sc.conflict_type);
  update public.staff_tasks t set done_at = now()
    from public.schedule_conflicts sc
   where t.kind = 'schedule_conflict' and t.reference_id = sc.id and t.done_at is null and sc.resolved_at is not null;

  return coalesce(added, 0);
end;
$$;
revoke all on function private.detect_schedule_conflicts(timestamptz, timestamptz),
  private.scan_schedule_conflicts(timestamptz, timestamptz) from public;

-- On every change to leave or closures, so new conflicts show within seconds, not at the next scan.
create function private.rescan_after_change() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.scan_schedule_conflicts();
  return null;
end;
$$;
create trigger rescan_conflicts after insert or update or delete on public.availability_exceptions
  for each statement execute function private.rescan_after_change();
create trigger rescan_conflicts after insert or update or delete on public.location_closures
  for each statement execute function private.rescan_after_change();

-- And every 15 minutes over the next 30 days, as a safety net for changes no trigger sees (bookings, travel times).
select cron.schedule('conflict-scanner', '*/15 * * * *', $$ select private.scan_schedule_conflicts() $$);
