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

# not <command...>: pass when the command fails.
not() { ! "$@"; }

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

check "renders a gate job on the same runs-on" \
  grep -qE '^  gate:$' "$wf"
check "gate runs on the installed runs-on" grep -qF 'runs-on: "ubuntu-latest"' "$wf"
check "deploys on vX.Y.Z tags too" grep -qF 'tags: ["v[0-9]+.[0-9]+.[0-9]+"]' "$wf"
check "deploy can be held with CD_DEPLOY_ENABLED" grep -qF "vars.CD_DEPLOY_ENABLED != 'false'" "$wf"
check "no repo-level secrets passed (environment-only)" not grep -q '^ *secrets:' "$wf"
check "default template does not call pick-runner" not grep -q pick-runner "$wf"
check "no catch-up file by default" test ! -e "$repo/.github/workflows/cd-catch-up.yml"

expect_err "refuses to overwrite without --force" bash "$installer" --ref v0 --target "$repo"
expect_ok "overwrites with --force" bash "$installer" --ref v0.1.0 --target "$repo" --force
check "--force writes new ref" grep -q '@v0.1.0' "$wf"

expect_err "requires --ref" bash "$installer" --target "$(new_repo)"
expect_err "rejects branch as ref" bash "$installer" --ref main --target "$(new_repo)"
expect_err "rejects unknown option" bash "$installer" --ref v0 --bogus
expect_err "rejects non-JSON runs-on" bash "$installer" --ref v0 --runs-on ubuntu-latest --target "$(new_repo)"

expect_err "rejects unknown --runner" bash "$installer" --ref v0 --runner bogus --target "$(new_repo)"
expect_err "refuses self-hosted on public repo" \
  bash "$installer" --ref v0 --runner self-hosted --visibility public --target "$(new_repo)"
expect_err "refuses self-hosted when visibility unknown" \
  bash "$installer" --ref v0 --runner self-hosted --target "$(new_repo)"
expect_err "refuses self-hosted --runs-on labels on public repo" \
  bash "$installer" --ref v0 --runs-on '["self-hosted","linux"]' --visibility public --target "$(new_repo)"

repo=$(new_repo)
expect_ok "allows self-hosted on private repo" \
  bash "$installer" --ref v0 --runner self-hosted --visibility private --target "$repo"
check "renders self-hosted runs-on" \
  grep -qF "runs-on: '[\"self-hosted\"]'" "$repo/.github/workflows/cd.yml"

repo=$(new_repo)
expect_ok "allows custom self-hosted labels on private repo" \
  bash "$installer" --ref v0 --runs-on '["self-hosted","linux"]' --visibility private --target "$repo"
check "renders custom labels" \
  grep -qF "runs-on: '[\"self-hosted\",\"linux\"]'" "$repo/.github/workflows/cd.yml"

repo=$(new_repo)
expect_ok "--catch-up writes cd-catch-up.yml" bash "$installer" --ref v0 --target "$repo" --catch-up
cu="$repo/.github/workflows/cd-catch-up.yml"
check "catch-up renders branch and runs-on" grep -q 'branch: main' "$cu"
check "catch-up runs-on is quoted JSON" grep -qF "runs-on: '\"ubuntu-latest\"'" "$cu"
check "catch-up has no placeholders left" not grep -q '__[A-Z_]*__' "$cu"
expect_err "refuses self-hosted catch-up on public repo" \
  bash "$installer" --ref v0 --runner self-hosted --visibility public --catch-up --target "$(new_repo)"

repo=$(new_repo)
expect_ok "self-hosted gate renders a YAML array" \
  bash "$installer" --ref v0 --runner self-hosted --visibility private --target "$repo"
check "gate runs-on is the self-hosted array" \
  grep -qF 'runs-on: ["self-hosted"]' "$repo/.github/workflows/cd.yml"

# cd-kit's own CI stays on GitHub-hosted runners.
check "own CI has no self-hosted labels" not grep -l self-hosted \
  "$root/.github/workflows/self-test.yml" "$root/.github/workflows/release.yml" \
  "$root/.github/workflows/flowchart-check.yml"

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

# --runner auto, against a stand-in gh. The stand-in applies the installer's
# real --jq filter to a fixture with jq, so the filter itself is tested too.
if command -v jq >/dev/null 2>&1; then
  fakebin=$(mktemp -d)
  cat > "$fakebin/gh" <<'GH'
#!/usr/bin/env bash
case "$1" in
  repo)
    case "$*" in
      *nameWithOwner*) [ -n "${FAKE_GH_REPO:-}" ] || exit 1; echo "$FAKE_GH_REPO" ;;
      *visibility*) [ -n "${FAKE_GH_VISIBILITY:-}" ] || exit 1; echo "$FAKE_GH_VISIBILITY" ;;
      *) exit 1 ;;
    esac ;;
  api)
    [ "${FAKE_GH_API_FAIL:-0}" != 1 ] || exit 1
    [ "$2" = "repos/$FAKE_GH_REPO/actions/runners" ] || exit 1
    filter=""
    while [ $# -gt 0 ]; do
      if [ "$1" = --jq ]; then filter=$2; fi
      shift
    done
    jq -r "$filter" "$FAKE_GH_RUNNERS" ;;
  *) exit 1 ;;
