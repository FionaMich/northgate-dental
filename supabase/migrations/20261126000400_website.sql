-- Section 08: the public website and the staff portal (docs/sections/08-web.md).
-- Line-by-line review (Fiona): row level security (a signed-out visitor gets two functions, nothing else).
--
-- Visitors have no privileges on any table (supabase/tests/00). The site reads the public catalogue (services with
-- their summaries and prices, clinics with their hours and phone) through public_catalogue(), and sends an enquiry
-- through submit_lead(), which checks consent and limits repeats. An enquiry is a task for the chosen clinic; only
-- staff read enquiries. Kept 12 months, then deleted (retention schedule).

create function public.public_catalogue() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'locations', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', l.code, 'name', l.name, 'address', l.address_line, 'city', l.city, 'state', l.state,
        'postal_code', l.postal_code, 'phone', l.phone,
        'hours', (select coalesce(jsonb_agg(jsonb_build_object('weekday', h.weekday, 'opens', to_char(h.opens, 'HH24:MI'),
                                                              'closes', to_char(h.closes, 'HH24:MI')) order by h.weekday, h.opens), '[]')
                  from public.location_hours h where h.location_id = l.id)) order by l.name), '[]')
      from public.locations l),
    'services', (select coalesce(jsonb_agg(jsonb_build_object(
        'code', s.code, 'name', s.name, 'summary', s.summary, 'duration_minutes', s.duration_minutes,
        'prices', (select coalesce(jsonb_object_agg(l.code, ls.price_cents), '{}')
                   from public.location_services ls join public.locations l on l.id = ls.location_id
                   where ls.service_id = s.id and ls.active)) order by s.name), '[]')
      from public.services s where s.active));
$$;
revoke all on function public.public_catalogue() from public;
grant execute on function public.public_catalogue() to anon, authenticated;

create table public.leads (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (char_length(name) between 2 and 80),
  email         text not null check (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' and char_length(email) <= 120),
  phone         text check (char_length(phone) <= 30),
  location_id   uuid not null references public.locations (id) on delete restrict,
  service_id    uuid references public.services (id) on delete restrict,
  message       text not null check (char_length(message) between 2 and 1000),
  consent_at    timestamptz not null,
  created_at    timestamptz not null default now()
);
create index leads_email_time on public.leads (lower(email), created_at desc);
alter table public.leads enable row level security;
create policy staff_need_mfa on public.leads as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create trigger audit_row after insert or update or delete on public.leads
  for each row execute function private.audit_row();
revoke all on public.leads from anon, authenticated;
grant select on public.leads to authenticated;
create policy staff_reads_leads on public.leads for select to authenticated
  using (private.is_staff() and location_id in (select private.my_location_ids()));

alter table public.staff_tasks drop constraint staff_tasks_kind_check,
  add constraint staff_tasks_kind_check check (kind in ('schedule_conflict', 'checkin_follow_up', 'billing_follow_up',
                                                        'shop_fulfilment', 'assistant_handover', 'website_lead'));

create function public.submit_lead(name text, email text, phone text, location_code text, service_code text,
                                   message text, consent boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  loc  uuid := (select l.id from public.locations l where l.code = submit_lead.location_code);
  svc  uuid := (select s.id from public.services s where s.code = submit_lead.service_code and s.active);
  lead uuid;
begin
  if not coalesce(consent, false) then
    raise exception 'consent to be contacted is needed' using errcode = 'invalid_parameter_value';
  end if;
  if loc is null or coalesce(email, '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'check the clinic and the email address' using errcode = 'invalid_parameter_value';
  end if;
  if (select count(*) from public.leads l where lower(l.email) = lower(btrim(submit_lead.email))
        and l.created_at > now() - interval '1 day') >= 3 then
    raise exception 'we already have your enquiries; the clinic will reply' using errcode = 'program_limit_exceeded';
  end if;
  insert into public.leads (name, email, phone, location_id, service_id, message, consent_at)
  values (btrim(submit_lead.name), lower(btrim(submit_lead.email)), nullif(btrim(submit_lead.phone), ''), loc, svc,
          btrim(submit_lead.message), now())
  returning id into lead;
  insert into public.staff_tasks (kind, location_id, reference_id, priority) values ('website_lead', loc, lead, 'normal');
end;
$$;
revoke all on function public.submit_lead(text, text, text, text, text, text, boolean) from public;
grant execute on function public.submit_lead(text, text, text, text, text, text, boolean) to anon, authenticated;
