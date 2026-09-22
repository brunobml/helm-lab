# Lab 17: Many releases: Helmfile (and Argo CD ApplicationSet) — Explained

This companion document explores the architectural trade-offs, internal algorithms, and promotion mechanics of managing large multi-chart Kubernetes fleets with Helmfile and Argo CD ApplicationSets.

---

## 1. Fleet Orchestration: The Four Architecture Models

When deploying dozens of services across multiple environments, teams choose between four architectural models:

```text
┌────────────────────────────────────────────────────────────────────────┐
│ 1. Imperative Shell Scripts (e.g. deploy.sh)                          │
│    - Sequence of `helm install` commands.                              │
│    ❌ Fragile, non-idempotent, no drift detection, no DAG.            │
├────────────────────────────────────────────────────────────────────────┤
│ 2. Umbrella Chart Pattern (e.g. shop umbrella)                         │
│    - One parent chart with 20 subcharts as dependencies.              │
│    ❌ Monolithic lifecycle: a failure in one subchart rolls back all. │
│    ❌ Forces all subcharts into a single namespace.                    │
├────────────────────────────────────────────────────────────────────────┤
│ 3. Declarative Orchestration: Helmfile (Push Model)                    │
│    - Multi-release DAG (`needs:`), multi-environment values layering.  │
│    ✅ Granular lifecycles, cross-namespace, on-demand `diff/apply`.   │
├────────────────────────────────────────────────────────────────────────┤
│ 4. GitOps Pull Controller: Argo CD ApplicationSet (Pull Model)        │
│    - Controller generator in-cluster reconciling desired state in Git. │
│    ✅ Continuous self-healing, automated cluster fleet generation.     │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Helmfile Internals: DAG Resolution and Templating

### Directed Acyclic Graph (DAG) Execution

Helmfile does not execute releases sequentially from top to bottom. Instead, it parses all `needs:` declarations and constructs a **Directed Acyclic Graph (DAG)**:

```text
       backend-db        monitoring-probe
           │                    │
           ▼ (needs db)         │ (independent)
       backend-api              │
           │                    │
           ▼ (needs api)        │
       frontend-web ◄───────────┘
```

- **Topological Sorting:** Helmfile determines which releases have zero unsatisfied dependencies and executes them first.
- **Parallelism (`--concurrency N`):** If multiple releases are independent (such as `backend-db` and `monitoring-probe`), Helmfile can install them in parallel.
- **Cycle Detection:** If release A needs B and B needs A, Helmfile immediately aborts before running any `helm` commands, preventing infinite loops.

### The Two-Pass Evaluation Engine in Helmfile v1

Helmfile uses a multi-pass evaluation engine:

1. **Pass 1: Environment Resolution:**
   Helmfile evaluates the first YAML document defining `environments:` and loads the active environment file (e.g. `environments/dev.yaml`).
2. **Pass 2: Manifest & Values Templating:**
   Helmfile processes the second YAML document defining `releases:`. In `.gotmpl` files, template variables (`{{ .Values.namespace }}`) are expanded using the environment values loaded in Pass 1.
3. **Pass 3: Helm Execution:**
   Helmfile invokes the Helm CLI binary (`helm diff`, `helm upgrade --install`) under the hood for each release in topological order.

---

## 3. Values Layering Mechanics

A core strength of Helmfile is **layered values inheritance**. Rather than duplicating large values files for every environment, Helmfile merges values from multiple sources in a well-defined hierarchy:

```text
┌───────────────────────────────────────┐
│ 1. Upstream Chart Default Values      │ (Lowest precedence)
└──────────────────┬────────────────────┘
                   ▼
┌───────────────────────────────────────┐
│ 2. Common Organization Defaults       │ (e.g. values/common.yaml)
└──────────────────┬────────────────────┘
                   ▼
┌───────────────────────────────────────┐
│ 3. Environment Specific Overrides     │ (e.g. environments/prod.yaml)
└──────────────────┬────────────────────┘
                   ▼
┌───────────────────────────────────────┐
│ 4. Release-Specific Dynamic Templates │ (e.g. values/web.yaml.gotmpl)
└──────────────────┬────────────────────┘
                   ▼
┌───────────────────────────────────────┐
│ 5. CLI Set Overrides (--set key=val)  │ (Highest precedence)
└───────────────────────────────────────┘
```

This ensures DRY (Don't Repeat Yourself) configuration: common settings are maintained once, while environment-specific parameters (replicas, hostnames, resource limits) are overlaid cleanly.

---

## 4. The Promotion Workflow: Dev to Prod

The golden rule of modern infrastructure-as-code:

> **Promote by changing versions and values, NEVER by changing chart templates.**

In a multi-environment Helmfile repository, a promotion follows this GitOps workflow:

1. Developer merges code into `main`. CI packages chart `nginx-demo` as version `0.6.0`.
2. Developer updates `helmfile/environments/dev.yaml`:

   ```yaml
   web:
     tag: "0.6.0"
   ```

3. Run `helmfile -e dev diff` and `helmfile -e dev apply`. Test and validate in the development cluster.
4. When ready for production, open a Pull Request updating `helmfile/environments/prod.yaml`:

   ```yaml
   web:
     tag: "0.6.0"
   ```

5. CI executes `helmfile -e prod diff` as a PR comment, showing the exact diff between running production and the proposed release.
6. When the PR merges, CD applies `helmfile -e prod apply`.

---

## 5. Helmfile vs. Argo CD ApplicationSet Comparison

| Capability | Helmfile | Argo CD ApplicationSet |
| :--- | :--- | :--- |
| **Control Plane** | Client-side (CI runner, developer laptop) | Cluster-side (Argo CD controller) |
| **Access Model** | Requires `kubeconfig` with cluster admin access | Operator in cluster pulls Git repository |
| **Drift Correction** | Manual on next `helmfile apply` run | Automatic continuous background self-healing |
| **Local Debugging** | Instant: run `helmfile diff` or `helmfile template` locally | Requires running an in-cluster Argo CD instance |
| **Ephemeral Environments** | Exceptional: create and destroy environments in seconds | Requires creating new Git branches or directories |

**Industry Trend:** Many high-velocity platform teams use **both**:

- **Helmfile** for local development, PR preview environments, and bootstrapping newly provisioned Kubernetes clusters.
- **Argo CD ApplicationSet** for continuous delivery across long-lived production and staging clusters.
