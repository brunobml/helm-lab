# Extension review: Storage and other workloads

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0, default StorageClass `standard` = `rancher.io/local-path`, `WaitForFirstConsumer`), 2026-09-22. k3d uses the same local-path provisioner, so I didn't repeat the test there.
**Result:**

- The chart lints and installs, and the PVC is `Bound`.
- The marker file survived Pod deletion (`marker-1` before and after).
- A bad StorageClass on a fresh install leaves the PVC `Pending` with `ProvisioningFailed ... storageclass.storage.k8s.io "nonexistent" not found`.
- `helm uninstall` deleted the PVC, and the PV went with it (`Delete` reclaim policy).

## Bugs

### B1: The hint's PVC template can't express an explicit empty `storageClassName` (medium)

Step 2 correctly says "Omitting storageClassName and explicitly setting it to an empty string have different meanings". But the hint uses `{{- if .Values.persistence.storageClassName }}`, which treats `""` as "omit". The learner can never produce `storageClassName: ""` (which disables dynamic provisioning), so they can't explore the distinction the step tells them to learn. The common Helm idiom handles this:

```gotemplate
{{- if .Values.persistence.storageClass }}
{{- if (eq "-" .Values.persistence.storageClass) }}
  storageClassName: ""
{{- else }}
  storageClassName: {{ .Values.persistence.storageClass | quote }}
{{- end }}
{{- end }}
```

or use `hasKey` / `kindIs "string"` checks. Pick one and explain it.

### B2: The break-it "restore the class" can't be done by upgrade (medium)

The break-it says to request a bad class and then "restore the class". If the learner applies the bad class via `helm upgrade` to the **existing** release, the upgrade fails immediately:

```text
PersistentVolumeClaim "storage-demo-data" is invalid: spec: Forbidden: spec is immutable after creation except resources.requests and volumeAttributesClassName for bound claims
```

So the "Pending PVC" state only appears on a **fresh install**. The lab mentions immutability only afterwards, as a side note. Restructure it as:

1. Try `helm upgrade --set persistence.storageClassName=nonexistent` and see the immutable-spec error.
2. `helm uninstall storage-demo` (and note that the data is gone).
3. `helm install` with the bad class and see `Pending` plus `ProvisioningFailed`.
4. Uninstall, wait for the PVC to be deleted (`kubectl wait --for=delete pvc/storage-demo-data`), and reinstall with the correct class.

Without the `wait`, a quick reinstall races the `Terminating` PVC (I hit this), and the events shown belong to the old claim.

## Missing content

- **M1:** Step 4 (Job, CronJob, StatefulSet, DaemonSet) has **no hints, no values, and no checkpoint content**. `extension-storage-complete` contains only the PVC + Deployment. Verify also says "For the Job, inspect completion and logs; for a CronJob, observe a scheduled Job". Either add minimal templates (a Job with `ttlSecondsAfterFinished` and a CronJob with `*/1 * * * *`) or mark Step 4 as a free-form stretch.
- **M2:** The lab never gives `Chart.yaml` or `values.yaml` for the new chart. The hints reference `.Values.persistence.accessMode/size/mountPath/storageClassName`, `.Values.image.*`, and `.Values.replicaCount`. Add the values block.
- **M3:** Step 3 "Write a marker file, replace the Pod, and read the marker" has no commands. These work:

  ```bash
  kubectl exec -n helm-lab deploy/storage-demo -- sh -c 'echo marker-1 > /data/marker'
  kubectl delete pod -n helm-lab -l app=storage-demo --wait
  kubectl rollout status deploy/storage-demo -n helm-lab
  kubectl exec -n helm-lab deploy/storage-demo -- cat /data/marker
  ```

- **M4:** The explained Q2 doesn't mention **`helm.sh/resource-policy: keep`**, the Helm-native answer to "What happens to the PVC on uninstall?". It's the single most relevant Helm feature for this question and shows up in Lab 15/CRDs as well.

## Accuracy / best-practice issues

- **I1:** The Deployment hint uses the default `RollingUpdate` strategy with a `ReadWriteOnce` PVC. On multi-node clusters, the new Pod can be scheduled on another node and hang in `ContainerCreating` (Multi-Attach error) while the old Pod holds the volume. Add `strategy: { type: Recreate }` and explain why. It's a classic Deployment + RWO trap.
- **I2:** The PVC and Deployment hints have no labels, so `kubectl get pvc -n helm-lab -l app=storage-demo` returns nothing. The chart also skips everything Lab 5 taught (standard labels, `helm.sh/chart`). Add at least `app.kubernetes.io/instance`.
- **I3:** Explained Q1 uses `marker.txt` / `'helm-persistence-test'` and PV `pvc-7d1f8480...`, which aren't in the lab. Use the lab's own names once M3 is added.

## Ease-of-following suggestions

- **S1:** Verify: add `kubectl get pv` after uninstall so learners see the PV disappear (reclaim `Delete`) and connect it to Explain Q2.
- **S2:** Mention that with `WaitForFirstConsumer` (kind and k3d), a PVC stays `Pending` *until a Pod uses it*. That's normal, and it's different from the break-it's `Pending`. Learners will otherwise confuse the two.
