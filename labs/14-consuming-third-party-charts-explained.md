# Lab 14: Consuming Third-Party Charts and Upgrading Safely — Explained

[Back to Lab 14](14-consuming-third-party-charts.md)

---

## Overview

Most Kubernetes platforms rely heavily on third-party Helm charts authored by external vendors and open-source communities. Consuming these charts safely requires distinct operational practices from authoring your own: pinning chart versions, isolating your configuration overrides to minimal deltas, validating upgrade changes with `helm diff`, and patching unexposed fields using `--post-renderer` rather than maintaining a forked chart.

---

### Question 1: Why is copying an upstream `values.yaml` considered an anti-pattern?

#### TL;DR

A full copy of an upstream chart's `values.yaml` freezes hundreds of defaults into your repository. When the upstream chart upgrades, your frozen copy will override new upstream defaults, re-introduce deprecated settings, and obscure the few lines your team actually cares about.

#### Deep Dive

1. **Default Shadowing:** Helm evaluates values in precedence order: user-supplied value files override the chart's default `values.yaml`. If you copy all 600 lines of an upstream `values.yaml`, Helm treats every single line as a user override. If version `6.15.0` changes an internal default (e.g. enabling a security parameter or tuning timeouts), your full copy forces the old value, silently overriding the upgrade.
2. **Maintenance Drag:** When an engineer reviews your Git repository, they cannot easily tell whether a given setting is standard or customized. In a 10-line delta file (`values-podinfo.yaml`), every line represents an intentional team decision.
3. **Upstream Schema Drift:** Upstream charts frequently deprecate or rename keys across versions. A full copy retains the old keys, which may cause schema validation failures or silent misconfigurations during subsequent upgrades.
4. **Best Practice:** Keep your values files minimal. Only define values where your requirements differ from upstream defaults.

---

### Question 2: Why must chart versions always be pinned, and how does Helm resolve unpinned charts?

#### TL;DR

If you omit `--version` during `helm install` or `helm upgrade`, Helm automatically resolves the latest available version in the repository index. In automated CI/CD pipelines, this can deploy unexpected major or breaking changes without review.

#### Deep Dive

1. **Resolution Mechanics:** When you run `helm install my-release repo/chart` without `--version`, Helm queries the local repository cache (`~/.cache/helm/repository/`) for the chart entry with the highest semantic version (excluding prereleases).
2. **The Drift Hazard:** Upstream maintainers release updates continuously. An unpinned pipeline job running on Monday might deploy chart version `6.14.0`, while the same job on Tuesday could pull version `7.0.0` with breaking schema changes, modified selector labels, or renamed Service ports.
3. **Reproducibility:** Helm release stability depends on deterministic inputs. Pinning `--version 6.14.0` ensures that staging, production, and disaster recovery deployments install byte-identical chart archives.

---

### Question 3: How does `--post-renderer` work under the hood, and when should you choose it over forking?

#### TL;DR

`--post-renderer` allows an external binary (such as a script invoking `kubectl kustomize`) to transform rendered Kubernetes manifests before Helm submits them to the cluster. This allows injecting corporate annotations, sidecars, or custom policies without maintaining a separate chart fork.

#### Deep Dive

1. **Execution Pipeline:**

   ```text
   Chart Templates + Values
             │
             ▼
      Helm Template Engine
             │ (Raw YAML)
             ▼ (stdin)
     Post-Renderer Script  ──>  kubectl kustomize
             ▲ (stdout)
             │ (Patched YAML)
             ▼
     Kubernetes API Server
   ```

   Helm renders the chart locally, passes the complete multi-document YAML via `stdin` to the executable passed to `--post-renderer`, and reads the transformed YAML from `stdout`.
2. **Why Not Fork?**
   - Forking requires maintaining a Git clone of the upstream chart repository.
   - Every time upstream releases a security patch or bug fix, your team must manually rebase or cherry-pick changes. Over time, forks drift, become painful to maintain, and fall behind on critical CVE patches.
3. **Kustomize Strategic Overlays:**
   - With `--post-renderer`, you treat the upstream chart as an immutable dependency and store only small Kustomize patch files in your repository.
   - Upstream updates can be consumed immediately by bumping `--version`, while your local Kustomize overlay continues applying your organizational patches (e.g., audit annotations, custom ingress annotations, or service mesh proxy sidecars).

---

### Question 4: How does `helm diff upgrade` prevent production outages?

#### TL;DR

`helm diff upgrade` compares your currently running release in the cluster against the rendered output of the proposed upgrade. Unlike changelogs or dry-runs, it shows the exact resource mutations about to occur on the live Kubernetes cluster.

#### Deep Dive

1. **Three-Way Comparison:** `helm diff` inspects the release Secret in the target namespace, reconstructs the currently active manifests, and performs a line-by-line unified diff against the upcoming render.
2. **What Dry-Run Misses:**
   - `helm upgrade --dry-run` prints the full rendered manifest, which can span thousands of lines across multi-resource charts. An engineer cannot easily spot a 1-line change buried in a large YAML dump.
   - In contrast, `helm diff upgrade` highlights only the additions, modifications, and deletions.
