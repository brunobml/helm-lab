# Lab 6: ConfigMaps and rollouts

**Start:** Lab 5 complete (`lab-05-complete`), with helper names and selectors preserved.
**Goal:** Change the served HTML through values and observe an automatic rollout.

## Steps

1. Add a multiline `pageContent` value containing `<h1>Hello from Helm Lab</h1>`.
2. Create `templates/configmap.yaml` named `<release>-page`, with a data key
   `index.html` populated by `pageContent` using a YAML block scalar and `nindent`.
3. Add a Pod volume referencing this ConfigMap and mount it at
   `/usr/share/nginx/html` in the NGINX container. Mount the directory, not a
   `subPath` file, for this exercise.
4. Add a checksum annotation under **`spec.template.metadata.annotations`** in
   the Deployment. This places the checksum in the Pod template, where changes
   trigger a rollout.

## Verify

```bash
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
kubectl get pods -n helm-lab -l app=demo-dev
kubectl get deployment demo-dev-deployment -n helm-lab -o jsonpath='{.spec.template.metadata.annotations}'
kubectl port-forward -n helm-lab service/demo-dev-service 8080:80
```

In another terminal, curl `http://localhost:8080` and expect your custom heading.
Stop port-forwarding. Change the heading in `pageContent`, rerun the upgrade,
and inspect Pods and the checksum again. Restart port-forwarding and curl.
Expect a different checksum, replacement Pod, and updated HTML.

## Break it and recover

Move the checksum to the Deployment's top-level `metadata.annotations` and
upgrade once. Record the Pod name. Change HTML again and upgrade. The checksum
changes but this change alone does not trigger new Pods. A directory-mounted
ConfigMap may eventually update the served file anyway; that is not proof of a
rollout. Restore the checksum under Pod-template metadata and verify replacement.

## Explain

- Why does hashing the ConfigMap change the Deployment's Pod template?
- How do you distinguish a file update from a Pod replacement?
- Why does indentation matter for multiline HTML?

## Cleanup and checkpoint

Stop port-forwarding; keep the working ConfigMap and checksum. Commit and create
`lab-06-complete`.

<details>
<summary>Hint: ConfigMap data and Pod-template annotation</summary>

In `configmap.yaml`, below metadata:

```yaml
data:
  index.html: |
    {{- .Values.pageContent | nindent 4 }}
```

In the Deployment's `spec.template.metadata`, alongside `labels`:

```yaml
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
```

Pod `volumes` belongs alongside `containers`. Container `volumeMounts` belongs
alongside `image` and `ports`; both refer to the same volume name.

</details>

Next: [Validation and tests](07-validation-and-tests.md).
