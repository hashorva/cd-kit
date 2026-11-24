# Changelog

## v0.1.1

- Changed: the default `node-version` input of `ci.yml` and `deploy-cloudflare.yml` is now `24` (was `22`). Callers can keep Node 22 by passing `node-version: "22"`. `node-version-file` still takes precedence when set.
- Changed: `actions/setup-node` v4 to v7, which runs on the Node 24 action runtime (#4).
- Changed: every `uses:` in `ci.yml` and `deploy-cloudflare.yml` is pinned to a full commit SHA with a version comment.
- Docs: README flowchart (mermaid) (#3); inputs table shows the new Node default.

## v0.1.0

- Initial release (#2).
