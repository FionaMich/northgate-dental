#!/usr/bin/env bash
# House style: no em dashes in documentation. Use commas or semicolons.
set -euo pipefail

hits="$(git ls-files -z '*.md' | xargs -0 -r grep -nF '—' -- || true)"

if [ -n "$hits" ]; then
  echo "Em dashes found; replace each with a comma or semicolon:"
  echo "$hits"
  exit 1
fi
