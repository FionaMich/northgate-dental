#!/usr/bin/env bash
# Proves Presidio removes every canary value (name, record number, member ID, phone, email) from a message,
# and that Presidio cannot be reached from outside its internal network.
set -euo pipefail
cd "$(dirname "$0")/.."
root="$(cd .. && pwd)"

docker compose up -d --wait presidio-analyzer presidio-anonymizer >/dev/null
out="$(docker compose exec -T presidio-analyzer python - < tests/presidio_check.py)"
echo "$out"
for e in PERSON NG_RECORD MEMBER_ID PHONE_NUMBER EMAIL_ADDRESS; do
  grep -q "$e" <<<"$out" || { echo "FAIL Presidio did not find $e"; exit 1; }
done
grep '^redacted:' <<<"$out" | "$root/scripts/canary-scan.sh"

# The data network is internal: no published port, so nothing on the host or the internet reaches Presidio.
if [ -n "$(docker port "$(docker compose ps -q presidio-analyzer)")" ]; then echo "FAIL Presidio has a published port"; exit 1; fi
echo "ok   Presidio has no published port"
