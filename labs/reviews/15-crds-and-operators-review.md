# Lab 15 review: CRDs and operators

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** `git checkout main -- charts/crd-demo` gives the 0.1.0 chart, and Part A reproduces every claim (the unknown-field warning, the dropped field, the manifest still showing `replicas: 3`, same-value upgrades not re-applying it, and `5` after a changed value). Parts B and C also reproduce.

## Still open (minor)

- **N2:** Step 4's `kubectl apply` prints a `missing the kubectl.kubernetes.io/last-applied-configuration annotation` warning (Helm created the CRD). Say it's harmless, or use `--server-side`.
- **I2:** Mention `crds.keep: true` as the source of the `keep` annotation. cert-manager v1.16.2 is dated.
- **I3:** Kept CRDs still carry `meta.helm.sh/release-name`. A different release name would hit the ownership error.
- **S2 / S3:** A cluster-level Verify check, and `kubectl wait` for the Certificate.
- **Tag note:** `lab-15-complete` now equals `main`. See the Lab 10 review's tag-semantics item.
