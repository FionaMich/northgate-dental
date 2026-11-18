-- Slots and self-booking for patients.
-- Slots come from each clinician's weekly template, in the location's local time, on a 30-minute grid,
-- minus booked or held time, leave, closures, and (for services that need it) a free room or machine.
-- A patient holds a slot for 10 minutes, then confirms it; a new hold releases their earlier one.
-- Patient identity always comes from the session (private.my_patient_ids), never from the caller's word alone.
-- Fiona reviews these functions line by line (they write appointments for patients).

alter table public.services add column self_bookable boolean not null default true;
update public.services set self_bookable = false where code = 'D9110';   -- emergencies go through the practice

-- Which clinicians may do a service: same specialty, or general and hygiene work done by
-- general dentists, paediatric dentists and endodontists (as the practices work today).
create function private.can_perform(role_specialty uuid, service_specialty uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select role_specialty = service_specialty
      or (exists (select 1 from public.specialties s where s.id = service_specialty and s.code in ('general', 'hygiene'))
          and exists (select 1 from public.specialties s where s.id = role_specialty and s.code in ('general', 'paediatric', 'endodontics')))
$$;

create function public.available_slots(loc uuid, service uuid, from_day date default current_date, days int default 14)
returns table (practitioner_id uuid, starts_at timestamptz, ends_at timestamptz, resource_id uuid)
language sql stable security definer set search_path = '' as $$
  with svc as (
    select s.id, s.duration_minutes * interval '1 minute' as len, s.requires_resource, s.specialty_id
      from public.services s
      join public.location_services ls on ls.service_id = s.id and ls.location_id = loc and ls.active
     where s.id = service and s.active and (s.self_bookable or private.is_staff()) and private.passes_staff_gate()
  ),
  place as (select l.time_zone from public.locations l where l.id = loc and l.active),
  shifts as (
    select pr.practitioner_id,
           (d::date + (w ->> 0)::time) at time zone place.time_zone as opens,
           (d::date + (w ->> 1)::time) at time zone place.time_zone as closes
      from svc, place,
           generate_series(from_day::timestamp, (from_day + least(greatest(days, 1), 60) - 1)::timestamp, interval '1 day') d,
           public.practitioner_roles pr,
           jsonb_array_elements(pr.weekly_template -> lower(to_char(d, 'dy'))) w
     where pr.location_id = loc and private.can_perform(pr.specialty_id, svc.specialty_id)
  ),
  starts as (
    select distinct sh.practitioner_id, g as starts_at, g + svc.len as ends_at
      from shifts sh, svc, generate_series(sh.opens, sh.closes - svc.len, interval '30 minutes') g
     where g > now()
  )
  select c.practitioner_id, c.starts_at, c.ends_at, r.id
    from starts c cross join svc
    left join lateral (
      select res.id from public.resources res
       where res.location_id = loc and res.kind = svc.requires_resource
         and not exists (select 1 from public.appointments a
                          where a.resource_id = res.id and a.status in ('held', 'booked', 'arrived')
                            and (a.status <> 'held' or a.hold_expires_at > now())
                            and tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)'))
       order by res.id limit 1) r on true
   where (svc.requires_resource is null or r.id is not null)
     and not exists (select 1 from public.appointments a
                      where a.practitioner_id = c.practitioner_id and a.status in ('held', 'booked', 'arrived')
                        and (a.status <> 'held' or a.hold_expires_at > now())
                        and tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)'))
     and not exists (select 1 from public.availability_exceptions x
                      where x.practitioner_id = c.practitioner_id
                        and tstzrange(x.starts_at, x.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)'))
     and not exists (select 1 from public.location_closures lc
                      where lc.location_id = loc
                        and tstzrange(lc.starts_at, lc.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)'))
   order by c.starts_at, c.practitioner_id
$$;

-- Holds past their 10 minutes are cancelled. Called before every new hold; a schedule calls it too (section 07).
create function public.release_expired_holds() returns int
language sql security definer set search_path = '' as $$
  with released as (
    update public.appointments a set status = 'cancelled', hold_expires_at = null
     where a.status = 'held' and a.hold_expires_at <= now()
    returning 1)
  select count(*)::int from released
$$;

create function public.hold_slot(loc uuid, service uuid, practitioner uuid, starts timestamptz, patient uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare
  mine uuid[] := array(select private.my_patient_ids());
  tz   text;
  slot record;
  new_id uuid;
begin
  if private.my_role() is distinct from 'patient' then
    raise exception 'only patient accounts book online' using errcode = 'insufficient_privilege';
  end if;
  patient := coalesce(patient, case when cardinality(mine) = 1 then mine[1] end);
  if patient is null or not patient = any (mine) then
    raise exception 'this sign-in is not linked to that patient' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.services s where s.id = service and s.self_bookable) then
    raise exception 'please call the practice to book this' using errcode = 'insufficient_privilege';
  end if;

  perform public.release_expired_holds();
  update public.appointments a set status = 'cancelled', hold_expires_at = null
   where a.booked_by = auth.uid() and a.status = 'held';

  select l.time_zone into tz from public.locations l where l.id = loc;
  select * into slot from public.available_slots(loc, service, (starts at time zone tz)::date, 1) s
   where s.practitioner_id = practitioner and s.starts_at = starts;
  if not found then
    raise exception 'this time is no longer available' using errcode = 'exclusion_violation';
  end if;

  insert into public.appointments (patient_id, location_id, practitioner_id, service_id, resource_id,
                                   starts_at, ends_at, status, hold_expires_at, booked_by)
  values (patient, loc, practitioner, service, slot.resource_id,
          slot.starts_at, slot.ends_at, 'held', now() + interval '10 minutes', auth.uid())
  returning appointments.id into new_id;
  return new_id;
end;
$$;

create function public.confirm_booking(appointment uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.appointments a set status = 'booked', hold_expires_at = null
   where a.id = appointment and a.status = 'held' and a.hold_expires_at > now()
     and a.booked_by = auth.uid() and a.patient_id in (select private.my_patient_ids());
  if not found then
    raise exception 'this hold has expired or is not yours' using errcode = 'invalid_parameter_value';
  end if;
end;
$$;

create function public.cancel_appointment(appointment uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.appointments a set status = 'cancelled', hold_expires_at = null
   where a.id = appointment and a.status in ('held', 'booked') and a.starts_at > now()
     and a.patient_id in (select private.my_patient_ids());
  if not found then
    raise exception 'this appointment cannot be cancelled online' using errcode = 'invalid_parameter_value';
  end if;
end;
$$;

grant execute on function public.available_slots(uuid, uuid, date, int),
  public.hold_slot(uuid, uuid, uuid, timestamptz, uuid),
  public.confirm_booking(uuid), public.cancel_appointment(uuid) to authenticated;
