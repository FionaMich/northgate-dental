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


def register_user(user_id: str, key: str, secret: str, http: httpx.Client | None = None) -> None:
    """Stream refuses a call for a user it has never seen, so the server registers the patient's Stream user when it
    issues the ticket: the opaque ID, the fixed display name "Patient" and the plain user role. Nothing else."""
    server = _jwt({"server": True, "iat": int(time.time())}, secret)
    client = http or httpx.Client(timeout=10)
    r = client.post(f"{API}/api/v2/users", params={"api_key": key},
                    headers={"Authorization": server, "stream-auth-type": "jwt"},
                    json={"users": {user_id: {"id": user_id, "name": "Patient", "role": "user"}}})
    r.raise_for_status()


def settings() -> tuple[str, str] | None:
    """API key and secret from the environment, or None when Stream is not configured (development without calls)."""
    key, secret = os.environ.get("STREAM_API_KEY"), os.environ.get("STREAM_API_SECRET")
    return (key, secret) if key and secret else None
