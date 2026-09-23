# Lab 18: Helm internals and advanced operations — Explained

This companion guide explains the internal architecture of Helm, the storage driver mechanics, the three-way strategic merge patch algorithm, resource adoption boundaries, the deprecated API upgrade trap, and the architectural evolution coming in Helm 4.

---

## 1. How Helm stores release state: The Secrets driver

In Helm 2, release state was stored in `ConfigMaps` managed by a cluster-side pod called **Tiller**. Tiller required cluster-admin privileges, creating a massive security vulnerability.

Helm 3 completely eliminated Tiller. Helm is now a 100% client-side CLI. To store release history without a central database, Helm uses standard Kubernetes primitives: **Secrets** (by default), **ConfigMaps**, or **SQL** (via experimental driver).

### Why Secrets instead of ConfigMaps?

1. **RBAC Isolation:** Kubernetes allows fine-grained RBAC on Secrets. Non-admin users can be granted permission to view ConfigMaps while restricting access to Secrets.
2. **Encryption at Rest:** Cloud providers and production clusters enable encryption-at-rest for Secrets using KMS keys (AWS KMS, GCP Cloud KMS, Azure Key Vault). Storing release state in Secrets protects sensitive chart values (`config`) and rendered secrets (`manifest`) at rest.
3. **Namespacing:** Release Secrets reside directly inside the namespace where the application is deployed. Deleting the namespace automatically cleans up all associated Helm release history.

### The dual-layer encoding pipeline

When Helm saves a release revision, it executes the following serialization pipeline:

```text
[ Go Release Struct ]
        |
        v  (json.Marshal)
   [ JSON Bytes ]
        |
        v  (gzip.Compress)
  [ Gzip Binary ]
        |
        v  (base64.StdEncoding.EncodeToString)
[ Helm Driver String ]
        |
        v  (kubectl/k8s client: base64 encode into Secret.data)
[ Kubernetes Secret Data ]
```

When querying a Secret via `kubectl jsonpath='{.data.release}'`, you must decode twice:

1. First decode: Reverses Kubernetes' base64 encoding of `Secret.data`.
2. Second decode: Reverses Helm's internal base64 encoding.
3. Gunzip: Decompresses the raw JSON release document.

### Anatomy of a release Secret

The JSON release document contains:

```json
{
  "name": "internals-demo",
  "version": 1,
  "namespace": "helm-internals",
  "info": {
    "first_deployed": "2026-09-22T17:49:33Z",
    "last_deployed": "2026-09-22T17:49:33Z",
    "status": "deployed",
    "description": "Install complete"
  },
  "chart": {
    "metadata": { "name": "nginx-demo", "version": "0.6.0" },
    "templates": [ ... ]
  },
  "config": {
    "replicaCount": 1
  },
  "manifest": "---\napiVersion: apps/v1\nkind: Deployment\n...",
  "hooks": [ ... ]
}
```

- **`config`:** Stores only the user-provided values passed via `--values` or `--set`.
- **`manifest`:** Stores the complete, rendered YAML stream submitted to the cluster.
- **`version`:** The release revision number.
- **`info.status`:** The lifecycle state: `deployed`, `superseded`, `failed`, `uninstalled`, `pending-install`, or `pending-upgrade`.

---

## 2. The Three-Way Strategic Merge Patch

A fundamental design decision in Helm is how it updates existing resources.

A naive deploy tool uses a **Two-Way Merge**: it compares the live cluster object against the new manifest. If a field exists on the cluster but is not in the new manifest, the tool cannot know whether:

- The field was added by a cluster controller (e.g. HPA, Service Mesh, Mutating Webhook), OR
- The field was deleted from the chart by a developer.

To solve this, Helm calculates a **Three-Way Strategic Merge Patch**:

```text
                      [ Base: Previous Manifest ]
                            (from Secret v1)
                             /            \
                            /              \
                           v                v
            [ Live Cluster State ]    [ Target Rendered Manifest ]
            (modified by operators)        (from Chart v2)
                           \                /
                            \              /
                             v            v
                   [ 3-Way Merge Patch Applied to API ]
```

### Three-way merge decision matrix

| Base (v1 Secret) | Live (Cluster) | Target (v2 Render) | Result Applied to Cluster | Explanation |
| :--- | :--- | :--- | :--- | :--- |
| `replicas: 1` | `replicas: 5` (drift) | `replicas: 2` | `replicas: 2` | Target changed from Base; chart intent overrides cluster drift. |
| Absent | `incident-id: INC-9901` | Absent | `incident-id: INC-9901` | Target did not touch Base; live cluster modification is preserved. |
| `sidecar: enabled` | `sidecar: enabled` | Absent | **Deleted** | Present in Base, absent in Target; Helm detects intentional deletion and removes it. |
| Absent | `mutated-by-webhook: true` | Absent | `mutated-by-webhook: true` | Injected by admission controller; safely preserved across upgrades. |

