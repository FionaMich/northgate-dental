-- Patients choose their dentist (Fiona, 2026-11-21): a patient-facing profile for each practitioner (name, title,
-- focus, a short bio and a photo bundled in the app under assets/images/team/<photo_key>.jpg). The staff record's
-- display_name keeps its synthetic wording for the portal; patients only ever see public_name.
-- Row level security: Fiona reviews line by line.

alter table public.practitioners
  add column public_name text check (char_length(public_name) between 2 and 80),
  add column title       text check (char_length(title) <= 60),
  add column focus       text check (char_length(focus) <= 80),
  add column bio         text check (char_length(bio) <= 400),
  add column photo_key   text check (photo_key ~ '^[a-z0-9-]+$');

-- Verified patients (password plus emailed code) see active practitioners and where they work; nothing else changes.
create policy patient_reads_active_practitioners on public.practitioners for select to authenticated
  using (active and (select private.my_role()) = 'patient' and (select private.passes_patient_gate()));
create policy patient_reads_active_practitioner_roles on public.practitioner_roles for select to authenticated
  using ((select private.my_role()) = 'patient' and (select private.passes_patient_gate())
         and exists (select 1 from public.practitioners p where p.id = practitioner_roles.practitioner_id and p.active));

-- Existing rows (staging); fresh databases get the same text from seed.sql.
update public.practitioners set public_name = 'Dr Mei Chen', title = 'Orthodontist', focus = 'Braces and clear aligners', photo_key = 'mei-chen',
  bio = 'Mei straightens smiles for teenagers and adults, and plans every aligner case from a 3D scan so you can see the result before you start.'
 where display_name = 'Dr Mei Chen (synthetic orthodontist)';
update public.practitioners set public_name = 'Priya Raman, RDH', title = 'Dental hygienist', focus = 'Cleanings and gum health', photo_key = 'priya-raman',
  bio = 'Priya gives thorough, gentle cleanings and shows you the small changes at home that keep your gums healthy between visits.'
 where display_name = 'Synthetic Back Bay Hygienist';
update public.practitioners set public_name = 'Dr Samuel Okafor', title = 'Endodontist', focus = 'Root canal treatment', photo_key = 'samuel-okafor',
  bio = 'Samuel saves teeth with calm, unhurried root canal treatment, and explains every step so nothing comes as a surprise.'
 where display_name = 'Synthetic Endodontist';
update public.practitioners set public_name = 'Dr Laura Bennett', title = 'Oral surgeon', focus = 'Extractions and implants', photo_key = 'laura-bennett',
  bio = 'Laura looks after wisdom teeth, extractions and implants, planning each procedure with a 3D scan for a quicker recovery.'
 where display_name = 'Synthetic Oral Surgeon';
update public.practitioners set public_name = 'Dr Diego Alvarez', title = 'Children''s dentist', focus = 'Dental care for children', photo_key = 'diego-alvarez',
  bio = 'Diego makes the dentist a fun place for children, with check-ups, sealants and plenty of time for questions from parents.'
 where display_name = 'Synthetic Paediatric Dentist';
update public.practitioners set public_name = 'Dr Hannah Brooks', title = 'General dentist', focus = 'Check-ups, fillings and crowns', photo_key = 'hannah-brooks',
  bio = 'Hannah looks after the whole family, from check-ups to fillings and crowns, and believes in fixing small problems early.'
 where display_name = 'Synthetic Quincy Dentist';
