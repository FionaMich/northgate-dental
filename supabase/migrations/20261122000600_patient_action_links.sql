-- Section 07 T4 and T6: the links inside patient emails, and what happens when a patient opens one.
-- Line-by-line review (Fiona): patient messaging, money (pay links) and clinical safety (check-in red flags).
--
--   W03 cancel link     confirmation and reminder emails   cancels within the location's policy; single use
--   W11 check-in link   1 and 3 days after a visit         "fine" or "concern" plus a note, screened for red flags
--   W06 pay link        statement reminders, days 0/14/28  sends the patient to Stripe Checkout for the open balance
--
-- A link is a random token; only its SHA-256 hash is stored, so a copy of the database cannot be turned into working
-- links. Links name no patient (they can be forwarded): the pages show the service, time and clinic only. Opening a link
-- (GET) never changes anything, because mail scanners open links; only the button on the page (POST) acts.

create table private.action_tokens (
  token_hash     bytea primary key,
  purpose        text not null check (purpose in ('cancel', 'checkin', 'pay')),
  appointment_id uuid not null references public.appointments (id) on delete cascade,
  kind           text,                        -- check-in day ('1d', '3d') or statement step
  payment_id     uuid references public.payments (id) on delete cascade,
  expires_at     timestamptz not null,
  used_at        timestamptz,
  created_at     timestamptz not null default now()
);

create function private.token_hash(token text) returns bytea
language sql immutable set search_path = '' as $$ select extensions.digest(token, 'sha256') $$;

-- The worker asks for a link when it writes an email. Cancel links last until the visit starts, check-in links a
-- week, pay links 30 days.
create function private.issue_action_token(appointment uuid, purpose text, kind text default null, payment uuid default null)
returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  token text := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/', '-_');
begin
  insert into private.action_tokens (token_hash, purpose, appointment_id, kind, payment_id, expires_at)
  select private.token_hash(token), issue_action_token.purpose, a.id, issue_action_token.kind, issue_action_token.payment,
         case issue_action_token.purpose when 'cancel' then a.starts_at
                                          when 'checkin' then now() + interval '7 days'
                                          else now() + interval '30 days' end
    from public.appointments a where a.id = issue_action_token.appointment;
  if not found then
    raise exception 'no such visit' using errcode = 'no_data_found';
  end if;
  return token;
end;
$$;