This algorithm allows Helm charts to coexist harmoniously with service meshes (Istio sidecars), admission controllers, external secret operators, and cluster autoscalers.

---

## 3. Resource ownership and adoption boundaries

Kubernetes API servers do not enforce resource ownership by default: anyone with sufficient RBAC can modify or overwrite any object.

To prevent teams from accidentally trampling each other's resources, Helm enforces a client-side ownership validation check before modifying existing resources.

### The three ownership markers

When Helm creates a resource, it injects three metadata markers:

```yaml
metadata:
  labels:
    app.kubernetes.io/managed-by: Helm
  annotations:
    meta.helm.sh/release-name: <release-name>
    meta.helm.sh/release-namespace: <namespace>
```

When Helm attempts to install or upgrade a resource that already exists on the cluster:

1. **If all three markers match:** Helm recognizes the resource as part of the current release and computes the three-way merge patch.
2. **If any marker is missing or points to another release/namespace:** Helm halts immediately with an ownership validation error to prevent accidental takeovers.

### Adoption strategies

1. **`--take-ownership` flag:**
   Tells Helm to suppress the ownership check, overwrite the metadata markers with the current release's details, and assume ownership of the existing resource.
2. **Manual metadata injection:**
   Applying `meta.helm.sh` annotations and `app.kubernetes.io/managed-by: Helm` directly via `kubectl annotate` and `kubectl label`. Ideal for scripted migrations where you want strict control before running Helm.

---

## 4. The Deprecated API Upgrade Trap & `mapkubeapis`

One of the most common production incidents during Kubernetes cluster upgrades is the **Helm Deprecated API Trap**.

### The sequence of failure

1. In Kubernetes v1.21, a chart was installed containing `policy/v1beta1` `PodDisruptionBudget`.
2. The release Secret recorded the `policy/v1beta1` manifest in `data.release`.
3. The cluster was upgraded to Kubernetes v1.25, where `policy/v1beta1` was permanently removed from the API server.
4. The chart author updated their templates to `policy/v1`.
5. The operator ran `helm upgrade`.
6. **Failure:** `helm upgrade` crashed with:

   ```text
   UPGRADE FAILED: unable to build kubernetes objects from current release manifest: ... no matches for kind "PodDisruptionBudget" in version "policy/v1beta1"
   ```

### Why didn't Helm just use the new template?

Before Helm can apply the new templates, it must load the **current release** manifest from the previous Secret and convert it into Go runtime objects (`unstructured.Unstructured` or typed Kubernetes API structs). This requires querying the Kubernetes API discovery endpoint (`/api` and `/apis`).

If the API group version in the old manifest no longer exists on the cluster, API discovery fails, and Helm cannot construct the **Base** object for the three-way merge.

### How `helm-mapkubeapis` resolves the deadlock

`helm-mapkubeapis` bypasses the Kubernetes API server discovery step entirely:

1. It reads the raw release Secret directly from etcd using standard Secret APIs (`v1.Secret`).
2. It decompresses and parses the raw YAML stream inside `.manifest`.
3. It performs static text and AST replacements using a mapping table (e.g. `policy/v1beta1` $\to$ `policy/v1`).
4. It re-encodes and writes a corrected release Secret (`superseded` $\to$ new revision).
5. When `helm upgrade` runs next, the **Base** manifest uses valid, supported APIs, allowing discovery and three-way merge to succeed cleanly.

---

## 5. Helm 3 vs. Helm 4 Architecture Comparison

Helm 4 represents the next major evolution of Helm, modernizing the core engine around native Kubernetes primitives.

| Dimension | Helm 3 | Helm 4 |
| :--- | :--- | :--- |
| **Apply Engine** | Client-Side 3-Way Strategic Merge Patch | Kubernetes Server-Side Apply (SSA) |
| **Patch Calculation** | Performed on client machine / CI runner | Performed server-side by Kubernetes API server |
| **Field Ownership** | Tracked implicitly via release Secrets | Tracked explicitly in resource `metadata.managedFields` |
| **Conflict Handling** | Last-write-wins (or manual resolution) | API server rejects conflicting updates unless `--force-conflicts` is used |
| **Removed API Trap** | Requires `mapkubeapis` to rewrite old Secrets | Eliminated: API server handles internal version conversion |
| **CRD Management** | `crds/` directory installed only once; upgrades ignored | Server-Side Apply allows native CRD reconciliation and schema evolution |
| **Distribution** | HTTP repository index (`index.yaml`) primary; OCI secondary | OCI-native primary; legacy HTTP repository format deprecated |

### How Server-Side Apply (SSA) eliminates the Removed API Trap

Under Server-Side Apply, the client sends only the fields it cares about directly to the API server with a declared field manager (`fieldManager=helm`).

The Kubernetes API server maintains an internal, version-independent representation of all resources. When an API version is removed from the external endpoint, the API server can still convert between stored versions internally. Because the client is no longer responsible for computing strategic merge patches against historical manifests, the deprecation trap disappears entirely in Helm 4.
