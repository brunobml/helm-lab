# Lab 16: Production hardening and chart best practices

**Start:** Lab 15 complete (`lab-15-complete`). Namespace `helm-lab` on your disposable cluster with internet access.
**Goal:** Harden the `nginx-demo` chart for enterprise production, achieving compliance with the Kubernetes Pod Security Standard (`restricted` profile), zero-downtime availability via `PodDisruptionBudget` and `topologySpreadConstraints`, network micro-segmentation with `NetworkPolicy`, strict schema constraints, auto-generated documentation via `helm-docs`, and CI policy validation with `kubeconform`.

A chart that renders valid YAML and runs in development is not yet a chart that is safe to run in production. Production Kubernetes clusters enforce strict security boundaries, admission policies, resource quotas, and high-availability guarantees.

In this lab, you will transform `charts/nginx-demo` into a hardened, production-grade chart that complies with the highest Kubernetes security standards.

---

## Part A: Workload security and the Pod Security `restricted` profile

Modern Kubernetes clusters (v1.25+) feature built-in **Pod Security Standards** with three levels: `privileged`, `baseline`, and `restricted`. The `restricted` profile enforces security-hardened pod best practices.

To pass the `restricted` profile, a pod must satisfy all of the following:

1. `spec.securityContext.runAsNonRoot: true`
2. `spec.securityContext.seccompProfile.type: RuntimeDefault` (or `Localhost`)
3. `spec.containers[*].securityContext.allowPrivilegeEscalation: false`
4. `spec.containers[*].securityContext.capabilities.drop: ["ALL"]`
5. `spec.containers[*].securityContext.readOnlyRootFilesystem: true`
6. `spec.containers[*].securityContext.runAsNonRoot: true`
7. `spec.containers[*].securityContext.runAsUser: <non-zero>` (cannot run as UID 0)

### Step 1: Switch to unprivileged NGINX and unprivileged port

Standard NGINX (`nginx:alpine`) runs as root (UID 0), listens on privileged port 80, and writes caches to `/var/cache/nginx`. To satisfy `restricted`, we switch to `nginxinc/nginx-unprivileged:1.27-alpine`, which runs as UID 101 (`nginx`) and listens on port 8080.

In `charts/nginx-demo/values.yaml`:

```yaml
image:
  repository: nginxinc/nginx-unprivileged
  tag: "1.27-alpine"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

livenessProbe:
  httpGet:
    path: /
    port: 8080

readinessProbe:
  httpGet:
    path: /
    port: 8080
```

*Note:* External traffic still connects to Service port `80`, but Kubernetes proxies it to container port `8080`.

### Step 2: Configure Pod and container security contexts

Add production-grade security contexts to `charts/nginx-demo/values.yaml`:

```yaml
# Pod-level security context
podSecurityContext:
  runAsNonRoot: true
  seccompProfile:
    type: RuntimeDefault

# Container-level security context
securityContext:
  allowPrivilegeEscalation: false
  capabilities:
    drop:
      - ALL
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 101
```

### Step 2b: Render security contexts in `templates/deployment.yaml` and update containerPort

Values in `values.yaml` only take effect when rendered in templates. Update `charts/nginx-demo/templates/deployment.yaml`:

1. Under `spec.template.spec`, add `podSecurityContext`:

   ```yaml
         {{- with .Values.podSecurityContext }}
         securityContext:
           {{- toYaml . | nindent 8 }}
         {{- end }}
   ```

2. Under `spec.template.spec.containers[0]`, add `securityContext`:

   ```yaml
             {{- with .Values.securityContext }}
             securityContext:
               {{- toYaml . | nindent 12 }}
             {{- end }}
   ```

3. Update the container port to use `targetPort`:

   ```yaml
             ports:
               - containerPort: {{ .Values.service.targetPort | default 80 }}
   ```

### Step 3: Handle `readOnlyRootFilesystem` with `emptyDir` mounts

When `readOnlyRootFilesystem: true` is enabled, the container's root filesystem cannot be written to. However, NGINX requires write access to `/tmp`, `/var/cache/nginx`, and `/var/run`.

In `charts/nginx-demo/templates/deployment.yaml`, dynamically mount writable `emptyDir` volumes when `readOnlyRootFilesystem` is active:

