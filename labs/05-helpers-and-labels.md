# Lab 5: Helpers and labels

**Start:** Lab 4 complete (`lab-04-complete`).
**Goal:** Extract reusable helpers while preserving the installed release's identity.

## Steps

1. Create `charts/nginx-demo/templates/_helpers.tpl`.
2. Define namespaced helpers `nginx-demo.selectorLabels` and `nginx-demo.labels`.
3. Keep the selector helper's output exactly `app: <release name>`. Use it in
   Deployment `matchLabels`, Pod labels, and the Service selector.
4. Have the common-label helper include selector labels plus
   `app.kubernetes.io/name`, `app.kubernetes.io/instance`,
   `app.kubernetes.io/version`, and `app.kubernetes.io/managed-by`. Apply common
   labels to Deployment, Service, and Pod metadata, not to selectors.
5. Add `nginx-demo.deploymentName` and `nginx-demo.serviceName` helpers that
   preserve `<release>-deployment` and `<release>-service`. Practice `printf`,
   `trunc 63`, and `trimSuffix "-"`. Replace direct name construction with `include`.

## Verify

```bash
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
kubectl get deployment demo-dev-deployment -n helm-lab -o jsonpath='{.spec.selector.matchLabels}'
kubectl get pods -n helm-lab --show-labels
kubectl get endpointslices -n helm-lab -l kubernetes.io/service-name=demo-dev-service
```

Expect the selector to remain `app: demo-dev`, extra metadata labels on Pods,
and a Service endpoint for the ready Pod. Repeat Lab 1's port-forward and curl.

## Break it and recover

Temporarily put the version label in the selector helper and render. Compare
with the installed Deployment's selector; do not apply it. Deployment selectors
are immutable, and changing versions should not change which Pods are selected.
Remove the version from selectors before continuing.

## Explain

- Why are metadata labels and selector labels separate helpers?
- Why prefix helper names with `nginx-demo`?
- Why could renaming resources turn a refactor into resource replacement?

## Cleanup and checkpoint

Stop port-forwarding. Keep resource names and selectors compatible with earlier
labs. Commit and create `lab-05-complete`.

<details>
<summary>Hint: _helpers.tpl definitions</summary>

```gotemplate
{{/*
Selector labels
*/}}
{{- define "nginx-demo.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end -}}

{{/*
Common labels
*/}}
{{- define "nginx-demo.labels" -}}
{{ include "nginx-demo.selectorLabels" . }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/*
Resource names
*/}}
{{- define "nginx-demo.deploymentName" -}}
{{- printf "%s-deployment" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nginx-demo.serviceName" -}}
{{- printf "%s-service" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

Under `matchLabels`, use `{{- include "nginx-demo.selectorLabels" . | nindent 6 }}`.
Under `metadata.labels`, use `{{- include "nginx-demo.labels" . | nindent 4 }}` (or `8` for Pod template).
Indentation depends on the insertion point. For a new chart you may choose
standard name/instance selectors from the start; this exercise preserves an
already-installed selector deliberately.

</details>

Reference: [Pod templates and selectors](https://helm.sh/docs/v3/chart_best_practices/pods/).

Next: [ConfigMaps and rollouts](06-configmaps-and-rollouts.md).
