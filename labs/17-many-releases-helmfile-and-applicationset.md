# Lab 17: Many releases: Helmfile (and Argo CD ApplicationSet)

**Start:** Lab 16 complete (`lab-16-complete`). Cluster with internet access and Helm v3.
**Goal:** Master multi-release fleet orchestration across environments using Helmfile, declare dependency DAGs (`needs:`), implement environment-based values layering, manage releases via label selectors, execute safe promotions (dev -> prod), and understand the equivalent GitOps architecture with Argo CD `ApplicationSet`.

Deploying a single chart with `helm install -f values.yaml` is simple. But real-world systems consist of dozens of microservices, databases, and third-party controllers deployed across multiple environments (development, staging, production).

Relying on shell scripts (`./deploy-all.sh`) quickly breaks down: scripts lack dependency resolution, parallel execution, drift detection, and state tracking. Umbrella charts can bundle subcharts, but they force all components into a single monolithic release lifecycle and namespace.

In this lab, you will use **Helmfile**, the industry-standard declarative orchestrator for Helm, to manage an enterprise multi-tier release fleet. You will also examine the equivalent pull-based GitOps pattern using an **Argo CD ApplicationSet**.

---

## Part A: Fleet architecture and directory structure

We will orchestrate a 4-release application fleet:

1. `backend-db`: PostgreSQL database ([`charts/shop-db`](../charts/shop-db))
2. `backend-api`: PostgREST API ([`charts/shop-api`](../charts/shop-api)) — depends on `backend-db`
3. `frontend-web`: Hardened NGINX frontend ([`charts/nginx-demo`](../charts/nginx-demo)) — depends on `backend-api`
4. `monitoring-probe`: Lightweight health probe (`podinfo/podinfo`) — external Helm repository

```text
helmfile/
├── helmfile.yaml.gotmpl       # Core declarative fleet specification
├── environments/
│   ├── dev.yaml              # Dev environment configuration
│   └── prod.yaml             # Prod environment configuration
├── values/
│   ├── db.yaml.gotmpl        # Layered values for PostgreSQL
│   ├── api.yaml.gotmpl       # Layered values for API
│   └── web.yaml.gotmpl       # Layered values for Web frontend
└── argocd/
    └── applicationset.yaml   # Argo CD ApplicationSet equivalent
```

---

## Part B: Setup and Helmfile installation

### Step 1: Install `helmfile`

If `helmfile` is not already installed in your environment, install the standalone binary:

```bash
# Verify if helmfile is available:
helmfile --version || {
  curl -sL https://github.com/helmfile/helmfile/releases/download/v1.8.0/helmfile_1.8.0_linux_amd64.tar.gz | tar -xz -C /tmp/ helmfile
  mkdir -p ~/.local/bin && mv /tmp/helmfile ~/.local/bin/
  chmod +x ~/.local/bin/helmfile
}
```

Verify that the `diff` plugin is installed in Helm (required by `helmfile diff`):

```bash
helm plugin list | grep diff || helm plugin install https://github.com/databus23/helm-diff
```

---

## Part C: The declarative fleet specification

### Step 2: Inspect environment values

Inspect `helmfile/environments/dev.yaml` and `helmfile/environments/prod.yaml`:

```bash
cat helmfile/environments/dev.yaml
echo "---"
cat helmfile/environments/prod.yaml
```

Notice the key differences between environments:

- **Namespace isolation:** `helm-lab-dev` vs `helm-lab-prod`.
- **Scaling:** `dev` runs 1 web replica; `prod` runs 2 replicas.
- **Hardening:** `prod` enables `PodDisruptionBudget` and `NetworkPolicy`.
- **Version Promotion:** `dev` runs probe version `6.14.0`; `prod` runs promoted version `6.15.0`.

### Step 3: Inspect layered values templates

Inspect `helmfile/values/db.yaml.gotmpl`:

```yaml
secret:
  create: true
  password: "shop{{ .Values.environment }}password"
persistence:
  enabled: false
```

Inspect `helmfile/values/api.yaml.gotmpl`:

```yaml
secret:
  create: true
  password: "shop{{ .Values.environment }}password"
# Note: shop-db names its service '<release>-db', which resolves to 'backend-db-db'
dbHost: backend-db-db
```

Inspect `helmfile/values/web.yaml.gotmpl`:

```yaml
replicaCount: {{ .Values.web.replicas }}
podDisruptionBudget:
  enabled: {{ .Values.web.pdb }}
networkPolicy:
  enabled: {{ .Values.web.networkPolicy }}
extraEnv:
  # Note: shop-api names its service '<release>-api', which resolves to 'backend-api-api'
  API_URL: "http://backend-api-api:3000"
  ENVIRONMENT: {{ .Values.environment | quote }}
```

