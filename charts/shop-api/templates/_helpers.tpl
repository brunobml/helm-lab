{{- define "shop-api.name" -}}
{{- printf "%s-api" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels. Deliberately NOT "app: <release>": the web chart's Service selects on that. */}}
{{- define "shop-api.selectorLabels" -}}
app.kubernetes.io/name: shop-api
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end -}}

{{- define "shop-api.labels" -}}
{{ include "shop-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* The Secret is created by the umbrella chart; see the shop chart's credentials-secret.yaml. */}}
{{- define "shop-api.credentialsSecret" -}}
{{- printf "%s-credentials" .Release.Name -}}
{{- end -}}
