# Extension: Identity and secrets

**Start:** Lab 7 or later.
**Goal:** Configure application identity independently from permissions and secret data.

## Steps

1. Add `serviceAccount.create` and `serviceAccount.name` values, a conditional
   ServiceAccount template, and a name helper wired to `serviceAccountName`.
2. Support an existing ServiceAccount when creation is disabled.
3. In a separate practice step, add `rbac.create` to gate a namespaced Role and
   RoleBinding granting only `get` on the application's page ConfigMap. NGINX
   does not need API permissions to serve its mounted file; this is an RBAC exercise.
4. Add an optional `existingSecret` value and reference it from `envFrom` when set.
   Create a disposable Secret using fake data:

```bash
kubectl create secret generic demo-learning -n helm-lab --from-literal=LAB_TOKEN=fake-training-value
```

Do not commit real secrets. Base64 in a Kubernetes Secret is encoding, not encryption.

## Verify

Render all create/false combinations and inspect the ServiceAccount reference.
Deploy the fake Secret reference, then use `kubectl exec` and `printenv LAB_TOKEN`
to verify injection. If your cluster identity permits impersonation, run
`kubectl auth can-i get configmap/demo-dev-page` with
`--as=system:serviceaccount:helm-lab:<your-service-account>` and `-n helm-lab`;
expect yes only with the exercise's binding. Test a different ConfigMap; expect no.

## Break it and recover

Reference a nonexistent Secret, observe the Pod configuration error with
`kubectl describe pod`, then restore the existing Secret name and upgrade.

## Explain

Why are `serviceAccount.create` and `rbac.create` independent? When would a
namespaced Role be more appropriate than a ClusterRole?

## Cleanup and checkpoint

Remove the Secret reference via upgrade before deleting `demo-learning`. Disable
the exercise's RBAC if no longer needed. Save `extension-identity-complete`.

<details>
<summary>Hint: helper in templates/_helpers.tpl</summary>

```gotemplate
{{/*
Service account name
*/}}
{{- define "nginx-demo.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
    {{- default (printf "%s-sa" .Release.Name) .Values.serviceAccount.name -}}
{{- else -}}
    {{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}
```

</details>

<details>
<summary>Hint: templates/serviceaccount.yaml</summary>

```yaml
{{- if .Values.serviceAccount.create -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "nginx-demo.serviceAccountName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
  {{- with .Values.serviceAccount.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
```

</details>

<details>
<summary>Hint: templates/rbac.yaml</summary>

```yaml
{{- if .Values.rbac.create -}}
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: {{ include "nginx-demo.deploymentName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
rules:
  - apiGroups: [""]
    resources: ["configmaps"]
    resourceNames: [{{ printf "%s-page" .Release.Name | quote }}]
    verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: {{ include "nginx-demo.deploymentName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: {{ include "nginx-demo.deploymentName" . }}
subjects:
  - kind: ServiceAccount
    name: {{ include "nginx-demo.serviceAccountName" . }}
    namespace: {{ .Release.Namespace }}
{{- end }}
```

</details>

Reference: [Helm RBAC guidance](https://helm.sh/docs/v3/chart_best_practices/rbac/).
