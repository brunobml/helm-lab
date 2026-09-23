# Lab 5: Helpers and labels — Explained

[Back to Lab 5: Helpers and labels](05-helpers-and-labels.md)

---

## Overview

In Lab 5, you extracted reusable named templates into `_helpers.tpl`, implemented standard Kubernetes labels (`app.kubernetes.io/*`), and learned the critical architectural distinction between metadata labels and immutable selector labels.

Below are in-depth explanations and answers for the questions posed in the **Check your understanding** section.

---

### Question 1: What is the difference between `define` and `include`?

#### TL;DR

- **`define`** declares and saves a named template into the template engine's global symbol table. It produces no direct output where it is declared.
- **`include`** executes a named template and returns its rendered text output as a string, allowing you to pass the result into pipeline functions like `nindent` or `trimSuffix`.

#### Deep Dive & Mechanism

1. **Named Template Declaration (`define`):**

   ```gotemplate
   {{- define "nginx-demo.labels" -}}
   app: {{ .Release.Name }}
   app.kubernetes.io/name: nginx-demo
   ...
   {{- end -}}
   ```

   - Templates defined with `{{- define "name" -}}` are loaded into a flat, global symbol table shared across the root chart and all subcharts.
   - **Why prefix helper names with `nginx-demo`:** Because the symbol table is global, if two charts both declare `{{- define "labels" -}}`, one will silently overwrite the other. Prefixing helper names with `<chart-name>.` (e.g. `nginx-demo.labels`, `nginx-demo.selectorLabels`) guarantees unique names across dependencies.

2. **Executing Named Templates (`include` vs `template`):**
   - Go's built-in `{{ template "name" . }}` is an action that writes output directly to the output stream. Crucially, **`template` cannot be pipelined** in Go templates.
   - Helm provides `include` as a custom template function: `{{ include "name" . }}`.
   - Because `include` is a function returning a string, its output can be piped into other functions:

     ```gotemplate
     labels:
       {{- include "nginx-demo.labels" . | nindent 8 }}
     ```

   - This allows programmatic indentation (`nindent`), quote manipulation, or trimming.

---

### Question 2: Why do the Pods get five labels while the selectors use only one?

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
     Contains only the single label needed to route Service traffic and link Deployment Pods:

     ```yaml
     app: {{ .Release.Name }}
     ```

     This never changes over the entire lifetime of the release.
   - **`labels` (Informational Metadata):**
     Includes `selectorLabels` plus dynamic metadata (5 labels in total):

     ```yaml
     app: {{ .Release.Name }}
     app.kubernetes.io/name: nginx-demo
     app.kubernetes.io/instance: {{ .Release.Name }}
     app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
     app.kubernetes.io/managed-by: {{ .Release.Service }}
     ```

     These are placed on `metadata.labels` of the Deployment, Service, and Pod-template, where Kubernetes allows updates during rollouts without selector rejection.

---

### Question 3: What does `nindent 8` do?

#### TL;DR

`nindent 8` writes a newline character (`\n`) and then indents every line of the piped string by exactly **8 spaces**.

#### Deep Dive & Mechanism

- `indent N` adds $N$ spaces to every line, but leaves the very first line unindented unless preceded by a newline.
- `nindent N` inserts a newline **first**, then indents every single line of the input text by $N$ spaces.
- When paired with `{{-` (which strips all preceding whitespace and newlines from the template tag), `{{- include "..." . | nindent 8 }}` ensures:
  1. The YAML key (e.g. `labels:`) remains cleanly on its own line.
  2. The injected block starts immediately on the next line indented by exactly 8 spaces.
  3. No empty blank lines or indentation misalignments are generated.

---

### Question 4: Why do we keep the same resource names during this change?

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

> Temporarily add the version line to `nginx-demo.selectorLabels` and render. Compare with the live Deployment's selector. Observe that Kubernetes rejects changes to immutable selectors with `field is immutable` during a server-side dry run. Restore the original selector before continuing.

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