esac
GH
  chmod +x "$fakebin/gh"

  # fixture <file> <status:label,label>...: a runners API response.
  fixture() {
    local f=$1 spec st lbls sep="" i=0 l
    local -a arr
    shift
    {
      printf '{"total_count":%d,"runners":[' $#
      for spec in "$@"; do
        st=${spec%%:*}; lbls=${spec#*:}
        printf '%s{"id":%d,"name":"r%d","status":"%s","labels":[{"name":"self-hosted","type":"read-only"},{"name":"Linux","type":"read-only"}' \
          "$sep" "$i" "$i" "$st"
        if [ -n "$lbls" ]; then
          IFS=',' read -r -a arr <<<"$lbls"
          for l in "${arr[@]}"; do printf ',{"name":"%s","type":"custom"}' "$l"; done
        fi
        printf ']}'
        sep=","; i=$((i + 1))
      done
      printf ']}'
    } > "$f"
  }

  # auto <visibility> <fixture-file> <installer args...>
  auto() {
    local vis=$1 fx=$2
    shift 2
    PATH="$fakebin:$PATH" FAKE_GH_REPO=acme/app FAKE_GH_VISIBILITY="$vis" FAKE_GH_RUNNERS="$fx" \
      bash "$installer" --ref v0 --runner auto "$@"
  }

  fx=$(mktemp)
  fixture "$fx" "online:foo-ci" "offline:foo-ci"
  repo=$(new_repo)
  expect_ok "auto installs on one label set" auto PRIVATE "$fx" --target "$repo"
  check "auto renders the detected labels" \
    grep -qF "runs-on: '[\"self-hosted\",\"foo-ci\"]'" "$repo/.github/workflows/cd.yml"
  check "auto gate gets the same labels" \
    grep -qF 'runs-on: ["self-hosted","foo-ci"]' "$repo/.github/workflows/cd.yml"

  fixture "$fx" "online:gpu,foo-ci" "online:foo-ci,gpu"
  repo=$(new_repo)
  expect_ok "auto installs several shared labels" auto PRIVATE "$fx" --target "$repo"
  check "auto renders shared labels sorted" \
    grep -qF "runs-on: '[\"self-hosted\",\"foo-ci\",\"gpu\"]'" "$repo/.github/workflows/cd.yml"

  fixture "$fx" "online:" "online:"
  repo=$(new_repo)
  expect_ok "auto installs runners with no custom labels" auto PRIVATE "$fx" --target "$repo"
  check "auto renders plain self-hosted" \
    grep -qF "runs-on: '[\"self-hosted\"]'" "$repo/.github/workflows/cd.yml"

  fixture "$fx" "offline:foo-ci"
  repo=$(new_repo)
  out=$(auto PRIVATE "$fx" --target "$repo" 2>&1) || true
  if grep -qF "runs-on: '[\"self-hosted\",\"foo-ci\"]'" "$repo/.github/workflows/cd.yml" \
    && grep -q "none is online" <<<"$out"; then
    pass "auto warns when no runner is online"
  else
    fail "auto warns when no runner is online"
  fi

  fixture "$fx" "online:foo-ci" "online:mini-vm"
  expect_err "auto refuses several label sets" auto PRIVATE "$fx" --target "$(new_repo)"

  fixture "$fx" "online:a*b"
  expect_err "auto refuses an unsupported label" auto PRIVATE "$fx" --target "$(new_repo)"

  fixture "$fx"
  repo=$(new_repo)
  expect_ok "auto falls back with no runners" auto PRIVATE "$fx" --target "$repo"
  check "auto with no runners renders GitHub-hosted" \
    grep -qF "runs-on: '\"ubuntu-latest\"'" "$repo/.github/workflows/cd.yml"

  fixture "$fx" "online:foo-ci"
  repo=$(new_repo)
  expect_ok "auto on a public repo installs" \
    env FAKE_GH_API_FAIL=1 PATH="$fakebin:$PATH" FAKE_GH_REPO=acme/app FAKE_GH_VISIBILITY=PUBLIC \
    bash "$installer" --ref v0 --runner auto --target "$repo"
  check "auto on a public repo renders GitHub-hosted, without listing runners" \
    grep -qF "runs-on: '\"ubuntu-latest\"'" "$repo/.github/workflows/cd.yml"

  expect_err "auto refuses when the runner list fails" \
    env FAKE_GH_API_FAIL=1 PATH="$fakebin:$PATH" FAKE_GH_REPO=acme/app FAKE_GH_VISIBILITY=PRIVATE \
    FAKE_GH_RUNNERS="$fx" bash "$installer" --ref v0 --runner auto --target "$(new_repo)"
  expect_err "auto refuses when visibility is unknown" auto "" "$fx" --target "$(new_repo)"
else
  echo "skip - --runner auto tests (jq not installed)"
fi

repo=$(new_repo)
expect_ok "--runs-on overrides --runner auto" \
  bash "$installer" --ref v0 --runner auto --runs-on '"ubuntu-24.04"' --target "$repo"
check "--runs-on wins over auto" grep -qF "runs-on: '\"ubuntu-24.04\"'" "$repo/.github/workflows/cd.yml"

[ "$fails" -eq 0 ] || { echo "$fails test(s) failed"; exit 1; }
echo "all tests passed"
