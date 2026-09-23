# Lab 16: Production hardening and chart best practices — Explained

This companion document explores the architectural rationale, security boundaries, and operational mechanisms behind production-grade Kubernetes Helm charts.

---

## 1. Kubernetes Pod Security Standards (PSS) Deep Dive

In Kubernetes v1.25+, the deprecated PodSecurityPolicy (PSP) was replaced by the built-in **Pod Security Admission (PSA)** controller. PSA enforces Pod Security Standards across three discrete tiers:

```text
┌────────────────────────────────────────────────────────┐
│               Privileged                               │
│  - Completely unrestricted. Allows root, hostNetwork,  │
│    hostPID, hostPath, privileged containers.           │
├────────────────────────────────────────────────────────┤
│               Baseline                                 │
│  - Prevents known privilege escalations. Default       │
│    configuration for most general workloads.           │
├────────────────────────────────────────────────────────┤
│               Restricted                               │
│  - Hardened security profile. Requires non-root,       │
│    dropped capabilities, read-only rootfs, seccomp.    │
└────────────────────────────────────────────────────────┘
```

### The Three Modes of Pod Security Admission

Namespaces configure PSA using labels in three possible modes:

- `enforce`: Rejects pods that violate the standard (returns HTTP 403 Forbidden).
- `audit`: Allows the pod, but records an audit event in the Kubernetes audit log.
- `warn`: Allows the pod, but returns a warning message directly to the client terminal.

In Lab 16, we labeled the namespace with `pod-security.kubernetes.io/enforce: restricted`.

### Why each `restricted` setting matters

1. **`runAsNonRoot: true` & `runAsUser: 101`:**
   Running container processes as root (UID 0) inside a container gives an attacker who escapes the container root permissions on the underlying host node. Unprivileged containers execute as arbitrary high UIDs (e.g. 101 for `nginx` or 1000 for standard users).
2. **`allowPrivilegeEscalation: false`:**
   Prevents child processes from gaining more privileges than their parent process (e.g. blocking `setuid` binaries like `sudo` or `ping`).
3. **`capabilities.drop: ["ALL"]`:**
   Linux capabilities divide root privileges into distinct units (e.g. `CAP_NET_ADMIN`, `CAP_SYS_ADMIN`, `CAP_CHOWN`). Dropping `ALL` removes all kernel capabilities from the process.
4. **`readOnlyRootFilesystem: true`:**
   Makes the container's root filesystem immutable. If an attacker discovers a Remote Code Execution (RCE) vulnerability in the application, they cannot write malicious scripts, download backdoors, or alter binary files on disk. Any dynamic state must be written to explicit, transient `emptyDir` mounts.
5. **`seccompProfile: { type: RuntimeDefault }`:**
   Applies the container runtime's default Secure Computing (seccomp) system call filter, blocking dozens of dangerous or rarely used Linux syscalls.

---

## 2. The Unprivileged NGINX Architecture

Standard NGINX images (`nginx:alpine`) are designed to run as `root` because:

- In historical Linux kernels, binding to network ports below 1024 (such as port 80) required root privileges (`CAP_NET_BIND_SERVICE`).
- The default configuration writes master PID files to `/var/run/nginx.pid` and caches to `/var/cache/nginx`, which are root-owned.

To run securely under the `restricted` profile:

1. We use `nginxinc/nginx-unprivileged`, which runs as UID 101 (`nginx`).
2. The default port is shifted to `8080` (above 1024).
3. In Kubernetes, the `Service` continues listening on port `80` externally, while mapping `targetPort: 8080` to the pod.
4. When `readOnlyRootFilesystem: true` is active, transient directories (`/tmp`, `/var/cache/nginx`, and `/var/run`) are mounted as memory-backed `emptyDir` volumes.

---

## 3. Availability Engineering: PDB & Topology Spread

Deploying multiple replicas (`replicaCount: 2`) does not guarantee high availability by itself.

### PodDisruptionBudget (PDB)

