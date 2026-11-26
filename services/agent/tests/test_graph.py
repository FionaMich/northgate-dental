"""The graph's safety behaviour, with a scripted model (no Ollama) and a fake database."""
import pytest
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.types import Command

from agent import graph, tools
from agent.safety import fixed


class ScriptedModel:
    """Replies with the next scripted message; records that it was called."""
    def __init__(self, *replies, second_look=None):
        self.replies, self.calls, self.second_look = list(replies), 0, second_look

    def bind_tools(self, _tools):
        return self

    def invoke(self, _messages):
        if getattr(_messages[-1], "content", None) == graph.NUDGE:   # the second look: nothing to add unless scripted
            return self.second_look or AIMessage("")
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
        call("book_visit", clinic_code="quincy", service_code="D1110", slot="2026-11-27T10:00"),
        AIMessage("You're booked."),
    )
    app, config, out = run(model, "Reserva la limpieza de las 10:00", language="es")
    assert "__interrupt__" in out, "nothing is booked before the patient confirms"
    card = out["__interrupt__"][0].value
    assert card["title"] == "¿Reservar esta cita?" and card["yes"] == "Confirmar", "the card speaks the patient's language"
    assert "Adult cleaning" in card["detail"] and "Northgate Dental, Quincy" in card["detail"]
    assert not any(n == "hold_slot" for n, _ in db)
    app.invoke(Command(resume=True), config)
    writes = [(n, p) for n, p in db if n != "available_slots"]   # the free times are read again to match the slot
    assert [n for n, _ in writes] == ["hold_slot", "confirm_booking"]
    assert writes[0][1]["patient"] == "patient-1", "the patient comes from the session, never from the model"
    assert writes[0][1]["starts"] == "2026-11-27T15:00:00+00:00", "the clinic's own slot, found from the time offered"


def test_declining_the_button_books_nothing(db):
    model = ScriptedModel(
        call("book_visit", clinic_code="quincy", service_code="D1110", slot="2026-11-27T10:00"),
        AIMessage("No problem."),
    )
    app, config, _ = run(model, "Book it")
    app.invoke(Command(resume=False), config)
    assert [n for n, _ in db if n != "available_slots"] == [], "nothing is written when the patient declines"


def test_a_time_the_clinic_does_not_have_free_cannot_be_booked(db):
    model = ScriptedModel(
        call("book_visit", clinic_code="quincy", service_code="D1110", slot="2026-11-27T03:00"),
        AIMessage("Let me look again."),
    )
    _, _, out = run(model, "Book it")
    assert "__interrupt__" not in out, "no confirm card for a time that is not free"
    assert not any(n == "hold_slot" for n, _ in db)


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


def test_pay_my_bill_skips_a_paid_visit_and_opens_the_next_unpaid_one(monkeypatch):
    from agent import tools
    monkeypatch.setattr(tools, "_get", lambda s, path, **p: [{"id": "paid"}, {"id": "due"}])

    def rpc(s, name, appointment):
        if appointment == "paid":
            raise tools.ToolRefused("this visit is already paid")
        return "tok"

    monkeypatch.setattr(tools, "_rpc", rpc)
    session = tools.Session("u", "k", "j", "patient-1", "en", "https://x")
    assert tools.pay_link.func(config={"configurable": {"session": session}}) == "https://x/pay?t=tok"


def test_a_reply_that_only_promises_to_check_gets_one_second_look_and_the_tool_runs(db):
    model = ScriptedModel(AIMessage("Je vais vérifier les disponibilités."),
                          AIMessage("Le premier créneau est lundi."),
                          second_look=call("find_slots", clinic_code="quincy", service_code="cleaning", day="2026-11-30"))
    _, _, out = run(model, "Je voudrais un détartrage à Quincy la semaine prochaine", language="fr")
    assert ("available_slots" in [name for name, _ in db]), "the tool the first reply skipped was called"
    assert out["messages"][-1].content == "Le premier créneau est lundi."



def test_free_times_carry_the_price_so_a_reply_that_quotes_it_is_not_refused(db, monkeypatch):
    real = tools._get
    monkeypatch.setattr(tools, "_get", lambda s, path, **p: [{"price_cents": 4500}] if path == "/location_services" else real(s, path, **p))
    model = ScriptedModel(
        call("find_slots", clinic_code="quincy", service_code="video", day="2026-11-27"),
        AIMessage("The earliest video consultation is Friday at 10:00, and it costs $45.00. Shall I book it?"),
    )
    _, _, out = run(model, "A video consultation at Quincy, the earliest you have")
    assert out["messages"][-1].content.startswith("The earliest video consultation"), "not replaced by the handover text"



@pytest.mark.parametrize("said,kept", [("2:00 PM", True), ("2:00pm", True), ("14:00", True), ("2:00 p.m.", True),
                                       ("3:00 PM", False), ("2:00 AM", False), ("12:30 PM", False)])
def test_a_time_on_the_12_hour_clock_matches_the_tools_24_hour_time(said, kept):
    from langchain_core.messages import ToolMessage
    state = {"messages": [HumanMessage("book it"), ToolMessage("BOOKED: Thursday 26 November at 14:00", tool_call_id="1"),
                          AIMessage(f"Booked for {said} on Thursday.")]}
    config = {"configurable": {"session": tools.Session("u", "k", "j", "p", "en"), "clinic_phone": None}}
    tools_rpc = tools._rpc
    tools._rpc = lambda *a, **k: None
    try:
        out = graph.grounded(state, config)
    finally:
        tools._rpc = tools_rpc
    assert (out == {}) is kept, said
