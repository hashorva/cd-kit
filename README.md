# cd-kit

Reusable, auto-installing continuous deployment for JavaScript and TypeScript projects that deploy to Cloudflare Workers.

It packages versioned GitHub Actions reusable workflows and an installer that adds them to any repository. CI detects npm, pnpm, Yarn or Bun and runs the project's own lint, typecheck, test and build scripts. Callers pin a release tag.

This repository is public. Public repositories stay on GitHub-hosted runners. Private repositories may pass their own self-hosted runner labels through a `runs-on` input.

## How it works

The installer writes one caller workflow, `cd.yml`, into the consuming repository. It calls cd-kit's reusable workflows at the pinned tag: `ci.yml` on every run, an always-running `gate` job that reports CI's result under one stable name, then `deploy-cloudflare.yml` for a push to the production branch or a `vX.Y.Z` tag. An older tag is a rollback. A deploy can be held with the repository variable `CD_DEPLOY_ENABLED=false` (unset deploys). After a successful deploy, `post-deploy.yml` runs the optional command in `CD_MIGRATE_COMMAND`.

```mermaid
%%{init: {"theme": "base", "themeVariables": {"fontFamily": "ui-sans-serif, system-ui, sans-serif", "lineColor": "#62748e", "primaryTextColor": "#0f172b", "edgeLabelBackground": "#f1f5f9", "clusterBkg": "#f8fafc", "clusterBorder": "#cad5e2", "titleColor": "#314158"}}}%%
flowchart TD
  trigger(["pull_request, push to main,<br/>push of a vX.Y.Z tag,<br/>or workflow_dispatch"]) --> detect

  subgraph ci ["ci.yml"]
    direction TB
    detect("Detect package manager from lockfile<br/>npm · pnpm · yarn · bun") --> install("Install with frozen lockfile")
    install --> phases("lint → typecheck → test → build<br/>each runs only if its script exists")
    phases -.-> artifact("build artifact<br/>(if build-artifact-path is set)")
  end

  phases --> gate{"gate (always runs):<br/>did CI succeed?"}
  gate -- no --> blocked(["gate fails:<br/>merge and deploy blocked"])
  gate -- yes --> which{"which event?"}
  which -- "pull request" --> done(["CI only"])
  which -- "push or manual run on main,<br/>or a vX.Y.Z tag" --> hold{"CD_DEPLOY_ENABLED<br/>== false?"}
  hold -- yes --> held(["deploy held"])
  hold -- "no (or unset)" --> dinstall

  subgraph deploy ["deploy-cloudflare.yml"]
    direction TB
    dinstall("environment: production, one deploy queue<br/>(secrets come from the environment)") --> tip{"run on main and<br/>no longer its tip?"}
    tip -- yes --> aside(["stands aside, deploys nothing"])
    tip -- "no (or a tag)" --> setup("Detect package manager and install")
    setup --> reuse{"build-artifact-path set?"}
    reuse -- yes --> download("Download build artifact")
    reuse -- no --> rebuild("Build")
    download --> wrangler("wrangler deploy")
    rebuild --> wrangler
  end

  artifact -.-> download
  wrangler --> workers("Cloudflare Workers")
  wrangler --> migrate{"CD_MIGRATE_COMMAND set?"}
  migrate -- yes --> post("post-deploy.yml: run the command<br/>same environment, its own queue")
  migrate -- no --> end_(["done"])

  classDef event fill:#f1f5f9,stroke:#62748e,color:#1d293d
  classDef ci fill:#dff2fe,stroke:#0084d1,color:#024a70
  classDef deploy fill:#d0fae5,stroke:#009966,color:#004f3b
  classDef decision fill:#fef3c6,stroke:#e17100,color:#7b3306
  classDef target fill:#ffedd4,stroke:#f54900,color:#7e2a0c
  classDef refused fill:#ffe4e6,stroke:#ec003f,color:#8b0836
  class trigger,done,held,aside,end_ event
  class detect,install,phases,artifact ci
  class dinstall,setup,download,rebuild,wrangler,post deploy
  class gate,which,hold,tip,reuse,migrate decision
  class workers target
  class blocked refused
```

Merges made with `GITHUB_TOKEN` (such as Dependabot auto-merge) start no workflow on `main`. The opt-in catch-up closes that gap, and the opt-in runner picker chooses hosted or self-hosted runners for a private repository:

