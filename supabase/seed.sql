-- Synthetic seed data for local development and tests. Describes no real person or practice.
-- Locations, hours and rooms follow the fictional Northgate Dental group. Prices are synthetic, in whole cents.

insert into public.organisation (name, is_synthetic) values ('Northgate Dental (synthetic)', true);
insert into public.org_settings (settings) values
  ('{"language": "en", "cancellation_hours": 24, "missed_appointment_fee_cents": 5000, "synthetic": true}');

insert into public.locations (code, name, address_line, city, state, postal_code, time_zone) values
  ('back-bay',  'Back Bay (synthetic)',  '1 Example Street',   'Boston',    'MA', '02116', 'America/New_York'),
  ('cambridge', 'Cambridge (synthetic)', '2 Example Avenue',   'Cambridge', 'MA', '02139', 'America/New_York'),
  ('quincy',    'Quincy (synthetic)',    '3 Example Road',     'Quincy',    'MA', '02169', 'America/New_York');
update public.locations set phone = '+16175550110', photo_key = 'back-bay'  where code = 'back-bay';
update public.locations set phone = '+16175550120', photo_key = 'cambridge' where code = 'cambridge';
update public.locations set phone = '+16175550130', photo_key = 'quincy'    where code = 'quincy';

-- Quincy takes MassHealth Dental: no missed-appointment fee there.
insert into public.location_settings (location_id, overrides)
select id, '{"missed_appointment_fee_cents": 0}' from public.locations where code = 'quincy';

-- Opening hours (weekday 1 is Monday), local time.
insert into public.location_hours (location_id, weekday, opens, closes)
select l.id, d, h.opens, h.closes
from public.locations l
join (values
  ('back-bay',  1, 5, '08:00'::time, '18:00'::time), ('back-bay',  6, 6, '09:00', '14:00'),
  ('cambridge', 1, 5, '09:00',       '17:00'),       ('cambridge', 6, 6, '09:00', '16:00'),
  ('quincy',    1, 6, '07:00',       '20:00')
) as h(code, first_day, last_day, opens, closes) on h.code = l.code
cross join lateral generate_series(h.first_day, h.last_day) as d;

-- Rooms and equipment.
insert into public.resources (location_id, kind, name)
select l.id, r.kind::public.resource_kind, r.name
from public.locations l
join (values
  ('back-bay', 'operatory', 'Operatory 1'), ('back-bay', 'operatory', 'Operatory 2'),
  ('back-bay', 'operatory', 'Operatory 3'), ('back-bay', 'operatory', 'Operatory 4'),
  ('back-bay', 'cbct_scanner', 'Cone beam CT'),
  ('cambridge', 'operatory', 'Operatory 1'), ('cambridge', 'operatory', 'Operatory 2'), ('cambridge', 'operatory', 'Operatory 3'),
  ('quincy', 'operatory', 'Operatory 1'), ('quincy', 'operatory', 'Operatory 2')
) as r(code, kind, name) on r.code = l.code;

insert into public.specialties (code, name) values
  ('general', 'General dentistry'), ('hygiene', 'Dental hygiene'), ('oral-surgery', 'Oral surgery'),
  ('endodontics', 'Endodontics'), ('orthodontics', 'Orthodontics'), ('paediatric', 'Paediatric dentistry');

insert into public.services (code, name, duration_minutes, specialty_id, requires_resource)
select v.code, v.name, v.minutes, s.id, v.resource::public.resource_kind
from (values
  ('D0150', 'Comprehensive oral exam',         60,  'general',      null),
  ('D1110', 'Adult cleaning',                  60,  'hygiene',      null),
  ('D1120', 'Child cleaning',                  45,  'paediatric',   null),
  ('D2391', 'Composite filling, one surface',  60,  'general',      null),
  ('D7140', 'Simple extraction',               45,  'general',      null),
  ('D3330', 'Root canal, molar',               90,  'endodontics',  null),
  ('D6010', 'Implant placement',               120, 'oral-surgery', 'cbct_scanner'),
  ('D8090', 'Comprehensive orthodontics (clear aligners)', 60, 'orthodontics', null),
  ('D9972', 'Whitening',                       60,  'general',      null),
  ('D5110', 'Complete upper denture',          60,  'general',      null),
  ('D9110', 'Emergency palliative treatment',  30,  'general',      null)
) as v(code, name, minutes, specialty, resource)
join public.specialties s on s.code = v.specialty;
update public.services set self_bookable = false where code = 'D9110';   -- emergencies are booked by the practice

