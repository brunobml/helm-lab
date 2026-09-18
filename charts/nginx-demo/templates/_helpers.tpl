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