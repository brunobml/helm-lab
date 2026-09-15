# Lab 0: Chart creation

**Start:** An empty workspace, a practice branch, or a new worktree.
**Goal:** Scaffold a chart using `helm create`, examine the generated structure, strip unnecessary boilerplate, and craft a minimal working starter chart.

---

## The concept

When you start a new Helm project, you almost never write all the directories from scratch. Helm provides `helm create` to scaffold a chart. However, `helm create` generates an extensive set of production templates (Ingress, ServiceAccount, HPA, tests, helper macros) that can be overwhelming when starting out.

In real-world engineering, teams often run `helm create` and then **strip the templates down to the bare essentials**, adding components back incrementally as requirements demand. That is exactly what we will do here.

---

## Steps

### 1. Scaffold the initial chart

From your repository or practice directory root, run:

```bash
helm create charts/nginx-demo
```

### 2. Inspect the generated structure

List the generated files:

```bash
ls -la charts/nginx-demo
ls -la charts/nginx-demo/templates
```

Notice what Helm created:
- **`Chart.yaml`**: The chart's primary metadata (name, version, description).
- **`values.yaml`**: Default configuration values for the chart templates.
- **`charts/`**: Directory for chart dependencies (subcharts). Empty for now.
- **`.helmignore`**: Patterns to ignore when packaging the chart (similar to `.gitignore`).
- **`templates/`**: A full microservice scaffold containing:
  - `deployment.yaml`, `service.yaml`, `hpa.yaml`, `ingress.yaml`, `serviceaccount.yaml`
  - `_helpers.tpl` (template helper definitions)
  - `NOTES.txt` (post-installation usage text)
  - `tests/test-connection.yaml` (smoke test hook)

### 3. Strip the boilerplate

To learn how Helm templates work from first principles, delete all files inside `templates/`:

```bash
rm -rf charts/nginx-demo/templates/*
```

Keep `.helmignore` and the `charts/` folder intact.

### 4. Configure `Chart.yaml`

Replace `charts/nginx-demo/Chart.yaml` with clean, minimal metadata:

```yaml
apiVersion: v2
name: nginx-demo
description: A small NGINX application for the Helm Lab exercises
type: application
version: 0.1.0
appVersion: "1.30.4"
```

> [!NOTE]
> - **`apiVersion: v2`**: Required for Helm 3 charts (`v1` was used in Helm 2).
> - **`type: application`**: A deployable chart (as opposed to `library`).
> - **`version: 0.1.0`**: The version of the **chart package itself**. Must follow strict [Semantic Versioning](https://semver.org/).
> - **`appVersion: "1.30.4"`**: The version of the **underlying application** (NGINX). Always quote it so YAML parsers don't misinterpret numbers like `1.10` as floats.

### 5. Create a minimal `values.yaml`

Replace `charts/nginx-demo/values.yaml` with the minimal inputs our application needs:

```yaml
# replicaCount controls how many NGINX Pods the Deployment runs.
replicaCount: 2

image:
  repository: nginx
  tag: "1.30.4-alpine"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 80
```

### 6. Create the minimal templates

Create `charts/nginx-demo/templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-deployment
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
        - name: nginx
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: 80
```

Create `charts/nginx-demo/templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}-service
spec:
  type: {{ .Values.service.type }}
  ports:
    - port: {{ .Values.service.port }}
      targetPort: {{ .Values.service.targetPort }}
      protocol: TCP
  selector:
    app: {{ .Release.Name }}
```

---

## Verify

Run Helm's linter and template renderer from the repository root:

```bash
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo
```

Expect:
- `1 chart(s) linted, 0 chart(s) failed`
- Rendered Kubernetes YAML containing `demo-dev-deployment` (replicas: 2) and `demo-dev-service`.

---

## Break it and recover

In `Chart.yaml`, temporarily change `version: 0.1.0` to an invalid SemVer value: `version: 1`.
Run `helm lint ./charts/nginx-demo` and observe:

```text
[ERROR] Chart.yaml: version "1" is not a valid SemVer
```

Helm enforces Semantic Versioning on the chart version. Restore `version: 0.1.0` and verify that `helm lint` passes again.

---

## Explain

- What is the difference between `version` and `appVersion` in `Chart.yaml`?
- What does `.helmignore` do when running `helm package`?
- Why did we delete `templates/*` instead of using the generated boilerplate immediately?

> [!TIP]
> See [00-chart-creation-explained.md](00-chart-creation-explained.md) for detailed explanations and answers to these questions.

---

## Cleanup and checkpoint

If you are tracking your own progress in git, stage and commit your starter chart:

```bash
git add charts/nginx-demo
git commit -m "Complete lab 0: scaffold starter chart"
git tag lab-00-start
```

Next: Continue to [Lab 1: First chart](01-first-chart.md) to install and run this application on your cluster.
