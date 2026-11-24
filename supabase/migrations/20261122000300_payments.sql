-- Section 07 T5: visit payments through Stripe Checkout (test mode).
-- Line-by-line review (Fiona): money, and a message to the patient (the receipt).
--
-- How it fits together:
--   W04 (n8n) asks open_payment() for the amount, creates a Checkout Session at Stripe and stores its ID with
--   attach_checkout(). W05 (n8n) receives Stripe's webhook and hands the raw body and signature header to
--   record_stripe_event(), which checks the signature, ignores duplicates, marks the payment paid and queues a receipt.
--   All money rules live here, where they are tested; n8n only relays. The webhook signing secret lives in Supabase
--   Vault, never in a workflow or in Git.
-- Money is whole cents in an integer, as everywhere else.

create table public.payments (
  id                         uuid primary key default gen_random_uuid(),
  appointment_id             uuid not null references public.appointments (id) on delete restrict,
  patient_id                 uuid not null references public.patients (id) on delete restrict,
  amount_cents               integer not null check (amount_cents > 0),
  currency                   text not null default 'usd' check (currency = 'usd'),
  status                     text not null default 'pending' check (status in ('pending', 'paid', 'expired')),
  stripe_checkout_session_id text unique,
  stripe_payment_intent_id   text unique,
  paid_at                    timestamptz,
  created_at                 timestamptz not null default now(),
  updated_at                 timestamptz not null default now(),
  check ((status = 'paid') = (paid_at is not null))
);
-- One open or settled payment per visit: a second payment link for the same visit reuses the first.
create unique index payments_one_live_per_appointment on public.payments (appointment_id) where status in ('pending', 'paid');
create index payments_patient_idx on public.payments (patient_id);

alter table public.payments enable row level security;
create policy staff_need_mfa on public.payments as restrictive for all to authenticated
  using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()));
create trigger audit_row after insert or update or delete on public.payments
  for each row execute function private.audit_row();

-- Read-only for everyone signed in; only the functions below write.
revoke all on public.payments from anon, authenticated;
grant select on public.payments to authenticated;
create policy patient_reads_own_payments on public.payments for select to authenticated
  using (patient_id in (select private.my_patient_ids()));
create policy staff_reads_payments on public.payments for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));

-- W04, step 1: the payment for a visit. Reuses an open one, so asking twice never charges twice. The amount is the
-- location's price for the service, never a number supplied by the caller.
create function private.open_payment(appointment uuid)
returns table (payment_id uuid, amount_cents integer, checkout_session_id text)
language plpgsql security definer set search_path = '' as $$
declare
  a public.appointments;
  p public.payments;
begin
  select * into a from public.appointments where id = open_payment.appointment;
  if a.id is null or a.status not in ('booked', 'arrived', 'completed') then
    raise exception 'only a booked or completed visit can be paid for' using errcode = 'check_violation';
  end if;
  select * into p from public.payments where payments.appointment_id = a.id and status in ('pending', 'paid');
  if p.status = 'paid' then
    raise exception 'this visit is already paid' using errcode = 'unique_violation';
  end if;
  if p.id is null then
    insert into public.payments (appointment_id, patient_id, amount_cents)
    select a.id, a.patient_id, ls.price_cents
      from public.location_services ls
     where ls.location_id = a.location_id and ls.service_id = a.service_id and ls.price_cents > 0
    returning * into p;
    if p.id is null then
      raise exception 'this service has no price to collect' using errcode = 'check_violation';
    end if;
  end if;
  return query select p.id, p.amount_cents, p.stripe_checkout_session_id;
end;
$$;

