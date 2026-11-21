-- The dental shop: the server decides prices, rules and stock; only a correctly signed Stripe event pays an order,
-- once; refills become new orders; nobody sees another patient's orders.
begin;
select plan(25);

create function pg_temp.act_as(uid uuid) returns void language plpgsql as $$
begin
  insert into auth.sessions (id, user_id) select uid, uid where exists (select 1 from auth.users where id = uid) on conflict do nothing;
  insert into private.verified_sessions (session_id, user_id) select uid, uid on conflict do nothing;
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role', 'authenticated', 'aal', 'aal1', 'session_id', uid)::text, true);
  set local role authenticated;
end;
$$;
create function pg_temp.sku(s text) returns uuid language sql security definer as $$ select id from public.shop_products where sku = s $$;
create function pg_temp.loc(c text) returns uuid language sql security definer as $$ select id from public.locations where code = c $$;
create function pg_temp.items(variadic lines text[]) returns jsonb language sql security definer as $$
  select jsonb_agg(jsonb_build_object('product_id', (select id from public.shop_products where sku = split_part(l, ':', 1)),
                                      'quantity', split_part(l, ':', 2)::int, 'refill', split_part(l, ':', 3) = 'refill',
                                      'price_cents', 1))   -- a client-sent price, which must be ignored
  from unnest(lines) l
$$;
delete from vault.secrets where name = 'stripe_webhook_secret';  -- rolled back with the test
select vault.create_secret('whsec_pgtap_shop', 'stripe_webhook_secret');
create function pg_temp.sign(body text) returns text language sql as $$
  select 't=' || extract(epoch from now())::bigint || ',v1=' ||
         encode(extensions.hmac(extract(epoch from now())::bigint || '.' || body, 'whsec_pgtap_shop', 'sha256'), 'hex')
$$;

-- Elena (...014) is linked to record ...001 (an adult). Her exams are moved out of the last year for the whitening rule.
insert into patient_links (profile_id, patient_id) values ('10000000-0000-4000-8000-000000000014', '30000000-0000-4000-8000-000000000001')
  on conflict do nothing;
update encounters set occurred_at = occurred_at - interval '3 years' where patient_id = '30000000-0000-4000-8000-000000000001';
select set_config('test.quincy', pg_temp.loc('quincy')::text, true);
select set_config('test.bag1', pg_temp.items('NG-BR-01:1', 'NG-BR-02:2:refill')::text, true);
select set_config('test.bag2', pg_temp.items('NG-PR-01:1')::text, true);
select set_config('test.bag3', pg_temp.items('NG-RX-01:1')::text, true);
select set_config('test.bag4', pg_temp.items('NG-WH-01:1')::text, true);
select set_config('test.bag5', pg_temp.items('NG-BR-01:1:refill')::text, true);
select set_config('test.bag6', pg_temp.items('NG-BR-01:11')::text, true);
select set_config('test.bag7', pg_temp.items('NG-CB-03:1')::text, true);
create temp table ids (name text primary key, id uuid);
grant all on ids to authenticated;

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select ok((select count(*) from shop_products) >= 19, 'a signed-in patient sees the catalogue');
select lives_ok($$ insert into ids values ('order', public.create_shop_order(
  current_setting('test.bag1')::jsonb, 'collect', current_setting('test.quincy')::uuid)) $$, 'a patient can order');
reset role;

select is((select subtotal_cents from shop_orders where id = (select id from ids where name = 'order')), 7900 + 2 * 1400,
  'the subtotal comes from the catalogue, not the price the app sent');
select is((select shipping_cents from shop_orders where id = (select id from ids where name = 'order')), 0, 'collection is free');
select ok((select has_refills from shop_orders where id = (select id from ids where name = 'order')), 'a refill line makes it a refill order');

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
insert into ids values ('small_ship', public.create_shop_order(current_setting('test.bag2')::jsonb, 'ship', current_setting('test.quincy')::uuid));
reset role;
select is((select shipping_cents from shop_orders where id = (select id from ids where name = 'small_ship')), 799,
  'delivery under $50 costs $7.99');

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select throws_ok($$ select public.create_shop_order(current_setting('test.bag3')::jsonb, 'ship', current_setting('test.quincy')::uuid) $$,
  '42501', null, 'a prescription-strength product without a dentist''s approval is refused');
select throws_ok($$ select public.create_shop_order(current_setting('test.bag4')::jsonb, 'ship', current_setting('test.quincy')::uuid) $$,
  '42501', null, 'whitening without an exam in the last year is refused');
select throws_ok($$ select public.create_shop_order(current_setting('test.bag5')::jsonb, 'ship', current_setting('test.quincy')::uuid) $$,
  '22023', null, 'a product not sold as a refill cannot be ordered as one');
select throws_ok($$ select public.create_shop_order(current_setting('test.bag6')::jsonb, 'ship', current_setting('test.quincy')::uuid) $$,
  '22023', null, 'quantities above 10 are refused');
