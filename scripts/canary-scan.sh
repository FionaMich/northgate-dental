#!/usr/bin/env bash
# Fails if any canary value appears in the given files (or stdin). Prints only the file names that matched.
# Later sections point this at logs, traces, queue messages and n8n executions.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
values="$root/services/synthdata/src/synthdata/canary.txt"

if [ "$#" -eq 0 ]; then set -- -; fi
if hits="$(grep -F -l -f "$values" -- "$@" 2>/dev/null)"; then
  echo "canary found in:"
  echo "$hits"
  exit 1
fi
echo "canary scan clean"
