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
    amount_cents: int | None = None  # receipts and statements
    link: str | None = None          # cancel, check-in or pay link


@dataclass(frozen=True)
class Message:
    subject: str
    text: str
    html: str


def decide(event: dict) -> str | None:
    """Which send an appointment event asks for, if any."""
    to, frm = event["to_status"], event.get("from_status")
    if to == "booked" and frm in (None, "held"):
        return "confirmation"
    if to == "cancelled" and frm == "booked":
        return "cancellation"
    return None


def when(ctx: Context) -> str:
    local = ctx.starts_at.astimezone(ZoneInfo(ctx.time_zone))
    return f"{local:%A} {local.day} {local:%B} at {local:%H:%M}"


def dollars(cents: int) -> str:
    return f"${cents // 100:,}.{cents % 100:02d}"


def render(kind: str, ctx: Context) -> Message:
    clinic = f"Northgate Dental, {ctx.clinic_name}"
    call = f"Call us on {ctx.clinic_phone}." if ctx.clinic_phone else "Call your clinic."
    visit = f"your {ctx.service_name} on {when(ctx)} at {clinic}"
    cancel = f"Need to cancel? Use this link: {ctx.link} " if ctx.link else "To change or cancel, open the Northgate Dental app. "
    if kind.startswith("reminder:") or kind == "confirmation":
        lead = {
            "confirmation": ("Your visit is booked", f"Your {ctx.service_name} is booked for {when(ctx)} at {clinic}."),
            "reminder:72h": ("Your visit is in 3 days", f"A reminder: your {ctx.service_name} is on {when(ctx)} at {clinic}."),
            "reminder:24h": ("Your visit is tomorrow", f"A reminder: your {ctx.service_name} is tomorrow, {when(ctx)}, at {clinic}."),
            "reminder:6h": ("Your visit is today", f"A reminder: your {ctx.service_name} is today, {when(ctx)}, at {clinic}."),
        }[kind]
        after = cancel + call
    elif kind == "cancellation":
        lead = ("Your visit is cancelled", f"Your {ctx.service_name} on {when(ctx)} at {clinic} is cancelled.")
        after = "To book again, open the Northgate Dental app. " + call
    elif kind == "receipt":
        lead = ("Payment received", f"We received your payment of {dollars(ctx.amount_cents)} for {visit}. Thank you.")
        after = call
    elif kind.startswith("checkin:"):
        lead = ("How are you feeling?", f"We hope you are recovering well after {visit}. "
                                        f"Tell us how you are, it takes a few seconds: {ctx.link}")
        after = ("If you have bleeding that will not stop, swelling that spreads, a fever, or trouble breathing or "
                 f"swallowing, do not wait for us to reply: {call} In an emergency call 911.")
    elif kind.startswith("statement:"):
        lead = ("Your balance with Northgate Dental", f"Your balance of {dollars(ctx.amount_cents)} for {visit} is still "
                                                      f"open. You can pay securely here: {ctx.link}")
        after = "Questions about your bill? " + call
    else:
        raise KeyError(kind)
    subject, body = lead
    text = f"Hello {ctx.first_name},\n\n{body}\n\n{after}\n\nNorthgate Dental\n"
    html = (
        '<div style="font-family:system-ui,sans-serif;max-width:520px;margin:auto;color:#0b2b2a">'
        '<p style="font-size:20px;font-weight:700;margin:0 0 4px">Northgate <span style="color:#137c6c">Dental</span></p>'
        '<p style="font-size:12px;letter-spacing:.15em;color:#4c6361;margin:0 0 24px">BACK BAY · CAMBRIDGE · QUINCY</p>'
        f"<p>Hello {escape(ctx.first_name)},</p><p>{_linked(body, ctx.link)}</p><p>{_linked(after, ctx.link)}</p></div>"
    )
    return Message(subject, text, html)


def _linked(text: str, link: str | None) -> str:
    """Escapes the text and turns the link, if present, into an anchor."""
    if not link or link not in text:
        return escape(text)
    before, after = text.split(link, 1)
    return f'{escape(before)}<a href="{escape(link)}" style="color:#137c6c">{escape(link)}</a>{escape(after)}'


def render_alert(clinic_name: str, checkin_id: str) -> Message:
    """To the clinic, not the patient: a check-in needs a clinician. IDs only; the answer itself is in the portal."""
    body = (f"A patient's post-visit check-in at {clinic_name} needs a clinician today. Open the task list in the "
            f"Northgate portal (check-in {checkin_id}).")
    return Message("Check-in needs follow-up", body + "\n", f'<p style="font-family:system-ui,sans-serif">{escape(body)}</p>')
