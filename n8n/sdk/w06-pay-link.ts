import { workflow, node, trigger, expr, ifElse } from '@n8n/workflow-sdk';

// W06: the pay link in statement reminders. A valid link runs W04 (price from the database, idempotent session)
// and redirects to Stripe Checkout; anything else gets a plain page.
const openLink = trigger({
  type: 'n8n-nodes-base.webhook', version: 2.1,
  config: { name: 'Open pay link', parameters: { httpMethod: 'GET', path: 'pay', responseMode: 'responseNode', options: {} }, position: [0, 0] },
});
const lookup = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Payment for link', alwaysOutputData: true,
    parameters: { operation: 'executeQuery', query: "select * from private.payment_for_token($1)", options: { queryReplacement: expr("{{ [ /^[A-Za-z0-9_-]{32}$/.test($json.query.t || '') ? $json.query.t : 'invalid' ] }}") } },
    credentials: { postgres: { id: 'ngActionsDb00001', name: 'Northgate patient actions database' } }, position: [220, 0] },
});
const isOpen = ifElse({ version: 2.2, config: { name: 'Still open?', parameters: { conditions: {
  options: { caseSensitive: true, typeValidation: 'loose' }, combinator: 'and',
  conditions: [{ leftValue: expr('{{ $json.state }}'), rightValue: 'ok', operator: { type: 'string', operation: 'equals' } }] } },
  position: [440, 0] } });
const runW04 = node({
  type: 'n8n-nodes-base.executeWorkflow', version: 1.2,
  config: { name: 'Run W04 Payment link', parameters: { source: 'database', workflowId: { __rl: true, mode: 'id', value: 'sm9FXDMA2wiesYVJ' },
    workflowInputs: { mappingMode: 'defineBelow', value: { appointment_id: expr('{{ $json.appointment_id }}') },
      schema: [{ id: 'appointment_id', displayName: 'appointment_id', type: 'string', display: true, required: false, defaultMatch: false, canBeUsedToMatch: true, removed: false }] },
    options: { waitForSubWorkflow: true } }, position: [660, -100] },
});
const toStripe = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.5,
  config: { name: 'Redirect to Stripe', parameters: { respondWith: 'redirect', redirectURL: expr('{{ $json.url }}'), options: { responseCode: 303 } }, position: [880, -100] },
});
const closedPage = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Closed page', parameters: { mode: 'runOnceForAllItems', jsCode: "// Shared page shell for the patient-action pages (copied into each Code node; n8n has no includes).\nconst esc = s => String(s ?? '').replace(/[&<>\"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '\"': '&quot;', \"'\": '&#39;' }[c]));\nconst tel = p => p ? `<a href=\"tel:${esc(p.replace(/[^+0-9]/g, ''))}\">${esc(p)}</a>` : 'your clinic';\nconst page = (title, body) => `<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"robots\" content=\"noindex\"><title>${esc(title)} \u00b7 Northgate Dental</title><style>body{margin:0;font-family:system-ui,-apple-system,\"Segoe UI\",Roboto,sans-serif;background:#f3f7f6;color:#0b2b2a}main{max-width:440px;margin:0 auto;padding:40px 20px}.brand{font-weight:700;font-size:18px}.brand span{color:#137c6c}.sub{font-size:11px;letter-spacing:.15em;color:#4c6361;margin-top:2px}.card{background:#fff;border-radius:20px;padding:28px 24px;margin-top:24px;box-shadow:0 1px 2px rgba(11,43,42,.06),0 12px 32px rgba(11,43,42,.08)}h1{font-size:22px;line-height:1.25;margin:0 0 10px}p{line-height:1.55;color:#29403e;margin:0 0 12px}.visit{background:#eef5f3;border-radius:14px;padding:14px 16px;margin:16px 0;font-weight:600}.visit small{display:block;font-weight:400;color:#4c6361;margin-top:4px}button{width:100%;padding:15px;border:0;border-radius:14px;font-size:16px;font-weight:600;background:#137c6c;color:#fff;margin-top:12px;cursor:pointer}button.danger{background:#b3261e}label.choice{display:flex;gap:12px;align-items:center;border:1.5px solid #cddbd8;border-radius:14px;padding:14px 16px;margin-top:10px;font-weight:600;cursor:pointer}label.choice:has(input:checked){border-color:#137c6c;background:#eef5f3}textarea{width:100%;box-sizing:border-box;border:1.5px solid #cddbd8;border-radius:14px;padding:12px 14px;font:inherit;min-height:100px;margin-top:14px}.alert{background:#fdeeed;border:1px solid #f1c2be;border-radius:14px;padding:16px;color:#7a1d16;margin-bottom:12px}.ok{color:#137c6c;font-size:40px;line-height:1}.muted{color:#4c6361;font-size:14px}a{color:#137c6c}</style></head><body><main><div class=\"brand\">Northgate <span>Dental</span></div><div class=\"sub\">BACK BAY \u00b7 CAMBRIDGE \u00b7 QUINCY</div><div class=\"card\">${body}</div></main></body></html>`;\nconst okToken = t => /^[A-Za-z0-9_-]{32}$/.test(String(t || ''));\nconst d = $input.first().json;\nlet html;\nif (d.state === 'paid') html = page('Already paid', `<div class=\"ok\">&#10003;</div><h1>This balance is already paid</h1><p>Thank you. Your receipt was emailed to you.</p>`);\nelse html = page('Link expired', `<h1>This payment link has expired</h1><p>Open the Northgate Dental app to see your balance, or call your clinic.</p>`);\nreturn [{ json: { html } }];\n" }, position: [660, 120] },
});
const sendClosed = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.5,
  config: { name: 'Send closed page', parameters: { respondWith: 'text', responseBody: expr('{{ $json.html }}'), options: { responseHeaders: { entries: [
        { name: 'Content-Type', value: 'text/html; charset=utf-8' },
        { name: 'Cache-Control', value: 'no-store' },
        { name: 'Referrer-Policy', value: 'no-referrer' },
        { name: 'Content-Security-Policy', value: "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'" },
      ] } } }, position: [880, 120] },
});

export default workflow('northgate-w06', 'W06 Pay link')
  .add(openLink).to(lookup).to(isOpen.onTrue(runW04.to(toStripe)).onFalse(closedPage.to(sendClosed)))
  .group('Pay', [lookup, isOpen, runW04, toStripe, closedPage, sendClosed], { description: 'An open balance goes to Stripe Checkout through W04; a paid or expired link gets a page.' });
