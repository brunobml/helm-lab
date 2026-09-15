# nginx-demo

The starter application for [Helm Lab](../../README.md).
It renders one Deployment and one ClusterIP Service, with two NGINX replicas.
Start with [Lab 1](../../labs/01-first-chart.md); implement subsequent features
in this directory as you work through the labs.

From the repository root:

```bash
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo
helm install demo-dev ./charts/nginx-demo -n helm-lab --create-namespace --wait --timeout 120s
```

| Value | Default | Meaning |
| --- | --- | --- |
| `replicaCount` | `2` | Desired Pod count |
| `image.repository` | `nginx` | Container image repository |
| `image.tag` | `1.30.4-alpine` | Explicit NGINX version and image variant |
| `image.pullPolicy` | `IfNotPresent` | Use a local image if available |
| `service.type` | `ClusterIP` | How Kubernetes exposes the Service |
| `service.port` | `80` | Port clients use on the Service |
| `service.targetPort` | `80` | Port NGINX actually listens on |

The image tag comes from the [official NGINX image metadata](https://github.com/docker-library/official-images/blob/master/library/nginx).
A versioned tag reduces unexpected changes; a digest is required for immutable
image identity. `Chart.yaml`'s `version` versions this package; `appVersion`
describes the application. Neither automatically overrides `image.tag`.

Changing `service.port` to 8080 is supported. Changing `service.targetPort` to
8080 does not reconfigure NGINX, which still listens on 80. The declared
`containerPort` is also metadata, not server configuration.

Generated names are `<release>-deployment` and `<release>-service`. Selectors
use the release's `app` label. Preserve these contracts in the helper lab so
upgrades remain straightforward.