Helmfile renders `.gotmpl` files with Go text/template before passing the result to Helm. This eliminates hardcoded configuration and allows values to dynamically adapt to the target environment.

### Step 4: Inspect `helmfile.yaml.gotmpl`

Inspect `helmfile/helmfile.yaml.gotmpl`:

```yaml
environments:
  default:
    values:
      - environments/dev.yaml
  dev:
    values:
      - environments/dev.yaml
  prod:
    values:
      - environments/prod.yaml

---

helmDefaults:
  wait: true
  timeout: 300

repositories:
  - name: podinfo
    url: https://stefanprodan.github.io/podinfo

releases:
  - name: backend-db
    namespace: {{ .Values.namespace }}
    createNamespace: true
    chart: ../charts/shop-db
    labels:
      tier: backend
      component: database
    values:
      - values/db.yaml.gotmpl

  - name: backend-api
    namespace: {{ .Values.namespace }}
    createNamespace: true
    chart: ../charts/shop-api
    needs:
      - {{ .Values.namespace }}/backend-db
    labels:
      tier: backend
      component: api
    values:
      - values/api.yaml.gotmpl

  - name: frontend-web
    namespace: {{ .Values.namespace }}
    createNamespace: true
    chart: ../charts/nginx-demo
    needs:
      - {{ .Values.namespace }}/backend-api
    labels:
      tier: frontend
      component: web
    values:
      - values/web.yaml.gotmpl

  - name: monitoring-probe
    namespace: {{ .Values.namespace }}
    createNamespace: true
    chart: podinfo/podinfo
    version: {{ .Values.probe.version }}
    labels:
      tier: monitoring
      component: probe
    values:
      - replicaCount: 1
      - ui:
          color: {{ .Values.probe.color | quote }}
          message: {{ .Values.probe.message | quote }}
```

> [!NOTE]
> **Understanding `needs:` DAG Ordering and `wait: true`:**
> Helmfile builds a Directed Acyclic Graph (DAG) of your releases. However, by default `needs:` orders only the sequence of `helm upgrade --install` invocations. To guarantee that `backend-db` is actually running and **Ready** before `backend-api` begins installing, `helmDefaults: { wait: true, timeout: 300 }` is specified. Without `wait: true`, Helm would fire commands sequentially without waiting for pod readiness.

---

## Part D: Diffing and applying the development fleet

### Step 5: Preview changes with `helmfile diff`

Before touching the cluster, preview what Helmfile will create in the `dev` environment:

```bash
cd helmfile
helmfile -e dev diff
```

Notice that:

1. Helmfile updates repository indices.
2. It calculates the topological order based on `needs:`: `backend-db` -> `monitoring-probe` -> `backend-api` -> `frontend-web`.
3. It prints a colorized `helm diff` preview of every Kubernetes resource that will be created in `helm-lab-dev`.

### Step 6: Deploy the dev fleet with `helmfile apply`

Apply the entire fleet into `helm-lab-dev`:

```bash
helmfile -e dev apply
```

*Observation:* Helmfile installs the releases in strict dependency order, waiting for dependencies to establish before proceeding.

Verify the deployed releases and running pods:

```bash
# List Helm releases in dev namespace:
helm list -n helm-lab-dev

# Check running pods:
kubectl get pods -n helm-lab-dev
```

*Expect:* All four releases (`backend-db`, `backend-api`, `frontend-web`, `monitoring-probe`) are deployed.

---

## Part E: Targeted operations with label selectors

In a fleet of twenty releases, you frequently want to inspect or upgrade only a specific tier (e.g. backend services) without touching the rest of the fleet.

Helmfile allows filtering releases by `labels`:

```bash
# List only releases with label 'tier=backend':
helmfile -e dev -l tier=backend list

# Diff only the frontend tier:
helmfile -e dev -l tier=frontend diff

# Upgrade only the database:
helmfile -e dev -l component=database apply
```

Label selectors make large fleets manageable by allowing granular, safe sub-fleet operations.

---

## Part F: Safe production promotion

Promoting software from development to production should never involve editing chart templates. Instead, promotion is executed by switching the target environment values.

### Step 7: Preview production changes

Preview the production deployment using `helmfile diff`:

```bash
helmfile -e prod diff
```

Inspect the diff carefully. Notice that:

- Target namespace is `helm-lab-prod`.
- `frontend-web` has `replicas: 2` (scaled up from 1).
- `frontend-web` adds `PodDisruptionBudget` (`minAvailable: 1`) and `NetworkPolicy`.
- `monitoring-probe` is promoted from version `6.14.0` to `6.15.0`.

### Step 8: Apply the production fleet

