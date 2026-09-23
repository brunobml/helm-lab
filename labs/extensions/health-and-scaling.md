# Extension: Workload health and scaling

**Start:** Lab 7 or later, with the `resources` template from Lab 4.
**Goal:** Distinguish running, ready, healthy, and automatically scaled workloads.

## Steps

1. Add configurable readiness, liveness, and startup HTTP probes on `/`, port 80.
2. Render each probe using `toYaml` and `nindent`; support disabling each.
3. Add optional `autoscaling/v2` HPA output controlled by `autoscaling.enabled`.
4. When HPA is enabled, omit Deployment `spec.replicas` so Helm does not keep
   overwriting the autoscaler's desired count. Set CPU requests for utilization targets.
5. For live scaling, ensure your cluster has a working resource metrics provider.

## Verify

Render with autoscaling both off and on. Expect replicas only when off and HPA
only when on.

Deploy probes to the dev release:

```bash
# If resource metrics are not yet installed on kind:
# helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
# helm upgrade --install metrics-server metrics-server/metrics-server -n kube-system --set args={--kubelet-insecure-tls}

helm upgrade demo-dev ./charts/nginx-demo -n helm-lab \
  --reset-values -f ./charts/nginx-demo/values-dev.yaml \
  --set readinessProbe.httpGet.path=/ \
  --set readinessProbe.httpGet.port=80 \
  --set livenessProbe.httpGet.path=/ \
  --set livenessProbe.httpGet.port=80
```

Inspect the deployed probes:

```bash
kubectl describe deployment demo-dev-deployment -n helm-lab
kubectl get pods -n helm-lab -l app=demo-dev
kubectl top pods -n helm-lab -l app=demo-dev
```

After enabling HPA, inspect `kubectl get hpa -n helm-lab`. Metrics must be
available before you expect useful scaling behavior. Apply controlled load in
your local cluster and observe replicas scale up:

```bash
kubectl run load -n helm-lab --image=busybox:1.36 --restart=Never -- \
  sh -c 'while true; do wget -q -O- http://demo-dev-service >/dev/null; done'
kubectl get hpa -n helm-lab -w
```

## Break it and recover

Set the readiness probe path to a missing page:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab \
  --reset-values -f ./charts/nginx-demo/values-dev.yaml \
  --set readinessProbe.httpGet.path=/missing.html --wait=false
```

Observe that during a rolling update, the new Pod runs but stays unready (`0/1 Running`), while the old Pod continues to serve traffic. Then restore `/` and verify readiness:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab \
  --reset-values -f ./charts/nginx-demo/values-dev.yaml \
  --set readinessProbe.httpGet.path=/ \
  --set readinessProbe.httpGet.port=80 \
  --wait
```

## Explain

Why should liveness failures restart a container while readiness failures remove
it from traffic? Why does CPU utilization scaling need a CPU request?

> [!TIP]
> See [health-and-scaling-explained.md](health-and-scaling-explained.md) for detailed explanations and answers to these questions.

## Cleanup and checkpoint

Stop load generation, disable autoscaling, and restore the dev replica count
through Helm. Keep correct probes. Save `extension-health-complete`.

<details>
<summary>Hint: conditional replicas and probes in templates/deployment.yaml</summary>

```yaml
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
...
      containers:
        - name: nginx
          ...
          {{- with .Values.startupProbe }}
          startupProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

</details>

<details>
<summary>Hint: templates/hpa.yaml</summary>

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "nginx-demo.deploymentName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "nginx-demo.deploymentName" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    {{- if .Values.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
{{- end }}
```

</details>
