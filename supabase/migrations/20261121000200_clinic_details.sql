-- Clinic pages in the patient app (Fiona, 2026-11-21): a phone number to call and a photo key (the photo is
-- bundled in the app). Numbers are in the fictional 555-01xx range, like every other number in this project.
alter table public.locations
  add column phone     text check (phone ~ '^\+1[2-9][0-9]{2}55501[0-9]{2}$'),
  add column photo_key text check (photo_key ~ '^[a-z0-9-]+$');

-- Existing rows (staging); fresh databases get the same values from seed.sql.
update public.locations set phone = '+16175550110', photo_key = 'back-bay'  where code = 'back-bay';
update public.locations set phone = '+16175550120', photo_key = 'cambridge' where code = 'cambridge';
update public.locations set phone = '+16175550130', photo_key = 'quincy'    where code = 'quincy';
