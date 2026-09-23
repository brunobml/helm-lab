# Extension: Storage and other workloads

**Start:** Lab 7 or later (do all four extensions before Lab 10; later labs build on them); a local cluster with a working storage provisioner.
**Goal:** Learn when a different workload deserves its own chart.

## Steps

1. Create a separate `charts/storage-demo/` chart for this exercise. Keep
   `nginx-demo` focused on its web application.
2. Add a PVC with configurable size, access modes, and optional storageClassName.
   Omitting storageClassName and explicitly setting it to an empty string have
   different meanings; inspect your cluster's StorageClasses first.
3. Add a Pod or single-replica Deployment that mounts the PVC. Write a marker
   file, replace the Pod, and read the marker from its replacement.
4. In separate small exercises, use a Job for one-off work and a CronJob for a
   schedule. Explore a StatefulSet when stable Pod identity matters, or a
   DaemonSet when you need a Pod on each eligible node.

## Verify

```bash
kubectl get storageclass
helm lint ./charts/storage-demo
helm template storage-demo ./charts/storage-demo
helm install storage-demo ./charts/storage-demo -n helm-lab --wait --timeout 120s
kubectl get pvc,pods -n helm-lab
```

Test volume persistence across Pod replacement:

```bash
# Write a marker file to the mounted volume:
kubectl exec -n helm-lab deploy/storage-demo -- sh -c 'echo marker-1 > /data/marker'

# Delete the running Pod:
kubectl delete pod -n helm-lab -l app=storage-demo --wait
kubectl rollout status deploy/storage-demo -n helm-lab

# Read the marker from the newly scheduled Pod:
kubectl exec -n helm-lab deploy/storage-demo -- cat /data/marker
```

*Expect:* `marker-1`. The file survived Pod recreation!

## Break it and recover

1. Attempt to change `storageClass` on the existing release:

   ```bash
   helm upgrade storage-demo ./charts/storage-demo -n helm-lab --set persistence.storageClass=nonexistent
   ```

   *Expect Error:* `PersistentVolumeClaim ... spec is immutable after creation`. PVC specs are immutable once bound.

2. To see the `Pending` state, uninstall and test on a fresh install:

   ```bash
   helm uninstall storage-demo -n helm-lab
   kubectl wait --for=delete pvc/storage-demo-data -n helm-lab --timeout=30s
   helm install storage-demo ./charts/storage-demo -n helm-lab --set persistence.storageClass=nonexistent
   kubectl describe pvc storage-demo-data -n helm-lab
   ```

   *Expect:* Status `Pending` with event `ProvisioningFailed ... storageclass.storage.k8s.io "nonexistent" not found`.

3. Recover:

   ```bash
   helm uninstall storage-demo -n helm-lab
   kubectl wait --for=delete pvc/storage-demo-data -n helm-lab --timeout=30s
   helm install storage-demo ./charts/storage-demo -n helm-lab
   ```

## Explain

What survives a Pod replacement? How do PVC ownership, retention, and a volume's
reclaim policy affect cleanup? Why is a StatefulSet more than a Deployment with a disk?

> [!TIP]
> See [storage-and-workloads-explained.md](storage-and-workloads-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Uninstall `storage-demo`, then inspect what survives:

```bash
helm uninstall storage-demo -n helm-lab
kubectl get pvc,pv -n helm-lab
```

The chart's own `storage-demo-data` PVC is deleted with the release (unless you added
`helm.sh/resource-policy: keep`). If you tried the Step 4 StatefulSet, its
`stateful-data-storage-demo-stateful-0` PVC **remains**: Kubernetes never deletes
`volumeClaimTemplates` PVCs when the StatefulSet goes away. Remove it only when the data is disposable:

```bash
kubectl delete pvc stateful-data-storage-demo-stateful-0 -n helm-lab
```

Save `extension-storage-complete`.

<details>
<summary>Hint: charts/storage-demo/values.yaml and Chart.yaml</summary>

```yaml
# Chart.yaml
apiVersion: v2
name: storage-demo
description: A Helm chart demonstrating persistent storage and workloads
version: 0.1.0
appVersion: "1.36"
```

```yaml
# values.yaml
replicaCount: 1

image:
  repository: busybox
  tag: "1.36"
  pullPolicy: IfNotPresent

persistence:
  enabled: true
  accessMode: ReadWriteOnce
  size: 100Mi
  mountPath: /data
  storageClass: ""  # Set to "-" for explicit empty string: storageClassName: ""
```

</details>

<details>
<summary>Hint: charts/storage-demo/templates/pvc.yaml</summary>

```yaml
{{- if .Values.persistence.enabled -}}
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: {{ .Release.Name }}-data
spec:
  accessModes:
    - {{ .Values.persistence.accessMode }}
  {{- if .Values.persistence.storageClass }}
  {{- if (eq "-" .Values.persistence.storageClass) }}
  storageClassName: ""
  {{- else }}
  storageClassName: {{ .Values.persistence.storageClass | quote }}
  {{- end }}
  {{- end }}
  resources:
    requests:
      storage: {{ .Values.persistence.size }}
{{- end }}
```

</details>

<details>
<summary>Hint: charts/storage-demo/templates/deployment.yaml</summary>

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: app
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command: ["sh", "-c", "while true; do sleep 3600; done"]
          {{- if .Values.persistence.enabled }}
          volumeMounts:
            - name: data
              mountPath: {{ .Values.persistence.mountPath }}
          {{- end }}
      {{- if .Values.persistence.enabled }}
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: {{ .Release.Name }}-data
      {{- end }}
```

</details>

<details>
<summary>Hint: Step 4 workload patterns (Job, CronJob, StatefulSet)</summary>

```yaml
# Job pattern (run-to-completion batch task):
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-job
spec:
  backoffLimit: 2
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: task
          image: busybox:1.36
          command: ["sh", "-c", "echo 'Batch job complete'"]

---
# CronJob pattern (recurring scheduled task):
apiVersion: batch/v1
kind: CronJob
metadata:
  name: {{ .Release.Name }}-cronjob
spec:
  schedule: "0 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: busybox:1.36
              command: ["sh", "-c", "echo 'Backup task finished'"]

---
# Headless Service: gives each StatefulSet Pod a stable DNS name
# (<release>-stateful-0.<release>-headless.<namespace>.svc.cluster.local).
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-headless
spec:
  clusterIP: None
  selector:
    app: {{ .Release.Name }}-stateful
  ports:
    - name: placeholder
      port: 80
---
# StatefulSet pattern (dedicated per-Pod PVCs via volumeClaimTemplates):
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ .Release.Name }}-stateful
spec:
  serviceName: {{ .Release.Name }}-headless
  replicas: 1
  selector:
    matchLabels:
      app: {{ .Release.Name }}-stateful
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-stateful
    spec:
      containers:
        - name: db
          image: busybox:1.36
          command: ["sh", "-c", "while true; do sleep 3600; done"]
          volumeMounts:
            - name: stateful-data
              mountPath: /data
  volumeClaimTemplates:
    - metadata:
        name: stateful-data
      spec:
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 100Mi
```

</details>
