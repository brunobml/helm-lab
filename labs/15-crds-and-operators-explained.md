# Lab 15: CRDs and operators — Explained

This companion document explains the architectural rationale, failure modes, and Kubernetes mechanics underlying Custom Resource Definitions (CRDs) and operators in Helm.

---

## 1. The Helm CRD Dilemma: Scope vs. Lifecycle

Understanding Helm's CRD behavior requires understanding a fundamental impedance mismatch in Kubernetes architecture:

```text
┌────────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                   │
│                                                        │
│  Cluster Scope:                                        │
│  CustomResourceDefinition (apiextensions.k8s.io)       │
│  (Defines the schema for ALL namespaces)               │
│                            │                           │
│                            ▼ (controls API)            │
│  Namespace: helm-lab       │    Namespace: production  │
│  ┌───────────────────────┐ │    ┌───────────────────┐  │
│  │ Custom Resource: CR-A │ │    │ Custom Resource:  │  │
│  │ (e.g. Certificate A)  │ │    │ CR-B (Prod Cert)  │  │
│  └───────────────────────┘ │    └───────────────────┘  │
│                            ▼                           │
│       ⚠️ DELETE CRD  ──►  CASCADE DELETE ALL CRs!      │
└────────────────────────────────────────────────────────┘
```

### Why Helm releases and CRDs clash

- **Helm Releases are Namespaced Lifecycle Units:**
  When you run `helm install my-app`, Helm creates a release in a specific namespace. When you run `helm uninstall my-app`, Helm deletes all resources that belong to that release.
- **CRDs are Global Cluster Extensions:**
  A CRD does not belong to a single namespace. It registers a new endpoint in the Kubernetes API server (e.g., `/apis/cert-manager.io/v1/certificates`) available cluster-wide.
- **The Cascade Deletion Danger:**
  If Helm tracked a CRD as part of a release, running `helm uninstall` on a staging deployment would delete the CRD. In Kubernetes, deleting a CRD immediately triggers the **garbage collection controller** to cascade-delete every single custom resource of that type in every namespace across the entire cluster! In production, this would destroy active TLS certificates, databases, message queues, and API routes.

---

## 2. The History: Helm 2 Hooks vs. Helm 3 `crds/`

To understand Helm 3's design, look at how Helm 2 handled CRDs:

1. **Helm 2 `crd-install` Hook:**
   In Helm 2, CRDs were placed in `templates/` with an annotation:
   `"helm.sh/hook": "crd-install"`
   This told Helm to apply the manifest before other templates. However, hooks had critical flaws:
   - They had no standardized directory.
   - Template validation failed before hooks could execute if the CR was evaluated in the same pass.
   - Accidental deletions still occurred during uninstall or rollback.

2. **Helm 3 Native `crds/` Directory:**
   Helm 3 introduced the `crds/` directory with explicit guarantees:
   - Installed **only once** on initial install.
   - **Never upgraded** by `helm upgrade`.
   - **Never deleted** by `helm uninstall`.
   - **Un-templated** raw YAML.

### Why Helm 3 Refuses to Upgrade CRDs in `crds/`

The Helm maintainers made a deliberate choice not to support automatic CRD upgrades in `crds/`:

1. **CRD Upgrades are Destructive and Complex:**
   Upgrading a CRD is not just applying YAML. It may involve removing deprecated fields, changing type validation, or migrating storage versions. If an automatic Helm upgrade removes a field from a CRD schema, Kubernetes will prune that field from all existing stored resources, causing irreversible data loss.
2. **Cluster-Wide Impact from Namespaced Tooling:**
   A developer upgrading a dev release in namespace `dev` should never have the authority to alter cluster-wide API definitions that affect `prod`.
3. **Template Engine Limitations:**
   Because CRDs define the schema that Helm itself relies upon when submitting manifests to the Kubernetes API, CRDs must be established before templates are parsed.

---

## 3. The 3-Way Merge Desync Trap

In Part A of the lab, we observed a subtle failure when updating a custom resource field before its CRD schema is upgraded:

```text
1. Developer edits template: adds `spec.replicas: 3`.
2. Developer runs `helm upgrade`.
3. Helm compiles release manifest containing `replicas: 3`.
4. Helm sends manifest to Kubernetes API Server.
5. API Server sees CRD lacks `replicas` schema.
   └── API Server drops `spec.replicas` (or warns).
6. Helm saves release manifest in release Secret (storing `replicas: 3`).
7. ⚠️ DESYNC STATE:
   - Helm thinks `replicas: 3` is applied.
   - Kubernetes cluster does NOT have `replicas: 3`.
8. Developer notices, and runs: `kubectl apply -f crds/...`
9. Cluster CRD now accepts `replicas`.
10. Developer runs `helm upgrade` again without changing template.
11. Helm calculates 3-Way Merge:
    - Previous Manifest: `replicas: 3`
    - Target Manifest:   `replicas: 3`
    - Diff: NO CHANGE!
12. ❌ Helm sends NO PATCH to Kubernetes!
    The live object remains missing `replicas` until the template changes or `--force` is used!
```

