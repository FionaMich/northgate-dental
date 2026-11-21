from datetime import datetime, timezone

from worker.messages import Context, decide, render

CTX = Context("Ana", datetime(2027, 3, 10, 15, 0, tzinfo=timezone.utc), "America/New_York", "Quincy", "+16175550130",
              "Cleaning and exam")


def test_booking_from_a_hold_or_directly_asks_for_a_confirmation():
    assert decide({"to_status": "booked", "from_status": "held"}) == "confirmation"
    assert decide({"to_status": "booked", "from_status": None}) == "confirmation"


def test_cancelling_a_booked_visit_asks_for_a_cancellation_notice():
    assert decide({"to_status": "cancelled", "from_status": "booked"}) == "cancellation"


def test_other_changes_send_nothing():
    for to, frm in [("held", None), ("arrived", "booked"), ("completed", "arrived"), ("cancelled", "held")]:
        assert decide({"to_status": to, "from_status": frm}) is None


def test_times_are_in_the_clinics_own_time_zone():
    message = render("confirmation", CTX)
    assert "Wednesday 10 March at 10:00" in message.text  # 15:00 UTC is 10:00 in Quincy


def test_messages_carry_the_minimum():
    for kind in ["confirmation", "cancellation", "reminder:72h", "reminder:24h", "reminder:6h"]:
        message = render(kind, CTX)
        assert "Ana" in message.text and "Quincy" in message.text
        for never in ["synthetic", "NG0", "@"]:
            assert never not in message.text and never not in message.html


def test_names_are_escaped_in_html():
    message = render("confirmation", Context("<b>x</b>", CTX.starts_at, CTX.time_zone, "Quincy", None, "Exam"))
    assert "<b>x</b>" not in message.html and "&lt;b&gt;" in message.html


def test_a_receipt_shows_the_amount_in_dollars_and_nothing_about_cancelling():
    from dataclasses import replace
    message = render("receipt", replace(CTX, amount_cents=123456))
    assert message.subject == "Payment received"
    assert "$1,234.56" in message.text and "cancel" not in message.text


def test_confirmations_and_reminders_carry_a_cancel_link_when_there_is_one():
    from dataclasses import replace
    message = render("reminder:24h", replace(CTX, link="https://n8n.example/webhook/visit?t=abc"))
    assert "Need to cancel? Use this link: https://n8n.example/webhook/visit?t=abc" in message.text
    assert '<a href="https://n8n.example/webhook/visit?t=abc"' in message.html


def test_a_check_in_asks_how_the_patient_is_and_gives_the_emergency_path():
    from dataclasses import replace
    message = render("checkin:1d", replace(CTX, link="https://n8n.example/webhook/checkin?t=abc"))
    assert message.subject == "How are you feeling?"
    assert "https://n8n.example/webhook/checkin?t=abc" in message.text and "911" in message.text
    assert "+16175550130" in message.text


def test_a_statement_shows_the_balance_and_a_pay_link():
    from dataclasses import replace
    message = render("statement:14d", replace(CTX, amount_cents=11000, link="https://n8n.example/webhook/pay?t=abc"))
    assert "$110.00" in message.text and "pay?t=abc" in message.text


def test_the_clinic_alert_names_no_patient():
    from worker.messages import render_alert
    message = render_alert("Quincy", "4a000000-0000-4000-8000-000000000003")
    assert "Quincy" in message.text and "4a000000" in message.text


def test_a_receipt_still_goes_when_the_pdf_renderer_is_down():
    from dataclasses import replace
    from worker.main import receipt_pdf
    assert receipt_pdf("http://127.0.0.1:9", replace(CTX, amount_cents=11000), "7247cdab-0000") is None


def test_the_receipt_document_is_self_contained():
    from dataclasses import replace
    from worker.messages import receipt_document
    html = receipt_document(replace(CTX, amount_cents=11000), "7247CDAB", "21 November 2026")
    assert "$110.00" in html and "7247CDAB" in html
    assert "http" not in html and "<script" not in html, "nothing for the renderer to fetch or run"
