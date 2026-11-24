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
