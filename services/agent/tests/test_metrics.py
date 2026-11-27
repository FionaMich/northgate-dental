"""The numbers for Grafana: counted from the shape of a turn, never from its words."""
from fastapi.testclient import TestClient
from langchain_core.messages import AIMessage, HumanMessage, ToolMessage
from prometheus_client import REGISTRY

from agent import api, metrics


def value(name, **labels):
    return REGISTRY.get_sample_value(name, labels) or 0.0


def test_a_turn_is_counted_by_channel_language_and_outcome_with_its_tools_and_tokens():
    before = value("nora_turns_total", channel="call", language="de", outcome="handover")
    tokens = value("nora_model_tokens_total", direction="output")
    out = {"messages": [
        HumanMessage("earlier question"), AIMessage("earlier answer"),
        HumanMessage("Ich möchte mit jemandem über meine Versicherung sprechen, Frau Canary-Zebra"),
        AIMessage("", tool_calls=[{"name": "handoff_to_staff", "args": {}, "id": "1"}],
                  usage_metadata={"input_tokens": 900, "output_tokens": 21, "total_tokens": 921}),
        ToolMessage("handed_over", tool_call_id="1"), AIMessage("Weitergegeben."),
    ]}
    metrics.record("call", "de", 7.5, out)
    assert value("nora_turns_total", channel="call", language="de", outcome="handover") == before + 1
    assert value("nora_model_tokens_total", direction="output") == tokens + 21
    assert value("nora_tool_calls_total", tool="handoff_to_staff") >= 1


def test_a_confirm_card_and_a_red_flag_are_their_own_outcomes():
    a = value("nora_turns_total", channel="chat", language="en", outcome="confirm")
    b = value("nora_turns_total", channel="chat", language="en", outcome="emergency")
    metrics.record("chat", "en", 1.0, {"messages": [HumanMessage("book it")], "__interrupt__": [object()]})
    metrics.record("chat", "en", 0.1, {"messages": [HumanMessage("bleeding")], "flags": ["bleeding"]})
    assert value("nora_turns_total", channel="chat", language="en", outcome="confirm") == a + 1
    assert value("nora_turns_total", channel="chat", language="en", outcome="emergency") == b + 1


def test_the_metrics_page_has_numbers_and_never_a_patients_words():
    metrics.record("chat", "en", 2.0, {"messages": [HumanMessage("My name is Canary-Zebra and my tooth hurts")]})
    page = TestClient(api.app).get("/metrics")
    assert page.status_code == 200 and "nora_turns_total" in page.text and "nora_turn_seconds_bucket" in page.text
    assert "Canary-Zebra" not in page.text and "tooth hurts" not in page.text


def _who(language="nl"):
    from agent import tools
    return api.Who("user-1", tools.Session("https://db.test", "pk", "jwt", "patient-1", language), None)


def test_every_turn_is_logged_to_ai_events_with_its_shape_and_never_its_words(monkeypatch):
    from agent import graph
    logged = []
    monkeypatch.setattr(api.tools, "_rpc", lambda s, name, **p: logged.append((name, p)))

    class Graph:
        def invoke(self, what, config):
            return {"messages": [
                HumanMessage("Ik ben Canary-Zebra, boek een reiniging"),
                AIMessage("", tool_calls=[{"name": "find_slots", "args": {"clinic_code": "quincy"}, "id": "1"}],
                          usage_metadata={"input_tokens": 1800, "output_tokens": 30, "total_tokens": 1830}),
                ToolMessage("2026-11-27 10:00", tool_call_id="1"), AIMessage("Quincy heeft vrijdag 10:00 vrij.")]}
    monkeypatch.setattr(api, "assistant", Graph())
    api._run("chat", _who(), {"messages": []}, "thread-001")
    name, event = logged[-1]
    assert name == "log_ai_event"
    assert event["channel"] == "chat" and event["language"] == "nl" and event["outcome"] == "answered"
    assert event["tools"] == ["find_slots"] and event["input_tokens"] == 1800 and event["output_tokens"] == 30
    assert event["prompt_version"] == graph.PROMPT_VERSION and event["model"].startswith("ollama:")
    assert "Canary-Zebra" not in str(event) and "10:00" not in str(event) and "quincy" not in str(event)


def test_a_failed_log_never_costs_the_patient_their_answer_and_is_counted(monkeypatch):
    def down(*a, **k):
        raise RuntimeError("database down")
    monkeypatch.setattr(api.tools, "_rpc", down)

    class Graph:
        def invoke(self, what, config):
            return {"messages": [HumanMessage("hours?"), AIMessage("We open at 07:00.")]}
    monkeypatch.setattr(api, "assistant", Graph())
    before = value("nora_ai_event_failures_total")
    assert api._run("chat", _who("en"), {"messages": []}, "thread-002").reply == "We open at 07:00."
    assert value("nora_ai_event_failures_total") == before + 1, "a lost log line is alertable"
