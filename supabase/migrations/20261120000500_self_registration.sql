-- New patients register themselves in the app; the front-desk code is no longer offered (Fiona, 2026-11-20).
-- Existing patients link with email plus date of birth (link_by_birth_date); everyone else registers here.
-- Rules: a verified session (password plus emailed code), adults only (children are added by a parent at the
-- practice), one record per account, and no second record for an email that is already on one.
-- The clinic starts as the first open clinic; the next app screen asks the patient to choose (details step).
-- Row level security and a new patient write path: Fiona reviews line by line.

create sequence private.app_mrn start 9000001 maxvalue 9999999 no cycle;  -- NG9xxxxxx; the generator uses the low range

create function public.register_new_patient(given text, family text, birth_date date, sex text) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  me     uuid := auth.uid();
  mail   text;
  clinic uuid;
  new_id uuid;
begin
  if private.my_role() is distinct from 'patient' or not private.passes_patient_gate() then
    raise exception 'enter the code from your email first' using errcode = 'insufficient_privilege';
  end if;
  if exists (select 1 from public.patient_links l where l.profile_id = me) then
    raise exception 'this account already has a record' using errcode = 'invalid_parameter_value';
  end if;
  given := nullif(trim(given), '');
  family := nullif(trim(family), '');
  if given is null or family is null or char_length(given) > 80 or char_length(family) > 80 then
    raise exception 'enter your first and last name' using errcode = 'invalid_parameter_value';
  end if;
  if sex is null or sex not in ('female', 'male', 'unknown') then
    raise exception 'choose an option for sex at birth' using errcode = 'invalid_parameter_value';
  end if;
  if birth_date is null or birth_date < '1900-01-01' or birth_date + interval '18 years' > current_date then
    raise exception 'patients under 18 are registered by a parent at the practice' using errcode = 'invalid_parameter_value';
  end if;

  select lower(u.email) into mail from auth.users u where u.id = me;
  if exists (select 1 from public.patients p where lower(p.email) = mail) then
    raise exception 'a record already uses this email: confirm your date of birth instead' using errcode = 'invalid_parameter_value';
  end if;

  select l.id into clinic from public.locations l where l.active order by l.name limit 1;
  insert into public.patients (mrn, given_name, family_name, date_of_birth, sex_at_birth, home_location_id, email)
  values ('NG' || nextval('private.app_mrn'), given, family, birth_date, sex, clinic,
          case when mail ~ '^[a-z0-9._-]+@([a-z0-9-]+\.)*synthetic$' then mail end)   -- the table accepts synthetic emails only
  returning id into new_id;
  insert into public.patient_links (profile_id, patient_id) values (me, new_id);  -- both rows audited by their triggers
  return new_id;
end;
$$;
revoke execute on function public.register_new_patient(text, text, date, text) from public, anon;
grant execute on function public.register_new_patient(text, text, date, text) to authenticated;
