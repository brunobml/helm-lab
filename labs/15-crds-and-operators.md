# Lab 15: CRDs and operators

**Start:** Lab 14 complete (`lab-14-complete`). Namespace `helm-lab` on your disposable cluster with internet access.
**Goal:** Understand how Helm handles Custom Resource Definitions (CRDs) and operators, master the native `crds/` directory and its upgrade limitations, learn how production operators (`cert-manager`) manage CRD lifecycles, and execute manual CRD upgrade playbooks.

Custom Resource Definitions (CRDs) extend the Kubernetes API with domain-specific resources (such as `Issuer`, `Certificate`, `PrometheusRule`, or `Database`). However, CRDs are the single most common source of surprises and operational failures in Helm.

While Helm manages *namespaced release lifecycles* (installing, upgrading, rolling back, and deleting manifests), CRDs are *cluster-scoped API extensions*. If Helm deleted a CRD on `helm uninstall`, Kubernetes would instantly cascade-delete **all instances** of that Custom Resource across every namespace in the entire cluster. To avoid catastrophic accidental data loss, Helm 3 adopted strict, controversial design choices for CRDs.

---

## Part A: The native `crds/` directory and the upgrade trap

### How Helm 3 handles the `crds/` directory

Helm 3 introduced a dedicated top-level directory named `crds/` in a chart:

1. **Installed once:** Helm installs YAML files in `crds/` only during `helm install` (before any templates are rendered).
2. **Never templated:** Files in `crds/` are raw YAML. Helm template functions (`{{ .Values... }}`) are not evaluated.
3. **Never upgraded:** `helm upgrade` **completely skips** the `crds/` directory. If an upstream chart adds new fields or versions to its CRD in `crds/`, Helm will not update the cluster's CRD.
4. **Never deleted:** `helm uninstall` leaves all CRDs in `crds/` behind on the cluster.
5. **Bypassable:** You can pass `--skip-crds` to `helm install` to suppress installing CRDs from `crds/`.

Let's observe this behavior hands-on using the educational `charts/crd-demo` chart.

### Step 1: Inspect the demo chart structure

If you are practicing on a branch from `lab-14-complete`, check out the `charts/crd-demo` starter:

```bash
git checkout lab-15-complete -- charts/crd-demo
```

Inspect `charts/crd-demo`:

```bash
ls -la charts/crd-demo
ls -la charts/crd-demo/crds
ls -la charts/crd-demo/templates
```

Notice that:

- `crds/crontabs.yaml` defines the CustomResourceDefinition `crontabs.stable.example.com` (currently with only `cronSpec` and `image`).
- `templates/crontab.yaml` defines an instance of kind `CronTab` named `my-cron`.

Render the chart templates locally:

```bash
helm template crd-demo charts/crd-demo
```

*Observation:* Notice that `helm template` outputs **only** `templates/crontab.yaml`. By default, `helm template` does not output files from `crds/`!

To include CRDs in rendered output (e.g. for offline `kubectl apply` pipelines), you must pass `--include-crds`:

```bash
helm template crd-demo charts/crd-demo --include-crds | grep "kind:"
```

### Step 2: Install the chart and verify CRD creation

Deploy the chart into `helm-lab`:

```bash
helm install crd-demo charts/crd-demo -n helm-lab
```

Verify that Helm installed the cluster-wide CRD and the namespaced Custom Resource:

```bash
# Verify the CRD exists at cluster scope:
kubectl get crd crontabs.stable.example.com

# Verify the Custom Resource instance exists in helm-lab:
kubectl get crontabs -n helm-lab
```

Inspect the schema currently registered on the cluster:

```bash
kubectl get crd crontabs.stable.example.com -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties}'
```

*Expect:* `{"cronSpec":{"type":"string"},"image":{"type":"string"}}`.

### Step 3: Trigger the silent CRD upgrade trap

Now simulate an upstream chart update: the maintainer updates the chart files to support a new `spec.replicas` field.

1. Edit `charts/crd-demo/crds/crontabs.yaml` to add `replicas` to `openAPIV3Schema.properties.spec.properties`:

   ```yaml
                   cronSpec:
                     type: string
                   image:
                     type: string
                   replicas:
                     type: integer
   ```

2. Bump the chart version in `charts/crd-demo/Chart.yaml` to `0.2.0`.

