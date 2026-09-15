# Lab 0: Chart creation — Explained

[Back to Lab 0: Chart creation](00-chart-creation.md)

---

## Overview

In Lab 0, you learned how to scaffold a new Helm chart with `helm create`, explored the generated files, and stripped the heavy boilerplate to build a clean starter chart from first principles.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: What is the difference between `version` and `appVersion` in `Chart.yaml`?

#### TL;DR
- **`version`** is the version of the **Helm chart itself** (the packaging, templates, and default values). It **must** follow strict Semantic Versioning (`MAJOR.MINOR.PATCH`, e.g., `0.1.0`).
- **`appVersion`** is the version of the **underlying application or container image** being deployed (e.g., NGINX `1.30.4`). It does not have to follow SemVer and is purely descriptive.

#### Deep Dive & Mechanism
1. **Chart `version` (SemVer required):**
   - Helm uses `version` for dependency resolution, repository indexing (`index.yaml`), OCI tag management, and package archiving.
   - When you run `helm package`, Helm names the resulting archive `<chart-name>-<version>.tgz` (e.g., `nginx-demo-0.1.0.tgz`).
   - If `version` is not valid SemVer (e.g., `1` or `latest`), `helm lint` and `helm package` will fail with an error:
     ```text
     [ERROR] Chart.yaml: version "1" is not a valid SemVer
     ```
   - **When to bump `version`:** Every single time you change anything in the chart—whether you edited a template, added a default value, or bumped `appVersion`.

2. **Application `appVersion` (Informational):**
   - `appVersion` is metadata intended for human operators to know which software version is packaged inside.
   - In Helm templates, it is exposed as `.Chart.AppVersion`. Many charts use it to set default container image tags:
     ```yaml
     image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
     ```
   - **Why quotes matter:** In YAML, `appVersion: 1.10` is parsed as a floating-point number (`1.1`). Always quote `appVersion: "1.10"` or `appVersion: "1.30.4"` to ensure it is treated as a string.

---

### Question 2: What does `.helmignore` do when running `helm package`?

#### TL;DR
`.helmignore` specifies file and directory patterns that Helm must exclude when packaging the chart into a `.tgz` archive or rendering templates. It functions identically to `.gitignore` or `.dockerignore`.

#### Deep Dive & Mechanism
- When Helm builds an archive via `helm package ./charts/nginx-demo`, it packages every file in the chart directory into a compressed tarball.
- Without `.helmignore`, accidental files would be bundled into the release artifact:
  - Local editor configurations (`.vscode/`, `.idea/`)
  - Git repository files (`.git/`)
  - OS metadata (`.DS_Store`, `Thumbs.db`)
  - Temporary backup or scratch files (`*.bak`, `*.swp`)
  - Local test fixtures or CI scripts
- **Why this matters for security and size:**
  - Bloated chart archives slow down downloads from OCI registries or chart repos.
  - Sensitive files (such as local `.env` files or certificates used for testing) could be inadvertently published to public registries if not ignored.

---

### Question 3: Why did we delete `templates/*` instead of using the generated boilerplate immediately?

#### TL;DR
`helm create` produces an enterprise-ready starter template containing dozens of advanced features (Ingress, ServiceAccount, HPA, PodDisruptionBudgets, complex helper macros, test hooks). While useful as a reference, starting with all of this at once obscures how basic templating works and makes learning frustrating.

#### Deep Dive & Mechanism
1. **The Boilerplate Trap:**
   - Beginners who try to modify a default `helm create` chart frequently get stuck debugging complex YAML indentation errors, nested `_helpers.tpl` functions, and selector label immutability before they even understand how `.Values` maps to a Pod.
2. **First-Principles Learning:**
   - By starting with only a minimal `deployment.yaml` and `service.yaml`, every single line in the chart is understood.
   - In subsequent labs, you will incrementally implement:
     - Scoping and loops in **Lab 4**
     - Custom helpers in **Lab 5**
     - ConfigMap hash rollouts in **Lab 6**
     - Validation schemas and test hooks in **Lab 7**
     - Subchart composition in **Lab 8**
     - Packaging and OCI distribution in **Lab 9**
   - When you build each capability yourself, you truly understand *why* the boilerplate is structured the way it is.

---

## Key Takeaways

| Concept | Golden Rule |
| :--- | :--- |
| `version` | Must follow SemVer (`x.y.z`). Increment every time chart files change. |
| `appVersion` | Represents the application version. Always wrap in quotes. |
| `.helmignore` | Keeps packaged charts lean and prevents leaking sensitive/local files. |
| Boilerplate | In production, start small and build up templates incrementally. |
