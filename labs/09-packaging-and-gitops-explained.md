# Lab 9: Packaging and GitOps — Explained

[Back to Lab 9: Packaging and GitOps](09-packaging-and-gitops.md)

---

## Overview

In Lab 9, you packaged your chart into an immutable `.tgz` artifact, published and inspected it via OCI registries, and learned how GitOps engines like Argo CD treat Helm as a templating engine rather than a release manager.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: What is the difference between a chart archive and a container image?

#### TL;DR
- A **container image** packages binary executables, dependencies, OS libraries, and filesystem layers to run a container (e.g. `nginx:1.30.4-alpine`).
- A **chart archive** packages declarative Kubernetes configuration templates, default values, and metadata that instruct Kubernetes *how* to deploy and manage that container in a cluster.

#### Deep Dive & Mechanism
1. **Container Image:**
   - Built with `docker build`.
   - Contains compiled application binaries, runtime interpreters, and shared libraries.
   - Stored in container registries (Docker Hub, GHCR, ECR, GCR).
   - Executed by the container runtime (`containerd`, `CRI-O`) on Kubernetes worker nodes.
2. **Helm Chart Archive (`.tgz`):**
   - Built with `helm package`.
   - Contains pure text files: Go templates, YAML files, JSON schemas, documentation.
   - Contains **zero executable binary code**.
   - With Helm 3, chart archives are stored in the **exact same OCI registries** as container images using OCI media types (`application/vnd.cncf.helm.chart.content.v1.tar+gzip`).
   - Evaluated by the Helm client or GitOps controller to generate Kubernetes API manifests.

---

### Question 2: Why is an explicit artifact version useful?

#### TL;DR
An explicit, immutable SemVer version (e.g. `0.2.0`) guarantees **idempotence, auditability, and reliable rollbacks**. Without it, teams cannot know what code was deployed at any given point in time.

#### Deep Dive & Mechanism
1. **The Risk of Mutable Tags (like `latest`):**
   - In container images or chart archives, mutable tags can be overwritten. If a deployment fails on Thursday, you cannot reproduce Tuesday's environment if `latest` was overwritten on Wednesday.
2. **Immutable Artifacts in Production:**
   - When a chart version is bumped (e.g., `0.1.0` $\rightarrow$ `0.2.0`) and packaged, the resulting archive has a unique SHA-256 cryptographic digest.
   - In OCI registries, pushing the same version tag twice can be blocked (immutability enforcement).
   - In GitOps (Argo CD, Flux), referencing an exact chart version ensures that identical manifests are applied across staging, testing, and production clusters.

---

### Question 3: Who owns deployment history when Argo CD renders a Helm chart?

#### TL;DR
**Argo CD and Git own the deployment history**, NOT Helm. Helm is used purely as a client-side templating engine (`helm template`).

#### Deep Dive & Mechanism
1. **How Helm Deploys Directly (`helm install` / `upgrade`):**
   - When you run Helm CLI commands, Helm creates and maintains versioned Secret objects in the cluster (`sh.helm.release.v1.demo-dev.v1`).
   - Release history, revisions, values, and rollbacks are stored and managed by Helm inside those Secrets.
2. **How Argo CD / GitOps Deploys Helm Charts:**
   - Argo CD clones your Git repository (or pulls the OCI chart).
   - Argo CD runs `helm template` internally with your specified values file (`values-dev.yaml`).
   - Argo CD takes the resulting raw Kubernetes YAML and applies it using server-side apply or `kubectl apply`.
   - **Crucial Consequence:**
     - Helm release Secrets are **never created** in the cluster.
     - Running `helm list` or `helm history` will show **nothing**.
     - History and rollbacks are managed entirely via **Git commits** (`git revert`, `git checkout`) and Argo CD Application revisions.
     - You cannot use `helm rollback` on an Argo CD-managed deployment!

---

## Key Takeaways

| Concept | Explanation |
| :--- | :--- |
| Image vs. Chart | Images package the software; charts package the deployment instructions. |
| Immutability | Always version chart archives with immutable Semantic Versioning. |
| GitOps Ownership | In GitOps, Git is the single source of truth; Helm is just a template renderer. |
