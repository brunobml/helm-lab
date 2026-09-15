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
