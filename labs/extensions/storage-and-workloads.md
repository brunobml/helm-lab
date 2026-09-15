# Extension: Storage and other workloads

**Start:** Lab 7 or later; a local cluster with a working storage provisioner.
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

Expect a Bound PVC and the same marker after Pod replacement. Record exactly
which object owns the claim and what happens to it on uninstall. For the Job,
inspect completion and logs; for a CronJob, observe a scheduled Job.

## Break it and recover

Request a nonexistent storage class, inspect the Pending PVC events, then
restore the class. Some PVC fields cannot be changed in place: for disposable
exercise data, uninstall and recreate the claim after understanding data loss.

## Explain

What survives a Pod replacement? How do PVC ownership, retention, and a volume's
reclaim policy affect cleanup? Why is a StatefulSet more than a Deployment with a disk?

## Cleanup and checkpoint

Uninstall `storage-demo`, inspect remaining PVCs/PVs, and remove only disposable
exercise storage. Save `extension-storage-complete`.

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
  {{- if .Values.persistence.storageClassName }}
  storageClassName: {{ .Values.persistence.storageClassName | quote }}
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
