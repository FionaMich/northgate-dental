#!/usr/bin/env bash
# Moves the VM to the Always Free Ampere A1 shape as soon as Oracle has capacity (ADR 0009).
#   infra/terraform/oci/retry-a1.sh [seconds between checks, default 900]
# Each round asks Oracle's capacity report first and runs Terraform only when A1 can be placed. The new VM is
# built before the old one is removed (create_before_destroy), so a failed attempt leaves the running VM alone.
set -euo pipefail
cd "$(dirname "$0")"
interval="${1:-900}"
ocpus=2 memory=12
tenancy="$(grep '^tenancy=' ~/.oci/config | cut -d= -f2)"
ad="$(oci iam availability-domain list --compartment-id "$tenancy" --query 'data[0].name' --raw-output)"

while true; do
  status="$(oci compute compute-capacity-report create --compartment-id "$tenancy" --availability-domain "$ad" \
    --shape-availabilities "[{\"instanceShape\":\"VM.Standard.A1.Flex\",\"instanceShapeConfig\":{\"ocpus\":$ocpus,\"memoryInGBs\":$memory}}]" \
    --query 'data."shape-availabilities"[0]."availability-status"' --raw-output)"
  echo "$(date -u +%FT%TZ) A1 $ocpus cores, $memory GB: $status"
  if [ "$status" = AVAILABLE ] &&
    terraform apply -input=false -auto-approve -var shape=VM.Standard.A1.Flex -var ocpus=$ocpus -var memory_gbs=$memory; then
    echo "moved to A1. Next: set the shape default in variables.tf to VM.Standard.A1.Flex ($ocpus cores, $memory GB) and open a pull request."
    exit 0
  fi
  sleep "$interval"
done
