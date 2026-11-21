"""The assistant's tools. Each one calls Supabase as the signed-in patient (their own token), so row level security
decides what the assistant can see and do, exactly as in the app. Identity is never a tool argument: the patient comes
from the verified session in the run configuration (blueprint section 31). Booking and cancelling pause the graph for
the patient's own confirmation button (LangGraph interrupt)."""

from dataclasses import dataclass
from datetime import date, datetime
from zoneinfo import ZoneInfo

import httpx
from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool
from langgraph.types import interrupt


@dataclass(frozen=True)
class Session:
    """Who is talking, set by the API from the verified token; the model never sees or sets it."""
    supabase_url: str
    publishable_key: str
    jwt: str
    patient_id: str
    language: str = "en"
    link_base: str = ""


def _session(config: RunnableConfig) -> Session:
    return config["configurable"]["session"]


def _db(s: Session) -> httpx.Client:
    return httpx.Client(base_url=f"{s.supabase_url}/rest/v1", timeout=15,
                        headers={"apikey": s.publishable_key, "Authorization": f"Bearer {s.jwt}"})


def _rpc(s: Session, name: str, **params):
    with _db(s) as db:
        r = db.post(f"/rpc/{name}", json=params)
    if r.status_code >= 300:
        raise ToolRefused(r.json().get("message", "refused") if r.headers.get("content-type", "").startswith("application/json") else "refused")
    return r.json() if r.content else None


def _get(s: Session, path: str, **params):
    with _db(s) as db:
        r = db.get(path, params=params)
    r.raise_for_status()
    return r.json()


class ToolRefused(Exception):
    """The database said no (a rule, a policy, a full slot). The message is written for patients."""


def _money(cents: int) -> str:
    return f"${cents // 100:,}.{cents % 100:02d}"


def _local(ts: str, tz: str) -> str:
    return datetime.fromisoformat(ts).astimezone(ZoneInfo(tz)).strftime("%A %d %B at %H:%M")


@tool
def clinic_info(config: RunnableConfig) -> str:
    """The three Northgate Dental clinics: code, name, address, phone and opening hours. Use for any question about
    where, when or how to contact a clinic."""
    rows = _get(_session(config), "/locations", select="code,name,address_line,city,phone,location_hours(weekday,opens,closes)",
                active="eq.true", order="name")
    days = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    out = []
    for r in rows:
        hours = ", ".join(f"{days[h['weekday']]} {h['opens'][:5]}-{h['closes'][:5]}"
                          for h in sorted(r["location_hours"], key=lambda h: h["weekday"]))
        out.append(f"{r['code']}: Northgate Dental {r['name']}, {r['address_line']}, {r['city']}; phone {r['phone']}; open {hours or 'see the app'}")
    return "\n".join(out)


@tool
def services(clinic_code: str, config: RunnableConfig) -> str:
    """Services a clinic offers that patients can book, with their code and price. Always use the code, never a
    translated name, when calling find_slots or book_visit."""
    rows = _get(_session(config), "/location_services", select="price_cents,services(code,name),locations!inner(code)",
                **{"locations.code": f"eq.{clinic_code}", "active": "eq.true"})
    return "\n".join(f"{r['services']['code']}: {r['services']['name']}, {_money(r['price_cents'])}" for r in rows) or "No services found."


def _ids(s: Session, clinic_code: str, service_code: str) -> tuple[str, str, str]:
    loc, svc, tz, _, _ = _named(s, clinic_code, service_code)
    return loc, svc, tz


def _named(s: Session, clinic_code: str, service_code: str) -> tuple[str, str, str, str, str]:
    loc = _get(s, "/locations", select="id,time_zone,name", code=f"eq.{clinic_code}")
    svc = _get(s, "/services", select="id,name", code=f"eq.{service_code}")
    if not loc or not svc:
        raise ToolRefused("unknown clinic or service code")
    return loc[0]["id"], svc[0]["id"], loc[0]["time_zone"], loc[0].get("name", clinic_code), svc[0].get("name", service_code)


def _card(s: Session, action: str, detail: str) -> dict:
    """What the app's confirmation card shows: in the patient's language, from the reviewed texts, never generated."""
    from .safety import fixed
    return {"action": action, "title": fixed(f"confirm_{action}", s.language), "detail": detail,
            "yes": fixed(f"yes_{action}", s.language), "no": fixed("not_now", s.language)}


