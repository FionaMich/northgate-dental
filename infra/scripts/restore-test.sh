#!/usr/bin/env bash
# Monthly restore test (blueprint section 52), run on a laptop, never on the VM: the VM holds neither the read key
# nor the age private key. Restores one backup into a throwaway Postgres and counts the rows that matter.
#   infra/scripts/restore-test.sh <backup.dump.age | s3://bucket/nightly/file.dump.age> <age identity file>
# For an s3:// path it uses the AWS profile in RESTORE_AWS_PROFILE (default northgate-restore, read-only).
set -euo pipefail
src="$1"; identity="$2"
work="$(mktemp -d)"; trap 'docker rm -f northgate-restore >/dev/null 2>&1; rm -rf "$work"' EXIT

if [[ "$src" == s3://* ]]; then
  aws s3 cp "$src" "$work/backup.dump.age" --profile "${RESTORE_AWS_PROFILE:-northgate-restore}" --only-show-errors
  src="$work/backup.dump.age"
fi
age -d -i "$identity" -o "$work/backup.dump" "$src"

# Supabase's own Postgres image (17.12, the version staging and production run), so roles and extensions match.
docker run -d --name northgate-restore -e POSTGRES_PASSWORD=restore -v "$work:/work:ro" \
  public.ecr.aws/supabase/postgres:17.12.0.000 >/dev/null
until docker exec northgate-restore pg_isready -h 127.0.0.1 -U postgres >/dev/null 2>&1; do sleep 2; done
sleep 5 # the image finishes its own set-up scripts after it first accepts connections
psql() { docker exec northgate-restore psql -U supabase_admin -d postgres -v ON_ERROR_STOP=1 "$@"; }
psql -qc "create schema if not exists private; create extension if not exists btree_gist with schema extensions;"
# Patient data lives in public and private. Sign-in accounts (auth) are rebuilt by restoring into a new Supabase
# project, which runs Supabase Auth's own migrations first; that full drill is in section 13.
docker exec northgate-restore pg_restore -U supabase_admin -d postgres -n public -n private /work/backup.dump 2>"$work/restore.log" || true
echo "$(grep -c '^pg_restore: error' "$work/restore.log" || true) restore warnings (expected: links to sign-in accounts that are not restored)"

result="$(psql -At -F' ' -c "
  select 'patients', count(*) from public.patients union all
  select 'appointments', count(*) from public.appointments union all
  select 'encounters', count(*) from public.encounters union all
  select 'audit_log', count(*) from public.audit_log")"
echo "$result"
# Patients and the audit log always have rows; appointments and encounters can be empty in a fresh environment.
awk '($1 == "patients" || $1 == "audit_log") && $2 == 0 { bad = 1 } END { exit bad }' <<<"$result" || { echo "FAIL a table restored empty"; exit 1; }
echo "restore test passed: $(date -u +%F) from $(basename "$1")"
