{{/*
lab-common.configmap: render a ConfigMap. Call with a dict, not the root context:
  {{ include "lab-common.configmap" (dict "root" $ "name" "settings" "data" $data) }}
  root: the root context (for .Release and tpl)
  name: suffix; the ConfigMap is named <release>-<name>
  data: map of key -> string; values are passed through tpl
*/}}
{{- define "lab-common.configmap" -}}
{{- $root := required "lab-common.configmap: 'root' is required" .root -}}
{{- $name := required "lab-common.configmap: 'name' is required" .name -}}
{{- $data := .data | default dict -}}
{{- if not $data -}}
  {{- fail (printf "lab-common.configmap: %q needs at least one key under 'data'" $name) -}}
{{- end -}}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ printf "%s-%s" $root.Release.Name $name | trunc 63 | trimSuffix "-" }}
  labels:
    {{- include "lab-common.labels" $root | nindent 4 }}
data:
  {{- range $key, $value := $data }}
  {{ $key }}: {{ tpl (toString $value) $root | quote }}
  {{- end }}
{{- end -}}
