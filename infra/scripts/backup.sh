#!/usr/bin/env bash
# Nightly encrypted backup (blueprint section 52): dump the production database, encrypt it with age, keep three nights
# on the VM and upload the encrypted file to S3 with an upload-only key. Cron on the VM:
#   0 2 * * * deploy /opt/northgate/infra/scripts/backup.sh >> /var/log/northgate-backup.log 2>&1
# Without BACKUP_BUCKET it stops after encrypting (local testing). Section 07 adds n8n's database to the loop.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a
: "${SUPABASE_DB_URL:?}" "${BACKUP_AGE_PUBLIC_KEY:?}"

stamp="$(date -u +%Y%m%dT%H%MZ)"
dir="${BACKUP_DIR:-/opt/northgate/backups}"
mkdir -p "$dir" && chmod 700 "$dir"
umask 077
# A dump cut short (lost connection) must never stay on the VM unencrypted.
trap 'rm -f "$dir"/*.dump' EXIT

# pg_dump 17 to match Supabase's Postgres 17; the URL never appears in logs or process lists of other users.
docker run --rm --network host -e DB_URL="$SUPABASE_DB_URL" postgres:17.6-alpine \
  sh -c 'pg_dump "$DB_URL" -Fc --no-owner' > "$dir/supabase-$stamp.dump"

for f in "$dir"/*-"$stamp".dump; do
  age -r "$BACKUP_AGE_PUBLIC_KEY" -o "$f.age" "$f" && rm "$f"
  if [ -n "${BACKUP_BUCKET:-}" ]; then
    docker run --rm -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_REGION -v "$dir:/backups:ro" \
      amazon/aws-cli:2.31.0 s3 cp "/backups/$(basename "$f").age" "s3://$BACKUP_BUCKET/nightly/$(basename "$f").age" --only-show-errors
  fi
  echo "$(date -u +%FT%TZ) backed up $(basename "$f").age ($(stat -c %s "$f.age") bytes)"
done
find "$dir" -name '*.age' -mtime +3 -delete
