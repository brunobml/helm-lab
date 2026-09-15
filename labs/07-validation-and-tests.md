# Lab 7: Validation and tests

**Start:** Lab 6 complete (`lab-06-complete`), serving custom HTML.
**Goal:** Catch invalid input before deployment and check application behavior afterward.

## Steps

1. Add `charts/nginx-demo/values.schema.json`. Require `replicaCount` to be an
   integer greater than or equal to zero, `image.repository` and `image.tag` to
   be nonempty strings, and Service ports to be integers from 1 through 65535.
   Require these fields explicitly; a property's type alone does not require it.
2. Keep unknown top-level properties allowed while you add future lab features.
3. Add `templates/tests/http.yaml`: a Pod with annotation `helm.sh/hook: test`
   that requests `http://<release>-service:<service.port>/`. Use the same NGINX
   Alpine image values as the application and its available `wget` command.
   Set `restartPolicy: Never` and a hook deletion policy of `before-hook-creation`
   so test logs remain readable with `--logs` and previous test pods are cleaned up
   before new runs.
4. Add a short `templates/NOTES.txt` with the correct namespace-aware
   port-forward command, using the Service-name helper and Service port.

## Verify

```bash
helm lint ./charts/nginx-demo
helm lint ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm lint ./charts/nginx-demo -f ./charts/nginx-demo/values-prod.yaml
helm template demo-dev ./charts/nginx-demo --set replicaCount=-1
helm template demo-dev ./charts/nginx-demo --set service.port=70000
```

The first three should pass; the last two must fail schema validation. Then:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
helm test demo-dev -n helm-lab --logs --timeout 60s
helm status demo-dev -n helm-lab
```

Expect a passing HTTP test and useful access instructions. If you include
`hook-succeeded` in the delete policy, Helm will delete the pod immediately upon
success, which can cause `--logs` to fail with "pod not found". Extend the test
to check for your expected heading if you want to verify content as well as HTTP availability.

## Break it and recover

Temporarily change the test's URL to a nonexistent Service. Upgrade and run the
test; expect failure. Inspect the retained test Pod with `kubectl logs`, correct
the URL, upgrade, and rerun. A Helm test failure does not automatically roll back
the application release.

## Explain

- What can schema validation catch that rendering alone does not?
- What can an HTTP test catch that linting does not?
- Why is `replicaCount: 0` valid even though the HTTP test would then fail?

> [!TIP]
> See [07-validation-and-tests-explained.md](07-validation-and-tests-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Keep the corrected test and schema. Remove any retained failed test Pod after
inspection. Commit and create `lab-07-complete`.

<details>
<summary>Hint: values.schema.json</summary>

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "title": "Values",
  "type": "object",
  "required": ["replicaCount", "image", "service"],
  "properties": {
    "replicaCount": { "type": "integer", "minimum": 0 },
    "image": {
      "type": "object",
      "required": ["repository", "tag"],
      "properties": {
        "repository": { "type": "string", "minLength": 1 },
        "tag": { "type": "string", "minLength": 1 },
        "pullPolicy": { "type": "string" }
      }
    },
    "service": {
      "type": "object",
      "required": ["port", "targetPort"],
      "properties": {
        "type": { "type": "string" },
        "port": { "type": "integer", "minimum": 1, "maximum": 65535 },
        "targetPort": { "type": "integer", "minimum": 1, "maximum": 65535 }
      }
    }
  }
}
```

</details>

<details>
<summary>Hint: test container and annotations</summary>

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: "{{ .Release.Name }}-http-test"
  labels:
    app.kubernetes.io/name: {{ .Chart.Name }}
    app.kubernetes.io/instance: {{ .Release.Name }}
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

Give the test Pod a name such as `<release>-http-test`. Do not give it the
application's selector labels: it must not become a Service endpoint.

</details>

<details>
<summary>Hint: templates/NOTES.txt</summary>

```text
1. Get the application URL by running these commands:
  kubectl --namespace {{ .Release.Namespace }} port-forward service/{{ include "nginx-demo.serviceName" . }} 8080:{{ .Values.service.port }}
  curl http://127.0.0.1:8080
```

</details>

Reference: [Chart tests](https://helm.sh/docs/v3/topics/chart_tests/).

Next: [Dependencies](08-dependencies.md), or choose an [extension](../README.md#learning-path).
