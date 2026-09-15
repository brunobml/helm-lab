# Helm Mastery: From First Chart to Production GitOps

A structured, progressive roadmap for mastering Helm chart development, templating, packaging, and lifecycle management.

---

## Roadmap Overview

```
Phase 1: Fundamentals (Completed)
   │
   ▼
Phase 2: Template Logic & Helpers
   │
   ▼
Phase 3: Config, Secrets & State
   │
   ▼
Phase 4: Networking & Extensibility
   │
   ▼
Phase 5: Multi-Env, Packaging & OCI
   │
   ▼
Phase 6: Testing, CI/CD & GitOps
```

---

## Phase 1: Core Fundamentals (Completed ✅)

- [x] Helm architecture (`Chart.yaml`, `values.yaml`, `templates/`)
- [x] Basic templating syntax (`{{ .Values.<key> }}`)
- [x] Chart linting and rendering (`helm lint`, `helm template`)
- [x] Release lifecycle (`helm install`, `helm upgrade`, `helm rollback`, `helm uninstall`)
- [x] Value overrides via CLI (`--set`)

---

## Phase 2: Template Logic, Functions & Helpers

Learn how to write dynamic, reusable, and robust templates instead of static substitutions.

### Key Objectives
- Master whitespace control (`{{-` and `-}}`) and understand YAML formatting hazards.
- Use pipeline functions: `default`, `quote`, `upper`, `lower`, `toJson`.
- Indentation management with `indent` and `nindent`.
- Flow control:
  - Conditionals: `{{- if }} ... {{- else if }} ... {{- else }} ... {{- end }}`
  - Loops: `{{- range }}` for maps and slices.
  - Scoping: `{{- with }}` and the `$` root context trap.
- Reusable partials in `templates/_helpers.tpl`:
  - `define` and `include`
  - Chart name formatting and Kubernetes 63-character truncation (`trunc 63 | trimSuffix "-"`)
  - Standard Kubernetes labels (`app.kubernetes.io/name`, `instance`, `version`, `managed-by`)

### Practice Project
> Refactor `helm-lab` to use `_helpers.tpl` for standard labels and selector labels. Add an optional `extraEnv` map in `values.yaml` rendered with a `range` loop in `deployment.yaml`.

---

## Phase 3: Configuration, Secrets & Application State

Manage configuration updates, sensitive data, and persistent storage safely.

### Key Objectives
- Dynamically generate `ConfigMap` and `Secret` templates.
- Inject values via `env`, `envFrom`, and volume mounts.
- Automate rolling restarts on config changes:
  ```yaml
  annotations:
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
  ```
- Implement `PersistentVolumeClaim` (PVC) templates with configurable storage classes and access modes.
- Set up resource requests and limits (`resources.limits`, `resources.requests`) using `toYaml` and `nindent`.

### Practice Project
> Add a custom NGINX `index.html` via a `ConfigMap`. Update `deployment.yaml` with the SHA256 checksum annotation and verify that running `helm upgrade` with updated HTML content automatically triggers a rolling deployment.

---

## Phase 4: Networking, Scaling & Workload Variety

Broaden the chart to handle real-world traffic routing and workload types.

### Key Objectives
- Dynamic Service types: toggle between `ClusterIP`, `NodePort`, and `LoadBalancer`.
- Template an `Ingress` resource supporting multiple hosts, paths, and TLS certificates.
- Configure probes: `livenessProbe`, `readinessProbe`, and `startupProbe`.
- Support Horizontal Pod Autoscalers (`HorizontalPodAutoscaler` / HPA).
- Explore other controller templates: `DaemonSet`, `StatefulSet`, `Job`, and `CronJob`.
- RBAC: conditionally render `ServiceAccount`, `ClusterRole`, and `ClusterRoleBinding` templates controlled by a `serviceAccount.create` flag (mirrors `helm create` scaffold defaults).

### Practice Project
> Create an optional `ingress.yaml` template controlled by `ingress.enabled: true|false`. Then add a `serviceaccount.yaml` template gated on `serviceAccount.create: true|false` and wire the service account name into the Deployment's `spec.template.spec.serviceAccountName`. Test both with `helm template`.

---

## Phase 5: Dependencies, Subcharts & OCI Packaging

Package, distribute, and compose complex applications.

### Key Objectives
- Subcharts & dependencies in `Chart.yaml`:
  ```yaml
  dependencies:
    - name: redis
      version: 17.x.x
      repository: https://charts.bitnami.com/bitnami
      condition: redis.enabled
  ```
- Managing subchart values from parent `values.yaml`.
- Global values (`.Values.global.*`).
- Modern chart distribution via OCI (Open Container Initiative) registries:
  - `helm package <chart>`
  - `helm push <package.tgz> oci://<registry-url>/<namespace>`
  - `helm install <release> oci://<registry-url>/<namespace>/<chart>`

### Practice Project
> Add a Redis subchart dependency to `helm-lab`. Expose a flag `redis.enabled` in `values.yaml` and verify that `helm dependency update` downloads the dependency archive.

---

## Phase 6: Testing, GitOps & Production Best Practices

Integrate Helm into automated CI/CD and GitOps workflows.

### Key Objectives
- Chart testing:
  - Built-in test hooks (`helm.sh/hook: test`)
  - Automated unit testing with the `helm-unittest` plugin
- Schema & style enforcement:
  - `values.schema.json` (JSON Schema) for input validation
  - `ct` (Chart Testing CLI) for linting and style enforcement
- Environment isolation patterns:
  - `values.yaml` (defaults)
  - `values-dev.yaml`
  - `values-staging.yaml`
  - `values-prod.yaml`
- GitOps deployment patterns with Argo CD or Flux CD:
  - Helm repository source vs. Git repository source
  - Value file overrides in Application CRDs

---

## Essential CLI Cheat Sheet

| Task | Command |
| :--- | :--- |
| **Lint syntax** | `helm lint <chart-path>` |
| **Render dry-run** | `helm template <release-name> <chart-path> -f <values.yaml>` |
| **Debug install** | `helm install <release-name> <chart-path> --dry-run --debug` |
| **Inspect values** | `helm get values <release-name>` |
| **Inspect all manifests** | `helm get manifest <release-name>` |
| **Revision history** | `helm history <release-name>` |
| **Rollback revision** | `helm rollback <release-name> <revision-number>` |
| **Package chart** | `helm package <chart-path>` |
| **Update dependencies** | `helm dependency update <chart-path>` |
