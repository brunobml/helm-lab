# Lab 0 review: Chart creation

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** `mkdir -p charts` lets `helm create` work from an empty workspace. The `version: latest` break-it and the `1`/`"1"` note are accurate.

## Still open

- **B2 (medium):** The **Start** line is still "An empty workspace, a practice branch, or a new worktree", and `README.md` still says "The working chart starts with a Deployment and Service". A learner on `main` who runs `helm create` overwrites the finished chart, and stale `ci/`, `tests/`, schema, and lock files survive. Give a concrete start (for example `git switch -c my-lab-00 lab-00-start`) and fix the README sentence.
- **N1 (low):** The expected lint output shows 3 lines. Helm prints 6, including `templates/: validation ...` and `unable to load chart`.
- **Explained Q1 (low):** It still says `1` fails with `version "1" is not a valid SemVer` (line ~27–30). The break-it section itself is fixed.
- **Minor:** `lab-00-start` differs from what the lab writes (comments and README), so `git diff` is noisy. The other earlier suggestions (S1–S4) remain.
