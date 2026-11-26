#!/usr/bin/env bash
# Puts new secrets on the server (and in the local voice .env) without them ever being shown or typed into chat.
#   scripts/set-secrets.sh grafana    Grafana Cloud token for metrics (then starts the collector)
#   scripts/set-secrets.sh jira       Atlassian email and API token, so handovers become Jira tickets
#   scripts/set-secrets.sh rotate     new ElevenLabs key and Stream key and secret (then restarts the voice and assistant)
# Each value is read with typing hidden, sent over the Bastion SSH connection on standard input, and written to
# /opt/northgate/infra/.env; nothing is passed on a command line, so nothing lands in shell history or process lists.
set -euo pipefail
cd "$(dirname "$0")/.."

ask() { local v; read -rsp "$1: " v; echo >&2; [ -n "$v" ] || { echo "empty, stopping" >&2; exit 1; }; printf '%s=%s\n' "$2" "$v"; }

case "${1:-}" in
  grafana)
    lines=$(ask "Grafana Cloud access policy token (starts glc_)" GRAFANA_PROM_TOKEN)
    restart="docker compose --profile monitoring up -d alloy" ;;
  jira)
    lines=$(ask "Atlassian account email" JIRA_EMAIL
            ask "Atlassian API token" JIRA_API_TOKEN)
    restart="docker compose --profile assistant up -d --force-recreate assistant" ;;
  rotate)
    lines=$(ask "New ElevenLabs API key (starts sk_)" ELEVENLABS_API_KEY
            ask "Stream API key" STREAM_API_KEY
            ask "New Stream API secret" STREAM_API_SECRET)
    restart="docker compose --profile assistant --profile voice up -d --force-recreate assistant voice" ;;
  *) echo "usage: $0 grafana|jira|rotate" >&2; exit 2 ;;
esac

# The local voice service reads services/voice/.env when run on this machine; keep it in step.
if [ "$1" = rotate ] && [ -f services/voice/.env ]; then
  while IFS='=' read -r k v; do
    sed -i "/^$k=/d" services/voice/.env; printf '%s=%s\n' "$k" "$v" >> services/voice/.env   # any character is safe
  done <<< "$lines"
fi

printf '%s\n' "$lines" | infra/scripts/ssh-vm.sh deploy "
  set -e; f=/opt/northgate/infra/.env
  while IFS='=' read -r k v; do
    [ -n \"\$k\" ] || continue
    sed -i \"/^\$k=/d\" \$f; printf '%s=%s\n' \"\$k\" \"\$v\" >> \$f
    echo \"set \$k\"
  done
  cd /opt/northgate/infra && $restart 2>&1 | tail -2"
echo "done"
