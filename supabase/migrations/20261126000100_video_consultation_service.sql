-- Video consultation as a bookable service (section 11): CDT D9995, teledentistry in real time. Booked, held, paid
-- and cancelled like any visit; the app opens the Stream room for it, and only for the patient whose visit it is.
-- General dentistry may not exist yet on a fresh database (the seed adds the rest); the seed tolerates it.
insert into public.specialties (code, name) values ('general', 'General dentistry') on conflict (code) do nothing;

insert into public.services (code, name, duration_minutes, specialty_id, summary)
select 'D9995', 'Video consultation', 20, s.id,
       'Talk to a dentist on video from home: questions, a quick look at a concern, or what to book next.'
  from public.specialties s where s.code = 'general'
on conflict (code) do nothing;

insert into public.location_services (location_id, service_id, price_cents)
select l.id, s.id, 4500
  from public.locations l cross join public.services s
 where s.code = 'D9995'
on conflict (location_id, service_id) do nothing;
