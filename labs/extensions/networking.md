# Extension: Networking

**Start:** Lab 7 or later (do all four extensions before Lab 10; later labs build on them); save a checkpoint before experimenting.
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

Deploy with a real Ingress controller. This lab uses **Traefik**: k3d/k3s ships it
(IngressClass `traefik` in `kube-system`), and on kind you install it with its Helm chart:

```bash
# kind only (k3d/k3s already runs Traefik in kube-system):
helm repo add traefik https://traefik.github.io/charts
helm upgrade --install traefik traefik/traefik --version 41.6.0 -n traefik --create-namespace \
  --set service.spec.type=ClusterIP --wait
kubectl get ingressclass   # expect: traefik
```

> [!NOTE]
> The community `ingress-nginx` controller was retired by the Kubernetes project (best-effort
> maintenance ended in March 2026), so it is no longer the default here. If your organization still
> runs it, the chart works the same way with `--set ingress.className=nginx`.

Enable the Ingress while keeping your dev values:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab \
  --reset-values -f ./charts/nginx-demo/values-dev.yaml \
  --set ingress.enabled=true --set ingress.className=traefik --wait --timeout 120s
kubectl get ingress -n helm-lab
```

Test routing through the controller from an ephemeral curl Pod. The controller Service DNS name
depends on where Traefik runs:

```bash
# kind (Traefik installed above, namespace traefik):
TRAEFIK=http://traefik.traefik.svc.cluster.local/
# k3d/k3s (bundled Traefik, namespace kube-system):
# TRAEFIK=http://traefik.kube-system.svc.cluster.local/

kubectl run curl-test -n helm-lab --image=curlimages/curl:8.5.0 --rm -i --restart=Never -- \
  -s -H "Host: chart-example.local" "$TRAEFIK"
```

*Expect:* your page's HTML. Use the curl response as the signal. On kind, the Ingress `ADDRESS`
column stays blank because the controller Service is `ClusterIP`; on k3d it shows a node IP.

## Break it and recover

Use the wrong ingress class with `--reset-values -f ./charts/nginx-demo/values-dev.yaml`:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab \
  --reset-values -f ./charts/nginx-demo/values-dev.yaml \
  --set ingress.enabled=true --set ingress.className=nonexistent --wait
```

Observe that rendering and applying still succeed, but the Ingress controller ignores the resource and traffic returns HTTP 404:

```bash
kubectl run curl-test -n helm-lab --image=curlimages/curl:8.5.0 --rm -i --restart=Never -- \
  -s -o /dev/null -w '%{http_code}\n' -H "Host: chart-example.local" "$TRAEFIK"
```

Then restore the correct class with `--set ingress.className=traefik`. A `LoadBalancer` Service stays
pending on kind (no cloud controller or MetalLB), while k3d's bundled ServiceLB assigns a node IP.

## Explain

What creates an Ingress object, and what actually handles its traffic?

> [!TIP]
> See [networking-explained.md](networking-explained.md) for detailed explanations and answers to this question.

## Cleanup and checkpoint

Disable the Ingress and restore your dev configuration, then remove the controller if you installed
it only for this exercise (kind):

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait
helm uninstall traefik -n traefik && kubectl delete namespace traefik
```

Save `extension-networking-complete`.

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
