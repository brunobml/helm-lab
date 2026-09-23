# Extension review: Storage and other workloads

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The Chart/values hint, the `-` idiom for an explicit empty `storageClassName` (renders `""`), the marker commands, and the immutable → Pending → recover break-it sequence.

## Still open

- **M1 (medium):** Step 4 (Job, CronJob, StatefulSet, DaemonSet) still has no hints or content.
- **I1 (medium):** The Deployment + `ReadWriteOnce` PVC still uses `RollingUpdate`. Suggest `strategy: Recreate`.
- **M4:** The explained page doesn't mention `helm.sh/resource-policy: keep`.
- **I2, I3, S2:** labels, the explained page's `marker.txt` names, and a note that `WaitForFirstConsumer` shows `Pending` right after install without `--wait` (observed in the recover step).
