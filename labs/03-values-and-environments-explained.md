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

3. **How `helm upgrade` Handles Previous Values:**
   - If you run `helm upgrade demo-prod ./charts/nginx-demo` without passing any `-f` or `--set` flags, Helm reuses the values from the previous revision.
   - **However**, as soon as you pass **any** `-f` or `--set` flag, Helm **drops all previous values** and starts from the chart's `values.yaml` defaults plus your new overrides (unless you explicitly pass `--reuse-values`).
   - Using `--reset-values -f <file>` makes intent explicit: it clears all past flags and guarantees the release matches exactly what is declared in your values files.

---

### Question 2: Why can two releases of the same chart coexist?

#### TL;DR

Because each resource's name and selectors incorporate **`{{ .Release.Name }}`**, ensuring that their names and label selectors do not collide in the Kubernetes API.

#### Deep Dive & Mechanism

- In Kubernetes, object identity is uniquely defined by:
  `[Group, Kind, Namespace, Name]`
- If the chart had hardcoded `name: nginx-deployment`, attempting to install a second release (`demo-prod`) in the same namespace would fail with an ownership collision error:

  ```text
  Error: INSTALLATION FAILED: Unable to continue with install: Deployment "nginx-deployment" in namespace "helm-lab" exists and cannot be imported into the current release: invalid ownership metadata; annotation validation error: key "meta.helm.sh/release-name" must equal "demo-prod": current value is "demo-dev"
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

## Break It and Recover — Detailed Walkthrough

### What the challenge asks
>
> Render with `--set service.port=8080`, then with `--set service.port=8080 --set service.targetPort=8080`. Compare the output. Explain why the first can route to NGINX on 80 and the second cannot. Keep targetPort at 80.

#### 1. The Experiment: Case A (`service.port=8080`)

Run:

```bash
helm template demo-dev ./charts/nginx-demo --set service.port=8080 | grep -A 5 "ports:"
```

*Rendered Service output:*

```yaml
  ports:
    - port: 8080
      targetPort: 80
      protocol: TCP
```

**Why this works:**

- `port: 8080` is the front-door listening port exposed by the Kubernetes Service within the cluster.
- `targetPort: 80` is the backend destination port on the Pod.
- Because NGINX inside the container is listening on port 80, the Service successfully forwards incoming requests from `demo-dev-service:8080` to the container on port 80.

---

#### 2. The Experiment: Case B (`service.port=8080 --set service.targetPort=8080`)

Run:

```bash
helm template demo-dev ./charts/nginx-demo --set service.port=8080 --set service.targetPort=8080 | grep -A 5 "ports:"
```

*Rendered Service output:*

```yaml
  ports:
    - port: 8080
      targetPort: 8080
      protocol: TCP
```

**Why this breaks traffic routing:**

- The Service now sends traffic to Pod port 8080.
- However, **nothing is listening on port 8080 inside the container**. Helm values configure Kubernetes resources; they do **not** reconfigure the third-party NGINX binary inside the container image!
- If this configuration were applied to the cluster, any HTTP request hitting the Service would fail immediately with `Connection refused`:

  ```text
  curl: (7) Failed to connect to demo-dev-service port 8080: Connection refused
  ```

---

#### 3. How to Recover

Ensure `service.targetPort` remains aligned with the application container's actual listening port (`80`):

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml | grep -A 5 "ports:"
```

*Output:*

```yaml
  ports:
    - port: 80
      targetPort: 80
      protocol: TCP
```

---

## Key Takeaways

| Concept | Explanation |
| :--- | :--- |
| Precedence | Later `-f` arguments win; `--set` overrides everything. |
| Resource Naming | Always prefix or namespace resource names with `.Release.Name` to prevent collisions. |
| Isolation | Use separate namespaces for different environments (dev/stage/prod) in real clusters. |
