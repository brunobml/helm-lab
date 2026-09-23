# Lab 8 review: Dependencies

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The duplicate `## Steps` heading. The lab works as written. (My earlier B2 about tracked `.tgz` files was wrong and stays withdrawn.)

## Still open

- **B1 (medium):** Explained Q2 still says `Chart.lock` pins "the exact version and checksum of every dependency". The digest covers the dependency declarations, not the contents, and the lab itself says so.
- **I2 (low):** The explained build output still shows `Getting lab-banner 0.1.0 from source chart`. Helm prints `Saving 1 charts` / `Deleting outdated charts`.
- **S2 (low):** Suggest `helm dependency update --skip-refresh` for `file://` dependencies.
- **I1, I3** as before.
