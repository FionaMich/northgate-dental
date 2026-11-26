"""HTTP API for the app's chat screen. Every request carries the patient's Supabase token; the service verifies it with
Supabase, finds the linked patient and their clinic's phone, and runs the graph with that identity. Conversations are
keyed by user and thread, so nobody can resume someone else's conversation.

LangSmith tracing turns on only when LANGSMITH_API_KEY is set, with inputs and outputs hidden (decision 2026-11-22):
traces show nodes, tools, timings and outcomes, never what the patient wrote."""

import os
import secrets
import time
from dataclasses import dataclass, field, replace
from typing import Literal

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException, Response
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.types import Command
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field

from . import graph, metrics, safety, stream, tools
from .tools import Session

if os.environ.get("LANGSMITH_API_KEY"):
    os.environ.setdefault("LANGSMITH_TRACING", "true")
    os.environ.setdefault("LANGSMITH_HIDE_INPUTS", "true")
    os.environ.setdefault("LANGSMITH_HIDE_OUTPUTS", "true")
    os.environ.setdefault("LANGSMITH_PROJECT", "northgate-assistant")

SUPABASE_URL = os.environ.get("SUPABASE_URL", "http://127.0.0.1:54321")
PUBLISHABLE_KEY = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
LINK_BASE = os.environ.get("LINK_BASE", "")

app = FastAPI(title="Northgate assistant", docs_url=None, redoc_url=None, openapi_url=None)
assistant = graph.build()

Language = Literal["en", "fr", "nl", "de", "es", "it", "lt", "sv"]


@dataclass(frozen=True)
class Who:
    user_id: str
    session: Session
    clinic_phone: str | None


async def who(authorization: str = Header(...), x_language: Language = Header("en")) -> Who:
    token = authorization.removeprefix("Bearer ").strip()
    async with httpx.AsyncClient(base_url=SUPABASE_URL, timeout=10,
                                 headers={"apikey": PUBLISHABLE_KEY, "Authorization": f"Bearer {token}"}) as db:
        user = await db.get("/auth/v1/user")
        if user.status_code != 200:
            raise HTTPException(401, "sign in again")
        uid = user.json()["id"]
        link = (await db.get("/rest/v1/patient_links", params={"select": "patient_id,patients(locations(phone))",
                                                                 "profile_id": f"eq.{uid}"})).json()
    if not link:
        raise HTTPException(403, "link your patient record first")
    phone = ((link[0].get("patients") or {}).get("locations") or {}).get("phone")
    return Who(user_id=uid, clinic_phone=phone,
               session=Session(SUPABASE_URL, PUBLISHABLE_KEY, token, link[0]["patient_id"], x_language, LINK_BASE))


class ChatIn(BaseModel):
    thread: str = Field(pattern=r"^[A-Za-z0-9-]{8,64}$")
    message: str = Field(min_length=1, max_length=2000)


class ConfirmIn(BaseModel):
    thread: str = Field(pattern=r"^[A-Za-z0-9-]{8,64}$")
    accept: bool


class CallTicket(BaseModel):
    """Everything the app needs to join a Nora call (ADR 0015). The call ID is random: never a name or patient ID."""
    api_key: str
    token: str
    user_id: str
    call_type: str = "nora_voice"
    call_id: str


@dataclass
class CallCtx:
    """A call in progress: who is on it, when it started, whether the voice service has picked it up, and replies the
    voice service still has to speak (the patient's Confirm answer arrives through the API, not through the call)."""
    who: Who
    started: float
    claimed: bool = False
    to_say: list[str] = field(default_factory=list)


# Calls the app has started, so the voice service can find the patient's session for a call ID.
# shortcut: one process in memory, upgrade to a Postgres table when a second assistant container appears.
calls: dict[str, CallCtx] = {}

# The voice service (services/voice) talks to this API with a shared key; it never holds a patient's token.
INTERNAL_KEY = os.environ.get("ASSISTANT_INTERNAL_KEY", "")
# Languages the voice service can speak (ElevenLabs' multilingual model: all eight); anything else uses the phone's voice.
VOICE_LANGUAGES = set(os.environ.get("VOICE_LANGUAGES", "en,fr,nl,de,es,it,lt,sv").split(","))


def internal(x_internal_key: str = Header(...)) -> None:
    if not INTERNAL_KEY or x_internal_key != INTERNAL_KEY:
        raise HTTPException(401, "internal key")


def _call(call_id: str) -> CallCtx:
    ctx = calls.get(call_id)
    if ctx is None or time.time() - ctx.started > stream.TOKEN_TTL:
        raise HTTPException(404, "no such call")
    return ctx


def _spoken(reply: "Reply") -> str:
    """What Nora says aloud for a reply: the confirm card is read out, the button stays the only way to book."""
    if reply.confirm:
        return f"{reply.confirm.get('title', '')} {reply.confirm.get('detail', '')}".strip()
    return reply.reply or ""


