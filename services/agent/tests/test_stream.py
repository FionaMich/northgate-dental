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
    monkeypatch.setattr(stream, "register_user", lambda user_id, key, secret, http=None, **kw: registered.append(user_id))
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


def test_the_team_chat_ticket_is_for_the_patients_own_channel_and_tells_stream_no_name(client, monkeypatch):
    signed_in(monkeypatch)
    sent = []
    monkeypatch.setattr(api.stream, "_server", lambda key, secret, http, path, body: sent.append((path, body)) or {})
    ticket = client.post("/assistant/team-chat", headers={"Authorization": "Bearer good"}).json()
    assert ticket["channel_id"] == "team-user-1" and ticket["user_id"] == "user-1" and ticket["team_id"] == "northgate-team"
    users = next(body for path, body in sent if path == "/users")["users"]
    assert users["user-1"] == {"id": "user-1", "name": "Patient", "role": "user"}, "an opaque ID and a fixed name, nothing else"
    channel = next(body for path, body in sent if path.endswith("/query"))
    assert sorted(channel["data"]["members"]) == ["northgate-team", "user-1"]
    assert client.post("/assistant/team-chat").status_code == 422, "no session, no ticket"


def test_only_the_internal_key_can_write_as_the_team(client, monkeypatch):
    sent = []
    monkeypatch.setattr(api.stream, "_server", lambda key, secret, http, path, body: sent.append((path, body)) or {})
    monkeypatch.setattr(api, "INTERNAL_KEY", "internal")
    url = "/assistant/team-chat/team-user-1/reply"
    assert client.post(url, json={"message": "Hello"}, headers={"X-Internal-Key": "wrong"}).status_code == 401
    assert sent == []
    assert client.post(url, json={"message": "Hello, this is Sam."}, headers={"X-Internal-Key": "internal"}).status_code == 204
    assert sent == [("/channels/messaging/team-user-1/read", {"user_id": "northgate-team"}),
                    ("/channels/messaging/team-user-1/message", {"message": {"text": "Hello, this is Sam.", "user_id": "northgate-team"}})]
    assert client.post("/assistant/team-chat/other/reply", json={"message": "x"}, headers={"X-Internal-Key": "internal"}).status_code == 404


def test_a_reply_that_handed_over_tells_the_app_to_offer_the_team_chat():
    handed = {"messages": [api.HumanMessage("a person please"),
                           api.AIMessage("", tool_calls=[{"name": "handoff_to_staff", "args": {}, "id": "1"}]),
                           api.AIMessage("I've passed this to our team.")]}
    assert api._reply(handed).team is True
    assert api._reply({"messages": [api.HumanMessage("hours?"), api.AIMessage("We open at 07:00.")]}).team is False


def test_a_video_room_is_only_for_the_patients_own_booked_video_consultation(client, monkeypatch):
    signed_in(monkeypatch)
    visits = {"v-video": {"id": "v-video", "status": "booked", "location_services": {"services": {"code": "D9995"}}},
              "v-clean": {"id": "v-clean", "status": "booked", "location_services": {"services": {"code": "D1110"}}},
              "v-gone": {"id": "v-gone", "status": "cancelled", "location_services": {"services": {"code": "D9995"}}}}
    # the patient's session only ever returns their own visits (row level security); someone else's is just absent
    monkeypatch.setattr(api.tools, "_get", lambda session, path, **p: [v for k, v in visits.items() if p["id"] == f"eq.{k}"])
    post = lambda vid: client.post("/assistant/consult", json={"appointment_id": vid}, headers={"Authorization": "Bearer good"})
    ticket = post("v-video").json()
    assert ticket["call_type"] == "consult" and ticket["call_id"] == "consult-v-video" and registered[-1] == "user-1"
    assert post("v-clean").status_code == 404, "a cleaning has no video room"
    assert post("v-gone").status_code == 404, "a cancelled visit has no video room"
    assert post("someone-elses").status_code == 404
    assert client.post("/assistant/consult", json={"appointment_id": "v-video"}).status_code == 422, "no session"
    url = "/assistant/consult/consult-v-video/team"
    assert client.post(url, headers={"X-Internal-Key": "wrong"}).status_code == 401
    team = client.post(url, params={"name": "Dr Hannah Brooks"}, headers={"X-Internal-Key": "internal"}).json()
    assert team["user_id"] == "staff-dr-hannah-brooks" and team["call_id"] == "consult-v-video"
    assert client.post("/assistant/consult/other/team", headers={"X-Internal-Key": "internal"}).status_code == 404


def test_a_patient_message_to_the_team_is_checked_for_red_flags_first(client, monkeypatch):
    signed_in(monkeypatch)
    sent, alerts = [], []
    monkeypatch.setattr(api.stream, "_server", lambda key, secret, http, path, body: sent.append((path, body)) or {})
    monkeypatch.setattr(api.tools, "_rpc", lambda session, name, **p: alerts.append((name, p)))
    ok = client.post("/assistant/team-chat/send", json={"message": "Is parking free at Quincy?"},
                     headers={"Authorization": "Bearer good"})
    assert ok.json() == {"emergency": None}
    assert sent == [("/channels/messaging/team-user-1/message", {"message": {"text": "Is parking free at Quincy?", "user_id": "user-1"}})]
    assert alerts == []
    sent.clear()
    urgent = client.post("/assistant/team-chat/send", json={"message": "My mouth won't stop bleeding after the extraction"},
                         headers={"Authorization": "Bearer good"}).json()
    assert urgent["emergency"] and "911" in urgent["emergency"], "the emergency text comes at once"
    assert sent[1][1]["message"]["type"] == "system", "and is posted in the conversation as a system line"
    assert alerts[0][0] == "request_handover" and alerts[0][1]["category"] == "emergency"
    summary = alerts[0][1]["summary"]
    assert "heavy_bleeding" in summary and "mouth" not in summary and "extraction" not in summary, "flags, not words"


def test_home_reads_where_the_team_conversation_stands(monkeypatch):
    from agent import stream as st
    def channel(messages, unread):
        return lambda key, secret, http, path, body: {"channels": [{"messages": messages, "read": [
            {"user": {"id": "u1"}, "unread_messages": unread}]}]}
    notice = {"type": "system", "user": {"id": "northgate-team"}}
    mine = {"type": "regular", "user": {"id": "u1"}}
    team = {"type": "regular", "user": {"id": "northgate-team"}}
    monkeypatch.setattr(st, "_server", lambda *a, **k: {"channels": []})
    assert st.team_status("u1", "k", "s") == {"state": "none", "unread": 0}
    monkeypatch.setattr(st, "_server", channel([notice, mine], 0))
    assert st.team_status("u1", "k", "s")["state"] == "waiting"
    monkeypatch.setattr(st, "_server", channel([notice, mine, team], 1))
    assert st.team_status("u1", "k", "s") == {"state": "unread", "unread": 1}
    monkeypatch.setattr(st, "_server", channel([notice, mine, team], 0))
    assert st.team_status("u1", "k", "s")["state"] == "open"
