"""NoraBrain is a bridge, not a brain: what it speaks is exactly the API's reply, and only Nora's words reach the voice."""

import asyncio

import httpx
import pytest

from voice import agent


class FakeAgent:
    def __init__(self):
        self.events = []

    async def send_custom_event(self, data):
        self.events.append(data)


def brain_with(handler):
    http = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    b = agent.NoraBrain("call-1", http)
    b.agent = FakeAgent()
    return b


async def spoken(b, text):
    return [r async for r in b.simple_response(text)]


def test_the_reply_is_spoken_verbatim_and_the_patients_words_never_reach_the_voice():
    seen = {}
    def handler(request):
        seen["url"] = str(request.url); seen["key"] = request.headers.get("X-Internal-Key"); seen["body"] = request.content
        return httpx.Response(200, json={"reply": "Quincy opens at seven."})
    b = brain_with(handler)
    out = asyncio.run(spoken(b, "When does Quincy open?"))
    assert seen["url"].endswith("/assistant/call/call-1/turn") and b"When does Quincy open?" in seen["body"]
    assert out[-1].text == "Quincy opens at seven." and "Quincy open?" not in out[-1].text
    assert b.agent.events[-1] == {"kind": "caption", "who": "nora", "text": "Quincy opens at seven."}


def test_a_confirm_card_is_read_out_and_shown_but_never_booked_here():
    def handler(request):
        return httpx.Response(200, json={"reply": None, "confirm": {"title": "Book this visit?", "detail": "Friday at 10:00",
                                                                     "yes": "Confirm", "no": "Not now"}})
    b = brain_with(handler)
    out = asyncio.run(spoken(b, "yes please book it"))
    assert out[-1].text == "Book this visit? Friday at 10:00"
    kinds = [e["kind"] for e in b.agent.events]
    assert kinds == ["mood", "confirm", "caption"], "the card goes to the phone; the button is the only way to book"


def test_an_api_failure_becomes_a_fixed_apology_not_an_invented_answer():
    b = brain_with(lambda request: httpx.Response(500))
    out = asyncio.run(spoken(b, "book me in"))
    assert "something went wrong" in out[-1].text and "call your clinic" in out[-1].text
