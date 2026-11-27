"""What the assistant does, as numbers for Prometheus and Grafana (AGENTS 14.4): how many turns, how fast, which
tools, how often a person takes over, how often the safety check refuses, and how many model tokens it all costs.

Nothing here can name a patient: every label is one of a few fixed words (a channel, a language, a tool, an outcome).
The page is served at /metrics, a path Nginx does not publish; only the collector on the same private network reads it."""

from langchain_core.messages import AIMessage, HumanMessage
from prometheus_client import Counter, Histogram

TURNS = Counter("nora_turns_total", "Patient turns answered", ["channel", "language", "outcome"])
SECONDS = Histogram("nora_turn_seconds", "Time to answer one turn", ["channel"],
                    buckets=(1, 2, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128))
TOOLS = Counter("nora_tool_calls_total", "Tool calls made by the assistant", ["tool"])
TOKENS = Counter("nora_model_tokens_total", "Model tokens used", ["direction"])
BLOCKS = Counter("nora_grounding_blocks_total", "Replies refused because a price, time or link had no tool behind it")
SECOND_LOOKS = Counter("nora_second_looks_total", "Replies that used no tool and were given one second look", ["result"])
CALLS = Counter("nora_calls_started_total", "Voice calls started", ["language"])
AI_EVENT_FAILURES = Counter("nora_ai_event_failures_total", "Turns whose ai_events row could not be written")


def record(channel: str, language: str, seconds: float, out: dict) -> dict:
    """One finished turn. Reads only the shape of the conversation (which tools, how many tokens), never its words,
    and returns that shape for the ai_events row."""
    messages = out.get("messages", [])
    since = max((i for i, m in enumerate(messages) if isinstance(m, HumanMessage)), default=0)
    tools = [c["name"] for m in messages[since:] if isinstance(m, AIMessage) for c in (m.tool_calls or [])]
    for name in tools:
        TOOLS.labels(name).inc()
    tokens = {"input_tokens": 0, "output_tokens": 0}
    for m in messages[since:]:
        usage = getattr(m, "usage_metadata", None) or {}
        for key in tokens:
            tokens[key] += usage.get(key, 0)
    TOKENS.labels("input").inc(tokens["input_tokens"])
    TOKENS.labels("output").inc(tokens["output_tokens"])
    outcome = ("confirm" if out.get("__interrupt__") else "emergency" if out.get("flags") else
               "handover" if "handoff_to_staff" in tools else "answered")
    TURNS.labels(channel, language, outcome).inc()
    SECONDS.labels(channel).observe(seconds)
    return {"outcome": outcome, "tools": tools, **tokens}
