# cd-kit

Reusable, auto-installing continuous-deployment recipe extracted from [finduck](https://github.com/hashorva/finduck).

It packages versioned GitHub Actions reusable workflows and an installer for Zamir's other projects (Astro+EmDash, Vite, Tailwind, React, shadcn; Cloudflare Workers; GitHub; Mac mini runners for private repos, GitHub-hosted for public). Callers pin a release tag.

This repository is public. Public consumers stay on GitHub-hosted runners. Private consumers may pass self-hosted Mini runners through a `runs-on` input.

See [hashorva/finduck#237](https://github.com/hashorva/finduck/issues/237).
