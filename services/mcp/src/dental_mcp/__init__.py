"""The Northgate dental-tools MCP server (blueprint section 09): public clinic tools that any MCP client can use, for
example Claude Desktop or another assistant. No patient data: every tool reads public information through the two
public database functions (public_catalogue and public_search_knowledge) with the publishable key, which grants
nothing else. Booking, paying and anything about a patient stay in the app and with Nora, under the patient's session.

    SUPABASE_URL=... SUPABASE_PUBLISHABLE_KEY=... dental-mcp                    # stdio, for desktop clients
    MCP_TRANSPORT=streamable-http dental-mcp                                    # HTTP on port 8300
"""
import os

import httpx
from mcp.server.mcpserver import MCPServer

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://dxkfsslymzqbgtoijuut.supabase.co").rstrip("/")
KEY = os.environ.get("SUPABASE_PUBLISHABLE_KEY", "")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "")      # optional: meaning search with bge-m3; keywords only without it
DAYS = ["", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

server = MCPServer(
    "northgate-dental", title="Northgate Dental", website_url="https://northgate-dental.vercel.app",
    instructions="Public information about Northgate Dental, a dental group with clinics at Back Bay, Cambridge and "
                 "Quincy in the Boston area: opening hours, services and prices, and the clinic's approved policies. "
                 "These tools hold no patient data. For booking, paying or anything about a patient, send people to "
                 "the Northgate app, where Nora, the AI receptionist, acts under their own sign-in.",
)


def _rpc(name: str, body: dict) -> object:
    r = httpx.post(f"{SUPABASE_URL}/rest/v1/rpc/{name}", json=body, timeout=20,
                   headers={"apikey": KEY, "Content-Type": "application/json"})
    r.raise_for_status()
    return r.json()


def _phone(e164: str) -> str:
    d = e164.removeprefix("+1")
    return f"({d[:3]}) {d[3:6]}-{d[6:]}" if len(d) == 10 else e164


def _hours(hours: list[dict]) -> str:
    lines, i = [], 0
    while i < len(hours):
        j = i
        while j + 1 < len(hours) and (hours[j + 1]["opens"], hours[j + 1]["closes"]) == (hours[i]["opens"], hours[i]["closes"]) \
                and hours[j + 1]["weekday"] == hours[j]["weekday"] + 1:
            j += 1
        days = DAYS[hours[i]["weekday"]] if i == j else f"{DAYS[hours[i]['weekday']]} to {DAYS[hours[j]['weekday']]}"
        lines.append(f"{days} {hours[i]['opens']} to {hours[i]['closes']}")
        i = j + 1
    return "; ".join(lines) + ("" if any(h["weekday"] == 7 for h in hours) else "; Sunday closed")


@server.tool()
def clinics() -> str:
    """The three Northgate clinics: address, phone number and opening hours (Boston time)."""
    data = _rpc("public_catalogue", {})
    return "\n".join(f"{c['name']}: {c['address']}, {c['city']}, {c['state']} {c['postal_code']}. Phone {_phone(c['phone'])}. "
                     f"Open {_hours(c['hours'])}." for c in data["locations"])


@server.tool()
def services_and_prices(clinic: str = "") -> str:
    """Every service with a one-line description, how long it takes, and the self-pay price at each clinic. Pass a
    clinic name (Back Bay, Cambridge or Quincy) to list only what that clinic offers."""
    data = _rpc("public_catalogue", {})
    codes = {c["name"].lower(): c["code"] for c in data["locations"]}
    only = codes.get(clinic.strip().lower()) if clinic else None
    if clinic and not only:
        return f"There is no Northgate clinic called {clinic!r}. The clinics are Back Bay, Cambridge and Quincy."
    names = {c["code"]: c["name"] for c in data["locations"]}
    lines = []
    for s in data["services"]:
        prices = {k: v for k, v in s["prices"].items() if not only or k == only}
        if not prices:
            continue
        cost = ", ".join(f"{names[k]} ${v / 100:,.0f}" for k, v in sorted(prices.items()))
        lines.append(f"{s['name']} ({s['duration_minutes']} minutes): {s['summary']} Price: {cost}.")
    return "\n".join(lines)


def _embed(text: str) -> str | None:
    if not OLLAMA_URL:
        return None
    try:
        r = httpx.post(f"{OLLAMA_URL}/api/embed", json={"model": "bge-m3", "input": text}, timeout=30)
        r.raise_for_status()
        return "[" + ",".join(f"{v:.6g}" for v in r.json()["embeddings"][0]) + "]"
    except httpx.HTTPError:
        return None   # keywords alone still find exact terms


@server.tool()
def clinic_policies(question: str) -> str:
    """Answers from Northgate's approved policy documents: cancellations and missed-visit fees, preparing for a
    visit, paying and payment plans, insurance, video consultations, children, records and privacy, parking and
    access, shop returns, urgent help, complaints. Ask in English; each passage names its document."""
    rows = _rpc("public_search_knowledge", {"query": question[:300], "query_embedding": _embed(question[:300]), "match_count": 5})
    kept = [r for r in rows if (r["similarity"] is not None and r["similarity"] >= 0.5) or (r["similarity"] is None and r["keyword_match"])]
    if not kept:
        return "No approved Northgate document answers this. The clinic team can help: call the clinic or ask Nora in the app."
    return "\n\n".join(f'From "{r["document_title"]}" ({r["heading"]}): {r["content"]}' for r in kept[:3])


@server.tool()
def how_to_book() -> str:
    """How to book, move, cancel or pay for a visit at Northgate Dental."""
    return ("Book, move, cancel and pay in the Northgate app, or ask Nora, the AI receptionist in the app, in any of "
            "eight languages: she books only after you press Confirm. Or call your clinic (see the clinics tool). "
            "Please give 24 hours notice to cancel or move a visit.")


def main() -> None:
    transport = os.environ.get("MCP_TRANSPORT", "stdio")
    if transport == "streamable-http":
        server.run(transport, host="0.0.0.0", port=int(os.environ.get("MCP_PORT", "8300")))
    else:
        server.run(transport)
