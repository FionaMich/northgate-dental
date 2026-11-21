"""Puts each workflow's two sticky notes in a strip above its nodes, so they never cover one.
Run after exporting a workflow: python3 n8n/add_notes.py (idempotent: notes are replaced, not duplicated)."""
import json
import pathlib
import uuid

NOTES = {
    "w03-cancel-link": (
        "## W03 Cancel link\n**Trigger:** a patient opens the cancel link in a confirmation or reminder email.\n\n"
        "**Top row (GET):** shows the visit only. Mail scanners open links, so opening one must never cancel.\n\n"
        "**Bottom row (POST):** the button. `cancel_by_token()` applies the clinic's cancellation window and works once. "
        "The outbox then sends the cancellation email.",
        "## Security and data\n- The link is a random token; the database stores only its SHA-256 hash.\n"
        "- The page shows service, time and clinic: never the patient's name (links get forwarded).\n"
        "- Database login: `northgate_actions_app`, which can call four functions and read no table.\n"
        "- Failed runs keep no data.",
    ),
    "w04-payment-link": (
        "## W04 Payment link\n**Trigger:** called by W06, the app (through W06) or, later, the assistant.\n\n"
        "1. `open_payment()` takes the price from the clinic's price list, never from the caller.\n"
        "2. Stripe Checkout Session, with the payment ID as the idempotency key (asking twice gives the same link).\n"
        "3. The session ID is stored so W05 can match Stripe's webhook.",
        "## Security and data\n- Stripe receives an amount, a generic item name and our payment ID: no name, email or service.\n"
        "- Adaptive Pricing is off: always USD.\n- Stripe key: n8n credential `Stripe test mode` (encrypted in n8n, never in this JSON).\n"
        "- Database login: `northgate_payments_app`, three functions only.",
    ),
    "w05-stripe-payment-received": (
        "## W05 Stripe payment received\n**Trigger:** Stripe's webhook `POST /webhook/stripe`.\n\n"
        "n8n only relays: the raw body and `Stripe-Signature` header go to `record_stripe_event()`, which checks the HMAC, "
        "refuses events older than 5 minutes, ignores repeats, checks the amount, marks the payment paid and queues the receipt.\n\n"
        "**Answers:** 200 `recorded`, `duplicate` or `ignored`; 400 for anything refused.",
        "## Security and data\n- The signing secret is in Supabase Vault, loaded by GitHub Actions; never in n8n or Git.\n"
        "- The raw body is passed byte for byte; reformatting it would break the signature.\n"
        "- Failed runs keep no data: a Stripe event can carry the payer's email.",
    ),
    "w06-pay-link": (
        "## W06 Pay link\n**Trigger:** a patient opens the pay link in a statement reminder (days 0, 14, 28) or taps Pay in the app.\n\n"
        "An open balance runs W04 and redirects (303) to Stripe Checkout. A paid or expired link gets a plain page.",
        "## Security and data\n- `payment_for_token()` returns only the state and the visit ID.\n"
        "- The amount is never in the link; W04 reads it from the price list.\n- Database login: `northgate_actions_app`.",
    ),
    "w11-post-visit-checkin": (
        "## W11 Post-visit check-in\n**Trigger:** the check-in link sent at 10:00 clinic time on days 1 and 3 after a visit.\n\n"
        "**Top row (GET):** the question, with the emergency path on the page itself.\n\n"
        "**Bottom row (POST):** `record_checkin()` screens the note for red flags with fixed rules. A concern or a flag opens a "
        "staff task and goes on the `urgent` queue; the worker alerts the clinic at once.",
        "## Security and data\n- No AI model reads the note: red flags skip the model (project rule).\n"
        "- The note stays in Postgres under row level security; the alert email carries IDs only.\n"
        "- A red flag tells the patient to call now, or 911.\n- Failed runs keep no data.",
    ),
}
WIDTH, HEIGHT, GAP = 460, 300, 60

for path in sorted(pathlib.Path(__file__).parent.joinpath("workflows").glob("*.json")):
    data = json.loads(path.read_text())
    wf = data[0] if isinstance(data, list) else data
    if path.stem not in NOTES:
        continue
    wf["nodes"] = [n for n in wf["nodes"] if n["type"] != "n8n-nodes-base.stickyNote"]
    left = min(n["position"][0] for n in wf["nodes"]) - 40
    top = min(n["position"][1] for n in wf["nodes"]) - HEIGHT - GAP - 40   # above every node, with a clear gap
    for i, (content, color) in enumerate(zip(NOTES[path.stem], (4, 3))):
        wf["nodes"].append({
            "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"{path.stem}-note-{i}")), "name": f"Note {i + 1}",
            "type": "n8n-nodes-base.stickyNote", "typeVersion": 1,
            "position": [left + i * (WIDTH + 40), top],
            "parameters": {"content": content, "width": WIDTH, "height": HEIGHT, "color": color},
        })
    path.write_text(json.dumps(data, indent=2) + "\n")
    print("notes added:", path.name)
