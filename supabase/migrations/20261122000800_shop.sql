-- The dental shop in the patient app (Fiona, 2026-11-21; plan in section 08a).
-- Line-by-line review (Fiona): money, and the clinical rules on what a patient may buy.
--
-- Every rule is checked here, at order time, never trusted from the app: prices come from this catalogue, prescription-
-- strength items need a dentist's approval for that patient, whitening needs an adult with an exam in the last year,
-- collection orders need stock at the chosen clinic. Stripe then adds sales tax (Stripe Tax) and takes the card; W05
-- records the result. Product names are deliberately non-diagnostic, because they reach Stripe.

create table public.shop_products (
  id                     uuid primary key default gen_random_uuid(),
  sku                    text not null unique,
  name                   text not null,
  category               text not null check (category in ('brush', 'clean_between', 'paste_and_rinse', 'prescription',
                                                           'aligners', 'whitening', 'kids')),
  summary                text not null check (char_length(summary) <= 140),
  description            text not null check (char_length(description) <= 600),
  tags                   text[] not null default '{}',     -- benefit labels: Sensitive, Gums, Aligners...
  price_cents            integer not null check (price_cents > 0),
  refill_interval_months integer check (refill_interval_months in (1, 2, 3, 6)),  -- null: not sold as a refill
  rule                   text not null default 'none' check (rule in ('none', 'prescription', 'whitening')),
  image_key              text not null check (image_key ~ '^[a-z0-9-]+$'),
  sort                   integer not null default 100,
  active                 boolean not null default true
);

create table public.shop_stock (
  product_id  uuid not null references public.shop_products (id) on delete restrict,
  location_id uuid not null references public.locations (id) on delete restrict,
  quantity    integer not null check (quantity >= 0),
  primary key (product_id, location_id)
);

-- A dentist approves a prescription-strength product for one patient, for a limited time.
create table public.shop_approvals (
  patient_id  uuid not null references public.patients (id) on delete restrict,
  product_id  uuid not null references public.shop_products (id) on delete restrict,
  approved_by uuid not null references public.profiles (id) on delete restrict,
  approved_at timestamptz not null default now(),
  expires_on  date not null default (current_date + 365),
  primary key (patient_id, product_id)
);

create table public.shop_orders (
  id                         uuid primary key default gen_random_uuid(),
  patient_id                 uuid not null references public.patients (id) on delete restrict,
  status                     text not null default 'pending'
                             check (status in ('pending', 'paid', 'ready', 'collected', 'shipped', 'expired')),
  fulfilment                 text not null check (fulfilment in ('collect', 'ship')),
  location_id                uuid not null references public.locations (id) on delete restrict,  -- collection clinic, or the clinic that ships
  subtotal_cents             integer not null check (subtotal_cents > 0),
  shipping_cents             integer not null default 0 check (shipping_cents >= 0),
  tax_cents                  integer check (tax_cents >= 0),       -- set from Stripe once paid
  total_cents                integer check (total_cents > 0),      -- set from Stripe once paid
  has_refills                boolean not null default false,
  parent_order_id            uuid references public.shop_orders (id) on delete restrict,  -- a refill cycle's order
  stripe_checkout_session_id text unique,
  stripe_subscription_id     text,
  created_at                 timestamptz not null default now(),
  paid_at                    timestamptz,
  check ((status = 'pending' or status = 'expired') = (paid_at is null))
);
create index shop_orders_patient_idx on public.shop_orders (patient_id, created_at desc);

create table public.shop_order_items (
  order_id   uuid not null references public.shop_orders (id) on delete cascade,
  product_id uuid not null references public.shop_products (id) on delete restrict,
  quantity   integer not null check (quantity between 1 and 10),
  unit_cents integer not null check (unit_cents > 0),
  refill     boolean not null default false,
  primary key (order_id, product_id)
);

-- ---------- access ----------