```yaml
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
            {{- if and .Values.securityContext .Values.securityContext.readOnlyRootFilesystem }}
            - name: tmp
              mountPath: /tmp
            - name: cache
              mountPath: /var/cache/nginx
            - name: run
              mountPath: /var/run
            {{- end }}
...
      volumes:
        - name: html
          configMap:
            name: {{ .Release.Name }}-page
        {{- if and .Values.securityContext .Values.securityContext.readOnlyRootFilesystem }}
        - name: tmp
          emptyDir: {}
        - name: cache
          emptyDir: {}
        - name: run
          emptyDir: {}
        {{- end }}
```

### Step 4: Harden test hooks and migration Jobs

Every Pod created by a release—including `test` hooks and `pre-install` Jobs—is evaluated by the Pod Security admission controller.

Ensure both `templates/tests/http.yaml` and `templates/migration-job.yaml` contain compliant `securityContext` settings:

```yaml
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: migrate # or http
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
            readOnlyRootFilesystem: true
            runAsNonRoot: true
            runAsUser: 1000 # non-root UID
```

---

## Part B: Availability and resilience hardening

### Step 5: Add a PodDisruptionBudget (PDB)

A `PodDisruptionBudget` prevents voluntary disruptions (e.g. `kubectl drain` during node upgrades) from evicting all replicas simultaneously.

Create `charts/nginx-demo/templates/pdb.yaml`:

```yaml
{{- if .Values.podDisruptionBudget.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "nginx-demo.deploymentName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
spec:
  {{- if .Values.podDisruptionBudget.minAvailable }}
  minAvailable: {{ .Values.podDisruptionBudget.minAvailable }}
  {{- end }}
  {{- if .Values.podDisruptionBudget.maxUnavailable }}
  maxUnavailable: {{ .Values.podDisruptionBudget.maxUnavailable }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "nginx-demo.selectorLabels" . | nindent 6 }}
{{- end }}
```

Add configuration to `values.yaml`:

```yaml
podDisruptionBudget:
  enabled: false
  minAvailable: 1
```

### Step 6: Add topology spread constraints and default resources

In `charts/nginx-demo/templates/deployment.yaml`, allow distributing Pods across nodes or availability zones. Place this block inside `spec.template.spec`, alongside `securityContext`:

```yaml
      {{- with .Values.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

In `values.yaml`, provide default resource requests and limits:

```yaml
resources:
  requests:
    cpu: 50m
    memory: 64Mi
  limits:
    cpu: 200m
    memory: 128Mi

