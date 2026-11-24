"""The graph's safety behaviour, with a scripted model (no Ollama) and a fake database."""
import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.types import Command

from agent import graph, tools
from agent.safety import fixed


class ScriptedModel:
    """Replies with the next scripted message; records that it was called."""
    def __init__(self, *replies):
        self.replies, self.calls = list(replies), 0

    def bind_tools(self, _tools):
        return self

    def invoke(self, _messages):
        self.calls += 1
        return self.replies.pop(0)


def call(name, **args):
    return AIMessage("", tool_calls=[{"name": name, "args": args, "id": f"c{len(args)}{name}"}])


@pytest.fixture
def db(monkeypatch):
    log = []
    def rpc(_s, name, **params):
        log.append((name, params))
        return {"hold_slot": "appt-1", "available_slots": [{"starts_at": "2026-11-27T15:00:00+00:00", "practitioner_id": "dr-1"}]}.get(name)
    def get(_s, path, **params):
        if path == "/locations":
            return [{"id": "loc-1", "time_zone": "America/New_York", "name": "Quincy"}]
        if path == "/services":
            return [{"id": "svc-1", "name": "Adult cleaning"}]
        return []
    monkeypatch.setattr(tools, "_rpc", rpc)
    monkeypatch.setattr(tools, "_get", get)
    return log


def run(model, message, language="en", thread="t1", app=None):
    app = app or graph.build()
    config = {"configurable": {"thread_id": thread, "model": model, "clinic_phone": "(617) 555-0130",
                               "session": tools.Session("https://db.test", "pk", "jwt", "patient-1", language)}}
    return app, config, app.invoke({"messages": [HumanMessage(message)]}, config)


def test_a_red_flag_skips_the_model_and_alerts_the_clinic(db):
    model = ScriptedModel()
    _, _, out = run(model, "La hinchazón se extiende hacia el ojo", language="es")
    assert model.calls == 0, "red flags never reach the model"
    assert out["messages"][-1].content == fixed("emergency", "es", "(617) 555-0130")
    name, params = db[0]
    assert name == "request_handover" and params["category"] == "emergency"
    assert "ojo" not in params["summary"], "the handover carries the flag, not the patient's words"


def test_a_clinical_question_is_handed_over_with_the_fixed_text(db):
    model = ScriptedModel(call("handoff_to_staff", category="clinical_question", summary_in_english="Asks whether to take ibuprofen."))
    _, _, out = run(model, "Can I take ibuprofen after my extraction?")
    assert out["messages"][-1].content == fixed("cannot_advise", "en", "(617) 555-0130")
    assert model.calls == 1, "the reply after a handover is fixed text, not another model call"


def test_booking_waits_for_the_patients_button(db):
    model = ScriptedModel(
        call("book_visit", clinic_code="quincy", service_code="D1110", slot="2026-11-27T15:00:00+00:00|dr-1"),
        AIMessage("You're booked."),
    )
    app, config, out = run(model, "Reserva la limpieza de las 10:00", language="es")
    assert "__interrupt__" in out, "nothing is booked before the patient confirms"
    card = out["__interrupt__"][0].value
    assert card["title"] == "¿Reservar esta cita?" and card["yes"] == "Confirmar", "the card speaks the patient's language"
    assert "Adult cleaning" in card["detail"] and "Northgate Dental, Quincy" in card["detail"]
    assert not any(n == "hold_slot" for n, _ in db)
    app.invoke(Command(resume=True), config)
    assert [n for n, _ in db] == ["hold_slot", "confirm_booking"]
    assert db[0][1]["patient"] == "patient-1", "the patient comes from the session, never from the model"


def test_declining_the_button_books_nothing(db):
    model = ScriptedModel(
        call("book_visit", clinic_code="quincy", service_code="D1110", slot="2026-11-27T15:00:00+00:00|dr-1"),
        AIMessage("No problem."),
    )
    app, config, _ = run(model, "Book it")
    app.invoke(Command(resume=False), config)
    assert db == []


def test_an_invented_price_or_time_is_not_sent(db):
    model = ScriptedModel(AIMessage("A cleaning is $79.00 and we have 10:30 tomorrow."))
    _, _, out = run(model, "How much is a cleaning?")
    assert "$79" not in out["messages"][-1].content
    assert out["messages"][-1].content == fixed("handover", "en", "(617) 555-0130")
    assert db[0][0] == "request_handover", "the fixed text says the team has it, so it must"


def test_an_invented_payment_link_is_not_sent(db):
    model = ScriptedModel(AIMessage("Here is your secure payment link: https://securepaymentlink.com/v-77"))
    _, _, out = run(model, "Can I pay my bill?")
    assert "http" not in out["messages"][-1].content      # only a link a tool returned may reach the patient
    assert out["messages"][-1].content == fixed("handover", "en", "(617) 555-0130")
