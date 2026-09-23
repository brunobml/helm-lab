# Extension: Storage and other workloads — Explained

[Back to Extension: Storage and other workloads](storage-and-workloads.md)

---

## Overview

In this extension, you created a standalone `charts/storage-demo` chart managing a PersistentVolumeClaim (PVC) and Deployment, tested data survival across Pod termination, and analyzed the lifecycle of stateful workloads in Kubernetes.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: What survives a Pod replacement?

#### TL;DR

- **Does NOT survive:** The container filesystem (ephemeral root layer, container memory, and local temporary directories like `/tmp` or emptyDir volumes).
- **DOES survive:** Data written to paths mounted to a **PersistentVolumeClaim (PVC)**.

#### Deep Dive & Mechanism

1. **The Ephemeral Container Layer:**
   - When a Docker/container image runs, any file written directly into the container's root filesystem (e.g. `/var/log/app.log`) is stored in an ephemeral copy-on-write layer.
   - When the Pod is deleted, killed, or rescheduled, that container layer is permanently destroyed and discarded.

2. **Persistent Volumes:**
   - In our lab, `/data` was mounted to `PersistentVolumeClaim/storage-demo-data`.
   - When we ran `echo 'helm-persistence-test' > /data/marker.txt` and deleted the Pod (`kubectl delete pod ...`):
     1. The old Pod was destroyed.
     2. Kubernetes scheduled a new replacement Pod.
     3. The `kubelet` reattached and mounted the same underlying storage volume (`pvc-7d1f8480...`) back into `/data`.
     4. Reading `/data/marker.txt` from the replacement Pod returned the exact file intact.

---

### Question 2: How do PVC ownership, retention, and a volume's reclaim policy affect cleanup?

#### TL;DR

Helm manages the **PVC resource**, but the **underlying storage disk (PersistentVolume / PV)** is governed by the StorageClass's `reclaimPolicy` (`Delete` vs `Retain`).

#### Deep Dive & Mechanism

1. **What happens during `helm uninstall`:**
   - If the PVC is part of the Helm chart templates (`templates/pvc.yaml`), running `helm uninstall` **deletes the PVC**.

2. **The `reclaimPolicy` decides the physical disk's fate:**
   - **`reclaimPolicy: Delete` (Common in dev/cloud):**
     When the PVC is deleted, the underlying PersistentVolume and physical cloud disk (AWS EBS, GCP Persistent Disk, local folder) are **immediately deleted**. All data is permanently lost.
   - **`reclaimPolicy: Retain` (Standard in enterprise production):**
     When the PVC is deleted, the PersistentVolume is marked as `Released`, but the underlying disk and data remain untouched on the storage backend. An administrator must manually reclaim or backup the disk.

3. **Production Best Practice for State:**
   - For critical production databases, many teams **do not define the PVC inside the application's Helm chart**.
   - Instead, the PVC is provisioned separately (or via Terraform/GitOps), and the Helm chart merely references the pre-existing PVC by name, ensuring that an accidental `helm uninstall` cannot destroy production data.

---

### Question 3: Why is a StatefulSet more than a Deployment with a disk?

#### TL;DR

A Deployment treats Pods as interchangeable, disposable cattle with random names and shared/ephemeral disks. A **StatefulSet** provides **stable network identities, ordered rollouts, and unique dedicated per-Pod persistent disks** via `volumeClaimTemplates`.

#### Deep Dive & Mechanism

1. **Deployment Limitations with Storage:**
   - In a Deployment, all replicas share the exact same Pod template. If you attach a single PVC with `ReadWriteOnce` access mode, multiple Pod replicas on different nodes cannot mount the disk simultaneously (`Multi-Attach error for volume`).

2. **The StatefulSet Superpowers:**
   - **Predictable Pod Identity:**
     Pods are named with fixed, ordinal indexes: `redis-0`, `redis-1`, `redis-2` (instead of random hashes like `redis-67f7fd67bf-bp692`).
   - **Dedicated Disks per Replica (`volumeClaimTemplates`):**
     A StatefulSet automatically creates an independent PVC for each replica: `data-redis-0`, `data-redis-1`, `data-redis-2`.
     If `redis-1` crashes, its replacement Pod reconnects strictly to `data-redis-1`.
   - **Ordered Startup and Shutdown:**
     Pods start sequentially (`0` $\rightarrow$ `1` $\rightarrow$ `2`) and terminate in reverse order (`2` $\rightarrow$ `1` $\rightarrow$ `0`), ensuring clustered databases (Kafka, Cassandra, Elasticsearch, ZooKeeper) maintain quorum during rollouts.
   - **Headless Services & Stable DNS:**
     StatefulSets integrate with headless Services (`clusterIP: None`) so each Pod gets a dedicated internal DNS record: `redis-0.redis-service.default.svc.cluster.local`.

