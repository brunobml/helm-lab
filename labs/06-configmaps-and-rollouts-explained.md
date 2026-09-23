# Lab 6: ConfigMaps and rollouts — Explained

[Back to Lab 6: ConfigMaps and rollouts](06-configmaps-and-rollouts.md)

---

## Overview

In Lab 6, you mounted custom HTML into NGINX using a ConfigMap, and implemented the standard Helm pattern for triggering automatic Deployment rollouts via the `checksum/config` Pod-template annotation.

Below are in-depth explanations and answers for the questions posed in the **Explain** and **Check your understanding** sections.

---

### Question 1: How does `pageContent` become a file inside NGINX?

#### TL;DR

Helm places the value of `pageContent` into the `data.index.html` key of a `ConfigMap`. In the Deployment, that ConfigMap is declared as a `volume`, and that volume is mounted into the NGINX container at `/usr/share/nginx/html`. Kubernetes automatically projects the ConfigMap key as a physical file on the container filesystem.

#### Deep Dive & Mechanism

1. **The ConfigMap Template (`templates/configmap.yaml`):**
   Helm evaluates `.Values.pageContent` and renders it under `data:` with key `index.html`:

   ```yaml
   apiVersion: v1
   kind: ConfigMap
   metadata:
     name: {{ .Release.Name }}-page
   data:
     index.html: |
       {{- .Values.pageContent | nindent 4 }}
   ```

2. **The Pod Volume Declaration (`spec.template.spec.volumes`):**
   The Deployment declares a volume backed by the ConfigMap:

   ```yaml
   volumes:
     - name: html
       configMap:
         name: {{ .Release.Name }}-page
   ```

3. **The Container Mount (`spec.template.spec.containers[0].volumeMounts`):**
   The volume is mounted into NGINX's default web directory:

   ```yaml
   volumeMounts:
     - name: html
       mountPath: /usr/share/nginx/html
       readOnly: true
   ```

   When the container starts, `kubelet` creates a volume populated with `index.html`, and mounts it over `/usr/share/nginx/html`. NGINX serves this file whenever an HTTP request arrives for `/`.

---

### Question 2: What connects `volumeMounts` to `volumes`?

#### TL;DR

The **`name`** field. Both `spec.template.spec.volumes[].name` and `spec.template.spec.containers[].volumeMounts[].name` must match exactly (e.g. `name: html`).

#### Deep Dive & Mechanism

- `volumes` defines **what storage exists** at the Pod level (ConfigMap, Secret, PersistentVolumeClaim, emptyDir, hostPath).
- `volumeMounts` defines **where inside a specific container** that storage is attached and whether it is read-only or read-write.
- Because a Pod can contain multiple containers and multiple volumes, Kubernetes pairs them using the unique volume `name`. If `volumeMounts[0].name` does not match any entry in `spec.volumes`, the Kubernetes API server rejects the Deployment with a validation error (`spec.template.spec.containers[0].volumeMounts[0].name: Not found: "..."`).

---

### Question 3: Why does the checksum belong under `spec.template.metadata`?

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
   - Because this annotation lives inside `spec.template.metadata`, the Deployment controller detects a mutated Pod template and initiates an automated rolling update. Placing the checksum at root `metadata.annotations` does *not* roll the Pods because it does not alter `spec.template`.

---

### Question 4: Does seeing updated HTML prove that a Pod was replaced?

#### TL;DR

**No.** Kubernetes periodically synchronizes mounted ConfigMap files to running containers in the background without restarting or replacing Pods. Seeing updated HTML only proves that the file on disk changed; verifying a rollout requires checking the Pod names, Pod IDs, or creation age.

#### Deep Dive & Mechanism

