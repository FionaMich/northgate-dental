"""Stream tokens (ADR 0015): signed on the server for the verified user only, one hour, nothing but an opaque ID inside."""

import base64
import json

import pytest
from fastapi.testclient import TestClient

from agent import api, stream


def _claims(token: str) -> dict:
    payload = token.split(".")[1]
    return json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))


def test_the_token_names_only_the_user_id_and_dies_after_an_hour():
    claims = _claims(stream.user_token("user-uuid", "s3cret", now=1_000))
    assert claims == {"user_id": "user-uuid", "iat": 1_000, "exp": 4_600}


def test_the_signature_depends_on_the_secret():
    a, b = stream.user_token("u", "one", now=0), stream.user_token("u", "two", now=0)
    assert a.split(".")[:2] == b.split(".")[:2] and a.split(".")[2] != b.split(".")[2]


registered = []


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("STREAM_API_KEY", "key")
    monkeypatch.setenv("STREAM_API_SECRET", "secret")
    monkeypatch.setattr(api, "INTERNAL_KEY", "internal")
    monkeypatch.setattr(stream, "register_user", lambda user_id, key, secret, http=None: registered.append(user_id))
    api.calls.clear(); registered.clear()
    return TestClient(api.app)


def signed_in(monkeypatch, user="user-1"):
    class Res:
        def __init__(self, body): self.status_code, self._b = 200, body
        def json(self): return self._b
    class Db:
        def __init__(self, *a, **k): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *a): pass
        async def get(self, path, **k):
            return Res({"id": user}) if path == "/auth/v1/user" else Res([{"patient_id": "p1", "patients": None}])
    monkeypatch.setattr(api.httpx, "AsyncClient", Db)


def test_no_session_means_no_token(client, monkeypatch):
    # The session check talks to Supabase; an invalid token is refused before any Stream work happens.
    class Res:
        status_code = 401
        def json(self): return {}
    class Db:
        def __init__(self, *a, **k): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *a): pass
        async def get(self, *a, **k): return Res()
    monkeypatch.setattr(api.httpx, "AsyncClient", Db)
    assert client.post("/assistant/call", headers={"Authorization": "Bearer bad"}).status_code == 401


def test_a_signed_in_patient_gets_a_token_for_their_own_id(client, monkeypatch):
    class Res:
        def __init__(self, body): self.status_code, self._b = 200, body
        def json(self): return self._b
    class Db:
        def __init__(self, *a, **k): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *a): pass
        async def get(self, path, **k):
            return Res({"id": "user-1"}) if path == "/auth/v1/user" else Res([{"patient_id": "p1", "patients": None}])
    monkeypatch.setattr(api.httpx, "AsyncClient", Db)
    body = client.post("/assistant/call", headers={"Authorization": "Bearer good"}).json()
    assert body["api_key"] == "key" and body["user_id"] == "user-1" and body["call_type"] == "nora_voice"
    assert _claims(body["token"])["user_id"] == "user-1"
    assert "user-1" not in body["call_id"] and "p1" not in body["call_id"], "call IDs are random, never an identity"
    assert api.calls[body["call_id"]].who.user_id == "user-1", "the voice service can find the patient behind the call"
    assert registered == ["user-1"], "the Stream user is registered by the server before the app joins"
    second = client.post("/assistant/call", headers={"Authorization": "Bearer good"}).json()
    assert second["call_id"] != body["call_id"]
    assert body["call_id"] not in api.calls and second["call_id"] in api.calls, "one live call per patient"


def test_without_stream_keys_the_endpoint_says_calls_are_unavailable(client, monkeypatch):
    monkeypatch.delenv("STREAM_API_KEY")
    monkeypatch.delenv("STREAM_API_SECRET")
    class Res:
        def __init__(self, body): self.status_code, self._b = 200, body
        def json(self): return self._b
    class Db:
        def __init__(self, *a, **k): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *a): pass
        async def get(self, path, **k):
            return Res({"id": "user-1"}) if path == "/auth/v1/user" else Res([{"patient_id": "p1", "patients": None}])
    monkeypatch.setattr(api.httpx, "AsyncClient", Db)
    assert client.post("/assistant/call", headers={"Authorization": "Bearer good"}).status_code == 503


