import { workflow, node, trigger, expr } from '@n8n/workflow-sdk';

// W05: Stripe tells us a payment went through. n8n only relays: the raw body and signature go to Postgres, where
// private.record_stripe_event() checks the signature, ignores repeats, marks the payment paid and queues the receipt.
const hook = trigger({
  type: 'n8n-nodes-base.webhook',
  version: 2.1,
  config: {
    name: 'Stripe webhook',
    parameters: { httpMethod: 'POST', path: 'stripe', responseMode: 'responseNode', options: { rawBody: true } },
    position: [0, 0],
  },
});

const rawText = node({
  type: 'n8n-nodes-base.extractFromFile',
  version: 1.1,
  config: {
    name: 'Raw body as text',
    parameters: { operation: 'text', binaryPropertyName: 'data', destinationKey: 'raw', options: {} },
    position: [220, 0],
  },
});

const record = node({
  type: 'n8n-nodes-base.postgres',
  version: 2.6,
  config: {
    name: 'Record Stripe event',
    onError: 'continueErrorOutput',
    parameters: {
      operation: 'executeQuery',
      query: 'select private.record_stripe_event($1, $2) as result',
      options: { queryReplacement: expr("{{ [ $json.raw, $('Stripe webhook').item.json.headers['stripe-signature'] || '' ] }}") },
    },
    credentials: { postgres: { id: 'ngPaymentsDb0001', name: 'Northgate payments database' } },
    position: [440, 0],
  },
});

const ok = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: {
    name: 'Accepted',
    parameters: { respondWith: 'json', responseBody: expr('{{ JSON.stringify({ received: $json.result }) }}'), options: { responseCode: 200 } },
    position: [660, -100],
  },
});

const refused = node({
  type: 'n8n-nodes-base.respondToWebhook',
  version: 1.5,
  config: {
    name: 'Refused',
    parameters: { respondWith: 'json', responseBody: '{"received": false}', options: { responseCode: 400 } },
    position: [660, 100],
  },
});

export default workflow('northgate-w05', 'W05 Stripe payment received')
  .add(hook)
  .to(rawText)
  .to(record.onError(refused))
  .add(record)
  .to(ok)
  .group('Record the payment', [rawText, record, ok, refused], {
    description: 'Raw body and signature go to Postgres, which verifies, de-duplicates and records the payment.',
  });