-- W04, step 2: remember which Checkout Session collects this payment. W04 sends the payment ID as Stripe's
-- idempotency key, so within 24 hours a repeat returns the same session; after that the old session has expired
-- (Checkout's default), and the new one replaces it.
create function private.attach_checkout(payment uuid, session_id text)
returns void
language sql security definer set search_path = '' as $$
  update public.payments set stripe_checkout_session_id = session_id, updated_at = now()
   where id = attach_checkout.payment and status = 'pending'
$$;

-- W05: one Stripe webhook delivery. Returns what happened: recorded, expired, duplicate or ignored.
-- Raises (so n8n answers 400 and Stripe retries or shows the failure) when the signature is wrong or stale,
-- or when the amount Stripe collected differs from the amount we asked for.
create function private.record_stripe_event(raw_body text, signature_header text, tolerance_seconds integer default 300)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  secret    text := (select decrypted_secret from vault.decrypted_secrets where name = 'stripe_webhook_secret');
  signed_at bigint;
  event     jsonb;
  session   jsonb;
  p         public.payments;
begin
  if secret is null then
    raise exception 'stripe webhook secret is not configured' using errcode = 'insufficient_privilege';
  end if;
  -- Stripe-Signature: t=<unix time>,v1=<hex HMAC-SHA256 of "<t>.<raw body>">[,v1=...]
  signed_at := nullif(substring(signature_header from 't=(\d+)'), '')::bigint;
  if signed_at is null
     or abs(extract(epoch from now()) - signed_at) > tolerance_seconds
     or not exists (
       select 1 from regexp_matches(signature_header, 'v1=([0-9a-f]{64})', 'g') m
        where m[1] = encode(extensions.hmac(signed_at || '.' || raw_body, secret, 'sha256'), 'hex')) then
    raise exception 'stripe signature check failed' using errcode = 'insufficient_privilege';
  end if;

  event := raw_body::jsonb;
  if not private.mark_processed('stripe', event ->> 'id') then
    return 'duplicate';
  end if;
  if event ->> 'type' not in ('checkout.session.completed', 'checkout.session.async_payment_succeeded',
                              'checkout.session.expired') then
    return 'ignored';
  end if;

  session := event -> 'data' -> 'object';
  select * into p from public.payments where stripe_checkout_session_id = session ->> 'id' for update;
  if p.id is null then
    return 'ignored';  -- a session this system did not create (another product on the same Stripe account)
  end if;

  if event ->> 'type' = 'checkout.session.expired' then
    update public.payments set status = 'expired', updated_at = now() where id = p.id and status = 'pending';
    return 'expired';
  end if;
  if session ->> 'payment_status' <> 'paid' then
    return 'ignored';  -- a delayed method: async_payment_succeeded follows
  end if;
  if (session ->> 'amount_total')::integer <> p.amount_cents or session ->> 'currency' <> p.currency then
    raise exception 'stripe collected a different amount than was asked for' using errcode = 'check_violation';
  end if;

  update public.payments
     set status = 'paid', paid_at = now(), stripe_payment_intent_id = session ->> 'payment_intent', updated_at = now()
   where id = p.id and status <> 'paid';
  if found then
    perform pgmq.send('notifications', jsonb_build_object('type', 'receipt', 'appointment_id', p.appointment_id,
                                                          'payment_id', p.id));
  end if;
  return 'recorded';
end;
$$;

-- The receipt needs the amount; the worker reads it through this, nothing else about the payment.
create function private.receipt_amount(payment uuid) returns integer
language sql stable security definer set search_path = '' as $$
  select amount_cents from public.payments where id = receipt_amount.payment and status = 'paid'
$$;

-- The payments role (used by n8n): these three functions, nothing else. Its login is created by hand on each project.
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'northgate_payments') then
    create role northgate_payments nologin;
  end if;
end $$;
revoke all on function private.open_payment(uuid), private.attach_checkout(uuid, text),
  private.record_stripe_event(text, text, integer), private.receipt_amount(uuid) from public;
grant usage on schema private to northgate_payments;
grant execute on function private.open_payment(uuid), private.attach_checkout(uuid, text),
  private.record_stripe_event(text, text, integer) to northgate_payments;
grant execute on function private.receipt_amount(uuid) to northgate_worker;