class Reply(BaseModel):
    reply: str | None = None
    confirm: dict | None = None   # a booking or cancellation waiting for the patient's button
    team: bool = False            # this turn was passed to the clinic team: the app offers the team chat


def _config(w: Who, thread: str) -> dict:
    return {"configurable": {"thread_id": f"{w.user_id}:{thread}", "session": w.session, "clinic_phone": w.clinic_phone}}


def _run(channel: str, w: Who, what, thread: str) -> Reply:
    """One turn through the graph, timed and counted (metrics.py)."""
    started = time.monotonic()
    out = assistant.invoke(what, _config(w, thread))
    metrics.record(channel, w.session.language, time.monotonic() - started, out)
    return _reply(out)


def _reply(out: dict) -> Reply:
    if out.get("__interrupt__"):
        return Reply(confirm=out["__interrupt__"][0].value)
    messages = out["messages"]
    last = next((m for m in reversed(messages) if isinstance(m, AIMessage) and m.content), None)
    since = max((i for i, m in enumerate(messages) if isinstance(m, HumanMessage)), default=0)
    team = any(c["name"] == "handoff_to_staff" for m in messages[since:] if isinstance(m, AIMessage) for c in (m.tool_calls or []))
    return Reply(reply=str(last.content) if last else None, team=team)


@app.get("/metrics", include_in_schema=False)
def prometheus() -> Response:
    """For the collector on the private network. Not under /assistant/, so Nginx never publishes it."""
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/assistant/health")
def health() -> dict:
    return {"ok": True}


@app.get("/assistant/hello")
def hello(language: Language = "en") -> dict:
    """The fixed AI disclosure that opens every conversation (EU AI Act Article 50, US bot-disclosure laws)."""
    return {"reply": safety.fixed("disclosure", language)}


@app.post("/assistant/chat", response_model=Reply)
def chat(body: ChatIn, w: Who = Depends(who)) -> Reply:
    return _run("chat", w, {"messages": [HumanMessage(body.message)]}, body.thread)


@app.post("/assistant/confirm", response_model=Reply)
def confirm(body: ConfirmIn, w: Who = Depends(who)) -> Reply:
    return _run("chat", w, Command(resume=body.accept), body.thread)


@app.post("/assistant/call", response_model=CallTicket)  # under /assistant/, the prefix Nginx proxies
def start_call(w: Who = Depends(who)) -> CallTicket:
    """A random call ID and a one-hour Stream Video token for the signed-in patient (ADR 0015). The Stream user is
    the Supabase user ID; the patient's session and language are kept here for the agent that joins the call."""
    conf = stream.settings()
    if conf is None or w.session.language not in VOICE_LANGUAGES:
        raise HTTPException(503, "calls are not available")
    key, secret = conf
    now = time.time()
    # One live call per patient, and nothing older than a token: the store cannot grow with repeated taps.
    for old in [cid for cid, c in calls.items() if c.who.user_id == w.user_id or now - c.started > stream.TOKEN_TTL]:
        calls.pop(old, None)
    try:
        stream.register_user(w.user_id, key, secret)
    except httpx.HTTPError:
        raise HTTPException(503, "calls are not available")
    call_id = secrets.token_urlsafe(12)
    calls[call_id] = CallCtx(who=w, started=now)
    metrics.CALLS.labels(w.session.language).inc()
    return CallTicket(api_key=key, token=stream.user_token(w.user_id, secret), user_id=w.user_id, call_id=call_id)


class ConsultIn(BaseModel):
    appointment_id: str = Field(min_length=1, max_length=64)


VIDEO_SERVICE = "D9995"   # teledentistry, synchronous: the only visit type that has a video room


@app.post("/assistant/consult", response_model=CallTicket)
def consult(body: ConsultIn, w: Who = Depends(who)) -> CallTicket:
    """A one-hour token for the video room of one booked video consultation (ADR 0015). The visit is read with the
    patient's own session, so row level security only returns it if it is theirs; it must be booked and be a video
    consultation. Stream records and transcribes nothing on this call type."""
    conf = stream.settings()
    if conf is None:
        raise HTTPException(503, "video consultations are not available")
    try:
        rows = tools._get(w.session, "/appointments", select="id,status,location_services(services(code))",
                          id=f"eq.{body.appointment_id}")
    except httpx.HTTPError:
        raise HTTPException(503, "video consultations are not available")
    visit = rows[0] if rows else None
    if (visit is None or visit["status"] not in ("booked", "arrived")
            or (visit.get("location_services") or {}).get("services", {}).get("code") != VIDEO_SERVICE):
        raise HTTPException(404, "no such video consultation")
    key, secret = conf
    try:
        stream.register_user(w.user_id, key, secret)
    except httpx.HTTPError:
        raise HTTPException(503, "video consultations are not available")
    return CallTicket(api_key=key, token=stream.user_token(w.user_id, secret), user_id=w.user_id,
                      call_type="consult", call_id=f"consult-{visit['id']}")


