# Extension review: Identity and secrets

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The Deployment and values hints, the render loop, the dev-values upgrades, and the break-it/recovery commands. The re-run gave `fake-training-value`, `can-i` yes, and `CreateContainerConfigError` while the old Pod serves.

## Still open (suggestions only)

- **S1:** `automountServiceAccountToken: false`.
- **S2:** Use a helper instead of `printf "%s-page"` in `rbac.yaml`.
- **S3:** Note that `envFrom` exposes every key.
- **I2 / I3** as before.
