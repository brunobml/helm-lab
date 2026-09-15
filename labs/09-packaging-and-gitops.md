# Lab 9: Packaging and GitOps

**Start:** Lab 8 complete (`lab-08-complete`).
**Goal:** Install a versioned artifact, then understand how Git can drive deployment.

Complete A locally first. B needs an OCI registry you can publish to. C needs a
Git remote readable by Argo CD and an existing Argo CD installation on your lab
cluster. You can pause at these boundaries and record which parts you completed.

## A. Package and install

1. Set the parent chart version to `0.2.0` to identify this completed learning
   milestone. Keep `appVersion` tied to NGINX, not the lab number.
2. Build, lint, and package:

```bash
helm dependency build ./charts/nginx-demo
helm lint ./charts/nginx-demo
mkdir -p dist
helm package ./charts/nginx-demo --destination ./dist
helm show chart ./dist/nginx-demo-0.2.0.tgz
helm install demo-package ./dist/nginx-demo-0.2.0.tgz -n helm-lab -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
helm test demo-package -n helm-lab --timeout 60s
```

Expect chart version `0.2.0`, a separate release, and a passing HTTP test.

**Break it:** Edit `pageContent` in the working chart and render the folder and
archive separately. The archive must retain the packaged content. Restore the
experimental edit; package a new chart version when you want a new artifact.

## B. Publish to OCI

You can publish to either a zero-configuration local registry or an external registry.

### Option 1: Fast local registry (self-contained, no auth required)

```bash
docker run -d -p 5001:5000 --name helm-registry registry:2
LAB_REGISTRY=localhost:5001
LAB_REGISTRY_NAMESPACE=helm-lab

helm push ./dist/nginx-demo-0.2.0.tgz "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE"
helm show chart "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE/nginx-demo" --version 0.2.0
helm template demo-oci "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE/nginx-demo" --version 0.2.0
```

### Option 2: External registry (GHCR, Harbor, Docker Hub, ECR, etc.)

Choose a registry and namespace you control; replace the example values below:

```bash
LAB_REGISTRY=registry.example.com
LAB_REGISTRY_NAMESPACE=your-namespace
helm registry login "$LAB_REGISTRY"
helm push ./dist/nginx-demo-0.2.0.tgz "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE"
helm show chart "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE/nginx-demo" --version 0.2.0
helm template demo-oci "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE/nginx-demo" --version 0.2.0
```

Expect remote metadata and rendering to match the packaged chart. Publishing an
artifact does not install a release. In Helm 3, OCI packaging replaces legacy HTTP
chart repositories (which required hosting an `index.yaml` and running `helm repo add` /
`helm repo update`).

## C. Let Git drive deployment

For this exercise, Argo CD reads the chart from Git. Commit the chart, child
source, lock file, and values file to a branch, then push that branch to your
remote. Argo CD must be able to resolve the local child dependency from this repo.
Use a new namespace, `helm-lab-gitops`, to avoid overlapping manually managed releases.

Create `gitops/nginx-demo.yaml` from this example. Replace `repoURL` and
`targetRevision` with your actual remote and branch. The default Argo CD project
must permit that source and destination.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: nginx-demo
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR-ACCOUNT/helm-lab.git
    targetRevision: YOUR-LAB-BRANCH
    path: charts/nginx-demo
    helm:
      valueFiles:
        - values-dev.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: helm-lab-gitops
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

Apply it and use manual sync first:

```bash
kubectl apply -f gitops/nginx-demo.yaml
argocd app get nginx-demo
argocd app diff nginx-demo
argocd app sync nginx-demo
argocd app wait nginx-demo --health --sync --timeout 120
kubectl get deployment,service -n helm-lab-gitops
```

Use the Argo CD UI equivalents if you do not have its CLI configured. Expect a
Healthy, Synced application. Argo CD defaults the Helm release name to the
Application name here, so resources are `nginx-demo-deployment` and
`nginx-demo-service`. It renders Helm charts and manages the resources itself;
this deployment is not a release to manage with `helm upgrade` or `helm rollback`.

Change the dev replica count in Git, commit, push, refresh the Application, and
inspect its diff before syncing. Expect OutOfSync before sync and the new replica
count afterward. Revert that Git change, push, and sync to practice recovery.

## Explain

- What is the difference between a chart archive and a container image?
- Why is an explicit artifact version useful?
- Who owns deployment history when Argo CD renders a Helm chart?

## Cleanup and checkpoint

```bash
helm uninstall demo-package -n helm-lab
# If you used the local registry in Option 1:
docker rm -f helm-registry 2>/dev/null || true
```

If you completed C, delete the Application with Argo CD's cascading deletion
option (CLI: `argocd app delete nginx-demo --cascade`) and verify its workloads
are gone. Delete the dedicated GitOps namespace afterward if desired. Follow
your registry's UI/CLI to remove the published test artifact if you no longer
need it. Keep source files; `dist/` stays ignored.

Record A/B/C completion separately. Create `lab-09-complete` after completing
all three; if external setup is deferred, record that instead of marking it done.

References: [OCI registries](https://helm.sh/docs/v3/topics/registries/),
[Argo CD Helm support](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/).
