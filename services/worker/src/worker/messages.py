"""What each patient message says. Minimal by design: first name, service, date, time, clinic and its phone number,
and at most one link: a single-use token that names nobody (cancel, check-in or pay).
No surname, no clinical detail, no record number (Meta and email providers sign no BAA)."""

from dataclasses import dataclass
from datetime import datetime
from html import escape
from zoneinfo import ZoneInfo


@dataclass(frozen=True)
class Context:
    first_name: str
    starts_at: datetime
    time_zone: str
    clinic_name: str
    clinic_phone: str | None
    service_name: str
    amount_cents: int | None = None             # receipts and statements
    link: str | None = None                     # cancel, check-in or pay link
    previous_starts_at: datetime | None = None  # a moved visit: the time it moved from


@dataclass(frozen=True)
class Message:
    subject: str
    text: str
    html: str


@dataclass(frozen=True)
class Promotion:
    """A marketing email: the same for every recipient except the first name. Never about anyone's treatment."""
    subject: str
    preheader: str
    headline: str
    body: str
    offer: str
    cta_label: str
    cta_link: str
    ends: str


def decide(event: dict) -> str | None:
    """Which send an appointment event asks for, if any."""
    to, frm = event["to_status"], event.get("from_status")
    if to == "booked" and frm in (None, "held"):
        return "confirmation"
    if to == "cancelled" and frm == "booked":
        return "cancellation"
    return None


def when(ctx: Context, at: datetime | None = None) -> str:
    local = (at or ctx.starts_at).astimezone(ZoneInfo(ctx.time_zone))
    return f"{local:%A} {local.day} {local:%B} at {local:%H:%M}"


def phone_label(phone: str) -> str:
    """+16175550130 reads as (617) 555-0130; anything else is shown as stored."""
    d = phone.removeprefix("+1")
    return f"({d[:3]}) {d[3:6]}-{d[6:]}" if len(d) == 10 and d.isdigit() else phone


def dollars(cents: int) -> str:
    return f"${cents // 100:,}.{cents % 100:02d}"