```mermaid
%%{init: {"theme": "base", "themeVariables": {"fontFamily": "ui-sans-serif, system-ui, sans-serif", "lineColor": "#62748e", "primaryTextColor": "#0f172b", "edgeLabelBackground": "#f1f5f9", "clusterBkg": "#f8fafc", "clusterBorder": "#cad5e2", "titleColor": "#314158"}}}%%
flowchart LR
  subgraph catchup ["cd-catch-up.yml (--catch-up), hourly"]
    direction TB
    tipq{"does the main tip<br/>have a cd run?"} -- yes --> idle(["nothing to do"])
    tipq -- no --> dispatch("workflow_dispatch cd on main<br/>with GITHUB_TOKEN")
  end
  dispatch --> cdrun(["cd runs: ci, gate, deploy"])

  subgraph pick ["pick-runner.yml (opt-in, runs on self-hosted)"]
    direction TB
    pub{"repository public<br/>or unknown?"} -- yes --> hosted1(["hosted runner"])
    pub -- no --> token{"BILLING_READ_TOKEN set<br/>and usage readable?"}
    token -- no --> selfh1(["self-hosted runner"])
    token -- yes --> left{"included minutes left<br/>> threshold?"}
    left -- yes --> hosted2(["hosted runner"])
    left -- no --> selfh2(["self-hosted runner"])
  end

  classDef ci fill:#dff2fe,stroke:#0084d1,color:#024a70
  classDef deploy fill:#d0fae5,stroke:#009966,color:#004f3b
  classDef decision fill:#fef3c6,stroke:#e17100,color:#7b3306
  classDef event fill:#f1f5f9,stroke:#62748e,color:#1d293d
  class tipq,pub,token,left decision
  class dispatch deploy
  class idle,cdrun,hosted1,hosted2,selfh1,selfh2 event
```

Installing, choosing a runner and releasing tie the two repositories together. Callers pin `@vX`, which the `release` workflow moves to each new `vX.Y.Z`:

```mermaid
%%{init: {"theme": "base", "themeVariables": {"fontFamily": "ui-sans-serif, system-ui, sans-serif", "lineColor": "#62748e", "primaryTextColor": "#0f172b", "edgeLabelBackground": "#f1f5f9", "clusterBkg": "#f8fafc", "clusterBorder": "#cad5e2", "titleColor": "#314158"}}}%%
flowchart LR
  subgraph kit ["hashorva/cd-kit"]
    direction TB
    cut("push a vX.Y.Z tag,<br/>or run release from main") --> release("release.yml")
    release --> ghrelease("GitHub release vX.Y.Z")
    release --> major("move the vX tag")
  end

  subgraph consumer ["consuming repository"]
    direction TB
    run("install.sh --ref vX") --> runner{"--runner"}
    runner -- github --> hosted("runs-on: ubuntu-latest")
    runner -- "self-hosted, or --runs-on labels" --> visibility{"repository private?"}
    visibility -- yes --> selfhosted("runs-on: your self-hosted labels")
    visibility -- "no / unknown" --> refused(["refused"])
    hosted --> cd(".github/workflows/cd.yml<br/>uses: hashorva/cd-kit/…@vX")
    selfhosted --> cd
    cd -. "--catch-up" .-> cu("cd-catch-up.yml")
  end

  major -. "install.sh and templates fetched at vX" .-> run
  cd -- "ci.yml, deploy-cloudflare.yml and post-deploy.yml resolved at vX" --> major

  classDef release fill:#ede9fe,stroke:#7f22fe,color:#4d179a
  classDef install fill:#dff2fe,stroke:#0084d1,color:#024a70
  classDef decision fill:#fef3c6,stroke:#e17100,color:#7b3306
  classDef refused fill:#ffe4e6,stroke:#ec003f,color:#8b0836
  class cut,release,ghrelease,major release
  class run,hosted,selfhosted,cd,cu install
  class runner,visibility decision
  class refused refused
```

## Install

From the root of the consuming repository:

```sh
curl -fsSL https://raw.githubusercontent.com/hashorva/cd-kit/v0/install.sh | bash -s -- --ref v0
```

This writes `.github/workflows/cd.yml`, which runs CI on every pull request and push, and deploys to Cloudflare Workers on pushes to `main` and on `vX.Y.Z` tags. Then:

- Add `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` as secrets on the `production` GitHub Environment only, so pull-request jobs never see them. On a public repo, limit that environment to the `main` branch and `v*` tags. Callers that still keep them as repository secrets can pass them with `secrets:` as before.
- Require the status check `gate` in the branch ruleset. A skipped reusable-workflow job reports as `ci`, not `ci / ci`, so requiring `ci` can block every pull request; `gate` always runs and fails unless CI succeeded.
- Do not set "Require deployments to succeed" on the branch ruleset: it blocks the merge that triggers the deploy.
- Create release tags in the GitHub Releases UI. A tag pushed with `GITHUB_TOKEN` does not start the deploy. Pushing an older tag is a rollback.
- Set `keep_vars: true` in the wrangler config (`keep_vars = true` in TOML) so a deploy does not wipe variables set in the dashboard.