This explains why teams often report that "Helm is ignoring my values" after manually fixing a CRD schema.

---

## 4. How Production Operators Solve the Problem

Because of the limitations of `crds/`, four distinct patterns have emerged in the Kubernetes ecosystem:

### Pattern 1: In-Chart Templates with `resource-policy: keep` (cert-manager)

`cert-manager` places its CRDs in `templates/` (e.g. `templates/crds.yaml`) wrapped in a conditional:

```yaml
{{- if .Values.crds.enabled }}
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: certificates.cert-manager.io
  annotations:
    helm.sh/resource-policy: keep
...
{{- end }}
```

**How it works:**

- When `crds.enabled: true`, `helm upgrade` treats the CRDs as normal templates and **upgrades their schemas**.
- When `helm uninstall` runs, Helm checks the annotations. Seeing `"helm.sh/resource-policy": "keep"`, Helm skips deleting the CRD!
- **Caveat:** `helm diff` and releases can become large because CRD definitions are often several megabytes of OpenAPI v3 YAML.

### Pattern 2: Dedicated CRD Subchart (traefik, prometheus)

Projects like Prometheus Operator and Traefik publish two separate charts:

1. `traefik-crd` (or `prometheus-operator-crds`): Installs only the CRDs.
2. `traefik` (or `kube-prometheus-stack`): Installs the operator controller and services.

**Workflow in CI/CD:**

```bash
# Step 1: Upgrade CRDs first
helm upgrade --install traefik-crds traefik/traefik-crds

# Step 2: Upgrade operator controller
helm upgrade --install traefik traefik/traefik
```

This isolates cluster-wide schema privileges from application release lifecycles.

### Pattern 3: Out-of-Band GitOps / Pipeline Application

In enterprise GitOps environments (Flux, Argo CD), charts are installed with CRD installation disabled:

```bash
helm install cert-manager jetstack/cert-manager --skip-crds # or --set crds.enabled=false
```

The GitOps repository manages raw CRD YAML files in a dedicated synchronization root that runs prior to tenant application charts.

---

## 5. Ordering Hazards with Helm Hooks and CRDs

When using Helm lifecycle hooks alongside CRDs, memorize this execution timeline:

```text
Phase 1: Helm unpacks chart and checks crds/
         └── Applies all YAML in crds/ (if helm install)
         └── Waits until Kubernetes reports CRD is Established

Phase 2: Helm executes pre-install hooks
         └── Job or Pod runs
         ⚠️ HAZARD: Cannot create CRs if CRD is in templates/
         ⚠️ HAZARD: Operator controller is NOT running yet!

Phase 3: Helm renders and applies templates/
         └── Deployments, Services, ConfigMaps, and CRs

Phase 4: Helm executes post-install hooks
         └── Job or Pod runs
         ✅ Operator controller is running and can reconcile CRs!
```

### Why Umbrella Charts Fail with Operators

If an umbrella chart bundles an operator subchart and custom resources in another subchart:

```text
umbrella/
  charts/
    my-operator/     # installs CRD in templates/
    my-app/          # creates CustomResource instance
```

Helm renders **all subcharts into a single manifest stream** and validates them against the Kubernetes API discovery cache *before* applying any resource. Since the API server has not yet received or established the CRD from `my-operator`, validation fails immediately:

```text
error: unable to recognize "": no matches for kind "MyCR" in version "example.com/v1"
```

**Rule of Thumb:** Never package an operator and its custom resources in the same Helm release unless the CRD is packaged in `crds/` AND does not require controller validation webhooks during initial admission.

---

## 6. Summary Checklist for CRD Operations

When managing or authoring charts with CRDs:

- [ ] Check how the upstream chart manages CRDs (`crds/` vs `templates/` vs external manifest).
- [ ] For charts using `crds/`, automate a `kubectl apply -f crds/` step in your upgrade pipeline.
- [ ] When packaging CRDs in `templates/`, always add `"helm.sh/resource-policy": keep` to prevent catastrophic cascade deletions on uninstall.
- [ ] Never mix an operator and its custom resources in the same Helm release if admission webhooks are required.
- [ ] Run `helm template --include-crds` when exporting manifests for GitOps or offline policy scanners (`kubeconform`).