Deploy the production fleet:

```bash
helmfile -e prod apply
```

Verify that both environments run concurrently in complete isolation:

```bash
# Verify dev environment (1 replica, no PDB):
kubectl get pods,pdb,networkpolicy -n helm-lab-dev

# Verify prod environment (2 replicas, PDB, NetworkPolicy):
kubectl get pods,pdb,networkpolicy -n helm-lab-prod
```

---

## Part G: The GitOps equivalent: Argo CD ApplicationSet

In a pull-based GitOps model, [Argo CD ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset-architecture/) provides the controller equivalent of Helmfile.

Inspect `helmfile/argocd/applicationset.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: shop-fleet
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: helm-lab-dev
            webReplicas: "1"
            probeVersion: "6.14.0"
          - env: prod
            namespace: helm-lab-prod
            webReplicas: "2"
            probeVersion: "6.15.0"
  template:
    metadata:
      name: "{{env}}-frontend-web"
    spec:
      project: default
      source:
        repoURL: "https://github.com/brunobml/helm-lab.git"
        targetRevision: HEAD
        path: charts/nginx-demo
        helm:
          releaseName: frontend-web
          values: |
            replicaCount: {{webReplicas}}
            extraEnv:
              ENVIRONMENT: "{{env}}"
      destination:
        server: "https://kubernetes.default.svc"
        namespace: "{{namespace}}"
```

### Helmfile vs. Argo CD ApplicationSet

| Feature | Helmfile | Argo CD ApplicationSet |
| :--- | :--- | :--- |
| **Model** | Declarative Push (CLI / CI Pipeline) | Declarative Pull (Kubernetes Controller) |
| **Execution** | Runs in local terminal, Docker, or GitHub Actions | Runs in-cluster as an operator |
| **Dependency DAG** | Native `needs:` directive with topological sorting | Sync waves (`argocd.argoproj.io/sync-wave`) |
| **Drift Detection** | On-demand via `helmfile diff` | Continuous background reconciliation |
| **Best Fit** | Local development, ephemeral CI environments, cluster bootstrap | Long-running production environments, continuous deployment |

---

## Part H: Break it and recover

### Trap 1: The DAG circular dependency trap

What happens if a developer accidentally introduces a circular dependency in `needs:`?

Simulate a cycle: edit `helmfile/helmfile.yaml.gotmpl` so that `backend-db` declares `needs: [ "{{ .Values.namespace }}/frontend-web" ]` (creating a loop: `db -> api -> web -> db`).

Run `helmfile -e dev diff`:

```text
in ./helmfile.yaml.gotmpl: in release "backend-db": cycle detected: backend-db -> frontend-web -> backend-api -> backend-db
```

Helmfile's internal DAG validator detects the cycle and halts execution before any commands are executed against the Kubernetes cluster.

### Trap 2: The unpinned version drift trap

What happens if a release omits `version:` or uses a floating range like `version: ">6.0.0"`?

- In `dev`, the unpinned chart resolves to the latest version available today (e.g. `6.15.0`).
- If upstream releases a breaking change (`7.0.0`), the next `helmfile diff` or CI execution in `dev` silently pulls `7.0.0`, breaking your build unexpectedly.
- **Rule of Thumb:** Always pin exact semantic versions (`version: "6.14.0"`) in your environment values. Promote versions intentionally by updating the environment YAML file.

---

## Cleanup and Checkpoint

Destroy both the `dev` and `prod` release fleets cleanly using Helmfile:

```bash
cd "$(git rev-parse --show-toplevel)/helmfile"
helmfile -e dev destroy
helmfile -e prod destroy
kubectl delete namespace helm-lab-dev helm-lab-prod --ignore-not-found
```

Verify that all fleet releases are removed:

```bash
helm list -A | grep -E 'helm-lab-(dev|prod)' || echo "All lab releases cleanly destroyed"
```

Check git status to confirm your repository is ready for checkpointing:

```bash
git status
```

---

## Explain: deepen your understanding

After completing this lab, you should be able to answer:

1. Why does `needs:` in Helmfile require `helmDefaults: { wait: true }` to guarantee that dependency pods are actually Ready before dependent releases install?
2. How do `.gotmpl` layered values files allow single charts to adapt dynamically across environments without code duplication?
3. How does Helmfile calculate topological execution order, and what happens when circular dependencies occur?
4. How does Argo CD ApplicationSet provide the declarative GitOps pull equivalent of Helmfile?

> [!TIP]
> See [17-many-releases-helmfile-and-applicationset-explained.md](17-many-releases-helmfile-and-applicationset-explained.md) for deep dives into Helmfile DAG sequencing, environment promotion patterns, and Argo CD ApplicationSet matrix generators.
