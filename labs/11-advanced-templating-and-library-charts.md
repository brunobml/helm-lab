# Lab 11: Advanced templating and library charts

**Start:** Lab 10 complete (`lab-10-complete`). Use the `helm-lab` namespace.
**Goal:** Use `tpl`, `required`, `fail`, `default`, and `lookup` correctly, then move shared
helpers into a **library chart** that other charts can depend on.

Lab 4 and Lab 5 gave you conditionals, loops, and named templates. Real charts also
need values that contain templates, hard failures with useful messages, and helpers
shared between charts. This lab covers those, starting with a throwaway chart so
mistakes cost nothing.

## Part A: Template functions in a scratch chart

Work outside the repository so you do not disturb the lab chart.

### Step 1: Create the scratch chart

```bash
mkdir -p /tmp/tplplay/templates && cd /tmp/tplplay
```

`/tmp/tplplay/Chart.yaml`:

```yaml
apiVersion: v2
name: tplplay
version: 0.1.0
```

`/tmp/tplplay/values.yaml`:

```yaml
replicas: 2
debug: false
name: ""
greeting: "Hello from {{ .Release.Name }}"
```

`/tmp/tplplay/templates/play.yaml`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-play
data:
  defaultReplicas: {{ .Values.replicas | default 5 | quote }}
  defaultDebug: {{ .Values.debug | default true | quote }}
  hasKeyDebug: {{ hasKey .Values "debug" | quote }}
  ternaryDebug: {{ ternary "verbose" "quiet" .Values.debug | quote }}
  coalesced: {{ coalesce .Values.name .Values.missing "fallback" | quote }}
  plain: {{ .Values.greeting | quote }}
  templated: {{ tpl .Values.greeting . | quote }}
  required: {{ required "name is required" .Values.name | quote }}
```

### Step 2: Predict, then render

Before running anything, predict the value of each key when `replicas=0`, `debug=false`
and `name=x`. Then:

```bash
helm template p .                                                # fails on purpose
helm template p . --set name=x --set replicas=0 --set debug=false
```

*Expect:* the first command fails with `execution error ... name is required`. The second prints:

```text
  defaultReplicas: "5"        # you set 0!
  defaultDebug: "true"        # you set false!
  hasKeyDebug: "true"
  ternaryDebug: "quiet"
  coalesced: "x"
  plain: "Hello from {{ .Release.Name }}"
  templated: "Hello from p"
  required: "x"
```

Two things to take from this:

- **`default` treats `0`, `false`, `""`, and empty lists/maps as "not set".** A user who sets
  `replicas: 0` or `debug: false` is silently overridden. When `false`/`0` are valid, use
  `hasKey`, `ternary`, or `coalesce` deliberately, or simply define the default in `values.yaml`
  and drop `default` from the template.
- **`tpl` renders a string as a template.** Values are plain data, so `{{ ... }}` in `values.yaml`
  stays literal (`plain`) until a template calls `tpl` on it (`templated`). `tpl` needs a context;
  pass `.` (or `$` inside a `range`). Only evaluate `tpl` on trusted input: never pass untrusted
  end-user inputs to `tpl`, as template execution can invoke `lookup` to read cluster Secrets.

### Step 3: `lookup` keeps a generated value stable

`lookup` reads live objects from the cluster during rendering. A classic use is generating a
random value once and reusing it on every upgrade.

Replace `templates/play.yaml` with `templates/token.yaml` (delete the old file):

```bash
rm templates/play.yaml
```

```yaml
{{- $existing := lookup "v1" "Secret" .Release.Namespace (printf "%s-token" .Release.Name) }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ .Release.Name }}-token
type: Opaque
data:
  {{- if $existing }}
  token: {{ index $existing.data "token" }}
  {{- else }}
  token: {{ randAlphaNum 16 | b64enc }}
  {{- end }}
```

```bash
# No cluster access: lookup returns an empty map, so the token differs on every render
helm template p . | grep token:
helm template p . | grep token:

