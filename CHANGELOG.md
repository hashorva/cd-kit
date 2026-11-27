# Changelog

## Unreleased

- Changed: `install.sh --runner` takes `github` (default) or `self-hosted`, which installs `runs-on: ["self-hosted"]`. The `mini` preset is removed; pass specific labels with `--runs-on '<json>'`. Workflows already installed are not affected.
- Changed: `pick-runner.yml` input `self-hosted-labels` defaults to `'["self-hosted"]'` (was a machine-specific label set). Callers that relied on the old default should pass their labels.
- Docs: README and input descriptions no longer reference a specific project or machine.
- Added: `gate` job in the caller template. It always runs and fails unless CI succeeded; require it in rulesets instead of `ci`.
- Added: deploys also run on `vX.Y.Z` tags (an older tag is a rollback); the new `release` job in the template uses `deploy-cloudflare.yml` with no stand-aside.
- Added: hold deploys with the repository variable `CD_DEPLOY_ENABLED=false`; unset still deploys.
- Added: `deploy-cloudflare.yml` input `production-branch` and output `deployed`. A run that is no longer the tip of the branch stands aside before installing.
- Added: `post-deploy.yml`, an optional command run after a successful deploy, in the same environment and its own queue; the template passes `vars.CD_MIGRATE_COMMAND`.
- Added: `catch-up.yml` and `install.sh --catch-up` (writes `cd-catch-up.yml`): dispatches `cd` when the branch tip has no run, for merges made with `GITHUB_TOKEN`.
- Added: `pick-runner.yml`, an opt-in picker that uses included hosted minutes first and falls back to self-hosted. Not used by the template or cd-kit's own CI. Uses `actions/github-script` v9.0.0.
- Changed: `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are optional workflow secrets and are read from the job's environment; the template no longer passes them. Callers that pass repository secrets keep working.
- Changed: every template job, including `gate`, takes the installed `runs-on`.
- Changed: `self-test.yml` uses actionlint 1.7.12 (was 1.7.7).
- Docs: README flowcharts updated; `AGENTS.md` and the `flowchart-check` workflow require README changes with workflow changes.

## v0.1.1

- Changed: the default `node-version` input of `ci.yml` and `deploy-cloudflare.yml` is now `24` (was `22`). Callers can keep Node 22 by passing `node-version: "22"`. `node-version-file` still takes precedence when set.
- Changed: `actions/setup-node` v4 to v7, which runs on the Node 24 action runtime (#4).
- Changed: actions moved off the Node 20 runtime to Node 24 versions: `actions/checkout` v4 to v7.0.1, `actions/upload-artifact` v4 to v7.0.2, `actions/download-artifact` v4 to v8.0.2, `cloudflare/wrangler-action` v3 to v4.1.3 (`actions/setup-node` was already v7).
- Changed: `wrangler-action` v4 installs Wrangler v4 when `wrangler-version` is empty and the project has no Wrangler installed of its own. Projects that depend on `wrangler` are unaffected; set `wrangler-version` to pin another version.
- Changed: every `uses:` in all four workflows is pinned to a full commit SHA with a version comment (`oven-sh/setup-bun` v2.2.0 too). `self-test.yml` and `release.yml` stay on `ubuntu-latest`.
- Docs: README flowchart (mermaid) (#3); inputs table shows the new Node default.

## v0.1.0

- Initial release (#2).
