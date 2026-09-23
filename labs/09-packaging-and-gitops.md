# Lab 9: Packaging and GitOps

**Start:** Lab 8 complete (`lab-08-complete`).
**Goal:** Install a versioned artifact, then understand how Git can drive deployment.

Complete A locally first. B needs an OCI registry you can publish to. C needs a
Git remote readable by Argo CD and an existing Argo CD installation on your lab
cluster. You can pause at these boundaries and record which parts you completed.

## Part A: Package and install

### Step 1: Bump chart version in `charts/nginx-demo/Chart.yaml`

Open `charts/nginx-demo/Chart.yaml` and update the chart `version` to `0.2.0` to represent this packaging milestone:

```yaml
version: 0.2.0
```

> [!NOTE]
> Keep `appVersion: "1.30.4"` unchanged. The chart `version` reflects the Helm template and configuration release, while `appVersion` tracks the underlying application (NGINX).

---

### Step 2: Build dependencies, lint, and package

Run these commands to package the chart into an immutable `.tgz` artifact:

```bash
# 1. Ensure subchart dependencies are built from Chart.lock
helm dependency build ./charts/nginx-demo

# 2. Lint chart syntax and schema
helm lint ./charts/nginx-demo

# 3. Create destination directory and package the chart
mkdir -p dist
helm package ./charts/nginx-demo --destination ./dist
```

*Expect:* Helm outputs `Successfully packaged chart and saved it to: ./dist/nginx-demo-0.2.0.tgz`.

---

### Step 3: Install directly from the packaged artifact

Deploy the `.tgz` package directly without pointing to the uncompressed source folder:

```bash
# Inspect packaged metadata
helm show chart ./dist/nginx-demo-0.2.0.tgz

# Install release from the packaged archive
helm install demo-package ./dist/nginx-demo-0.2.0.tgz -n helm-lab -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s

# Verify integration tests pass
helm test demo-package -n helm-lab --timeout 60s
```

*Expect:* A separate release named `demo-package` running alongside `demo-dev` in namespace `helm-lab`, with all tests passing.

---

## Part B: Publish to an OCI Registry

Helm 3 can push and pull chart archives directly to/from **OCI (Open Container Initiative) registries** using the same protocols and infrastructure as container images.

You have two options:

### Option 1: Fast local registry with Docker (Recommended for labs)

> [!NOTE]
> **Why use Docker for the registry instead of running it in Kubernetes?**
> In production, an OCI registry is an **external infrastructure service** outside the application cluster (like GHCR, AWS ECR, Harbor, or Docker Hub). Running `registry:2` in Docker provides a lightweight, local OCI registry on `localhost:5001` that requires **zero cloud accounts, zero authentication tokens, and zero ingress configuration**, while accurately simulating how Helm interacts with external registries.

1. **Start the local registry container:**

   ```bash
   docker run -d -p 5001:5000 --name helm-registry registry:2
   ```

2. **Push the chart to the local OCI registry:**

   ```bash
   LAB_REGISTRY=localhost:5001
   LAB_REGISTRY_NAMESPACE=helm-lab

   helm push ./dist/nginx-demo-0.2.0.tgz "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE"
   ```

   *Expect output:*

   ```text
   Pushed: localhost:5001/helm-lab/nginx-demo:0.2.0
   Digest: sha256:...
   ```

3. **Inspect and render directly from the OCI registry:**

   ```bash
   helm show chart "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE/nginx-demo" --version 0.2.0
   helm template demo-oci "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE/nginx-demo" --version 0.2.0
   ```

---

### Option 2: External OCI registry (GHCR, Harbor, Docker Hub, ECR)

If you have an account on an external registry, authenticate and push:

```bash
LAB_REGISTRY=ghcr.io
LAB_REGISTRY_NAMESPACE=your-username

# Authenticate with registry
helm registry login "$LAB_REGISTRY"

# Push to OCI registry
helm push ./dist/nginx-demo-0.2.0.tgz "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE"

# Inspect and render from remote registry
helm show chart "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE/nginx-demo" --version 0.2.0
helm template demo-oci "oci://$LAB_REGISTRY/$LAB_REGISTRY_NAMESPACE/nginx-demo" --version 0.2.0
```

---

## Part C: Let Git drive deployment (GitOps with Argo CD)

> [!NOTE]
> **Prerequisites for Part C:**
> Part C requires an Argo CD instance running on your cluster and a remote Git repository (GitHub/GitLab) where your chart branch is pushed.
>
> - If you want to install Argo CD locally on your cluster:
>
>   ```bash
>   kubectl create namespace argocd
>   kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
>   kubectl wait -n argocd --for=condition=Available deploy --all --timeout=300s
>
>   # Access CLI/UI (uses initial admin password non-interactively):
>   kubectl port-forward -n argocd svc/argocd-server 8443:443 &
>   ARGOCD_PWD=$(argocd admin initial-password -n argocd | head -1)
>   argocd login localhost:8443 --username admin --password "$ARGOCD_PWD" --insecure --grpc-web
>   ```
>
> - If you do not have an external Git remote, you can serve a local Git daemon: `git daemon --export-all --base-path=. --port=9418` and use `repoURL: git://<host-ip>/` (with `--base-path=.`, the repo root is served at `/`). Note that `<host-ip>` must be reachable from cluster pods (e.g. WSL2 `eth0` IP or docker bridge IP), and that this daemon exposes repository refs without authentication on port 9418.
> - If you do not have Argo CD or an external Git remote configured, completing **Part A and Part B** fulfills all core Helm packaging and OCI registry learning objectives!

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
argocd app diff nginx-demo || true
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
inspect its diff before syncing:

```bash
argocd app get nginx-demo --refresh
argocd app diff nginx-demo || true   # Note: exits 1 when differences exist
argocd app sync nginx-demo
```

Expect OutOfSync before sync and the new replica count afterward. Revert that Git
change, push, and sync to practice recovery.

## Break it and recover

Test packaging drift detection and artifact immutability:

1. Temporarily modify the chart's defaults in `charts/nginx-demo/values.yaml` (for example, change `replicaCount: 2` to `replicaCount: 5`).
2. Render from the pre-packaged archive:

   ```bash
   helm template dist/nginx-demo-0.2.0.tgz | grep -A 2 'replicas:'
   ```

   Notice that Helm renders from the archived package (`replicas: 2`) and completely ignores unpacked changes made in `charts/nginx-demo/`. The package archive is immutable!
3. To package the changes, honor SemVer and artifact immutability by bumping the chart `version: 0.2.1` in `charts/nginx-demo/Chart.yaml`, then run `helm package charts/nginx-demo -d dist`.
4. Render the new archive `helm template dist/nginx-demo-0.2.1.tgz | grep -A 2 'replicas:'` and verify it renders `replicas: 5`.
5. Restore `replicaCount: 2` in `values.yaml` and `version: 0.2.0` in `Chart.yaml`, and remove `dist/nginx-demo-0.2.1.tgz`.

## Explain

- What is the difference between a chart archive and a container image?
- Why is an explicit artifact version useful?
- Who owns deployment history when Argo CD renders a Helm chart?

> [!TIP]
> See [09-packaging-and-gitops-explained.md](09-packaging-and-gitops-explained.md) for detailed explanations and answers to these questions.

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
