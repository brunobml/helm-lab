{{- define "shop.credentialsSecret" -}}
{{- printf "%s-credentials" .Release.Name -}}
{{- end -}}

{{/* Labels for resources owned by the umbrella. Not used as selectors. */}}
{{- define "shop.labels" -}}
app.kubernetes.io/name: shop
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: platform
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