-- How many hours before a visit it can still be cancelled online: the location's setting, else the organisation's.
create function private.cancellation_hours(location uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select coalesce((
    select (coalesce(o.settings, '{}'::jsonb) || coalesce(s.overrides, '{}'::jsonb)) ->> 'cancellation_hours'
      from public.org_settings o left join public.location_settings s on s.location_id = cancellation_hours.location
     where o.id = 1)::integer, 24)
$$;

-- What a page may show about a link: no name, no record number, nothing clinical beyond the service.
-- state: ok, used, expired, unknown, too_late (inside the cancellation window), closed (visit no longer booked), paid.
create function private.describe_action(token text, purpose text)
returns table (state text, service_name text, starts_local text, clinic_name text, clinic_phone text, amount_cents integer)
language plpgsql stable security definer set search_path = '' as $$
declare
  t private.action_tokens;
  a public.appointments;
  p public.payments;
begin
  select * into t from private.action_tokens x where x.token_hash = private.token_hash(token) and x.purpose = describe_action.purpose;
  if t.token_hash is null then
    return query select 'unknown', null::text, null::text, null::text, null::text, null::integer; return;
  end if;
  select * into a from public.appointments where id = t.appointment_id;
  select * into p from public.payments where id = t.payment_id;
  return query
  select case
           when t.used_at is not null then 'used'
           when t.expires_at <= now() then 'expired'
           when t.purpose = 'cancel' and a.status <> 'booked' then 'closed'
           when t.purpose = 'cancel' and a.starts_at - now() < private.cancellation_hours(a.location_id) * interval '1 hour' then 'too_late'
           when t.purpose = 'pay' and p.status = 'paid' then 'paid'
           when t.purpose = 'pay' and p.status <> 'pending' then 'closed'
           else 'ok' end,
         s.name, to_char(a.starts_at at time zone l.time_zone, 'FMDay FMDD FMMonth "at" HH24:MI'), 'Northgate Dental, ' || l.name,
         l.phone, p.amount_cents
    from public.locations l, public.services s
   where l.id = a.location_id and s.id = a.service_id;
end;
$$;

-- W03: cancel from the email. The outbox then sends the cancellation notice as for any cancellation.
create function private.cancel_by_token(token text) returns text
language plpgsql security definer set search_path = '' as $$
declare
  st text := (select d.state from private.describe_action(token, 'cancel') d);
begin
  if st <> 'ok' then
    return st;
  end if;
  update private.action_tokens set used_at = now() where token_hash = private.token_hash(token) and used_at is null;
  if not found then
    return 'used';  -- two clicks at once: only one wins
  end if;
  update public.appointments set status = 'cancelled'
   where id = (select appointment_id from private.action_tokens where token_hash = private.token_hash(token))
     and status = 'booked';
  return 'cancelled';
end;
$$;

-- ---------- W11: post-visit check-ins ----------

create table public.post_visit_checkins (
  id             uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments (id) on delete restrict,
  patient_id     uuid not null references public.patients (id) on delete restrict,
  day            text not null check (day in ('1d', '3d')),
  feeling        text not null check (feeling in ('fine', 'concern')),
  note           text check (char_length(note) <= 1000),
  red_flags      text[] not null default '{}',
  created_at     timestamptz not null default now(),
  unique (appointment_id, day)
);
alter table public.post_visit_checkins enable row level security;
create policy staff_need_mfa on public.post_visit_checkins as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create trigger audit_row after insert or update or delete on public.post_visit_checkins
  for each row execute function private.audit_row();
revoke all on public.post_visit_checkins from anon, authenticated;
grant select on public.post_visit_checkins to authenticated;
create policy patient_reads_own_checkins on public.post_visit_checkins for select to authenticated
  using (patient_id in (select private.my_clinical_patient_ids()));
create policy staff_reads_checkins on public.post_visit_checkins for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
insert into private.audit_redacted_tables (table_name) values ('post_visit_checkins') on conflict do nothing;

-- Red flags after dental treatment, by fixed rules: no model reads the note (red-flag messages skip the model).
-- Deliberately broad: a false alarm costs a phone call; a missed one could cost much more.
create function private.red_flags(note text) returns text[]
language sql immutable set search_path = '' as $$
  select coalesce(array_agg(flag order by flag), '{}') from (values
    ('breathing_or_swallowing', '(breath|swallow|choking)'),
    ('heavy_bleeding',          'bleed[a-z]*.{0,40}(won.?t stop|not stop|heavy|a lot|lots|soak|still)|(heavy|lots of|a lot of) blood'),
    ('spreading_swelling',      'swell[a-z]*.{0,40}(spread|eye|neck|jaw|worse|bigger|growing)'),
    ('fever',                   '(fever|temperature|chills|shiver)'),
    ('lasting_numbness',        'numb[a-z]*.{0,40}(still|won.?t|days|not gone|not going)'),
    ('infection_signs',         '(pus|foul taste|bad taste|discharge)'),
    ('severe_pain',             '(pain|hurt|ache)[a-z]*.{0,40}(unbearable|severe|worse|terrible|10/10|can.?t sleep)|(severe|unbearable|terrible) (pain|ache)')
  ) r (flag, pattern)
  where coalesce(note, '') ~* r.pattern
$$;

-- W11: record the answer. A concern or any red flag opens a task for the clinic and goes on the urgent queue, where
-- the worker alerts the clinic at once, separate from routine sends.
create function private.record_checkin(token text, feeling text, note text)
returns table (state text, red_flags text[], clinic_phone text)
language plpgsql security definer set search_path = '' as $$
declare
  t private.action_tokens;
  flags text[] := private.red_flags(note);
  c public.post_visit_checkins;
begin
  update private.action_tokens x set used_at = now()
   where x.token_hash = private.token_hash(token) and x.purpose = 'checkin' and x.used_at is null and x.expires_at > now()
  returning * into t;
  if t.token_hash is null then
    return query select 'unusable', '{}'::text[], null::text; return;
  end if;
  insert into public.post_visit_checkins (appointment_id, patient_id, day, feeling, note, red_flags)
  select a.id, a.patient_id, t.kind, record_checkin.feeling, nullif(btrim(record_checkin.note), ''), flags
    from public.appointments a where a.id = t.appointment_id
  on conflict (appointment_id, day) do nothing
  returning * into c;
  if c.id is null then
    return query select 'unusable', '{}'::text[], null::text; return;
  end if;
  if c.feeling = 'concern' or cardinality(flags) > 0 then
    insert into public.staff_tasks (kind, appointment_id, location_id, reference_id, priority)
    select 'checkin_follow_up', a.id, a.location_id, c.id, case when cardinality(flags) > 0 then 'urgent' else 'high' end
      from public.appointments a where a.id = c.appointment_id;
    perform pgmq.send('urgent', jsonb_build_object('type', 'checkin_alert', 'appointment_id', c.appointment_id, 'checkin_id', c.id));
  end if;
  return query select 'recorded', flags, l.phone
    from public.appointments a join public.locations l on l.id = a.location_id where a.id = c.appointment_id;
end;
$$;

create table private.checkin_log (
  appointment_id uuid not null references public.appointments (id) on delete cascade,
  day            text not null check (day in ('1d', '3d')),
  claimed_at     timestamptz not null,
  primary key (appointment_id, day)
);

-- Check-ins go at 10:00 clinic time on the first and third day after a completed visit, once each, within 2 hours.
create function private.claim_due_checkins(at timestamptz default now())
returns table (appointment_id uuid, day text)
language sql security definer set search_path = '' as $$
  with due as (
    select a.id, d.day, l.time_zone,
           ((a.ends_at at time zone l.time_zone)::date + d.n) + time '10:00' as due_local
      from public.appointments a
      join public.locations l on l.id = a.location_id
     cross join (values ('1d', 1), ('3d', 3)) d (day, n)
     where a.status = 'completed' and a.ends_at > claim_due_checkins.at - interval '5 days'
  ),
  claimed as (
    insert into private.checkin_log (appointment_id, day, claimed_at)
    select x.id, x.day, claim_due_checkins.at from due x
     where (claim_due_checkins.at at time zone x.time_zone) >= x.due_local
       and (claim_due_checkins.at at time zone x.time_zone) < x.due_local + interval '2 hours'
    on conflict do nothing
    returning checkin_log.appointment_id, checkin_log.day
  ),
  queued as (
    select c.appointment_id, c.day,
           pgmq.send('notifications', jsonb_build_object('type', 'checkin', 'appointment_id', c.appointment_id, 'kind', c.day))
      from claimed c
  )
  select q.appointment_id, q.day from queued q
$$;
select cron.schedule('checkin-scanner', '*/10 * * * *', $$ select private.claim_due_checkins() $$);

-- ---------- W06: statement reminders ----------

create table private.statement_log (
  payment_id uuid not null references public.payments (id) on delete cascade,
  step       text not null check (step in ('0d', '14d', '28d', 'billing')),
  claimed_at timestamptz not null,
  primary key (payment_id, step)
);

-- An open balance is a payment still pending after the visit is completed. Reminders on days 0, 14 and 28 at 10:00
-- clinic time; on day 35 a billing task for the clinic instead of another email.
create function private.claim_due_statements(at timestamptz default now())
returns integer
language plpgsql security definer set search_path = '' as $$
declare
  n integer;
begin
  with due as (
    select p.id as payment_id, p.appointment_id, a.location_id, s.step, l.time_zone,
           ((a.ends_at at time zone l.time_zone)::date + s.n) + time '10:00' as due_local
      from public.payments p
      join public.appointments a on a.id = p.appointment_id
      join public.locations l on l.id = a.location_id
     cross join (values ('0d', 0), ('14d', 14), ('28d', 28), ('billing', 35)) s (step, n)
     where p.status = 'pending' and a.status = 'completed'
  ),
  claimed as (
    insert into private.statement_log (payment_id, step, claimed_at)
    select x.payment_id, x.step, claim_due_statements.at from due x
     where (claim_due_statements.at at time zone x.time_zone) >= x.due_local
       and (claim_due_statements.at at time zone x.time_zone) < x.due_local + interval '2 hours'
    on conflict do nothing
    returning statement_log.payment_id, statement_log.step
  ),
  sent as (
    select pgmq.send('notifications', jsonb_build_object('type', 'statement', 'appointment_id', d.appointment_id,
                                                          'payment_id', d.payment_id, 'kind', d.step))
      from claimed c join due d on d.payment_id = c.payment_id and d.step = c.step
     where c.step <> 'billing'
  ),
  tasks as (
    insert into public.staff_tasks (kind, appointment_id, location_id, reference_id)
    select 'billing_follow_up', d.appointment_id, d.location_id, d.payment_id
      from claimed c join due d on d.payment_id = c.payment_id and d.step = c.step
     where c.step = 'billing'
    on conflict do nothing
    returning 1
  )
  select (select count(*) from sent) + (select count(*) from tasks) into n;
  return n;
end;
$$;
select cron.schedule('statement-scanner', '*/10 * * * *', $$ select private.claim_due_statements() $$);

-- W06 pay link: the payment the link is for, while it is still open. n8n then runs W04 to get a Checkout page.
create function private.payment_for_token(token text) returns table (state text, appointment_id uuid)
language sql stable security definer set search_path = '' as $$
  select d.state, t.appointment_id
    from private.action_tokens t, private.describe_action(token, 'pay') d
   where t.token_hash = private.token_hash(token) and t.purpose = 'pay'
$$;

-- What the worker reads for a statement: the open amount, nothing else about the payment.
create function private.balance_amount(payment uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select amount_cents from public.payments where id = balance_amount.payment and status = 'pending'
$$;

-- ---------- who may call what ----------

revoke all on function private.token_hash(text), private.issue_action_token(uuid, text, text, uuid),
  private.cancellation_hours(uuid), private.describe_action(text, text), private.cancel_by_token(text),
  private.red_flags(text), private.record_checkin(text, text, text), private.claim_due_checkins(timestamptz),
  private.claim_due_statements(timestamptz), private.payment_for_token(text), private.balance_amount(uuid) from public;

-- The worker writes the emails, so it issues links and reads the open balance.
grant execute on function private.issue_action_token(uuid, text, text, uuid), private.balance_amount(uuid) to northgate_worker;

-- n8n's patient-action pages: describe a link, cancel, record a check-in, find the payment. Nothing else.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'northgate_patient_actions') then
    create role northgate_patient_actions nologin;
  end if;
end $$;
grant usage on schema private to northgate_patient_actions;
grant execute on function private.describe_action(text, text), private.cancel_by_token(text),
  private.record_checkin(text, text, text), private.payment_for_token(text) to northgate_patient_actions;
