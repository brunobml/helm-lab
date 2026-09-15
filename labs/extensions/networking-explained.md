# Extension: Networking — Explained

[Back to Extension: Networking](networking.md)

---

## Overview

In this extension, you configured Service types (ClusterIP vs NodePort), implemented an `Ingress` resource using `networking.k8s.io/v1`, and tested HTTP routing through the cluster's ingress controller.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: What creates an Ingress object, and what actually handles its traffic?

#### TL;DR
- **The Helm release** creates the `Ingress` object (a metadata declaration in the Kubernetes API).
- **The Ingress Controller** (e.g. Traefik, NGINX Ingress, Envoy, HAProxy) is an independent daemon that watches the Kubernetes API for Ingress objects and actually routes, terminates TLS, and proxies HTTP traffic to your Pods.

#### Deep Dive & Mechanism
1. **The Ingress Resource is Pure Metadata:**
   - When Helm applies `templates/ingress.yaml`, Kubernetes simply stores a record in etcd describing the routing rules:
     ```yaml
     rules:
       - host: "chart-example.local"
         http:
           paths:
             - path: /
               backend:
                 service:
                   name: demo-dev-service
                   port: 80
     ```
   - On its own, the Kubernetes API server does **not** listen on port 80/443 or route external HTTP packets.
2. **The Ingress Controller Does the Real Work:**
   - A cluster must run an Ingress Controller (k3s includes Traefik by default; kind or cloud clusters often install `ingress-nginx`).
   - The controller has a control loop that:
     1. Queries `IngressClass` (e.g. `ingressClassName: traefik`).
     2. Reads the routing rules and backend Services.
     3. Dynamically reconfigures its internal reverse-proxy routing tables.
     4. Accepts incoming HTTP requests on host ports (80/443), matches the `Host:` header, and proxies traffic directly to the backend Pod IPs.
3. **What happens if no Ingress Controller is installed?**
   - Helm will successfully create the Ingress object without any errors.
   - However, the `ADDRESS` field on the Ingress will remain blank, and external requests will never reach your application!

---

## Break It and Recover — Detailed Walkthrough

### What the challenge asks:
> Use the wrong ingress class (e.g. `--set ingress.className=nonexistent`), observe that rendering and applying still succeed but traffic is not routed by the intended controller, then restore the correct class.

#### 1. What to Break
Run `helm upgrade` setting the Ingress class to an arbitrary nonexistent name:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set ingress.className=nonexistent --wait --timeout 120s
```

#### 2. Observe the Ingress Resource
Check the Ingress object in Kubernetes:
```bash
kubectl get ingress -n helm-lab
```
*Output:*
```text
NAME               CLASS         HOSTS                 ADDRESS   PORTS   AGE
demo-dev-ingress   nonexistent   chart-example.local             80      30s
```
Notice:
- `helm upgrade` completed with exit code 0.
- Kubernetes successfully created the `Ingress` object.
- However, the `ADDRESS` column remains **completely blank**!

#### 3. Test Ingress Traffic Routing
Attempt to send traffic to Traefik using the virtual host:
```bash
kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -i --restart=Never -- -s -H "Host: chart-example.local" http://traefik.kube-system.svc.cluster.local/
```
*Output:*
```text
404 page not found
```

#### 4. Why This Failed
- In modern Kubernetes (`networking.k8s.io/v1`), Ingress controllers only process Ingress objects whose `spec.ingressClassName` matches their registered class name (e.g. `traefik` in k3s/k3d, or `nginx` in `ingress-nginx`).
- Because `className` was `nonexistent`, Traefik ignored the resource completely.
- The Ingress object sat dormant in etcd, unmanaged by any controller.

#### 5. How to Recover
Restore the valid Ingress class (e.g. `traefik` for k3s/k3d):

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set ingress.className=traefik --wait --timeout 120s
```

Verify that the Ingress acquires an address and routes HTTP traffic:
```bash
kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -i --restart=Never -- -s -H "Host: chart-example.local" http://traefik.kube-system.svc.cluster.local/
```
*Output:*
```html
<h1>Hello from Helm Lab</h1>
```

---

## Key Takeaways

| Component | Responsibility |
| :--- | :--- |
| Ingress Resource | Declarative specification of hostnames and paths. |
| Ingress Controller | The reverse proxy daemon that actually accepts and routes network traffic. |
| `IngressClass` | Decouples multiple controllers running in the same cluster. |
