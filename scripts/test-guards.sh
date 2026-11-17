#!/usr/bin/env bash
# Tests for .gitignore and the guard scripts. Each case builds a throwaway git repo,
# plants a file, and checks the guard passes or refuses. Runs locally and in CI.
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
failures=0

new_repo() {
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  cp "$root/.gitignore" "$dir/"
  mkdir -p "$dir/scripts" "$dir/docs"
  cp "$root/scripts/check-forbidden-files.sh" "$root/scripts/check-no-em-dash.sh" "$dir/scripts/"
  echo "$dir"
}

expect() { # expect pass|fail "description" command...
  local want="$1" name="$2"; shift 2
  if "$@" >/dev/null 2>&1; then got=pass; else got=fail; fi
  if [ "$got" = "$want" ]; then echo "ok    $name"; else echo "FAIL  $name (wanted $want, got $got)"; failures=$((failures + 1)); fi
}

# .gitignore keeps the private files out
d="$(new_repo)"; mkdir -p "$d/docs/sections"; touch "$d/unsplash.env" "$d/.env" "$d/docs/blueprint.pdf" "$d/docs/sections/01.md"
expect pass "gitignore ignores unsplash.env"      git -C "$d" check-ignore -q unsplash.env
expect pass "gitignore ignores .env"              git -C "$d" check-ignore -q .env
expect pass "gitignore ignores docs/blueprint.pdf" git -C "$d" check-ignore -q docs/blueprint.pdf
expect pass "gitignore ignores everything in docs/" git -C "$d" check-ignore -q docs/sections/01.md

# forbidden files guard: clean repo passes
d="$(new_repo)"; echo "# ok" > "$d/README.md"; git -C "$d" add -A
expect pass "guard passes on a clean repo"        bash -c "cd '$d' && scripts/check-forbidden-files.sh"

# forbidden files guard: force-added private files are refused
for f in docs/blueprint.pdf docs/sections/01-repo-and-ci.md docs/learning-log.md unsplash.env .env .env.local services/x/.env; do
  d="$(new_repo)"; mkdir -p "$d/$(dirname "$f")"; echo x > "$d/$f"; git -C "$d" add -f "$f"
  expect fail "guard refuses tracked $f"          bash -c "cd '$d' && scripts/check-forbidden-files.sh"
done

# forbidden files guard: a file ignored by a local-only rule (like the global gitignore) is refused when force-added
d="$(new_repo)"; echo "private-notes.md" >> "$d/.git/info/exclude"; echo x > "$d/private-notes.md"; git -C "$d" add -f private-notes.md
expect fail "guard refuses a tracked file that a local ignore rule covers" bash -c "cd '$d' && scripts/check-forbidden-files.sh"

# an example env file with no values is allowed
d="$(new_repo)"; echo "KEY=" > "$d/.env.example"; git -C "$d" add -f .env.example
expect pass "guard allows .env.example"           bash -c "cd '$d' && scripts/check-forbidden-files.sh"

# em dash check
d="$(new_repo)"; echo "plain text, with a comma" > "$d/notes.md"; git -C "$d" add -A
expect pass "docs check passes without em dashes" bash -c "cd '$d' && scripts/check-no-em-dash.sh"
d="$(new_repo)"; printf 'bad \xe2\x80\x94 dash\n' > "$d/notes.md"; git -C "$d" add -A
expect fail "docs check refuses an em dash"       bash -c "cd '$d' && scripts/check-no-em-dash.sh"

[ "$failures" -eq 0 ] && echo "all guard tests passed" || { echo "$failures guard test(s) failed"; exit 1; }
