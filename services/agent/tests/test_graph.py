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


def test_asking_for_the_team_shows_a_choice_card_and_hands_over_only_after_the_patients_choice(db):
    model = ScriptedModel(call("handoff_to_staff", category="other", summary_in_english="Asks about insurance."))
    app, config, out = run(model, "Een medewerker spreken", language="nl")
    card = out["__interrupt__"][0].value
    assert card["action"] == "team" and card["title"] == fixed("confirm_team", "nl")
    assert card["yes"] == fixed("yes_team", "nl") and card["call"] == fixed("call_team", "nl")
    assert db == [], "nothing reaches the team before the patient chooses"
    out = app.invoke(Command(resume={"reply_by": "app"}), config)
    assert db[0][0] == "request_handover" and db[0][1]["summary"] == "Asks about insurance."
    assert out["messages"][-1].content == fixed("handover", "nl", "(617) 555-0130")
    assert model.calls == 1, "the choice and the handover need no second model call"


def test_not_now_on_the_team_card_hands_nothing_over(db):
    model = ScriptedModel(call("handoff_to_staff", category="other", summary_in_english="x"), AIMessage("Of course."))
    app, config, _ = run(model, "I want to talk to the team")
    app.invoke(Command(resume=False), config)
    assert db == []


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
    monkeypatch.setattr(tools, "interrupt", lambda card: True)   # the patient pressed Send
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


@pytest.mark.parametrize("said,kept", [("más de $500, puedes", True), ("$500.", True), ("$1,200 in total", True),
                                       ("$1,200, then", True), ("$50, then", False), ("$5,000", False)])
def test_a_price_followed_by_punctuation_matches_the_documents_price(said, kept, monkeypatch):
    from langchain_core.messages import ToolMessage
    state = {"messages": [HumanMessage("instalments?"),
                          ToolMessage('From "Paying your bill": over $500 ... a crown is $1,200.', tool_call_id="1"),
                          AIMessage(f"Yes: {said} over 6 months.")]}
    config = {"configurable": {"session": tools.Session("u", "k", "j", "p", "es"), "clinic_phone": None}}
    monkeypatch.setattr(tools, "_rpc", lambda *a, **k: None)
    assert (graph.grounded(state, config) == {}) is kept, said


def test_a_time_inside_a_longer_time_is_not_evidence(monkeypatch):
    from langchain_core.messages import ToolMessage
    state = {"messages": [HumanMessage("when?"), ToolMessage("Free: 19:00", tool_call_id="1"), AIMessage("We have 9:00 free.")]}
    config = {"configurable": {"session": tools.Session("u", "k", "j", "p", "en"), "clinic_phone": None}}
    monkeypatch.setattr(tools, "_rpc", lambda *a, **k: None)
    assert graph.grounded(state, config) != {}, "9:00 was never offered"


def test_a_payment_link_is_emailed_only_after_the_patients_button(db):
    model = ScriptedModel(call("pay_link", visit_ref="appt-9"), AIMessage("Done."))
    app, config, out = run(model, "Envoyez-moi le lien de paiement", language="fr")
    card = out["__interrupt__"][0].value
    assert card["action"] == "paylink" and card["title"] == fixed("confirm_paylink", "fr")
    assert db == [], "nothing is sent before the patient presses Send"
    app.invoke(Command(resume=True), config)
    assert db == [("send_my_payment_link", {"appointment": "appt-9"})]


def test_a_reschedule_link_is_emailed_only_after_the_patients_button(visit_db):
    db = visit_db
    model = ScriptedModel(call("reschedule_link", visit_ref="appt-9"), AIMessage("Sent."))
    app, config, out = run(model, "Can I move my cleaning?")
    card = out["__interrupt__"][0].value
    assert card["action"] == "movelink" and "Northgate Dental, Quincy" in card["detail"]
    app.invoke(Command(resume=False), config)
    assert db == [], "declining sends nothing"

    model = ScriptedModel(call("reschedule_link", visit_ref="appt-9"), AIMessage("Sent."))
    app, config, _ = run(model, "Can I move my cleaning?", thread="t2")
    app.invoke(Command(resume=True), config)
    assert db == [("send_my_reschedule_link", {"appointment": "appt-9"})]


@pytest.fixture
def visit_db(db, monkeypatch):
    real = tools._get
    monkeypatch.setattr(tools, "_get", lambda s, path, **p: [{"starts_at": "2026-12-03T15:00:00+00:00", "location_services": {
        "services": {"name": "Adult cleaning"}, "locations": {"name": "Quincy", "time_zone": "America/New_York"}}}]
        if path == "/appointments" else real(s, path, **p))
    return db


def test_actions_go_through_n8n_as_the_patient_from_the_session_never_the_model(visit_db, monkeypatch):
    from agent import actions
    sent = []
    monkeypatch.setattr(actions, "configured", lambda: True)
    monkeypatch.setattr(actions, "call", lambda tool, token, **args: sent.append((tool, token, args)) or "tok")
    model = ScriptedModel(call("reschedule_link", visit_ref="appt-9", session_token="forged"), AIMessage("Sent."))
    app, config, _ = run(model, "Move my visit")
    app.invoke(Command(resume=True), config)
    assert sent == [("reschedule_link", "jwt", {"visit_ref": "appt-9"})], "the token is the verified session's"
    assert visit_db == [], "n8n did it, so the database was not called directly"


def test_when_n8n_is_down_the_same_database_function_still_runs(visit_db, monkeypatch):
    from agent import actions
    def down(*a, **k):
        raise actions.Unavailable("ConnectError")
    monkeypatch.setattr(actions, "configured", lambda: True)
    monkeypatch.setattr(actions, "call", down)
    model = ScriptedModel(call("handoff_to_staff", category="billing", summary_in_english="Question about a bill."))
    app, config, _ = run(model, "I want to talk to someone about my bill")
    app.invoke(Command(resume={"reply_by": "app"}), config)
    assert visit_db[0][0] == "request_handover", "the handover still reaches the inbox"


def test_a_refusal_from_the_database_is_not_retried_around_n8n(monkeypatch):
    from agent import actions
    def refused(*a, **k):
        raise actions.Refused("this visit is not yours")
    monkeypatch.setattr(actions, "configured", lambda: True)
    monkeypatch.setattr(actions, "call", refused)
    monkeypatch.setattr(tools, "_rpc", lambda *a, **k: pytest.fail("a refusal must not fall back to a direct call"))
    with pytest.raises(tools.ToolRefused, match="not yours"):
        tools._act(tools.Session("u", "k", "j", "p"), "reschedule_link", {"visit_ref": "x"}, "send_my_reschedule_link", appointment="x")


def test_n8n_tool_responses_are_read_as_the_database_answer():
    from agent import actions
    assert actions.parse('[{"statusCode": 200, "body": "tok", "headers": {}}]') == "tok"
    with pytest.raises(actions.Refused, match="not yours"):
        actions.parse('{"statusCode": 403, "body": {"message": "this visit is not yours"}}')
    with pytest.raises(actions.Unavailable):
        actions.parse('{"error": "workflow failed"}')
