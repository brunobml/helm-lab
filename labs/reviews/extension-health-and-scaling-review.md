# Extension review: Workload health and scaling

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Tested with:** Helm v3.19.0. kind (Kubernetes v1.35.0, **no metrics-server**) and k3d (k3s v1.35.5, bundled metrics-server). 2026-09-22.
**Result:**

- Probes render and appear in `kubectl describe` (`Liveness: http-get http://:80/ ...`).
- Autoscaling on and off render correctly: `replicas` appears only when off, the HPA only when on.
- On **k3d**, live scaling worked: 3 load Pods pushed CPU to 640 % of a 20 % target, and the HPA scaled from 1 to 5 replicas.
- On **kind**, `kubectl top` fails with `error: Metrics API not available`.

The lab doesn't warn about several real-world traps I ran into.

## Bugs

### B1: Enabling the HPA can immediately scale the Deployment *down* (high)

Step 4 (omit `spec.replicas` when autoscaling is on) is correct, but the *transition* is dangerous and not mentioned. Tested on kind:

1. `demo-dev` running with `replicaCount=3` → `spec.replicas: 3`
2. `helm upgrade ... --set autoscaling.enabled=true --set autoscaling.minReplicas=2`
3. Right after the upgrade, `spec.replicas` was **1**. Helm's 3-way merge removed the field and the API defaulted it to 1. The HPA then raised it back to 2 about 15 s later.

In production this drops capacity from 3 to 1 Pods during an upgrade. The explained page instead talks about the *opposite* problem (Helm resetting HPA decisions).
**Fix:** Add a warning and the common mitigations: set `minReplicas` ≥ the current count before switching, or use `lookup` to keep the live `spec.replicas` on the first switch. Otherwise, tell learners to watch `kubectl get deploy -w` during the upgrade so they see it happen.

### B2: The step list asks for a startup probe that nothing provides (medium)

Step 1 says "Add configurable readiness, liveness, **and startup** HTTP probes". The hint, the values in `extension-health-complete`, and the explained page (only as a "Bonus") contain no `startupProbe`. Either add `{{- with .Values.startupProbe }}` to the hint and values, or drop "startup" from Step 1.

### B3: The break-it doesn't produce "unavailable Service endpoints" (medium)

With `--set readinessProbe.httpGet.path=/missing`, a **rolling update** starts. The new Pod is `0/1 Running`, but the **old Pod stays Ready**, so the EndpointSlice shows `ready: true,false` and the Service keeps serving (verified). Only when all Pods fail readiness (for example `replicaCount=1` with `strategy` recreate, or after deleting the old Pod) do the endpoints become empty.
The explained page shows a single unready Pod and an empty EndpointSlice, which isn't what learners will see. This is actually a great lesson ("readiness gates rollouts, so a bad probe never takes down a working version"), so rewrite the expectation around it.

## Accuracy issues

- **I1: `kubectl top pods -n helm-lab` fails on a namespace with a completed test Pod.** On k3d it printed only `error: Metrics not available for pod helm-lab/demo-dev-http-test` and **no rows**, because the Lab 7 test Pod is kept (`before-hook-creation`). Use `kubectl top pods -n helm-lab -l app=demo-dev`, which works.
- **I2:** Verify says "ensure your cluster has a working resource metrics provider", but gives no pointer. kind has none. Add:

  ```bash
  helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
  helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --set args={--kubelet-insecure-tls}
  ```

  Note that k3d/k3s ships it. This is a good place to recommend k3d.
- **I3:** The explained break-it uses `helm upgrade demo-dev ... --set readinessProbe.httpGet.path=/missing.html --wait=false` without `--reset-values -f values-dev.yaml`, so the dev settings are dropped (see the networking review B2). Add the values file.
- **I4:** Explained Q2: "HPA controller ... refuses to scale" without a CPU request. More precisely, the HPA condition shows `FailedGetResourceMetric: missing request for cpu`. Quote that so learners can recognize it (`kubectl describe hpa`).

## Ease-of-following suggestions

- **S1:** "Apply controlled load" has no command. This one worked well:

  ```bash
  kubectl run load -n helm-lab --image=busybox:1.36 --restart=Never -- \
    sh -c 'while true; do wget -q -O- http://demo-dev-service >/dev/null; done'
  kubectl get hpa -n helm-lab -w
  ```

  With the dev `cpu: 50m` request, the default 80 % target is reached with 2–3 load Pods. A lower target (`--set autoscaling.targetCPUUtilizationPercentage=20`) shows scaling within about 30 s.
- **S2:** Mention that the probes hard-code `port: 80` in values. When Lab 16 switches to the unprivileged image on 8080, these defaults must change too. That's a good forward reference, and a good reason to use a named port (`http`) instead.
- **S3:** Cleanup: give the restore command (`helm upgrade demo-dev ... --reset-values -f ./charts/nginx-demo/values-dev.yaml`) and `kubectl delete pod load -n helm-lab`.
- **S4:** The HPA `metrics:` block renders an empty list when `targetCPUUtilizationPercentage` is unset, and the HPA API then applies its default (80 % CPU). Worth a note, or add a memory metric option for completeness.
