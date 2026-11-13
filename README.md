# cd-kit

Reusable, auto-installing continuous-deployment recipe extracted from [finduck](https://github.com/hashorva/finduck).

It packages versioned GitHub Actions reusable workflows and an installer for Zamir's other projects (Astro+EmDash, Vite, Tailwind, React, shadcn; Cloudflare Workers; GitHub; Mac mini runners for private repos, GitHub-hosted for public). Callers pin a release tag.

This repository is public. Public consumers stay on GitHub-hosted runners. Private consumers may pass self-hosted Mini runners through a `runs-on` input.

See [hashorva/finduck#237](https://github.com/hashorva/finduck/issues/237).

## Install

From the root of the consuming repository:

```sh
curl -fsSL https://raw.githubusercontent.com/hashorva/cd-kit/v0/install.sh | bash -s -- --ref v0
```

This writes `.github/workflows/cd.yml`, which runs CI on every pull request and push, and deploys to Cloudflare Workers on pushes to `main`. Then add the `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` secrets (repository-level, or on the `production` environment).

| Option | Default | |
| --- | --- | --- |
| `--ref <tag>` | required | cd-kit tag to pin: `v0` follows the latest v0 release, `v0.1.0` is fixed |
| `--runner github\|mini` | `github` | `mini` uses `["self-hosted","macOS","mini"]` |
| `--runs-on <json>` | | explicit runner labels, overrides `--runner` |
| `--visibility public\|private` | detected with `gh` | self-hosted runners are refused for public repos |
| `--branch <name>` | `main` | branch that deploys to production |
| `--working-directory <dir>` | `.` | directory holding `package.json` |
| `--force` | | overwrite an existing `cd.yml` (use to upgrade) |
| `--dry-run` | | print instead of writing |

Private repo on the Mac mini:

```sh
curl -fsSL https://raw.githubusercontent.com/hashorva/cd-kit/v0/install.sh | bash -s -- --ref v0 --runner mini
```

## Reusable workflows

### `ci.yml`

Detects the package manager from the lockfile (npm, pnpm, yarn, bun), installs with a frozen lockfile, then runs `lint`, `typecheck`, `test` and `build`. Each phase runs the package.json script of that name when it exists and is skipped otherwise.

| Input | Default | |
| --- | --- | --- |
| `runs-on` | `'"ubuntu-latest"'` | JSON label or array |
| `working-directory` | `.` | |
| `node-version` / `node-version-file` | `22` / | the file wins when set |
| `lint-command`, `typecheck-command`, `test-command`, `build-command` | | override a phase; `-` skips it |
| `build-artifact-path` | | upload this path as the `build` artifact |

### `deploy-cloudflare.yml`

Installs, builds (or downloads the `build` artifact from `ci.yml`) and runs wrangler. One deploy per GitHub environment at a time.

| Input | Default | |
| --- | --- | --- |
| `runs-on`, `working-directory`, `node-version`, `node-version-file` | as above | |
| `environment` | `production` | GitHub environment |
| `wrangler-environment` | | wrangler `--env` |
| `wrangler-command` | `deploy` | e.g. `versions upload` for a preview |
| `wrangler-version` | | defaults to the project's wrangler |
| `build-command` | | as in `ci.yml` |
| `build-artifact-path` | | reuse the CI build instead of rebuilding |

Secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`. Output: `deployment-url`.

## Releasing

Either push a `vX.Y.Z` tag, or run the `release` workflow from `main` (Actions → release → Run workflow) with the version; the latter tags the current `main` commit. The workflow publishes a GitHub release and moves the `vX` tag to it, so callers on `@vX` pick it up.

## Development

```sh
shellcheck install.sh tests/*.sh
actionlint
bash tests/install.sh
```

The `self-test` workflow runs the same checks, then installs into a scratch repo and lints the generated workflow.
