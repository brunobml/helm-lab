# Lab 2 review: Release lifecycle

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The explained history samples now follow the lab's revision sequence. The lab reproduces history 1 superseded, 2 superseded, 3 deployed, 4 failed, and the rollback to 3.

## Still open (suggestions only)

- **S2:** "roll back to the last successful revision ... using the rollback command above" is still vague. Say "the newest `deployed` revision (3 if you followed this lab)".
- **S1, S3–S7** as before (`--max 1`, `--reuse-values` behavior, `--revision`, `--atomic` foreshadowing, a shorter timeout, and the tag clash).