def render(kind: str, ctx: Context) -> Message:
    """Subjects carry the day and time, never the treatment (they show on lock screens); the body has the minimum."""
    e, name, at = escape, ctx.first_name, when(ctx)
    where = f"Northgate Dental, {ctx.clinic_name}"
    details = [("When", at), ("Where", where), ("For", ctx.service_name)]
    manage = ("Change or cancel", ctx.link) if ctx.link else None
    no_link = "To change or cancel, open the Northgate Dental app."
    if kind == "confirmation":
        subject, pre = f"You're booked: {at}", f"Your {ctx.service_name} at {ctx.clinic_name} is confirmed."
        eyebrow, headline = "Visit confirmed", f"You're booked, {name}"
        intro, cta, note = f"Your {ctx.service_name} is confirmed. We'll send a reminder before the day.", manage, \
            "Please arrive 10 minutes early and bring your dental plan card if you have one."
    elif kind.startswith("reminder:"):
        lead = {"72h": ("In 3 days", f"See you in 3 days, {name}"), "24h": ("Tomorrow", f"See you tomorrow, {name}"),
                "6h": ("Today", f"See you today, {name}")}[kind.split(":")[1]]
        subject, pre = f"{lead[0]}: your visit on {at}", f"Your {ctx.service_name} at {ctx.clinic_name}. Can't make it? Change it in a tap."
        eyebrow, headline = "Visit reminder", lead[1]
        intro, cta, note = f"A friendly reminder of your {ctx.service_name}.", manage, \
            "Can't make it? Changing your visit frees the time for another patient."
    elif kind == "reschedule":
        was = when(ctx, ctx.previous_starts_at) if ctx.previous_starts_at else None
        subject, pre = f"Your visit has moved to {at}", f"Your {ctx.service_name} is now {at}."
        eyebrow, headline = "Visit moved", f"All set, {name}: your visit has moved"
        intro, cta, note = f"Your {ctx.service_name} is now on the new time below. The old time is released.", manage, None
        details = ([("Was", was)] if was else []) + [("Now", at), ("Where", where), ("For", ctx.service_name)]
    elif kind == "cancellation":
        subject, pre = f"Your visit on {at} is cancelled", "Book again whenever suits you, it takes under a minute."
        eyebrow, headline = "Visit cancelled", f"Your visit is cancelled, {name}"
        intro, cta, note = f"We've cancelled your {ctx.service_name}. Nothing else is needed from you.", None, \
            "Whenever you're ready, book again in the Northgate Dental app in under a minute."
    elif kind == "receipt":
        amount = dollars(ctx.amount_cents)
        subject, pre = f"Receipt: {amount} paid to Northgate Dental", "Thank you. Your receipt is attached as a PDF."
        eyebrow, headline = "Payment received", f"Thank you, {name}"
        intro, cta, note = f"We received your payment of {amount}. Your receipt is attached for your records, dental plan or HSA.", \
            None, "Card payments are processed by Stripe; Northgate Dental never sees your card number."
        details = [("Paid", amount), ("Visit", at), ("Where", where), ("For", ctx.service_name)]
    elif kind.startswith("checkin:"):
        subject, pre = f"How are you feeling, {name}?", "Two quick questions about your recovery. It takes a few seconds."
        eyebrow, headline = "Checking in", f"How are you feeling, {name}?"
        intro = f"We hope you're recovering well after your {ctx.service_name}. Tell us how you are; a clinician reads every answer."
        cta, note, details = ("Tell us how you are", ctx.link) if ctx.link else None, None, [("Visit", at), ("Where", where)]
    elif kind.startswith("statement:"):
        amount = dollars(ctx.amount_cents)
        subject, pre = f"Your balance of {amount} is ready to pay", "Pay securely in a minute with card, Apple Pay or Google Pay."
        eyebrow, headline = "Your balance", f"{amount} to pay, {name}"
        intro, cta, note = f"Your balance for your {ctx.service_name} is still open. You can pay securely online.", \
            ("Pay securely", ctx.link) if ctx.link else None, None
        details = [("Balance", amount), ("Visit", at), ("Where", where)]
    else:
        raise KeyError(kind)

    call = f"Call {ctx.clinic_name} on {phone_label(ctx.clinic_phone)}." if ctx.clinic_phone else "Call your clinic."
    urgent = ("If you have bleeding that will not stop, swelling that spreads, a fever, or trouble breathing or "
              f"swallowing, do not wait for us to reply: {call} In an emergency call 911.") if kind.startswith("checkin:") else None
    lines = [f"Hello {name},", intro, "\n".join(f"{k}: {v}" for k, v in details)]
    lines += [f"{cta[0]}: {cta[1]}"] if cta else ([no_link] if kind == "confirmation" or kind.startswith("reminder:")
                                                 or kind == "reschedule" else [])
    lines += [x for x in (note, urgent) if x] + [f"Questions? {call}", "Northgate Dental"]
    text = "\n\n".join(lines) + "\n"

    show_tile = kind != "receipt" and not kind.startswith("statement:")
    rows = "".join(
        f'<tr><td style="padding:10px 0;border-top:1px solid #E3ECEA;width:84px;color:#5B706E;font-size:14px;vertical-align:top">'
        f'{e(k)}</td><td class="ink" style="padding:10px 0;border-top:1px solid #E3ECEA;color:#0B2B2A;font-size:16px;'
        f'font-weight:600;{"text-decoration:line-through;color:#8A9C9A;font-weight:400;" if k == "Was" else ""}">{e(v)}</td></tr>'
        for k, v in details if not (show_tile and k in ("When", "Now", "Visit")))  # the tile already shows the time
    local = ctx.starts_at.astimezone(ZoneInfo(ctx.time_zone))
    tile = (f'<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 18px"><tr>'
            f'<td width="64" align="center" style="width:64px;height:64px;border-radius:16px;background:#137C6C;color:#FFFFFF">'
            f'<div style="font-size:13px;line-height:16px;padding-top:9px">{local:%a}</div>'
            f'<div style="font-size:26px;line-height:30px;font-weight:800">{local.day}</div></td>'
            f'<td style="padding-left:16px"><div class="ink" style="font-size:22px;font-weight:800;color:#0B2B2A">{local:%H:%M}</div>'
            f'<div style="font-size:14px;color:#5B706E">{local:%A} {local.day} {local:%B} &middot; {e(ctx.clinic_name)}</div></td>'
            f'</tr></table>')
    body = (f'<p class="ink" style="margin:0 0 20px;font-size:16px;line-height:25px;color:#0B2B2A">{e(intro)}</p>'
            + (tile if show_tile else "") +
            f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="border-bottom:1px solid #E3ECEA">'
            f'{rows}</table>')
    if cta:
        body += _button(*cta)
    elif kind == "confirmation" or kind.startswith("reminder:") or kind == "reschedule":
        body += _p(no_link, top=22)
    if note:
        body += _p(note, top=18)
    if urgent:
        body += (f'<div style="margin-top:22px;padding:16px 18px;border-radius:14px;background:#FFF4F2;color:#7A271A;'
                 f'font-size:14px;line-height:21px">{e(urgent)}</div>')
    return Message(subject, text, _layout(pre, eyebrow, headline, body, ctx.clinic_name, ctx.clinic_phone))


