#!/usr/bin/env bash
# Fails if a private or secret file is tracked by git, even one force-added past .gitignore.
# Runs in pre-commit (git ls-files includes staged files) and in CI.
set -euo pipefail

# 1. any tracked file that an ignore rule covers (.gitignore, .git/info/exclude, the global gitignore)
# 2. docs/ and env files by name, in case .gitignore itself is edited
bad="$( { git ls-files --cached --ignored --exclude-standard; git ls-files | grep -E '^docs/|\.env$|(^|/)\.env\.[^/]*$'; } | grep -vE '(^|/)\.env\.example$' | sort -u || true)"

if [ -n "$bad" ]; then
  echo "These files must never be committed (private or secret):"
  echo "$bad"
  echo "Remove them with: git rm --cached <file>"
  exit 1
fi
