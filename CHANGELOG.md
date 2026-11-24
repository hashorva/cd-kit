# Changelog

## v0.1.1

- Changed: the default `node-version` input of `ci.yml` and `deploy-cloudflare.yml` is now `24` (was `22`). Callers can keep Node 22 by passing `node-version: "22"`. `node-version-file` still takes precedence when set.
- Changed: `actions/setup-node` v4 to v7, which runs on the Node 24 action runtime (#4).
- Changed: actions moved off the Node 20 runtime to Node 24 versions: `actions/checkout` v4 to v7.0.1, `actions/upload-artifact` v4 to v7.0.2, `actions/download-artifact` v4 to v8.0.2, `cloudflare/wrangler-action` v3 to v4.1.3 (`actions/setup-node` was already v7).
- Changed: `wrangler-action` v4 installs Wrangler v4 when `wrangler-version` is empty and the project has no Wrangler installed of its own. Projects that depend on `wrangler` are unaffected; set `wrangler-version` to pin another version.
- Changed: every `uses:` in all four workflows is pinned to a full commit SHA with a version comment (`oven-sh/setup-bun` v2.2.0 too). `self-test.yml` and `release.yml` stay on `ubuntu-latest`.
- Docs: README flowchart (mermaid) (#3); inputs table shows the new Node default.

## v0.1.0

- Initial release (#2).