| Option | Default | |
| --- | --- | --- |
| `--ref <tag>` | required | cd-kit tag to pin: `v0` follows the latest v0 release, `v0.1.0` is fixed |
| `--runner github\|self-hosted` | `github` | `self-hosted` uses `["self-hosted"]` |
| `--runs-on <json>` | | explicit runner labels, overrides `--runner` |
| `--visibility public\|private` | detected with `gh` | self-hosted runners are refused for public repos |
| `--branch <name>` | `main` | branch that deploys to production |
| `--working-directory <dir>` | `.` | directory holding `package.json` |
| `--catch-up` | off | also write `cd-catch-up.yml` (see below) |
| `--force` | | overwrite an existing `cd.yml` (use to upgrade) |
| `--dry-run` | | print instead of writing |

Private repo on your own self-hosted runners, targeting their labels:

```sh
curl -fsSL https://raw.githubusercontent.com/hashorva/cd-kit/v0/install.sh | bash -s -- --ref v0 --runs-on '["self-hosted","linux"]'
```

## Reusable workflows

### `ci.yml`

Detects the package manager from the lockfile (npm, pnpm, yarn, bun), installs with a frozen lockfile, then runs `lint`, `typecheck`, `test` and `build`. Each phase runs the package.json script of that name when it exists and is skipped otherwise.

| Input | Default | |
| --- | --- | --- |
| `runs-on` | `'"ubuntu-latest"'` | JSON label or array |
| `working-directory` | `.` | |
| `node-version` / `node-version-file` | `24` / | the file wins when set |
| `lint-command`, `typecheck-command`, `test-command`, `build-command` | | override a phase; `-` skips it |
| `build-artifact-path` | | upload this path as the `build` artifact |

### `deploy-cloudflare.yml`

Installs, builds (or downloads the `build` artifact from `ci.yml`) and runs wrangler. One deploy per GitHub environment at a time, queued and never cancelled. With `production-branch` set, a run that is no longer the tip of that branch stands aside before installing, so overlapping deploys cannot clobber each other.

| Input | Default | |
| --- | --- | --- |
| `runs-on`, `working-directory`, `node-version`, `node-version-file` | as above | |
| `environment` | `production` | GitHub environment |
| `wrangler-environment` | | wrangler `--env` |
| `wrangler-command` | `deploy` | e.g. `versions upload` for a preview |
| `wrangler-version` | | defaults to the project's wrangler |
| `build-command` | | as in `ci.yml` |
| `build-artifact-path` | | reuse the CI build instead of rebuilding |
| `production-branch` | | branch whose tip deploys; empty never stands aside (use it for tags) |

Secrets: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, read from the job's GitHub Environment (optional to pass). Outputs: `deployment-url`, `deployed`.

### `post-deploy.yml`

Optional hook: runs one generic shell command after a successful deploy, from CI, in the same environment (so the Cloudflare secrets are in its environment variables) and in its own queue. Skipped when `command` is empty. Migrate from CI, never inside a request. The template passes the repository variable `CD_MIGRATE_COMMAND`.

| Input | Default | |
| --- | --- | --- |
| `command` | | shell command; empty skips the job |
| `runs-on`, `working-directory`, `node-version`, `node-version-file`, `environment` | as above | |

### `catch-up.yml`

Merges made with `GITHUB_TOKEN` (such as Dependabot auto-merge) start no `main` CI and no deploy. This job finds a branch tip with no run of the caller workflow and starts one with `workflow_dispatch`, which `GITHUB_TOKEN` may trigger. It needs no token of its own. Opt in with `install.sh --catch-up`, which writes an hourly `cd-catch-up.yml` (about 24 short runs a day; mind that on hosted minutes). Inputs: `branch` (`main`), `workflow` (`cd.yml`), `runs-on`.

### `pick-runner.yml`

For **private** repos: spend the included GitHub-hosted minutes first, then fall back to self-hosted. Opt in by calling it and passing its output to the other workflows; the installed template keeps a static `runs-on`.

```yaml
  pick:
    uses: hashorva/cd-kit/.github/workflows/pick-runner.yml@v0
    secrets:
      BILLING_READ_TOKEN: ${{ secrets.BILLING_READ_TOKEN }}
  ci:
    needs: pick
    uses: hashorva/cd-kit/.github/workflows/ci.yml@v0
    with:
      runs-on: ${{ needs.pick.outputs.runs-on }}
```

