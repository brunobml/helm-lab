# Lab 2: Release lifecycle — Explained

[Back to Lab 2: Release lifecycle](02-release-lifecycle.md)

---

## Overview

In Lab 2, you explored release lifecycle management: upgrading releases, inspecting computed values vs user-supplied values, rolling back changes, and diagnosing failed rollouts.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: How do chart version, image tag, and release revision differ?

#### TL;DR
- **Chart Version:** The version of the Helm chart package itself (defined in `Chart.yaml`, e.g., `0.1.0`).
- **Image Tag:** The version/identifier of the Docker/container image running inside the Pod (e.g., `nginx:1.30.4-alpine`).
- **Release Revision:** A sequential integer managed by Helm (`1`, `2`, `3`...) that increments every time you `install`, `upgrade`, or `rollback` a specific release.

#### Deep Dive & Mechanism
1. **Chart Version (`Chart.yaml`):**
   - Tracks the source code of the deployment logic (the Helm templates).
   - Changing a label, adding an environment variable, or modifying resource limits requires bumping the chart version.
2. **Image Tag (`values.yaml` / Container registry):**
   - Tracks the compiled binary/application code built into the container image.
   - You can upgrade the image tag without changing the chart version (via values override), or you can change chart templates without changing the image tag.
3. **Release Revision (Helm Cluster State):**
   - Helm stores each release's state as a versioned Kubernetes Secret in the release namespace:
     ```text
     sh.helm.release.v1.demo-dev.v1  (Revision 1)
     sh.helm.release.v1.demo-dev.v2  (Revision 2)
     sh.helm.release.v1.demo-dev.v3  (Revision 3 - Rollback to 1)
     ```
   - When you execute `helm rollback demo-dev 1`, Helm does **not** erase revision 2. Instead, it generates **revision 3**, whose manifest matches revision 1. History is append-only!

---

### Question 2: Does a successful render imply a successful rollout?

#### TL;DR
**No, absolutely not.** A successful render only proves that your Go template syntax is valid and produced syntactically correct YAML. It guarantees nothing about whether Kubernetes can run the workload.

#### Deep Dive & Mechanism
A Helm release goes through several distinct phases:
1. **Client-side Rendering (`helm template`):**
   - Evaluates loops, variables, and string interpolation.
   - If a required value is missing or indentation is broken, this fails.
2. **Kubernetes API Validation:**
   - Evaluates whether the resource schema is valid (e.g., are field types correct? Are required fields present?).
3. **Cluster Admission & Scheduling:**
   - Admission controllers (e.g., OPA Gatekeeper, Kyverno) can reject the manifest.
   - The scheduler checks if nodes have enough CPU/memory.
4. **Workload Runtime Rollout (`--wait`):**
   - The kubelet pulls the image and starts the container.
   - This phase can fail for many runtime reasons that rendering cannot detect:
     - Invalid image name or tag (`ImagePullBackOff` / `ErrImagePull`)
     - Missing Secrets or ConfigMaps (`CreateContainerConfigError`)
     - Failing application startup or crash-loops (`CrashLoopBackOff`)
     - Failing readiness probes
   - **Best Practice:** Always use `--wait` and `--timeout` during `helm install` and `helm upgrade` in CI/CD pipelines so failures at the runtime layer are caught before marking deployments complete.

---

### Question 3: Which command showed the cause of the failure?

#### TL;DR
`kubectl describe pods -n helm-lab -l app=demo-dev`

#### Deep Dive & Mechanism
- When an upgrade times out, Helm will only report:
  ```text
  Error: UPGRADE FAILED: context deadline exceeded
  ```
  Helm does not know *why* the Pod failed to become ready; it only knows that the Deployment's rollout condition was not satisfied within the timeout window.
- Running `kubectl get pods -n helm-lab` shows the high-level Pod status:
  ```text
  demo-dev-deployment-d9c9977d7-jk524   0/1   ImagePullBackOff   0   20s
  ```
