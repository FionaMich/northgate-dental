"""Nora on a voice call (ADR 0015, section 11).

Stream carries the audio; Vision Agents runs the speech pipeline: fast-whisper (on our server) turns the patient's
voice into text, smart-turn (on our server) decides when they have finished, and ElevenLabs speaks the reply (ADR 0016:
Nora's reply text goes to ElevenLabs, US, synthetic data only). The brain is not here: every turn
goes to the assistant API (the same LangGraph graph as the chat, red-flag gate first), which also keeps the patient's
identity. The patient's Confirm button never passes through the call: it reaches the API with the patient's own session,
and the reply comes back here to be spoken.

What leaves our server: the patient's voice, between the phone and this process, through Stream (US East); Nora's reply
text, to ElevenLabs for the voice. What stays: the patient's words (transcripts go only to the assistant API), and
nothing is recorded.

Run: `uv run nora-voice`; it then claims calls the API lists as pending and joins each one as "nora"."""

import asyncio
import logging
import os
from typing import AsyncIterator

import httpx
from vision_agents.core import Agent, User, llm
from vision_agents.core.agents.events import (AgentTurnEndedEvent, AgentTurnStartedEvent, UserTranscriptEvent,
                                               UserTurnStartedEvent)
from vision_agents.core.edge.types import Participant
from vision_agents.core.llm.llm import LLMResponseDelta, LLMResponseFinal
from vision_agents.plugins import elevenlabs, fast_whisper, getstream, smart_turn

log = logging.getLogger("nora-voice")
ASSISTANT_URL = os.environ.get("ASSISTANT_URL", "http://127.0.0.1:8100").rstrip("/")
INTERNAL = {"X-Internal-Key": os.environ.get("ASSISTANT_INTERNAL_KEY", "")}
# Nora's voice: "Diane", ElevenLabs' warm receptionist voice; the multilingual Flash model speaks all eight languages.
NORA_VOICE_ID = os.environ.get("NORA_VOICE_ID", "u91OxrFDaRINovYRRue2")
NORA_VOICE_MODEL = os.environ.get("NORA_VOICE_MODEL", "eleven_flash_v2_5")


class NoraBrain(llm.LLM):
    """The 'LLM' seen by Vision Agents: a thin bridge to the assistant API for one call. It holds no prompt, no tools
    and no identity: the API knows who is on the call from the session it kept when the call was started."""

    def __init__(self, call_id: str, http: httpx.AsyncClient):
        super().__init__()
        self.call_id = call_id
        self.http = http
        self.agent: Agent | None = None

    async def simple_response(self, text: str, participant: Participant | None = None
                              ) -> AsyncIterator[LLMResponseDelta | LLMResponseFinal]:
        await self._event({"kind": "mood", "mood": "thinking"})
        try:
            r = await self.http.post(f"{ASSISTANT_URL}/assistant/call/{self.call_id}/turn", json={"message": text},
                                     headers=INTERNAL, timeout=180)
            r.raise_for_status()
            reply = r.json()
        except httpx.HTTPError:
            log.exception("assistant API failed for call %s", self.call_id)
            reply = {"reply": "I am sorry, something went wrong on my side. Please try again or call your clinic."}
        spoken = reply.get("reply") or ""
        if reply.get("confirm"):
            card = reply["confirm"]
            spoken = f"{card.get('title', '')} {card.get('detail', '')}".strip()
            await self._event({"kind": "confirm", "card": card})   # the buttons appear; nothing is booked by voice
        await self._event({"kind": "caption", "who": "nora", "text": spoken})
        yield LLMResponseDelta(delta=spoken, sequence_number=0, content_index=0)
        yield LLMResponseFinal(text=spoken, original=reply)

    async def _event(self, data: dict) -> None:
        if self.agent is not None:
            await self.agent.send_custom_event(data)