@tool
def find_slots(clinic_code: str, service_code: str, day: str, config: RunnableConfig) -> str:
    """Free times for a service at a clinic, for one day (YYYY-MM-DD) and the two days after it. Each line gives a time
    and a slot reference to pass to book_visit."""
    s = _session(config)
    loc, svc, tz = _ids(s, clinic_code, service_code)
    date.fromisoformat(day)
    slots = _rpc(s, "available_slots", loc=loc, service=svc, from_day=day, days=3) or []
    lines = [f"{_local(x['starts_at'], tz)} (slot {x['starts_at']}|{x['practitioner_id']})" for x in slots[:12]]
    return "\n".join(lines) or "No free times on those days."


@tool
def book_visit(clinic_code: str, service_code: str, slot: str, config: RunnableConfig) -> str:
    """Book a visit in a slot from find_slots. The patient is asked to confirm with a button before anything is booked."""
    s = _session(config)
    loc, svc, tz, clinic, service = _named(s, clinic_code, service_code)
    starts, practitioner = slot.split("|")
    answer = interrupt(_card(s, "book", f"{service} · {_local(starts, tz)} · Northgate Dental, {clinic}"))
    if not answer:
        return "The patient chose not to book."
    held = _rpc(s, "hold_slot", loc=loc, service=svc, practitioner=practitioner, starts=starts, patient=s.patient_id)
    _rpc(s, "confirm_booking", appointment=held)
    return f"Booked for {_local(starts, tz)}. A confirmation email is on its way."


@tool
def my_visits(config: RunnableConfig) -> str:
    """The patient's own upcoming visits, with a reference for cancel_visit or pay_link."""
    s = _session(config)
    rows = _get(s, "/appointments", select="id,starts_at,location_services(services(name),locations(name,time_zone))",
                status="eq.booked", starts_at=f"gte.{datetime.now().astimezone().isoformat()}", order="starts_at")
    out = []
    for r in rows:
        ls = r["location_services"]
        out.append(f"{ls['services']['name']} at {ls['locations']['name']}, {_local(r['starts_at'], ls['locations']['time_zone'])} (ref {r['id']})")
    return "\n".join(out) or "No upcoming visits."


@tool
def cancel_visit(visit_ref: str, config: RunnableConfig) -> str:
    """Cancel one of the patient's upcoming visits (ref from my_visits). The patient confirms with a button first."""
    s = _session(config)
    visit = _get(s, "/appointments", select="starts_at,location_services(services(name),locations(name,time_zone))", id=f"eq.{visit_ref}")
    if not visit:
        raise ToolRefused("that visit is not one of yours")
    ls = visit[0]["location_services"]
    detail = f"{ls['services']['name']} · {_local(visit[0]['starts_at'], ls['locations']['time_zone'])} · Northgate Dental, {ls['locations']['name']}"
    if not interrupt(_card(s, "cancel", detail)):
        return "The patient kept the visit."
    _rpc(s, "cancel_appointment", appointment=visit_ref)
    return "Cancelled. A confirmation email is on its way."


@tool
def pay_link(visit_ref: str, config: RunnableConfig) -> str:
    """A secure link to pay for one of the patient's visits by card on Stripe's page. The price comes from the clinic's
    price list on the server."""
    s = _session(config)
    token = _rpc(s, "start_my_payment", appointment=visit_ref)
    return f"{s.link_base}/pay?t={token}"


@tool
def shop_search(query: str, config: RunnableConfig) -> str:
    """Products in the Northgate Dental shop matching a word (for example floss, sensitive, aligner, kids)."""
    word = "".join(c for c in query if c.isalnum() or c == " ")[:40]  # PostgREST filter syntax: letters only
    rows = _get(_session(config), "/shop_products", select="name,summary,price_cents,refill_interval_months",
                active="eq.true", **{"or": f"(name.ilike.*{word}*,summary.ilike.*{word}*)"})
    return "\n".join(f"{r['name']}: {r['summary']} {_money(r['price_cents'])}"
                     + (f", or as a refill every {r['refill_interval_months']} months" if r["refill_interval_months"] else "")
                     for r in rows[:8]) or "Nothing found; the Shop tab in the app has everything."


@tool
def handoff_to_staff(category: str, summary_in_english: str, config: RunnableConfig) -> str:
    """Pass the conversation to the clinic team. category is one of booking, billing, clinical_question, shop, other.
    Always use clinical_question for anything about symptoms, medicines or treatment advice. Write a short summary in
    English of what the patient needs, without diagnosing."""
    s = _session(config)
    _rpc(s, "request_handover", category=category, language=s.language, summary=summary_in_english[:600])
    return "handed_over"


ALL = [clinic_info, services, find_slots, book_visit, my_visits, cancel_visit, pay_link, shop_search, handoff_to_staff]