reset role;

-- The dentist approves the high-fluoride toothpaste; an exam today unlocks whitening.
insert into shop_approvals (patient_id, product_id, approved_by)
values ('30000000-0000-4000-8000-000000000001', pg_temp.sku('NG-RX-01'), '10000000-0000-4000-8000-000000000013');
insert into encounters (patient_id, location_id, practitioner_id, occurred_at, kind)
select '30000000-0000-4000-8000-000000000001', pg_temp.loc('quincy'), pr.id, now(), 'exam'
  from practitioners pr where pr.profile_id = '10000000-0000-4000-8000-000000000013';
update shop_stock set quantity = 0 where product_id = pg_temp.sku('NG-CB-03') and location_id = pg_temp.loc('quincy');

select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select lives_ok($$ select public.create_shop_order(current_setting('test.bag3')::jsonb, 'ship', current_setting('test.quincy')::uuid) $$,
  'with the dentist''s approval it can be ordered');
select lives_ok($$ select public.create_shop_order(current_setting('test.bag4')::jsonb, 'ship', current_setting('test.quincy')::uuid) $$,
  'an adult with a recent exam can order whitening');
select throws_ok($$ select public.create_shop_order(current_setting('test.bag7')::jsonb, 'collect', current_setting('test.quincy')::uuid) $$,
  '22023', null, 'collection is refused when the clinic is out of stock');
select ok(length(public.shop_order_pay_link((select id from ids where name = 'order'))) = 32, 'the patient gets a pay link for their order');
reset role;

-- Someone else (Back Bay's receptionist without the clinic, and another patient) cannot see Elena's order.
select pg_temp.act_as('10000000-0000-4000-8000-000000000002');
select is((select count(*)::int from shop_orders where id = (select id from ids where name = 'order')), 0,
  'staff at another clinic do not see the order');
reset role;

-- Checkout lines for W12, then Stripe's answer.
select pg_temp.act_as('10000000-0000-4000-8000-000000000014');
select set_config('test.token', public.shop_order_pay_link((select id from ids where name = 'order')), true);
reset role;
select is((select count(*)::int from private.shop_checkout_lines(current_setting('test.token'))), 2, 'W12 gets one line per product');
select private.attach_shop_checkout((select id from ids where name = 'order'), 'cs_test_shop');

create function pg_temp.event(id text, subtotal int) returns text language sql as $$
  select jsonb_build_object('id', id, 'type', 'checkout.session.completed', 'data', jsonb_build_object('object', jsonb_build_object(
    'id', 'cs_test_shop', 'payment_status', 'paid', 'currency', 'usd', 'amount_subtotal', subtotal, 'amount_total', subtotal + 669,
    'subscription', 'sub_test_1', 'total_details', jsonb_build_object('amount_tax', 669, 'amount_shipping', 0))))::text
$$;
select throws_ok($$ select private.record_stripe_event(pg_temp.event('evt_s1', 100), pg_temp.sign(pg_temp.event('evt_s1', 100))) $$,
  '23514', null, 'a payment for a different subtotal is refused');
select is(private.record_stripe_event(pg_temp.event('evt_s2', 10700), pg_temp.sign(pg_temp.event('evt_s2', 10700))), 'recorded',
  'a correctly signed payment marks the order paid');
select is((select tax_cents from shop_orders where id = (select id from ids where name = 'order')), 669, 'with the tax Stripe calculated');
select is((select quantity from shop_stock where product_id = pg_temp.sku('NG-BR-01') and location_id = pg_temp.loc('quincy')), 11,
  'collection stock is taken');
select is((select count(*)::int from staff_tasks where kind = 'shop_fulfilment' and reference_id = (select id from ids where name = 'order')), 1,
  'the clinic gets a task to set it aside');
select is((select count(*)::int from pgmq.q_notifications where message ->> 'order_id' = (select id::text from ids where name = 'order')), 1,
  'and one order email is queued, with IDs only');
select is(private.record_stripe_event(pg_temp.event('evt_s2', 10700), pg_temp.sign(pg_temp.event('evt_s2', 10700))), 'duplicate',
  'the same event again changes nothing');

-- Three months later Stripe charges the refill.
create function pg_temp.invoice() returns text language sql as $$
  select jsonb_build_object('id', 'evt_inv', 'type', 'invoice.paid', 'data', jsonb_build_object('object', jsonb_build_object(
    'subscription', 'sub_test_1', 'billing_reason', 'subscription_cycle', 'amount_paid', 2975, 'tax', 175)))::text
$$;
select is(private.record_stripe_event(pg_temp.invoice(), pg_temp.sign(pg_temp.invoice())), 'recorded', 'a refill charge is recorded');
select is((select count(*)::int from shop_order_items i join shop_orders o on o.id = i.order_id
            where o.parent_order_id = (select id from ids where name = 'order')), 1,
  'as a new paid order with only the refill items');

select * from finish();
rollback;