def render_promotion(first_name: str, promo: Promotion, unsubscribe: str) -> Message:
    """A campaign email (only to patients who opted in to offers). Same frame as the service emails, plus unsubscribe."""
    e = escape
    text = (f"Hello {first_name},\n\n{promo.headline}\n\n{promo.body}\n\n{promo.offer}, until {promo.ends}.\n\n"
            f"{promo.cta_label}: {promo.cta_link}\n\nNorthgate Dental\n\nYou get offers because you said yes to them. "
            f"Unsubscribe: {unsubscribe}\n")
    body = (f'<p class="ink" style="margin:0 0 22px;font-size:16px;line-height:25px;color:#0B2B2A">{e(promo.body)}</p>'
            f'<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td style="padding:22px;'
            f'border-radius:16px;background:#E8F6F2;border:1px dashed #1FBFA2">'
            f'<p style="margin:0;font-size:22px;line-height:28px;font-weight:800;color:#0B2B2A">{e(promo.offer)}</p>'
            f'<p style="margin:6px 0 0;font-size:14px;color:#3E5654">Until {e(promo.ends)}, at all three clinics.</p>'
            f'</td></tr></table>' + _button(promo.cta_label, promo.cta_link))
    footer = (f'You get offers because you said yes to them. <a href="{e(unsubscribe)}" style="color:#5B706E;'
              f'text-decoration:underline">Unsubscribe</a> in one click.')
    return Message(promo.subject, text, _layout(promo.preheader, "For you", f"{first_name}, {promo.headline[0].lower()}"
                                                f"{promo.headline[1:]}", body, None, None, footer))


def _p(text: str, top: int = 0) -> str:
    return f'<p style="margin:{top}px 0 0;font-size:14px;line-height:21px;color:#5B706E">{escape(text)}</p>'


def _button(label: str, link: str) -> str:
    """A button that works in every client, Outlook included: a padded table cell, not a styled link alone."""
    return (f'<table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:26px"><tr>'
            f'<td style="border-radius:999px;background:#137C6C"><a href="{escape(link)}" style="display:inline-block;'
            f'padding:15px 30px;font-size:16px;font-weight:700;color:#FFFFFF;text-decoration:none;border-radius:999px">'
            f'{escape(label)}</a></td></tr></table>')


