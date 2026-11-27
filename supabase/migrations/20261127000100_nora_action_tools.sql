-- Nora's action tools (blueprint sections 21 and 24): n8n's MCP Server Trigger publishes send_payment_link,
-- reschedule_link and ask_receptionist, and each one calls a function below with the patient's own session token, so
-- row level security and these checks decide, never the model or n8n.
-- Line-by-line review (Fiona): money (the payment link), patient messaging (both emails) and booking (moving a visit
-- from a link).
--
--   send_my_payment_link     emails a pay link for the caller's own visit and returns one for the chat
--   send_my_reschedule_link  emails a single-use link to choose a new time for the caller's own visit
--   reschedule_options       the page behind that link: the visit and up to 8 free times, no patient name
--   move_by_token            the button on that page: books the new time and cancels the old one in one step

alter table private.action_tokens drop constraint action_tokens_purpose_check;
alter table private.action_tokens add constraint action_tokens_purpose_check
  check (purpose in ('cancel', 'checkin', 'pay', 'shop', 'reschedule'));

-- A reschedule link lasts until the visit starts, like a cancel link.
create or replace function private.issue_action_token(appointment uuid, purpose text, kind text default null, payment uuid default null)
returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  token text := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/', '-_');
begin
  insert into private.action_tokens (token_hash, purpose, appointment_id, kind, payment_id, expires_at)
  select private.token_hash(token), issue_action_token.purpose, a.id, issue_action_token.kind, issue_action_token.payment,
         case when issue_action_token.purpose in ('cancel', 'reschedule') then a.starts_at
              when issue_action_token.purpose = 'checkin' then now() + interval '7 days'
              else now() + interval '30 days' end
    from public.appointments a where a.id = issue_action_token.appointment;
  if not found then
    raise exception 'no such visit' using errcode = 'no_data_found';
  end if;
  return token;
end;
$$;

-- Moving a visit follows the cancellation window: inside it, the page says to call the clinic.
create or replace function private.describe_action(token text, purpose text)
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
           when t.purpose in ('cancel', 'reschedule') and a.status <> 'booked' then 'closed'
           when t.purpose in ('cancel', 'reschedule')
                and a.starts_at - now() < private.cancellation_hours(a.location_id) * interval '1 hour' then 'too_late'
           when t.purpose = 'pay' and p.status = 'paid' then 'paid'
           when t.purpose = 'pay' and p.status <> 'pending' then 'closed'
           else 'ok' end,
         s.name, to_char(a.starts_at at time zone l.time_zone, 'FMDay FMDD FMMonth "at" HH24:MI'), 'Northgate Dental, ' || l.name,
         l.phone, p.amount_cents
    from public.locations l, public.services s
   where l.id = a.location_id and s.id = a.service_id;
end;
$$;

-- The caller's own visit, from a session that passed the emailed sign-in code; anything else is refused.
create function private.own_visit(appointment uuid) returns public.appointments
language plpgsql stable security definer set search_path = '' as $$
declare
  a public.appointments;
begin
  select * into a from public.appointments x
   where x.id = own_visit.appointment and x.patient_id in (select private.my_patient_ids());
  if not private.passes_patient_gate() or a.id is null then
    raise exception 'this visit is not yours' using errcode = 'insufficient_privilege';
  end if;
  return a;
end;
$$;

