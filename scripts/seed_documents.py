#!/usr/bin/env python3
"""Share practice documents with synthetic patients: a real, openly licensed X-ray for each exam (scripts/xrays,
credited in CREDITS.md) and a branded one-page PDF visit summary for each visit. Standard library only.

Needs SUPABASE_URL and SUPABASE_SECRET_KEY in the environment (local: from `supabase status -o env`;
staging: Fiona's secret key from the dashboard, never committed). Safe to run again: files and rows that
already exist are left alone.

    SUPABASE_URL=... SUPABASE_SECRET_KEY=... python3 -I scripts/seed_documents.py --patients 20
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime
from zoneinfo import ZoneInfo

URL = os.environ.get("SUPABASE_URL", "").rstrip("/")
KEY = os.environ.get("SUPABASE_SECRET_KEY", "")
BUCKET = "patient-documents"


def call(method, path, body=None, headers=None):
    req = urllib.request.Request(URL + path, data=body, method=method)
    req.add_header("apikey", KEY)
    req.add_header("Authorization", f"Bearer {KEY}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=60) as res:
            data = res.read()
            return res.status, json.loads(data) if data and data[:1] in b"[{" else data
    except urllib.error.HTTPError as e:
        return e.code, e.read()


# --- Real X-rays (see scripts/xrays/CREDITS.md), rotated across each patient's exams --------------------------

XRAY_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "xrays")
XRAYS = [  # file, title, what it shows
    ("bitewing-calculus.jpg", "Bitewing X-ray", "general"),
    ("periapical-apical-periodontitis.jpg", "Periapical X-ray", "root"),
    ("panoramic-restorations.jpg", "Panoramic X-ray", "general"),
    ("caries-molar-wisdom-tooth.jpg", "Bitewing X-ray", "decay"),
    ("panoramic-adult.jpg", "Panoramic X-ray", "general"),
    ("caries-secondary-arrow.jpg", "Bitewing X-ray", "decay"),
]


def pick_xray(images, findings, turn):
    """A visit where the dentist noted decay gets a decay X-ray; a root problem gets the periapical; others take turns."""
    noted = {f["condition"] for f in findings}
    wanted = "decay" if "caries" in noted else "root" if noted & {"root_canal", "fractured"} else None
    matches = [img for img in images if img[3] == wanted] if wanted else []
    return (matches or images)[turn % len(matches or images)]


# --- A branded one-page PDF visit summary ---------------------------------------------------------------

# Helvetica advance widths (per 1000 units) for the characters we print; others fall back to 556.
_W = {**{c: 556 for c in "0123456789$#?"}, " ": 278, ".": 278, ",": 278, ":": 278, "-": 333, "(": 333, ")": 333, "|": 260,
      "/": 278, "'": 191, "I": 278, "i": 222, "l": 222, "j": 222, "t": 278, "f": 278, "r": 333, "m": 833, "w": 722, "W": 944, "M": 833}
_WB = {**_W, "t": 333, "r": 389, "i": 278, "l": 278, "f": 333}


def text_width(s: str, size: float, bold=False) -> float:
    table = _WB if bold else _W
    fallback = (722, 600) if bold else (667, 556)  # Helvetica-Bold letters run wider than regular
    return sum(table.get(ch, fallback[0] if ch.isupper() else fallback[1]) for ch in s) * size / 1000


def _hex(rgb: str) -> str:
    r, g, b = (int(rgb[k:k + 2], 16) / 255 for k in (1, 3, 5))
    return f"{r:.3f} {g:.3f} {b:.3f}"


class Page:
    """A tiny PDF drawing surface: rectangles, lines, text, and the Northgate tooth mark."""

    def __init__(self):
        self.ops = []

    def rect(self, x, y, w, h, fill):
        self.ops.append(f"{_hex(fill)} rg {x:.1f} {y:.1f} {w:.1f} {h:.1f} re f")

    def line(self, x1, y1, x2, y2, colour, width=0.6):
        self.ops.append(f"{_hex(colour)} RG {width} w {x1:.1f} {y1:.1f} m {x2:.1f} {y2:.1f} l S")

    def text(self, x, y, s, size=10, colour="#0B2B2A", bold=False, align="left"):
        if align == "right":
            x -= text_width(s, size, bold)
        s = s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)").encode("latin-1", "replace").decode("latin-1")
        self.ops.append(f"BT /{'F2' if bold else 'F1'} {size} Tf {_hex(colour)} rg {x:.1f} {y:.1f} Td ({s}) Tj ET")

    def tooth(self, x, y, h, fill, stroke):
        """The app's tooth mark (lib/design/art.dart), drawn h points tall with its top-left at (x, y)."""
        w = h * 160 / 214
        pt = lambda px, py: (x + (px - 20) * w / 160, y - (py - 6) * h / 214)
        curves = [[82, 16, 44, 12, 31, 40], [20, 64, 27, 95, 37, 120], [45, 140, 47, 170, 55, 196], [61, 214, 77, 212, 81, 194],
                  [86, 171, 90, 152, 100, 152], [110, 152, 114, 171, 119, 194], [123, 212, 139, 214, 145, 196],
                  [153, 170, 155, 140, 163, 120], [173, 95, 180, 64, 169, 40], [156, 12, 118, 16, 100, 32]]
        sx, sy = pt(100, 32)
        path = [f"{sx:.1f} {sy:.1f} m"]
        for c in curves:
            pts = [pt(c[k], c[k + 1]) for k in (0, 2, 4)]
            path.append(" ".join(f"{a:.1f} {b:.1f}" for a, b in pts) + " c")
        self.ops.append(f"{_hex(fill)} rg {_hex(stroke)} RG 1.4 w " + " ".join(path) + " h B")

    def pdf(self) -> bytes:
        stream = "\n".join(self.ops).encode("latin-1")
        objs = [
            b"<< /Type /Catalog /Pages 2 0 R >>",
            b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
            b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>",
            b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding >>",
            b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
        ]
        out, offsets = bytearray(b"%PDF-1.4\n"), []
        for n, body in enumerate(objs, 1):
            offsets.append(len(out))
            out += f"{n} 0 obj\n".encode() + body + b"\nendobj\n"
        xref = len(out)
        out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode() + b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
        out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R /Info << /Title (Visit summary) /Producer (Northgate Dental) >> >>\nstartxref\n{xref}\n%%EOF\n".encode()
        return bytes(out)


