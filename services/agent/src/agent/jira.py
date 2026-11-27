"""Handovers as tickets on the team's Jira board (ADR 0019). The staff inbox in our database stays the record; the
ticket is how the team sees and works the request. It carries the request in English, how to reply, the callback
number when the patient asked for a call, and the patient's record ID. Never a name, date of birth or address."""

import os

import httpx

SITE = os.environ.get("JIRA_SITE", "").rstrip("/")
PROJECT = os.environ.get("JIRA_PROJECT", "NGD")


def configured() -> bool:
    return bool(SITE and os.environ.get("JIRA_EMAIL") and os.environ.get("JIRA_API_TOKEN"))


def _paragraph(text: str) -> dict:
    return {"type": "paragraph", "content": [{"type": "text", "text": text}]}


def ticket(category: str, language: str, summary: str, reply_by: str, phone: str, patient_id: str,
           http: httpx.Client | None = None) -> str | None:
    """Creates the ticket and returns its key (NGD-12), or None when Jira is not set up. Errors are the caller's."""
    if not configured():
        return None
    how = f"Call the patient back on {phone}." if reply_by == "call" else "Reply to the patient in the app's team chat."
    body = {"fields": {
        "project": {"key": PROJECT},
        "issuetype": {"name": "Task"},
        "summary": f"[{category}] Patient request from Nora ({language}): {'call back' if reply_by == 'call' else 'reply in app'}",
        "labels": ["nora-handover", category, f"lang-{language}"],
        "description": {"type": "doc", "version": 1, "content": [
            _paragraph(f"What the patient needs: {summary}"),
            _paragraph(f"How to reply: {how}"),
            _paragraph(f"Patient record: {patient_id} (open it in the staff portal)."),
            _paragraph("Created by Nora, the AI receptionist. Do not give clinical advice by chat; book a visit instead."),
        ]},
    }}
    client = http or httpx.Client(timeout=15)
    r = client.post(f"{SITE}/rest/api/3/issue", json=body,
                    auth=(os.environ["JIRA_EMAIL"], os.environ["JIRA_API_TOKEN"]))
    r.raise_for_status()
    return r.json()["key"]
