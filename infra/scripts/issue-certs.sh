#!/usr/bin/env bash
# Starts the front door and gets Let's Encrypt certificates (webroot method, blueprint section 52).
#   infra/scripts/issue-certs.sh                 placeholder only (local testing, or before DNS and ports are ready)
#   infra/scripts/issue-certs.sh --letsencrypt   real certificate for DOMAIN and each name in SUBDOMAINS
# Renewal (weekly cron on the VM): docker compose --profile tools run --rm certbot renew && docker compose exec waf nginx -s reload
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source .env; set +a

live=/etc/letsencrypt/live/northgate
compose() { docker compose "$@"; }
# The waf runs as nginx (uid and gid 101): let that group read the keys. Certbot keeps the key's group and mode on renewal.
let_waf_read() {
  compose --profile tools run --rm --entrypoint sh certbot -c \
    "mkdir -p /etc/letsencrypt/archive && chgrp -R 101 /etc/letsencrypt/live /etc/letsencrypt/archive && chmod -R g+rX,o-rwx /etc/letsencrypt/live /etc/letsencrypt/archive"
}

# Nginx refuses to start without a certificate, so a one-day self-signed one stands in until Certbot runs.
if ! compose --profile tools run --rm --entrypoint sh certbot -c "test -f $live/fullchain.pem"; then
  compose --profile tools run --rm --entrypoint sh certbot -c "
    mkdir -p $live && openssl req -x509 -nodes -newkey rsa:2048 -days 1 -subj '/CN=$DOMAIN' \
      -keyout $live/privkey.pem -out $live/fullchain.pem 2>/dev/null && touch $live/.placeholder"
fi
let_waf_read
compose up -d --wait waf

[ "${1:-}" = "--letsencrypt" ] || exit 0

domains=(-d "$DOMAIN")
for sub in ${SUBDOMAINS:-}; do domains+=(-d "$sub.$DOMAIN"); done

# Certbot will not write into a live folder it did not create, so the placeholder goes first; Nginx keeps serving it from memory.
compose --profile tools run --rm --entrypoint sh certbot -c \
  "if [ -f $live/.placeholder ]; then rm -rf $live /etc/letsencrypt/archive/northgate /etc/letsencrypt/renewal/northgate.conf; fi"
compose --profile tools run --rm certbot certonly --webroot -w /var/www/certbot --cert-name northgate \
  --register-unsafely-without-email --agree-tos --non-interactive --keep-until-expiring --expand "${domains[@]}"
let_waf_read
compose exec waf nginx -s reload
echo "certificate issued for: ${domains[*]//-d /}"