Now upgrade the release while supplying the new `replicas` value:

```bash
helm upgrade crd-demo charts/crd-demo -n helm-lab --set crontab.replicas=3
```

Watch the terminal carefully. You will see:

```text
Warning: unknown field "spec.replicas"
Release "crd-demo" has been upgraded. Happy Helming!
```

Now check what happened to the CRD and the Custom Resource on the cluster:

```bash
# 1. Check if the cluster CRD was updated with the new field:
kubectl get crd crontabs.stable.example.com -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.replicas}'

# 2. Check the live Custom Resource object on the cluster:
kubectl get crontab my-cron -n helm-lab -o jsonpath='{.spec}'

# 3. Check what Helm recorded in its release manifest:
helm get manifest crd-demo -n helm-lab | grep replicas
```

> [!WARNING]
> **The Silent Drop Trap:**
> Helm reported the upgrade as successful! However:
>
> 1. Helm **did not touch** the CRD schema on the cluster. The cluster CRD still lacks `replicas`.
> 2. The Kubernetes API server received `replicas: 3` in the submitted manifest, but because the cluster CRD schema didn't recognize `replicas`, Kubernetes **silently stripped the field**! `kubectl get crontab` shows only `cronSpec` and `image`.
> 3. Even worse: Helm's release Secret now records `replicas: 3`. Helm believes the field is deployed.

### Step 4: Execute the manual CRD upgrade playbook

Because Helm deliberately refuses to upgrade CRDs in `crds/`, the cluster operator must upgrade CRDs out-of-band using `kubectl`:

```bash
# Manually apply the updated CRD schema to the cluster:
kubectl apply -f charts/crd-demo/crds/crontabs.yaml
```

Verify that the cluster CRD now knows about `replicas`:

```bash
kubectl get crd crontabs.stable.example.com -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.replicas}'
```

*Expect:* `{"type":"integer"}`.

Now, test what happens if you re-run the upgrade with the **same** value:

```bash
helm upgrade crd-demo charts/crd-demo -n helm-lab --set crontab.replicas=3
kubectl get crontab my-cron -n helm-lab -o jsonpath='{.spec}'
```

*Observation:* The live Custom Resource **still does not have `replicas`!** Why? Because Helm's 3-way strategic merge patch compares the newly rendered manifest (`replicas: 3`) against the last-applied release manifest (`replicas: 3`), sees zero difference, and sends nothing to the cluster!

To force Helm to re-synchronize the custom resource with the updated schema, pass a changed value:

```bash
helm upgrade crd-demo charts/crd-demo -n helm-lab --set crontab.replicas=5
```

Verify that the live Custom Resource now contains `replicas: 5`:

```bash
kubectl get crontab my-cron -n helm-lab -o jsonpath='{.spec.replicas}'
```

*Expect:* `5`.

### Step 5: Test uninstall and observe the orphaned CRD

Uninstall the release:

```bash
helm uninstall crd-demo -n helm-lab
```

Verify what was deleted and what was preserved:

```bash
# The custom resource is deleted:
kubectl get crontabs -n helm-lab

# The CRD is STILL in the cluster!
kubectl get crd crontabs.stable.example.com
```

Helm deleted the namespaced `CronTab` instance because it was in `templates/`. But Helm **never** deletes the CRD in `crds/`.

Clean up the demo CRD manually:

```bash
kubectl delete crd crontabs.stable.example.com
```

---

## Part B: The production operator pattern (`cert-manager`)

Because the native `crds/` directory does not support upgrades, many major Kubernetes operators (including `cert-manager`) do not use `crds/` exclusively. Instead, they provide alternative patterns.

### How `cert-manager` solves the CRD dilemma

Inspect the default CRD configuration in `jetstack/cert-manager`:

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update jetstack
helm show values jetstack/cert-manager --version v1.16.2 | grep -A 15 "crds:"
```

Notice two critical settings:

1. `crds.enabled: false` (default): By default, cert-manager expects operators to install CRDs out-of-band via `kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/.../cert-manager.crds.yaml`.
2. When `crds.enabled: true`: cert-manager renders CRDs as regular manifests inside `templates/`, but attaches a special annotation:
   `helm.sh/resource-policy: keep`

Why does cert-manager do this?

- Because CRDs are in `templates/`, `helm upgrade` **does** update them when upgrading cert-manager!
- Because of `"helm.sh/resource-policy": keep`, `helm uninstall` **will not delete** the CRDs, protecting cluster certificates from catastrophic garbage collection!

### Step 6: Install `cert-manager` with managed CRDs

Install `cert-manager` v1.16.2 into its own namespace with `crds.enabled=true`:

```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --version v1.16.2 \
  --set crds.enabled=true \
  --wait
