#!/usr/bin/env bash
# Refuses any text that credits an AI tool as an author: Co-authored-by trailers for Claude or Anthropic, and
# "Generated with Claude Code" lines. GitHub turns co-author trailers into contributor credits; this repository
# lists its owner only. Used as a commit-msg hook (file argument) and in CI (text on stdin).
set -euo pipefail
pattern='co-authored-by:.*(claude|anthropic)|generated with \[?claude|noreply@anthropic\.com'
if grep -Eiq "$pattern" "${1:--}"; then
  echo "refused: AI attribution found (remove Co-Authored-By or 'Generated with' lines)" >&2
  grep -Ein "$pattern" "${1:--}" >&2 || true
  exit 1
fi
