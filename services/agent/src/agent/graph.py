"""The receptionist assistant as a LangGraph graph (blueprint section 31, Figure 5):

    gate --red flag--> emergency (fixed text, urgent handover) --> END
      |
      v
    assistant (model) <--> tools (book and cancel pause for the patient's button)
      |
      v
    grounded? (prices and times must come from a tool) --> END

A handover to the team ends the turn with the fixed handover text, never generated words."""

import re
from datetime import date

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage
from langchain_core.runnables import RunnableConfig
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import END, START, MessagesState, StateGraph
from langgraph.prebuilt import ToolNode

from . import safety, tools
from .models import model_for


class State(MessagesState):
    flags: list[str]


PROMPT = """You are Nora, the virtual receptionist of Northgate Dental, a dental group in Boston with clinics at Back Bay
(code back-bay), Cambridge (cambridge) and Quincy (quincy). Today is {today}.

Reply only in {language}, briefly and warmly, in plain words.

The patient has already been greeted and told who you are. Never greet again or introduce yourself again, even when
the patient says hello or gives their name: answer the question straight away, using their first name at most once.

You can: answer questions about the clinics, hours and services (use clinic_info and services); find and book visits
(services, then find_slots, then book_visit with the slot reference); list and cancel the patient's visits; give a
payment link; suggest shop products; and pass anything else to the team with handoff_to_staff.

Rules you never break:
- Never give medical or dental advice, a diagnosis, or advice about medicines. For any question about symptoms, pain,
  medicines or treatment choices, call handoff_to_staff with category clinical_question.
- Never state a price, time or date unless a tool gave it to you in this conversation.
- Never ask for or repeat a date of birth, insurance number or address; you already know who the patient is.
- If you are unsure, hand over to the team rather than guess."""


def _phone(config: RunnableConfig) -> str | None:
    return config["configurable"].get("clinic_phone")


def gate(state: State) -> dict:
    last = state["messages"][-1]
    return {"flags": safety.red_flags(last.content) if isinstance(last, HumanMessage) else []}


def emergency(state: State, config: RunnableConfig) -> dict:
    session = tools._session(config)
    try:  # the clinic hears at once; the handover carries the flags, never the patient's words
        tools._rpc(session, "request_handover", category="emergency", language=session.language,
                   summary="Red flag in the assistant chat: " + ", ".join(state["flags"]) + ". Call the patient now.")
    except Exception:  # the patient's reply must never wait on the alert
        pass
    return {"messages": [AIMessage(safety.fixed("emergency", session.language, _phone(config)))]}


def assistant(state: State, config: RunnableConfig) -> dict:
    session = tools._session(config)
    language = safety.texts().get(session.language, safety.texts()["en"])["name"]
    model = config["configurable"].get("model") or model_for("assistant")
    reply = model.bind_tools(tools.ALL).invoke(
        [SystemMessage(PROMPT.format(today=date.today().isoformat(), language=language)), *state["messages"]])
    return {"messages": [reply]}


def after_assistant(state: State) -> str:
    last = state["messages"][-1]
    return "tools" if getattr(last, "tool_calls", None) else "grounded"


def after_tools(state: State) -> str:
    last = state["messages"][-1]
    return "handed_over" if isinstance(last, ToolMessage) and last.content == "handed_over" else "assistant"


def handed_over(state: State, config: RunnableConfig) -> dict:
    session = tools._session(config)
    call = next(c for m in reversed(state["messages"]) for c in getattr(m, "tool_calls", None) or []
                if c["name"] == "handoff_to_staff")
    key = "cannot_advise" if call["args"].get("category") == "clinical_question" else "handover"
    return {"messages": [AIMessage(safety.fixed(key, session.language, _phone(config)))]}


_FACT = re.compile(r"\$\s?\d[\d,]*(\.\d\d)?|\b\d{1,2}:\d{2}\b")


def grounded(state: State, config: RunnableConfig) -> dict:
    """Every price and time in the reply must appear in a tool result since the patient's last message."""
    messages = state["messages"]
    since = max(i for i, m in enumerate(messages) if isinstance(m, HumanMessage))
    evidence = " ".join(str(m.content) for m in messages[since:] if isinstance(m, ToolMessage))
    reply = str(messages[-1].content)
    unsupported = [m.group(0) for m in _FACT.finditer(reply) if m.group(0).replace(" ", "") not in evidence.replace(" ", "")]
    if not unsupported:
        return {}
    session = tools._session(config)
    try:  # the fixed text says the team has it, so the team must really have it
        tools._rpc(session, "request_handover", category="other", language=session.language,
                   summary="The assistant could not confirm a price or time from the records; please answer the patient.")
    except Exception:
        pass
    return {"messages": [AIMessage(safety.fixed("handover", session.language, _phone(config)), id=messages[-1].id)]}


def build(checkpointer=None):
    g = StateGraph(State)
    g.add_node("gate", gate)
    g.add_node("emergency", emergency)
    g.add_node("assistant", assistant)
    g.add_node("tools", ToolNode(tools.ALL, handle_tool_errors=lambda e: f"Refused: {e}"))
    g.add_node("handed_over", handed_over)
    g.add_node("grounded", grounded)
    g.add_edge(START, "gate")
    g.add_conditional_edges("gate", lambda s: "emergency" if s["flags"] else "assistant", ["emergency", "assistant"])
    g.add_edge("emergency", END)
    g.add_conditional_edges("assistant", after_assistant, ["tools", "grounded"])
    g.add_conditional_edges("tools", after_tools, ["handed_over", "assistant"])
    g.add_edge("handed_over", END)
    g.add_edge("grounded", END)
    return g.compile(checkpointer=checkpointer or MemorySaver())