# With a cluster: generated once, then reused
helm install p . -n helm-lab
kubectl get secret p-token -n helm-lab -o jsonpath='{.data.token}'; echo
helm upgrade p . -n helm-lab
kubectl get secret p-token -n helm-lab -o jsonpath='{.data.token}'; echo
```

*Expect:* the two `helm template` tokens differ; the two `kubectl` tokens are identical.

> [!WARNING]
> `lookup` returns nothing under plain `helm template` and `--dry-run=client`. (Note: `helm template --dry-run=server` or `helm install/upgrade --dry-run=server` *does* query the cluster). GitOps tools that
> render with `helm template` (Argo CD, Flux's default) never see cluster state, so the token
> would be regenerated on every sync. For secrets under GitOps, use an external secret manager
> (see the Identity extension) instead.

Clean up: `helm uninstall p -n helm-lab && cd - && rm -rf /tmp/tplplay`

## Part B: `tpl` in the real chart

Now let users put template expressions in `pageContent`.

### Step 4: Edit `charts/nginx-demo/templates/configmap.yaml`

Change the last line:

```yaml
  index.html: |
    {{- tpl .Values.pageContent . | nindent 4 }}
```

### Step 5: Use it in `charts/nginx-demo/values-dev.yaml`

Replace `pageContent` with:

```yaml
pageContent: |
  <h1>Hello from {{ .Release.Name }} in {{ .Values.global.environment }}</h1>
```

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml \
  --show-only templates/configmap.yaml
```

*Expect:* `<h1>Hello from demo-dev in dev</h1>`. Existing values without `{{` render exactly as before.

## Part C: Build a library chart

A **library chart** (`type: library`) contains only named templates. It renders nothing by
itself and cannot be installed. Other charts depend on it and `include` its templates. Use one
when several charts share conventions (labels, ConfigMaps, security contexts).

### Step 6: Snapshot the current output