---

## Break It and Recover — Detailed Walkthrough

### What the challenge asks

> Request a nonexistent storage class, inspect the Pending PVC events, then restore the class. Understand why PVC fields cannot be changed in place.

#### 1. What to Break

Install `storage-broken` requesting a StorageClass that does not exist in the cluster:

```bash
helm install storage-broken ./charts/storage-demo -n helm-lab --set persistence.storageClass=nonexistent-sc --timeout 30s
```

#### 2. The Error Observed

The install command times out waiting for Pod readiness:

```text
Error: INSTALLATION FAILED: context deadline exceeded
```

#### 3. Diagnose the Pending PVC and Pod

Inspect the PVC and Pod status:

```bash
kubectl get pvc,pods -n helm-lab -l app=storage-broken
```

*Output:*

```text
NAME                                       STATUS    VOLUME   CAPACITY   ACCESS MODES   STORAGECLASS     AGE
persistentvolumeclaim/storage-broken-data   Pending                                      nonexistent-sc   45s

NAME                                          READY   STATUS    RESTARTS   AGE
pod/storage-broken-deployment-7bb9cf9475-x2n4p 0/1     Pending   0          45s
```

Inspect the PVC events:

```bash
kubectl describe pvc storage-broken-data -n helm-lab
```

*Events log:*

```text
Warning  ProvisioningFailed  15s (x3 over 45s)  persistentvolume-controller
storageclass.storage.k8s.io "nonexistent-sc" not found
```

Inspect the Pod events:

```bash
kubectl describe pod -l app=storage-broken -n helm-lab
```

*Events log:*

```text
Warning  FailedScheduling  10s (x2 over 40s)  default-scheduler
0/1 nodes are available: 1 pod has unbound immediate PersistentVolumeClaims.
```

#### 4. The Immutability Rule (Why `helm upgrade` Fails Here)

If you try to simply run `helm upgrade storage-broken ... --set persistence.storageClass=local-path`, the Kubernetes API server will reject the change:

```text
Error: UPGRADE FAILED: cannot patch "storage-broken-data" with kind PersistentVolumeClaim:
PersistentVolumeClaim "storage-broken-data" is invalid: spec: Forbidden: is immutable after creation
```

Unlike Deployments or Services, **most fields on a Kubernetes PersistentVolumeClaim (including `storageClassName` and `accessModes`) are strictly immutable**.

#### 5. How to Recover

Because the claim cannot be patched in place, you must uninstall the broken release and reinstall it with a valid StorageClass (e.g., `local-path` in k3s/k3d):

```bash
helm uninstall storage-broken -n helm-lab
helm install storage-demo ./charts/storage-demo -n helm-lab --wait --timeout 120s
```

Verify that the PVC is `Bound` and the Pod is `Running`:

```bash
kubectl get pvc,pods -n helm-lab
```

*Output:*

```text
NAME                                     STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS   AGE
persistentvolumeclaim/storage-demo-data   Bound    pvc-87df43e9-86f2-491a-b328-98e6a12b4899   10Mi       RWO            local-path     15s

NAME                                        READY   STATUS    RESTARTS   AGE
pod/storage-demo-deployment-7bb9cf9475-x2n4p 1/1     Running   0          12s
```

---

## Key Takeaways

| Workload Type | When to Use | Storage Pattern |
| :--- | :--- | :--- |
| **Deployment** | Stateless web apps, APIs, microservices. | Shared read-only storage or external database. |
| **StatefulSet** | Databases, message brokers, distributed clusters. | Dedicated per-pod PVCs via `volumeClaimTemplates`. |
| **Job / CronJob** | One-off tasks, database migrations, batch jobs. | Ephemeral storage or external object storage. |
