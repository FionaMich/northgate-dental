"""Stream Video tokens (ADR 0015). The API secret stays here; the app gets a short-lived token for the signed-in user.

A Stream user token is a plain HS256 JWT, so the standard library is enough: no SDK and no JWT dependency."""

import base64
import hashlib
import hmac
import json
import os
import time

import httpx

TOKEN_TTL = 3600  # one hour: long enough for a consultation, short enough that a leaked token dies quickly


def _b64(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode()


def _jwt(claims: dict, secret: str) -> str:
    header = _b64(json.dumps({"alg": "HS256", "typ": "JWT"}, separators=(",", ":")).encode())
    payload = _b64(json.dumps(claims, separators=(",", ":")).encode())
    signature = hmac.new(secret.encode(), f"{header}.{payload}".encode(), hashlib.sha256).digest()
    return f"{header}.{payload}.{_b64(signature)}"


def user_token(user_id: str, secret: str, now: float | None = None) -> str:
    """A token that lets exactly this user join calls. `user_id` is the Supabase user ID, never a name."""
    iat = int(now if now is not None else time.time())
    return _jwt({"user_id": user_id, "iat": iat, "exp": iat + TOKEN_TTL}, secret)


API = os.environ.get("STREAM_API_URL", "https://video.stream-io-api.com")


def register_user(user_id: str, key: str, secret: str, http: httpx.Client | None = None,
                  name: str = "Patient", role: str = "user") -> None:
    """Stream refuses a call for a user it has never seen, so the server registers the patient's Stream user when it
    issues the ticket: the opaque ID, the fixed display name "Patient" and the plain user role. Nothing else."""
    server = _jwt({"server": True, "iat": int(time.time())}, secret)
    client = http or httpx.Client(timeout=10)
    r = client.post(f"{API}/api/v2/users", params={"api_key": key},
                    headers={"Authorization": server, "stream-auth-type": "jwt"},
                    json={"users": {user_id: {"id": user_id, "name": name, "role": role}}})
    r.raise_for_status()


CHAT_API = os.environ.get("STREAM_CHAT_URL", "https://chat.stream-io-api.com")
TEAM = "northgate-team"   # the one Stream user staff write as; who typed a reply is recorded on our side, not at Stream


def _server(key: str, secret: str, http: httpx.Client | None, path: str, body: dict) -> dict:
    client = http or httpx.Client(timeout=10)
    r = client.post(f"{CHAT_API}{path}", params={"api_key": key}, json=body,
                    headers={"Authorization": _jwt({"server": True, "iat": int(time.time())}, secret), "stream-auth-type": "jwt"})
    r.raise_for_status()
    return r.json()


def team_channel(user_id: str, key: str, secret: str, http: httpx.Client | None = None) -> str:
    """The patient's one conversation with the clinic team (ADR 0018), made if it does not exist. Stream learns the
    opaque user ID and the fixed name "Patient", as for calls; the words written in the chat are stored by Stream."""
    channel = f"team-{user_id}"
    _server(key, secret, http, "/users", {"users": {user_id: {"id": user_id, "name": "Patient", "role": "user"},
                                                     TEAM: {"id": TEAM, "name": "Northgate team", "role": "admin"}}})
    _server(key, secret, http, f"/channels/messaging/{channel}/query",
            {"data": {"members": [user_id, TEAM], "created_by_id": TEAM}})
    return channel


def team_notice(channel: str, text: str, key: str, secret: str, http: httpx.Client | None = None) -> None:
    """A system line in the conversation ("Request NGD-12 sent to the team"): shown centred, never as a person."""
    _server(key, secret, http, f"/channels/messaging/{channel}/message",
            {"message": {"text": text, "user_id": TEAM, "type": "system"}})


def patient_message(channel: str, user_id: str, text: str, key: str, secret: str,
                    http: httpx.Client | None = None) -> None:
    """The patient's message, sent by our server after the safety check, as the patient's own Stream user."""
    _server(key, secret, http, f"/channels/messaging/{channel}/message", {"message": {"text": text, "user_id": user_id}})


def team_status(user_id: str, key: str, secret: str, http: httpx.Client | None = None) -> dict:
    """Where the patient's team conversation stands: none, waiting (their message is last), unread (the team replied
    and they have not read it) or open. Read on our server, so the phone needs no Stream connection for Home."""
    out = _server(key, secret, http, "/channels", {"filter_conditions": {"id": f"team-{user_id}"}, "state": True,
                                                    "user_id": user_id, "limit": 1, "message_limit": 30})
    channels = out.get("channels") or []
    if not channels:
        return {"state": "none", "unread": 0}
    ch = channels[0]
    mine = next((r for r in ch.get("read") or [] if (r.get("user") or {}).get("id") == user_id), {})
    unread = int(mine.get("unread_messages") or 0)
    said = [m for m in ch.get("messages") or [] if m.get("type") != "system"]
    if not said:
        return {"state": "open" if ch.get("messages") else "none", "unread": 0}
    if unread:
        return {"state": "unread", "unread": unread}
    return {"state": "waiting" if (said[-1].get("user") or {}).get("id") == user_id else "open", "unread": 0}


def team_reply(channel: str, text: str, key: str, secret: str, http: httpx.Client | None = None) -> None:
    """A message from the team into a patient's conversation: for the staff portal, and for the demo until it exists."""
    # Whoever answers has read what came before: the patient's ticks turn blue.
    _server(key, secret, http, f"/channels/messaging/{channel}/read", {"user_id": TEAM})
    _server(key, secret, http, f"/channels/messaging/{channel}/message", {"message": {"text": text, "user_id": TEAM}})


def settings() -> tuple[str, str] | None:
    """API key and secret from the environment, or None when Stream is not configured (development without calls)."""
    key, secret = os.environ.get("STREAM_API_KEY"), os.environ.get("STREAM_API_SECRET")
    return (key, secret) if key and secret else None