Kubernetes distinguishes between:

- **Involuntary Disruptions:** Hardware failures, kernel panics, or node network loss (unavoidable).
- **Voluntary Disruptions:** Node draining (`kubectl drain`) for OS upgrades, cluster autoscaler downsizing, or rolling cluster reboots.

A `PodDisruptionBudget` protects against voluntary disruptions. When an engineer or automated pipeline drains a node, the Kubernetes Eviction API checks active PDBs:

- If `minAvailable: 1` and only 1 pod is healthy, the eviction request is **blocked** until another pod becomes ready on a different node.
- This prevents automated maintenance from accidentally taking down a service.

### Topology Spread Constraints

By default, the Kubernetes scheduler distributes pods based on resource utilization. On a 3-node cluster, two replicas might both be scheduled on `node-1`. If `node-1` fails, the service suffers total downtime.

`topologySpreadConstraints` with `topologyKey: kubernetes.io/hostname` and `maxSkew: 1` instruct the scheduler to spread pods evenly across nodes (or availability zones with `topology.kubernetes.io/zone`).

---

## 4. Network Micro-Segmentation with NetworkPolicy

By default, Kubernetes network models follow a "flat network" design: any pod can communicate with any other pod across any namespace.

When a `NetworkPolicy` selects a pod:

1. **Default Deny:** The pod enters an "isolated" state. All ingress traffic is denied except what is explicitly whitelisted.
2. **DNS Egress Requirement:**
   If a NetworkPolicy specifies `policyTypes: [Egress]`, **all egress is blocked**. If you do not explicitly whitelist UDP/TCP port 53 to the cluster DNS service (CoreDNS in `kube-system`), the application will fail to resolve any domain names, databases, or external APIs!
3. **Selector semantics in `from`:** Each list item is a separate allowed source. `podSelector: {}` on its own means "any Pod in **this** namespace". `namespaceSelector: {}` on its own means "any Pod in **any** namespace", which effectively disables ingress isolation. That's why the chart allows the release namespace plus only the namespaces listed in `networkPolicy.allowedNamespaces`, matched by the built-in `kubernetes.io/metadata.name` label. If you put an Ingress controller in front of the chart, add its namespace to that list.

---

## 5. Tooling: `helm-docs` and `kubeconform`

Production charts should automate validation and documentation:

### `helm-docs`

Maintains synchronization between `values.yaml` and documentation. By adding docstrings directly above keys in `values.yaml`:

```yaml
# -- CPU and memory resource requests and limits.
resources:
  requests:
    cpu: 50m
```

Running `helm-docs` automatically generates standard GitHub Markdown tables inside `README.md`.

### `kubeconform`

Validates rendered templates against the official Kubernetes OpenAPI schema specifications. Unlike `helm lint` (which only checks template syntax), `kubeconform`:

- Rejects deprecated or removed API versions (`apiVersion: extensions/v1beta1`).
- Validates field data types and mandatory fields according to specific Kubernetes versions (e.g. `v1.30.0`).
- Runs fast in CI pipelines without requiring a live Kubernetes cluster.

---

## 6. Enterprise Production Readiness Checklist

Before publishing any Helm chart to production:

- [ ] **Pod Security:** Default `securityContext` passes the `restricted` Pod Security standard.
- [ ] **High Availability:** `PodDisruptionBudget` and `topologySpreadConstraints` are supported.
- [ ] **Resource Sizing:** Sensible `requests` and `limits` are configured to guarantee QoS classes.
- [ ] **Micro-segmentation:** `NetworkPolicy` template is included to restrict unauthorized ingress.
- [ ] **Probes:** Explicit `livenessProbe`, `readinessProbe`, and `startupProbe` are configured.
- [ ] **Documentation:** `values.yaml` is tagged with docstrings and validated with `helm-docs`.
- [ ] **CI Gates:** Manifests pass `helm lint`, `helm unittest`, and `kubeconform -strict`.
