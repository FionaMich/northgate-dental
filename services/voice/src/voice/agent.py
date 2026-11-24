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
import re
import time
from typing import AsyncIterator

import httpx
from faster_whisper.vad import get_speech_timestamps
from vision_agents.core import Agent, User, llm
from vision_agents.core.agents.events import AgentTurnEndedEvent, AgentTurnStartedEvent, UserTranscriptEvent
from vision_agents.core.edge.types import Participant
from vision_agents.core.llm.llm import LLMResponseDelta, LLMResponseFinal
from vision_agents.core.tts.events import TTSSynthesisCompleteEvent
from vision_agents.core.warmup import WarmupCache
from vision_agents.plugins import elevenlabs, fast_whisper, getstream

log = logging.getLogger("nora-voice")
ASSISTANT_URL = os.environ.get("ASSISTANT_URL", "http://127.0.0.1:8100").rstrip("/")
INTERNAL = {"X-Internal-Key": os.environ.get("ASSISTANT_INTERNAL_KEY", "")}
# Nora's voice: "Diane", ElevenLabs' warm receptionist voice; the multilingual Flash model speaks all eight languages.
NORA_VOICE_ID = os.environ.get("NORA_VOICE_ID", "u91OxrFDaRINovYRRue2")
NORA_VOICE_MODEL = os.environ.get("NORA_VOICE_MODEL", "eleven_flash_v2_5")
QUIET, MAX_QUESTION = 1.0, 30     # seconds of quiet that end the caller's turn; longest question kept
LINK = re.compile(r"https?://\S+")
PAY_LABEL = {"en": "Pay securely", "fr": "Payer en toute sécurité", "nl": "Veilig betalen", "de": "Sicher bezahlen",
             "es": "Pagar de forma segura", "it": "Paga in sicurezza", "lt": "Mokėti saugiai", "sv": "Betala säkert"}
EARS_HINT = "Nora at Northgate Dental."   # spelling of the names a caller is likely to say; never patient data


class Floor:
    """Who may speak. While Nora thinks or speaks she does not listen, so a cough, a television or her own voice
    coming back through the phone can never cut her answer short; the patient speaks once she has finished."""
    nora = True   # she greets first


class NoraBrain(llm.LLM):
    """The 'LLM' seen by Vision Agents: a thin bridge to the assistant API for one call. It holds no prompt, no tools
    and no identity: the API knows who is on the call from the session it kept when the call was started."""

    def __init__(self, call_id: str, http: httpx.AsyncClient, language: str = "en"):
        super().__init__()
        self.language = language
        self.call_id = call_id
        self.http = http
        self.agent: Agent | None = None
        self.floor = Floor()

    async def simple_response(self, text: str, participant: Participant | None = None
                              ) -> AsyncIterator[LLMResponseDelta | LLMResponseFinal]:
        self.floor.nora = True
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
        link = LINK.search(spoken)
        if link:   # a web address is for tapping, not for reading aloud: it becomes a button on the call screen
            spoken = LINK.sub("", spoken).rstrip(" :\n") + "."
            await self._event({"kind": "link", "url": link.group(0).rstrip(".,"),
                               "label": PAY_LABEL.get(self.language, PAY_LABEL["en"])})
        await self._event({"kind": "caption", "who": "nora", "text": spoken})
        if not spoken:
            self.floor.nora = False   # nothing to say, so nothing will end her turn
        yield LLMResponseDelta(delta=spoken, sequence_number=0, content_index=0)
        yield LLMResponseFinal(text=spoken, original=reply)

    async def _event(self, data: dict) -> None:
        if self.agent is not None:
            await self.agent.send_custom_event(data)


