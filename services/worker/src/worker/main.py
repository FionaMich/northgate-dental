"""The notification worker. Reads two queues in small batches, one message per transaction:

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

from .messages import Context, decide, render
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


def handle_notification(conn, msg: dict, sender) -> None:
    request = msg["message"]
    appointment = request["appointment_id"]
    kind = request["type"] if request["type"] != "reminder" else f"reminder:{request['kind']}"
    ctx = conn.execute("select * from private.notification_context(%s)", (appointment,)).fetchone()
    wanted = "cancelled" if kind == "cancellation" else "booked"
    if ctx is None or ctx["status"] != wanted:
        log(event="skipped", reason="status changed", kind=kind, appointment_id=appointment)
    elif not ctx["email"]:
        log(event="skipped", reason="no app sign-in email", kind=kind, appointment_id=appointment)
    else:
        claimed = conn.execute(
            """insert into private.notification_log (appointment_id, patient_id, kind, channel, template)
               values (%s, %s, %s, 'email', %s) on conflict do nothing returning id""",
            (appointment, ctx["patient_id"], kind, f"{kind}.v1")).fetchone()
        if claimed:
            message = render(kind, Context(ctx["first_name"], ctx["starts_at"], ctx["time_zone"], ctx["clinic_name"],
                                           ctx["clinic_phone"], ctx["service_name"]))
            provider_id = sender.send(ctx["email"], message, idempotency_key=f"{appointment}:{kind}:email")
            conn.execute("update private.notification_log set status = 'sent', provider_message_id = %s, updated_at = now() "
                         "where id = %s", (provider_id, claimed["id"]))
            log(event="sent", kind=kind, channel="email", appointment_id=appointment, log_id=claimed["id"])
        else:
            log(event="duplicate", kind=kind, appointment_id=appointment)
    archive(conn, "notifications", msg["msg_id"])


def run_once(conn, sender) -> int:
    """One pass over both queues; returns how many messages were handled. Each message commits on its own."""
    handled = 0
    for queue, handler in (("events", lambda c, m: handle_event(c, m)),
                           ("notifications", lambda c, m: handle_notification(c, m, sender))):
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
    with psycopg.connect(os.environ["WORKER_DB_URL"], row_factory=dict_row, autocommit=True) as conn:
        log(event="started")
        while not stop:
            if run_once(conn, sender) == 0:
                time.sleep(2)
    log(event="stopped")
    sys.exit(0)