def test_the_voice_service_claims_a_call_once_and_speaks_through_the_graph(client, monkeypatch):
    signed_in(monkeypatch)
    call_id = client.post("/assistant/call", headers={"Authorization": "Bearer good"}).json()["call_id"]
    assert client.get("/assistant/calls/pending").status_code == 422, "no internal key, no list"
    assert client.get("/assistant/calls/pending", headers={"X-Internal-Key": "wrong"}).status_code == 401
    pending = client.get("/assistant/calls/pending", headers={"X-Internal-Key": "internal"}).json()
    assert [p["call_id"] for p in pending] == [call_id] and pending[0]["language"] == "en"
    assert client.get("/assistant/calls/pending", headers={"X-Internal-Key": "internal"}).json() == [], "claimed once"

    seen = {}
    class Graph:
        def invoke(self, state, config):
            seen["thread"] = config["configurable"]["thread_id"]
            seen["who"] = config["configurable"]["session"].patient_id
            return {"messages": [api.AIMessage("Quincy opens at 07:00.")]}
    monkeypatch.setattr(api, "assistant", Graph())
    reply = client.post(f"/assistant/call/{call_id}/turn", json={"message": "When does Quincy open?"},
                        headers={"X-Internal-Key": "internal"}).json()
    assert reply["reply"] == "Quincy opens at 07:00."
    assert seen == {"thread": f"user-1:call-{call_id}", "who": "p1"}, "identity comes from the call's session"
    assert client.post("/assistant/call/nope/turn", json={"message": "hi"}, headers={"X-Internal-Key": "internal"}).status_code == 404


def test_a_confirm_on_the_call_needs_the_patients_own_session_and_is_then_spoken(client, monkeypatch):
    signed_in(monkeypatch)
    call_id = client.post("/assistant/call", headers={"Authorization": "Bearer good"}).json()["call_id"]
    class Graph:
        def invoke(self, command, config):
            return {"messages": [api.AIMessage("Booked for Friday at 10:00.")]}
    monkeypatch.setattr(api, "assistant", Graph())
    signed_in(monkeypatch, user="someone-else")
    assert client.post(f"/assistant/call/{call_id}/confirm", json={"thread": "call-xxxxxxxx", "accept": True},
                       headers={"Authorization": "Bearer other"}).status_code == 403
    signed_in(monkeypatch)
    ok = client.post(f"/assistant/call/{call_id}/confirm", json={"thread": "call-xxxxxxxx", "accept": True},
                     headers={"Authorization": "Bearer good"})
    assert ok.status_code == 200 and ok.json()["reply"] == "Booked for Friday at 10:00."
    say = client.get(f"/assistant/call/{call_id}/say", headers={"X-Internal-Key": "internal"}).json()
    assert say == ["Booked for Friday at 10:00."]
    assert client.get(f"/assistant/call/{call_id}/say", headers={"X-Internal-Key": "internal"}).json() == [], "spoken once"


def test_a_language_the_voice_cannot_speak_falls_back_to_the_phone(client, monkeypatch):
    signed_in(monkeypatch)
    monkeypatch.setattr(api, "VOICE_LANGUAGES", {"en"})
    assert client.post("/assistant/call", headers={"Authorization": "Bearer good", "X-Language": "lt"}).status_code == 503


def test_registering_the_stream_user_sends_only_the_opaque_id_and_a_fixed_name():
    import httpx
    seen = {}
    def handler(request):
        seen["auth"] = request.headers["Authorization"]; seen["body"] = request.read()
        return httpx.Response(201, json={"users": {}})
    stream.register_user("user-uuid", "key", "s3cret", httpx.Client(transport=httpx.MockTransport(handler)))
    assert _claims(seen["auth"]) == {"server": True, "iat": _claims(seen["auth"])["iat"]}
    assert seen["body"] == b'{"users":{"user-uuid":{"id":"user-uuid","name":"Patient","role":"user"}}}'


def test_the_confirm_on_a_call_is_answered_in_the_calls_language(client, monkeypatch):
    signed_in(monkeypatch)
    call_id = client.post("/assistant/call", headers={"Authorization": "Bearer good", "X-Language": "de"}).json()["call_id"]
    seen = {}
    class Graph:
        def invoke(self, command, config):
            seen["language"] = config["configurable"]["session"].language
            return {"messages": [api.AIMessage("Gebucht.")]}
    monkeypatch.setattr(api, "assistant", Graph())
    client.post(f"/assistant/call/{call_id}/confirm", json={"thread": "call-xxxxxxxx", "accept": True},
                headers={"Authorization": "Bearer good"})   # the button sends no language of its own
    assert seen["language"] == "de"
