"""The notification worker. Reads three queues in small batches, one message per transaction:

- urgent: check-ins that need a clinician; read first on every pass, an alert to the clinic at once.
- events: appointment changes from the outbox; a booking or cancellation asks for a send on the notifications queue.
- notifications: send requests; each is claimed in notification_log (one per appointment, kind and channel) before the
  email goes out, so a redelivered message never sends twice.

A message that fails five times moves to the dead_letter queue. Logs are JSON with IDs only."""

import json
import os
import signal
import sys
import time

import psycopg
from psycopg.rows import dict_row

import base64
from datetime import date

from .messages import Context, decide, receipt_document, render, render_alert
from .pdf import PdfError, render_pdf
from .senders import ResendSender, SendError

BATCH = 10          # fixed batch: the worker never takes more than it can finish (Addendum D)
VISIBILITY = 60     # seconds a read message stays hidden from other readers
MAX_TRIES = 5


def log(**fields) -> None:
    print(json.dumps({"time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), **fields}), flush=True)


def read(conn, queue: str) -> list[dict]:
    return conn.execute("select msg_id, read_ct, message from pgmq.read(%s, %s, %s)", (queue, VISIBILITY, BATCH)).fetchall()


def archive(conn, queue: str, msg_id: int) -> None:
    conn.execute("select pgmq.archive(%s, %s::bigint)", (queue, msg_id))


def dead_letter(conn, queue: str, msg: dict) -> None:
    conn.execute("select pgmq.send('dead_letter', %s)", (json.dumps({"queue": queue, "message": msg["message"]}),))
    archive(conn, queue, msg["msg_id"])
    log(event="dead_letter", queue=queue, msg_id=msg["msg_id"])


def handle_event(conn, msg: dict) -> None:
    event = msg["message"]
    key = f"appointment:{event['appointment_id']}:v{event['version']}"
    if conn.execute("select private.mark_processed('worker', %s) as first", (key,)).fetchone()["first"]:
        kind = decide(event)
        if kind:
            conn.execute("select pgmq.send('notifications', %s)", (json.dumps(
                {"type": kind, "appointment_id": event["appointment_id"]}),))
            log(event="queued", kind=kind, appointment_id=event["appointment_id"])
    archive(conn, "events", msg["msg_id"])


LINKS = {"cancel": "visit", "checkin": "checkin", "pay": "pay"}  # n8n webhook paths that serve each link's page


def link_for(conn, link_base: str, kind: str, appointment: str, request: dict) -> str | None:
    """A single-use link for the email, issued inside the send's transaction (a failed send discards it too)."""
    if not link_base:
        return None
    if kind == "confirmation" or kind.startswith("reminder:"):
        purpose, args = "cancel", (appointment, "cancel", None, None)
    elif kind.startswith("checkin:"):
        purpose, args = "checkin", (appointment, "checkin", request["kind"], None)
    elif kind.startswith("statement:"):
        purpose, args = "pay", (appointment, "pay", request["kind"], request["payment_id"])
    else:
        return None
    token = conn.execute("select private.issue_action_token(%s, %s, %s, %s) as t", args).fetchone()["t"]
    return f"{link_base}/{LINKS[purpose]}?t={token}"


def receipt_pdf(pdf_url: str, ctx: Context, payment_id: str) -> list[dict] | None:
    """The receipt as a PDF attachment; None if the renderer is unavailable (the email still goes, the log says so)."""
    if not pdf_url:
        return None
    try:
        pdf = render_pdf(pdf_url, receipt_document(ctx, payment_id[:8].upper(), f"{date.today():%d %B %Y}"))
    except PdfError as error:
        log(event="pdf_failed", detail=str(error)[:80])
        return None
    return [{"filename": "Northgate-Dental-receipt.pdf", "content": base64.b64encode(pdf).decode()}]


def handle_notification(conn, msg: dict, sender, link_base: str = "", pdf_url: str = "") -> None:
    request = msg["message"]
    appointment, kind_type = request["appointment_id"], request["type"]
    kind = kind_type if "kind" not in request else f"{kind_type}:{request['kind']}"
    ctx = conn.execute("select * from private.notification_context(%s)", (appointment,)).fetchone()
    wanted = {"cancellation": ("cancelled",), "receipt": ("booked", "arrived", "completed"),
              "checkin": ("completed",), "statement": ("completed",)}.get(kind_type, ("booked",))
    amount = None
    if kind_type in ("receipt", "statement"):
        fn = "receipt_amount" if kind_type == "receipt" else "balance_amount"
        amount = conn.execute(f"select private.{fn}(%s) as cents", (request["payment_id"],)).fetchone()["cents"]
    if ctx is None or ctx["status"] not in wanted or (kind_type in ("receipt", "statement") and amount is None):
        log(event="skipped", reason="status changed", kind=kind, appointment_id=appointment)
    elif not ctx["email"]:
        log(event="skipped", reason="no app sign-in email", kind=kind, appointment_id=appointment)
    else:
        claimed = conn.execute(
            """insert into private.notification_log (appointment_id, patient_id, kind, channel, template)
               values (%s, %s, %s, 'email', %s) on conflict do nothing returning id""",
            (appointment, ctx["patient_id"], kind, f"{kind}.v1")).fetchone()
        if claimed:
            link = link_for(conn, link_base, kind, appointment, request)
            context = Context(ctx["first_name"], ctx["starts_at"], ctx["time_zone"], ctx["clinic_name"],
                              ctx["clinic_phone"], ctx["service_name"], amount, link)
            attachments = receipt_pdf(pdf_url, context, request["payment_id"]) if kind == "receipt" else None
            provider_id = sender.send(ctx["email"], render(kind, context), idempotency_key=f"{appointment}:{kind}:email",
                                      attachments=attachments)
            conn.execute("update private.notification_log set status = 'sent', provider_message_id = %s, updated_at = now() "
                         "where id = %s", (provider_id, claimed["id"]))
            log(event="sent", kind=kind, channel="email", appointment_id=appointment, log_id=claimed["id"])
        else:
            log(event="duplicate", kind=kind, appointment_id=appointment)
    archive(conn, "notifications", msg["msg_id"])


def handle_urgent(conn, msg: dict, sender, alert_to: str | None) -> None:
    """Check-ins that need a clinician: an alert to the clinic's inbox at once, IDs only."""
    request = msg["message"]
    appointment, checkin = request["appointment_id"], request["checkin_id"]
    kind = f"alert:{checkin}"
    ctx = conn.execute("select clinic_name from private.notification_context(%s)", (appointment,)).fetchone()
    if not alert_to or ctx is None:
        log(event="skipped", reason="no clinic alert address", kind="alert", appointment_id=appointment)
    elif conn.execute("""insert into private.notification_log (appointment_id, kind, channel, template)
                         values (%s, %s, 'email', 'checkin_alert.v1') on conflict do nothing returning id""",
                      (appointment, kind)).fetchone():
        sender.send(alert_to, render_alert(ctx["clinic_name"], checkin), idempotency_key=f"{kind}:email")
        log(event="sent", kind="alert", channel="email", appointment_id=appointment)
    archive(conn, "urgent", msg["msg_id"])


def run_once(conn, sender, link_base: str = "", alert_to: str | None = None, pdf_url: str = "") -> int:
    """One pass over the queues, urgent first; returns how many messages were handled. Each commits on its own."""
    handled = 0
    for queue, handler in (("urgent", lambda c, m: handle_urgent(c, m, sender, alert_to)),
                           ("events", lambda c, m: handle_event(c, m)),
                           ("notifications", lambda c, m: handle_notification(c, m, sender, link_base, pdf_url))):
        with conn.transaction():
            messages = read(conn, queue)
        for msg in messages:
            try:
                with conn.transaction():
                    if msg["read_ct"] > MAX_TRIES:
                        dead_letter(conn, queue, msg)
                    else:
                        handler(conn, msg)
                handled += 1
            except (SendError, psycopg.Error, KeyError) as error:
                # left on the queue: it reappears after the visibility timeout and is retried
                log(event="failed", queue=queue, msg_id=msg["msg_id"], error=type(error).__name__, detail=str(error)[:80])
    return handled


def main() -> None:
    stop = False

    def request_stop(*_):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, request_stop)
    signal.signal(signal.SIGINT, request_stop)
    sender = ResendSender(os.environ["RESEND_API_KEY"], os.environ["EMAIL_FROM"], os.environ.get("EMAIL_REDIRECT_TO") or None)
    link_base = os.environ.get("LINK_BASE", "").rstrip("/")         # e.g. https://n8n.<domain>/webhook
    alert_to = os.environ.get("CLINIC_ALERT_EMAIL") or None         # the clinic inbox for urgent check-ins
    pdf_url = os.environ.get("PDF_URL", "").rstrip("/")             # the internal PDF renderer
    with psycopg.connect(os.environ["WORKER_DB_URL"], row_factory=dict_row, autocommit=True) as conn:
        log(event="started")
        while not stop:
            if run_once(conn, sender, link_base, alert_to, pdf_url) == 0:
                time.sleep(2)
    log(event="stopped")
    sys.exit(0)
