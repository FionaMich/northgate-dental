-- Section 07 T1: Supabase Queues (pgmq) with the transactional outbox, idempotent consumers and exactly-once reminders.
-- Queues live in the same database as the data, so an event sent inside the transaction that changed an appointment
-- commits or rolls back with it: nothing is lost if a worker or n8n is down. Messages carry IDs only.
-- Line-by-line review (Fiona): who can read and write the queues, and what a patient message may contain.

create extension if not exists pgmq;
create extension if not exists pg_cron;

select pgmq.create('events');        -- domain events from the outbox (appointment changes)
select pgmq.create('notifications'); -- send requests: confirmations, reminders, receipts
select pgmq.create('urgent');        -- clinical messages (red flags, check-in concerns), never behind bulk sends

-- Nobody but the database owner and the worker role touches the queues; patients and staff never do.
revoke all on schema pgmq from public, anon, authenticated;
revoke all on all tables in schema pgmq from public, anon, authenticated;
revoke all on all functions in schema pgmq from public, anon, authenticated;
alter default privileges in schema pgmq revoke all on tables from public, anon, authenticated;
alter default privileges in schema pgmq revoke all on functions from public, anon, authenticated;

-- ---------- outbox: every appointment change becomes an event ----------

create function private.publish_appointment_event() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform pgmq.send('events', jsonb_build_object(
    'appointment_id', new.appointment_id,
    'version', new.version,
    'from_status', new.from_status,
    'to_status', new.to_status));
  return null;
end;
$$;
revoke all on function private.publish_appointment_event() from public;

create trigger appointment_events_publish
  after insert on public.appointment_events
  for each row execute function private.publish_appointment_event();

-- ---------- idempotent consumers ----------

create table private.processed_events (
  consumer     text not null,
  message_key  text not null,          -- for example 'events:<msg_id>' or 'stripe:<event id>'
  processed_at timestamptz not null default now(),
  primary key (consumer, message_key)
);

-- True the first time a consumer sees a message, false afterwards: a duplicate delivery has no effect.
create function private.mark_processed(consumer text, message_key text) returns boolean
language sql security definer set search_path = '' as $$
  with ins as (
    insert into private.processed_events (consumer, message_key) values (mark_processed.consumer, mark_processed.message_key)
    on conflict do nothing
    returning 1
  )
  select exists (select 1 from ins)
$$;
revoke all on function private.mark_processed(text, text) from public;

-- ---------- reminders, claimed exactly once ----------

create table private.reminder_log (
  appointment_id uuid not null references public.appointments (id) on delete cascade,
  kind           text not null check (kind in ('72h', '24h', '6h')),
  claimed_at     timestamptz not null,
  primary key (appointment_id, kind)
);

-- Claims the reminders due at `at` and queues one send request for each. Quiet hours are 21:00 to 08:00 in the clinic's
-- time zone: nothing is claimed then, and a reminder that would fall inside them moves to 20:00 the evening before.
-- Each reminder has a two-hour window, so a scanner outage longer than that skips it rather than sending it late.
create function private.claim_due_reminders(at timestamptz default now())
returns table (appointment_id uuid, kind text)
language plpgsql security definer set search_path = '' as $$
begin
  return query
  with kinds (kind, lead) as (
    values ('72h', interval '72 hours'), ('24h', interval '24 hours'), ('6h', interval '6 hours')
  ),
  due as (
    select a.id, k.kind, l.time_zone, (a.starts_at - k.lead) at time zone l.time_zone as raw_local
    from public.appointments a
    join public.locations l on l.id = a.location_id
    cross join kinds k
    where a.status = 'booked' and a.starts_at > claim_due_reminders.at
  ),
  adjusted as (
    select d.id, d.kind, d.time_zone,
           case
             when extract(hour from d.raw_local) >= 21 then date_trunc('day', d.raw_local) + interval '20 hours'
             when extract(hour from d.raw_local) < 8 then date_trunc('day', d.raw_local) - interval '4 hours'
             else d.raw_local
           end as due_local
    from due d
  ),
  claimed as (
    insert into private.reminder_log (appointment_id, kind, claimed_at)
    select x.id, x.kind, claim_due_reminders.at
    from adjusted x
    where (claim_due_reminders.at at time zone x.time_zone) >= x.due_local
      and (claim_due_reminders.at at time zone x.time_zone) < x.due_local + interval '2 hours'
      and extract(hour from claim_due_reminders.at at time zone x.time_zone) between 8 and 20
    on conflict do nothing
    returning reminder_log.appointment_id, reminder_log.kind
  ),
  queued as (
    select c.appointment_id, c.kind,
           pgmq.send('notifications', jsonb_build_object('type', 'reminder', 'appointment_id', c.appointment_id, 'kind', c.kind))
    from claimed c
  )
  select q.appointment_id, q.kind from queued q;
end;
$$;
revoke all on function private.claim_due_reminders(timestamptz) from public;

-- Every 10 minutes, inside the database: no scheduler to keep alive elsewhere, and one copy of the database means one
-- scanner (Addendum D's automation lease matters once the standby exists, section 16).
select cron.schedule('reminder-scanner', '*/10 * * * *', $$ select private.claim_due_reminders() $$);

-- ---------- what was sent ----------

create table private.notification_log (
  id                  bigint generated always as identity primary key,
  appointment_id      uuid references public.appointments (id) on delete set null,
  patient_id          uuid references public.patients (id) on delete set null,
  kind                text not null,      -- 'confirmation', 'reminder:24h', 'receipt', ...
  channel             text not null check (channel in ('email', 'push', 'whatsapp')),
  template            text not null,      -- template name and version; never the message text
  provider_message_id text,
  status              text not null default 'queued' check (status in ('queued', 'sent', 'delivered', 'read', 'failed')),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (appointment_id, kind, channel)  -- one confirmation or reminder per channel, however often it is retried
);

-- The worker's role: queues, the logs and the idempotency check, nothing else. A login for it is created by hand on
-- each project (section 07 T2), never in a migration, so no password lives in Git.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'northgate_worker') then
    create role northgate_worker nologin;
  end if;
end $$;
grant usage on schema pgmq, private to northgate_worker;
grant select, insert, update, delete on all tables in schema pgmq to northgate_worker;
grant execute on all functions in schema pgmq to northgate_worker; -- read, send, archive, delete, set_vt
grant select, insert, update on private.notification_log to northgate_worker;
grant execute on function private.mark_processed(text, text) to northgate_worker;