1. **Volume Sync vs. Container Restart:**
   - When a ConfigMap is mounted as a directory (without `subPath`), `kubelet` syncs updated ConfigMap data to the mounted volume periodically (typically every 60–90 seconds via its sync loop).
   - For **static content** (like NGINX reading `index.html` from disk on each HTTP request), the updated file is served immediately once the kubelet syncs it to disk—even though the Pod was never restarted!
   - However, for **application configuration read at startup** (such as `nginx.conf`, database connection pools, or environment variables in Python/Java/Go), the process retains the old configuration in memory unless restarted or reloaded.
2. **Why a Rolling Update is Superior:**
   - By using the checksum annotation to force a rolling update:
     1. A new Pod is created and passes readiness probes with the new config.
     2. Traffic shifts seamlessly to the new Pod.
     3. The old Pod is safely terminated.
   - This eliminates configuration drift, enables zero-downtime reloads, and ensures rollbacks revert both the configuration and the workload together.

---

### Question 5: Why does indentation matter for multiline HTML?

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

## Break It and Recover — Detailed Walkthrough

### What the challenge asks
>
> Move the checksum to the Deployment's top-level `metadata.annotations` and upgrade once. Record the Pod name. Change HTML again and upgrade. The checksum changes but this change alone does not trigger new Pods. Restore the checksum under Pod-template metadata and verify replacement.

#### 1. What to Break

In `charts/nginx-demo/templates/deployment.yaml`, move the `checksum/config` annotation from `spec.template.metadata.annotations` up to the root `metadata.annotations`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "nginx-demo.deploymentName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
  annotations:
    checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "nginx-demo.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      # checksum/config REMOVED from here!
      labels:
        {{- include "nginx-demo.labels" . | nindent 8 }}
```

#### 2. Apply and Record Current Pod

Apply this change:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
```

Check the active Pod name and creation age:

```bash
kubectl get pods -n helm-lab -l app=demo-dev
```

*Output:*

```text
NAME                                   READY   STATUS    RESTARTS   AGE
demo-dev-deployment-7bb9cf9475-abc12   1/1     Running   0          45s
```

*(Record the Pod name: `demo-dev-deployment-7bb9cf9475-abc12`)*

#### 3. Update the HTML and Upgrade Again

Now modify `pageContent` to change the ConfigMap's checksum:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --set pageContent="<h1>Rollout Test</h1>" --wait --timeout 120s
```

Now check the Pods again:

```bash
kubectl get pods -n helm-lab -l app=demo-dev
```

*Output:*

```text
NAME                                   READY   STATUS    RESTARTS   AGE
demo-dev-deployment-7bb9cf9475-abc12   1/1     Running   0          2m15s
```

**Notice:** The Pod was **NOT** replaced! The Pod name is identical and its age continued counting up.

#### 4. Why This Failed

- The Kubernetes Deployment controller inspects `spec.template` to decide whether a new ReplicaSet is required.
- Annotations placed in root `metadata.annotations` only update metadata on the Deployment object itself in etcd.
- Because `spec.template` remained bit-for-bit identical, the controller concluded that no Pod rollout was necessary, leaving the old Pod running.

#### 5. How to Recover

Move `checksum/config` back into `spec.template.metadata.annotations`:

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "nginx-demo.labels" . | nindent 8 }}
```

Re-run the upgrade:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
```

Verify that a brand-new Pod was scheduled:

```bash
kubectl get pods -n helm-lab -l app=demo-dev
```

*Output:*

```text
NAME                                   READY   STATUS    RESTARTS   AGE
demo-dev-deployment-85df649f88-xyz99   1/1     Running   0          5s
```

A new Pod with a new ReplicaSet hash has been created and is serving traffic.

---

## Key Takeaways

| Technique | Purpose |
| :--- | :--- |
| `checksum/config` in Pod template | Triggers rolling updates automatically when ConfigMaps change. |
| Pod Age / Name inspection | Verifies actual Pod replacement rather than passive background file sync. |
| `nindent` with `\|` | Ensures multiline configuration/HTML renders as valid, well-aligned YAML. |
