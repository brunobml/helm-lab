# Helm Lab Validation

Every lab and extension has been executed and validated against a live **k3d-helm-lab** cluster (Kubernetes v1.35.5, Helm v3.19.0).

During this validation process, several friction points were resolved, instructions were streamlined, and complete hint templates were added to make the exercises effortless to follow.

---

### Summary of Live Validation & Instruction Improvements

| Lab / Topic | Validation Outcome | Instructions & Hints Improved | Checkpoint Tag |
| :--- | :--- | :--- | :--- |
| **Lab 1: First Chart** | `helm lint`, `helm template`, `helm install`, `kubectl rollout`, `port-forward`, and `curl` verified. Missing value break-and-recover tested. | Clarified file roles and output expectations. | `lab-01-complete` |
| **Lab 2: Release Lifecycle** | Revision tracking, `--set` overrides, rollback to revision 1, and timed-out upgrade failure with image pull error verified. | Documented revision mechanics and rollback behaviors. | `lab-02-complete` |
| **Lab 3: Values & Environments** | `values-dev.yaml` and `values-prod.yaml` created. Precedence rules and multi-release coexistence verified on the cluster. | Explicit guidance on `--reset-values` vs persistent `--set` flags. | `lab-03-complete` |
| **Lab 4: Template Logic** | `extraEnv` (`with` + `range`) and `resources` (`toYaml` + `nindent`) implemented. Verified inside Pod with `printenv`. | Added hint showing variable quoting and scope traversal (`$.Release.Name`). | `lab-04-complete` |
| **Lab 5: Helpers & Labels** | `_helpers.tpl` created with standard labels and resource names. Verified selector immutability and endpoint slice matching. | Expanded hints to include complete definitions for `labels`, `deploymentName`, and `serviceName` (`trunc 63 \| trimSuffix "-"`). | `lab-05-complete` |
| **Lab 6: ConfigMaps & Rollouts** | ConfigMap volume mount and `checksum/config: sha256sum` implemented. Verified that modifying HTML triggers automatic Pod replacement. | Clarified why the checksum must live under `spec.template.metadata.annotations`. | `lab-06-complete` |
| **Lab 7: Validation & Tests** | `values.schema.json`, test hook Pod, and `NOTES.txt` implemented. Schema rejects invalid replicas (`-1`) and ports (`70000`). | Fixed hook deletion race condition: updated policy to `before-hook-creation` so `helm test --logs` reliably fetches logs without "pod not found" errors. Added schema hint. | `lab-07-complete` |
| **Lab 8: Dependencies** | Companion subchart `lab-banner` created with `file://` dependency, `Chart.lock`, and global values propagation verified. | Added explicit failure recovery steps for missing `.tgz` archives using `helm dependency build`. | `lab-08-complete` |
| **Lab 9: Packaging & GitOps** | Bumped version to 0.2.0, packaged archive, and verified installation and testing from archive. | Added a zero-auth local OCI registry option (`docker run -d -p 5001:5000 ...`) so OCI publishing can be tested 100% offline without third-party registry accounts. | `lab-09-complete` |
| **Ext: Networking** | Ingress routing tested through k3s's built-in Traefik controller. | Added in-cluster curl test command (`kubectl run curl-test ...`) to verify Ingress routing on Docker/k3d networks, plus complete `ingress.yaml` template in hints. | `extension-networking-complete` |
| **Ext: Health & Scaling** | Liveness/readiness HTTP probes and HPA v2 autoscaling verified with cluster metrics-server. | Added hint showing conditional omission of `spec.replicas` when HPA is active. | `extension-health-complete` |
| **Ext: Identity & Secrets** | ServiceAccount creation, Role, RoleBinding, and `existingSecret` verified with `printenv` and `kubectl auth can-i`. | Added hint templates for `serviceaccount.yaml`, `rbac.yaml`, and `_helpers.tpl` helper. | `extension-identity-complete` |
| **Ext: Storage & Workloads** | Created standalone `charts/storage-demo` with PVC and Deployment. Verified data persistence across pod deletion. | Added hint templates and full working manifests for `storage-demo` on local-path storage. | `extension-storage-complete` |