DEEP, TEAL, MINT, MIST, LINE, MUTED, APRICOT = "#0C4C46", "#137C6C", "#8FE3C8", "#F1F6F5", "#D6E3E0", "#4C6361", "#B35F1E"
SURFACES = {"M": "front", "O": "top", "D": "back", "B": "cheek side", "L": "tongue side", "F": "lip side", "I": "biting edge"}
CONDITIONS = {"caries": "Decay", "filled": "Filling", "crown": "Crown", "missing": "Missing tooth", "implant": "Implant",
              "root_canal": "Root canal treated", "fractured": "Cracked", "sealant": "Sealant"}


def visit_summary_pdf(v: dict) -> bytes:
    """v: kind_title, when, clinic, clinic_address, dentist, reason, patient, mrn, dob, procedures[], findings[]."""
    pg = Page()
    # Header band with the tooth mark and wordmark.
    pg.rect(0, 752, 595, 90, DEEP)
    pg.tooth(44, 822, 50, DEEP, MINT)
    pg.text(92, 804, "Northgate", 22, "#FFFFFF", bold=True)
    pg.text(92 + text_width("Northgate ", 22, True), 804, "Dental", 22, MINT)
    pg.text(92, 786, "BACK BAY   |   CAMBRIDGE   |   QUINCY", 8, MINT)
    pg.text(551, 806, "VISIT SUMMARY", 10, MINT, bold=True, align="right")
    pg.text(551, 790, v["when"], 9, "#FFFFFF", align="right")
    # Title.
    pg.text(44, 698, v["kind_title"], 24, DEEP, bold=True)
    pg.text(44, 680, f"{v['clinic']} clinic   |   {v['dentist']}", 10, MUTED)
    # Two cards: patient and visit.
    for x, title, rows in ((44, "PATIENT", [("Name", v["patient"]), ("Record number", v["mrn"]), ("Date of birth", v["dob"])]),
                           (302, "VISIT", [("Clinic", f"Northgate Dental, {v['clinic']}"), ("Dentist", v["dentist"]), ("Reason", v.get("reason") or "Routine visit")])):
        pg.rect(x, 560, 249, 88, MIST)
        pg.text(x + 14, 630, title, 8, TEAL, bold=True)
        for k, (label, value) in enumerate(rows):
            y = 610 - k * 17
            pg.text(x + 14, y, label, 8.5, MUTED)
            pg.text(x + 98, y, value[:34], 9.5, DEEP, bold=True)
    # Procedures table.
    y = 528
    pg.text(44, y, "What was done", 13, DEEP, bold=True)
    y -= 26
    cols = [(54, "Treatment", "left"), (300, "Tooth", "left"), (348, "Surface", "left"), (430, "Status", "left"), (541, "Fee", "right")]
    pg.rect(44, y - 6, 507, 22, TEAL)
    for cx, head, align in cols:
        pg.text(cx, y + 1, head, 8.5, "#FFFFFF", bold=True, align=align)
    total = 0
    for n, p in enumerate(v["procedures"]):
        y -= 22
        if n % 2:
            pg.rect(44, y - 7, 507, 22, MIST)
        surface = ", ".join(SURFACES.get(ch, ch) for ch in (p.get("surface") or "")) or "-"
        cells = [p["name"][:40], p.get("tooth") or "-", surface, "Done" if p["status"] == "completed" else "Planned", f"${p['fee_cents'] / 100:,.2f}"]
        for (cx, _, align), cell in zip(cols, cells):
            colour = APRICOT if cell == "Planned" else DEEP
            pg.text(cx, y, cell, 9.5, colour, bold=cell == "Planned", align=align)
        total += p["fee_cents"]
    y -= 14
    pg.line(44, y, 551, y, LINE, 1)
    y -= 18
    pg.text(54, y, "Total before insurance", 10, MUTED, bold=True)
    pg.text(541, y, f"${total / 100:,.2f}", 12, DEEP, bold=True, align="right")
    # Findings.
    if v.get("findings"):
        y -= 40
        pg.text(44, y, "What the dentist noted", 13, DEEP, bold=True)
        for f in v["findings"]:
            y -= 20
            surface = (", " + ", ".join(SURFACES.get(ch, ch) for ch in f["surface"])) if f.get("surface") else ""
            pg.rect(48, y - 2, 6, 6, APRICOT)
            pg.text(62, y - 1, f"Tooth {f['tooth']}{surface}:  {CONDITIONS.get(f['condition'], f['condition'])}", 10, DEEP)
    # Next steps.
    if any(p["status"] != "completed" for p in v["procedures"]):
        y -= 40
        pg.rect(44, y - 30, 507, 44, MIST)
        pg.text(58, y - 2, "Next step", 9, TEAL, bold=True)
        pg.text(58, y - 18, "Your dentist has planned the treatment marked Planned. You can book it in the Northgate Dental app.", 9.5, DEEP)
    # Footer.
    pg.line(44, 70, 551, 70, LINE, 1)
    pg.text(44, 54, f"Northgate Dental, {v['clinic']} clinic, {v['clinic_address']}", 8, MUTED)
    pg.text(44, 41, "Questions about this visit? Message us in the Northgate Dental app.", 8, MUTED)
    pg.text(551, 41, "Page 1 of 1", 8, MUTED, align="right")
    return pg.pdf()


