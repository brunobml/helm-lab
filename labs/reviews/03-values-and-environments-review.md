# Lab 3 review: Values and environments

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** Explained B1 (when upgrade reuses values), B2 (the real ownership-collision error), and B3 (object identity). The lab reproduces renders 1/3/4 and the Deployments at 1/1 and 3/3.

## Still open (suggestions only)

- **S2:** Verify still uses `kubectl get service ... -o yaml` (about 60 lines for one fact). Use `-o custom-columns=NAME:.metadata.name,SELECTOR:.spec.selector`.
- **S1, S3–S6** as before (one-liners for the values files, the reversed `-f` demo, why `--reset-values`, a real targetPort failure test, and the tag clash).
