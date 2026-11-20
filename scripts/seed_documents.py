#!/usr/bin/env python3
"""Share synthetic practice documents with patients: a bitewing X-ray image for each exam and a one-page
PDF visit summary for each visit. Every file says SYNTHETIC. Standard library only.

Needs SUPABASE_URL and SUPABASE_SECRET_KEY in the environment (local: from `supabase status -o env`;
staging: Fiona's secret key from the dashboard, never committed). Safe to run again: files and rows that
already exist are left alone.

    SUPABASE_URL=... SUPABASE_SECRET_KEY=... python3 -I scripts/seed_documents.py --patients 20
"""

import argparse
import json
import os
import random
import struct
import sys
import urllib.error
import urllib.request
import zlib

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


# --- A stylised bitewing X-ray, drawn pixel by pixel ------------------------------------------------------

FONT = {  # 5x7 capitals, enough for the watermark
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    " ": ["00000"] * 7,
}


def bitewing_png(seed: int, width=640, height=360) -> bytes:
    rnd = random.Random(seed)
    mid, teeth = height // 2, 5
    span = width / teeth
    crowns = []  # (cx, cy, half-width, half-height, upper?, filled?)
    for t in range(teeth):
        cx = span * (t + 0.5) + rnd.uniform(-4, 4)
        for upper in (True, False):
            crowns.append((cx, mid - 52 if upper else mid + 52, span * 0.42, 46, upper, rnd.random() < 0.2))

    def tooth(x, y):
        """0 outside; otherwise a brightness: bright enamel rim, softer dentin, dark pulp, white fillings."""
        for cx, cy, w, h, upper, filled in crowns:
            dx, dy = (x - cx) / w, (y - cy) / h
            r = dx ** 4 + dy ** 4
            if r <= 1:
                if filled and (dx * 2.6) ** 2 + ((dy + (0.4 if upper else -0.4)) * 3.4) ** 2 < 1:
                    return 252
                if dx * dx * 4 + dy * dy * 3 < 0.35:
                    return 120  # pulp chamber
                return 212 if r > 0.55 else 172
            # two tapered roots running away from the bite
            depth = (cy - h - y) if upper else (y - cy - h)
            if 0 < depth < 120:
                taper = w * 0.42 * (1 - depth / 135)
                for off in (-w * 0.38, w * 0.38):
                    if abs(x - (cx + off * (1 - depth / 260))) < taper:
                        return 150 if abs(x - (cx + off)) > taper * 0.35 else 105  # root canal shows darker
        return 0

    px = []
    for y in range(height):
        row = []
        for x in range(width):
            vignette = 1 - (((x - width / 2) / width) ** 2 + ((y - height / 2) / height) ** 2) * 0.9
            v = tooth(x, y) or 24 * vignette
            row.append(max(0, min(255, int(v + rnd.gauss(0, 5)))))
        px.append(row)
    for _ in range(2):  # soften edges like film
        px = [[sum(px[yy][xx] for yy in (max(0, y - 1), y, min(height - 1, y + 1)) for xx in (max(0, x - 1), x, min(width - 1, x + 1))) // 9
               for x in range(width)] for y in range(height)]
    # watermark
    scale, x, y = 4, 18, 14
    for ch in "SYNTHETIC":
        for r, row in enumerate(FONT[ch]):
            for c, bit in enumerate(row):
                if bit == "1":
                    for dy in range(scale):
                        for dx in range(scale):
                            px[y + r * scale + dy][x + c * scale + dx] = 235
        x += 6 * scale
    raw = b"".join(b"\x00" + bytes(row) for row in px)

    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# --- A one-page PDF visit summary -------------------------------------------------------------------------

def pdf(lines: list[str]) -> bytes:
    def esc(s):
        return s.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)").encode("latin-1", "replace").decode("latin-1")

    text = ["BT /F1 20 Tf 56 780 Td (" + esc(lines[0]) + ") Tj ET"]
    y = 750
    for line in lines[1:]:
        text.append(f"BT /F1 11 Tf 56 {y} Td ({esc(line)}) Tj ET")
        y -= 18
    stream = "\n".join(text).encode("latin-1")
    objs = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        b"<< /Length " + str(len(stream)).encode() + b" >>\nstream\n" + stream + b"\nendstream",
    ]
    out, offsets = bytearray(b"%PDF-1.4\n"), []
    for i, body in enumerate(objs, 1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objs) + 1}\n0000000000 65535 f \n".encode()
    out += b"".join(f"{o:010d} 00000 n \n".encode() for o in offsets)
    out += f"trailer\n<< /Size {len(objs) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


KIND_TITLE = {"exam": "Exam", "hygiene": "Hygiene visit", "treatment": "Treatment", "emergency": "Emergency visit", "consultation": "Consultation"}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--patients", type=int, default=20, help="how many patients (lowest record numbers first)")
    args = parser.parse_args()
    if not URL or not KEY:
        sys.exit("Set SUPABASE_URL and SUPABASE_SECRET_KEY first.")

    status, patients = call("GET", f"/rest/v1/patients?select=id,given_name,family_name,mrn&order=mrn&limit={args.patients}")
    if status != 200:
        sys.exit(f"could not read patients ({status})")
    shared = 0
    for p in patients:
        status, visits = call(
            "GET",
            "/rest/v1/encounters?select=id,occurred_at,kind,reason,locations(name),practitioners(display_name),"
            "dental_procedures(tooth,surface,status,fee_cents,location_services(services(name)))"
            f"&patient_id=eq.{p['id']}&order=occurred_at",
        )
        for v in visits if status == 200 else []:
            day = v["occurred_at"][:10]
            clinic = (v.get("locations") or {}).get("name", "Northgate Dental").replace(" (synthetic)", "")
            dentist = (v.get("practitioners") or {}).get("display_name", "")
            docs = []
            if v["kind"] == "exam":
                docs.append(("xray", f"Bitewing X-rays, {day}", f"{p['id']}/{v['id']}-bitewing.png", "image/png",
                             bitewing_png(hash(v["id"]) & 0xFFFFFFFF)))
            lines = [f"Visit summary: {KIND_TITLE.get(v['kind'], 'Visit')}",
                     "SYNTHETIC RECORD. Not a real patient or practice.", "",
                     f"Patient: {p['given_name']} {p['family_name']} ({p['mrn']})",
                     f"Date: {day}    Clinic: Northgate Dental, {clinic}", f"Dentist: {dentist}"]
            if v.get("reason"):
                lines.append(f"Reason for visit: {v['reason']}")
            lines += ["", "What was done:"]
            for d in v.get("dental_procedures") or []:
                name = ((d.get("location_services") or {}).get("services") or {}).get("name", "Procedure")
                tooth = f", tooth {d['tooth']}" + (f" ({d['surface']})" if d.get("surface") else "") if d.get("tooth") else ""
                lines.append(f"  - {name}{tooth}: {d['status']}, ${d['fee_cents'] / 100:,.2f}")
            lines += ["", "Questions? Message us in the Northgate Dental app."]
            docs.append(("visit_summary", f"Visit summary, {day}", f"{p['id']}/{v['id']}-summary.pdf", "application/pdf", pdf(lines)))

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
    print(f"shared {shared} documents with {len(patients)} patients")  # counts only, never names


if __name__ == "__main__":
    main()
