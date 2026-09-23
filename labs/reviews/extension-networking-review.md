# Extension review: Networking

**Tested with:** Helm v3.19.0. kind (Kubernetes v1.35.0) + ingress-nginx chart 4.15.1, **and** k3d (k3s v1.35.5) + bundled Traefik. 2026-09-22.
**Result:**

- NodePort and disabled renders are correct.
- The Ingress routes on both clusters: `<h1>Hello from ...</h1>` via `ingress-nginx-controller.ingress-nginx.svc` on kind and via `traefik.kube-system.svc` on k3d.
- The wrong class returns **HTTP 404** from ingress-nginx, as described.

The commands in both pages undo the learner's dev configuration, and the explained break-it can't be reproduced at all.

## Bugs

### B1: The explained break-it and recovery commands delete the Ingress (high)

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set ingress.className=nonexistent --wait
```

This passes only `ingress.className`. Because a `--set` is present, Helm drops the previous values (Lab 3 review B1), so `ingress.enabled` reverts to `false` and **the Ingress is removed**. `kubectl get ingress` then shows `No resources found`, not the `nonexistent` class row the page shows. The recovery command has the same problem.

**Fix:** Always pass the full intent:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml \
  --set ingress.enabled=true --set ingress.className=nonexistent --wait
```

### B2: The lab's upgrade command drops the dev configuration (high)

The lab's Verify step:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set ingress.enabled=true --set ingress.className=nginx --wait
```

This silently reset `demo-dev` to chart defaults: **replicas 1 → 2, `extraEnv` removed, and the page reverted** from "Hello from Updated Helm Lab" to "Hello from Helm Lab" (verified). This contradicts Lab 3's convention ("Future labs use `--reset-values -f .../values-dev.yaml`"). Add `--reset-values -f ./charts/nginx-demo/values-dev.yaml`.

### B3: The explained page uses the wrong Ingress name (low)

It shows `demo-dev-ingress`. The hint template names the Ingress `{{ include "nginx-demo.serviceName" . }}`, which is **`demo-dev-service`**. Either fix the sample, or (better) add an `nginx-demo.ingressName` helper. An Ingress named `...-service` is confusing.

## Missing / outdated information

- **M1: ingress-nginx has been retired.** The Kubernetes project retired `ingress-nginx` (best-effort maintenance ended March 2026). The chart still installs, but recommending it for new learners in 2026 is questionable. Suggest:
  - making Traefik (bundled in k3d) or another maintained controller the primary path, and
  - adding a Gateway API variant. `helm create` already generates `templates/httproute.yaml` (see the Lab 0 review), so there's a natural hook.
- **M2: There are no concrete controller install steps for kind.** Step 4 says "install an Ingress controller appropriate to your local cluster and use its documented access method". The kind docs' manifest requires a cluster created with the `ingress-ready=true` node label and `extraPortMappings`, which the README's `kind create cluster` command doesn't set, so the controller Pod stays Pending. What works on the README's plain kind cluster (verified):

  ```bash
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx -n ingress-nginx --create-namespace \
    --set controller.service.type=ClusterIP --wait
  ```

  (It requires `helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx`, which the lab never mentions.)
- **M3: The values structure isn't specified.** Step 2 says "Add `ingress.enabled: false` and configurable class, hosts, paths, and TLS", but the hint template relies on an exact shape (`hosts[].host`, `hosts[].paths[].path/pathType`, `tls[].hosts/secretName`). Learners who invent their own shape won't match the template. Add the `values.yaml` block (it's in `extension-networking-complete`) to the hint.
- **M4:** The hint's default `pathType: ImplementationSpecific` behaves differently per controller. Suggest `Prefix` for predictable learning.

## Accuracy issues

- **I1:** Explained "the `ADDRESS` field will remain blank". On k3d/Traefik the correct-class Ingress gets an ADDRESS (`172.21.0.3`). On kind with a ClusterIP controller, even the *correct* class shows a blank ADDRESS, so a blank ADDRESS isn't a reliable signal there. Use the curl result as the signal.
- **I2:** The break-it note "A `LoadBalancer` Service may stay pending on a local cluster" is true for kind but **not** for k3d, where the bundled ServiceLB (klipper) assigns node IPs. Name the clusters.
- **I3:** The explained page lists the backend as `port: 80`. The actual rendered structure is `port: { number: 80 }`.

## Ease-of-following suggestions

- **S1:** The verify curl runs in namespace `default` without `-n`. That works, but add `-n helm-lab` for consistency with the other labs, and add `-o /dev/null -w '%{http_code}'` for the break-it so learners see `404` clearly.
- **S2:** Pin a newer curl image (`curlimages/curl:8.5.0` is from 2023), or use `curlimages/curl` without a tag in a learning context.
- **S3:** Cleanup: give the commands (`helm uninstall ingress-nginx -n ingress-nginx`, then an upgrade with the dev values and no ingress flags).
