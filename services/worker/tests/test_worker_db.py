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
    assert [(to, m.subject) for to, m, _ in sender.sent] == [("fiona.test@example.com", "Your visit is booked")]
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
