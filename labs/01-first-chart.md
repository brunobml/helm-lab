# Lab 1: First chart

**Start:** The starter chart from [Lab 0: Chart creation](00-chart-creation.md) (or tag `lab-00-start`),
the README setup complete, and no `demo-dev` release in namespace `helm-lab`.
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
```

Expect a deployed Helm release, a Deployment with two ready replicas, and a
ClusterIP Service. Then open a temporary tunnel to the Service and request the page.
`port-forward` keeps running until stopped, so start it in the background:

```bash
kubectl port-forward -n helm-lab service/demo-dev-service 8080:80 &
sleep 2
curl --fail http://localhost:8080
kill %1   # stop the port-forward
```

(Alternatively, run `port-forward` in one terminal and `curl` in another.)

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

> [!TIP]
> See [01-first-chart-explained.md](01-first-chart-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Make sure port-forwarding is stopped (`kill %1`, or Ctrl+C in its terminal). Keep `demo-dev` installed for Lab 2. Record
your observations, commit your work, and create a personal tag such as `my-lab-01-complete` (the reference
`lab-01-complete` tag already exists in this repository).

<details>
<summary>Hint</summary>

Deployment selector, Pod labels, and Service selector all use `app: demo-dev`.
The chart folder's name is not the release name.

</details>

Next: [Release lifecycle](02-release-lifecycle.md).
