#!/usr/bin/env bash
# cd-kit installer: writes caller workflows into a repository, pinned to a
# cd-kit release tag.
#
#   curl -fsSL https://raw.githubusercontent.com/hashorva/cd-kit/v0/install.sh \
#     | bash -s -- --ref v0
#
# Run with --help for options. Works on bash 3.2 (macOS) and later.
set -euo pipefail

CD_KIT_REPO="hashorva/cd-kit"
MINI_RUNS_ON='["self-hosted","macOS","mini"]'
GITHUB_RUNS_ON='"ubuntu-latest"'
TEMPLATES="cd.yml"

ref=""
target="."
runner="github"
runs_on=""
visibility=""
branch="main"
working_directory="."
force=0
dry_run=0

usage() {
  cat <<EOF
Usage: install.sh --ref <tag> [options]

Writes .github/workflows/cd.yml into the target repository. The workflow
calls cd-kit's reusable workflows pinned to <tag>.

Options:
  --ref <tag>              cd-kit release tag to pin (required), e.g. v0 or v0.1.0
  --target <dir>           Repository to install into (default: .)
  --runner github|mini     GitHub-hosted (default) or self-hosted Mac mini runners
  --runs-on <json>         Explicit runs-on JSON, overrides --runner
                           e.g. '"ubuntu-24.04"' or '["self-hosted","linux"]'
  --visibility public|private
                           Repository visibility. Detected with gh when omitted.
                           Self-hosted runners are refused for public repos.
  --branch <name>          Branch that deploys to production (default: main)
  --working-directory <d>  Directory holding package.json (default: .)
  --force                  Overwrite existing workflow files
  --dry-run                Print the files instead of writing them
  -h, --help               Show this help
EOF
}

die() { echo "cd-kit: $*" >&2; exit 1; }
info() { echo "cd-kit: $*" >&2; }

need_arg() { [ $# -ge 2 ] && [ -n "$2" ] || die "$1 needs a value"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) need_arg "$@"; ref="$2"; shift 2 ;;
    --target) need_arg "$@"; target="$2"; shift 2 ;;
    --runner) need_arg "$@"; runner="$2"; shift 2 ;;
    --runs-on) need_arg "$@"; runs_on="$2"; shift 2 ;;
    --visibility) need_arg "$@"; visibility="$2"; shift 2 ;;
    --branch) need_arg "$@"; branch="$2"; shift 2 ;;
    --working-directory) need_arg "$@"; working_directory="$2"; shift 2 ;;
    --force) force=1; shift ;;
    --dry-run) dry_run=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
done

# --- validate inputs -------------------------------------------------------

[ -n "$ref" ] || { usage >&2; die "--ref is required (pin a release tag, e.g. v0)"; }
case "$ref" in
  main|master|HEAD) die "--ref must be a release tag, not a branch ($ref)" ;;
esac
case "$ref" in
  *[!A-Za-z0-9._-]*) die "invalid --ref: $ref" ;;
esac
case "$branch" in
  *[!A-Za-z0-9._/-]*) die "invalid --branch: $branch" ;;
esac
case "$working_directory" in
  *[!A-Za-z0-9._/-]*) die "invalid --working-directory: $working_directory" ;;
esac

if [ -z "$runs_on" ]; then
  case "$runner" in
    github) runs_on="$GITHUB_RUNS_ON" ;;
    mini) runs_on="$MINI_RUNS_ON" ;;
    *) die "--runner must be github or mini (got $runner)" ;;
  esac
fi
case "$runs_on" in
  *"'"*) die "--runs-on must not contain single quotes" ;;
  \"*\"|\[*\]) ;;
  *) die "--runs-on must be JSON: a quoted label or an array, e.g. '\"ubuntu-latest\"'" ;;
esac

[ -d "$target" ] || die "target directory not found: $target"
[ -f "$target/$working_directory/package.json" ] \
  || info "warning: no package.json in $target/$working_directory"

# Self-hosted runners execute untrusted pull-request code on a public repo.
self_hosted=0
case "$runs_on" in *self-hosted*) self_hosted=1 ;; esac

if [ -z "$visibility" ] && command -v gh >/dev/null 2>&1; then
  visibility=$( (cd "$target" && gh repo view --json visibility -q .visibility 2>/dev/null) \
    | tr '[:upper:]' '[:lower:]' || true)
fi
case "$visibility" in
  public|private|internal|"") ;;
  *) die "--visibility must be public or private (got $visibility)" ;;
esac
if [ "$self_hosted" -eq 1 ]; then
  case "$visibility" in
    public) die "self-hosted runners are not allowed for public repositories; use --runner github" ;;
    "") die "cannot detect repository visibility; pass --visibility private to use self-hosted runners" ;;
  esac
fi

# --- render ----------------------------------------------------------------

script_dir=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

load_template() {
  if [ -n "$script_dir" ] && [ -f "$script_dir/templates/$1" ]; then
    cat "$script_dir/templates/$1"
  else
    command -v curl >/dev/null 2>&1 || die "curl is required to fetch templates"
    curl -fsSL "https://raw.githubusercontent.com/$CD_KIT_REPO/$ref/templates/$1" \
      || die "could not fetch templates/$1 at $ref (does the tag exist?)"
  fi
}

# Bash 5.2 treats & in a ${var//pat/rep} replacement as the match; turn it off.
shopt -u patsub_replacement 2>/dev/null || true

render() {
  local out
  out=$(load_template "$1")
  out=${out//__CD_KIT_REF__/$ref}
  out=${out//__RUNS_ON__/$runs_on}
  out=${out//__BRANCH__/$branch}
  out=${out//__WORKING_DIRECTORY__/$working_directory}
  printf '%s\n' "$out"
}

dest_dir="$target/.github/workflows"
for name in $TEMPLATES; do
  dest="$dest_dir/$name"
  content=$(render "$name")
  if [ "$dry_run" -eq 1 ]; then
    printf '# --- %s ---\n%s\n' "$dest" "$content"
    continue
  fi
  if [ -e "$dest" ] && [ "$force" -ne 1 ]; then
    die "$dest exists; re-run with --force to overwrite"
  fi
  mkdir -p "$dest_dir"
  printf '%s\n' "$content" > "$dest"
  info "wrote $dest (cd-kit@$ref, runs-on $runs_on)"
done

if [ "$dry_run" -ne 1 ]; then
  cat >&2 <<EOF
cd-kit: next steps
  1. Add repository secrets CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID
     (or scope them to the "production" environment).
  2. Commit .github/workflows/ and open a pull request.
EOF
fi
