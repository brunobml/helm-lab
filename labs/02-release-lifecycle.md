# Lab 2: Release lifecycle

**Start:** Lab 1 complete (`lab-01-complete`), with `demo-dev` running two replicas.
**Goal:** Make, inspect, and reverse a release change.

## Steps

1. Record the current revision from `helm history` before changing anything.
2. Upgrade the release to three replicas using a CLI override.
3. Compare user-supplied values with computed values and stored manifests.

```bash
helm history demo-dev -n helm-lab
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set replicaCount=3 --wait --timeout 120s
helm get values demo-dev -n helm-lab
helm get values demo-dev -n helm-lab --all
helm get manifest demo-dev -n helm-lab
kubectl get deployment demo-dev-deployment -n helm-lab
```

## Verify

Expect three ready replicas and a new Helm revision. The source `values.yaml`
still says two: a CLI override does not edit it.

Use your recorded revision (replace `1` if your history differs):

```bash
helm rollback demo-dev 1 -n helm-lab --wait --timeout 120s
helm history demo-dev -n helm-lab
kubectl get deployment demo-dev-deployment -n helm-lab
```

Expect two replicas. Rollback creates another revision rather than deleting history.

## Break it and recover

Try an unavailable image tag:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set-string image.tag=does-not-exist-helm-lab --wait --timeout 60s
kubectl get pods -n helm-lab
kubectl describe pods -n helm-lab -l app=demo-dev
helm history demo-dev -n helm-lab
```

Expect the upgrade to time out and a new Pod to report an image-pull error.
Existing healthy Pods may continue serving traffic. Recover by rolling back to
the newest revision whose STATUS is `deployed` in `helm history` (revision 3 if you
followed this lab): `helm rollback demo-dev 3 -n helm-lab --wait --timeout 120s`. Verify the Deployment is healthy again.

## Explain

- How do chart version, image tag, and release revision differ?
- Does a successful render imply a successful rollout?
- Which command showed the cause of the failure?

> [!TIP]
> See [02-release-lifecycle-explained.md](02-release-lifecycle-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Practice uninstalling, then restore the baseline for Lab 3:

```bash
helm uninstall demo-dev -n helm-lab
helm list -n helm-lab
helm install demo-dev ./charts/nginx-demo -n helm-lab --wait --timeout 120s
```

The namespace remains; the fresh install starts new release history. Record
observations, commit, and create a personal tag such as `my-lab-02-complete` (the reference
`lab-02-complete` tag already exists in this repository).

Next: [Values and environments](03-values-and-environments.md).
