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
