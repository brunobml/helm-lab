{{/*
Selector labels
*/}}
{{- define "nginx-demo.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end -}}

{{/*
Common labels (shared with other lab charts through the lab-common library)
*/}}
{{- define "nginx-demo.labels" -}}
{{ include "nginx-demo.selectorLabels" . }}
{{ include "lab-common.labels" . }}
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

{{/*
Secret name used for envFrom: an existing Secret, or the one this chart creates.
*/}}
{{- define "nginx-demo.envSecretName" -}}
{{- if and .Values.existingSecret .Values.secret.create -}}
  {{- fail "set either existingSecret or secret.create, not both" -}}
{{- else if .Values.existingSecret -}}
  {{- .Values.existingSecret -}}
{{- else if .Values.secret.create -}}
  {{- printf "%s-secret" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Auxiliary and hook resource labels (excludes the Service selector label 'app: <release>')
*/}}
{{- define "nginx-demo.hookLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: migration
{{- end -}}