```

Verify that all three cert-manager pods are Running and Ready:

```bash
kubectl get pods -n cert-manager
```

Verify the 6 custom resource definitions created by cert-manager:

```bash
kubectl get crd | grep cert-manager.io
```

Inspect the annotations on one of the CRDs:

```bash
kubectl get crd certificates.cert-manager.io -o jsonpath='{.metadata.annotations.helm\.sh/resource-policy}'
```

*Expect:* `keep`.

### Step 7: Create a Custom Resource and test reconciliation

Create a self-signed `Issuer` and a `Certificate` in `helm-lab`:

```bash
cat <<EOF | kubectl apply -n helm-lab -f -
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: lab-selfsigned-issuer
  namespace: helm-lab
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: lab-demo-tls
  namespace: helm-lab
spec:
  secretName: lab-demo-tls-secret
  dnsNames:
    - demo.helm-lab.local
  issuerRef:
    name: lab-selfsigned-issuer
    kind: Issuer
EOF
```

Verify that the cert-manager operator watches the CR, reconciles it, and issues the TLS Secret:

```bash
# Check certificate status:
kubectl get certificate lab-demo-tls -n helm-lab

# Check the generated Secret:
kubectl get secret lab-demo-tls-secret -n helm-lab
```

*Expect:* `READY: True` and Secret `lab-demo-tls-secret` of type `kubernetes.io/tls`.

### Step 8: Test uninstall safety with `resource-policy: keep`

Now uninstall `cert-manager`:

```bash
helm uninstall cert-manager -n cert-manager
```

Look closely at Helm's output:

```text
These resources were kept due to the resource policy:
[CustomResourceDefinition] certificaterequests.cert-manager.io
[CustomResourceDefinition] certificates.cert-manager.io
[CustomResourceDefinition] challenges.acme.cert-manager.io
[CustomResourceDefinition] clusterissuers.cert-manager.io
[CustomResourceDefinition] issuers.cert-manager.io
[CustomResourceDefinition] orders.acme.cert-manager.io

release "cert-manager" uninstalled
```

Now verify the state of the cluster:

```bash
# CRDs are preserved:
kubectl get crd | grep cert-manager.io

# Existing Certificate in helm-lab is preserved:
kubectl get certificate -n helm-lab

# Existing TLS Secret is preserved:
kubectl get secret lab-demo-tls-secret -n helm-lab
```

If cert-manager had not used `helm.sh/resource-policy: keep`, Helm would have deleted the `Certificate` CRD, triggering Kubernetes cascading garbage collection to immediately delete `lab-demo-tls` and all certificates across the entire cluster!

Clean up the cert-manager resources:

```bash
kubectl delete certificate lab-demo-tls -n helm-lab
kubectl delete issuer lab-selfsigned-issuer -n helm-lab
kubectl delete secret lab-demo-tls-secret -n helm-lab
kubectl delete crd certificaterequests.cert-manager.io certificates.cert-manager.io challenges.acme.cert-manager.io clusterissuers.cert-manager.io issuers.cert-manager.io orders.acme.cert-manager.io
kubectl delete namespace cert-manager
```

---

## Part C: Ordering traps and hook interactions

### Trap 1: The Missing CRD Error

What happens if you try to deploy a Custom Resource before its CRD is registered on the cluster?

Try applying an `Issuer` right now (the CRDs were deleted in the previous step):

```bash
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: orphan-issuer
  namespace: helm-lab
spec:
  selfSigned: {}
EOF
```

*Expect Error:*

```text
Error from server (NotFound): error when creating "STDIN": the server could not find the requested resource (post issuers.cert-manager.io)
# or in client validation mode:
# error: resource mapping not found for name: "orphan-issuer" namespace: "helm-lab" from "STDIN": no matches for kind "Issuer" in version "cert-manager.io/v1"
```

The Kubernetes API server rejects the resource at the discovery layer because the API group and kind do not exist.

### Trap 2: Umbrella charts with operator and custom resources

A common anti-pattern is building an umbrella chart that lists an operator chart as a dependency and includes custom resources in `templates/`:

```text
my-umbrella/
  Chart.yaml          # dependencies: [name: cert-manager]
  templates/
    issuer.yaml       # kind: Issuer (Custom Resource)
