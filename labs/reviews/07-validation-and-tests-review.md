# Lab 7 review: Validation and tests

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The schema error format, the `helm test` output format (`TEST SUITE / Phase / POD LOGS`), the expected page content, and the explicit break-it steps. All re-verified: `Phase: Failed`, `wget: bad address 'does-not-exist:80'`, then recovery.

## Still open (minor)

- **I1:** `$schema` uses `https://json-schema.org/draft-07/schema#`. The canonical draft-07 ID is `http://`.
- **I3:** The test Pod labels are hand-written. Consider a non-selector labels helper (Lab 10 now has `hookLabels`, which could be reused).
- **S2–S5** as before.
