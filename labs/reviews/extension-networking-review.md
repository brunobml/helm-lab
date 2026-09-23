# Extension review: Networking

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The upgrades now keep the dev values (replicas 1, the updated page). The wrong class keeps the Ingress and returns 404. There's a values hint with `Prefix`, and an ingress-nginx install hint for kind. The explained Ingress name is fixed. k3d/Traefik still routes.

## Still open (minor)

- **M1:** ingress-nginx is retired. Consider Traefik or Gateway API as the primary path.
- **I1 / I2:** A blank `ADDRESS` isn't a reliable signal on kind; the `LoadBalancer` pending note depends on the cluster.
- **I3:** The explained backend shows `port: 80` instead of `port: { number: 80 }`.
- **S2 / S3** as before.
