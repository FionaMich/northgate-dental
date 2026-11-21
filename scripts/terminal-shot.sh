#!/usr/bin/env bash
# Turns command output into a terminal-style image for the portfolio:
#   some-command 2>&1 | scripts/terminal-shot.sh "<command as typed>" <out.png>
# Lines starting with "ok" are green and "FAIL" red. Never pipe secrets into it.
set -euo pipefail
cmd="$1"; out="$2"
root="$(cd "$(dirname "$0")/.." && pwd)"
html="$(mktemp --suffix=.html)"; trap 'rm -f "$html"' EXIT
py=$(cat <<'PY'
import html, sys
rows = []
for line in sys.stdin.read().rstrip("\n").split("\n"):
    cls = "ok" if line.startswith("ok") else "fail" if line.startswith("FAIL") else ""
    rows.append('<div class="%s">%s</div>' % (cls, html.escape(line) or "&nbsp;"))
print("".join(rows))
PY
)
body="$(python3 -I -c "$py")"
lines="$(grep -o "<div" <<<"$body" | wc -l)"
cat >"$html" <<HTML
<!doctype html><meta charset="utf-8"><style>
body{margin:0;background:#e9efee;font:15px/1.55 ui-monospace,"DejaVu Sans Mono",monospace}
.w{margin:28px;border-radius:12px;overflow:hidden;box-shadow:0 18px 40px -12px #0b2b2a55;background:#0d1f1e}
.t{background:#16302e;padding:10px 14px;display:flex;gap:8px;align-items:center;color:#9fd9cd;font-size:13px}
.t i{width:12px;height:12px;border-radius:50%;display:inline-block}.t span{margin-left:10px}
pre{margin:0;padding:18px 22px;color:#d7efe9;white-space:pre-wrap}.p{color:#1fbfa2}.ok{color:#5fe0b5}.fail{color:#ff7b72}
</style><div class="w"><div class="t"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i><span>northgate-dental</span></div>
<pre><div><span class="p">$ </span>$(python3 -I -c 'import html,sys;print(html.escape(sys.argv[1]))' "$cmd")</div>$body</pre></div>
HTML
height=$(( 130 + lines * 24 ))
CHROME="${CHROME:-}" "$root/scripts/shot.sh" "file://$html" "$out" "1100x$height" >/dev/null
# shot.sh uses a fixed window; trim the empty space below the terminal
python3 -I -c '
import sys
from PIL import Image, ImageChops
im = Image.open(sys.argv[1]).convert("RGB")
bg = Image.new("RGB", im.size, im.getpixel((2, 2)))
box = ImageChops.difference(im, bg).getbbox()
if box: im.crop((0, 0, im.width, min(im.height, box[3] + 56))).save(sys.argv[1])
' "$out"
echo "saved $out (${height}px of content)"