alter table public.shop_products    enable row level security;
alter table public.shop_stock       enable row level security;
alter table public.shop_approvals   enable row level security;
alter table public.shop_orders      enable row level security;
alter table public.shop_order_items enable row level security;
do $$ declare t text; begin
  foreach t in array array['shop_products', 'shop_stock', 'shop_approvals', 'shop_orders', 'shop_order_items'] loop
    execute format('create policy staff_need_mfa on public.%I as restrictive for all to authenticated
                      using ((select private.passes_staff_gate())) with check ((select private.passes_staff_gate()))', t);
    execute format('create trigger audit_row after insert or update or delete on public.%I
                      for each row execute function private.audit_row()', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

grant select on public.shop_products, public.shop_stock, public.shop_approvals, public.shop_orders, public.shop_order_items
  to authenticated;
grant insert, update, delete on public.shop_products, public.shop_stock to authenticated;
grant insert, delete on public.shop_approvals to authenticated;
grant update (status) on public.shop_orders to authenticated;

-- The catalogue and stock levels are readable by anyone signed in; only an org admin changes them (money).
create policy read_products on public.shop_products for select to authenticated using (active or private.is_staff());
create policy admin_manages_products on public.shop_products for all to authenticated
  using (private.is_org_admin()) with check (private.is_org_admin());
create policy read_stock on public.shop_stock for select to authenticated using (true);
create policy staff_manage_stock on public.shop_stock for all to authenticated
  using (private.is_org_admin() or private.manages(location_id)) with check (private.is_org_admin() or private.manages(location_id));

-- Approvals: the patient sees their own; a clinician approves for patients they can see, under their own name.
create policy patient_reads_approvals on public.shop_approvals for select to authenticated
  using (patient_id in (select private.my_patient_ids()));
create policy staff_reads_approvals on public.shop_approvals for select to authenticated
  using (private.is_staff() and private.can_see_patient(patient_id));
create policy clinician_approves on public.shop_approvals for insert to authenticated
  with check ((select private.my_role()) in ('clinician', 'org_admin') and approved_by = auth.uid()
              and private.can_see_patient(patient_id));
create policy clinician_withdraws on public.shop_approvals for delete to authenticated
  using ((select private.my_role()) in ('clinician', 'org_admin') and private.can_see_patient(patient_id));

-- Orders: the patient sees their own; clinic staff see and move on their clinic's orders (ready, collected, shipped).
create policy patient_reads_orders on public.shop_orders for select to authenticated
  using (patient_id in (select private.my_patient_ids()));
create policy staff_reads_orders on public.shop_orders for select to authenticated
  using (private.is_staff() and (private.is_org_admin() or location_id in (select private.my_location_ids())));
create policy staff_moves_orders on public.shop_orders for update to authenticated
  using (private.is_staff() and status in ('paid', 'ready') and (private.is_org_admin() or location_id in (select private.my_location_ids())))
  with check (status in ('ready', 'collected', 'shipped'));
create policy read_order_items on public.shop_order_items for select to authenticated
  using (exists (select 1 from public.shop_orders o where o.id = order_id));  -- the order's own policies decide

-- ---------- placing an order ----------

-- What the app sends: [{product_id, quantity, refill}], how to receive it, and the clinic. Returns the order ID.
-- The order is pending until Stripe confirms payment (W05).
create function public.create_shop_order(items jsonb, fulfilment text, location uuid) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  buyer     uuid := (select l.patient_id from public.patient_links l where l.profile_id = auth.uid());
  order_id  uuid;
  subtotal  integer;
  refills   boolean;
  line      record;
begin
  if not private.passes_patient_gate() or buyer is null then
    raise exception 'sign in with a linked patient record to order' using errcode = 'insufficient_privilege';
  end if;
  if fulfilment not in ('collect', 'ship') or not private.is_active_location(location) then
    raise exception 'choose collection at a clinic or delivery' using errcode = 'invalid_parameter_value';
  end if;
  if jsonb_typeof(items) <> 'array' or jsonb_array_length(items) not between 1 and 20 then
    raise exception 'the bag is empty or too large' using errcode = 'invalid_parameter_value';
  end if;

  for line in
    select p.*, (i ->> 'quantity')::integer as qty, coalesce((i ->> 'refill')::boolean, false) as wants_refill
      from jsonb_array_elements(items) i
      left join public.shop_products p on p.id = (i ->> 'product_id')::uuid and p.active
  loop
    if line.id is null then
      raise exception 'a product in the bag is no longer sold' using errcode = 'invalid_parameter_value';
    end if;
    if line.qty is null or line.qty not between 1 and 10 then
      raise exception 'quantities are 1 to 10' using errcode = 'invalid_parameter_value';
    end if;
    if line.wants_refill and line.refill_interval_months is null then
      raise exception '% is not sold as a refill', line.name using errcode = 'invalid_parameter_value';
    end if;
    if line.rule = 'prescription' and not exists (
         select 1 from public.shop_approvals a
          where a.patient_id = buyer and a.product_id = line.id and a.expires_on >= current_date) then
      raise exception '% needs your dentist''s approval first', line.name using errcode = 'insufficient_privilege';
    end if;
    if line.rule = 'whitening' and (
         (select age(current_date, p.date_of_birth) < interval '18 years' from public.patients p where p.id = buyer)
         or not exists (select 1 from public.encounters e where e.patient_id = buyer and e.kind = 'exam'
                         and e.occurred_at > now() - interval '12 months')) then
      raise exception 'whitening needs an exam in the last 12 months and is for adults only' using errcode = 'insufficient_privilege';
    end if;
    if fulfilment = 'collect' and coalesce((select s.quantity from public.shop_stock s
                                              where s.product_id = line.id and s.location_id = location), 0) < line.qty then
      raise exception '% is out of stock at that clinic', line.name using errcode = 'invalid_parameter_value';
    end if;
  end loop;

  select sum(p.price_cents * (i ->> 'quantity')::integer), bool_or(coalesce((i ->> 'refill')::boolean, false))
    into subtotal, refills
    from jsonb_array_elements(items) i join public.shop_products p on p.id = (i ->> 'product_id')::uuid;

  insert into public.shop_orders (patient_id, fulfilment, location_id, subtotal_cents, shipping_cents, has_refills)
  values (buyer, fulfilment, location, subtotal,
          case when fulfilment = 'ship' and subtotal < 5000 then 799 else 0 end,  -- $7.99, free from $50
          refills)
  returning id into order_id;
  insert into public.shop_order_items (order_id, product_id, quantity, unit_cents, refill)
  select order_id, p.id, (i ->> 'quantity')::integer, p.price_cents, coalesce((i ->> 'refill')::boolean, false)
    from jsonb_array_elements(items) i join public.shop_products p on p.id = (i ->> 'product_id')::uuid;
  return order_id;
end;
$$;
revoke all on function public.create_shop_order(jsonb, text, uuid) from public;
grant execute on function public.create_shop_order(jsonb, text, uuid) to authenticated;

-- ---------- paying: links, Checkout lines, and Stripe's answer ----------

alter table private.action_tokens alter column appointment_id drop not null,
  add column order_id uuid references public.shop_orders (id) on delete cascade,
  drop constraint action_tokens_purpose_check,
  add constraint action_tokens_purpose_check check (purpose in ('cancel', 'checkin', 'pay', 'shop')),
  add constraint action_tokens_target check ((purpose = 'shop') = (order_id is not null) and (purpose = 'shop' or appointment_id is not null));

-- The app asks for a single-use link to pay for its own pending order; it opens W12, which builds the Checkout.
create function public.shop_order_pay_link(order_id uuid) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare
  token text := translate(encode(extensions.gen_random_bytes(24), 'base64'), '+/', '-_');
begin
  if not private.passes_patient_gate() or not exists (
       select 1 from public.shop_orders o where o.id = shop_order_pay_link.order_id and o.status = 'pending'
          and o.patient_id in (select private.my_patient_ids())) then
    raise exception 'this order cannot be paid' using errcode = 'insufficient_privilege';
  end if;
  insert into private.action_tokens (token_hash, purpose, order_id, expires_at)
  values (private.token_hash(token), 'shop', shop_order_pay_link.order_id, now() + interval '1 hour');
  return token;
end;
$$;
revoke all on function public.shop_order_pay_link(uuid) from public;
grant execute on function public.shop_order_pay_link(uuid) to authenticated;

-- W12 reads what to put in the Checkout Session: one row per line, plus the order's fulfilment. Product names only,
-- never the patient. A used, expired or paid link returns no rows.
create function private.shop_checkout_lines(token text)
returns table (order_id uuid, fulfilment text, shipping_cents integer, has_refills boolean,
               name text, quantity integer, unit_cents integer, refill_months integer)
language sql stable security definer set search_path = '' as $$
  select o.id, o.fulfilment, o.shipping_cents, o.has_refills, p.name, i.quantity, i.unit_cents,
         case when i.refill then p.refill_interval_months end
    from private.action_tokens t
    join public.shop_orders o on o.id = t.order_id and o.status = 'pending'
    join public.shop_order_items i on i.order_id = o.id
    join public.shop_products p on p.id = i.product_id
   where t.token_hash = private.token_hash(token) and t.purpose = 'shop' and t.expires_at > now()
$$;

create function private.attach_shop_checkout(order_id uuid, session_id text) returns void
language sql security definer set search_path = '' as $$
  update public.shop_orders set stripe_checkout_session_id = session_id
   where id = attach_shop_checkout.order_id and status = 'pending'
$$;

-- Called from record_stripe_event for sessions this function knows: checks the item subtotal and shipping against
-- the order (Stripe adds tax), records tax and total, takes collection stock, opens a fulfilment task, queues the email.
create function private.record_shop_payment(session jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  o public.shop_orders;
begin
  select * into o from public.shop_orders where stripe_checkout_session_id = session ->> 'id' for update;
  if o.id is null then
    return null;  -- not a shop session
  end if;
  if session ->> 'payment_status' <> 'paid' then
    return 'ignored';
  end if;
  if (session ->> 'amount_subtotal')::integer <> o.subtotal_cents
     or coalesce((session -> 'total_details' ->> 'amount_shipping')::integer, 0) <> o.shipping_cents
     or session ->> 'currency' <> 'usd' then
    raise exception 'stripe collected a different amount than the order' using errcode = 'check_violation';
  end if;
  update public.shop_orders
     set status = 'paid', paid_at = now(), tax_cents = coalesce((session -> 'total_details' ->> 'amount_tax')::integer, 0),
         total_cents = (session ->> 'amount_total')::integer, stripe_subscription_id = session ->> 'subscription'
   where id = o.id and status = 'pending';
  if not found then
    return 'recorded';
  end if;
  if o.fulfilment = 'collect' then
    update public.shop_stock s set quantity = greatest(s.quantity - i.quantity, 0)
      from public.shop_order_items i where i.order_id = o.id and s.product_id = i.product_id and s.location_id = o.location_id;
  end if;
  insert into public.staff_tasks (kind, location_id, reference_id, priority)
  values ('shop_fulfilment', o.location_id, o.id, 'normal');
  perform pgmq.send('notifications', jsonb_build_object('type', 'order', 'order_id', o.id));
  return 'recorded';
end;
$$;

-- A refill cycle Stripe has charged (invoice.paid, billing_reason subscription_cycle): a new paid order for the refill
-- items, so the clinic ships or sets them aside like any order.
create function private.record_shop_refill(invoice jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  parent public.shop_orders;
  child  uuid;
begin
  select * into parent from public.shop_orders
   where stripe_subscription_id = coalesce(invoice ->> 'subscription', invoice -> 'parent' -> 'subscription_details' ->> 'subscription')
     and parent_order_id is null;
  if parent.id is null or invoice ->> 'billing_reason' <> 'subscription_cycle' then
    return 'ignored';
  end if;
  insert into public.shop_orders (patient_id, status, fulfilment, location_id, subtotal_cents, shipping_cents, tax_cents,
                                  total_cents, has_refills, parent_order_id, paid_at)
  select parent.patient_id, 'paid', parent.fulfilment, parent.location_id, sum(i.quantity * i.unit_cents), 0,
         coalesce((invoice ->> 'tax')::integer, 0), (invoice ->> 'amount_paid')::integer, true, parent.id, now()
    from public.shop_order_items i where i.order_id = parent.id and i.refill
  returning id into child;
  insert into public.shop_order_items (order_id, product_id, quantity, unit_cents, refill)
  select child, i.product_id, i.quantity, i.unit_cents, true from public.shop_order_items i where i.order_id = parent.id and i.refill;
  insert into public.staff_tasks (kind, location_id, reference_id, priority) values ('shop_fulfilment', parent.location_id, child, 'normal');
  perform pgmq.send('notifications', jsonb_build_object('type', 'order', 'order_id', child));
  return 'recorded';
end;
$$;

-- Staff tasks can now be about an order rather than a visit.
alter table public.staff_tasks alter column appointment_id drop not null,
  drop constraint staff_tasks_kind_check,
  add constraint staff_tasks_kind_check check (kind in ('schedule_conflict', 'checkin_follow_up', 'billing_follow_up', 'shop_fulfilment'));

-- record_stripe_event learns about shop sessions and refill invoices; visit payments work exactly as before.
create or replace function private.record_stripe_event(raw_body text, signature_header text, tolerance_seconds integer default 300)
returns text
language plpgsql security definer set search_path = '' as $$
declare
  secret    text := (select decrypted_secret from vault.decrypted_secrets where name = 'stripe_webhook_secret');
  signed_at bigint;
  event     jsonb;
  session   jsonb;
  shop      text;
  p         public.payments;
begin
  if secret is null then
    raise exception 'stripe webhook secret is not configured' using errcode = 'insufficient_privilege';
  end if;
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
  if event ->> 'type' = 'invoice.paid' then
    return private.record_shop_refill(event -> 'data' -> 'object');
  end if;
  if event ->> 'type' not in ('checkout.session.completed', 'checkout.session.async_payment_succeeded',
                              'checkout.session.expired') then
    return 'ignored';
  end if;

  session := event -> 'data' -> 'object';
  if event ->> 'type' = 'checkout.session.expired' then
    update public.shop_orders set status = 'expired' where stripe_checkout_session_id = session ->> 'id' and status = 'pending';
  else
    shop := private.record_shop_payment(session);
    if shop is not null then
      return shop;
    end if;
  end if;

  select * into p from public.payments where stripe_checkout_session_id = session ->> 'id' for update;
  if p.id is null then
    return case when event ->> 'type' = 'checkout.session.expired' then 'expired' else 'ignored' end;
  end if;
  if event ->> 'type' = 'checkout.session.expired' then
    update public.payments set status = 'expired', updated_at = now() where id = p.id and status = 'pending';
    return 'expired';
  end if;
  if session ->> 'payment_status' <> 'paid' then
    return 'ignored';
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

-- What the worker needs for the order email: first name, sign-in email, the lines, totals and how it arrives.
create function private.order_context(order_id uuid)
returns table (first_name text, email text, status text, fulfilment text, clinic_name text, clinic_phone text,
               total_cents integer, lines text[], refill boolean)
language sql stable security definer set search_path = '' as $$
  select coalesce(pt.preferred_name, pt.given_name), u.email::text, o.status, o.fulfilment, l.name, l.phone, o.total_cents,
         array(select i.quantity || ' × ' || p.name from public.shop_order_items i join public.shop_products p on p.id = i.product_id
                where i.order_id = o.id order by p.sort, p.name),
         o.parent_order_id is not null
    from public.shop_orders o
    join public.patients pt on pt.id = o.patient_id
    join public.locations l on l.id = o.location_id
    left join public.patient_links pl on pl.patient_id = pt.id
    left join auth.users u on u.id = pl.profile_id
   where o.id = order_context.order_id
$$;

revoke all on function private.shop_checkout_lines(text), private.attach_shop_checkout(uuid, text),
  private.record_shop_payment(jsonb), private.record_shop_refill(jsonb), private.order_context(uuid) from public;
grant execute on function private.shop_checkout_lines(text), private.attach_shop_checkout(uuid, text) to northgate_patient_actions;
grant execute on function private.order_context(uuid) to northgate_worker;

-- ---------- the catalogue ----------

insert into public.shop_products (sku, name, category, summary, description, tags, price_cents, refill_interval_months, rule, image_key, sort) values
  ('NG-BR-01', 'Sonic electric toothbrush', 'brush', 'Two-minute timer, pressure sensor and a 30-day battery.',
   'The brush our hygienists recommend most: 31,000 strokes a minute, a pressure sensor that slows down when you press too hard, and a 30-second pacer for each part of the mouth.', '{Everyday,Gums}', 7900, null, 'none', 'sonic-brush', 10),
  ('NG-BR-02', 'Replacement brush heads, 2 pack', 'brush', 'Fits the Northgate sonic brush. Change every three months.',
   'Soft, end-rounded bristles that fade from teal to white when it is time to change. Most people replace a head every three months.', '{Everyday}', 1400, 3, 'none', 'brush-heads', 11),
  ('NG-BR-03', 'Kids'' sonic toothbrush', 'kids', 'Smaller head, gentle mode and a fun two-minute timer.',
   'Made for ages 3 to 10: a small soft head, a gentle mode and a timer that plays a tune so two minutes feels short.', '{Kids}', 3900, null, 'none', 'kids-brush', 60),
  ('NG-BR-04', 'Travel case', 'brush', 'Slim, ventilated case for the sonic brush and a spare head.',
   'A hard case with vents so the brush dries between uses.', '{Travel}', 1200, null, 'none', 'travel-case', 12),
  ('NG-CB-01', 'Waxed floss, 3 pack', 'clean_between', 'Mint, shred-resistant, easy on tight contacts.',
   'A smooth waxed floss that slides between tight teeth without shredding.', '{Gums,Everyday}', 900, 3, 'none', 'floss', 20),
  ('NG-CB-02', 'Interdental brushes, mixed sizes', 'clean_between', 'Cleans where floss struggles: bridges, braces, gaps.',
   'Eight sizes in one pack. Your hygienist can tell you your size at your next cleaning.', '{Gums,Braces}', 850, 3, 'none', 'interdental', 21),
  ('NG-CB-03', 'Cordless water flosser', 'clean_between', 'Three pressure modes; good for implants and braces.',
   'A rechargeable water flosser with gentle, normal and pulse modes, and a reservoir that lasts a full clean.', '{Gums,Implants,Braces}', 6900, null, 'none', 'water-flosser', 22),
  ('NG-PR-01', 'Sensitive toothpaste', 'paste_and_rinse', 'Potassium nitrate formula for sensitive teeth.',
   'Daily toothpaste with fluoride and potassium nitrate. Give it two weeks of twice-daily use to feel the difference.', '{Sensitive}', 750, 3, 'none', 'sensitive-paste', 30),
  ('NG-PR-02', 'Enamel repair toothpaste', 'paste_and_rinse', 'Fluoride and calcium to strengthen enamel.',
   'For enamel that has worn thin from acidic food and drink.', '{Enamel}', 850, 3, 'none', 'enamel-paste', 31),
  ('NG-PR-03', 'Alcohol-free mouthwash', 'paste_and_rinse', 'Fluoride rinse without the sting.',
   'An alcohol-free fluoride rinse for after brushing, at a different time from your toothpaste.', '{Everyday}', 950, null, 'none', 'mouthwash', 32),
  ('NG-PR-04', 'Dry mouth gel', 'paste_and_rinse', 'Soothing gel for a dry mouth, day or night.',
   'Relief for a dry mouth from medicines or breathing through the mouth at night.', '{Comfort}', 1100, null, 'none', 'dry-mouth-gel', 33),
  ('NG-RX-01', 'High-fluoride toothpaste', 'prescription', 'Prescription strength. Your dentist must approve it first.',
   'A prescription-strength fluoride toothpaste for people at higher risk of decay. Your dentist approves it for you, then it appears here to order.', '{Prescription}', 1800, 3, 'prescription', 'high-fluoride', 40),
  ('NG-RX-02', 'Prescription gum rinse', 'prescription', 'For a short course after gum treatment, as your dentist directs.',
   'A prescription rinse used for a short course after gum treatment. Your dentist approves it for you first.', '{Prescription}', 1600, null, 'prescription', 'gum-rinse', 41),
  ('NG-AL-01', 'Aligner chewies, 2 pack', 'aligners', 'Seat your aligners fully after every change.',
   'Soft chews that press aligners into place, so they fit closely and move teeth as planned.', '{Aligners}', 800, null, 'none', 'chewies', 50),
  ('NG-AL-02', 'Aligner and retainer case', 'aligners', 'Pocket-sized, vented, hard shell.',
   'Keeps aligners or a retainer safe when you eat. Most lost aligners were wrapped in a napkin.', '{Aligners,Retainers}', 1400, null, 'none', 'aligner-case', 51),
  ('NG-AL-03', 'Aligner cleaning crystals, 3 months', 'aligners', 'Keeps aligners clear and fresh in 15 minutes.',
   'Dissolving crystals that clean aligners and retainers without scratching them.', '{Aligners,Retainers}', 2200, 3, 'none', 'cleaning-crystals', 52),
  ('NG-WH-01', 'Take-home whitening kit', 'whitening', 'Dentist-supervised; needs a recent exam.',
   'A supervised whitening course with trays and gel. Available to adults who have had an exam in the last 12 months, so we know whitening is right for you.', '{Whitening}', 19900, null, 'whitening', 'whitening-kit', 70),
  ('NG-KD-01', 'Kids'' brushing kit', 'kids', 'Brush, timer and a mild fruit toothpaste.',
   'Everything a child needs to brush well for two minutes, twice a day.', '{Kids}', 2400, null, 'none', 'kids-kit', 61),
  ('NG-KD-02', 'Disclosing tablets', 'kids', 'Shows the spots brushing missed.',
   'Chew one after brushing: any plaque left turns pink, so children (and adults) can see where to brush better.', '{Kids,Everyday}', 700, null, 'none', 'disclosing', 62);

-- Each clinic starts with 12 of everything for collection.
insert into public.shop_stock (product_id, location_id, quantity)
select p.id, l.id, 12 from public.shop_products p cross join public.locations l;
