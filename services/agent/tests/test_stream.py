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


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("STREAM_API_KEY", "key")
    monkeypatch.setenv("STREAM_API_SECRET", "secret")
    return TestClient(api.app)


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
    assert api.calls[body["call_id"]][0].user_id == "user-1", "the agent can find the patient behind the call"
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
