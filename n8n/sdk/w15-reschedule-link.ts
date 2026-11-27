import { workflow, node, trigger, expr } from '@n8n/workflow-sdk';

// W15: the reschedule link that Nora's reschedule_link tool emails. Opening it shows the visit and free times; only the
// button moves the visit, in one transaction, so the patient is never left with two visits or none.
const openLink = trigger({
  type: 'n8n-nodes-base.webhook', version: 2.1,
  config: { name: 'Open link', parameters: { httpMethod: 'GET', path: 'move', responseMode: 'responseNode', options: {} }, position: [0, 0] },
});
const options = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Free times for link', alwaysOutputData: true,
    parameters: { operation: 'executeQuery', query: 'select * from private.reschedule_options($1)', options: { queryReplacement: expr("{{ [ /^[A-Za-z0-9_-]{32}$/.test($json.query.t || '') ? $json.query.t : 'invalid' ] }}") } },
    credentials: { postgres: { id: 'ngActionsDb00001', name: 'Northgate patient actions database' } }, position: [220, 0] },
});
const showPage = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Choose page', parameters: { mode: 'runOnceForAllItems', jsCode: "// Shared page shell for the patient-action pages (copied into each Code node; n8n has no includes).\nconst esc = s => String(s ?? '').replace(/[&<>\"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '\"': '&quot;', \"'\": '&#39;' }[c]));\nconst tel = p => p ? `<a href=\"tel:${esc(p.replace(/[^+0-9]/g, ''))}\">${esc(p)}</a>` : 'your clinic';\nconst page = (title, body) => `<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"robots\" content=\"noindex\"><title>${esc(title)} \u00b7 Northgate Dental</title><style>body{margin:0;font-family:system-ui,-apple-system,\"Segoe UI\",Roboto,sans-serif;background:#f3f7f6;color:#0b2b2a}main{max-width:440px;margin:0 auto;padding:40px 20px}.brand{font-weight:700;font-size:18px}.brand span{color:#137c6c}.sub{font-size:11px;letter-spacing:.15em;color:#4c6361;margin-top:2px}.card{background:#fff;border-radius:20px;padding:28px 24px;margin-top:24px;box-shadow:0 1px 2px rgba(11,43,42,.06),0 12px 32px rgba(11,43,42,.08)}h1{font-size:22px;line-height:1.25;margin:0 0 10px}p{line-height:1.55;color:#29403e;margin:0 0 12px}.visit{background:#eef5f3;border-radius:14px;padding:14px 16px;margin:16px 0;font-weight:600}.visit small{display:block;font-weight:400;color:#4c6361;margin-top:4px}button{width:100%;padding:15px;border:0;border-radius:14px;font-size:16px;font-weight:600;background:#137c6c;color:#fff;margin-top:12px;cursor:pointer}button.danger{background:#b3261e}label.choice{display:flex;gap:12px;align-items:center;border:1.5px solid #cddbd8;border-radius:14px;padding:14px 16px;margin-top:10px;font-weight:600;cursor:pointer}label.choice:has(input:checked){border-color:#137c6c;background:#eef5f3}textarea{width:100%;box-sizing:border-box;border:1.5px solid #cddbd8;border-radius:14px;padding:12px 14px;font:inherit;min-height:100px;margin-top:14px}.alert{background:#fdeeed;border:1px solid #f1c2be;border-radius:14px;padding:16px;color:#7a1d16;margin-bottom:12px}.ok{color:#137c6c;font-size:40px;line-height:1}.muted{color:#4c6361;font-size:14px}a{color:#137c6c}</style></head><body><main><div class=\"brand\">Northgate <span>Dental</span></div><div class=\"sub\">BACK BAY \u00b7 CAMBRIDGE \u00b7 QUINCY</div><div class=\"card\">${body}</div></main></body></html>`;\nconst okToken = t => /^[A-Za-z0-9_-]{32}$/.test(String(t || ''));\nconst d = $input.first().json, t = $('Open link').first().json.query.t;\nconst visit = `<div class=\"visit\">${esc(d.service_name)}<small>Now: ${esc(d.starts_local)} \u00b7 ${esc(d.clinic_name)}</small></div>`;\nconst times = Array.isArray(d.options) ? d.options : [];\nlet html;\nif (d.state === 'ok' && times.length) html = page('Choose a new time', `<h1>Choose a new time</h1>${visit}<form method=\"post\"><input type=\"hidden\" name=\"t\" value=\"${esc(t)}\">${times.map((o, i) => `<label class=\"choice\"><input type=\"radio\" name=\"at\" value=\"${esc(o.at)}\"${i === 0 ? ' checked' : ''}>${esc(o.label)}</label>`).join('')}<button type=\"submit\">Move my visit</button></form><p class=\"muted\" style=\"margin-top:16px\">Your current visit stays booked until you press the button.</p>`);\nelse if (d.state === 'ok') html = page('Please call us', `<h1>No free times online right now</h1>${visit}<p>Please call us on ${tel(d.clinic_phone)} and we will find a time with you.</p>`);\nelse if (d.state === 'too_late') html = page('Please call us', `<h1>It is too close to your visit to move it online</h1>${visit}<p>Please call us on ${tel(d.clinic_phone)} and we will help.</p>`);\nelse if (d.state === 'used' || d.state === 'closed') html = page('Already changed', `<h1>This visit has already been moved or cancelled</h1><p>Open the Northgate Dental app to see your visits.</p>`);\nelse html = page('Link expired', `<h1>This link has expired</h1><p>Ask Nora in the app for a new one, or call your clinic.</p>`);\nreturn [{ json: { html } }];\n" }, position: [440, 0] },
});
const sendPage = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.5,
  config: { name: 'Send choose page', parameters: { respondWith: 'text', responseBody: expr('{{ $json.html }}'), options: { responseHeaders: { entries: [
        { name: 'Content-Type', value: 'text/html; charset=utf-8' },
        { name: 'Cache-Control', value: 'no-store' },
        { name: 'Referrer-Policy', value: 'no-referrer' },
        { name: 'Content-Security-Policy', value: "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'" },
      ] } } }, position: [660, 0] },
});
const press = trigger({
  type: 'n8n-nodes-base.webhook', version: 2.1,
  config: { name: 'Move pressed', parameters: { httpMethod: 'POST', path: 'move', responseMode: 'responseNode', options: {} }, position: [0, 240] },
});
const move = node({
  type: 'n8n-nodes-base.postgres', version: 2.6,
  config: { name: 'Move by link', alwaysOutputData: true,
    parameters: { operation: 'executeQuery',
      query: "select private.move_by_token($1, $2::timestamptz) as result, d.clinic_phone from private.describe_action($1, 'reschedule') d",
      options: { queryReplacement: expr("{{ [ /^[A-Za-z0-9_-]{32}$/.test($('Move pressed').item.json.body.t || '') ? $('Move pressed').item.json.body.t : 'invalid', /^\\d{4}-\\d{2}-\\d{2}T[0-9:.+-]+Z?$/.test($('Move pressed').item.json.body.at || '') ? $('Move pressed').item.json.body.at : '1970-01-01T00:00:00Z' ] }}") } },
    credentials: { postgres: { id: 'ngActionsDb00001', name: 'Northgate patient actions database' } }, position: [220, 240] },
});
const donePage = node({
  type: 'n8n-nodes-base.code', version: 2,
  config: { name: 'Result page', parameters: { mode: 'runOnceForAllItems', jsCode: "// Shared page shell for the patient-action pages (copied into each Code node; n8n has no includes).\nconst esc = s => String(s ?? '').replace(/[&<>\"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '\"': '&quot;', \"'\": '&#39;' }[c]));\nconst tel = p => p ? `<a href=\"tel:${esc(p.replace(/[^+0-9]/g, ''))}\">${esc(p)}</a>` : 'your clinic';\nconst page = (title, body) => `<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta name=\"robots\" content=\"noindex\"><title>${esc(title)} \u00b7 Northgate Dental</title><style>body{margin:0;font-family:system-ui,-apple-system,\"Segoe UI\",Roboto,sans-serif;background:#f3f7f6;color:#0b2b2a}main{max-width:440px;margin:0 auto;padding:40px 20px}.brand{font-weight:700;font-size:18px}.brand span{color:#137c6c}.sub{font-size:11px;letter-spacing:.15em;color:#4c6361;margin-top:2px}.card{background:#fff;border-radius:20px;padding:28px 24px;margin-top:24px;box-shadow:0 1px 2px rgba(11,43,42,.06),0 12px 32px rgba(11,43,42,.08)}h1{font-size:22px;line-height:1.25;margin:0 0 10px}p{line-height:1.55;color:#29403e;margin:0 0 12px}.visit{background:#eef5f3;border-radius:14px;padding:14px 16px;margin:16px 0;font-weight:600}.visit small{display:block;font-weight:400;color:#4c6361;margin-top:4px}button{width:100%;padding:15px;border:0;border-radius:14px;font-size:16px;font-weight:600;background:#137c6c;color:#fff;margin-top:12px;cursor:pointer}button.danger{background:#b3261e}label.choice{display:flex;gap:12px;align-items:center;border:1.5px solid #cddbd8;border-radius:14px;padding:14px 16px;margin-top:10px;font-weight:600;cursor:pointer}label.choice:has(input:checked){border-color:#137c6c;background:#eef5f3}textarea{width:100%;box-sizing:border-box;border:1.5px solid #cddbd8;border-radius:14px;padding:12px 14px;font:inherit;min-height:100px;margin-top:14px}.alert{background:#fdeeed;border:1px solid #f1c2be;border-radius:14px;padding:16px;color:#7a1d16;margin-bottom:12px}.ok{color:#137c6c;font-size:40px;line-height:1}.muted{color:#4c6361;font-size:14px}a{color:#137c6c}</style></head><body><main><div class=\"brand\">Northgate <span>Dental</span></div><div class=\"sub\">BACK BAY \u00b7 CAMBRIDGE \u00b7 QUINCY</div><div class=\"card\">${body}</div></main></body></html>`;\nconst okToken = t => /^[A-Za-z0-9_-]{32}$/.test(String(t || ''));\nconst d = $input.first().json;\nlet html;\nif (d.result === 'moved') html = page('Visit moved', `<div class=\"ok\">&#10003;</div><h1>Your visit has moved</h1><p>We have emailed you the new time. You can also see it in the Northgate Dental app.</p>`);\nelse if (d.result === 'taken') html = page('Time taken', `<h1>That time has just been taken</h1><p>Your visit has not changed. Go back and choose another time, or call us on ${tel(d.clinic_phone)}.</p>`);\nelse if (d.result === 'too_late') html = page('Please call us', `<h1>It is too close to your visit to move it online</h1><p>Please call us on ${tel(d.clinic_phone)}.</p>`);\nelse if (d.result === 'used' || d.result === 'closed') html = page('Already changed', `<h1>This visit has already been moved or cancelled</h1>`);\nelse html = page('Link expired', `<h1>This link has expired</h1><p>Ask Nora in the app for a new one, or call your clinic.</p>`);\nreturn [{ json: { html } }];\n" }, position: [440, 240] },
});
const sendDone = node({
  type: 'n8n-nodes-base.respondToWebhook', version: 1.5,
  config: { name: 'Send result page', parameters: { respondWith: 'text', responseBody: expr('{{ $json.html }}'), options: { responseHeaders: { entries: [
        { name: 'Content-Type', value: 'text/html; charset=utf-8' },
        { name: 'Cache-Control', value: 'no-store' },
        { name: 'Referrer-Policy', value: 'no-referrer' },
        { name: 'Content-Security-Policy', value: "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; base-uri 'none'; frame-ancestors 'none'" },
      ] } } }, position: [660, 240] },
});

export default workflow('northgate-w15', 'W15 Reschedule link')
  .add(openLink).to(options).to(showPage).to(sendPage)
  .add(press).to(move).to(donePage).to(sendDone)
  .group('Show free times', [options, showPage, sendPage], { description: 'GET only reads: mail scanners open links, so opening one must never move a visit.' })
  .group('Move it', [move, donePage, sendDone], { description: 'POST from the button: move_by_token books the new time and cancels the old one in one step, once.' });
