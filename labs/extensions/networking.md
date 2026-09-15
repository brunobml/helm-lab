# Extension: Networking

**Start:** Lab 7 or later; save a checkpoint before experimenting.
**Goal:** Separate chart rendering from the cluster infrastructure needed for traffic.

## Steps

1. Override `service.type` to `NodePort` and inspect the generated manifest.
2. Add `ingress.enabled: false` and configurable class, hosts, paths, and TLS.
3. Implement `templates/ingress.yaml` with `networking.k8s.io/v1`; route to the
   existing Service name and its `service.port`. Render host/path arrays with loops.
4. For a live exercise, install an Ingress controller appropriate to your local
   cluster and use its documented access method. TLS also requires a matching Secret.

## Verify

```bash
helm template demo-dev ./charts/nginx-demo --set service.type=NodePort
helm template demo-dev ./charts/nginx-demo --set ingress.enabled=false
```

Create an ingress values file with a host and path, render with it, and inspect
the backend. Disabled output has no Ingress; enabled output has the expected
host, pathType, class, and backend port.

After deploying your values:
```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set ingress.enabled=true --set ingress.className=traefik --wait --timeout 120s
kubectl get ingress -n helm-lab
```

Test routing through the Ingress controller using an ephemeral curl Pod (works in any local cluster):
```bash
kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -i --restart=Never -- -s -H "Host: chart-example.local" http://traefik.kube-system.svc.cluster.local/
```

## Break it and recover

Use the wrong ingress class (e.g. `--set ingress.className=nonexistent`), observe
that rendering and applying still succeed but traffic is not routed by the intended
controller, then restore the correct class. A `LoadBalancer` Service may stay
pending on a local cluster without a cloud controller or MetalLB.

## Explain

What creates an Ingress object, and what actually handles its traffic?

## Cleanup and checkpoint

Disable the Ingress through a Helm upgrade, restore ClusterIP, and remove any
controller you installed solely for this exercise. Save `extension-networking-complete`.

<details>
<summary>Hint: templates/ingress.yaml</summary>

```yaml
{{- if .Values.ingress.enabled -}}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "nginx-demo.serviceName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
  {{- with .Values.ingress.annotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if .Values.ingress.className }}
  ingressClassName: {{ .Values.ingress.className }}
  {{- end }}
  {{- if .Values.ingress.tls }}
  tls:
    {{- range .Values.ingress.tls }}
    - hosts:
        {{- range .hosts }}
        - {{ . | quote }}
        {{- end }}
      secretName: {{ .secretName }}
    {{- end }}
  {{- end }}
  rules:
    {{- range .Values.ingress.hosts }}
    - host: {{ .host | quote }}
      http:
        paths:
          {{- range .paths }}
          - path: {{ .path }}
            pathType: {{ .pathType }}
            backend:
              service:
                name: {{ include "nginx-demo.serviceName" $ }}
                port:
                  number: {{ $.Values.service.port }}
          {{- end }}
    {{- end }}
{{- end }}
```

</details>