- Running `kubectl describe pod ...` inspects the **Events** section at the bottom, which reveals the exact root cause:
  ```text
  Events:
    Type     Reason          Message
    ----     ------          -------
    Normal   Scheduled       Successfully assigned helm-lab/demo-dev-... to node
    Normal   Pulling         Pulling image "nginx:does-not-exist-helm-lab"
    Warning  Failed          Failed to pull image "nginx:does-not-exist-helm-lab": rpc error: code = NotFound
    Warning  Failed          Error: ErrImagePull
  ```

---

## Break It and Recover — Detailed Walkthrough

### What the challenge asks:
> Try an unavailable image tag with `--set-string image.tag=does-not-exist-helm-lab --wait --timeout 60s`. Expect the upgrade to time out and a new Pod to report an image-pull error. Recover by rolling back to the last successful revision.

#### 1. What to Break
Run `helm upgrade` pointing to an image tag that does not exist in the registry, using `--wait` and a 60-second timeout:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set-string image.tag=does-not-exist-helm-lab --wait --timeout 60s
```

#### 2. The Error Observed
After waiting 60 seconds, Helm aborts and returns:
```text
Error: UPGRADE FAILED: context deadline exceeded
```

#### 3. Diagnose the Pod Failure
Check the cluster Pods:
```bash
kubectl get pods -n helm-lab
```
*Output:*
```text
NAME                                   READY   STATUS             RESTARTS   AGE
demo-dev-deployment-7bb9cf9475-x2n4p   1/1     Running            0          10m
demo-dev-deployment-7bb9cf9475-z89wq   1/1     Running            0          10m
demo-dev-deployment-556b69b9b5-4q8lp   0/1     ImagePullBackOff   0          65s
```

Inspect the pod events:
```bash
kubectl describe pods -n helm-lab -l app=demo-dev
```
*Events log:*
```text
Warning  Failed     30s (x2 over 45s)   kubelet  Failed to pull image "nginx:does-not-exist-helm-lab": rpc error: code = NotFound
Warning  Failed     30s (x2 over 45s)   kubelet  Error: ErrImagePull
```

Check the Helm release history:
```bash
helm history demo-dev -n helm-lab
```
*Output:*
```text
REVISION    UPDATED                     STATUS    CHART               APP VERSION    DESCRIPTION
1           ...                         superseded nginx-demo-0.1.0   1.30.4         Install complete
2           ...                         failed     nginx-demo-0.1.0   1.30.4         Upgrade "demo-dev" failed: context deadline exceeded
```
Notice that:
- Revision 2 is marked `failed`.
- Kubernetes rolling update paused: the old healthy Pods from Revision 1 were kept alive and serving traffic because the new Pod never became `Ready`!

#### 4. How to Recover
Roll back to the last known healthy revision (Revision 1):
```bash
helm rollback demo-dev 1 -n helm-lab --wait --timeout 60s
```
*Output:*
```text
Rollback was a success! Happy Helming!
```

#### 5. Verify Clean State
Inspect the release history and Pod status:
```bash
helm history demo-dev -n helm-lab
kubectl get pods -n helm-lab
```
*Output:*
```text
REVISION    UPDATED     STATUS      CHART               APP VERSION    DESCRIPTION
1           ...         superseded  nginx-demo-0.1.0   1.30.4         Install complete
2           ...         failed      nginx-demo-0.1.0   1.30.4         Upgrade "demo-dev" failed
3           ...         deployed    nginx-demo-0.1.0   1.30.4         Rollback to 1

NAME                                   READY   STATUS    RESTARTS   AGE
demo-dev-deployment-7bb9cf9475-x2n4p   1/1     Running   0          12m
demo-dev-deployment-7bb9cf9475-z89wq   1/1     Running   0          12m
```
Helm created Revision 3 (a rollback to Revision 1), terminating the broken Pod and returning the Deployment to a healthy state.

---

## Key Takeaways

| Concept | Explanation |
| :--- | :--- |
| Revision History | Helm revisions are append-only. Rolling back creates a new revision. |
| Verification Depth | `helm template` checks syntax; `--wait` checks runtime pod readiness. |
| Troubleshooting | When Helm reports `context deadline exceeded`, check `kubectl describe pod` events. |