async def create_agent(language: str = "en", call_id: str = "", **kwargs) -> Agent:
    http = httpx.AsyncClient()
    brain = NoraBrain(call_id, http)
    agent = Agent(
        edge=getstream.Edge(),
        agent_user=User(name="Nora", id="nora"),      # the app trusts events from this id only
        instructions="",                              # the real instructions live in the assistant API
        llm=brain,
        stt=fast_whisper.STT(model_size=os.environ.get("WHISPER_MODEL", "small"), language=language,
                             device="cpu", compute_type="int8"),
        tts=elevenlabs.TTS(voice_id=NORA_VOICE_ID, model_id=NORA_VOICE_MODEL),
        turn_detection=smart_turn.TurnDetection(),
    )
    brain.agent = agent

    @agent.events.subscribe
    async def on_user_turn(event: UserTurnStartedEvent):
        log.info("state %s listening", call_id)   # the demo harness reads these lines for turn-taking
        await agent.send_custom_event({"kind": "mood", "mood": "listening"})

    @agent.events.subscribe
    async def on_transcript(event: UserTranscriptEvent):
        # The phone shows what Nora heard, so the patient can check it; the words stay between the phone and here.
        log.info("state %s heard", call_id)       # never the words themselves
        await agent.send_custom_event({"kind": "caption", "who": "you", "text": event.text})

    @agent.events.subscribe
    async def on_speaking(event: AgentTurnStartedEvent):
        log.info("state %s speaking", call_id)
        await agent.send_custom_event({"kind": "mood", "mood": "speaking"})

    @agent.events.subscribe
    async def on_spoken(event: AgentTurnEndedEvent):
        log.info("state %s idle", call_id)
        await agent.send_custom_event({"kind": "mood", "mood": "listening"})

    return agent


async def say_pending(agent: Agent, http: httpx.AsyncClient, call_id: str) -> None:
    """Replies the API queued after the patient pressed Confirm or Not now: spoken here, never through the model."""
    while True:
        await asyncio.sleep(0.7)
        try:
            lines = (await http.get(f"{ASSISTANT_URL}/assistant/call/{call_id}/say", headers=INTERNAL, timeout=10)).json()
        except httpx.HTTPError:
            continue
        for text in lines if isinstance(lines, list) else []:
            await agent.send_custom_event({"kind": "caption", "who": "nora", "text": text})
            await agent.say(text)


async def join_call(agent: Agent, call_type: str, call_id: str, **kwargs) -> None:
    call = await agent.create_call(call_type, call_id)
    brain: NoraBrain = agent.llm  # type: ignore[assignment]
    async with agent.join(call):
        hello = await brain.http.get(f"{ASSISTANT_URL}/assistant/hello", params={"language": kwargs.get("language", "en")},
                                     timeout=10)
        greeting = hello.json().get("reply", "") if hello.status_code == 200 else "Hello, I am Nora, an AI assistant."
        await agent.send_custom_event({"kind": "caption", "who": "nora", "text": greeting})
        await agent.say(greeting)                      # the fixed AI disclosure, never generated
        pending = asyncio.create_task(say_pending(agent, brain.http, call_id))
        try:
            await agent.finish()
        finally:
            pending.cancel()
            await brain.http.aclose()


async def run_call(call: dict) -> None:
    """One agent per call, created and joined here (the framework's launcher cannot pass the language through)."""
    agent = await create_agent(language=call["language"], call_id=call["call_id"])
    try:
        await join_call(agent, call["call_type"], call["call_id"], language=call["language"])
    except Exception:
        log.exception("call %s ended with an error", call["call_id"])
    finally:
        await agent.close()


async def claim_calls() -> None:
    """Every second, join the calls the assistant API lists as pending. The API runs behind the WAF; this process can
    run anywhere with a network, so a laptop can serve a demo and the VM can serve the hosted demo."""
    async with httpx.AsyncClient() as http:
        while True:
            await asyncio.sleep(1)
            try:
                r = await http.get(f"{ASSISTANT_URL}/assistant/calls/pending", headers=INTERNAL, timeout=10)
                calls = r.json() if r.status_code == 200 else []
            except httpx.HTTPError:
                continue
            for c in calls:
                log.info("joining call %s (%s)", c["call_id"], c["language"])
                asyncio.create_task(run_call(c))


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(message)s")
    asyncio.run(claim_calls())
