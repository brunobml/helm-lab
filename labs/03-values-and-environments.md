# Lab 3: Values and environments

**Start:** Lab 2 complete (`lab-02-complete`), with the baseline `demo-dev` installed.
**Goal:** Deploy the same chart with different settings and predict precedence.

## Steps

1. Create `charts/nginx-demo/values-dev.yaml` with `replicaCount: 1`.
2. Create `charts/nginx-demo/values-prod.yaml` with `replicaCount: 3`.
   These are practice profiles, not production readiness guarantees.
3. Render each file. Then pass both files and a CLI override:

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm template demo-prod ./charts/nginx-demo -f ./charts/nginx-demo/values-prod.yaml
helm template precedence ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml -f ./charts/nginx-demo/values-prod.yaml --set replicaCount=4
```

4. Install both release configurations:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
helm install demo-prod ./charts/nginx-demo -n helm-lab -f ./charts/nginx-demo/values-prod.yaml --wait --timeout 120s
```

## Verify

Expect rendered replicas of 1, 3, and 4 respectively. Chart defaults are overridden
by values files, later files win for conflicting keys, and CLI overrides win over
files. Inspect the cluster:

```bash
helm list -n helm-lab
kubectl get deployments -n helm-lab
kubectl get service demo-dev-service demo-prod-service -n helm-lab -o yaml
```

Expect separate Deployments with one and three replicas. Each Service selects
its own release. Future labs use `--reset-values -f .../values-dev.yaml` on upgrades
to make the desired inputs explicit instead of relying on previous CLI overrides.

## Break it and recover

Render with `--set service.port=8080`, then with
`--set service.port=8080 --set service.targetPort=8080`. Compare the output.
Explain why the first can route to NGINX on 80 and the second cannot. Neither
value changes NGINX's configuration. Keep targetPort at 80.

## Explain

- What happens when you reverse the two `-f` arguments?
- Why can two releases of the same chart coexist?
- How would separate namespaces improve environment isolation?

> [!TIP]
> See [03-values-and-environments-explained.md](03-values-and-environments-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

```bash
helm uninstall demo-prod -n helm-lab
```

Keep both values files and `demo-dev` with one replica. Commit and create
`lab-03-complete`.

Next: [Template logic](04-template-logic.md).
