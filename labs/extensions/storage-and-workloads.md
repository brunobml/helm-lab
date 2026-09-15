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
