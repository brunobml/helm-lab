# Extension: Workload health and scaling — Explained

[Back to Extension: Workload health and scaling](health-and-scaling.md)

---

## Overview

In this extension, you configured HTTP probes (`livenessProbe`, `readinessProbe`) and integrated an `autoscaling/v2` HorizontalPodAutoscaler (HPA), learning how Helm manages replica counts in conjunction with Kubernetes autoscalers.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: Why should liveness failures restart a container while readiness failures remove it from traffic?

#### TL;DR

- **Liveness probe failure = Broken/Deadlocked process.** The container is in an unrecoverable state (e.g. deadlock, infinite loop, fatal out-of-memory state). Restarting the container is the only way to recover.
- **Readiness probe failure = Temporarily busy/Overloaded process.** The container is alive, but temporarily unable to accept new traffic (e.g. warming up caches, running database migrations, handling peak load). Restarting it would make the problem worse.

#### Deep Dive & Mechanism

1. **The Liveness Probe:**
   - When a liveness probe fails consecutively for `failureThreshold` times, the `kubelet` terminates the container and restarts it according to the Pod's `restartPolicy`.
   - **Caution:** If your application is simply slow under heavy load, a failing liveness probe will cause a **restart storm**: containers restart, lose their in-memory caches, get overwhelmed again immediately, and restart in an infinite loop!

2. **The Readiness Probe:**
   - When a readiness probe fails, Kubernetes does **not** restart the container.
   - Instead, the EndpointSlice controller immediately **removes the Pod's IP address from all matching Services**.
   - As a result, no incoming traffic is routed to that Pod while it recovers or finishes warming up. Once the readiness probe succeeds again, the Pod IP is re-added to the Service.

3. **The Startup Probe (Bonus):**
   - Disables liveness and readiness checks during slow application startup, preventing premature container restarts before complex initialization finishes.

---

### Question 2: Why does CPU utilization scaling need a CPU request?

#### TL;DR

HPA calculates CPU utilization as a percentage of the container's **requested CPU** (`AverageUtilization = CurrentUsage / RequestedCPU * 100`). Without `resources.requests.cpu`, there is no mathematical baseline to calculate a percentage.

#### Deep Dive & Mechanism

1. **The Mathematical Formula:**
   - If a container has `requests.cpu: 100m` (0.1 CPU core) and its current consumption is `80m`:
     $$\text{Utilization} = \frac{80\text{m}}{100\text{m}} \times 100\% = 80\%$$
   - The HPA target percentage (e.g. 80%) is compared against this computed percentage to decide whether to scale replicas up or down.

2. **What Happens if `requests.cpu` is Missing:**
   - If no CPU request is specified, the denominator is undefined.
   - HPA reports `TARGETS: <unknown>/80%`.
   - The HPA controller logs an error indicating that metrics could not be computed and refuses to scale the Deployment.

3. **Why Helm Must Conditionally Omit `replicas`:**
   - In `templates/deployment.yaml`:

     ```gotemplate
     {{- if not .Values.autoscaling.enabled }}
     replicas: {{ .Values.replicaCount }}
     {{- end }}
     ```

   - If `replicas` is hardcoded while HPA is enabled, every time you run `helm upgrade`, Helm will reset the replica count back to `replicaCount` (e.g., 2), undoing whatever scaling decisions the HPA made during peak traffic!

---

## Break It and Recover — Detailed Walkthrough

### What the challenge asks

> Set the readiness probe path to a missing page. Observe a running but unready Pod and unavailable Service endpoints. Restore `/` and verify readiness.

#### 1. What to Break

Run `helm upgrade` setting the readiness probe to a nonexistent path like `/missing.html`:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set readinessProbe.httpGet.path=/missing.html --wait=false
```

*(We pass `--wait=false` because otherwise Helm will wait and time out waiting for the unready Pod).*

#### 2. Observe the Unready Pod

Inspect the Pod status:

```bash
kubectl get pods -n helm-lab -l app=demo-dev
```

*Output:*

```text
NAME                                   READY   STATUS    RESTARTS   AGE
demo-dev-deployment-64fc987bf5-h29sk   0/1     Running   0          30s
```

Notice:

- `STATUS` is **Running** (the container started and the process is alive).
- `READY` is **0/1** (the readiness probe is failing HTTP 404).

#### 3. Inspect Service Endpoints

Check whether the Service has endpoints available to route traffic:

```bash
kubectl get endpointslices -n helm-lab -l kubernetes.io/service-name=demo-dev-service
```

*Output:*

```text
NAME                     ADDRESSTYPE   PORTS   ENDPOINTS   AGE
demo-dev-service-abc12   IPv4          80                  2m
```

Notice that `ENDPOINTS` is completely empty! Because the Pod failed readiness, Kubernetes removed its IP address from the Service to protect users from receiving errors.

#### 4. How to Recover

Restore the readiness probe path to `/`:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
```

Verify that the Pod becomes `READY 1/1` and the endpoint is restored:

```bash
kubectl get pods -n helm-lab -l app=demo-dev
kubectl get endpointslices -n helm-lab -l kubernetes.io/service-name=demo-dev-service
```

*Output:*

```text
NAME                                   READY   STATUS    RESTARTS   AGE
demo-dev-deployment-7bb9cf9475-x2n4p   1/1     Running   0          10s

NAME                     ADDRESSTYPE   PORTS   ENDPOINTS      AGE
demo-dev-service-abc12   IPv4          80      10.42.0.45     3m
```

---

## Key Takeaways

| Feature | Function |
| :--- | :--- |
| Liveness Probe | Restarts deadlocked or crashed containers. |
| Readiness Probe | Stops sending incoming traffic to temporarily unready Pods. |
| CPU Requests | Required baseline for HorizontalPodAutoscaler utilization metrics. |
| HPA + Helm | Always conditionally omit `spec.replicas` in Deployment when HPA is enabled. |
