# Lab 18 review: Helm internals and advanced operations

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** "Helm v3.17+", the adoption warning, the updated Helm 4 table header, and Option A. Parts A–D reproduce, including mapkubeapis.

## New bug

- **N1 (medium): Option B after Option A re-blocks the release.** Option A's rollback leaves the old revision in `pending-upgrade` permanently. Following the note ("re-run the python patch ... before testing Option B") patches and deletes the *latest* revision, which exposes the older `pending-upgrade` revision, so the upgrade fails again with `another operation ... is in progress`. Verified sequence: after A, history is `1 superseded, 2 pending-upgrade, 3 deployed`; after B, it's `1 superseded, 2 pending-upgrade`, and the upgrade is blocked. **Verified fix:** delete every pending revision Secret, `kubectl delete secret -n helm-internals -l owner=helm,name=internals-demo,status=pending-upgrade`, after which the upgrade succeeds. Alternatively, practice Option B on a fresh release.

## Still open (minor)

- **B4:** The Helm 4 table still claims "Server-Side Apply allows managing CRDs declaratively" under CRD upgrades. Helm 4 doesn't change the `crds/` directory's install-only behavior as far as I know. Verify against the release notes.
- **I1:** The Part D expected error omits the `ensure CRDs are installed first` line.
- **I3, I4, S2, S4** as before.