@app.post("/assistant/consult/{call_id}/team", response_model=CallTicket, dependencies=[Depends(internal)])
def consult_team(call_id: str) -> CallTicket:
    """A token for the team member who takes the consultation. Internal key only: the staff portal will call this."""
    conf = stream.settings()
    if conf is None or not call_id.startswith("consult-"):
        raise HTTPException(404, "no such consultation")
    key, secret = conf
    try:
        stream.register_user(stream.TEAM, key, secret, name="Northgate team", role="admin")
    except httpx.HTTPError:
        raise HTTPException(503, "video consultations are not available")
    return CallTicket(api_key=key, token=stream.user_token(stream.TEAM, secret), user_id=stream.TEAM,
                      call_type="consult", call_id=call_id)


class TeamChatTicket(BaseModel):
    """What the app needs to open the patient's conversation with the clinic team (ADR 0018)."""
    api_key: str
    token: str
    user_id: str
    channel_id: str
    team_id: str = stream.TEAM


@app.post("/assistant/team-chat", response_model=TeamChatTicket)
def team_chat(w: Who = Depends(who)) -> TeamChatTicket:
    """The signed-in patient's own channel with the team, and a one-hour token for it. The channel is named after the
    verified session, so nobody can ask for someone else's."""
    conf = stream.settings()
    if conf is None:
        raise HTTPException(503, "team chat is not available")
    key, secret = conf
    try:
        channel = stream.team_channel(w.user_id, key, secret)
    except httpx.HTTPError:
        raise HTTPException(503, "team chat is not available")
    return TeamChatTicket(api_key=key, token=stream.user_token(w.user_id, secret), user_id=w.user_id, channel_id=channel)


class TeamReplyIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)


@app.post("/assistant/team-chat/{channel_id}/reply", status_code=204, dependencies=[Depends(internal)])
def team_chat_reply(channel_id: str, body: TeamReplyIn) -> None:
    """A reply from the team. Internal key only: the staff portal will call this once it exists."""
    conf = stream.settings()
    if conf is None or not channel_id.startswith("team-"):
        raise HTTPException(404, "no such conversation")
    try:
        stream.team_reply(channel_id, body.message, *conf)
    except httpx.HTTPError:
        raise HTTPException(502, "the reply was not delivered")


class TurnIn(BaseModel):
    message: str = Field(min_length=1, max_length=2000)


class PendingCall(BaseModel):
    call_id: str
    call_type: str = "nora_voice"
    language: str


@app.get("/assistant/calls/pending", response_model=list[PendingCall], dependencies=[Depends(internal)])
def pending_calls() -> list[PendingCall]:
    """Calls nobody has joined yet; the voice service claims them and joins each one as Nora."""
    out = []
    for cid, ctx in calls.items():
        if not ctx.claimed and time.time() - ctx.started < 120:
            ctx.claimed = True
            out.append(PendingCall(call_id=cid, language=ctx.who.session.language))
    return out


@app.post("/assistant/call/{call_id}/turn", response_model=Reply, dependencies=[Depends(internal)])
def call_turn(call_id: str, body: TurnIn) -> Reply:
    """What the patient said on the call, as text, through the same graph as the chat (gate first). The identity is
    the session kept for the call, never anything the voice service sends."""
    ctx = _call(call_id)
    return _run("call", ctx.who, {"messages": [HumanMessage(body.message)]}, f"call-{call_id}")


@app.post("/assistant/call/{call_id}/confirm", response_model=Reply)
def call_confirm(call_id: str, body: ConfirmIn, w: Who = Depends(who)) -> Reply:
    """The patient's Confirm or Not now on the call screen: the only write path in a call, with the verified session.
    Nora then says the outcome: the voice service collects it from /say."""
    ctx = _call(call_id)
    if ctx.who.user_id != w.user_id:
        raise HTTPException(403, "not your call")
    # the call's language: the button's request carries none. Everything else is this request's verified session.
    w = replace(w, session=replace(w.session, language=ctx.who.session.language))
    reply = _run("call", w, Command(resume=body.accept), f"call-{call_id}")
    ctx.to_say.append(_spoken(reply))
    return reply


@app.get("/assistant/call/{call_id}/say", response_model=list[str], dependencies=[Depends(internal)])
def call_say(call_id: str) -> list[str]:
    """Replies waiting to be spoken (after a Confirm); each is handed out once."""
    ctx = _call(call_id)
    out, ctx.to_say = ctx.to_say, []
    return out
