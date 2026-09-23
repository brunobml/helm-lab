# Lab 14: Consuming third-party charts and upgrading safely

**Start:** Lab 13 complete (`lab-13-complete`). Namespace `helm-lab` on your disposable cluster.
**Goal:** Search, inspect, override, upgrade, post-render with Kustomize, and roll back third-party charts safely in production.

Most production Helm usage involves consuming charts written and maintained by others (e.g., databases, ingress controllers, observability agents). While authoring charts teaches you the internal engine, *consuming* external charts requires a disciplined operational playbook: pinning exact versions, maintaining minimal value deltas, previewing changes with `helm diff`, patching gaps with `--post-renderer`, and knowing how to recover when upstream releases break.

This lab uses [podinfo](https://github.com/stefanprodan/podinfo), a lightweight, CNCF-standard microservice chart designed to demonstrate Kubernetes and Helm patterns.

---

## Part A: Discovery and inspection

### Step 1: Add the repository and search

Add the upstream chart repository and update the local index:

```bash
helm repo add podinfo https://stefanprodan.github.io/podinfo
helm repo update podinfo
```

Search available chart versions:

```bash
helm search repo podinfo/podinfo --versions | head -10
```

*Expect:* A list of semantic chart versions (`6.15.0`, `6.14.1`, `6.14.0`, etc.) and corresponding application versions.

### Step 2: Inspect before installing (no cluster needed)

Before deploying an unknown chart, inspect its metadata, documentation, and configurable values:

```bash
# Chart metadata (type, dependencies, maintainers)
helm show chart podinfo/podinfo --version 6.14.0

# Official README and installation notes
helm show readme podinfo/podinfo --version 6.14.0 | head -30

# Default values hierarchy
helm show values podinfo/podinfo --version 6.14.0 | head -40
```

Notice that `podinfo` organizes its values logically under top-level keys like `ui:`, `resources:`, and `replicaCount:`.

---

## Part B: Safe overrides and minimal values

### Step 3: Write a minimal delta values file

> [!WARNING]
> **The Full-Copy Anti-Pattern:** Never copy an upstream chart's entire 500-line `values.yaml` into your repository. Full copies shadow future upstream defaults, keep obsolete settings, and hide what your team actually customized.

Create `values-podinfo.yaml` containing **only** the keys you intend to override:

```yaml
replicaCount: 2

ui:
  color: "#34577c"
  message: "Helm Lab Third-Party Chart"

resources:
  requests:
    cpu: 10m
    memory: 16Mi
```

### Step 4: Inspect the upstream templates

To understand how your values are actually used, fetch and unpack the chart locally:

```bash
PODINFO_SRC=$(mktemp -d)
helm pull podinfo/podinfo --version 6.14.0 --untar -d "$PODINFO_SRC"
grep -A 5 "PODINFO_UI_MESSAGE" "$PODINFO_SRC/podinfo/templates/deployment.yaml"
rm -rf "$PODINFO_SRC"
```

You can see that `ui.message` maps to an environment variable `PODINFO_UI_MESSAGE` inside the container.

### Step 5: Render and deploy with a pinned version

Always specify `--version` explicitly:

```bash
# Validate rendering
helm template my-podinfo podinfo/podinfo --version 6.14.0 -f values-podinfo.yaml | grep -E "image:|replicas:"

# Deploy to helm-lab
helm install my-podinfo podinfo/podinfo --version 6.14.0 -n helm-lab \
  -f values-podinfo.yaml --wait --timeout 90s

kubectl rollout status deployment/my-podinfo -n helm-lab --timeout=90s
kubectl get pods -n helm-lab -l app.kubernetes.io/name=my-podinfo
```

*Expect:* Two Pods, each `1/1 Running`. (`--wait` honors the chart's rollout strategy and can return
while the second Pod is still starting; `rollout status` waits for both.)

Test the service from within the cluster:

```bash
kubectl run curl --rm -i --restart=Never --image=busybox:1.36 -n helm-lab -q -- wget -qO- http://my-podinfo:9898/ | grep "message"
```

*Expect:* `"message": "Helm Lab Third-Party Chart"`.

---

## Part C: The upgrade playbook

Upstream maintainers release new versions with bug fixes, security patches, and schema changes. Never run `helm upgrade` blindly.

### Step 6: Diff before upgrading

Compare your currently deployed release against the new chart version (`6.15.0`):

```bash
helm diff upgrade my-podinfo podinfo/podinfo -n helm-lab \
  --version 6.15.0 -f values-podinfo.yaml
```

*Expect:* A clear color-coded diff showing:

- `chart: podinfo-6.14.0` -> `podinfo-6.15.0`
- `app.kubernetes.io/version: "6.14.0"` -> `"6.15.0"`
- `image: "ghcr.io/stefanprodan/podinfo:6.14.0"` -> `"ghcr.io/stefanprodan/podinfo:6.15.0"`
- No unexpected changes to your overridden replicas, resources, or UI message.

### Step 7: Execute the upgrade

```bash
helm upgrade my-podinfo podinfo/podinfo -n helm-lab \
  --version 6.15.0 -f values-podinfo.yaml --wait --timeout 90s

helm history my-podinfo -n helm-lab
```

*Expect:* Revision 2 marked `deployed` with chart version `podinfo-6.15.0`.

---

## Part D: When values cannot do it — Post-rendering with Kustomize

What happens when an upstream chart does not expose a value for a field your organization requires (e.g., custom compliance annotations, specialized security sidecars, or specific labels)?

**Do not fork the chart.** Forking creates an ongoing maintenance burden to sync upstream changes. Instead, use Helm's native `--post-renderer` feature combined with `kubectl kustomize`.

### Step 8: Create the post-renderer overlay

Helm passes its rendered YAML to the post-renderer via `stdin`, and expects the modified YAML on `stdout`.

Create `post-render/kustomization.yaml`:

```yaml
resources:
  - manifests.yaml

patches:
  - target:
      kind: Deployment
      name: my-podinfo
    patch: |-
      - op: add
        path: /metadata/annotations/company.internal~1audit-policy
        value: strict-v1
```

Create `post-render/kustomize.sh`:

```bash
#!/bin/bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
cp "$DIR/kustomization.yaml" "$TMP/"
cat <&0 > "$TMP/manifests.yaml"
kubectl kustomize "$TMP"
```

Make the script executable:

```bash
chmod +x post-render/kustomize.sh
```

### Step 9: Preview and upgrade with post-rendering

Preview the post-renderer modifications using `helm diff`:

```bash
helm diff upgrade my-podinfo podinfo/podinfo -n helm-lab \
  --version 6.15.0 -f values-podinfo.yaml --post-renderer post-render/kustomize.sh
```

Notice the addition of `company.internal/audit-policy: strict-v1` on the Deployment metadata.

Now apply the upgrade:

```bash
helm upgrade my-podinfo podinfo/podinfo -n helm-lab \
  --version 6.15.0 -f values-podinfo.yaml \
  --post-renderer post-render/kustomize.sh --wait --timeout 90s
```

Verify that the annotation exists on the cluster:

```bash
kubectl get deployment my-podinfo -n helm-lab -o jsonpath='{.metadata.annotations.company\.internal/audit-policy}{"\n"}'
```

*Expect:* `strict-v1`.

---

## Part E: Rehearse rollback

If an upgrade introduces an unexpected issue, roll back to the previous stable revision:

```bash
helm rollback my-podinfo 2 -n helm-lab --wait --timeout 90s
helm history my-podinfo -n helm-lab
```

*Expect:* Revision 4 created as `Rollback to 2`. Verify that the post-render annotation has been removed:

```bash
kubectl get deployment my-podinfo -n helm-lab -o jsonpath='{.metadata.annotations.company\.internal/audit-policy}{"\n"}'
```

*Expect:* Empty output (reverted to revision 2).

---

## Verify

### Local

```bash
helm template my-podinfo podinfo/podinfo --version 6.14.0 -f values-podinfo.yaml | grep -c "kind: Deployment"
helm template my-podinfo podinfo/podinfo --version 6.14.0 -f values-podinfo.yaml --post-renderer post-render/kustomize.sh | grep -c "company.internal/audit-policy"
```

### Cluster

```bash
helm status my-podinfo -n helm-lab
kubectl get pods -n helm-lab -l app.kubernetes.io/name=my-podinfo
```

---

## Break it and recover

1. **The floating version trap:** Run `helm template my-podinfo podinfo/podinfo -f values-podinfo.yaml | grep "chart:"`. Notice that omitting `--version` pulls the latest release (`6.15.0`), which in production could silently pull a major breaking change or unvetted release. Always pin `--version`.
2. **Post-renderer failure:** Edit `post-render/kustomization.yaml` and corrupt the patch syntax (e.g. change `op: add` to `op: invalid-op`). Run `helm template my-podinfo podinfo/podinfo --version 6.15.0 -f values-podinfo.yaml --post-renderer post-render/kustomize.sh`. Notice that Helm aborts immediately with an error from the post-renderer, preventing malformed manifests from reaching the cluster. Revert the file.
3. **Values type mismatch and missing schema:** Run `helm template test podinfo/podinfo -n helm-lab --version 6.15.0 --set replicaCount=two | kubectl apply --dry-run=server -f -`. Notice that because `podinfo` lacks a client-side `values.schema.json`, `helm template` silently renders invalid YAML (`replicas: two`). The error only surfaces when validated by the Kubernetes API: `cannot unmarshal string into Go struct field DeploymentSpec.spec.replicas of type int32`. This reinforces why server dry-run validation (Lab 10) is essential when consuming third-party charts.

---

## Explain

- Why is maintaining a minimal delta values file safer across upstream upgrades than copying the full `values.yaml`?
- How does `helm diff upgrade` differ from reviewing release changelogs?
- How does `--post-renderer` work under the hood, and why is it preferred over forking the chart?
- Why is omitting `--version` dangerous in automated CI/CD pipelines?

> [!TIP]
> See [14-consuming-third-party-charts-explained.md](14-consuming-third-party-charts-explained.md) for detailed explanations.

---

## Cleanup and checkpoint

```bash
helm uninstall my-podinfo -n helm-lab
rm -f values-podinfo.yaml
rm -rf post-render
```

Create a personal tag such as `my-lab-14-complete` (the reference
`lab-14-complete` tag already exists in this repository).

---

## Your notes

Record versions, observations, failures, and explanations here.