class NoraEars(fast_whisper.STT):
    """The plugin's Whisper, with silence skipped before it reaches the model.

    Without the filter the model spends seconds on every quiet buffer, falls behind the caller, and writes
    words nobody said ("Thank you."), which Nora then answers."""

    floor: Floor | None = None
    _caller = None
    _last_packet = 0.0
    _watch: asyncio.Task | None = None

    async def process_audio(self, pcm_data, participant):
        """Keeps the caller's audio until they stop; the whole question is transcribed in one piece, once."""
        if self.floor and self.floor.nora:
            return
        self._caller = participant
        self._audio_buffer = self._audio_buffer.append(pcm_data.resample(fast_whisper.stt.RATE).to_float32())
        self._last_packet = time.monotonic()
        if self._watch is None:
            self._watch = asyncio.create_task(self._listen())

    async def _listen(self) -> None:
        rate = fast_whisper.stt.RATE
        while not self.closed:
            await asyncio.sleep(0.25)
            audio = self._audio_buffer.samples
            if (self.floor and self.floor.nora) or audio.size > MAX_QUESTION * rate:
                self._audio_buffer.clear()
                continue
            if audio.size < rate // 2:
                continue
            speech = await asyncio.to_thread(get_speech_timestamps, audio)
            if not speech:
                continue
            # quiet = silence at the end of what arrived, plus the time since anything arrived (phones stop
            # sending in silence)
            quiet = (audio.size - speech[-1]["end"]) / rate + time.monotonic() - self._last_packet
            if quiet >= QUIET and self._caller is not None:
                await self._process_buffer(self._caller)

    async def _transcribe(self, audio_array):
        whisper = self.whisper
        if whisper is None:
            raise ValueError("Whisper model not loaded, call warmup() first")

        def work():
            segments, info = whisper.transcribe(
                audio_array, language=self.language, beam_size=1, vad_filter=True,
                condition_on_previous_text=False, initial_prompt=EARS_HINT,
            )
            return list(segments), info

        return await asyncio.get_running_loop().run_in_executor(self._executor, work)


def whisper_model(language: str) -> str:
    """English has its own smaller model, quick enough to keep up on a CPU; the other languages share one."""
    return os.environ.get("WHISPER_MODEL") or ("base.en" if language == "en" else "small")


async def create_agent(language: str = "en", call_id: str = "", **kwargs) -> Agent:
    http = httpx.AsyncClient()
    brain = NoraBrain(call_id, http, language)
    agent = Agent(
        edge=getstream.Edge(),
        agent_user=User(name="Nora", id="nora"),      # the app trusts events from this id only
        instructions="",                              # the real instructions live in the assistant API
        llm=brain,
        stt=NoraEars(model_size=whisper_model(language), language=language, device="cpu"),
        tts=elevenlabs.TTS(voice_id=NORA_VOICE_ID, model_id=NORA_VOICE_MODEL),
        # no turn detector: Nora's ears decide when the caller has finished, and she is never interrupted
    )
    brain.agent = agent
    agent.stt.floor = floor = brain.floor

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
    async def on_synthesised(event: TTSSynthesisCompleteEvent):
        # The framework ends the turn when the audio is queued; the patient hears it for audio_duration_ms more.
        # Turn-taking: "listening" only once Nora has really finished speaking.
        await asyncio.sleep((event.audio_duration_ms or 0) / 1000 + 0.3)
        floor.nora = False
        log.info("state %s idle", call_id)
        await agent.send_custom_event({"kind": "mood", "mood": "listening"})

    @agent.events.subscribe
    async def on_spoken(event: AgentTurnEndedEvent):
        if event.interrupted:
            floor.nora = False
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
            agent.llm.floor.nora = True   # type: ignore[attr-defined]
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


WARMUP = WarmupCache()


async def run_call(call: dict) -> None:
    """One agent per call, created and joined here (the framework's launcher cannot pass the language through), with
    the speech models loaded first, as the launcher would."""
    agent = await create_agent(language=call["language"], call_id=call["call_id"])
    await asyncio.gather(*(c.warmup(WARMUP) for c in (agent.stt, agent.tts) if hasattr(c, "warmup")))
    try:
        await join_call(agent, call["call_type"], call["call_id"], language=call["language"])
    except Exception:
        log.exception("call %s ended with an error", call["call_id"])
    finally:
        await agent.close()


async def claim_calls() -> None:
    """Poll for and join the calls the assistant API lists as pending. The API runs behind the WAF; this process can
    run anywhere with a network, so a laptop can serve a demo and the VM can serve the hosted demo."""
    # The English speech model is loaded before the first call, so the first caller is not kept waiting for it.
    await NoraEars(model_size=whisper_model("en"), language="en").warmup(WARMUP)
    log.info("ready for calls")
    async with httpx.AsyncClient() as http:
        while True:
            await asyncio.sleep(0.4)
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
    logging.getLogger("httpx").setLevel(logging.WARNING)   # one poll a second would drown the turn-state lines
    asyncio.run(claim_calls())


if __name__ == "__main__":
    main()
