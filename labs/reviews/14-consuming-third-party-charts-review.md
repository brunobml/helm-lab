# Lab 14 review: Consuming third-party charts

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (Helm v3.19.0, podinfo 6.14.0/6.15.0, kind v1.35.0).

**Fixed and verified:**

- **B1:** Verify now prints `1`. Break-it 2 fails as documented: `error: Unexpected kind: invalid-op`.
- **B2:** The podinfo link is fixed.
- **S1:** `kustomize.sh` uses a temp dir with `set -euo pipefail`. No `manifests.yaml` is left in `post-render/`, the install applies `company.internal/audit-policy: strict-v1`, and the script propagates failures.

## Still open (minor)

- **I1:** Step 5 still says "Two Pods in `Running` state (`2/2`)". Each Pod is `1/1`.
- **New N1:** Right after `helm install ... --wait`, the re-run showed the two podinfo Pods as `1/1` and `0/1`. Helm's wait honors the chart's rollout strategy (`maxUnavailable`), so it can return before both Pods are Ready. Tell learners to run `kubectl rollout status deployment/my-podinfo -n helm-lab` before checking, and fix the "(`2/2`)" wording in I1 at the same time.
- **I2:** Step 9: the post-rendered `helm diff` is noisy (re-run: **184** changed lines with the post-renderer versus **10** without) (kustomize re-serializes the manifests). Suggest `--normalize-manifests` or `-C 3` (both exist in helm-diff 3.15.13).
- **I3:** Step 1's expected version list will drift. Say "your list may include newer versions".
- **I4:** `lab-14-complete` contains no Lab 14 artifacts. Note in the README that it's a documentation-only checkpoint.
- **S2:** Helm 4 forward note: `--post-renderer` takes a plugin name there.
- **S3:** Step 4 still uses `/tmp/podinfo-src`. Use `mktemp -d`.
- **S4:** Add `helm test my-podinfo` (podinfo ships test hooks).
- **S5:** Explain that rollback restores the **stored, already post-rendered** manifest, and that the post-renderer isn't re-run.
- **Break-it 3** still renders with release name `test`. That's harmless there (no post-renderer), but use `my-podinfo` for consistency.
