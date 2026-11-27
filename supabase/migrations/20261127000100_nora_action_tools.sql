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

-- The free-slot query, without the caller checks, so the reschedule page (n8n's role, nobody signed in) can offer times.
-- public.available_slots keeps exactly its old checks on top of it; the page asks for self-bookable services only.
create function private.free_slots(loc uuid, service uuid, from_day date, days int, staff_only_too boolean)
returns table (practitioner_id uuid, starts_at timestamptz, ends_at timestamptz, resource_id uuid)
language sql stable security definer set search_path = '' as $$
  with svc as (
    select s.id, s.duration_minutes * interval '1 minute' as len, s.requires_resource, s.specialty_id
      from public.services s
      join public.location_services ls on ls.service_id = s.id and ls.location_id = loc and ls.active
     where s.id = service and s.active and (s.self_bookable or staff_only_too)
  ),
  place as (select l.time_zone from public.locations l where l.id = loc and l.active),
  shifts as (
    select pr.practitioner_id,
           (d::date + (w ->> 0)::time) at time zone place.time_zone as opens,
           (d::date + (w ->> 1)::time) at time zone place.time_zone as closes
      from svc, place,
           generate_series(from_day::timestamp, (from_day + least(greatest(days, 1), 60) - 1)::timestamp, interval '1 day') d,
           public.practitioner_roles pr,
           jsonb_array_elements(pr.weekly_template -> lower(to_char(d, 'dy'))) w
     where pr.location_id = loc and private.can_perform(pr.specialty_id, svc.specialty_id)
  ),
  starts as (
    select distinct sh.practitioner_id, g as starts_at, g + svc.len as ends_at
      from shifts sh, svc, generate_series(sh.opens, sh.closes - svc.len, interval '30 minutes') g
     where g > now()
  )
  select c.practitioner_id, c.starts_at, c.ends_at, r.id
    from starts c cross join svc
    left join lateral (
      select res.id from public.resources res
       where res.location_id = loc and res.kind = svc.requires_resource
         and not exists (select 1 from public.appointments a
                          where a.resource_id = res.id and a.status in ('held', 'booked', 'arrived')
                            and (a.status <> 'held' or a.hold_expires_at > now())
                            and tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)'))
       order by res.id limit 1) r on true
   where (svc.requires_resource is null or r.id is not null)
     and not exists (select 1 from public.appointments a
                      where a.practitioner_id = c.practitioner_id and a.status in ('held', 'booked', 'arrived')
                        and (a.status <> 'held' or a.hold_expires_at > now())
                        and tstzrange(a.starts_at, a.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)'))
     and not exists (select 1 from public.availability_exceptions x
                      where x.practitioner_id = c.practitioner_id
                        and tstzrange(x.starts_at, x.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)'))
     and not exists (select 1 from public.location_closures lc
                      where lc.location_id = loc
                        and tstzrange(lc.starts_at, lc.ends_at, '[)') && tstzrange(c.starts_at, c.ends_at, '[)'))
   order by c.starts_at, c.practitioner_id
$$;
revoke all on function private.free_slots(uuid, uuid, date, int, boolean) from public;

create or replace function public.available_slots(loc uuid, service uuid, from_day date default current_date, days int default 14)
returns table (practitioner_id uuid, starts_at timestamptz, ends_at timestamptz, resource_id uuid)
language sql stable security definer set search_path = '' as $$
  select f.* from private.free_slots(loc, service, from_day, days, private.is_staff()) f where private.passes_staff_gate()
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
             from (select distinct s.starts_at from private.free_slots(a.location_id, a.service_id, current_date, 14, false) s
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
  select s.* into slot from private.free_slots(a.location_id, a.service_id,
                                                 (starts at time zone (select time_zone from public.locations where id = a.location_id))::date, 1, false) s
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
