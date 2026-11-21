import { workflow, node, trigger, expr } from '@n8n/workflow-sdk';

// W04: a payment link for a visit. Called by other workflows and, from section 09, by the assistant as an MCP tool.
// The amount comes from the price list inside open_payment(), never from the caller. Stripe sees only an amount, a
// generic item name and our payment ID: no name, email or service (no BAA with Stripe; payments are covered by the
// HIPAA payment-processing exemption, so nothing clinical goes there).
const start = trigger({
  type: 'n8n-nodes-base.executeWorkflowTrigger',
  version: 1.1,
  config: {
    name: 'Payment link requested',
    parameters: { inputSource: 'workflowInputs', workflowInputs: { values: [{ name: 'appointment_id', type: 'string' }] } },
    position: [0, 0],
  },
});

const open = node({
  type: 'n8n-nodes-base.postgres',
  version: 2.6,
  config: {
    name: 'Open payment',
    parameters: {
      operation: 'executeQuery',
      query: 'select payment_id, amount_cents from private.open_payment($1::uuid)',
      options: { queryReplacement: expr('{{ [ $json.appointment_id ] }}') },
    },
    credentials: { postgres: { id: 'ngPaymentsDb0001', name: 'Northgate payments database' } },
    position: [220, 0],
  },
});

const checkout = node({
  type: 'n8n-nodes-base.httpRequest',
  version: 4.2,
  config: {
    name: 'Create Checkout Session',
    parameters: {
      method: 'POST',
      url: 'https://api.stripe.com/v1/checkout/sessions',
      authentication: 'predefinedCredentialType',
      nodeCredentialType: 'stripeApi',
      sendHeaders: true,
      headerParameters: { parameters: [{ name: 'Idempotency-Key', value: expr('{{ "checkout-" + $json.payment_id }}') }] },
      sendBody: true,
      contentType: 'form-urlencoded',
      specifyBody: 'string',
      body: expr('{{ [ "mode=payment", "line_items[0][quantity]=1", "line_items[0][price_data][currency]=usd", "line_items[0][price_data][unit_amount]=" + $json.amount_cents, "line_items[0][price_data][product_data][name]=" + encodeURIComponent("Northgate Dental visit"), "client_reference_id=" + $json.payment_id, "metadata[payment_id]=" + $json.payment_id, "success_url=" + encodeURIComponent("https://84-12-126-31.sslip.io/"), "cancel_url=" + encodeURIComponent("https://84-12-126-31.sslip.io/") ].join("&") }}'),
      options: {},
    },
    credentials: { stripeApi: { id: 'ngStripeTest0001', name: 'Stripe test mode' } },
    position: [440, 0],
  },
});

const attach = node({
  type: 'n8n-nodes-base.postgres',
  version: 2.6,
  config: {
    name: 'Remember session',
    parameters: {
      operation: 'executeQuery',
      query: 'select private.attach_checkout($1::uuid, $2), $1 as payment_id, $3 as url',
      options: { queryReplacement: expr("{{ [ $('Open payment').item.json.payment_id, $json.id, $json.url ] }}") },
    },
    credentials: { postgres: { id: 'ngPaymentsDb0001', name: 'Northgate payments database' } },
    position: [660, 0],
  },
});

export default workflow('northgate-w04', 'W04 Payment link')
  .add(start)
  .to(open)
  .to(checkout)
  .to(attach)
  .group('Create the link', [open, checkout, attach], {
    description: 'Price from the database, Checkout Session at Stripe (idempotent per payment), session ID stored.',
  });