```

Why does this fail on a fresh cluster?

- In Helm 3, Helm builds its REST mapping client-side for all resources up front before anything is applied.
- Because `Issuer` is not yet established on the cluster API discovery, Helm aborts immediately before installing anything:

```text
Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest: resource mapping not found for name: "my-issuer" namespace: "" from "": no matches for kind "Issuer" in version "cert-manager.io/v1" ensure CRDs are installed first
```

- Even if the operator chart installs CRDs via `crds/`, the operator controller pod has not started yet. Any custom resource that requires immediate webhook validation or reconciliation will fail or block the release.

**Production Solution:** Always separate operator installation from custom resource consumption into two distinct deployment steps or releases.

### Trap 3: Helm hook ordering with CRDs

Helm lifecycle hooks have specific ordering rules relative to CRDs:

1. `crds/` are installed before anything else.
2. `pre-install` hooks run next.
3. `templates/` (and normal chart resources) are applied.
4. `post-install` hooks run last.

This means:

- A `pre-install` hook **cannot** create a Custom Resource if the CRD is packaged in `templates/` (the CRD does not exist yet).
- A `pre-install` hook **cannot** rely on operator controller logic (the operator pod is in `templates/` and hasn't started).
- Any hook that generates or validates Custom Resources must be a `post-install` or `post-upgrade` hook, and must include retry logic while waiting for the operator to become Ready.

---

## CRD Management Architecture Comparison

| Strategy | Where CRDs Live | Upgrades Supported? | Uninstall Deletes CRDs? | Best Used For |
| :--- | :--- | :--- | :--- | :--- |
| **Native `crds/` Directory** | `<chart>/crds/` | ❌ No (requires manual `kubectl apply`) | ❌ No (never deleted) | Simple charts where CRDs rarely change schema. |
| **Templated with `keep` policy** | `<chart>/templates/` | ✅ Yes (`helm upgrade`) | ❌ No (`resource-policy: keep`) | Complex operators (`cert-manager`) with evolving schemas. |
| **Separate CRD Chart** | Dedicated `<chart>-crds` chart | ✅ Yes (`helm upgrade <chart>-crds`) | ❌ No (annotated with `keep`) | Enterprise fleets (`traefik-crd`, `prometheus-operator-crds`). |
| **Out-of-band / GitOps Pipeline** | Raw manifests or Kustomize | ✅ Yes (`kubectl apply` before Helm) | ❌ No (managed by pipeline) | Strict GitOps environments (Argo CD, Flux). |

---

## Verify

Run these commands to confirm your understanding:

```bash
# 1. Verify helm template omits crds/ by default:
helm template crd-demo charts/crd-demo | grep -i "CustomResourceDefinition" || echo "CRD omitted as expected"

# 2. Verify --include-crds includes them:
helm template crd-demo charts/crd-demo --include-crds | grep -i "CustomResourceDefinition"
```

---

## Cleanup and Checkpoint

Ensure all test releases and CRDs are removed:

```bash
helm uninstall crd-demo -n helm-lab --ignore-not-found
kubectl delete crd crontabs.stable.example.com --ignore-not-found
```

Check git status to ensure your practice working tree is ready:

```bash
git status
```

---

## Explain: deepen your understanding

After completing this lab, you should be able to answer:

1. Why did Helm 3 design the `crds/` directory to be install-only and skip upgrades and deletions?
2. What is the Kubernetes silent field drop, and why does Helm report success even when a Custom Resource drops new fields?
3. Why does `helm upgrade` with the same values fail to re-apply dropped fields even after `kubectl apply -f crds/...` upgrades the CRD schema?
4. How does `helm.sh/resource-policy: keep` protect CRDs when operators place them inside `templates/`?

> [!TIP]
> See [15-crds-and-operators-explained.md](15-crds-and-operators-explained.md) for deep architectural walkthroughs, 3-way merge desync mechanics, and production CRD migration playbooks.
