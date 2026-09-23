# Lab 4: Template logic

**Start:** Lab 3 complete (`lab-03-complete`).
**Goal:** Render optional settings without malformed YAML or unintended types.

## Steps

### Step 1: Add default empty blocks in `charts/nginx-demo/values.yaml`

Open `charts/nginx-demo/values.yaml` and add `extraEnv: {}` and `resources: {}` to the bottom of the file:

```yaml
extraEnv: {}

resources: {}
```

Declaring empty defaults establishes the chart's schema and ensures templates do not error when optional values are omitted.

### Step 2: Add template logic to `charts/nginx-demo/templates/deployment.yaml`

Open `charts/nginx-demo/templates/deployment.yaml`. Inside the container definition under `spec.template.spec.containers[0]`, add the `extraEnv` and `resources` logic directly below the `ports:` block:

```yaml
          ports:
            # Declares the image's default port; it does not configure the server.
            - containerPort: 80
          {{- with .Values.extraEnv }}
          env:
            {{- range $name, $value := . }}
            - name: {{ $name | quote }}
              value: {{ $value | quote }}
            {{- end }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

**How this works:**

- `{{- with .Values.extraEnv }}`: Only renders the `env:` block if `extraEnv` is non-empty. Inside this block, `.` changes from root context to `.Values.extraEnv`.
- `{{- range $name, $value := . }}`: Iterates over the key-value map.
- `{{ $value | quote }}`: Enforces string values (`"false"`, `"dev"`) required by the Kubernetes `v1.EnvVar` specification.
- `{{- toYaml . | nindent 12 }}`: Dumps the `resources` map as YAML, indented by 12 spaces to match container specifications.

### Step 3: Configure dev values in `charts/nginx-demo/values-dev.yaml`

Open `charts/nginx-demo/values-dev.yaml` and append the `extraEnv` and `resources` definitions, keeping `replicaCount: 1`:

```yaml
extraEnv:
  LAB_NAME: dev
  FEATURE_ENABLED: "false"

resources:
  requests:
    cpu: 50m
    memory: 32Mi
  limits:
    memory: 128Mi
```

## Verify

1. **Lint chart syntax:**

   ```bash
   helm lint ./charts/nginx-demo
   ```

2. **Verify defaults omit `env` and `resources`:**

   ```bash
   helm template demo-dev ./charts/nginx-demo
   ```

   *Expect:* Manifest contains `ports:`, but neither `env:` nor `resources:`.

3. **Verify dev values render `env` and `resources`:**

   ```bash
   helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
   ```

   *Expect:* Container section includes `env:` with `LAB_NAME="dev"` and `FEATURE_ENABLED="false"`, and `resources:` with CPU and memory limits/requests.

4. **Apply changes to cluster and inspect runtime Pod:**

   ```bash
   helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
   kubectl exec -n helm-lab deployment/demo-dev-deployment -- printenv LAB_NAME FEATURE_ENABLED
   ```

   *Expect output:*

   ```text
   dev
   false
   ```

## Break it and recover

Inside `range`, try accessing `.Release.Name`. Observe the rendering error, then
use `$.Release.Name` to access the original root context. Restore the intended
output. Also try a wrong indentation level (such as `nindent 8` on `resources`)
and observe the YAML parse error with `helm template --debug`.

## Explain

- What does `.` mean inside `with` and `range`?
- Why must an environment variable value be rendered as a string?
- What does the leading dash in `{{-` remove?

> [!TIP]
> See [04-template-logic-explained.md](04-template-logic-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Keep the successful dev configuration and release. Commit and create
`lab-04-complete`.

<details>
<summary>Reference: complete containers block in `templates/deployment.yaml`</summary>

```yaml
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            # Declares the image's default port; it does not configure the server.
            - containerPort: 80
          {{- with .Values.extraEnv }}
          env:
            {{- range $name, $value := . }}
            - name: {{ $name | quote }}
              value: {{ $value | quote }}
            {{- end }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

</details>

Next: [Helpers and labels](05-helpers-and-labels.md).
