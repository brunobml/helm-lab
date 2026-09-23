# Lab 7: Validation and tests

**Start:** Lab 6 complete (`lab-06-complete`), serving custom HTML.
**Goal:** Catch invalid input before deployment and check application behavior afterward.

## Steps

### Step 1: Create `charts/nginx-demo/values.schema.json`

Create a new file at `charts/nginx-demo/values.schema.json`. Helm uses JSON Schema Draft-07 to validate user values during `helm lint`, `helm template`, `helm install`, and `helm upgrade`.

Add the schema definition:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "title": "Values",
  "type": "object",
  "required": [
    "replicaCount",
    "image",
    "service"
  ],
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 0
    },
    "image": {
      "type": "object",
      "required": [
        "repository",
        "tag"
      ],
      "properties": {
        "repository": {
          "type": "string",
          "minLength": 1
        },
        "tag": {
          "type": "string",
          "minLength": 1
        },
        "pullPolicy": {
          "type": "string"
        }
      }
    },
    "service": {
      "type": "object",
      "required": [
        "port",
        "targetPort"
      ],
      "properties": {
        "type": {
          "type": "string"
        },
        "port": {
          "type": "integer",
          "minimum": 1,
          "maximum": 65535
        },
        "targetPort": {
          "type": "integer",
          "minimum": 1,
          "maximum": 65535
        }
      }
    }
  }
}
```

**Key rules to understand:**

- **Explicit `required`:** In JSON Schema, specifying a property type does **not** make it required. You must list required field names in the `"required": [...]` array.
- **Top-level properties:** Notice that `"additionalProperties": false` is omitted. This allows additional top-level keys (`extraEnv`, `resources`, `pageContent`, and future lab features) without schema errors.
- **Port boundaries:** Restricts `port` and `targetPort` between `1` and `65535`, preventing invalid TCP port configurations.

---

### Step 2: Create `charts/nginx-demo/templates/tests/http.yaml`

Create the directory `charts/nginx-demo/templates/tests/` and create `charts/nginx-demo/templates/tests/http.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Release.Name }}-http-test
  labels:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
    app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
    app.kubernetes.io/managed-by: {{ .Release.Service }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  restartPolicy: Never
  containers:
    - name: http
      image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
      command: ["wget"]
      args:
        - "-qO-"
        - "--timeout=10"
        - "http://{{ include "nginx-demo.serviceName" . }}:{{ .Values.service.port }}/"
```

**Key rules to understand:**

- **`helm.sh/hook: test`:** Marks this Pod as an integration test hook. Helm will NOT deploy it during `helm install` or `upgrade`; it only deploys when you invoke `helm test`.
- **`helm.sh/hook-delete-policy: before-hook-creation`:** Deletes any previous test Pod before creating a new one. This keeps test logs available for inspection via `--logs` after the test finishes (unlike `hook-succeeded`, which deletes the Pod immediately and breaks `--logs`).
- **No selector labels:** Notice the test Pod does **not** have the selector label `app: {{ .Release.Name }}`. Test Pods must never become endpoints in the application Service!
- **`restartPolicy: Never`:** If the test fails, the Pod must not restart in a loop.

---

### Step 3: Create `charts/nginx-demo/templates/NOTES.txt`

Create `charts/nginx-demo/templates/NOTES.txt`. Helm displays this file to operators immediately after a release is installed or upgraded, and when running `helm status`.

```text
1. Get the application URL by running these commands:
  kubectl --namespace {{ .Release.Namespace }} port-forward service/{{ include "nginx-demo.serviceName" . }} 8080:{{ .Values.service.port }}
  curl http://127.0.0.1:8080
```

**Why dynamic templating matters:**

- `{{ .Release.Namespace }}` injects the actual namespace where the release was installed.
- `{{ include "nginx-demo.serviceName" . }}` outputs the exact Service name (`demo-dev-service`).
- `{{ .Values.service.port }}` outputs the configured listening port.

---

## Verify

### 1. Test schema validation with valid values

Run the linter against the default chart, dev profile, and prod profile:

```bash
helm lint ./charts/nginx-demo
helm lint ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm lint ./charts/nginx-demo -f ./charts/nginx-demo/values-prod.yaml
```

*Expect:* All three pass with `0 chart(s) failed`.

### 2. Test fail-fast schema rejection with invalid values

Test invalid negative replica count:

```bash
helm template demo-dev ./charts/nginx-demo --set replicaCount=-1
```

*Expect error:*

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
nginx-demo:
- at '/replicaCount': minimum: got -1, want 0
```

Test invalid TCP port number:

```bash
helm template demo-dev ./charts/nginx-demo --set service.port=70000
```

*Expect error:*

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
nginx-demo:
- at '/service/port': maximum: got 70,000, want 65,535
```

### 3. Deploy and test the live application

Deploy the release using dev values:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
```

Run the in-cluster HTTP test suite:

```bash
helm test demo-dev -n helm-lab --logs --timeout 60s
```

*Expect output:*

```text
TEST SUITE:     demo-dev-http-test
Last Started:   ...
Last Completed: ...
Phase:          Succeeded
POD LOGS: demo-dev-http-test
<h1>Hello from Updated Helm Lab</h1>
<p>I changed this page with helm upgrade.</p>
```

Inspect release status and verify `NOTES.txt` rendering:

```bash
helm status demo-dev -n helm-lab
```

*Expect:* `NOTES:` section displays the rendered port-forward instructions with `demo-dev-service` and port `80`.

## Break it and recover

1. Temporarily change the test's URL in `charts/nginx-demo/templates/tests/http.yaml` to a nonexistent service:
   `http://does-not-exist:{{ .Values.service.port }}/`
2. Run `helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml`
   *(Note: You must run `helm upgrade` because Helm test hooks are stored inside the release manifest in the cluster; editing the file alone does not update the hook).*
3. Run `helm test demo-dev -n helm-lab --logs`:
   *Expect:* `Phase: Failed` and `Error: 1 error occurred: * pod demo-dev-http-test failed`. Logs show `wget: bad address 'does-not-exist:80'`.
4. Restore `templates/tests/http.yaml` to `http://{{ include "nginx-demo.serviceName" . }}:{{ .Values.service.port }}/`, upgrade, and rerun `helm test`. It passes! Notice that a test failure does not automatically roll back the application release.

## Explain

- What can schema validation catch that rendering alone does not?
- What can an HTTP test catch that linting does not?
- Why is `replicaCount: 0` valid even though the HTTP test would then fail?

> [!TIP]
> See [07-validation-and-tests-explained.md](07-validation-and-tests-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Keep the corrected test and schema. Remove any retained failed test Pod after
inspection. Commit and create `lab-07-complete`.

Reference: [Chart tests](https://helm.sh/docs/v3/topics/chart_tests/).

Next: [Dependencies](08-dependencies.md), or choose an [extension](../README.md#learning-path).
