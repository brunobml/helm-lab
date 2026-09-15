# Lab 3: Values and environments — Explained

[Back to Lab 3: Values and environments](03-values-and-environments.md)

---

## Overview

In Lab 3, you learned how values files (`values-dev.yaml`, `values-prod.yaml`) and CLI `--set` overrides interact through Helm's precedence rules, and how multiple releases of the same chart coexist on a single cluster.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: What happens when you reverse the two `-f` arguments?

#### TL;DR
When you pass multiple values files with `-f`, **later files override earlier files** for conflicting keys. Reversing the order reverses which file wins.

#### Deep Dive & Mechanism
1. **Values Hierarchy in Helm:**
   From lowest priority (default) to highest priority (override):
   ```text
   [Subchart values.yaml]
              ↓
   [Parent chart values.yaml]
              ↓
   [-f file1.yaml]
              ↓
   [-f file2.yaml (wins over file1)]
              ↓
   [--set key=value (highest priority)]
   ```

2. **The Reversal Experiment:**
   - If `values-dev.yaml` defines `replicaCount: 1` and `values-prod.yaml` defines `replicaCount: 3`:
     ```bash
     helm template precedence ./charts/nginx-demo -f values-dev.yaml -f values-prod.yaml
     # Result: replicaCount is 3 (values-prod.yaml was evaluated last)
     ```
   - If you reverse the order:
     ```bash
     helm template precedence ./charts/nginx-demo -f values-prod.yaml -f values-dev.yaml
     # Result: replicaCount is 1 (values-dev.yaml was evaluated last)
     ```
   - CLI flags like `--set replicaCount=4` override all `-f` files regardless of ordering.

3. **Why `--reset-values` is Critical:**
   - When running `helm upgrade`, Helm retains values supplied in previous revisions by default.
   - If you ran `helm upgrade --set replicaCount=5` in revision 2, subsequent upgrades might silently inherit that override unless you supply `--reset-values -f <file>` to wipe old CLI overrides and reset the release state strictly to the declared files.

---

### Question 2: Why can two releases of the same chart coexist?

#### TL;DR
Because each resource's name and selectors incorporate **`{{ .Release.Name }}`**, ensuring that their names and label selectors do not collide in the Kubernetes API.

#### Deep Dive & Mechanism
- In Kubernetes, object identity in a given namespace is uniquely defined by:
  `[Group, Version, Kind, Name]`
- If the chart had hardcoded `name: nginx-deployment`, attempting to install a second release (`demo-prod`) would fail with:
  ```text
  Error: rendered manifests contain a resource that already exists
  ```
- Because our templates use:
  ```yaml
  metadata:
    name: {{ .Release.Name }}-deployment
  ```
  - Release `demo-dev` creates `demo-dev-deployment` and `demo-dev-service`.
  - Release `demo-prod` creates `demo-prod-deployment` and `demo-prod-service`.
- Furthermore, because the Service selector is `app: {{ .Release.Name }}`, `demo-dev-service` only routes to `demo-dev` Pods, and `demo-prod-service` only routes to `demo-prod` Pods. They operate completely independently.

---

### Question 3: How would separate namespaces improve environment isolation?

#### TL;DR
While multiple releases can coexist in the same namespace by naming conventions, using dedicated namespaces (e.g., `dev` and `prod`) provides hard boundaries for security (RBAC), resource limits (ResourceQuotas), network isolation (NetworkPolicies), and blast radius control.

#### Deep Dive & Mechanism
1. **Security & RBAC:**
   - Developers might need `admin` or `edit` permissions in `dev`, but only `view` permissions in `prod`. Kubernetes RBAC RoleBindings are scoped per namespace.
2. **Resource Quotas & Limits:**
   - In a shared namespace, a run-away dev deployment or memory leak could consume all CPU/memory, starving production Pods.
   - `ResourceQuota` and `LimitRange` objects enforce strict boundaries per namespace.
3. **Network Isolation:**
   - Kubernetes `NetworkPolicy` resources can restrict cross-namespace traffic, preventing accidental communication between dev and prod environments.
4. **Secret Management:**
   - Production secrets (API keys, database credentials) are completely segregated from developer access when placed in a restricted production namespace.

---

## Key Takeaways

| Concept | Explanation |
| :--- | :--- |
| Precedence | Later `-f` arguments win; `--set` overrides everything. |
| Resource Naming | Always prefix or namespace resource names with `.Release.Name` to prevent collisions. |
| Isolation | Use separate namespaces for different environments (dev/stage/prod) in real clusters. |