| Input | Default | |
| --- | --- | --- |
| `self-hosted-labels` | `'["self-hosted"]'` | runs the picker itself and is the fallback |
| `hosted-labels` | `'"ubuntu-latest"'` | used while minutes remain |
| `threshold` | `200` | hosted while more than this many included minutes remain |
| `included-minutes` | `0` | monthly included minutes; 0 infers them from the plan (free 2000, pro/team 3000, enterprise 50000) |

Secret `BILLING_READ_TOKEN`: a fine-grained personal access token with Plan: read, which you create. The picker runs on `self-hosted-labels`, never on a hosted runner (hosted jobs round up to a minute, and with a $0 budget a hosted picker cannot start). It falls back to self-hosted when the secret is missing, an API call fails or usage is unclear, and never outputs self-hosted labels for a public repo. Billing data lags by minutes to hours and is read per calendar month, so keep the threshold generous. Also set the Actions budget to $0 with stop-usage on (owner setting), so hosted minutes can never be billed. Keep `gate` and other required checks on a static runner that cannot disappear, such as your self-hosted labels.

## Releasing

Either push a `vX.Y.Z` tag, or run the `release` workflow from `main` (Actions → release → Run workflow) with the version; the latter tags the current `main` commit. The workflow publishes a GitHub release and moves the `vX` tag to it, so callers on `@vX` pick it up.

## Development

```sh
shellcheck install.sh tests/*.sh
actionlint
bash tests/install.sh
```

The `self-test` workflow runs the same checks, then installs into a scratch repo and lints the generated workflow. The `flowchart-check` workflow fails a pull request that changes `.github/workflows/` or `templates/` without changing this README; the `no-flowchart-change` label skips it for changes that do not alter behaviour. cd-kit's own workflows stay on GitHub-hosted runners.

## Sources

GitHub Actions:

- [Reusing workflows](https://docs.github.com/en/actions/sharing-automations/reusing-workflows): `workflow_call` inputs, secrets and outputs, and calling a workflow pinned to a tag.
- [Workflow syntax](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions): `runs-on`, `needs`, `if`, `permissions`, `defaults.run`.
- [Expressions](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/evaluate-expressions-in-workflows-and-actions): `fromJSON`, used to pass `runs-on` as a JSON string.
- [Concurrency](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/control-the-concurrency-of-workflows-and-jobs): one deploy per environment, pull-request runs cancelled when superseded.
- [Deployment environments](https://docs.github.com/en/actions/managing-workflow-runs-and-deployments/managing-deployments/managing-environments-for-deployment): the `production` environment, its protection rules and secrets.
- [Storing and sharing data from a workflow](https://docs.github.com/en/actions/writing-workflows/choosing-what-your-workflow-does/storing-and-sharing-data-from-a-workflow): the `build` artifact passed from CI to deploy.
- [About self-hosted runners](https://docs.github.com/en/actions/hosting-your-own-runners/managing-self-hosted-runners/about-self-hosted-runners) and [security hardening](https://docs.github.com/en/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions): why self-hosted runners are refused for public repositories.
- [Action versioning](https://github.com/actions/toolkit/blob/main/docs/action-versioning.md): the `vX.Y.Z` release plus moving `vX` major tag convention.

Actions used: [actions/checkout](https://github.com/actions/checkout), [actions/setup-node](https://github.com/actions/setup-node), [actions/github-script](https://github.com/actions/github-script), [oven-sh/setup-bun](https://github.com/oven-sh/setup-bun), [actions/upload-artifact](https://github.com/actions/upload-artifact), [actions/download-artifact](https://github.com/actions/download-artifact), [cloudflare/wrangler-action](https://github.com/cloudflare/wrangler-action).

Cloudflare and tooling:

- [Cloudflare Workers: GitHub Actions](https://developers.cloudflare.com/workers/ci-cd/external-cicd/github-actions/): API token and account ID secrets.
- [Wrangler commands](https://developers.cloudflare.com/workers/wrangler/commands/): `deploy`, `versions upload`, `--env`.
- [Corepack](https://nodejs.org/api/corepack.html): pnpm and yarn versions from `packageManager`.
- [actionlint](https://github.com/rhysd/actionlint) and [ShellCheck](https://www.shellcheck.net/): the self-test linters.
- [Mermaid flowcharts on GitHub](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-diagrams): how the diagrams above render.

License: [PolyForm Shield 1.0.0](https://polyformproject.org/licenses/shield/1.0.0/).
