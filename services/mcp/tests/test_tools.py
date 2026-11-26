"""The dental-tools MCP server: public clinic information only, read through the two public database functions."""
import asyncio

import dental_mcp as m

CATALOGUE = {
    "locations": [
        {"code": "quincy", "name": "Quincy", "address": "3 Example Road", "city": "Quincy", "state": "MA", "postal_code": "02169",
         "phone": "+16175550130", "hours": [{"weekday": d, "opens": "07:00", "closes": "20:00"} for d in range(1, 7)]},
        {"code": "back-bay", "name": "Back Bay", "address": "1 Example Street", "city": "Boston", "state": "MA", "postal_code": "02116",
         "phone": "+16175550110", "hours": [{"weekday": d, "opens": "08:00", "closes": "18:00"} for d in range(1, 6)]
         + [{"weekday": 6, "opens": "09:00", "closes": "14:00"}]},
    ],
    "services": [
        {"code": "D1110", "name": "Adult cleaning", "summary": "A hygienist cleans and polishes.", "duration_minutes": 60,
         "prices": {"quincy": 11000, "back-bay": 13000}},
        {"code": "D6010", "name": "Implant placement", "summary": "A titanium post.", "duration_minutes": 120, "prices": {"back-bay": 320000}},
    ],
}


def test_clinics_give_address_phone_and_hours_grouped_by_day(monkeypatch):
    monkeypatch.setattr(m, "_rpc", lambda name, body: CATALOGUE)
    out = m.clinics()
    assert "Quincy: 3 Example Road, Quincy, MA 02169. Phone (617) 555-0130. Open Monday to Saturday 07:00 to 20:00; Sunday closed." in out
    assert "Monday to Friday 08:00 to 18:00; Saturday 09:00 to 14:00; Sunday closed" in out


def test_prices_can_be_limited_to_one_clinic_and_an_unknown_clinic_is_refused(monkeypatch):
    monkeypatch.setattr(m, "_rpc", lambda name, body: CATALOGUE)
    assert "Implant placement" in m.services_and_prices() and "Back Bay $3,200" in m.services_and_prices()
    quincy = m.services_and_prices("quincy")
    assert "Adult cleaning (60 minutes)" in quincy and "Quincy $110" in quincy and "Implant" not in quincy
    assert "no Northgate clinic called 'Salem'" in m.services_and_prices("Salem")


def test_policies_answer_from_approved_documents_and_refuse_weak_matches(monkeypatch):
    sent = {}
    monkeypatch.setattr(m, "_embed", lambda q: None)
    monkeypatch.setattr(m, "_rpc", lambda name, body: sent.update(name=name, **body) or [
        {"document_title": "Cancellations and missed visits", "heading": "Missed visits", "content": "$50 at Back Bay.",
         "similarity": None, "keyword_match": True},
        {"document_title": "Getting here", "heading": "Quincy", "content": "Free parking.", "similarity": None, "keyword_match": False}])
    out = m.clinic_policies("missed visit fee")
    assert sent["name"] == "public_search_knowledge" and sent["query_embedding"] is None, "keywords only without an embedder"
    assert 'From "Cancellations and missed visits"' in out and "Free parking" not in out
    monkeypatch.setattr(m, "_rpc", lambda name, body: [])
    assert m.clinic_policies("best toothpaste").startswith("No approved Northgate document")


def test_the_server_lists_exactly_the_public_tools():
    tools = asyncio.run(m.server.list_tools())
    assert sorted(t.name for t in tools) == ["clinic_policies", "clinics", "how_to_book", "services_and_prices"]
    assert all(t.description for t in tools)
