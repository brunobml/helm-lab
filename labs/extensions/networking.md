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
host, pathType, class, and backend port. After deploying your values, send an
HTTP request through the controller with the configured Host header.

## Break it and recover

Use the wrong ingress class, observe that rendering still succeeds but traffic
is not routed by the intended controller, then restore the correct class.
A `LoadBalancer` Service may stay pending on a local cluster without an implementation.

## Explain

What creates an Ingress object, and what actually handles its traffic?

## Cleanup and checkpoint

Disable the Ingress through a Helm upgrade, restore ClusterIP, and remove any
controller you installed solely for this exercise. Save `extension-networking-complete`.
