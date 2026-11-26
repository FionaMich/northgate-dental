"""Handovers become Jira tickets: the right fields, a checked callback number, and never a lost handover."""
import httpx
import pytest

from agent import jira, tools

REAL_CLIENT = httpx.Client


@pytest.fixture
def board(monkeypatch):
    monkeypatch.setattr(jira, "SITE", "https://example.atlassian.net")
    monkeypatch.setenv("JIRA_EMAIL", "team@example.test")
    monkeypatch.setenv("JIRA_API_TOKEN", "token")
    sent = []

    def handler(request):
        sent.append(request)
        return httpx.Response(201, json={"key": "NGD-7"})

    monkeypatch.setattr(jira.httpx, "Client", lambda **k: REAL_CLIENT(transport=httpx.MockTransport(handler)))
    db = []
    monkeypatch.setattr(tools, "_rpc", lambda s, name, **p: db.append((name, p)))
    return sent, db


def handoff(**args):
    session = tools.Session("u", "k", "j", "patient-42", "fr")
    return tools.handoff_to_staff.func(config={"configurable": {"session": session}}, **args)


def test_a_call_back_request_becomes_a_ticket_with_the_checked_number_and_no_name(board):
    sent, db = board
    assert handoff(category="billing", summary_in_english="Wants to check insurance before Monday",
                   reply_by="call", phone="+1 (617) 555-0142") == "handed_over"
    assert db[0][0] == "request_handover", "the staff inbox still gets it first"
    body = sent[0].read().decode()
    assert "+16175550142" in body and "patient-42" in body and "lang-fr" in body and "call back" in body
    assert sent[0].url.path == "/rest/api/3/issue"


def test_a_number_that_is_not_a_phone_number_is_refused_so_nora_asks_again(board):
    sent, db = board
    with pytest.raises(tools.ToolRefused):
        handoff(category="other", summary_in_english="x", reply_by="call", phone="call me")
    assert sent == [] and db == [], "nothing is filed with a broken number"


def test_a_reply_in_the_app_carries_no_number_and_jira_being_down_never_loses_the_handover(board, monkeypatch):
    sent, db = board
    handoff(category="other", summary_in_english="Question about parking", reply_by="app", phone="617 555 0100")
    assert "617" not in sent[0].read().decode() and "reply in app" in sent[0].read().decode()

    def down(**k):
        raise httpx.ConnectError("down")
    monkeypatch.setattr(jira.httpx, "Client", lambda **k: REAL_CLIENT(transport=httpx.MockTransport(lambda r: down())))
    assert handoff(category="other", summary_in_english="Still filed", reply_by="app") == "handed_over"
    assert db[-1][1]["summary"] == "Still filed"
