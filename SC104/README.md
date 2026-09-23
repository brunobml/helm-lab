# SC104: Developing Helm Charts Study Guide

This guide maps the complete curriculum of the Linux Foundation **SC104: Developing Helm Charts** SkillCred certification directly to the hands-on exercises in this repository.

This laboratory curriculum provides **100% coverage** of all domains and competencies evaluated by the SC104 exam, while also extending into advanced production and enterprise operations.

---

## 1. Exam Overview

- **Certification Name:** Developing Helm Charts (SC104)
- **Issuing Body:** The Linux Foundation
- **Credential Type:** SkillCred (hands-on performance and multiple-choice micro-credential)
- **Exam Duration:** 45 minutes
- **Environment:** Online, browser-based terminal and multiple-choice interface
- **Expiry:** Does not expire once achieved
- **Domain Weight:** Developing Helm Charts — **100%**

---

## 2. Competency-to-Lab Mapping Matrix

The SC104 certification evaluates seven core competencies. The table below details what is tested, the critical CLI commands, and the corresponding hands-on labs in this repository.

| Competency | Exam Objectives & Concepts | Key Commands & Files | Corresponding Labs |
| :--- | :--- | :--- | :--- |
| **1. Create charts using basic templating** | • Initialize charts with `helm create`<br>• Understand chart anatomy (`Chart.yaml`, `values.yaml`, `templates/`, `.helmignore`)<br>• Template syntax, actions, and built-ins (`.Values`, `.Release`, `.Chart`, `.Files`)<br>• Control flow: `if / else / end`<br>• Scoping and loops: `with`, `range`<br>• Template functions & pipelines: `default`, `quote`, `toYaml`, `indent`, `nindent`<br>• Named templates (`define`, `include` vs `template`)<br>• Standard Kubernetes labels in `_helpers.tpl`<br>• Post-install guidance via `NOTES.txt` | • `helm create <name>`<br>• `templates/_helpers.tpl`<br>• `templates/NOTES.txt`<br>• `.helmignore` | • [Lab 0: Chart Creation](file:///home/bleite/repos/helm-lab/labs/00-chart-creation.md)<br>• [Lab 1: First Chart](file:///home/bleite/repos/helm-lab/labs/01-first-chart.md)<br>• [Lab 4: Template Logic](file:///home/bleite/repos/helm-lab/labs/04-template-logic.md)<br>• [Lab 5: Helpers and Labels](file:///home/bleite/repos/helm-lab/labs/05-helpers-and-labels.md)<br>• [Lab 7: NOTES.txt](file:///home/bleite/repos/helm-lab/labs/07-validation-and-tests.md) |
| **2. Customize existing charts** | • Inspect charts before installing (`show chart/values/readme/all`)<br>• Override values using files (`-f` / `--values`) and flags (`--set`, `--set-string`, `--set-file`, `--set-json`)<br>• Understand value precedence hierarchy and deep merging rules<br>• Manage upgrades and state (`--reuse-values` vs `--reset-values`)<br>• Diff rendered manifests before applying changes | • `helm show chart <chart>`<br>• `helm show values <chart>`<br>• `helm upgrade <rel> <chart> -f <file>`<br>• `helm diff upgrade <rel> <chart>` | • [Lab 2: Release Lifecycle](file:///home/bleite/repos/helm-lab/labs/02-release-lifecycle.md)<br>• [Lab 3: Values & Environments](file:///home/bleite/repos/helm-lab/labs/03-values-and-environments.md)<br>• [Lab 14: Third-Party Charts](file:///home/bleite/repos/helm-lab/labs/14-consuming-third-party-charts.md) |
| **3. Manage chart dependencies** | • Declare dependencies in `Chart.yaml` (`name`, `version`, `repository`, `alias`, `condition`, `tags`)<br>• Update and synchronize dependencies (`helm dep update`, `helm dep build`)<br>• Lockfile management (`Chart.lock`) and integrity checksums<br>• Pass values to subcharts using the subchart key<br>• Share cross-cutting configurations with `global:` values<br>• Construct umbrella charts | • `helm dependency list`<br>• `helm dependency update`<br>• `helm dependency build`<br>• `Chart.lock` | • [Lab 8: Dependencies](file:///home/bleite/repos/helm-lab/labs/08-dependencies.md)<br>• [Lab 13: Capstone Umbrella](file:///home/bleite/repos/helm-lab/labs/13-capstone.md) |
| **4. Use chart hooks** | • Understand hook execution phases (`pre-install`, `post-install`, `pre-upgrade`, `post-upgrade`, `pre-delete`, `post-delete`, `pre-rollback`, `post-rollback`, `test`)<br>• Order hooks with `helm.sh/hook-weight`<br>• Control resource cleanup with `helm.sh/hook-delete-policy`<br>• Hook failure behavior and rollback interaction | • `helm.sh/hook`<br>• `helm.sh/hook-weight`<br>• `helm.sh/hook-delete-policy`<br>• `helm test <release>` | • [Lab 7: Test Hooks](file:///home/bleite/repos/helm-lab/labs/07-validation-and-tests.md)<br>• [Lab 10: Hooks & Recovery](file:///home/bleite/repos/helm-lab/labs/10-hooks-and-failure-recovery.md)<br>• [Lab 13: Capstone Hook Jobs](file:///home/bleite/repos/helm-lab/labs/13-capstone.md) |
| **5. Understand types of charts** | • Differentiate `type: application` vs `type: library` in `Chart.yaml`<br>• Author library charts containing reusable helper templates<br>• Import and execute library chart definitions in dependent charts<br>• Verify that library charts cannot be installed independently (`helm install` rejection)<br>• Design umbrella/wrapper charts | • `Chart.yaml` (`type:` field)<br>• Library helper definitions<br>• Umbrella chart architectures | • [Lab 0: Chart Anatomy](file:///home/bleite/repos/helm-lab/labs/00-chart-creation.md)<br>• [Lab 11: Library Charts](file:///home/bleite/repos/helm-lab/labs/11-advanced-templating-and-library-charts.md)<br>• [Lab 13: Capstone Umbrella](file:///home/bleite/repos/helm-lab/labs/13-capstone.md) |
| **6. Test and troubleshoot** | • Validate chart syntax and style with `helm lint`<br>• Render templates locally with `helm template`<br>• Perform client and server dry-runs with `--debug`<br>• Enforce schema constraints with `values.schema.json`<br>• Execute release smoke tests using `helm test`<br>• Inspect live release metadata (`status`, `get values`, `get manifest`, `history`)<br>• Recover from failed releases (`--atomic`, `helm rollback`) | • `helm lint <chart>`<br>• `helm template <rel> <chart>`<br>• `helm install --dry-run=server`<br>• `values.schema.json`<br>• `helm history <release>`<br>• `helm rollback <release> <rev>` | • [Lab 1: Linting & Rendering](file:///home/bleite/repos/helm-lab/labs/01-first-chart.md)<br>• [Lab 2: Release Inspection](file:///home/bleite/repos/helm-lab/labs/02-release-lifecycle.md)<br>• [Lab 7: JSON Schema & Tests](file:///home/bleite/repos/helm-lab/labs/07-validation-and-tests.md)<br>• [Lab 10: Atomic Rollbacks](file:///home/bleite/repos/helm-lab/labs/10-hooks-and-failure-recovery.md)<br>• [Lab 12: Unit Testing & CI](file:///home/bleite/repos/helm-lab/labs/12-secrets-signing-and-ci.md)<br>• [Lab 18: Deep Troubleshooting](file:///home/bleite/repos/helm-lab/labs/18-helm-internals-and-advanced-operations.md) |
| **7. Publish charts** | • Package charts into archives with `helm package`<br>• Distinguish chart `version` from application `appVersion`<br>• Index classic HTTP repositories with `helm repo index`<br>• Publish and consume charts via OCI registries (`oci://`)<br>• Sign packages with GPG keys and verify provenance files (`.prov`) | • `helm package <chart>`<br>• `helm repo index <dir>`<br>• `helm push <pkg>.tgz oci://...`<br>• `helm pull oci://...`<br>• `helm verify <pkg>.tgz` | • [Lab 9: Packaging & OCI](file:///home/bleite/repos/helm-lab/labs/09-packaging-and-gitops.md)<br>• [Lab 12: Provenance Signing](file:///home/bleite/repos/helm-lab/labs/12-secrets-signing-and-ci.md) |

---

## 3. Essential Command Quick Reference

The SC104 exam requires quick, error-free CLI execution. Memorize these fundamental commands and syntax patterns:

### Chart Lifecycle & Inspection

```bash
# Create a chart from default scaffold
helm create my-chart

# Check syntax, schema, and best-practice rules
helm lint ./my-chart

# Render templates locally to inspect YAML output
helm template my-release ./my-chart

# Test installation against API server without persisting resources
helm install my-release ./my-chart --dry-run=server --debug

# Install or upgrade idempotently
helm upgrade --install my-release ./my-chart --namespace my-ns --create-namespace

# Inspect an existing or remote chart
helm show chart <repo>/<chart>
helm show values <repo>/<chart>
helm show readme <repo>/<chart>
helm show all <repo>/<chart>
```

### Values & Precedence

```bash
# Override values with one or more files (later files take precedence)
helm upgrade my-release ./my-chart -f values.yaml -f values-prod.yaml

# Command-line overrides (highest precedence)
helm upgrade my-release ./my-chart --set replicaCount=3 --set-string env.NODE_ENV=production

# Load a whole file into a value key
helm upgrade my-release ./my-chart --set-file configData=config.json
```

### Dependencies & Subcharts

```bash
# List dependencies declared in Chart.yaml
helm dependency list ./my-chart

# Download dependencies and generate/update Chart.lock
helm dependency update ./my-chart

# Build dependencies from an existing Chart.lock without checking for newer versions
helm dependency build ./my-chart
```

### Hooks & Testing

```bash
# Run test pods defined with 'helm.sh/hook: test'
helm test my-release

# Run test pods and stream log output
helm test my-release --logs

# Roll back automatically if install/upgrade or hooks fail
helm upgrade my-release ./my-chart --atomic --timeout 3m
```

### Release State & History

```bash
# List all releases across all namespaces
helm list -A

# Check revision history
helm history my-release

# Inspect user-supplied values vs computed values
helm get values my-release
helm get values my-release --all

# Inspect installed Kubernetes manifests
helm get manifest my-release

# Roll back to a specific revision
helm rollback my-release 2
```

### Packaging & Distribution

```bash
# Package a chart into a .tgz archive
helm package ./my-chart

# Update index.yaml for a classic HTTP repository
helm repo index . --url https://example.com/charts

# Push package to an OCI registry
helm push my-chart-0.1.0.tgz oci://registry-1.docker.io/myorg

# Pull package from an OCI registry
helm pull oci://registry-1.docker.io/myorg/my-chart --version 0.1.0

# Sign a package using a private GPG key
helm package --sign --key "Key Name" --keyring ~/.gnupg/secring.gpg ./my-chart

# Verify chart provenance before installing
helm verify my-chart-0.1.0.tgz --keyring ~/.gnupg/pubring.gpg
```

---

## 4. Key Traps and Exam Pitfalls

Every lab in this repository includes a dedicated **Break and recover** exercise. The following failure patterns are common testing targets on SC104:

1. **The Scope-Shift Trap (`with` and `range`):**
   - In Go templates, entering a `{{ with .Values.image }}` or `{{ range .Values.ports }}` block changes the context (`.`).
   - Accessing top-level variables like `.Release.Name` inside that block fails unless prefixed with the root variable `$` (e.g., `{{ $.Release.Name }}`).
2. **Indentation Failures (`indent` vs `nindent`):**
   - Piping a YAML block via `toYaml | indent 4` produces an invalid indentation on the first line if preceded by newline syntax.
   - Always use `toYaml | nindent 4` to ensure every line, including the first, is correctly padded.
3. **Data Type Mismatches with `--set`:**
   - `--set port=8080` parses `8080` as an integer or float. If the chart schema or template expects a string, the release fails.
   - Use `--set-string port="8080"` to enforce string parsing.
4. **Subchart Value Scoping:**
   - Values passed to a dependency chart must be nested under the subchart name (or alias) in the parent `values.yaml`:

     ```yaml
     shop-db:
       persistence:
         enabled: true
     ```

   - Only keys defined under `global:` are passed directly to all subcharts.
5. **The Missing `Chart.lock` Trap:**
   - Running `helm dependency build` fails if `Chart.lock` does not exist.
   - Run `helm dependency update` first to generate `Chart.lock` and download archives into `charts/`.
6. **Library Chart Install Errors:**
   - Running `helm install` or `helm template` on a chart with `type: library` fails with `cannot be installed`.
   - Library charts are strictly templates for dependencies; they cannot produce release manifests on their own.
7. **The Hook Resource Isolation Trap:**
   - Kubernetes manifests annotated with `helm.sh/hook` are not tracked as part of the release's main manifest list.
   - They do not appear in `helm get manifest`, and they are not automatically deleted on `helm rollback` unless managed by a `helm.sh/hook-delete-policy`.
8. **The `--reuse-values` Trap:**
   - Using `helm upgrade --reuse-values` preserves past values but ignores any new default keys introduced in the new chart version.
   - In production workflows, prefer maintaining explicit, version-controlled values files.

---

## 5. Beyond SC104: Senior Operational Skills

While SC104 validates chart authoring fundamentals, Labs 10–18 of this laboratory prepare you for senior DevOps and platform engineering responsibilities:

- **CRD Lifecycle & Traps ([Lab 15](file:///home/bleite/repos/helm-lab/labs/15-crds-and-operators.md)):** Overcoming the limitation that `helm upgrade` ignores files in `crds/`, managing operator CRDs, and avoiding silent field drops.
- **Production Hardening ([Lab 16](file:///home/bleite/repos/helm-lab/labs/16-production-hardening-and-best-practices.md)):** Meeting the Pod Security `restricted` standard, configuring non-root containers, `readOnlyRootFilesystem`, PodDisruptionBudgets, NetworkPolicies, and CI OpenAPI linting with `kubeconform`.
- **Fleet Orchestration ([Lab 17](file:///home/bleite/repos/helm-lab/labs/17-multi-release-helmfile-and-gitops.md)):** Managing multi-release dependencies, DAG scheduling, and layered environment promotion using Helmfile and Argo CD ApplicationSets.
- **Helm Internals & 3-Way Merge ([Lab 18](file:///home/bleite/repos/helm-lab/labs/18-helm-internals-and-advanced-operations.md)):** Decoding base64 gzip release Secrets, mastering the three-way strategic merge patch, adopting unmanaged resources with `--take-ownership`, and migrating deprecated APIs with `mapkubeapis`.

---

## 6. Recommended SC104 Study Plan

To prepare efficiently for the 45-minute exam, work through the labs in this sequence:

1. **Foundations (Day 1):** Complete [Lab 0](file:///home/bleite/repos/helm-lab/labs/00-chart-creation.md), [Lab 1](file:///home/bleite/repos/helm-lab/labs/01-first-chart.md), and [Lab 2](file:///home/bleite/repos/helm-lab/labs/02-release-lifecycle.md). Focus on directory anatomy, `helm lint`, `helm template`, and basic install/upgrade/rollback.
2. **Templating Mastery (Day 2):** Complete [Lab 4](file:///home/bleite/repos/helm-lab/labs/04-template-logic.md) and [Lab 5](file:///home/bleite/repos/helm-lab/labs/05-helpers-and-labels.md). Drill `if/else`, `range`, `with`, `_helpers.tpl`, and `toYaml | nindent`.
3. **Values & Validation (Day 3):** Complete [Lab 3](file:///home/bleite/repos/helm-lab/labs/03-values-and-environments.md) and [Lab 7](file:///home/bleite/repos/helm-lab/labs/07-validation-and-tests.md). Practice value hierarchy, `values.schema.json`, and `NOTES.txt`.
4. **Dependencies, Types & Publishing (Day 4):** Complete [Lab 8](file:///home/bleite/repos/helm-lab/labs/08-dependencies.md), [Lab 9](file:///home/bleite/repos/helm-lab/labs/09-packaging-and-gitops.md), and [Lab 11](file:///home/bleite/repos/helm-lab/labs/11-advanced-templating-and-library-charts.md). Practice subchart locks, library charts, `helm package`, and OCI push/pull.
5. **Hooks & Synthesis (Day 5):** Complete [Lab 10](file:///home/bleite/repos/helm-lab/labs/10-hooks-and-failure-recovery.md) and review [Lab 13](file:///home/bleite/repos/helm-lab/labs/13-capstone.md). Practice hook weights, delete policies, and `--atomic` rollbacks.
