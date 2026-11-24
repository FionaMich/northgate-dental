"""HTTP API for the app's chat screen. Every request carries the patient's Supabase token; the service verifies it with
Supabase, finds the linked patient and their clinic's phone, and runs the graph with that identity. Conversations are
keyed by user and thread, so nobody can resume someone else's conversation.

LangSmith tracing turns on only when LANGSMITH_API_KEY is set, with inputs and outputs hidden (decision 2026-11-22):
traces show nodes, tools, timings and outcomes, never what the patient wrote."""

import os
import secrets
import time
from dataclasses import dataclass
from typing import Literal

import httpx
from fastapi import Depends, FastAPI, Header, HTTPException
from langchain_core.messages import AIMessage, HumanMessage
from langgraph.types import Command
from pydantic import BaseModel, Field

from . import graph, safety, stream
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


# Calls the app has started, so the Nora agent (next ticket) can find the patient's session for a call ID.
# shortcut: one process in memory, upgrade to a Postgres table when a second agent container appears.
calls: dict[str, tuple[Who, float]] = {}


class Reply(BaseModel):
    reply: str | None = None
    confirm: dict | None = None   # a booking or cancellation waiting for the patient's button


def _config(w: Who, thread: str) -> dict:
    return {"configurable": {"thread_id": f"{w.user_id}:{thread}", "session": w.session, "clinic_phone": w.clinic_phone}}


def _reply(out: dict) -> Reply:
    if out.get("__interrupt__"):
        return Reply(confirm=out["__interrupt__"][0].value)
    last = next((m for m in reversed(out["messages"]) if isinstance(m, AIMessage) and m.content), None)
    return Reply(reply=str(last.content) if last else None)


@app.get("/assistant/health")
def health() -> dict:
    return {"ok": True}


@app.get("/assistant/hello")
def hello(language: Language = "en") -> dict:
    """The fixed AI disclosure that opens every conversation (EU AI Act Article 50, US bot-disclosure laws)."""
    return {"reply": safety.fixed("disclosure", language)}


@app.post("/assistant/chat", response_model=Reply)
def chat(body: ChatIn, w: Who = Depends(who)) -> Reply:
    return _reply(assistant.invoke({"messages": [HumanMessage(body.message)]}, _config(w, body.thread)))


@app.post("/assistant/confirm", response_model=Reply)
def confirm(body: ConfirmIn, w: Who = Depends(who)) -> Reply:
    return _reply(assistant.invoke(Command(resume=body.accept), _config(w, body.thread)))


@app.post("/assistant/call", response_model=CallTicket)  # under /assistant/, the prefix Nginx proxies
def start_call(w: Who = Depends(who)) -> CallTicket:
    """A random call ID and a one-hour Stream Video token for the signed-in patient (ADR 0015). The Stream user is
    the Supabase user ID; the patient's session and language are kept here for the agent that joins the call."""
    conf = stream.settings()
    if conf is None:
        raise HTTPException(503, "calls are not available")
    key, secret = conf
    now = time.time()
    # One live call per patient, and nothing older than a token: the store cannot grow with repeated taps.
    for old in [cid for cid, (owner, started) in calls.items() if owner.user_id == w.user_id or now - started > stream.TOKEN_TTL]:
        calls.pop(old, None)
    call_id = secrets.token_urlsafe(12)
    calls[call_id] = (w, now)
    return CallTicket(api_key=key, token=stream.user_token(w.user_id, secret), user_id=w.user_id, call_id=call_id)
