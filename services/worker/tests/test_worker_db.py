"""Against a real database (the local Supabase stack), inside one transaction that is rolled back: book a visit for the
canary patient, run the worker, check exactly one email, a second run sends nothing, and the logs hold no canary."""

import os
from pathlib import Path

import psycopg
import pytest
from psycopg.rows import dict_row

from worker.main import run_once
from worker.senders import FakeSender

DB = os.environ.get("WORKER_TEST_DB_URL", "postgresql://postgres:postgres@127.0.0.1:54322/postgres")
CANARY = Path(__file__).parents[3] / "services/synthdata/src/synthdata/canary.txt"
USER = "10000000-0000-4000-8000-000000000099"


@pytest.fixture
def conn():
    try:
        c = psycopg.connect(DB, row_factory=dict_row, connect_timeout=3)
    except psycopg.OperationalError:
        pytest.skip("no local database")
    yield c
    c.rollback()
    c.close()


def test_one_booking_sends_one_confirmation_and_logs_no_canary(conn, capsys):
    conn.execute("insert into auth.users (id, email, aud, role, email_confirmed_at) values (%s, 'fiona.test@example.com',"
                 " 'authenticated', 'authenticated', now())", (USER,))
    conn.execute("insert into patient_links (profile_id, patient_id) values (%s, '30000000-0000-4000-8000-000000000099')", (USER,))
    conn.execute("""insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
        select '30000000-0000-4000-8000-000000000099', l.id, pr.id, s.id, '2027-04-07 14:00+00', '2027-04-07 15:00+00', 'booked'
        from locations l, practitioners pr, services s
        where l.code = 'quincy' and pr.profile_id = '10000000-0000-4000-8000-000000000013' and s.code = 'D1110'""")
    sender = FakeSender()

    run_once(conn, sender)   # the event becomes a confirmation request
    run_once(conn, sender)   # the request is sent
    run_once(conn, sender)   # nothing left
    assert [(to, m.subject) for to, m, _ in sender.sent] == [("fiona.test@example.com", "You're booked: Wednesday 7 April at 10:00")]
    assert "Zyxwq" in sender.sent[0][1].text

    conn.execute("select pgmq.send('notifications', jsonb_build_object('type', 'confirmation', 'appointment_id', "
                 "(select id from appointments where patient_id = '30000000-0000-4000-8000-000000000099' "
                 "and starts_at = '2027-04-07 14:00+00')))")
    run_once(conn, sender)
    assert len(sender.sent) == 1, "a repeated request must not send a second email"

    logs = capsys.readouterr().out
    assert '"event": "sent"' in logs and '"event": "duplicate"' in logs
    for value in CANARY.read_text().split():
        assert value not in logs, "no canary value may reach the logs"


def test_a_paid_visit_sends_one_receipt_with_the_amount(conn):
    import hashlib, hmac, json, time
    conn.execute("insert into auth.users (id, email, aud, role, email_confirmed_at) values (%s, 'fiona.test@example.com',"
                 " 'authenticated', 'authenticated', now())", (USER,))
    conn.execute("insert into patient_links (profile_id, patient_id) values (%s, '30000000-0000-4000-8000-000000000099')", (USER,))
    appointment = conn.execute("""insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
        select '30000000-0000-4000-8000-000000000099', l.id, pr.id, s.id, '2027-04-08 14:00+00', '2027-04-08 15:00+00', 'booked'
        from locations l, practitioners pr, services s
        where l.code = 'quincy' and pr.profile_id = '10000000-0000-4000-8000-000000000013' and s.code = 'D1110'
        returning id""").fetchone()["id"]
    payment = conn.execute("select * from private.open_payment(%s)", (appointment,)).fetchone()
    conn.execute("select private.attach_checkout(%s, 'cs_test_worker')", (payment["payment_id"],))
    conn.execute("delete from vault.secrets where name = 'stripe_webhook_secret'")  # rolled back with the test
    conn.execute("select vault.create_secret('whsec_pytest_only', 'stripe_webhook_secret')")
    body = json.dumps({"id": "evt_worker", "type": "checkout.session.completed", "data": {"object": {
        "id": "cs_test_worker", "payment_status": "paid", "amount_total": payment["amount_cents"], "currency": "usd",
        "payment_intent": "pi_worker"}}})
    t = int(time.time())
    signature = f"t={t},v1=" + hmac.new(b"whsec_pytest_only", f"{t}.{body}".encode(), hashlib.sha256).hexdigest()
    assert conn.execute("select private.record_stripe_event(%s, %s) as r", (body, signature)).fetchone()["r"] == "recorded"

    sender = FakeSender()
    for _ in range(3):
        run_once(conn, sender)
    receipts = [m for _, m, _ in sender.sent if m.subject.startswith("Receipt: ")]
    cents = payment["amount_cents"]
    assert len(receipts) == 1
    assert f"${cents // 100:,}.{cents % 100:02d}" in receipts[0].text


