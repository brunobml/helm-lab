# Lab 8: Dependencies

**Start:** Lab 7 complete (`lab-07-complete`).
**Goal:** Learn parent/subchart boundaries and reproducible dependency resolution.

Use a tiny local companion chart that creates a ConfigMap. This isolates Helm
composition from database setup and image downloads.

## Steps

## Steps

### Step 1: Create the subchart metadata and values

Create the directory `charts/lab-banner/` and add its metadata file `charts/lab-banner/Chart.yaml`:

```yaml
apiVersion: v2
name: lab-banner
type: application
version: 0.1.0
```

Next, create `charts/lab-banner/values.yaml` with the subchart's default values:

```yaml
message: Hello from the child chart
global: {}
```
> [!NOTE]
> Defining `global: {}` in the child chart's defaults ensures the subchart can be rendered or linted independently without failing on undefined `.Values.global` references.

---

### Step 2: Create the subchart template `charts/lab-banner/templates/configmap.yaml`

Create the subchart template directory `charts/lab-banner/templates/` and add `charts/lab-banner/templates/configmap.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-banner
data:
  message: {{ .Values.message | quote }}
  environment: {{ .Values.global.environment | default "local" | quote }}
```

**Notice value resolution:**
- `.Values.message`: Reads from local subchart values (or parent overrides under the `lab-banner:` key).
- `.Values.global.environment`: Reads from the top-level `global:` key shared across all charts.

---

### Step 3: Declare the dependency in parent `charts/nginx-demo/Chart.yaml`

Open the parent chart's `charts/nginx-demo/Chart.yaml` and append the `dependencies:` block:

```yaml
dependencies:
  - name: lab-banner
    version: 0.1.0
    repository: file://../lab-banner
    condition: lab-banner.enabled
```

> [!IMPORTANT]
> `condition: lab-banner.enabled` inspects the values tree (`.Values.lab-banner.enabled`), **not** `Chart.yaml`. If this key is missing or false in values, Helm skips rendering the subchart entirely.

---

### Step 4: Configure parent default values in `charts/nginx-demo/values.yaml`

Open the parent chart's `charts/nginx-demo/values.yaml` and append the `lab-banner` and `global` blocks:

```yaml
lab-banner:
  enabled: true
  message: Hello from the parent

global:
  environment: local
```

---

### Step 5: Configure dev environment values in `charts/nginx-demo/values-dev.yaml`

Open `charts/nginx-demo/values-dev.yaml` and append the `global` environment setting:

```yaml
global:
  environment: dev
```

---

## Verify

1. **Update and package dependencies:**
   ```bash
   helm dependency update ./charts/nginx-demo
   helm dependency list ./charts/nginx-demo
   ```
   *Expect:* Helm generates `charts/nginx-demo/Chart.lock` and packages `charts/nginx-demo/charts/lab-banner-0.1.0.tgz`. The list shows `lab-banner 0.1.0 ok`.

2. **Lint both charts:**
   ```bash
   helm lint ./charts/lab-banner
   helm lint ./charts/nginx-demo
   ```
   *Expect:* Both charts pass with 0 errors.

3. **Verify template rendering (enabled vs disabled):**
   ```bash
   # Should include demo-dev-banner ConfigMap with environment="dev" and message="Hello from the parent"
   helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml

   # Should omit the banner ConfigMap entirely because condition is false
   helm template demo-dev ./charts/nginx-demo --set lab-banner.enabled=false
   ```

4. **Deploy and inspect cluster state:**
   ```bash
   helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
   kubectl get configmap demo-dev-banner -n helm-lab -o yaml
   helm test demo-dev -n helm-lab --timeout 60s
   ```
   *Expect:* `demo-dev-banner` exists in `helm-lab` namespace with `data.environment: "dev"`. Running `helm list` shows only a single release (`demo-dev`), proving the subchart is managed within the parent release.

## Break it and recover

Delete only the generated `charts/nginx-demo/charts/lab-banner-0.1.0.tgz`, keeping
the source chart and lock file. Try rendering, observe the missing-dependency
error, then recover:

```bash
helm dependency build ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo
```

`update` resolves the declared versions and writes a lock; `build` uses that
lock. If you edit local child sources, bump the child version and update the
parent dependency rather than silently changing the same version. A local lock
is not a content hash for every source file; Git tracks those files.

## Explain

- Which values are visible to the child?
- Why commit the lock file but ignore generated archives?
- When would you intentionally use `update` instead of `build`?

> [!TIP]
> See [08-dependencies-explained.md](08-dependencies-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Keep the child source, parent dependency settings, and `Chart.lock` in Git.
Generated `.tgz` files are ignored. Commit and create `lab-08-complete`.

References: [Subcharts and globals](https://helm.sh/docs/v3/chart_template_guide/subcharts_and_globals/),
[dependency build](https://helm.sh/docs/v3/helm/helm_dependency_build/).

Next: [Packaging and GitOps](09-packaging-and-gitops.md).
