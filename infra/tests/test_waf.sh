#!/usr/bin/env bash
# Proves the front door: normal requests pass, attacks are refused (403), plain HTTP moves to HTTPS,
# security headers are set, the server does not name itself, floods get 429 and the access log has no query strings.
# Needs the stack running (scripts/issue-certs.sh). Usage: infra/tests/test_waf.sh [https://host:port]
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
set -a
# shellcheck source=/dev/null
source .env
set +a
base="${1:-https://$DOMAIN:${HTTPS_PORT:-443}}"
plain="http://$DOMAIN:${HTTP_PORT:-80}"
fails=0

check() { # name, expected, actual
  if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected $2, got $3"; fails=$((fails + 1)); fi
}
status() { curl -sk -o /dev/null -w '%{http_code}' "$@"; }

check "health passes" 200 "$(status "$base/health")"
check "root page is served" 200 "$(status "$base/")"
check "unknown path is 404, not an error page" 404 "$(status "$base/nothing-here")"
check "cross-site scripting in a query is refused" 403 "$(status "$base/health?q=<script>alert(1)</script>")"
check "SQL injection in a query is refused" 403 "$(status "$base/health?id=1'%20OR%20'1'='1")"
check "SQL injection in a form body is refused" 403 "$(status -X POST -d "user=admin' UNION SELECT password FROM users--" "$base/health")"
check "path traversal is refused" 403 "$(status "$base/health?file=../../../../etc/passwd")"
check "shell command injection is refused" 403 "$(status "$base/health?cmd=;cat%20/etc/passwd")"
check "the n8n editor is not on the internet" 404 "$(status -H "Host: n8n.$DOMAIN" "$base/")"
check "the n8n API is not on the internet" 404 "$(status -H "Host: n8n.$DOMAIN" "$base/rest/login")"
check "plain HTTP redirects to HTTPS" 301 "$(status "$plain/health")"
check "Let's Encrypt challenge path is served over HTTP" 404 "$(status "$plain/.well-known/acme-challenge/missing")"

headers="$(curl -sk -D - -o /dev/null "$base/health" | tr -d '\r' | tr '[:upper:]' '[:lower:]')"
for h in strict-transport-security x-content-type-options x-frame-options referrer-policy content-security-policy; do
  check "header $h is set" yes "$(grep -q "^$h:" <<<"$headers" && echo yes || echo no)"
done
for path in /nothing-here "/health?q=<script>alert(1)</script>"; do
  check "error page for $path names no software" no "$(curl -sk "$base$path" | grep -qi nginx && echo yes || echo no)"
done
check "server header is hidden" no "$(grep -q '^server:' <<<"$headers" && echo yes || echo no)"

check "TLS 1.1 is refused" fail "$(curl -sk --tls-max 1.1 -o /dev/null "$base/health" 2>/dev/null && echo pass || echo fail)"

codes="$(for _ in $(seq 1 120); do status "$base/health" & done; wait)"
check "a flood gets 429 Too Many Requests" yes "$(grep -q 429 <<<"$codes" && echo yes || echo no)"

sleep 2 # let the flood's limit drain, so the canary request takes the normal path
curl -sk -o /dev/null "$base/health?token=CANARY-7F3A9"
check "query strings never reach the logs" clean \
  "$(docker compose logs waf --since 1m 2>/dev/null | grep -v 'ModSecurity' | grep -q 'CANARY-7F3A9' && echo leaked || echo clean)"

echo "$fails failure(s)"
exit $((fails > 0))
