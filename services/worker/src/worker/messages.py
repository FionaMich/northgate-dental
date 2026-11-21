"""What each patient message says. Minimal by design: first name, service, date, time, clinic and its phone number.
No surname, no clinical detail, no link that identifies the patient (Meta and email providers sign no BAA)."""

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
    amount_cents: int | None = None  # receipts only


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


def render(kind: str, ctx: Context) -> Message:
    clinic = f"Northgate Dental, {ctx.clinic_name}"
    call = f"Call us on {ctx.clinic_phone}." if ctx.clinic_phone else "Call your clinic."
    lead = {
        "confirmation": ("Your visit is booked", f"Your {ctx.service_name} is booked for {when(ctx)} at {clinic}."),
        "cancellation": ("Your visit is cancelled", f"Your {ctx.service_name} on {when(ctx)} at {clinic} is cancelled."),
        "reminder:72h": ("Your visit is in 3 days", f"A reminder: your {ctx.service_name} is on {when(ctx)} at {clinic}."),
        "reminder:24h": ("Your visit is tomorrow", f"A reminder: your {ctx.service_name} is tomorrow, {when(ctx)}, at {clinic}."),
        "reminder:6h": ("Your visit is today", f"A reminder: your {ctx.service_name} is today, {when(ctx)}, at {clinic}."),
    }
    if ctx.amount_cents is not None:
        dollars = f"${ctx.amount_cents // 100:,}.{ctx.amount_cents % 100:02d}"
        lead["receipt"] = ("Payment received", f"We received your payment of {dollars} for your {ctx.service_name} on "
                                               f"{when(ctx)} at {clinic}. Thank you.")
    subject, body = lead[kind]
    after = call if kind == "receipt" else "To change or cancel, open the Northgate Dental app. " + call
    text = f"Hello {ctx.first_name},\n\n{body}\n\n{after}\n\nNorthgate Dental\n"
    html = (
        '<div style="font-family:system-ui,sans-serif;max-width:520px;margin:auto;color:#0b2b2a">'
        '<p style="font-size:20px;font-weight:700;margin:0 0 4px">Northgate <span style="color:#137c6c">Dental</span></p>'
        '<p style="font-size:12px;letter-spacing:.15em;color:#4c6361;margin:0 0 24px">BACK BAY · CAMBRIDGE · QUINCY</p>'
        f"<p>Hello {escape(ctx.first_name)},</p><p>{escape(body)}</p><p>{escape(after)}</p></div>"
    )
    return Message(subject, text, html)
