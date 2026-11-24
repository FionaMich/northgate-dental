from datetime import datetime, timezone

import re
from dataclasses import replace

import pytest

from worker.messages import Context, Promotion, decide, render, render_promotion

EMAIL = re.compile(r"[\w.+-]+@[\w-]+\.[a-z]{2,}")

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
        for never in ["synthetic", "NG0"]:
            assert never not in message.text and never not in message.html
        assert not EMAIL.search(message.text) and not EMAIL.search(message.html), "no email address in the body"


def test_names_are_escaped_in_html():
    message = render("confirmation", Context("<b>x</b>", CTX.starts_at, CTX.time_zone, "Quincy", None, "Exam"))
    assert "<b>x</b>" not in message.html and "&lt;b&gt;" in message.html


def test_a_receipt_shows_the_amount_in_dollars_and_nothing_about_cancelling():
    from dataclasses import replace
    message = render("receipt", replace(CTX, amount_cents=123456))
    assert message.subject == "Receipt: $1,234.56 paid to Northgate Dental"
    assert "$1,234.56" in message.text and "cancel" not in message.text


def test_confirmations_and_reminders_carry_a_cancel_link_when_there_is_one():
    from dataclasses import replace
    message = render("reminder:24h", replace(CTX, link="https://n8n.example/webhook/visit?t=abc"))
    assert "Change or cancel: https://n8n.example/webhook/visit?t=abc" in message.text
    assert '<a href="https://n8n.example/webhook/visit?t=abc"' in message.html


def test_a_check_in_asks_how_the_patient_is_and_gives_the_emergency_path():
    from dataclasses import replace
    message = render("checkin:1d", replace(CTX, link="https://n8n.example/webhook/checkin?t=abc"))
    assert message.subject == "How are you feeling, Ana?"
    assert "https://n8n.example/webhook/checkin?t=abc" in message.text and "911" in message.text
    assert "(617) 555-0130" in message.text, "the clinic number, readable"


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


def test_an_order_email_lists_the_products_and_how_it_arrives():
    from worker.messages import render_order
    message = render_order("Ana", ["1 × Sonic electric toothbrush", "2 × Replacement brush heads, 2 pack"], 10669,
                           "collect", "Quincy", "(617) 555-0130", False)
    assert message.subject == "Thank you for your order"
    assert "Sonic electric toothbrush" in message.text and "$106.69" in message.text and "Quincy" in message.text


def test_a_moved_visit_is_one_email_with_the_old_and_the_new_time():
    moved = replace(CTX, previous_starts_at=datetime(2027, 3, 9, 14, 0, tzinfo=timezone.utc), link="https://n8n.example/webhook/visit?t=abc")
    message = render("reschedule", moved)
    assert message.subject == "Your visit has moved to Wednesday 10 March at 10:00"
    assert "Tuesday 9 March at 09:00" in message.text and "Wednesday 10 March at 10:00" in message.text
    assert "visit?t=abc" in message.html


def test_every_patient_email_has_an_inbox_preview_and_a_tap_to_call_number():
    for kind in ["confirmation", "cancellation", "reminder:24h"]:
        html = render(kind, CTX).html
        assert 'style="display:none' in html.split("<table", 1)[0], "preview text sits before the layout"
        assert 'href="tel:+16175550130"' in html


def test_a_promotion_names_no_visit_and_always_carries_unsubscribe():
    promo = Promotion(subject="Brighter by spring: 20% off whitening", preheader="Take-home whitening, fitted at your next visit.",
                      headline="Your brightest smile, ready by spring", body="Book a whitening consultation this month.",
                      offer="20% off take-home whitening", cta_label="Book a consultation", cta_link="https://example.org/book",
                      ends="31 March")
    message = render_promotion("Ana", promo, unsubscribe="https://n8n.example/webhook/unsubscribe?t=xyz")
    assert message.subject == promo.subject and "Ana" in message.text
    assert "unsubscribe?t=xyz" in message.text and "unsubscribe?t=xyz" in message.html
    assert "Cleaning and exam" not in message.html, "marketing never mentions anyone's treatment"


def test_a_promotion_shows_its_picture_with_alt_text_and_its_reasons():
    promo = Promotion(subject="Merry and bright", preheader="A gift for your smile.", headline="Give your smile a December treat",
                      body="Book before the holidays.", offer="Free whitening touch-up with every cleaning", cta_label="Book now",
                      cta_link="https://example.org/offers/december", ends="24 December",
                      hero_image="https://example.org/img/december.jpg", hero_alt="A family laughing by the Christmas tree",
                      points=(("Quick", "45 minutes"), ("Gentle", "Made for your teeth")), accent="#D9A441")
    html = render_promotion("Ana", promo, unsubscribe="https://n8n.example/webhook/unsubscribe?t=xyz").html
    assert 'src="https://example.org/img/december.jpg"' in html and 'alt="A family laughing by the Christmas tree"' in html
    assert html.index("december.jpg") < html.index("Northgate <span"), "the picture sits above the brand band"
    assert '<a href="https://example.org/offers/december" style="display:block' in html, "the picture links to the offer"
    assert "Quick" in html and "45 minutes" in html and "#D9A441" in html
    assert "img" not in render("confirmation", CTX).html, "service emails stay image-free"


def test_a_campaign_picture_cannot_track_who_opened_it():
    with pytest.raises(ValueError):
        Promotion(subject="s", preheader="p", headline="H", body="b", offer="o", cta_label="c",
                  cta_link="https://example.org/offers/x", ends="e", hero_image="https://example.org/h.jpg?r=patient-1")


def test_a_campaign_button_never_points_at_the_bare_site_root():
    with pytest.raises(ValueError):
        Promotion(subject="s", preheader="p", headline="H", body="b", offer="o", cta_label="c",
                  cta_link="https://84-12-126-31.sslip.io/?utm_source=mail", ends="e")
