# Lab 1: First chart

**Start:** The committed starter (`lab-00-start`, if you created it), the README
setup complete, and no `demo-dev` release in namespace `helm-lab`.
**Goal:** Trace a value from a chart to a running NGINX Pod.

## Steps

1. Read `charts/nginx-demo/Chart.yaml`, `values.yaml`, and both templates.
2. Find `.Release.Name` and `.Values.replicaCount`. Predict the resource names
   and replica count for release `demo-dev`.
3. Render locally, then install into the lab cluster:

```bash
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo
helm install demo-dev ./charts/nginx-demo -n helm-lab --create-namespace --wait --timeout 120s
```

## Verify

```bash
helm list -n helm-lab
kubectl get deployment,pods,service -n helm-lab
kubectl rollout status deployment/demo-dev-deployment -n helm-lab --timeout=120s
kubectl port-forward -n helm-lab service/demo-dev-service 8080:80
```

Expect a deployed Helm release, a Deployment with two ready replicas, and a
ClusterIP Service. Leave port-forward running; in another terminal:

```bash
curl --fail http://localhost:8080
```

Expect the NGINX welcome HTML. Rendering alone cannot prove that HTTP works.

## Break it and recover

Temporarily misspell `.Values.replicaCount` in the Deployment template. Run
`helm template` and inspect `replicas`: a missing value may render empty instead
of producing an obvious template error. Restore the key and render again.
Do not deploy this broken version; later you will add input validation.

## Explain

- What is the difference between a chart and a release?
- Which files are Helm inputs, and which output is Kubernetes YAML?
- How does the Service find the application's Pods?

## Cleanup and checkpoint

Stop port-forwarding with Ctrl+C. Keep `demo-dev` installed for Lab 2. Record
your observations, commit your work, and create `lab-01-complete`.

<details>
<summary>Hint</summary>

Deployment selector, Pod labels, and Service selector all use `app: demo-dev`.
The chart folder's name is not the release name.

</details>

Next: [Release lifecycle](02-release-lifecycle.md).
