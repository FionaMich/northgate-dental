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


def test_care_check_ins_email_the_patient_once_and_an_emergency_alerts_the_clinic_once(conn, capsys):
    conn.execute("insert into auth.users (id, email, aud, role, email_confirmed_at) values (%s, 'fiona.test@example.com',"
                 " 'authenticated', 'authenticated', now())", (USER,))
    conn.execute("insert into patient_links (profile_id, patient_id) values (%s, '30000000-0000-4000-8000-000000000099')", (USER,))
    enrolment = conn.execute("""insert into care_enrolments (patient_id, location_id, programme, starts_on, ends_on, status, consent_at)
        select '30000000-0000-4000-8000-000000000099', l.id, 'post_procedure', current_date - 2, current_date + 3, 'active', now()
        from locations l where l.code = 'quincy' returning id""").fetchone()["id"]
    ten_thirty = "(current_date + time '10:30') at time zone 'America/New_York'"
    assert conn.execute(f"select private.claim_due_care({ten_thirty}) as n").fetchone()["n"] == 1
    sender = FakeSender()
    run_once(conn, sender, alert_to="clinic@example.com")
    run_once(conn, sender, alert_to="clinic@example.com")
    mail = [(to, m) for to, m, _ in sender.sent if m.subject == "Your recovery check-in for today"]
    assert len(mail) == 1 and mail[0][0] == "fiona.test@example.com"
    assert "Northgate app" in mail[0][1].text and "911" in mail[0][1].text

    checkin = conn.execute("select id from care_checkins where enrolment_id = %s", (enrolment,)).fetchone()["id"]
    for _ in range(2):   # the same alert delivered twice
        conn.execute("select pgmq.send('urgent', jsonb_build_object('type', 'care_alert', 'enrolment_id', %s::text, 'checkin_id', %s::text))",
                     (enrolment, checkin))
    run_once(conn, sender, alert_to="clinic@example.com")
    alerts = [(to, m) for to, m, _ in sender.sent if m.subject == "Care check-in needs a clinician"]
    assert len(alerts) == 1 and alerts[0][0] == "clinic@example.com" and str(checkin) in alerts[0][1].text

    logs = capsys.readouterr().out
    for value in CANARY.read_text().split():
        assert value not in logs, "no canary value may reach the logs"


def test_nora_s_links_email_once_a_day_and_the_reschedule_link_moves_the_visit(conn):
    """What n8n's send_payment_link and reschedule_link tools do, as the signed-in patient, then the worker's emails."""
    import re
    conn.execute("insert into auth.users (id, email, aud, role, email_confirmed_at) values (%s, 'fiona.test@example.com',"
                 " 'authenticated', 'authenticated', now())", (USER,))
    conn.execute("insert into patient_links (profile_id, patient_id) values (%s, '30000000-0000-4000-8000-000000000099')", (USER,))
    visit = conn.execute("""insert into appointments (patient_id, location_id, practitioner_id, service_id, starts_at, ends_at, status)
        select '30000000-0000-4000-8000-000000000099', l.id, pr.id, s.id, date_trunc('hour', now()) + interval '6 days',
               date_trunc('hour', now()) + interval '6 days 1 hour', 'booked'
        from locations l, practitioners pr, services s
        where l.code = 'quincy' and pr.profile_id = '10000000-0000-4000-8000-000000000013' and s.code = 'D1110'
        returning id""").fetchone()["id"]
    sender = FakeSender()
    run_once(conn, sender, link_base="https://n8n.example/webhook")
    sender.sent.clear()

    conn.execute("insert into auth.sessions (id, user_id) values (%s, %s) on conflict do nothing", (USER, USER))
    conn.execute("insert into private.verified_sessions (session_id, user_id) values (%s, %s) on conflict do nothing", (USER, USER))
    conn.execute("select set_config('request.jwt.claims', %s, true)",
                 (f'{{"sub": "{USER}", "role": "authenticated", "aal": "aal1", "session_id": "{USER}"}}',))
    conn.execute("set local role authenticated")
    for _ in range(2):   # asking Nora twice
        conn.execute("select public.send_my_payment_link(%s)", (visit,))
        conn.execute("select public.send_my_reschedule_link(%s)", (visit,))
    conn.execute("reset role")
    for _ in range(3):
        run_once(conn, sender, link_base="https://n8n.example/webhook")
    subjects = sorted(m.subject for _, m, _ in sender.sent)
    assert len(subjects) == 2 and subjects[0].startswith("Choose a new time") and subjects[1].startswith("Your payment link: $")
    move = next(m for _, m, _ in sender.sent if m.subject.startswith("Choose"))
    token = re.search(r"move\?t=([A-Za-z0-9_-]{32})", move.text).group(1)

    options = conn.execute("select options from private.reschedule_options(%s)", (token,)).fetchone()["options"]
    assert conn.execute("select private.move_by_token(%s, %s) as r", (token, options[0]["at"])).fetchone()["r"] == "moved"
    sender.sent.clear()
    for _ in range(3):
        run_once(conn, sender, link_base="https://n8n.example/webhook")
    assert [m.subject.split(" to ")[0] for _, m, _ in sender.sent] == ["Your visit has moved"], "one moved email, no cancellation"
