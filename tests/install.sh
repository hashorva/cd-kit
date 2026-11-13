#!/usr/bin/env bash
# Tests for install.sh. Runs offline against the local templates/.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installer="$root/install.sh"
fails=0

new_repo() {
  local d
  d=$(mktemp -d)
  echo '{"name":"t"}' > "$d/package.json"
  echo "$d"
}

pass() { echo "ok   - $1"; }
fail() { echo "FAIL - $1"; fails=$((fails + 1)); }

# check <name> <command...>: pass when the command succeeds.
check() {
  local name=$1; shift
  if "$@"; then pass "$name"; else fail "$name"; fi
}

expect_ok() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

expect_err() {
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then fail "$name"; else pass "$name"; fi
}

# Scratch dirs are not git repos, so gh cannot detect visibility there.
repo=$(new_repo)
expect_ok "installs with defaults" bash "$installer" --ref v0 --target "$repo"
wf="$repo/.github/workflows/cd.yml"
if grep -q 'hashorva/cd-kit/.github/workflows/ci.yml@v0' "$wf" \
  && grep -q "runs-on: '\"ubuntu-latest\"'" "$wf" \
  && ! grep -q '__[A-Z_]*__' "$wf"; then
  pass "renders ref and runs-on, no placeholders left"
else
  fail "renders ref and runs-on, no placeholders left"
fi

expect_err "refuses to overwrite without --force" bash "$installer" --ref v0 --target "$repo"
expect_ok "overwrites with --force" bash "$installer" --ref v0.1.0 --target "$repo" --force
check "--force writes new ref" grep -q '@v0.1.0' "$wf"

expect_err "requires --ref" bash "$installer" --target "$(new_repo)"
expect_err "rejects branch as ref" bash "$installer" --ref main --target "$(new_repo)"
expect_err "rejects unknown option" bash "$installer" --ref v0 --bogus
expect_err "rejects non-JSON runs-on" bash "$installer" --ref v0 --runs-on ubuntu-latest --target "$(new_repo)"

expect_err "refuses mini on public repo" \
  bash "$installer" --ref v0 --runner mini --visibility public --target "$(new_repo)"
expect_err "refuses mini when visibility unknown" \
  bash "$installer" --ref v0 --runner mini --target "$(new_repo)"

repo=$(new_repo)
expect_ok "allows mini on private repo" \
  bash "$installer" --ref v0 --runner mini --visibility private --target "$repo"
check "renders mini runs-on" \
  grep -qF "runs-on: '[\"self-hosted\",\"macOS\",\"mini\"]'" "$repo/.github/workflows/cd.yml"

repo=$(new_repo)
out=$(bash "$installer" --ref v0 --target "$repo" --dry-run --branch release --working-directory app)
if [ ! -e "$repo/.github/workflows/cd.yml" ] \
  && grep -q "branches: \[release\]" <<<"$out" \
  && grep -q "working-directory: app" <<<"$out"; then
  pass "--dry-run prints and writes nothing"
else
  fail "--dry-run prints and writes nothing"
fi

repo=$(new_repo)
expect_ok "runs-on with & is not mangled" bash "$installer" --ref v0 --target "$repo" --runs-on '["a&b"]' --visibility private
check "& survives substitution" grep -qF '["a&b"]' "$repo/.github/workflows/cd.yml"

[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all tests passed"
