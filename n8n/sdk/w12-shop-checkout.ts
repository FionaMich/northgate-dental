import { workflow, node, trigger, expr, ifElse } from '@n8n/workflow-sdk';

// W12: shop checkout. The app's single-use link opens this; prices and rules were already checked in Postgres
// (create_shop_order), so this only turns the order's lines into a Stripe Checkout Session and redirects to it.
const open = trigger({ type: 'n8n-nodes-base.webhook', version: 2.1,
  config: { name: 'Open shop checkout', parameters: { httpMethod: 'GET', path: 'shop', responseMode: 'responseNode', options: {} }, position: [0, 0] } });
const lines = node({ type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Order lines', alwaysOutputData: true,
    parameters: { operation: 'executeQuery', query: 'select * from private.shop_checkout_lines($1)',
      options: { queryReplacement: expr("{{ [ /^[A-Za-z0-9_-]{32}$/.test($json.query.t || '') ? $json.query.t : 'invalid' ] }}") } },
    credentials: { postgres: { id: 'ngActionsDb00001', name: 'Northgate patient actions database' } }, position: [220, 0] } });
const build = node({ type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Build Checkout request', parameters: { mode: 'runOnceForAllItems', jsCode: "const rows = $input.all().map(i => i.json).filter(r => r.order_id);\nif (!rows.length) return [{ json: { ok: false } }];\nconst o = rows[0], refills = o.has_refills, enc = encodeURIComponent;\nconst p = [['mode', refills ? 'subscription' : 'payment'], ['client_reference_id', o.order_id], ['metadata[order_id]', o.order_id],\n  ['automatic_tax[enabled]', 'true'], ['success_url', 'https://84-12-126-31.sslip.io/'], ['cancel_url', 'https://84-12-126-31.sslip.io/']];\nif (!refills) p.push(['adaptive_pricing[enabled]', 'false']);\nrows.forEach((r, i) => {\n  const k = `line_items[${i}]`;\n  p.push([`${k}[quantity]`, String(r.quantity)], [`${k}[price_data][currency]`, 'usd'], [`${k}[price_data][unit_amount]`, String(r.unit_cents)],\n         [`${k}[price_data][tax_behavior]`, 'exclusive'], [`${k}[price_data][product_data][name]`, r.name],\n         [`${k}[price_data][product_data][tax_code]`, 'txcd_99999999']);\n  if (r.refill_months) p.push([`${k}[price_data][recurring][interval]`, 'month'], [`${k}[price_data][recurring][interval_count]`, String(r.refill_months)]);\n});\nif (o.fulfilment === 'ship') {\n  p.push(['shipping_address_collection[allowed_countries][0]', 'US'],\n         ['shipping_options[0][shipping_rate_data][type]', 'fixed_amount'],\n         ['shipping_options[0][shipping_rate_data][fixed_amount][amount]', String(o.shipping_cents)],\n         ['shipping_options[0][shipping_rate_data][fixed_amount][currency]', 'usd'],\n         ['shipping_options[0][shipping_rate_data][tax_behavior]', 'exclusive'],\n         ['shipping_options[0][shipping_rate_data][display_name]', o.shipping_cents ? 'Standard delivery (3 to 5 days)' : 'Free delivery (3 to 5 days)']);\n} else {\n  p.push(['billing_address_collection', 'required']);\n}\nreturn [{ json: { ok: true, order_id: o.order_id, body: p.map(([a, b]) => `${enc(a)}=${enc(b)}`).join('&') } }];\n" }, position: [440, 0] } });
const usable = ifElse({ version: 2.2, config: { name: 'Order still open?', parameters: { conditions: {
  options: { caseSensitive: true, typeValidation: 'loose' }, combinator: 'and',
  conditions: [{ leftValue: expr('{{ $json.ok }}'), rightValue: true, operator: { type: 'boolean', operation: 'true', singleValue: true } }] } },
  position: [660, 0] } });
const checkout = node({ type: 'n8n-nodes-base.httpRequest', version: 4.2,
  config: { name: 'Create Checkout Session', parameters: { method: 'POST', url: 'https://api.stripe.com/v1/checkout/sessions',
    authentication: 'predefinedCredentialType', nodeCredentialType: 'stripeApi', sendHeaders: true,
    headerParameters: { parameters: [{ name: 'Idempotency-Key', value: expr('{{ "shop-" + $json.order_id }}') }] },
    sendBody: true, contentType: 'form-urlencoded', specifyBody: 'string', body: expr('{{ $json.body }}'), options: {} },
    credentials: { stripeApi: { id: 'ngStripeTest0001', name: 'Stripe test mode' } }, position: [880, -100] } });
const remember = node({ type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Remember session',
    parameters: { operation: 'executeQuery', query: 'select private.attach_shop_checkout($1::uuid, $2), $3 as url',
      options: { queryReplacement: expr("{{ [ $('Build Checkout request').item.json.order_id, $json.id, $json.url ] }}") } },
    credentials: { postgres: { id: 'ngActionsDb00001', name: 'Northgate patient actions database' } }, position: [1100, -100] } });
const toStripe = node({ type: 'n8n-nodes-base.respondToWebhook', version: 1.5,
  config: { name: 'Redirect to Stripe', parameters: { respondWith: 'redirect', redirectURL: expr('{{ $json.url }}'), options: { responseCode: 303 } }, position: [1320, -100] } });
const expiredPage = node({ type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Expired page', parameters: { mode: 'runOnceForAllItems', jsCode: "const page = `<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><title>Order link expired</title><style>body{margin:0;font-family:system-ui,sans-serif;background:#f3f7f6;color:#0b2b2a}main{max-width:440px;margin:0 auto;padding:40px 20px}.card{background:#fff;border-radius:20px;padding:28px 24px;margin-top:24px}b span{color:#137c6c}</style></head><body><main><b>Northgate <span>Dental</span></b><div class=\"card\"><h1>This checkout link has expired</h1><p>Go back to the Northgate Dental app and tap Pay again; your bag is still there.</p></div></main></body></html>`;\nreturn [{ json: { html: page } }];\n" }, position: [880, 120] } });
const sendExpired = node({ type: 'n8n-nodes-base.respondToWebhook', version: 1.5,
  config: { name: 'Send expired page', parameters: { respondWith: 'text', responseBody: expr('{{ $json.html }}'),
    options: { responseHeaders: { entries: [{ name: 'Content-Type', value: 'text/html; charset=utf-8' }, { name: 'Cache-Control', value: 'no-store' }] } } }, position: [1100, 120] } });

export default workflow('northgate-w12', 'W12 Shop checkout')
  .add(open).to(lines).to(build).to(usable.onTrue(checkout.to(remember).to(toStripe)).onFalse(expiredPage.to(sendExpired)))
  .group('Checkout', [lines, build, usable, checkout, remember, toStripe, expiredPage, sendExpired],
    { description: 'Order lines from Postgres become a Stripe Checkout Session (Stripe Tax on); refills make it a subscription.' });
