# Extension: Identity and secrets — Explained

[Back to Extension: Identity and secrets](identity-and-secrets.md)

---

## Overview

In this extension, you decoupled workload identity (`ServiceAccount`) from permissions (`Role`, `RoleBinding`) and external sensitive data (`Secrets`), verifying authorization using `kubectl auth can-i`.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: Why are `serviceAccount.create` and `rbac.create` independent?

#### TL;DR
Because identity (`ServiceAccount`) and permissions (`Role` / `RoleBinding`) are separate architectural layers. An application may need its own identity without needing any Kubernetes API permissions, or an enterprise cluster may mandate using pre-existing security identities provisioned by cluster administrators.

#### Deep Dive & Mechanism
1. **Scenario 1: Identity without RBAC (`serviceAccount.create: true`, `rbac.create: false`):**
   - Cloud providers (AWS IRSA, GCP Workload Identity, Azure Workload Identity) bind Kubernetes ServiceAccounts directly to cloud IAM roles (e.g. allowing an app to read an S3 bucket or Cloud SQL database).
   - In this setup, the application needs a distinct ServiceAccount in Kubernetes, but needs **zero permissions to read the Kubernetes API**!
   - Creating a Role would violate the principle of least privilege.
2. **Scenario 2: Enterprise Pre-provisioned Identities (`serviceAccount.create: false`, `serviceAccount.name: enterprise-sa`):**
   - Many strictly managed production environments forbid Helm charts from creating new ServiceAccounts or Roles.
   - The security team creates a hardened, pre-approved ServiceAccount ahead of time.
   - By decoupling `serviceAccount.create` from `serviceAccount.name`, the chart can seamlessly bind to an existing account without attempting to recreate it.

---

### Question 2: When would a namespaced Role be more appropriate than a ClusterRole?

#### TL;DR
A **namespaced Role** is always appropriate when an application only needs to interact with resources inside its **own namespace** (least privilege). A **ClusterRole** is only required when the application needs cluster-wide permissions (e.g. watching Nodes, reading CRDs, or managing resources across all namespaces).

#### Deep Dive & Mechanism
1. **Blast Radius Control:**
   - A compromised application with a namespaced `Role` can only view or mutate resources within its own namespace (e.g. `helm-lab`).
   - If that same application had a `ClusterRole` bound via `ClusterRoleBinding`, an attacker could read Secrets, delete Deployments, or compromise workloads across **every single namespace** in the cluster.
2. **Multi-Tenancy:**
   - In shared or multi-tenant clusters, application developers are typically not cluster administrators.
   - Standard Kubernetes users have permissions to create namespaced Roles in their project namespace, but lack cluster-wide permissions to create `ClusterRoles` or `ClusterRoleBindings`.
3. **When ClusterRoles ARE Necessary:**
   - Ingress controllers (must watch Services and Ingresses across all namespaces).
   - Monitoring agents (Prometheus node-exporter scraping cluster metrics).
   - GitOps controllers (Argo CD reconciling cluster-wide resources).
   - Workload operators (managing Custom Resources globally).

---

## Break It and Recover — Detailed Walkthrough

### What the challenge asks:
> Reference a nonexistent Secret, observe the Pod configuration error with `kubectl describe pod`, then restore the existing Secret name and upgrade.

#### 1. What to Break
Run `helm upgrade` pointing the `existingSecret` parameter to a secret that does not exist in the cluster:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set existingSecret=nonexistent-secret --wait=false
```

#### 2. The Error Observed
Check the Pod status:
```bash
kubectl get pods -n helm-lab -l app=demo-dev
```
*Output:*
```text
NAME                                   READY   STATUS                       RESTARTS   AGE
demo-dev-deployment-7bb9cf9475-x2n4p   1/1     Running                      0          15m
demo-dev-deployment-55d8f6cc9b-p2k4v   0/1     CreateContainerConfigError   0          25s
```

#### 3. Diagnose the Root Cause
Inspect the Pod events:
```bash
kubectl describe pods -n helm-lab -l app=demo-dev
```
*Events log:*
```text
Warning  Failed     10s (x3 over 35s)   kubelet  Error: secret "nonexistent-secret" not found
```
**Why this happened:**
- The kubelet must resolve and mount all referenced Secrets and environment variables before the container process can start.
- Because `nonexistent-secret` does not exist in the `helm-lab` namespace, the kubelet halts container initialization with `CreateContainerConfigError`.
- Existing healthy Pods continue serving traffic because the new Pod never reached `Ready`.

#### 4. How to Recover
Restore the valid secret name (`demo-secret`):

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set existingSecret=demo-secret --wait --timeout 120s
```

Verify that the new Pod starts and mounts the Secret successfully:
```bash
kubectl get pods -n helm-lab -l app=demo-dev
kubectl exec -n helm-lab deployment/demo-dev-deployment -- printenv LAB_TOKEN
```
*Output:*
```text
NAME                                   READY   STATUS    RESTARTS   AGE
demo-dev-deployment-85df649f88-k8d12   1/1     Running   0          10s

super-secret-token-value
```

---

## Key Takeaways

| Concept | Golden Rule |
| :--- | :--- |
| ServiceAccount vs RBAC | Keep them decoupled. Applications often need cloud identity without K8s API rights. |
| Role vs ClusterRole | Always default to a namespaced `Role` unless cluster-wide scope is strictly required. |
| Secrets in Values | Never put raw secret values in `values.yaml` or Git. Use `existingSecret` references. |
