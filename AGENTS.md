# AGENTS.md

Rules for agents working in this repository.

- **Flowcharts.** A change to workflow behaviour (`.github/workflows/`, `templates/`) must update the mermaid flowcharts in `README.md` in the same PR. The `flowchart-check` CI job fails otherwise; the `no-flowchart-change` PR label is only for changes that do not alter behaviour.
- **Public kit.** This repository is public (PolyForm Shield 1.0.0). Do not change the license or visibility.
- **Hosted CI only.** cd-kit's own workflows (`self-test.yml`, `release.yml`, `flowchart-check.yml`) run on `ubuntu-latest`. Never add self-hosted labels to them.
- **No `pull_request_target`.**
- **No tags.** Do not create or move git tags or run the release workflow; the maintainer releases.
- **Pins.** Actions are pinned to a full commit SHA with a version comment, at a release at least 7 days old. Keep a pin only if a comment explains why.
- **Compatibility.** Callers pin `@v0`: new workflow inputs are additive with safe defaults; never rename or remove one.