You are about to refactor. Prove afterward that nothing changed:

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml > /tmp/before-dev.yaml
```

### Step 7: Create `charts/lab-common`

`charts/lab-common/Chart.yaml`:

```yaml
apiVersion: v2
name: lab-common
description: Shared named templates for the Helm Lab charts
type: library
version: 0.1.0
```

`charts/lab-common/templates/_labels.tpl` (moves your standard labels here):

```yaml
{{/*
lab-common.labels: standard labels. Call with the root context:
  {{ include "lab-common.labels" . }}
*/}}
{{- define "lab-common.labels" -}}
app: {{ .Release.Name }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
```

`charts/lab-common/templates/_configmap.tpl` (a template that takes a **dict**, not the root context):

```yaml
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
```

Files starting with `_` are never rendered as manifests; they only hold `define` blocks.

### Step 8: Depend on it from `nginx-demo`

Append `lab-common` to `dependencies` in `charts/nginx-demo/Chart.yaml`:

```yaml
dependencies:
  - name: lab-banner
    version: 0.1.0
    repository: file://../lab-banner
    condition: lab-banner.enabled
  - name: lab-common
    version: 0.1.0
    repository: file://../lab-common
```

Bump the chart version to `0.4.0`, then resolve dependencies (this updates `Chart.lock` and
packages the library into `charts/nginx-demo/charts/`):

```bash
helm dependency update ./charts/nginx-demo
```

### Step 9: Delegate the labels

In `charts/nginx-demo/templates/_helpers.tpl`, replace the body of `nginx-demo.labels` (keep
`nginx-demo.selectorLabels` exactly as is; selectors are immutable):

```yaml
{{- define "nginx-demo.labels" -}}
{{- include "lab-common.labels" . -}}
{{- end -}}
```

Prove the refactor changed nothing:

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml | diff - /tmp/before-dev.yaml && echo "identical"
```

*Expect:* `identical`. A refactor that changes rendered output is a change, not a refactor.

### Step 10: Use the library to render extra ConfigMaps

Create `charts/nginx-demo/templates/extra-configmaps.yaml`:

```yaml
{{- range $name, $data := .Values.extraConfigMaps }}
---
{{ include "lab-common.configmap" (dict "root" $ "name" $name "data" $data) }}
{{- end }}
```

Note `$`: inside `range`, `.` is the current item, and `$` is still the root context the library needs.

Add to `charts/nginx-demo/values.yaml`:

```yaml
# Extra ConfigMaps rendered by the lab-common library. Map of name -> map of key/value.
# Values may contain template expressions, for example "{{ .Release.Name }}".
extraConfigMaps: {}
```

Add to `charts/nginx-demo/values-dev.yaml`:

```yaml
extraConfigMaps:
  settings:
    ENVIRONMENT: "{{ .Values.global.environment }}"
    RELEASE: "{{ .Release.Name }}"
    MAX_CONN: 100
  feature-flags:
    beta: "false"
```

Add to the top-level `properties` in `charts/nginx-demo/values.schema.json`. Notice the comma `,` added after `"migration": { ... }`:

```json
    "migration": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" },
        "image": { "type": "string", "minLength": 1 },
        "fail": { "type": "boolean" }
      }
    },
    "extraConfigMaps": {
      "type": "object",
      "additionalProperties": {
        "type": "object",
        "minProperties": 1
      }
    }
```

### Step 11: Render and deploy

```bash
helm lint ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml \
  --show-only templates/extra-configmaps.yaml

helm install demo-tpl ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
kubectl get configmap -n helm-lab | grep demo-tpl
kubectl get configmap demo-tpl-settings -n helm-lab -o jsonpath='{.data}{"\n"}'
kubectl exec deploy/demo-tpl-deployment -n helm-lab -- cat /usr/share/nginx/html/index.html
```

*Expect:* ConfigMaps `demo-tpl-page`, `demo-tpl-banner`, `demo-tpl-settings`, `demo-tpl-feature-flags`;
settings data `{"ENVIRONMENT":"dev","MAX_CONN":"100","RELEASE":"demo-tpl"}` (the number became a
string because ConfigMap data must be strings); and `<h1>Hello from demo-tpl in dev</h1>`.

## Verify

Local:

```bash
helm dependency build ./charts/nginx-demo
helm lint ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml | grep -c "kind: ConfigMap"   # 4 (page, banner, settings, feature-flags)
helm install x ./charts/lab-common --dry-run 2>&1 | tail -1     # library charts are not installable
```

Cluster:

```bash
helm test demo-tpl -n helm-lab --timeout 60s
```

## Break it and recover

Do each in a scratch values file (for example `/tmp/bad.yaml`) passed with `-f`; do not edit
`values-dev.yaml`.

1. **A `tpl` expression on a missing key.**

   ```yaml
   extraConfigMaps:
     settings:
       OWNER: "{{ .Values.team.name }}"
   ```

   *Expect:* `error calling tpl ... nil pointer evaluating interface {}.name`. This is **not** a
   `required` failure. `team` does not exist, so `.name` on it crashes. Fix it by defining `team`
   in `values.yaml`, or guard the access: `{{ .Values.team | default dict | dig "name" "unassigned" }}`.

2. **An empty ConfigMap.** The schema stops it first:

   ```bash
   helm template d ./charts/nginx-demo --set-json 'extraConfigMaps={"empty":{}}'
   ```

   *Expect:* `minProperties: got 0, want 1`. Now bypass the schema and reach the library's own guard:

   ```bash
   helm template d ./charts/nginx-demo --set-json 'extraConfigMaps={"empty":{}}' --skip-schema-validation
   ```

   *Expect:* `lab-common.configmap: "empty" needs at least one key under 'data'`. Try changing the
   library's `fail` check to `required` in `charts/lab-common/templates/_configmap.tpl`. Because parent
   charts render from the packaged `.tgz` archive, rebuild dependencies first:
   `helm dependency update ./charts/nginx-demo --skip-refresh`. Then re-run the `--skip-schema-validation`
   command above to see what renders (an invalid ConfigMap with an empty `data:`, because `required`
   only rejects `nil` and `""`). Then restore `fail` in `_configmap.tpl` and run
   `helm dependency update ./charts/nginx-demo --skip-refresh` again.
3. **A wrong type.** `--set extraConfigMaps.settings=1` fails schema validation
   (`got number, want object`).

## Explain

- Why did `defaultReplicas` become `5` when you set `replicas: 0`, and what would you use instead?
- Why must the library's `lab-common.configmap` receive a `dict` with `root`, and what would break if it took `.`?
- Why did the label refactor need to leave `nginx-demo.selectorLabels` alone?
- Where should `lookup` not be used, and why?

> [!TIP]
> See [11-advanced-templating-and-library-charts-explained.md](11-advanced-templating-and-library-charts-explained.md) for detailed explanations.

## Cleanup and checkpoint

```bash
helm uninstall demo-tpl -n helm-lab
rm -f /tmp/before-dev.yaml /tmp/bad.yaml
```

Keep `demo-dev`. Commit your work (`charts/nginx-demo/charts/*.tgz` stays ignored, but keep
`Chart.lock`), tick Lab 11 in the README, and create `lab-11-complete`.

References: [Named templates and library charts](https://helm.sh/docs/topics/library_charts/),
[Template functions](https://helm.sh/docs/chart_template_guide/function_list/),
[`tpl` and `required`](https://helm.sh/docs/howto/charts_tips_and_tricks/).

## Your notes

Record versions, observations, failures, and explanations here.
