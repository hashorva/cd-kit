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
SELF_HOSTED_RUNS_ON='["self-hosted"]'
GITHUB_RUNS_ON='"ubuntu-latest"'
# --runner auto: one line per registered runner, "<status><TAB><custom labels, sorted, comma-joined>".
RUNNERS_JQ='.runners[] | [.status, ([.labels[] | select(.type == "custom") | .name] | sort | join(","))] | @tsv'
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
catch_up=0

usage() {
  cat <<EOF
Usage: install.sh --ref <tag> [options]

Writes .github/workflows/cd.yml into the target repository. The workflow
calls cd-kit's reusable workflows pinned to <tag>. Its gate job is the one
required-check name for branch rulesets.

Options:
  --ref <tag>              cd-kit release tag to pin (required), e.g. v0 or v0.1.0
  --target <dir>           Repository to install into (default: .)
  --runner github|self-hosted|auto
                           GitHub-hosted (default); any self-hosted runner
                           (runs-on ["self-hosted"]); or auto: detect the
                           repository's registered self-hosted runners with gh
                           and use their labels, else GitHub-hosted
  --runs-on <json>         Explicit runs-on JSON, overrides --runner
                           e.g. '"ubuntu-24.04"' or '["self-hosted","linux"]'
  --visibility public|private
                           Repository visibility. Detected with gh when omitted.
                           Self-hosted runners are refused for public repos.
  --branch <name>          Branch that deploys to production (default: main)
  --working-directory <d>  Directory holding package.json (default: .)
  --catch-up               Also write cd-catch-up.yml, an hourly job that starts cd
                           for a branch tip no run picked up (e.g. a merge made
                           with GITHUB_TOKEN). Off by default.
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
    --catch-up) catch_up=1; shift ;;
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
    self-hosted) runs_on="$SELF_HOSTED_RUNS_ON" ;;
    auto) ;; # resolved below, once the visibility is known
    *) die "--runner must be github, self-hosted or auto (got $runner)" ;;
  esac
fi

validate_runs_on() {
  case "$runs_on" in
    *"'"*) die "--runs-on must not contain single quotes" ;;
    \"*\"|\[*\]) ;;
    *) die "--runs-on must be JSON: a quoted label or an array, e.g. '\"ubuntu-latest\"'" ;;
  esac
}
[ -z "$runs_on" ] || validate_runs_on

[ -d "$target" ] || die "target directory not found: $target"
[ -f "$target/$working_directory/package.json" ] \
  || info "warning: no package.json in $target/$working_directory"

if [ -z "$visibility" ] && command -v gh >/dev/null 2>&1; then
  visibility=$( (cd "$target" && gh repo view --json visibility -q .visibility 2>/dev/null) \
    | tr '[:upper:]' '[:lower:]' || true)
fi
case "$visibility" in
  public|private|internal|"") ;;
  *) die "--visibility must be public or private (got $visibility)" ;;
esac

# --runner auto: use the labels of the repository's registered self-hosted
# runners. Public repositories always get GitHub-hosted runners.
detect_runs_on() {
  local repo rows groups count labels total online json label list
  case "$visibility" in
    public)
      info "--runner auto: public repository, using GitHub-hosted runners"
      echo "$GITHUB_RUNS_ON"; return ;;
    private|internal) ;;
    *) die "--runner auto needs the repository visibility; pass --visibility private, or install gh" ;;
  esac
  command -v gh >/dev/null 2>&1 \
    || die "--runner auto needs gh logged in with admin access to the repository"
  repo=$( (cd "$target" && gh repo view --json nameWithOwner -q .nameWithOwner) 2>/dev/null || true)
  [ -n "$repo" ] || die "--runner auto: cannot identify the GitHub repository in $target"
  rows=$(gh api "repos/$repo/actions/runners" --paginate --jq "$RUNNERS_JQ" 2>/dev/null) \
    || die "--runner auto: cannot list the self-hosted runners of $repo (needs admin access); pass --runs-on instead"
  if [ -z "$rows" ]; then
    info "--runner auto: no self-hosted runners registered for $repo, using GitHub-hosted runners"
    info "  runners that register only when a job starts (ephemeral pools) are not detected; pass --runs-on for those"
    echo "$GITHUB_RUNS_ON"; return
  fi
  groups=$(printf '%s\n' "$rows" | awk -F '\t' '
    { n[$2]++; if ($1 == "online") o[$2]++ }
    END { for (k in n) printf "%d\t%d\t%s\n", n[k], o[k] + 0, k }')
  count=$(printf '%s\n' "$groups" | wc -l | tr -d ' ')
  if [ "$count" -gt 1 ]; then
    info "--runner auto: the self-hosted runners of $repo carry different labels:"
    printf '%s\n' "$groups" | sort -t "$(printf '\t')" -k 3 | while IFS=$'\t' read -r total online labels; do
      info "  [${labels:-no custom labels}] $total runner(s), $online online"
    done
    die "choose one set with --runs-on, e.g. --runs-on '[\"self-hosted\",\"<label>\"]'"
  fi
  IFS=$'\t' read -r total online labels <<<"$groups"
  json='["self-hosted"'
  if [ -n "$labels" ]; then
    IFS=',' read -r -a list <<<"$labels"
    for label in "${list[@]}"; do
      case "$label" in
        *[!A-Za-z0-9._-]*) die "--runner auto: unsupported runner label: $label; pass --runs-on instead" ;;
      esac
      json="$json,\"$label\""
    done
  fi
  json="$json]"
  info "--runner auto: $total self-hosted runner(s) for $repo, $online online: runs-on $json"
  [ "$online" -gt 0 ] || info "  warning: none is online now; jobs will wait until one is"
  echo "$json"
}

if [ -z "$runs_on" ]; then
  runs_on=$(detect_runs_on)
  validate_runs_on
fi

# Self-hosted runners execute untrusted pull-request code on a public repo.
self_hosted=0
case "$runs_on" in *self-hosted*) self_hosted=1 ;; esac
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

templates="$TEMPLATES"
[ "$catch_up" -eq 1 ] && templates="$templates cd-catch-up.yml"

dest_dir="$target/.github/workflows"
for name in $templates; do
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
  1. Add CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID as secrets on the
     "production" environment only, so pull-request jobs never see them. On a
     public repo, limit that environment to the $branch branch and v* tags.
  2. In the branch ruleset, require the status check "gate", and do not set
     "Require deployments to succeed".
  3. Commit .github/workflows/ and open a pull request.
EOF
fi
