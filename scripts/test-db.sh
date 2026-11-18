#!/usr/bin/env bash
# Run the database tests locally exactly as CI does: fresh database, migrations, seed, generated sample, pgTAP.
# Needs only the Postgres container (supabase db start). Run before every push that touches supabase/.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
url=postgresql://postgres:postgres@127.0.0.1:54322/postgres
supabase stop --no-backup >/dev/null 2>&1 || true
supabase db start >/dev/null
until docker exec supabase_db_northgate-dental pg_isready -U postgres -q 2>/dev/null; do sleep 2; done
(cd services/synthdata && uv run --quiet synthdata check-target "$url" >/dev/null && uv run --quiet synthdata generate --patients 50 --seed 2026) \
  | docker exec -i supabase_db_northgate-dental psql -v ON_ERROR_STOP=1 -q -U postgres -d postgres
supabase test db