def _layout(preheader: str, eyebrow: str, headline: str, body: str, clinic: str | None, phone: str | None,
            footer: str | None = None) -> str:
    """The frame every patient email shares: inbox preview, brand band, card, help line, footer. Self-contained:
    system fonts and no images, so nothing is fetched and nothing breaks when images are blocked."""
    e = escape
    help_line = (f'Questions? Call {e(clinic)} on <a href="tel:{e(phone)}" style="color:#137C6C;font-weight:700;'
                 f'text-decoration:none">{e(phone_label(phone))}</a>' if phone else "")
    footer = footer or "You get this email because you have a visit with us. Please don't reply with medical questions."
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light dark">
<meta name="supported-color-schemes" content="light dark"><title>{e(headline)}</title>
<style>
@media (max-width:620px){{.card{{width:100%!important;border-radius:0!important}}.px{{padding-left:24px!important;padding-right:24px!important}}h1{{font-size:26px!important;line-height:32px!important}}}}
@media (prefers-color-scheme:dark){{.bg{{background:#06201F!important}}.card{{background:#0E2F2D!important}}.ink{{color:#EAF4F2!important}}}}
</style></head>
<body style="margin:0;padding:0;background:#EEF3F2">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent">{e(preheader)}&#8199;&#847;&#8199;&#847;&#8199;&#847;</div>
<table role="presentation" class="bg" width="100%" cellpadding="0" cellspacing="0" style="background:#EEF3F2;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif">
<tr><td align="center" style="padding:32px 12px">
<table role="presentation" class="card" width="600" cellpadding="0" cellspacing="0" style="width:600px;max-width:600px;background:#FFFFFF;border-radius:24px;overflow:hidden">
<tr><td class="px" style="background:#0B2B2A;padding:30px 44px 34px">
<p style="margin:0;font-size:19px;font-weight:800;color:#FFFFFF;letter-spacing:-0.2px">Northgate <span style="color:#1FBFA2">Dental</span></p>
<p style="margin:3px 0 30px;font-size:12px;color:#A9DCD1">Back Bay &middot; Cambridge &middot; Quincy</p>
<p style="margin:0 0 8px;font-size:14px;font-weight:700;color:#1FBFA2">{e(eyebrow)}</p>
<h1 style="margin:0;font-size:30px;line-height:36px;font-weight:800;color:#FFFFFF;letter-spacing:-0.5px">{e(headline)}</h1>
</td></tr>
<tr><td class="px" style="padding:34px 44px 8px">{body}</td></tr>
{f'<tr><td class="px" style="padding:26px 44px 34px"><p class="ink" style="margin:0;padding-top:22px;border-top:1px solid #E3ECEA;font-size:15px;line-height:22px;color:#0B2B2A">{help_line}</p></td></tr>' if help_line else '<tr><td style="height:30px"></td></tr>'}
</table>
<p style="margin:20px 0 0;max-width:520px;font-size:12px;line-height:18px;color:#6B7F7D">{footer}<br>Northgate Dental &middot; Back Bay, Cambridge and Quincy, Massachusetts</p>
</td></tr></table></body></html>"""


def receipt_document(ctx: Context, receipt_number: str, paid_on: str) -> str:
    """A printable receipt (letter size) for the PDF renderer: the same minimum as the email, laid out as a document.
    Self-contained: no fonts, images or scripts to fetch."""
    e = escape
    return f"""<!doctype html><html><head><meta charset="utf-8"><style>
body{{font-family:Helvetica,Arial,sans-serif;color:#0b2b2a;margin:0}}
.top{{display:flex;justify-content:space-between;align-items:flex-start;border-bottom:3px solid #137c6c;padding-bottom:18px}}
.brand{{font-size:26px;font-weight:700}}.brand span{{color:#137c6c}}.sub{{font-size:10px;letter-spacing:.18em;color:#4c6361;margin-top:4px}}
h1{{font-size:14px;letter-spacing:.2em;color:#4c6361;margin:0;text-align:right}}.num{{text-align:right;font-size:12px;margin-top:6px}}
table{{width:100%;border-collapse:collapse;margin-top:36px;font-size:13px}}th{{text-align:left;color:#4c6361;font-weight:600;
border-bottom:1px solid #d6e3e0;padding:8px 0}}td{{padding:12px 0;border-bottom:1px solid #eef3f2}}.r{{text-align:right}}
.total td{{font-size:16px;font-weight:700;border-bottom:0;padding-top:18px}}.paid{{display:inline-block;margin-top:28px;padding:6px 12px;
border-radius:999px;background:#e6f6f2;color:#137c6c;font-weight:700;font-size:12px}}.foot{{margin-top:60px;font-size:11px;color:#4c6361;line-height:1.6}}
</style></head><body>
<div class="top"><div><div class="brand">Northgate <span>Dental</span></div><div class="sub">BACK BAY · CAMBRIDGE · QUINCY</div></div>
<div><h1>RECEIPT</h1><div class="num">No. {e(receipt_number)}<br>Paid {e(paid_on)}</div></div></div>
<p style="margin-top:28px;font-size:13px">Received from {e(ctx.first_name)}, with thanks.</p>
<table><tr><th>Description</th><th>Visit</th><th class="r">Amount</th></tr>
<tr><td>{e(ctx.service_name)}</td><td>{e(when(ctx))}, {e(ctx.clinic_name)}</td><td class="r">{e(dollars(ctx.amount_cents))}</td></tr>
<tr class="total"><td colspan="2">Total paid (USD)</td><td class="r">{e(dollars(ctx.amount_cents))}</td></tr></table>
<span class="paid">PAID BY CARD</span>
<div class="foot">Northgate Dental, {e(ctx.clinic_name)}{" · " + e(ctx.clinic_phone) if ctx.clinic_phone else ""}<br>
Card payments are processed by Stripe; Northgate Dental never sees your card number.<br>
Keep this receipt for your records or a claim to your dental plan or HSA.</div>
</body></html>"""


def render_order(first_name: str, lines: list[str], total_cents: int | None, fulfilment: str, clinic_name: str,
                 clinic_phone: str | None, refill: bool) -> Message:
    """Order confirmation from the shop: what was bought, the total and how it arrives. Product names only."""
    clinic = f"Northgate Dental, {clinic_name}"
    subject = "Your refill is on its way" if refill and fulfilment == "ship" else (
        "Your refill is ready to collect" if refill else "Thank you for your order")
    arrive = (f"We will set it aside at {clinic}: collect it at your next visit, or any time we are open."
              if fulfilment == "collect" else "We will ship it within 2 working days; it arrives in 3 to 5 days.")
    items = "\n".join(f"  {line}" for line in lines)
    total = f"Total paid, including sales tax: {dollars(total_cents)}." if total_cents else ""
    call = f"Questions? Call us on {clinic_phone}." if clinic_phone else "Questions? Call your clinic."
    text = f"Hello {first_name},\n\nThank you for your order:\n{items}\n\n{total}\n\n{arrive}\n\n{call}\n\nNorthgate Dental\n"
    rows = "".join(f'<li style="margin:4px 0">{escape(line)}</li>' for line in lines)
    html = (
        '<div style="font-family:system-ui,sans-serif;max-width:520px;margin:auto;color:#0b2b2a">'
        '<p style="font-size:20px;font-weight:700;margin:0 0 4px">Northgate <span style="color:#137c6c">Dental</span></p>'
        '<p style="font-size:12px;letter-spacing:.15em;color:#4c6361;margin:0 0 24px">BACK BAY · CAMBRIDGE · QUINCY</p>'
        f"<p>Hello {escape(first_name)},</p><p>Thank you for your order:</p><ul>{rows}</ul>"
        f"<p><strong>{escape(total)}</strong></p><p>{escape(arrive)}</p><p>{escape(call)}</p></div>"
    )
    return Message(subject, text, html)


def render_alert(clinic_name: str, checkin_id: str) -> Message:
    """To the clinic, not the patient: a check-in needs a clinician. IDs only; the answer itself is in the portal."""
    body = (f"A patient's post-visit check-in at {clinic_name} needs a clinician today. Open the task list in the "
            f"Northgate portal (check-in {checkin_id}).")
    return Message("Check-in needs follow-up", body + "\n", f'<p style="font-family:system-ui,sans-serif">{escape(body)}</p>')
