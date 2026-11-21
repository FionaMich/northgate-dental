#!/usr/bin/env bash
# Signs in to the private VM through Oracle Bastion (the VM has no public IP; ADR 0009).
#   infra/scripts/ssh-vm.sh [user] [command...]     user defaults to deploy
# Reuses an active session or opens a new one for 3 hours. Needs ~/.oci/config, the OCI CLI and the Terraform state.
set -euo pipefail
user="${1:-deploy}"; shift || true
key="$HOME/.ssh/northgate_oracle"
tf() { terraform -chdir="$(dirname "$0")/../terraform/oci" output -raw "$1"; }
bastion="$(tf bastion_id)"; ip="$(tf vm_private_ip)"
session="$(oci bastion session list --bastion-id "$bastion" --session-lifecycle-state ACTIVE --all \
  --query "data[?\"target-resource-details\".\"target-resource-private-ip-address\"=='$ip'] | [0].id" --raw-output 2>/dev/null || true)"
if [ -z "$session" ] || [ "$session" = null ]; then
  session="$(oci bastion session create-port-forwarding --bastion-id "$bastion" --target-private-ip "$ip" --target-port 22 \
    --ssh-public-key-file "$key.pub" --session-ttl 10800 --display-name "ssh-$(date -u +%H%M)" \
    --wait-for-state SUCCEEDED --query 'data.resources[0].identifier' --raw-output)"
  sleep 10 # a new session takes a few seconds before it accepts keys
fi
host="host.bastion.$(grep '^region=' ~/.oci/config | cut -d= -f2).oci.oraclecloud.com"
# TUNNEL=<local port> forwards it to the n8n editor on the VM (127.0.0.1:5678) instead of opening a shell.
tunnel=(); [ -n "${TUNNEL:-}" ] && tunnel=(-N -L "$TUNNEL:127.0.0.1:5678")
exec ssh -i "$key" -o IdentitiesOnly=yes -o ServerAliveInterval=30 "${tunnel[@]}" \
  -o ProxyCommand="ssh -i $key -o IdentitiesOnly=yes -W %h:%p -p 22 $session@$host" "$user@$ip" "$@"
