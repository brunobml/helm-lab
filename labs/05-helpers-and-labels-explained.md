# Lab 5: Helpers and labels — Explained

[Back to Lab 5: Helpers and labels](05-helpers-and-labels.md)

---

## Overview

In Lab 5, you extracted reusable named templates into `_helpers.tpl`, implemented standard Kubernetes labels (`app.kubernetes.io/*`), and learned the critical architectural distinction between metadata labels and immutable selector labels.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: Why are metadata labels and selector labels separate helpers?

#### TL;DR

Because **Deployment `spec.selector.matchLabels` is immutable in Kubernetes**, whereas metadata labels change frequently (e.g., chart version, image version, managed-by). Combining them breaks future upgrades.

#### Deep Dive & Mechanism

1. **The Immutability Rule:**
   - Kubernetes strictly forbids changing `spec.selector` on an existing Deployment:

     ```text
     The Deployment "demo-dev-deployment" is invalid: spec.selector: Invalid value: ... field is immutable
     ```

   - If you include `app.kubernetes.io/version: "1.30.4"` inside `selectorLabels`:
     - Revision 1 deploys with selector `app.kubernetes.io/version: 1.30.4`.
     - In Revision 2, you bump the chart or application version to `1.30.5`.
     - When you run `helm upgrade`, Kubernetes rejects the manifest because the selector cannot be mutated!
2. **The Separation of Concerns:**
   - **`selectorLabels` (Minimal & Immutable):**
     Contains only the absolute minimum labels needed to uniquely identify the workload:

     ```yaml
     app.kubernetes.io/name: nginx-demo
     app.kubernetes.io/instance: demo-dev
     # (or in our lab: app: demo-dev)
     ```

     These never change over the entire lifetime of the release.
   - **`labels` (Informational Metadata):**
     Includes `selectorLabels` plus dynamic metadata:

     ```yaml
     app.kubernetes.io/version: "1.30.4"   # Changes with new versions
     app.kubernetes.io/managed-by: Helm    # Identifies deployment tool
     helm.sh/chart: nginx-demo-0.1.0       # Tracks specific chart packaging
     ```

     These are placed on `metadata.labels` of the Deployment, Service, and Pods, where Kubernetes allows updates during rollouts.

---

### Question 2: Why prefix helper names with `nginx-demo`?

#### TL;DR

Named templates defined in `_helpers.tpl` share a single **global namespace** across the parent chart and all subcharts. Prefixing helper names with the chart name (`nginx-demo.labels`) prevents naming collisions.

#### Deep Dive & Mechanism

- In Helm, any template defined with `{{- define "helperName" -}}` is loaded into a flat, global symbol table.
- If your chart defines:

  ```gotemplate
  {{- define "labels" -}} ... {{- end -}}
  ```

  And later in **Lab 8** you add a subchart (e.g., `lab-banner`, or Redis/PostgreSQL) that also defines `{{- define "labels" -}}`:
  - One template will silently overwrite the other!
  - Your parent chart might suddenly render labels meant for Redis, or vice-versa.
- **The Helm Convention:**
  Always namespace helper templates using `<chart-name>.<helperFunction>`:
  - `nginx-demo.labels`
  - `nginx-demo.selectorLabels`
  - `nginx-demo.deploymentName`
  - `nginx-demo.serviceName`

---

### Question 3: Why could renaming resources turn a refactor into resource replacement?

#### TL;DR

Kubernetes resources are identified by their **`metadata.name`**. If you change a template's naming logic, Helm does not "rename" the existing resource—it creates a **new resource** and deletes the old one, causing downtime or state loss.

#### Deep Dive & Mechanism

1. **How Helm Tracks Resources:**
   - Helm tracks resources by their GVK (Group/Version/Kind), namespace, and name.
   - If in Lab 5 you changed:
     `name: demo-dev-deployment`
     to:
     `name: demo-dev-nginx`
   - During `helm upgrade`, Helm detects:
     1. A new object `Deployment/demo-dev-nginx` must be created.
     2. The old object `Deployment/demo-dev-deployment` is no longer in the rendered manifests, so Helm **deletes** it.
2. **Production Consequences:**
   - **Services:** Deleting and recreating a Service changes its ClusterIP, breaking internal DNS and client connections until DNS caches expire.
   - **Persistent Volumes (PVCs):** If a PVC is renamed, a new empty volume is created; your existing data is abandoned or deleted.
   - **Workloads:** Pods are abruptly terminated and rescheduled under the new Deployment name.
3. **Safety Practice:**
   When refactoring templates to use helpers (like `printf "%s-deployment"`), verify that the rendered output exactly matches the previously installed resource names before executing `helm upgrade`.

---

## Break It and Recover — Detailed Walkthrough

### What the challenge asks
>
> Temporarily put the version label in the selector helper and render. Compare with the installed Deployment's selector; do not apply it. Deployment selectors are immutable, and changing versions should not change which Pods are selected. Remove the version from selectors before continuing.

#### 1. What to Break

In `charts/nginx-demo/templates/_helpers.tpl`, temporarily add the application version to the selector helper:

```gotemplate
{{- define "nginx-demo.selectorLabels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
```

#### 2. Render and Compare

Render the updated templates:

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
```

Notice the rendered Deployment selector:

```yaml
spec:
  selector:
    matchLabels:
      app: demo-dev
      app.kubernetes.io/version: "1.30.4"
```

Now inspect the selector currently running on the live Kubernetes cluster:

```bash
kubectl get deployment demo-dev-deployment -n helm-lab -o jsonpath='{.spec.selector.matchLabels}'
```

*Live cluster output:*

```json
{"app":"demo-dev"}
```

#### 3. What Would Happen If Applied (The Immutability Violation)

If you attempted to run `helm upgrade demo-dev ...`, the Kubernetes API server would reject the request with an unrecoverable error:

```text
Error: UPGRADE FAILED: cannot patch "demo-dev-deployment" with kind Deployment:
Deployment.apps "demo-dev-deployment" is invalid: spec.selector: Invalid value:
map[string]string{"app":"demo-dev", "app.kubernetes.io/version":"1.30.4"}: field is immutable
```

#### 4. Why This Failed

- Kubernetes controllers (`Deployment`, `StatefulSet`, `DaemonSet`) require immutable selectors (`spec.selector.matchLabels`). Once created, Kubernetes will never allow you to add, remove, or modify selector keys.
- If selectors were mutable and changed with every version bump, the Deployment controller would instantly orphan its existing Pods during an upgrade, losing track of what is running and failing to perform a zero-downtime rolling update.

#### 5. How to Recover

Remove `app.kubernetes.io/version` from `nginx-demo.selectorLabels` in `charts/nginx-demo/templates/_helpers.tpl`, keeping it strictly inside `nginx-demo.labels`:

```gotemplate
{{- define "nginx-demo.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end }}
```

Verify that the selector matches the cluster state:

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml | grep -A 3 "matchLabels:"
```

*Output:*

```yaml
    matchLabels:
      app: demo-dev
```

---

## Key Takeaways

| Principle | Implementation |
| :--- | :--- |
| Selector Immutability | Never put version numbers or volatile values in `spec.selector.matchLabels`. |
| Helper Namespacing | Always prefix helper names with `chartName.` to avoid collisions in subcharts. |
| Resource Identity | In Kubernetes, renaming a resource means deleting and recreating it. |
