# Lab 8: Dependencies

**Start:** Lab 7 complete (`lab-07-complete`).
**Goal:** Learn parent/subchart boundaries and reproducible dependency resolution.

Use a tiny local companion chart that creates a ConfigMap. This isolates Helm
composition from database setup and image downloads.

## Steps

1. Create `charts/lab-banner/Chart.yaml` with `apiVersion: v2`, name `lab-banner`,
   type `application`, and version `0.1.0`.
2. Add its `values.yaml` with `message: Hello from the child chart`.
3. Add `templates/configmap.yaml` with this body:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-banner
data:
  message: {{ .Values.message | quote }}
  environment: {{ .Values.global.environment | default "local" | quote }}
```

Also define `global: {}` in the child defaults so it renders independently.
4. Add this dependency to the **parent** `charts/nginx-demo/Chart.yaml`:

```yaml
dependencies:
  - name: lab-banner
    version: 0.1.0
    repository: file://../lab-banner
    condition: lab-banner.enabled
```

5. Add parent default values:

```yaml
lab-banner:
  enabled: true
  message: Hello from the parent
global:
  environment: local
```

6. Set `global.environment: dev` in `values-dev.yaml`. Build the dependency:

```bash
helm dependency update ./charts/nginx-demo
helm dependency list ./charts/nginx-demo
helm lint ./charts/lab-banner
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm template demo-dev ./charts/nginx-demo --set lab-banner.enabled=false
```

## Verify

Expect `charts/nginx-demo/Chart.lock` and a packaged child under its `charts/`
folder. Enabled rendering includes `demo-dev-banner` with the parent's message
and environment `dev`; disabled rendering omits it. The child reads
`.Values.message`, not `.Values.lab-banner.message`.

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
kubectl get configmap demo-dev-banner -n helm-lab -o yaml
helm list -n helm-lab
helm test demo-dev -n helm-lab --timeout 60s
```

The child belongs to the parent's release; it does not get a separate Helm
release. This companion is metadata for the exercise, not a new NGINX feature.

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
