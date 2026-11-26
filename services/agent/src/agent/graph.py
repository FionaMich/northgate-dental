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
from datetime import date, timedelta

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage
from langchain_core.runnables import RunnableConfig
from langgraph.checkpoint.memory import MemorySaver
from langgraph.graph import END, START, MessagesState, StateGraph
from langgraph.prebuilt import ToolNode

from . import metrics, safety, tools
from .models import model_for


class State(MessagesState):
    flags: list[str]


PROMPT = """You are Nora, the virtual receptionist of Northgate Dental, a dental group in Boston with clinics at Back Bay
(code back-bay), Cambridge (cambridge) and Quincy (quincy). Today is {today}; tomorrow is {tomorrow}. This week ends on Sunday; next week starts on {next_monday}.
Work out every date the patient means ("today", "tomorrow", "next Monday", "this weekend") from today's date yourself.
Never ask the patient what the date is.

Reply only in {language}, briefly and warmly, in plain words.

The patient has already been greeted and told who you are. Never greet again or introduce yourself again, even when
the patient says hello or gives their name. Use their first name at most once.

You know nothing about the clinics, the patient's visits or prices except what a tool returns, so call the tool first
and answer from its result. Act at once, in the same turn: never say you are going to check or look something up,
never ask "would you like me to check?", and never ask the patient for something a tool can tell you. Whatever
language the patient writes in, choose and call tools exactly as you would for the same request in English; only
your final words are in {language}.

How to do each job:
- Hours, address or phone: call clinic_info, then answer for the day the patient means.
- Pay a bill: call pay_link (with no ref it is for the patient's next visit), then say the secure payment link is
  ready and give the link exactly as the tool returned it. Never write a link yourself.
- Book a visit: a cleaning, a check-up, a filling, whitening or a video consultation is the kind of visit, whatever
  word or language the patient uses for it (a "détartrage", "Zahnreinigung" or "limpieza" is a cleaning; a
  "videoconsulta" or a video call with the dentist is a video consultation, kind "video"). When the patient has named
  the clinic and the kind of visit, call find_slots with the clinic, the kind of visit as one English word and the
  first day of the period they mean, then offer the earliest time it returns. Never ask what type of visit when they
  named one; ask only if the clinic or the kind of visit is truly missing. After booking a video consultation, say
  that the Join button appears on the visit in Visits.
- The patient says yes to a time you offered: call book_visit with the same clinic, the same kind of visit and that
  time's slot. Do not ask anything again.
- The patient's visits: call my_visits. To cancel, call cancel_visit with the ref.
- Shop products: call shop_search.
- The patient asks for a member of the Northgate team, or about insurance, or anything no tool covers: call
  handoff_to_staff at once, with a short summary of what they need if they said it. The app then asks them how the
  team should reply. Never ask them that yourself, and never ask what it is about first.

Rules you never break:
- Never give medical or dental advice, a diagnosis, or advice about medicines. For any question about symptoms, pain,
  medicines or treatment choices, call handoff_to_staff with category clinical_question.
- Never state a price, time or date unless a tool gave it to you in this conversation.
- Never say or show a ref or slot code; they are for your tools only.
- Never ask for or repeat a date of birth, insurance number or address; you already know who the patient is.
- If you are unsure, hand over to the team rather than guess."""


NUDGE = ("(Reminder from the system, not the patient.) You replied without calling a tool. If the patient's last "
         "message is one of the jobs in your instructions, call the right tool now with what you already know. "
         "If no tool applies, repeat your reply.")


def _day(d: date) -> str:
    return d.strftime("%A %Y-%m-%d")   # the weekday is spelled out: opening hours are listed by weekday


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
    bound = model.bind_tools(tools.ALL)
    history = [SystemMessage(PROMPT.format(today=_day(date.today()), tomorrow=_day(date.today() + timedelta(days=1)),
                                      next_monday=_day(date.today() + timedelta(days=7 - date.today().weekday())), language=language)), *state["messages"]]
    reply = bound.invoke(history)
    since = max((i for i, m in enumerate(state["messages"]) if isinstance(m, HumanMessage)), default=0)
    used_a_tool = any(isinstance(m, ToolMessage) for m in state["messages"][since:])
    if not getattr(reply, "tool_calls", None) and not used_a_tool:
        # A small model sometimes says "I will check" and stops. One second look, before the patient sees anything.
        second = bound.invoke([*history, reply, HumanMessage(NUDGE)])
        used = bool(getattr(second, "tool_calls", None))
        metrics.SECOND_LOOKS.labels("tool_called" if used else "kept").inc()
        if used:
            reply = second
    return {"messages": [reply]}


def after_assistant(state: State) -> str:
    last = state["messages"][-1]
    return "tools" if getattr(last, "tool_calls", None) else "grounded"


def after_tools(state: State) -> str:
    last = state["messages"][-1]
    return "handed_over" if isinstance(last, ToolMessage) and last.content in ("handed_over", "handed_over_call") else "assistant"


def handed_over(state: State, config: RunnableConfig) -> dict:
    session = tools._session(config)
    call = next(c for m in reversed(state["messages"]) for c in getattr(m, "tool_calls", None) or []
                if c["name"] == "handoff_to_staff")
    key = "cannot_advise" if call["args"].get("category") == "clinical_question" else "handover"
    return {"messages": [AIMessage(safety.fixed(key, session.language, _phone(config)))]}


_FACT = re.compile(r"\$\s?\d[\d,]*(\.\d\d)?|\b\d{1,2}:\d{2}\b(\s*[AaPp]\.?\s?[Mm]\b\.?)?|https?://[^\s)>\]]+")


def _forms(fact: str) -> list[str]:
    """The ways a fact may appear in a tool result. Tools give times on the 24-hour clock ("14:00"); Nora may say
    "2:00 PM", which is the same time and must not be refused."""
    m = re.fullmatch(r"(\d{1,2}):(\d{2})\s*([AaPp])?\.?\s?[Mm]?\.?", fact.strip())
    if not m:
        return [fact.replace(" ", "")]
    hour, minute, half = int(m.group(1)), m.group(2), (m.group(3) or "").lower()
    if half == "p" and hour < 12:
        hour += 12
    elif half == "a" and hour == 12:
        hour = 0
    return [f"{hour:02d}:{minute}", f"{hour}:{minute}"]


def grounded(state: State, config: RunnableConfig) -> dict:
    """Every price, time and link in the reply must appear in a tool result since the patient's last message."""
    messages = state["messages"]
    since = max(i for i, m in enumerate(messages) if isinstance(m, HumanMessage))
    evidence = " ".join(str(m.content) for m in messages[since:] if isinstance(m, ToolMessage))
    reply = str(messages[-1].content)
    flat = evidence.replace(" ", "")
    unsupported = [m.group(0) for m in _FACT.finditer(reply) if not any(f in flat for f in _forms(m.group(0)))]
    if not unsupported:
        return {}
    metrics.BLOCKS.inc()
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
