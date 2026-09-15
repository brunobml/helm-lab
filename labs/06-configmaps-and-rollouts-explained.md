# Lab 6: ConfigMaps and rollouts — Explained

[Back to Lab 6: ConfigMaps and rollouts](06-configmaps-and-rollouts.md)

---

## Overview

In Lab 6, you mounted custom HTML into NGINX using a ConfigMap, and implemented the standard Helm pattern for triggering automatic Deployment rollouts via the `checksum/config` Pod-template annotation.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: Why does hashing the ConfigMap change the Deployment's Pod template?

#### TL;DR
Kubernetes Deployments **only trigger a rollout when `spec.template` changes**. Hashing the rendered ConfigMap into an annotation under `spec.template.metadata.annotations` ensures that any configuration change mutates the Pod template, forcing Kubernetes to replace the Pods.

#### Deep Dive & Mechanism
1. **The Native Kubernetes Limitation:**
   - A Deployment manages ReplicaSets. The Deployment controller only creates a new ReplicaSet if the **Pod template (`spec.template`)** is modified (e.g., image tag change, env var change).
   - If you update a ConfigMap or Secret referenced by a volume, the ConfigMap object in Kubernetes is updated, but the Deployment's `spec.template` remains **completely identical**.
   - As a result, the Deployment controller does nothing: no new ReplicaSet is created, and existing Pods continue running with their old configuration or cached process state.
2. **The Helm Solution (`checksum/config`):**
   ```gotemplate
   spec:
     template:
       metadata:
         annotations:
           checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
   ```
   - `include (print $.Template.BasePath "/configmap.yaml") .` renders the exact YAML content of the ConfigMap template.
   - `sha256sum` calculates a cryptographic SHA-256 hash of that rendered text (e.g., `a3579b50...`).
   - When values like `pageContent` change, the generated hash changes.
   - Because this annotation lives inside `spec.template.metadata`, the Deployment controller detects a mutated Pod template and initiates an automated rolling update.

---

### Question 2: How do you distinguish a file update from a Pod replacement?

#### TL;DR
- **Pod replacement:** Creates a brand-new Pod with a new Pod name (e.g., `demo-dev-deployment-79b889cb9c-2pqsr` $\rightarrow$ `demo-dev-deployment-86c5dc48bb-qvx8v`) and a fresh start time / age (`2s`).
- **File update:** The existing Pod name and age remain unchanged (`age: 15m`), but the file content on disk inside the container eventually syncs in the background.

#### Deep Dive & Mechanism
1. **Volume Sync vs. Container Restart:**
   - When a ConfigMap is mounted as a directory (without `subPath`), the `kubelet` syncs updated ConfigMap data to the mounted volume periodically (typically every 60–90 seconds via its sync loop).
   - However, **most software (including NGINX, Python, Java) does not watch the filesystem for changes**. Even if the file updates on disk, the application process retains the old configuration in memory unless restarted or reloaded!
2. **Why a Rolling Update is Superior:**
   - By using the checksum annotation to force a rolling update:
     1. A new Pod is created and passes readiness probes with the new config.
     2. Traffic shifts seamlessly to the new Pod.
     3. The old Pod is safely terminated.
   - This eliminates configuration drift, guarantees zero-downtime reloads, and ensures rollbacks revert both the configuration and the workload together.

---

### Question 3: Why does indentation matter for multiline HTML?

#### TL;DR
In YAML, multiline strings under literal block scalars (`|`) rely on **uniform leading indentation** to determine where the string begins and ends. Improper indentation causes YAML parsing errors or accidentally parses HTML tags as YAML keys.

#### Deep Dive & Mechanism
- Consider this template:
  ```yaml
  data:
    index.html: |
      {{- .Values.pageContent | nindent 4 }}
  ```
- The block scalar indicator `|` tells the YAML parser: "Everything indented further than `index.html` is raw string content."
- Since `data:` is at 0 spaces, `index.html:` is at 2 spaces, its content must be indented by **at least 4 spaces**.
- **What happens if indentation is wrong:**
  - If `nindent 2` is used, the content is indented at the same level as `index.html:`, causing an immediate YAML syntax error:
    ```text
    error converting YAML to JSON: yaml: line 6: mapping values are not allowed in this context
    ```
  - If the multiline string contains `:` (such as in CSS styles like `color: red;`), the YAML parser may mistake the HTML for nested YAML dictionaries!
- Pipelining through `nindent 4` guarantees that every single line of the input text is indented by exactly 4 spaces, regardless of how many lines it contains.

---

## Key Takeaways

| Technique | Purpose |
| :--- | :--- |
| `checksum/config` in Pod template | Triggers rolling updates automatically when ConfigMaps change. |
| Pod Age / Name inspection | Verifies actual Pod replacement rather than passive background file sync. |
| `nindent` with `\|` | Ensures multiline configuration/HTML renders as valid, well-aligned YAML. |