KIND_TITLE = {"exam": "Exam", "hygiene": "Hygiene visit", "treatment": "Treatment", "emergency": "Emergency visit", "consultation": "Consultation"}


def remove_drawn_xrays():
    """The first version shared computer-drawn PNG X-rays; take those files and rows away."""
    status, rows = call("GET", "/rest/v1/patient_documents?select=id,file_path&kind=eq.xray&content_type=eq.image/png")
    if status != 200 or not rows:
        return 0
    paths = [r["file_path"] for r in rows]
    for k in range(0, len(paths), 100):
        call("DELETE", f"/storage/v1/object/{BUCKET}", json.dumps({"prefixes": paths[k:k + 100]}).encode(), {"Content-Type": "application/json"})
    call("DELETE", "/rest/v1/patient_documents?kind=eq.xray&content_type=eq.image/png")
    return len(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--patients", type=int, default=20, help="how many patients (lowest record numbers first)")
    args = parser.parse_args()
    if not URL or not KEY:
        sys.exit("Set SUPABASE_URL and SUPABASE_SECRET_KEY first.")
    removed = remove_drawn_xrays()
    images = [(open(os.path.join(XRAY_DIR, f), "rb").read(), f, t, shows) for f, t, shows in XRAYS]

    status, patients = call("GET", f"/rest/v1/patients?select=id,given_name,family_name,mrn,date_of_birth&order=mrn&limit={args.patients}")
    if status != 200:
        sys.exit(f"could not read patients ({status})")
    shared = 0
    for p in patients:
        status, visits = call(
            "GET",
            "/rest/v1/encounters?select=id,occurred_at,kind,reason,"
            "locations(name,address_line,city,state,postal_code,time_zone),practitioners(display_name),"
            "dental_procedures(tooth,surface,status,fee_cents,location_services(services(name))),tooth_conditions(tooth,surface,condition)"
            f"&patient_id=eq.{p['id']}&order=occurred_at",
        )
        exams = 0
        for v in visits if status == 200 else []:
            loc = v.get("locations") or {}
            at = datetime.fromisoformat(v["occurred_at"]).astimezone(ZoneInfo(loc.get("time_zone") or "America/New_York"))
            day = at.strftime("%Y-%m-%d")
            docs = []
            if v["kind"] == "exam":
                data, fname, title, _ = pick_xray(images, v.get("tooth_conditions") or [], exams)
                exams += 1
                docs.append(("xray", f"{title}, {day}", f"{p['id']}/{v['id']}-{fname}", "image/jpeg", data))
            summary = {
                "kind_title": KIND_TITLE.get(v["kind"], "Visit"),
                "when": at.strftime("%A %d %B %Y, %H:%M").replace(" 0", " "),
                "clinic": (loc.get("name") or "Northgate Dental").replace(" (synthetic)", ""),
                "clinic_address": ", ".join(x for x in (loc.get("address_line"), loc.get("city"), f"{loc.get('state', '')} {loc.get('postal_code', '')}".strip()) if x),
                "dentist": (v.get("practitioners") or {}).get("display_name", "Northgate dentist"),
                "reason": v.get("reason"),
                "patient": f"{p['given_name']} {p['family_name']}",
                "mrn": p["mrn"],
                "dob": datetime.fromisoformat(p["date_of_birth"]).strftime("%d %B %Y").lstrip("0"),
                "procedures": [{"name": ((d.get("location_services") or {}).get("services") or {}).get("name", "Procedure"),
                                "tooth": d.get("tooth"), "surface": d.get("surface"), "status": d["status"], "fee_cents": d["fee_cents"]}
                               for d in v.get("dental_procedures") or []],
                "findings": v.get("tooth_conditions") or [],
            }
            docs.append(("visit_summary", f"Visit summary, {day}", f"{p['id']}/{v['id']}-summary.pdf", "application/pdf", visit_summary_pdf(summary)))

            for kind, title, path, ctype, data in docs:
                up, _ = call("POST", f"/storage/v1/object/{BUCKET}/{path}", data, {"Content-Type": ctype, "x-upsert": "true"})
                if up not in (200, 201):
                    print(f"upload failed ({up}) for one file; skipping", file=sys.stderr)
                    continue
                row = {"patient_id": p["id"], "encounter_id": v["id"], "kind": kind, "title": title, "file_path": path, "content_type": ctype}
                ins, _ = call("POST", "/rest/v1/patient_documents?on_conflict=file_path", json.dumps(row).encode(),
                              {"Content-Type": "application/json", "Prefer": "resolution=ignore-duplicates"})
                if ins in (200, 201, 204):
                    shared += 1
    print(f"removed {removed} drawn X-rays; shared {shared} documents with {len(patients)} patients")  # counts only, never names


if __name__ == "__main__":
    main()
