-- Section 07 T2: what the notification worker may know about a visit, and where messages that keep failing go.
-- Line-by-line review (Fiona): this decides what a patient message can contain and where it is sent.

select pgmq.create('dead_letter'); -- messages that failed five times; an alert fires when it is not empty (section 12)

-- The minimum a confirmation or reminder needs: first name, sign-in email, language, time, clinic and service.
-- Never the surname, date of birth, record number, address, insurance or anything clinical. The email is the patient's
-- own app sign-in (profiles are auth users); records without a linked sign-in get no email, because the addresses
-- stored on synthetic records (.synthetic) cannot receive mail.
create function private.notification_context(appointment uuid)
returns table (
  patient_id   uuid,
  first_name   text,
  email        text,
  language     text,
  starts_at    timestamptz,
  time_zone    text,
  clinic_name  text,
  clinic_phone text,
  service_name text,
  status       text
)
language sql stable security definer set search_path = '' as $$
  select p.id, coalesce(p.preferred_name, p.given_name), u.email::text, p.preferred_language,
         a.starts_at, l.time_zone, l.name, l.phone, s.name, a.status
  from public.appointments a
  join public.patients p on p.id = a.patient_id
  join public.locations l on l.id = a.location_id
  join public.services s on s.id = a.service_id
  left join public.patient_links pl on pl.patient_id = p.id
  left join auth.users u on u.id = pl.profile_id
  where a.id = notification_context.appointment
$$;
revoke all on function private.notification_context(uuid) from public;
grant execute on function private.notification_context(uuid) to northgate_worker;
