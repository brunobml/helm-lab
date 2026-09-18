{{- define "shop-db.name" -}}
{{- printf "%s-db" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels. Deliberately NOT "app: <release>": the web chart's Service selects on that. */}}
{{- define "shop-db.selectorLabels" -}}
app.kubernetes.io/name: shop-db
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: db
{{- end -}}

{{- define "shop-db.labels" -}}
{{ include "shop-db.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* The Secret is created by the umbrella chart; see the shop chart's credentials-secret.yaml. */}}
{{- define "shop-db.credentialsSecret" -}}
{{- printf "%s-credentials" .Release.Name -}}
{{- end -}}