topologySpreadConstraints: []
```

---

## Part C: Network micro-segmentation with NetworkPolicy

### Step 7: Create a NetworkPolicy template

Create `charts/nginx-demo/templates/networkpolicy.yaml` to restrict traffic:

```yaml
{{- if .Values.networkPolicy.enabled }}
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: {{ include "nginx-demo.deploymentName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
spec:
  podSelector:
    matchLabels:
      {{- include "nginx-demo.selectorLabels" . | nindent 6 }}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector: {}
        - namespaceSelector: {}
      ports:
        - protocol: TCP
          port: {{ .Values.service.targetPort | default 80 }}
  egress:
    # Allow DNS resolution to CoreDNS
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53
{{- end }}
```

Add to `values.yaml`:

```yaml
networkPolicy:
  enabled: false
```

---

## Part D: Auto-generated documentation with `helm-docs`

Documenting chart values manually leads to stale documentation. [helm-docs](https://github.com/norwoodj/helm-docs) parses docstrings prefixed with `# --` in `values.yaml` and auto-generates Markdown tables.

Add `# --` docstring comments above the parameters in `charts/nginx-demo/values.yaml` (or verify them if working from the repository):

```yaml
# -- Number of replicas to deploy
replicaCount: 1

image:
  # -- Container image repository
  repository: nginxinc/nginx-unprivileged
  # -- Image pull policy
  pullPolicy: IfNotPresent
  # -- Overrides the image tag whose default is the chart appVersion
  tag: ""
```

Run `helm-docs` using Docker (passing `--user` so generated files are owned by your current user):

```bash
docker run --rm -v "$(pwd)/charts/nginx-demo":/helm-docs --user "$(id -u):$(id -g)" jnorwood/helm-docs:v1.14.2
```

Inspect `charts/nginx-demo/README.md`:

```bash
head -45 charts/nginx-demo/README.md
```

Notice that all parameters, types, and defaults are cataloged. Parameters documented with `# -- <description>` in `values.yaml` automatically populate the Description column.

---

## Part E: CI Policy and schema scanning with `kubeconform`

Before deploying manifests to a cluster, validate rendered templates against official Kubernetes OpenAPI schemas using `kubeconform` (specifying a `-kubernetes-version` that matches your cluster minor, e.g. 1.30.0 or 1.32.0):

```bash
helm template test-release charts/nginx-demo \
  --set podDisruptionBudget.enabled=true \
  --set networkPolicy.enabled=true | \
  docker run --rm -i ghcr.io/yannh/kubeconform:v0.6.7 -summary -strict -kubernetes-version 1.30.0
```

*Expect:* `Summary: 9 resources found parsing stdin - Valid: 9, Invalid: 0, Errors: 0, Skipped: 0`.

---

## Part F: Break it and recover: Pod Security admission rejection

### Step 8: Create an enforcing namespace

Create a namespace enforcing the `restricted` Pod Security standard:

```bash
kubectl create namespace hardened-lab
kubectl label namespace hardened-lab pod-security.kubernetes.io/enforce=restricted --overwrite
```

### Step 9: Install the hardened release and verify admission

Install the chart with all hardening features enabled:

```bash
helm install hardened-demo charts/nginx-demo \
  -n hardened-lab \
  --set podDisruptionBudget.enabled=true \
  --set networkPolicy.enabled=true \
  --wait
```

Verify that all pods are running and admitted:

```bash
# Check running pods:
kubectl get pods -n hardened-lab

# Check PDB and NetworkPolicy:
kubectl get pdb,networkpolicy -n hardened-lab

# Run the test hook:
helm test hardened-demo -n hardened-lab
```

*Expect:* Two Pods, each `1/1 Running`, PDB active, NetworkPolicy created, and `helm test` succeeds!

### Step 10: Break it — deploy unhardened values

Attempt to upgrade the release with `securityContext` stripped (simulating an unhardened configuration):

```bash
helm upgrade hardened-demo charts/nginx-demo \
  -n hardened-lab \
  --set podSecurityContext=null \
  --set securityContext=null \
  --wait \
  --timeout=15s
```

*Expect Error:*

```text
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false ..., unrestricted capabilities ..., runAsNonRoot != true ..., seccompProfile ...
Error: UPGRADE FAILED: context deadline exceeded
```

Inspect the cluster events to observe the admission rejection:

```bash
kubectl get events -n hardened-lab --sort-by='.metadata.creationTimestamp' | grep FailedCreate | tail -3
```

Notice that the ReplicaSet was blocked from creating pods by the Kubernetes admission controller! The existing running pods from revision 1 remain running and untouched.

### Step 11: Recover

Roll back to the compliant revision:

```bash
helm rollback hardened-demo 1 -n hardened-lab --wait
```

Verify that the release is healthy:

```bash
helm status hardened-demo -n hardened-lab
kubectl get pods -n hardened-lab
```

---

## Cleanup and Checkpoint

Clean up the test release and namespace:

```bash
helm uninstall hardened-demo -n hardened-lab
kubectl delete namespace hardened-lab
```

Bump chart version to `0.6.0` in `Chart.yaml`:

```yaml
version: 0.6.0
```

> [!NOTE]
> **Managing Downstream Dependencies:**
> When you bump a chart's version (`0.5.0` $\to$ `0.6.0`), any umbrella charts or downstream consumers that pin it (such as `charts/shop`) must update their dependency version constraint in `Chart.yaml` (`version: ">=0.5.0 <=0.6.0"`) and rebuild their locks (`helm dependency update charts/shop`).

Ensure the hardening test suite `charts/nginx-demo/tests/hardening_test.yaml` is in place (check it out from `main` or verify its contents):

```bash
git checkout main -- charts/nginx-demo/tests/hardening_test.yaml
```

Run the complete unit test suite:

```bash
helm unittest charts/nginx-demo
git status
```

*Expect:* All 28 tests in `charts/nginx-demo` pass (`PASS  charts/nginx-demo  ... Tests: 28 passed, 28 total`). Running `helm unittest charts/nginx-demo charts/shop` passes 42/42 tests!

---

## Explain: deepen your understanding

After completing this lab, you should be able to answer:

1. Why does Pod Security admission rejection block ReplicaSets from creating new Pods while leaving existing running Pods healthy?
2. Why does `readOnlyRootFilesystem: true` require writable `emptyDir` mounts for NGINX even when running unprivileged?
3. How do PodDisruptionBudgets prevent service outages during voluntary cluster node drains or rolling node upgrades?
4. Why is validating rendered manifests against OpenAPI schemas with `kubeconform` essential in CI before cluster submission?

> [!TIP]
> See [16-production-hardening-and-best-practices-explained.md](16-production-hardening-and-best-practices-explained.md) for detailed security context architectures, NetworkPolicy mechanics, and admission controller event analysis.
