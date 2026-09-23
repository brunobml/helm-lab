# Lab 14 review: Consuming third-party charts

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified:** The lab passes as written (pinned install, diff, upgrade, post-render annotation, rollback, Verify `1`, break-it 2 `Unexpected kind: invalid-op`, and break-it 3).

## Still open (minor)

- **I1:** Step 5 still says "(`2/2`)". Pods are each `1/1`, and one can still be `0/1` right after `--wait`. Add `kubectl rollout status`.
- **I2:** The post-renderer diff is noisy (184 vs 10 lines). Suggest `--normalize-manifests`.
- **S3:** Step 4 still uses `/tmp/podinfo-src`.
- **I3, I4, S2, S4, S5** as before.
