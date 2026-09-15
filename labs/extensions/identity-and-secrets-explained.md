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

## Key Takeaways

| Concept | Golden Rule |
| :--- | :--- |
| ServiceAccount vs RBAC | Keep them decoupled. Applications often need cloud identity without K8s API rights. |
| Role vs ClusterRole | Always default to a namespaced `Role` unless cluster-wide scope is strictly required. |
| Secrets in Values | Never put raw secret values in `values.yaml` or Git. Use `existingSecret` references. |