-- What each service is, in plain words, for patients choosing what to book.
update public.services set summary = 'A full check of your teeth, gums and bite, with X-rays if needed, and a plan for anything we find.' where code = 'D0150';
update public.services set summary = 'A hygienist removes plaque and tartar, polishes your teeth and shows you what to focus on at home.' where code = 'D1110';
update public.services set summary = 'A gentle clean and polish for children, with tips for brushing and a check on growing teeth.' where code = 'D1120';
update public.services set summary = 'A tooth-coloured filling that repairs a small cavity on one side of a tooth, usually in one visit.' where code = 'D2391';
update public.services set summary = 'Removing a tooth that can be lifted out simply, with numbing so you feel pressure, not pain.' where code = 'D7140';
update public.services set summary = 'Treats infection inside a back tooth and seals it, so you can keep the tooth instead of losing it.' where code = 'D3330';
update public.services set summary = 'Placing a titanium post to replace a missing tooth root, planned with a 3D scan first.' where code = 'D6010';
update public.services set summary = 'Straightening your teeth with clear, removable aligners, worn about 22 hours a day.' where code = 'D8090';
update public.services set summary = 'Brightening the colour of your teeth safely in the clinic, after a quick check that it suits you.' where code = 'D9972';
update public.services set summary = 'A full removable set of upper teeth, made to fit your mouth over a few fittings.' where code = 'D5110';
update public.services set summary = 'Quick relief for dental pain or injury. Call us and we will see you as soon as we can.' where code = 'D9110';

-- Prices per location, in whole cents (12000 is $120.00). Synthetic; Fiona reviews these line by line.
insert into public.location_services (location_id, service_id, price_cents)
select l.id, s.id, p.price_cents
from (values
  ('back-bay',  'D0150', 15000), ('back-bay',  'D1110', 13000), ('back-bay',  'D2391', 21000),
  ('back-bay',  'D7140', 22000), ('back-bay',  'D3330', 125000), ('back-bay', 'D6010', 320000),
  ('back-bay',  'D8090', 550000), ('back-bay', 'D9110', 18000),
  ('cambridge', 'D0150', 14000), ('cambridge', 'D1110', 12000), ('cambridge', 'D1120', 9000),
  ('cambridge', 'D2391', 20000), ('cambridge', 'D8090', 520000), ('cambridge', 'D9972', 45000),
  ('quincy',    'D0150', 12000), ('quincy',    'D1110', 11000), ('quincy',    'D2391', 18000),
  ('quincy',    'D7140', 19000), ('quincy',    'D5110', 160000), ('quincy',   'D9110', 15000)
) as p(location, service, price_cents)
join public.locations l on l.code = p.location
join public.services s on s.code = p.service;

-- Synthetic sign-ins, one or more per role. No passwords: sign-in is set up in section 05.
insert into auth.users (id, email, aud, role) values
  ('10000000-0000-4000-8000-000000000001', 'admin@northgate.synthetic',               'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000002', 'backbay.reception@northgate.synthetic',   'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000003', 'cambridge.reception@northgate.synthetic', 'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000004', 'quincy.reception@northgate.synthetic',    'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000005', 'backbay.manager@northgate.synthetic',     'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000006', 'cambridge.manager@northgate.synthetic',   'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000007', 'quincy.manager@northgate.synthetic',      'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000008', 'oral.surgeon@northgate.synthetic',        'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000009', 'endodontist@northgate.synthetic',         'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000010', 'backbay.hygienist@northgate.synthetic',   'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000011', 'orthodontist@northgate.synthetic',        'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000012', 'paediatric.dentist@northgate.synthetic',  'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000013', 'quincy.dentist@northgate.synthetic',      'authenticated', 'authenticated'),
  ('10000000-0000-4000-8000-000000000014', 'patient@northgate.synthetic',             'authenticated', 'authenticated');

