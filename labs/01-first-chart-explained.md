# Lab 1: First chart — Explained

[Back to Lab 1: First chart](01-first-chart.md)

---

## Overview

In Lab 1, you learned how Helm connects values and templates to generate valid Kubernetes manifests, and you deployed your first release (`demo-dev`) into the cluster.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: What is the difference between a chart and a release?

#### TL;DR
- A **chart** is the uninstantiated recipe/package (code, templates, defaults in Git or a `.tgz` archive). It is equivalent to a **class** in object-oriented programming, or a Docker image.
- A **release** is a running, stateful installation of that chart in a Kubernetes cluster with a specific release name, namespace, and configuration values. It is equivalent to an **instance** of an object, or a running Docker container.

#### Deep Dive & Mechanism
1. **The Chart (Static Package):**
   - Located on disk at `charts/nginx-demo/` or stored in a registry.
   - It contains parameterizable template files (`templates/deployment.yaml`), metadata (`Chart.yaml`), and default values (`values.yaml`).
   - The chart itself creates zero resources in Kubernetes until it is installed.

2. **The Release (Live Instance):**
   - Created when you run `helm install <release-name> <chart>`.
   - Helm renders the chart templates using the provided values, sends the manifests to the Kubernetes API server, and tracks the resulting state in a Secret inside the release's namespace (e.g., `sh.helm.release.v1.demo-dev.v1`).
   - You can install multiple releases from the **exact same chart** in the same cluster (e.g., `demo-dev` and `demo-prod`). Each release has independent history, values, and Kubernetes objects.

---

### Question 2: Which files are Helm inputs, and which output is Kubernetes YAML?

#### TL;DR
- **Inputs:** `Chart.yaml`, `values.yaml` (and any `-f <custom-values>.yaml` or `--set` flags), built-in Helm objects (`.Release`, `.Chart`, `.Capabilities`), and the template files (`templates/*.yaml`).
- **Output:** Fully evaluated, standard Kubernetes YAML manifests sent to `kubectl` / API server (or printed to stdout when using `helm template`).

#### Deep Dive & Mechanism
```text
[values.yaml + CLI overrides] ──┐
[Chart.yaml metadata]         ──┼──> [Helm Template Engine (Go Text Template)] ──> [Raw Kubernetes YAML]
[templates/*.yaml]            ──┤
[Built-in Objects (.Release)] ──┘
```
- The files inside `templates/` are **not valid Kubernetes manifests on their own** because they contain Go template directives like `{{ .Release.Name }}`.
- When you run `helm template` or `helm install`, Helm's rendering pipeline evaluates all template expressions, substitutes values, and produces valid Kubernetes YAML.
- Kubernetes itself has no concept of Helm charts or templates; it only receives and stores standard Kubernetes resources (Deployments, Services, ConfigMaps).

---

### Question 3: How does the Service find the application's Pods?

#### TL;DR
The Service finds Pods using **label selectors** (`spec.selector`), which match against the Pods' labels (`spec.template.metadata.labels`).

#### Deep Dive & Mechanism
1. **The Selector-Label Relationship:**
   - In `service.yaml`:
     ```yaml
     spec:
       selector:
         app: {{ .Release.Name }}
     ```
     For release `demo-dev`, this evaluates to `app: demo-dev`.
   - In `deployment.yaml`:
     ```yaml
     template:
       metadata:
         labels:
           app: {{ .Release.Name }}
     ```
     When the Deployment controller creates Pods, each Pod is labeled with `app: demo-dev`.

2. **Endpoints & EndpointSlices:**
   - The Kubernetes `endpointslice` controller continuously watches for Pods matching `app: demo-dev`.
   - As soon as a Pod reaches the `Ready` condition, its IP address is added to the Service's `EndpointSlice`.
   - When a client sends traffic to the Service's ClusterIP (`demo-dev-service:80`), kube-proxy / CoreDNS load-balances the traffic across those healthy Pod IPs.
   - **Crucial Lesson:** If the Service selector has `app: demo-dev` but the Pod template labels say `app: nginx`, the Service will find zero endpoints and all HTTP requests will fail or time out!

---

## Break It and Recover — Detailed Walkthrough

### What the challenge asks:
> Temporarily misspell `.Values.replicaCount` in the Deployment template. Run `helm template` and inspect `replicas`: a missing value may render empty instead of producing an obvious template error. Restore the key and render again.

#### 1. What to Break
In `charts/nginx-demo/templates/deployment.yaml`, introduce a typo in the replica count key (e.g., changing `replicaCount` to `replicasCount`):

```yaml
spec:
  replicas: {{ .Values.replicasCount }}
```

#### 2. Run the Command
```bash
helm template demo-dev ./charts/nginx-demo
```

#### 3. The Result Observed
Look closely at the rendered `Deployment` output:
```yaml
# Source: nginx-demo/templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-dev-deployment
  labels:
    app: demo-dev
spec:
  replicas: 
  selector:
    matchLabels:
      app: demo-dev
```
Notice that `replicas:` is completely empty! Helm did **not** throw an error during rendering.

#### 4. Why This Failed (The Silent Nil Trap)
- In Go templates, accessing a non-existent key on a map (like `.Values.replicasCount`) does not raise an exception or abort by default; it evaluates to `nil`, which renders as an empty string `""`.
- In YAML, `replicas:` with nothing following it evaluates to `null`.
- If you were to apply this manifest to Kubernetes, the API server would reject it with a schema violation:
  ```text
  error: error validating "": error validating data: ValidationError(Deployment.spec.replicas): invalid type: got "null", expected "integer"
  ```
- **Why this matters:** Silent template omissions are dangerous. This is why production charts use the `required` function (e.g., `{{ required "replicaCount is required" .Values.replicaCount }}`) or JSON Schema validation (`values.schema.json`, covered in Lab 7).

#### 5. How to Recover
Restore the correct key name in `charts/nginx-demo/templates/deployment.yaml`:
```yaml
spec:
  replicas: {{ .Values.replicaCount }}
```

Verify that the template renders a valid integer:
```bash
helm template demo-dev ./charts/nginx-demo | grep "replicas:"
```
*Output:*
```yaml
  replicas: 2
```

---

## Key Takeaways

| Concept | Explanation |
| :--- | :--- |
| Chart vs. Release | Chart = Recipe / Package; Release = Deployed instance on the cluster. |
| Template Engine | Helm interpolates values into templates to produce standard Kubernetes YAML. |
| Service Discovery | Kubernetes routes traffic based strictly on matching label selectors to Pod labels. |
