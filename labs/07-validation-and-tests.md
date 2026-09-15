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
   Set `restartPolicy: Never` and a hook deletion policy of
   `before-hook-creation,hook-succeeded` so tests can be rerun.
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

Expect a passing HTTP test and useful access instructions. Successful-hook
cleanup may remove logs before they can be fetched; temporarily keep successful
Pods if you need to inspect them. Extend the test to check for your expected
heading if you want to verify content as well as HTTP availability.

## Break it and recover

Temporarily change the test's URL to a nonexistent Service. Upgrade and run the
test; expect failure. Inspect the retained test Pod with `kubectl logs`, correct
the URL, upgrade, and rerun. A Helm test failure does not automatically roll back
the application release.

## Explain

- What can schema validation catch that rendering alone does not?
- What can an HTTP test catch that linting does not?
- Why is `replicaCount: 0` valid even though the HTTP test would then fail?

## Cleanup and checkpoint

Keep the corrected test and schema. Remove any retained failed test Pod after
inspection. Commit and create `lab-07-complete`.

<details>
<summary>Hint: test container</summary>

```yaml
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

Reference: [Chart tests](https://helm.sh/docs/v3/topics/chart_tests/).

Next: [Dependencies](08-dependencies.md), or choose an [extension](../README.md#learning-path).
