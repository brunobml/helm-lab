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

After deploying your values (using your cluster's IngressClass, e.g. `traefik` for k3d/k3s or `nginx` for kind):

```bash
# If using kind without an ingress controller, install ingress-nginx:
# helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
# helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx \
#   --create-namespace --set controller.service.type=ClusterIP --wait

helm upgrade demo-dev ./charts/nginx-demo -n helm-lab \
  --reset-values -f ./charts/nginx-demo/values-dev.yaml \
  --set ingress.enabled=true --set ingress.className=nginx --wait --timeout 120s
kubectl get ingress -n helm-lab
```

Test routing through the Ingress controller using an ephemeral curl Pod (adjust the controller Service DNS for your cluster):

```bash
# For ingress-nginx:
kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -i --restart=Never -- -s -H "Host: chart-example.local" http://ingress-nginx-controller.ingress-nginx.svc.cluster.local/

# For k3s/k3d Traefik:
# kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -i --restart=Never -- -s -H "Host: chart-example.local" http://traefik.kube-system.svc.cluster.local/
```

## Break it and recover

Use the wrong ingress class with `--reset-values -f ./charts/nginx-demo/values-dev.yaml`:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab \
  --reset-values -f ./charts/nginx-demo/values-dev.yaml \
  --set ingress.enabled=true --set ingress.className=nonexistent --wait
```

Observe that rendering and applying still succeed, but the Ingress controller ignores the resource and traffic returns HTTP 404. Then restore the correct class using the upgrade command with `--set ingress.className=nginx` (or `traefik`). A `LoadBalancer` Service may stay pending on a local cluster without a cloud controller or MetalLB.

## Explain

What creates an Ingress object, and what actually handles its traffic?

> [!TIP]
> See [networking-explained.md](networking-explained.md) for detailed explanations and answers to this question.

## Cleanup and checkpoint

Disable the Ingress through a Helm upgrade, restore ClusterIP, and remove any
controller you installed solely for this exercise. Save `extension-networking-complete`.

<details>
<summary>Hint: values.yaml configuration block</summary>

```yaml
ingress:
  enabled: false
  className: ""
  annotations: {}
  hosts:
    - host: chart-example.local
      paths:
        - path: /
          pathType: Prefix
  tls: []
```

</details>

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
