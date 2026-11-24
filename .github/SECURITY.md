# Security

## Keeping credentials out of the repo

This project never needs your AWS keys in the repo. Access comes from your own AWS CLI
profile/role; runtime settings live in `config.local.json`, which is gitignored. Credential and
local-config files are blocked by several layers, in the order that actually prevents exposure:

1. **`.gitignore`** — keeps credential and `config.local.*` files from being staged at all.
2. **Local pre-commit hook** (`.githooks/pre-commit`) — refuses to commit those files or an obvious
   AWS key. Enable it once per clone:
   ```sh
   git config core.hooksPath .githooks
   ```
3. **GitHub push protection** (enable in repo settings) — blocks a *push* that contains a detected
   secret, before it ever lands on GitHub. This is the layer that stops exposure.
4. **CI secret scan** (`.github/workflows/secret-scan.yml`) — fails any PR that tracks a
   credential/local-config file or whose content trips gitleaks. A required check, so such a PR
   cannot merge.

> Note: once a secret is *pushed* to a branch on GitHub it is already exposed in git history, even if
> CI later blocks the merge. So layers 1–3 (commit- and push-time) are what prevent exposure; the CI
> scan is the backstop that guarantees it never merges.

## Reporting a vulnerability

Open a private security advisory on the repository, or contact the maintainer directly. Please don't
file public issues for security problems.
