"""Live smoke test: the real model (Ollama) drives the real graph; the database is faked. Not run in CI (slow, needs
Ollama). Run: uv run python evals/smoke_live_model.py"""
import time

from langchain_core.messages import HumanMessage
from langgraph.types import Command

from agent import graph, tools

CLINICS = "back-bay: Northgate Dental Back Bay, 1 Example Street, Boston; phone (617) 555-0110; open Mon 08:00-18:00\n" \
          "quincy: Northgate Dental Quincy, 3 Example Road, Quincy; phone (617) 555-0130; open Mon 07:00-15:00"
log = []


def rpc(_s, name, **params):
    log.append(name)
    return {"available_slots": [{"starts_at": "2026-11-27T15:00:00+00:00", "practitioner_id": "dr-1"},
                                {"starts_at": "2026-11-27T19:00:00+00:00", "practitioner_id": "dr-1"}],
            "hold_slot": "appt-1"}.get(name)


def get(_s, path, **params):
    return {"/locations": [{"id": "loc", "time_zone": "America/New_York", "code": "quincy", "name": "Quincy",
                            "address_line": "3 Example Road", "city": "Quincy", "phone": "(617) 555-0130", "location_hours": []}],
            "/services": [{"id": "svc"}],
            "/location_services": [{"price_cents": 11000, "services": {"code": "D1110", "name": "Adult cleaning"}}]}.get(path, [])


tools._rpc, tools._get = rpc, get
tools.clinic_info.func.__globals__["_get"] = get  # same module; explicit for clarity

CASES = [
    ("es", "Hola, quiero una limpieza en Quincy el 2026-11-27."),
    ("de", "Ich habe Zahnschmerzen, darf ich Ibuprofen nehmen?"),
    ("sv", "När öppnar kliniken i Quincy på måndag?"),
]
for lang, text in CASES:
    app = graph.build()
    cfg = {"configurable": {"thread_id": lang, "clinic_phone": "(617) 555-0130",
                            "session": tools.Session("x", "x", "x", "patient-1", lang)}}
    log.clear(); t = time.time()
    out = app.invoke({"messages": [HumanMessage(text)]}, cfg)
    if out.get("__interrupt__"):
        print(f"[{lang}] asks to confirm: {out['__interrupt__'][0].value}")
        out = app.invoke(Command(resume=True), cfg)
    tool_calls = [c["name"] for m in out["messages"] for c in (getattr(m, "tool_calls", None) or [])]
    print(f"[{lang}] {round(time.time() - t)}s tools={tool_calls} db={log}\n  -> {out['messages'][-1].content[:300]}\n")