-- send_payment_link. The amount comes from the price list (open_payment); the email goes at most once a day per visit
-- (the worker's notification log), so asking Nora again cannot flood the patient's inbox.
create function public.send_my_payment_link(appointment uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare
  a public.appointments := private.own_visit(appointment);
  payment uuid;
begin
  select o.payment_id into payment from private.open_payment(a.id) o;
  perform pgmq.send('notifications', jsonb_build_object('type', 'paylink', 'appointment_id', a.id, 'payment_id', payment,
                                                         'kind', to_char(now() at time zone 'utc', 'YYYY-MM-DD')));
  return private.issue_action_token(a.id, 'pay', 'nora', payment);
end;
$$;

-- reschedule_link. Only a booked visit outside the cancellation window; the link itself is made by the worker when it
-- writes the email, so it is never in a queue message.
create function public.send_my_reschedule_link(appointment uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  a public.appointments := private.own_visit(appointment);
begin
  if a.status <> 'booked' or a.starts_at - now() < private.cancellation_hours(a.location_id) * interval '1 hour' then
    raise exception 'this visit can no longer be moved online; please call the clinic' using errcode = 'check_violation';
  end if;
  perform pgmq.send('notifications', jsonb_build_object('type', 'movelink', 'appointment_id', a.id,
                                                         'kind', to_char(now() at time zone 'utc', 'YYYY-MM-DD')));
end;
$$;

-- The page behind a reschedule link: the visit and up to 8 free times for the same service at the same clinic over
-- the next 14 days, one per start time, outside the cancellation window.
create function private.reschedule_options(token text)
returns table (state text, service_name text, starts_local text, clinic_name text, clinic_phone text, options jsonb)
language plpgsql stable security definer set search_path = '' as $$
declare
  d record;
  a public.appointments;
  tz text;
begin
  select * into d from private.describe_action(token, 'reschedule');
  select x.* into a from public.appointments x join private.action_tokens t on t.appointment_id = x.id
   where t.token_hash = private.token_hash(token) and t.purpose = 'reschedule';
  select l.time_zone into tz from public.locations l where l.id = a.location_id;
  return query
  select d.state, d.service_name, d.starts_local, d.clinic_name, d.clinic_phone,
         case when d.state <> 'ok' then '[]'::jsonb else coalesce((
           select jsonb_agg(jsonb_build_object('at', f.starts_at,
                    'label', to_char(f.starts_at at time zone tz, 'FMDay FMDD FMMonth "at" HH24:MI')) order by f.starts_at)
             from (select distinct s.starts_at from public.available_slots(a.location_id, a.service_id, current_date, 14) s
                    where s.starts_at - now() >= private.cancellation_hours(a.location_id) * interval '1 hour'
                      and s.starts_at <> a.starts_at
                    order by s.starts_at limit 8) f), '[]'::jsonb) end;
end;
$$;

-- The button: the new time is booked and the old visit cancelled in one transaction, and the new visit records the one
-- it replaces, so the worker sends a single "your visit has moved" email. Answers: moved, taken, used, expired,
-- closed, too_late, unknown.
create function private.move_by_token(token text, starts timestamptz) returns text
language plpgsql security definer set search_path = '' as $$
declare
  st text := (select d.state from private.describe_action(token, 'reschedule') d);
  a public.appointments;
  slot record;
begin
  if st <> 'ok' then
    return st;
  end if;
  select x.* into a from public.appointments x join private.action_tokens t on t.appointment_id = x.id
   where t.token_hash = private.token_hash(token) and t.purpose = 'reschedule';
  if starts - now() < private.cancellation_hours(a.location_id) * interval '1 hour' then
    return 'taken';
  end if;
  select s.* into slot from public.available_slots(a.location_id, a.service_id,
                                                    (starts at time zone (select time_zone from public.locations where id = a.location_id))::date, 1) s
   where s.starts_at = starts
   order by (s.practitioner_id = a.practitioner_id) desc
   limit 1;
  if not found then
    return 'taken';
  end if;
  begin
    insert into public.appointments (patient_id, location_id, practitioner_id, service_id, resource_id, starts_at, ends_at,
                                     status, replaces)
    values (a.patient_id, a.location_id, slot.practitioner_id, a.service_id, slot.resource_id, slot.starts_at, slot.ends_at,
            'booked', a.id);
    update private.action_tokens set used_at = now() where token_hash = private.token_hash(token) and used_at is null;
    if not found then
      raise exception 'used';   -- two clicks at once: only one wins, and the losing booking is rolled back
    end if;
    update public.appointments set status = 'cancelled' where id = a.id and status = 'booked';
  exception
    when exclusion_violation then return 'taken';
    when raise_exception then return 'used';
  end;
  return 'moved';
end;
$$;

revoke all on function private.own_visit(uuid), public.send_my_payment_link(uuid), public.send_my_reschedule_link(uuid),
  private.reschedule_options(text), private.move_by_token(text, timestamptz) from public;
grant execute on function public.send_my_payment_link(uuid), public.send_my_reschedule_link(uuid) to authenticated;
grant execute on function private.reschedule_options(text), private.move_by_token(text, timestamptz) to northgate_patient_actions;
