# Lab 5: Helpers and labels

**Start:** Lab 4 complete (`lab-04-complete`).
**Goal:** Extract reusable helpers while preserving the installed release's identity.

## Steps

### Step 1: Create `charts/nginx-demo/templates/_helpers.tpl`

Create a new file at `charts/nginx-demo/templates/_helpers.tpl`. Files prefixed with an underscore (`_`) do not generate Kubernetes manifests; they serve as shared template libraries.

Add the following helper template definitions:

```gotemplate
{{/*
Selector labels (immutable workload identifier)
*/}}
{{- define "nginx-demo.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end -}}

{{/*
Common metadata labels (selector labels + standard Kubernetes labels)
*/}}
{{- define "nginx-demo.labels" -}}
{{ include "nginx-demo.selectorLabels" . }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Resource names (RFC 1123 compliant: max 63 characters, no trailing dash)
*/}}
{{- define "nginx-demo.deploymentName" -}}
{{- printf "%s-deployment" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nginx-demo.serviceName" -}}
{{- printf "%s-service" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

**Key rules to understand:**
- **`include` vs `template`:** Always invoke helpers with `include "..." .` rather than `template`. Unlike `template`, `include` allows you to pipe the rendered output into formatting functions like `| nindent 4`.
- **Passing the dot `.` scope:** In `{{ include "nginx-demo.labels" . }}`, the dot `.` passes the execution context so the helper can access `.Release`, `.Chart`, and `.Values`.
- **`trunc 63 | trimSuffix "-"`:** Kubernetes names and label values are limited to 63 characters (RFC 1123). Truncating at 63 characters might cut off right after a dash (e.g. `my-long-release-name-`), which is invalid syntax. `trimSuffix "-"` removes any trailing dash.

---

### Step 2: Update `charts/nginx-demo/templates/deployment.yaml`

Open `charts/nginx-demo/templates/deployment.yaml` and refactor it to use the helper templates:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "nginx-demo.deploymentName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "nginx-demo.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "nginx-demo.labels" . | nindent 8 }}
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            # Declares the image's default port; it does not configure the server.
            - containerPort: 80
          {{- with .Values.extraEnv }}
          env:
            {{- range $name, $value := . }}
            - name: {{ $name | quote }}
              value: {{ $value | quote }}
            {{- end }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

**Notice the indentation offsets:**
- `metadata.labels`: indented with `nindent 4` (2 spaces for `metadata:` + 2 spaces for labels).
- `spec.selector.matchLabels`: indented with `nindent 6` (4 spaces for `matchLabels:` + 2 spaces for labels).
- `spec.template.metadata.labels`: indented with `nindent 8` (6 spaces for `metadata.labels:` + 2 spaces for labels).

> [!IMPORTANT]
> - `spec.selector.matchLabels` uses `nginx-demo.selectorLabels` (`app: demo-dev`). In Kubernetes, Deployment selectors are **immutable** and must never include version numbers.
> - `metadata.labels` and `template.metadata.labels` use `nginx-demo.labels`, which includes the full set of metadata labels.

---

### Step 3: Update `charts/nginx-demo/templates/service.yaml`

Open `charts/nginx-demo/templates/service.yaml` and update the service name, metadata labels, and selector:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "nginx-demo.serviceName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
  selector:
    {{- include "nginx-demo.selectorLabels" . | nindent 4 }}
```

**Key details:**
- `metadata.name`: uses `include "nginx-demo.serviceName" .` (preserves `demo-dev-service`).
- `metadata.labels`: uses `nginx-demo.labels` with `nindent 4`.
- `spec.selector`: uses **`nginx-demo.selectorLabels`** with `nindent 4` to match the Pod's immutable selector label (`app: demo-dev`).

---

## Verify

1. **Lint chart syntax:**
   ```bash
   helm lint ./charts/nginx-demo
   ```
   *Expect:* `1 chart(s) linted, 0 chart(s) failed`.

2. **Render and inspect template output:**
   ```bash
   helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
   ```
   *Verify that:*
   - Resource names remain `demo-dev-deployment` and `demo-dev-service`.
   - `selector.matchLabels` on Deployment is strictly `app: demo-dev`.
   - `metadata.labels` on Deployment, Service, and Pod contains all 5 standard labels (`app: demo-dev`, `app.kubernetes.io/name`, `instance`, `version`, `managed-by`).

3. **Deploy changes to the cluster:**
   ```bash
   helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
   ```
   *Verify:* The upgrade succeeds in-place without deleting or recreating the Deployment.

4. **Inspect live cluster resources:**
   ```bash
   # Confirm Deployment selector remains unchanged
   kubectl get deployment demo-dev-deployment -n helm-lab -o jsonpath='{.spec.selector.matchLabels}'

   # Confirm Pods carry the new metadata labels
   kubectl get pods -n helm-lab --show-labels

   # Confirm Service has active ready endpoints
   kubectl get endpointslices -n helm-lab -l kubernetes.io/service-name=demo-dev-service
   ```
   *Expect:*
   - Selector output is `{"app":"demo-dev"}`.
   - Pods show labels `app=demo-dev`, `app.kubernetes.io/name=nginx-demo`, `app.kubernetes.io/version=1.30.4`, etc.
   - EndpointSlice shows ready IP endpoint for the running Pod.

## Break it and recover

Temporarily put the version label in the selector helper and render. Compare
with the installed Deployment's selector; do not apply it. Deployment selectors
are immutable, and changing versions should not change which Pods are selected.
Remove the version from selectors before continuing.

## Explain

- Why are metadata labels and selector labels separate helpers?
- Why prefix helper names with `nginx-demo`?
- Why could renaming resources turn a refactor into resource replacement?

> [!TIP]
> See [05-helpers-and-labels-explained.md](05-helpers-and-labels-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Stop port-forwarding. Keep resource names and selectors compatible with earlier
labs. Commit and create `lab-05-complete`.

Reference: [Pod templates and selectors](https://helm.sh/docs/v3/chart_best_practices/pods/).

Next: [ConfigMaps and rollouts](06-configmaps-and-rollouts.md).
