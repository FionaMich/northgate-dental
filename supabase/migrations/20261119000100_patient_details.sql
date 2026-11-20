-- Patients choose their preferred clinic and give their home address in the app (section 05).
-- The preferred clinic is the existing home location, so staff visibility follows the patient's choice.
-- Row level security and a new patient write path: Fiona reviews line by line.

alter table public.patients
  add column address_line1        text check (char_length(address_line1) between 1 and 120),
  add column address_line2        text check (char_length(address_line2) between 1 and 120),
  add column city                 text check (char_length(city) between 1 and 80),
  add column state                text check (state ~ '^[A-Z]{2}$'),
  add column postal_code          text check (postal_code ~ '^[0-9]{5}(-[0-9]{4})?$'),
  add column details_confirmed_at timestamptz,
  -- A usable address or none: a second line needs a first, and the four main parts come together.
  add constraint patients_address_complete check (
    num_nulls(address_line1, city, state, postal_code) in (0, 4)
    and (address_line2 is null or address_line1 is not null));

-- Front desk may set the address too; their existing policy still limits which rows.
grant insert (address_line1, address_line2, city, state, postal_code) on public.patients to authenticated;
grant update (address_line1, address_line2, city, state, postal_code) on public.patients to authenticated;

-- The only way a patient (or a parent, for a child) writes to a patient record. Patients have no update
-- policy on patients, so a direct update changes nothing. The audit trigger records the changed columns.
create function public.update_my_details(
  patient uuid, location uuid, line1 text, line2 text, town text, region text, zip text
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if patient is null or patient not in (select private.my_patient_ids()) then
    raise exception 'not allowed to change this record' using errcode = 'insufficient_privilege';
  end if;
  if not exists (select 1 from public.locations l where l.id = location and l.active) then
    raise exception 'choose one of our open clinics' using errcode = 'invalid_parameter_value';
  end if;
  update public.patients
     set home_location_id     = location,
         address_line1        = nullif(trim(line1), ''),
         address_line2        = nullif(trim(line2), ''),
         city                 = nullif(trim(town), ''),
         state                = upper(nullif(trim(region), '')),
         postal_code          = nullif(trim(zip), ''),
         details_confirmed_at = now()
   where id = patient;
end;
$$;
revoke execute on function public.update_my_details(uuid, uuid, text, text, text, text, text) from public, anon;
grant execute on function public.update_my_details(uuid, uuid, text, text, text, text, text) to authenticated;
