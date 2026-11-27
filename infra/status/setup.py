"""Sets up the Northgate status page in Uptime Kuma: the database, the admin account (first run only), the monitors and
the public page. Safe to run again: existing monitors are matched by name and left as they are.

Run on the VM (Kuma's dashboard listens on 127.0.0.1:3001 only):
    uv run --with uptime-kuma-api==1.2.1 python infra/status/setup.py http://127.0.0.1:3001
It asks for the admin username and password; on the first run they create the account. Nothing is stored or printed."""

import getpass
import sys
import time

import requests
from uptime_kuma_api import MonitorType, UptimeKumaApi

SLUG = "northgate"
DOMAIN = "84-12-126-31.sslip.io"
SUPABASE = "https://dxkfsslymzqbgtoijuut.supabase.co"   # staging; not a secret

# Name, URL, how often in seconds, and the group on the page. Each checks what a patient would notice.
MONITORS = [
    ("Website", "https://northgate-dental.vercel.app/", 300, "Patients"),
    ("Services and prices", "https://northgate-dental.vercel.app/services/", 300, "Patients"),
    ("Nora (assistant API)", f"https://{DOMAIN}/assistant/health", 120, "Patients"),
    ("Payment and visit links", f"https://n8n.{DOMAIN}/webhook/visit?t=status-check", 300, "Patients"),
    ("Front door (WAF)", f"https://{DOMAIN}/health", 120, "Platform"),
    ("Database API", f"{SUPABASE}/auth/v1/health", 300, "Platform"),   # 401 without a key still proves it answers
]


def setup_database(url: str) -> None:
    info = requests.get(f"{url}/setup-database-info", timeout=10).json()
    if info.get("needSetup"):
        requests.post(f"{url}/setup-database", json={"dbConfig": {"type": "sqlite"}}, timeout=30).raise_for_status()
    for _ in range(90):   # Kuma restarts itself after choosing the database; wait until its app answers again
        try:
            if requests.get(f"{url}/api/entry-page", timeout=5).ok:
                return
        except requests.RequestException:
            pass
        time.sleep(2)
    raise SystemExit("Kuma did not come back after setting up its database")


def main(url: str) -> None:
    setup_database(url)
    user = input("Kuma admin username: ").strip()
    password = getpass.getpass("Kuma admin password: ")
    for attempt in range(3):   # a Kuma that has just restarted can drop the first connection; every step is idempotent
        try:
            return configure(url, user, password)
        except Exception as error:
            if attempt == 2:
                raise
            print(f"retrying after {type(error).__name__}")
            time.sleep(5)


def configure(url: str, user: str, password: str) -> None:
    with UptimeKumaApi(url, timeout=30) as api:
        if api.need_setup():
            api.setup(user, password)
        api.login(user, password)

        have = {m["name"]: m["id"] for m in api.get_monitors()}
        for name, target, every, _ in MONITORS:
            if name not in have:
                # the visit link page answers 200 with "expired" for an unknown token: the page is up
                data = api._build_monitor_data(type=MonitorType.HTTP, name=name, url=target, interval=every,
                                               maxretries=2, accepted_statuscodes=["200-299", "401"] if "supabase" in target else ["200-299"])
                # shortcut: the client is written for Kuma 1.23; Kuma 2 also needs `conditions`. Upgrade when the
                # client supports Kuma 2.
                data["conditions"] = "[]"
                have[name] = api._call("add", data)["monitorID"]

        if SLUG not in {p["slug"] for p in api.get_status_pages()}:
            api.add_status_page(SLUG, "Northgate Dental status")
        groups = {}
        for name, _, _, group in MONITORS:
            groups.setdefault(group, []).append({"id": have[name]})
        config = {   # Kuma's own saveStatusPage event: the client's helper reads fields Kuma 2 no longer sends
            "slug": SLUG, "title": "Northgate Dental status", "icon": "/icon.svg", "theme": "light",
            "description": "Live checks of what patients use: the website, Nora, payment and visit links, and the "
                           "platform behind them.",
            "footerText": "Fictional practice: generated test data, no real patients.",
            "autoRefreshInterval": 300, "showTags": False, "showPoweredBy": False, "showCertificateExpiry": False,
            "customCSS": "", "domainNameList": [], "logo": "/icon.svg", "analyticsType": None,   # no analytics
        }
        api._call("saveStatusPage", (SLUG, config, "/icon.svg",
                                     [{"name": g, "monitorList": ms} for g, ms in groups.items()]))
    print(f"ok: {len(MONITORS)} monitors on https://status.{DOMAIN}/status/{SLUG}")


if __name__ == "__main__":
    main(sys.argv[1].rstrip("/"))