3. **Catching Breaking Mutations:**
   - Changing immutable fields (such as `spec.selector.matchLabels` on a Deployment) is rejected by the Kubernetes API and fails mid-rollout.
   - `helm diff` reveals selector or StatefulSet volume claim changes before you issue the upgrade command, allowing you to plan recreation or migration strategies.

---

## Quick reference

| Command | Purpose |
| :--- | :--- |
| `helm repo add <name> <url>` | Register an external chart repository |
| `helm repo update <name>` | Fetch the latest chart index from upstream |
| `helm search repo <chart> --versions` | List all available chart and app versions |
| `helm show values <chart> --version <v>` | View default values hierarchy |
| `helm show readme <chart> --version <v>` | View upstream installation and usage documentation |
| `helm pull <chart> --version <v> --untar` | Unpack chart archive locally to inspect templates |
| `helm diff upgrade <name> <chart> -n <ns> --version <v>` | Inspect exact cluster mutations prior to upgrading |
| `helm upgrade <name> <chart> --post-renderer <script>` | Apply external Kustomize patches during deployment |
| `helm rollback <name> <revision> -n <ns> --wait` | Revert to a previous stable revision |

---

## Common pitfalls

- **Full-copy values:** Copying the upstream `values.yaml` in full instead of specifying only your project's delta overrides.
- **Unpinned versions:** Leaving off `--version` in automated scripts, causing unexpected chart version bumps.
- **Missing namespace in `helm diff`:** Running `helm diff upgrade` without `-n <namespace>`, causing a "release not found" error because releases are namespace-scoped.
- **Forking prematurely:** Forking an upstream chart to add one annotation or label instead of using `--post-renderer`.
- **Non-executable post-render script:** Forgetting `chmod +x` on the post-renderer wrapper script.

---

## Break It and Recover — Detailed Walkthrough

### 1. The Floating Version Trap

#### What Happens

When you run `helm template` or `helm install` without specifying `--version`:

```bash
helm template test podinfo/podinfo -f values-podinfo.yaml | grep "chart:"
```

*Output:*

```yaml
helm.sh/chart: podinfo-6.15.0
```

Helm automatically resolves and renders the newest version published in the repository index.

#### Why It Happens

If `--version` is omitted, Helm defaults to the constraint `>0.0.0-0` (the highest semantic version). In CI/CD pipelines, an unpinned chart can silently trigger major version upgrades, breaking configuration contracts or introducing incompatible Kubernetes API requirements.

#### Key Takeaways & Recovery

- **Rule:** Always pin `--version <exact-semver>` in both command lines and GitOps declarations.

---

### 2. Post-Renderer Syntax Failure

#### What Happens

If an error or invalid patch syntax is introduced into `post-render/kustomization.yaml`:

```yaml
patches:
  - target:
      kind: Deployment
      name: my-podinfo
    patch: |-
      - op: invalid-op
        path: /metadata/annotations/test
```

Running `helm template` or `helm upgrade` with `--post-renderer` fails immediately:

```text
Error: error while running post render on files: error while running command post-render/kustomize.sh: exit status 1
```

#### Why It Happens

Helm validates the exit code of the post-renderer process. If Kustomize fails to apply a patch or encounters a syntax error, the script exits with non-zero status. Helm aborts the entire upgrade process before any changes are sent to the Kubernetes API server.

#### Key Takeaways & Recovery

- **Fail-Safe Execution:** Malformed post-renderer scripts cannot corrupt cluster state because Helm halts prior to manifest submission.
- **Recovery:** Correct the Kustomize patch syntax and rerun the command.

---

### 3. Values Type Mismatch & Missing Client-Side Schema

#### What Happens

When you pass an invalid data type to a third-party chart that lacks a `values.schema.json`:

```bash
helm template test podinfo/podinfo -n helm-lab --version 6.15.0 --set replicaCount=two | kubectl apply --dry-run=server -f -
```

*Output:*

```text
Error from server (BadRequest): error when creating "STDIN": Deployment in version "v1" cannot be handled as a Deployment: json: cannot unmarshal string into Go struct field DeploymentSpec.spec.replicas of type int32
```

#### Why It Happens

Unlike `nginx-demo` (which defined a strict `values.schema.json` in Lab 7), many upstream community charts do not publish a client-side JSON schema. Consequently, `helm template` silently interpolates the invalid string into the YAML manifest:

```yaml
spec:
  replicas: two
```

The error is not caught during local rendering. It only surfaces when submitted to the Kubernetes API server, which fails to unmarshal the string into the typed Go integer field.

#### Key Takeaways & Recovery

- **Why Server Dry-Run is Essential:** When consuming external charts without client schemas, running `helm template ... | kubectl apply --dry-run=server -f -` before deployment catches syntax and type errors against real Kubernetes OpenAPI schemas.
- **Recovery:** Supply the correct data type in your values file (e.g. `replicaCount: 2`).