def test_a_worried_check_in_alerts_the_clinic_once_and_the_patient_email_has_a_check_in_link(conn):
    conn.execute("insert into auth.users (id, email, aud, role, email_confirmed_at) values (%s, 'fiona.test@example.com',"
                 " 'authenticated', 'authenticated', now())", (USER,))
    conn.execute("insert into patient_links (profile_id, patient_id) values (%s, '30000000-0000-4000-8000-000000000099')", (USER,))
    appointment = conn.execute("""insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
        select '30000000-0000-4000-8000-000000000099', l.id, pr.id, s.id, '2027-01-10 14:00+00', '2027-01-10 15:00+00', 'completed'
        from locations l, practitioners pr, services s
        where l.code = 'quincy' and pr.profile_id = '10000000-0000-4000-8000-000000000013' and s.code = 'D1110'
        returning id""").fetchone()["id"]
    assert conn.execute("select count(*) as n from private.claim_due_checkins('2027-01-11 15:30+00')").fetchone()["n"] == 1

    sender = FakeSender()
    run_once(conn, sender, link_base="https://n8n.example/webhook", alert_to="clinic@example.com")
    checkin_mail = [m for _, m, _ in sender.sent if m.subject.startswith("How are you feeling")]
    assert len(checkin_mail) == 1 and "https://n8n.example/webhook/checkin?t=" in checkin_mail[0].text

    token = checkin_mail[0].text.split("checkin?t=")[1].split()[0]
    flags = conn.execute("select red_flags from private.record_checkin(%s, 'concern', 'the bleeding will not stop')",
                         (token,)).fetchone()["red_flags"]
    assert flags == ["heavy_bleeding"]
    run_once(conn, sender, link_base="https://n8n.example/webhook", alert_to="clinic@example.com")
    run_once(conn, sender, link_base="https://n8n.example/webhook", alert_to="clinic@example.com")
    alerts = [(to, m) for to, m, _ in sender.sent if m.subject == "Check-in needs follow-up"]
    assert len(alerts) == 1 and alerts[0][0] == "clinic@example.com"
    assert "bleeding" not in alerts[0][1].text, "the alert carries IDs, never what the patient wrote"
    assert str(appointment)


def test_a_moved_visit_sends_one_moved_email_and_no_cancellation(conn):
    conn.execute("insert into auth.users (id, email, aud, role, email_confirmed_at) values (%s, 'fiona.test@example.com',"
                 " 'authenticated', 'authenticated', now())", (USER,))
    conn.execute("insert into patient_links (profile_id, patient_id) values (%s, '30000000-0000-4000-8000-000000000099')", (USER,))
    visit = """insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status, replaces)
        select '30000000-0000-4000-8000-000000000099', l.id, pr.id, s.id, %s, %s::timestamptz + interval '1 hour', 'booked', %s
        from locations l, practitioners pr, services s
        where l.code = 'quincy' and pr.profile_id = '10000000-0000-4000-8000-000000000013' and s.code = 'D1110' returning id"""
    old = conn.execute(visit, ("2027-04-07 14:00+00", "2027-04-07 14:00+00", None)).fetchone()["id"]
    sender = FakeSender()
    for _ in range(3):
        run_once(conn, sender)
    sender.sent.clear()

    # What reschedule_booking does in one transaction: the new visit, naming the old one, and the old one cancelled.
    conn.execute(visit, ("2027-04-08 13:00+00", "2027-04-08 13:00+00", old))
    conn.execute("update appointments set status = 'cancelled' where id = %s", (old,))
    for _ in range(3):
        run_once(conn, sender)
    assert [m.subject for _, m, _ in sender.sent] == ["Your visit has moved to Thursday 8 April at 09:00"]
    assert "Wednesday 7 April at 10:00" in sender.sent[0][1].text, "the email shows the time it moved from"
