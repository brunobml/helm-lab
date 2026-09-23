# Lab 14 review: Consuming third-party charts

**Tested with:** Helm v3.19.0, helm-diff 3.15.13, podinfo chart 6.14.0 → 6.15.0, kubectl (kustomize v5.8.1), kind (Kubernetes v1.35.0), 2026-09-23
**Result:** Parts A–E work:

- Search and inspect work, and `PODINFO_UI_MESSAGE` is found in the template.
- Install gives 2 Pods, and the message is `"Helm Lab Third-Party Chart"`.
- The upgrade diff shows exactly the chart, version, and image lines.
- The post-renderer adds `company.internal/audit-policy: strict-v1`, and a rollback removes it.
- Break-it 1 (floating version → 6.15.0) and break-it 3 (`cannot unmarshal string into ... spec.replicas of type int32`) reproduce.

**The Verify step and break-it 2 are broken** by a release-name mismatch.

## Bugs

### B1: The Verify post-renderer check prints `0`, and break-it 2 never errors (high)

The Kustomize patch targets `kind: Deployment, name: my-podinfo`. The local Verify and break-it 2 render with release name **`test`**, which produces a Deployment named **`test-podinfo`**, so the patch matches nothing:

| Command | Documented | Actual |
| --- | --- | --- |
| `helm template test ... --post-renderer post-render/kustomize.sh \| grep -c "company.internal/audit-policy"` | `1` (implied) | **`0`** |
| Break-it 2 (`op: invalid-op`) with `helm template test ...` | "Helm aborts immediately with an error" | **Renders successfully**. The invalid patch is never evaluated because nothing matches. |

With release name `my-podinfo`, both behave as documented (`1`, and `error: Unexpected kind: invalid-op`). This is itself a good lesson (post-render patches are coupled to resource names that depend on the release name), but as written the learner just sees the lab "fail".

**Fix:** Use `my-podinfo` in both commands, or target the patch by label (`labelSelector: app.kubernetes.io/name=...`) or by kind only, and add a sentence about name coupling.

### B2: Wrong podinfo repository link (low)

The intro links to `https://github.com/stafanprodan/podinfo` (typo). It should be `stefanprodan`.

## Accuracy issues

- **I1:** Step 5 says "*Expect:* Two Pods in `Running` state (`2/2`)". Each Pod shows `1/1`. "2/2" reads like READY for a single Pod. Say "two Pods, each `1/1 Running`".
- **I2:** Step 9: "Notice the addition of `company.internal/audit-policy: strict-v1`". The actual `helm diff` output is **much noisier**: kustomize re-serializes the manifests (drops `# Source:` comments, reorders keys), so the diff shows many `-`/`+` lines for unchanged fields. Warn learners, or suggest `helm diff ... --normalize-manifests` or `-C 3` (both flags exist in helm-diff 3.15.13).
- **I3:** Step 1 expects versions "`6.15.0`, `6.14.1`, `6.14.0`". That's correct today, but it will drift. Add "(your list may include newer versions; this lab pins 6.14.0 → 6.15.0)".
- **I4:** `lab-14-complete` contains **no** Lab 14 artifacts (no `values-podinfo.yaml`, no `post-render/`), because the lab's cleanup deletes them. The README tag table describes the tag as "minimal values, `helm diff`, post-renderer Kustomize, rollback", which suggests there's something to diff against. Clarify in the README that this checkpoint is documentation-only.

## Security / best-practice suggestions

- **S1:** `post-render/kustomize.sh` writes the **full rendered manifests**, including any Secrets, to `post-render/manifests.yaml` inside the repository, and never deletes it. Use a temp dir:

  ```bash
  #!/bin/bash
  set -euo pipefail
  TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
  cp "$(dirname "$0")/kustomization.yaml" "$TMP/"
  cat > "$TMP/manifests.yaml"
  kubectl kustomize "$TMP"
  ```

  or at least add `post-render/manifests.yaml` to `.gitignore`. Also add `set -euo pipefail` so a failing `kubectl kustomize` reliably propagates.
- **S2:** Forward note for Helm 4: `--post-renderer` there takes a **post-renderer plugin name** rather than an arbitrary executable path. The lab states Helm 3 semantics, but since Lab 18 discusses Helm 4, a one-line pointer here would prevent surprise.
- **S3:** Step 4 uses `/tmp/podinfo-src`. As with Labs 12/13, prefer `mktemp -d`.
- **S4:** podinfo ships `helm test` hooks (the chart pulls `curlimages/curl:7.69.0`, `giantswarm/tiny-tools`, `grpc_health_probe`). Adding `helm test my-podinfo -n helm-lab` shows learners how to use a vendor's own tests after an upgrade, which fits the "upgrade playbook" theme.
- **S5:** Part E: say explicitly *why* the rollback removed the annotation: Helm rolls back to revision 2's **stored, already post-rendered** manifest. The post-renderer is not re-run on rollback. That's a subtle and important point.
