# Lab 7: Validation and tests — Explained

[Back to Lab 7: Validation and tests](07-validation-and-tests.md)

---

## Overview

In Lab 7, you added fail-fast input validation via `values.schema.json`, created post-deployment integration tests using Helm test hooks (`templates/tests/http.yaml`), and customized post-install user guidance with `NOTES.txt`.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: What can schema validation catch that rendering alone does not?

#### TL;DR
`helm template` only verifies that Go template syntax is correct and yields valid YAML. `values.schema.json` validates **business constraints, ranges, types, and required inputs** before rendering or cluster submission even begins.

#### Deep Dive & Mechanism
1. **Silent Logical Errors in `helm template`:**
   - If a user passes `replicaCount: -1`, `helm template` happily produces:
     ```yaml
     spec:
       replicas: -1
     ```
     This syntax is valid YAML, but applying it causes Kubernetes to fail or behave unpredictably.
   - If a user passes `service.port: 70000`, `helm template` outputs valid YAML, but TCP port numbers must be between 1 and 65535.
   - If a user accidentally passes a string for an integer (`replicaCount: "two"`), rendering might produce unquoted invalid types or silent empty values.
2. **Fail-Fast with JSON Schema:**
   - Helm 3 natively supports [JSON Schema Draft-07](https://json-schema.org/draft-07/schema#).
   - When `values.schema.json` exists, Helm validates all user-supplied values against the schema during `helm lint`, `helm template`, `helm install`, and `helm upgrade`.
   - Any violation aborts execution immediately with clear, actionable diagnostics:
     ```text
     Error: values don't meet the specifications of the schema(s) in the following chart(s):
     nginx-demo:
     - at '/replicaCount': minimum: got -1, want 0
     - at '/service/port': maximum: got 70,000, want 65,535
     ```

---

### Question 2: What can an HTTP test catch that linting does not?

#### TL;DR
Linting only analyzes static text files on your local machine. An HTTP test hook runs **live inside the Kubernetes cluster** and verifies network connectivity, DNS resolution, Service routing, and application health.

#### Deep Dive & Mechanism
- **What `helm lint` validates:**
  - `Chart.yaml` has required fields (name, version).
  - Values match `values.schema.json`.
  - Templates render without Go template syntax errors.
- **What `helm lint` CANNOT detect:**
  - Can the container actually pull its image?
  - Did the application crash during boot?
  - Does the Service selector actually match the Pod labels?
  - Is CoreDNS resolving the internal service name (`demo-dev-service`)?
  - Is the application listening on the port that `targetPort` routes to?
  - Are firewall rules / NetworkPolicies blocking traffic?
- **How `helm test` bridges the gap:**
  - By deploying an ephemeral Pod annotated with `"helm.sh/hook": test`, Helm runs real client requests (`wget http://demo-dev-service:80/`) inside the cluster network.
  - If the test fails, Helm reports a non-zero exit code and displays logs, giving CI/CD pipelines automated verification of end-to-end functionality.

---

### Question 3: Why is `replicaCount: 0` valid even though the HTTP test would then fail?

#### TL;DR
`replicaCount: 0` is a valid, intentional administrative state in Kubernetes (used for maintenance, decommissioning, or scaled-to-zero workloads). The schema validates configuration **validity**, whereas the test validates **traffic availability**.

#### Deep Dive & Mechanism
1. **Schema Role (Configuration Boundaries):**
   - The schema sets `"replicaCount": { "minimum": 0 }`.
   - Setting `replicas: 0` is completely valid in Kubernetes: it safely stops all Pods without deleting the Deployment or Helm release.
   - For example, you might scale an application to 0 replicas overnight to save cloud costs in staging, or during an offline database migration.
2. **Test Hook Role (Operational Health):**
   - When replicas is 0, the Deployment has no running Pods, so `demo-dev-service` has zero endpoints in its EndpointSlice.
   - When `helm test` executes:
     ```bash
     wget -qO- --timeout=10 http://demo-dev-service:80/
     ```
     The HTTP connection times out or is rejected.
   - The test correctly reports failure: traffic cannot be served when replicas are 0.
   - This distinction highlights why both tools are necessary: schema validation enforces acceptable input ranges; chart tests verify that running workloads satisfy operational expectations.

---

## Key Takeaways

| Validation Layer | When It Runs | What It Verifies |
| :--- | :--- | :--- |
| `values.schema.json` | Pre-render (Client) | Types, ranges, required fields, value constraints. |
| `helm lint` | Pre-render (Client) | Chart metadata, syntax, template correctness. |
| `helm test` | Post-deployment (Cluster) | In-cluster DNS, network routing, application response. |
