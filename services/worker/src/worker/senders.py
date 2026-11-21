"""Where messages go. Resend for email; a fake that records sends for tests."""

import httpx

from .messages import Message


class SendError(Exception):
    pass


class ResendSender:
    """Resend's email API. The idempotency key makes Resend drop a repeat of the same send for 24 hours, a second guard
    behind the notification log. `redirect_to` sends everything to one inbox (staging: only the account owner can
    receive mail from Resend's shared sender)."""

    def __init__(self, api_key: str, sender: str, redirect_to: str | None = None):
        self._client = httpx.Client(base_url="https://api.resend.com", timeout=15,
                                    headers={"Authorization": f"Bearer {api_key}"})
        self._sender = sender
        self._redirect_to = redirect_to

    def send(self, to: str, message: Message, idempotency_key: str, attachments: list[dict] | None = None) -> str:
        body = {"from": self._sender, "to": [self._redirect_to or to],
                "subject": message.subject, "text": message.text, "html": message.html}
        if attachments:
            body["attachments"] = attachments  # [{"filename": ..., "content": base64}]
        response = self._client.post("/emails", headers={"Idempotency-Key": idempotency_key}, json=body)
        if response.status_code >= 300:
            raise SendError(f"resend returned {response.status_code}")  # status only, never the body: it may echo the address
        return response.json()["id"]


class FakeSender:
    def __init__(self):
        self.sent: list[tuple[str, Message, str]] = []
        self.attachments: list[list[dict]] = []

    def send(self, to: str, message: Message, idempotency_key: str, attachments: list[dict] | None = None) -> str:
        self.sent.append((to, message, idempotency_key))
        self.attachments.append(attachments or [])
        return f"fake-{len(self.sent)}"
