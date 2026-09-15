# Lab 4: Template logic

**Start:** Lab 3 complete (`lab-03-complete`).
**Goal:** Render optional settings without malformed YAML or unintended types.

## Steps

1. Add `extraEnv: {}` and `resources: {}` to the default values.
2. In the container, use `with` to omit empty `extraEnv`, and `range` to render
   each map entry as an environment variable. Quote the rendered value.
3. Render nonempty `resources` with `toYaml` and `nindent`.
4. Add this to `values-dev.yaml`, preserving its replica setting:

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

```bash
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
kubectl exec -n helm-lab deployment/demo-dev-deployment -- printenv LAB_NAME FEATURE_ENABLED
```

Defaults should omit the optional sections; dev output should contain valid
container `env` and `resources` fields. `printenv` should print `dev` and `false`.
These demonstration variables do not change NGINX behavior.

## Break it and recover

Inside `range`, try accessing `.Release.Name`. Observe the rendering error, then
use `$.Release.Name` to access the original root context. Restore the intended
output. Also try a wrong indentation level and inspect where `env` lands.

## Explain

- What does `.` mean inside `with` and `range`?
- Why must an environment variable value be rendered as a string?
- What does the leading dash in `{{-` remove?

## Cleanup and checkpoint

Keep the successful dev configuration and release. Commit and create
`lab-04-complete`.

<details>
<summary>Hint: environment variables inside the container</summary>

```yaml
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