insert into public.profiles (id, role, display_name) values
  ('10000000-0000-4000-8000-000000000001', 'org_admin',        'Synthetic Admin'),
  ('10000000-0000-4000-8000-000000000002', 'receptionist',     'Synthetic Back Bay Receptionist'),
  ('10000000-0000-4000-8000-000000000003', 'receptionist',     'Synthetic Cambridge Receptionist'),
  ('10000000-0000-4000-8000-000000000004', 'receptionist',     'Synthetic Quincy Receptionist'),
  ('10000000-0000-4000-8000-000000000005', 'location_manager', 'Synthetic Back Bay Manager'),
  ('10000000-0000-4000-8000-000000000006', 'location_manager', 'Synthetic Cambridge Manager'),
  ('10000000-0000-4000-8000-000000000007', 'location_manager', 'Synthetic Quincy Manager'),
  ('10000000-0000-4000-8000-000000000008', 'clinician',        'Synthetic Oral Surgeon'),
  ('10000000-0000-4000-8000-000000000009', 'clinician',        'Synthetic Endodontist'),
  ('10000000-0000-4000-8000-000000000010', 'clinician',        'Synthetic Back Bay Hygienist'),
  ('10000000-0000-4000-8000-000000000011', 'clinician',        'Dr Mei Chen (synthetic orthodontist)'),
  ('10000000-0000-4000-8000-000000000012', 'clinician',        'Synthetic Paediatric Dentist'),
  ('10000000-0000-4000-8000-000000000013', 'clinician',        'Synthetic Quincy Dentist'),
  ('10000000-0000-4000-8000-000000000014', 'patient',          'Synthetic Patient')
on conflict (id) do update set role = excluded.role, display_name = excluded.display_name;

insert into public.staff_locations (profile_id, location_id)
select p.id::uuid, l.id
from (values
  ('10000000-0000-4000-8000-000000000002', 'back-bay'), ('10000000-0000-4000-8000-000000000003', 'cambridge'),
  ('10000000-0000-4000-8000-000000000004', 'quincy'),   ('10000000-0000-4000-8000-000000000005', 'back-bay'),
  ('10000000-0000-4000-8000-000000000006', 'cambridge'), ('10000000-0000-4000-8000-000000000007', 'quincy'),
  ('10000000-0000-4000-8000-000000000008', 'back-bay'), ('10000000-0000-4000-8000-000000000009', 'back-bay'),
  ('10000000-0000-4000-8000-000000000010', 'back-bay'), ('10000000-0000-4000-8000-000000000011', 'cambridge'),
  ('10000000-0000-4000-8000-000000000011', 'back-bay'), ('10000000-0000-4000-8000-000000000012', 'cambridge'),
  ('10000000-0000-4000-8000-000000000013', 'quincy')
) as p(id, code)
join public.locations l on l.code = p.code;

insert into public.practitioners (profile_id, display_name)
select id, display_name from public.profiles where role = 'clinician';

-- What patients see: a name, title, focus, bio and photo (assets/images/team in the app).
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

-- Where and as what each clinician works. The orthodontist works at Cambridge and, on Tuesdays, at Back Bay.
insert into public.practitioner_roles (practitioner_id, location_id, specialty_id, weekly_template)
select pr.id, l.id, s.id, r.template::jsonb
from (values
  ('Synthetic Oral Surgeon',       'back-bay',  'oral-surgery', '{"mon": [["08:00","18:00"]], "wed": [["08:00","18:00"]], "fri": [["08:00","18:00"]]}'),
  ('Synthetic Endodontist',        'back-bay',  'endodontics',  '{"mon": [["08:00","18:00"]], "thu": [["08:00","18:00"]]}'),
  ('Synthetic Back Bay Hygienist', 'back-bay',  'hygiene',      '{"mon": [["08:00","18:00"]], "tue": [["08:00","18:00"]], "wed": [["08:00","18:00"]], "thu": [["08:00","18:00"]], "fri": [["08:00","18:00"]]}'),
  ('Dr Mei Chen (synthetic orthodontist)',       'cambridge', 'orthodontics', '{"mon": [["09:00","17:00"]], "wed": [["09:00","17:00"]], "thu": [["09:00","17:00"]], "fri": [["09:00","17:00"]], "sat": [["09:00","16:00"]]}'),
  ('Dr Mei Chen (synthetic orthodontist)',       'back-bay',  'orthodontics', '{"tue": [["08:00","18:00"]]}'),
  ('Synthetic Paediatric Dentist', 'cambridge', 'paediatric',   '{"mon": [["09:00","17:00"]], "tue": [["09:00","17:00"]], "wed": [["09:00","17:00"]], "thu": [["09:00","17:00"]]}'),
  ('Synthetic Quincy Dentist',     'quincy',    'general',      '{"mon": [["07:00","15:00"]], "tue": [["07:00","15:00"]], "wed": [["12:00","20:00"]], "thu": [["12:00","20:00"]], "sat": [["07:00","15:00"]]}')
) as r(name, code, specialty, template)
join public.practitioners pr on pr.display_name = r.name
join public.locations l on l.code = r.code
join public.specialties s on s.code = r.specialty;
