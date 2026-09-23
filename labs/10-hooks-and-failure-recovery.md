# Lab 10: Hooks, failure recovery, and debugging

**Start:** Lab 9 complete (`lab-09-complete`). Use the `helm-lab` namespace on your disposable cluster.
**Goal:** Run a task before an upgrade, survive a failed upgrade, and diagnose problems before and after they reach the cluster.

You have used one hook so far: the `test` Pod from Lab 7. Real charts use hooks
for work that must happen *around* a release, such as database migrations. This
lab adds one, breaks it on purpose, and then covers the debugging tools you will
reach for most often in production.

This lab uses a new release named `demo-hooks` so `demo-dev` stays untouched.

## Part A: Add a pre-upgrade hook

### Step 1: Predict

A hook is a normal Kubernetes resource with a `helm.sh/hook` annotation. Helm
creates it at a specific point in the release lifecycle and (for a `Job`) waits for
it to finish. **Before you build it, predict:** if the hook Job fails during
`helm upgrade`, will the Deployment still be updated?

### Step 2: Create `charts/nginx-demo/templates/migration-job.yaml`

This Job simulates a database migration. It runs before every install and upgrade.

```yaml
{{- if .Values.migration.enabled }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-migrate
  labels:
    {{- include "nginx-demo.hookLabels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        {{- include "nginx-demo.hookLabels" . | nindent 8 }}
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.migration.image }}"
          command: ["sh", "-c"]
          args:
            - |
              echo "Running migration for release {{ .Release.Name }} (revision {{ .Release.Revision }})"
              sleep 2
              {{- if .Values.migration.fail }}
              echo "Migration failed on purpose" >&2
              exit 1
              {{- end }}
              echo "Migration complete"
{{- end }}
```

> [!IMPORTANT]
> **Label Isolation for Hooks and Auxiliary Pods:**
> In `charts/nginx-demo/templates/_helpers.tpl`, define `nginx-demo.hookLabels` (which provides standard metadata but **omits** `app: {{ .Release.Name }}`).
> Why? The application Service selector selects on `app: {{ .Release.Name }}`. If the migration Job Pod carries that selector label, Kubernetes will register the migration pod as a ready endpoint of the Service while the migration runs! Traffic will be routed to a pod that does not serve HTTP. Always keep hook and test pod labels decoupled from application Service selectors.

What the annotations mean:

| Annotation | Effect |
| --- | --- |
| `helm.sh/hook: pre-install,pre-upgrade` | Run before Helm creates or updates the regular resources |
| `helm.sh/hook-weight: "0"` | Order among hooks of the same type (lowest first; must be a quoted string) |
| `helm.sh/hook-delete-policy` | `before-hook-creation` removes the previous run's Job first; `hook-succeeded` cleans up after success. A **failed** Job is kept so you can read its logs. |

`backoffLimit: 0` makes the Job fail on the first error instead of retrying, so
the lab does not wait several minutes.

### Step 3: Add values in `charts/nginx-demo/values.yaml`

Append:

```yaml
# Pre-install/pre-upgrade hook Job that simulates a database migration.
migration:
  enabled: true
  image: busybox:1.36
  # Set to true to make the hook fail (used in Lab 10 to observe hook failures).
  fail: false
```

### Step 4: Extend `charts/nginx-demo/values.schema.json`

Add a `migration` entry inside the top-level `properties` object (after `"service": { ... }`):

```json
    "migration": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" },
        "image": { "type": "string", "minLength": 1 },
        "fail": { "type": "boolean" }
      }
    }
```

### Step 5: Bump the chart version in `charts/nginx-demo/Chart.yaml`

```yaml
version: 0.3.0
```

### Step 6: Render and install

If `helm lint` warns that the subchart dependency `lab-banner` is missing, build it first with `helm dependency build ./charts/nginx-demo`.

```bash
helm lint ./charts/nginx-demo
helm template demo-hooks ./charts/nginx-demo | grep -B2 -A12 "kind: Job"

helm install demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
```

`helm template` prints the hook because it is part of the render. Inspect how
Helm classifies it. Hooks are stored separately from the regular manifest:

```bash
helm get hooks demo-hooks -n helm-lab      # the Job and the test Pod
helm get manifest demo-hooks -n helm-lab   # Deployment, Service, ConfigMap, ... (no Job)
```

## Part B: Break the hook

Make the migration fail and try to change the replica count in the same upgrade:

```bash
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml \
  --set migration.fail=true --set replicaCount=3 --wait --timeout 60s
```

*Expect:* `UPGRADE FAILED: pre-upgrade hooks failed ... job demo-hooks-migrate failed: BackoffLimitExceeded`.

Inspect the damage:

```bash
helm history demo-hooks -n helm-lab
kubectl get deployment demo-hooks-deployment -n helm-lab -o jsonpath='{.spec.replicas}{"\n"}'
kubectl logs job/demo-hooks-migrate -n helm-lab
```

*Expect:* revision 2 is `failed`, the Deployment still has its **old** replica
count (the regular resources were never touched), and the log shows
`Migration failed on purpose`.

Recover by fixing the cause and upgrading again:

```bash
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --set replicaCount=2 --wait --timeout 60s
kubectl get job -n helm-lab     # the failed Job is gone: before-hook-creation removed it
```

## Part C: `--wait`, `--timeout`, and `--atomic`

Lab 2 showed that a bad image fails an upgrade. Now let Helm undo it for you:

```bash
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --set replicaCount=2 \
  --set image.tag=does-not-exist --atomic --timeout 40s
```

*Expect:* `UPGRADE FAILED: release demo-hooks failed, and has been rolled back due to atomic being set`.

```bash
helm history demo-hooks -n helm-lab
kubectl get pods -n helm-lab | grep demo-hooks-deployment
```

*Expect:* one revision `failed`, followed by a new `deployed` revision whose
description is `Rollback to N`. The Pods from the last good revision are still
Running.

> [!NOTE]
> `--atomic` implies `--wait`. In Helm 4 it is renamed `--rollback-on-failure`.
> These labs use Helm 3.

## Part D: Debug before and after deploying

Work through these in order. It is the same order you would use on a real problem.

### 1. Does it render? (`--debug`)

```bash
helm template demo-hooks ./charts/nginx-demo --set replicaCount=abc --debug
```

The schema catches it: `at '/replicaCount': got string, want integer`.
`--debug` adds the computed values and, when a template errors, the partial output.

### 2. Will Kubernetes accept it? (server-side dry run)

Add a value the schema allows (any string) but Kubernetes rejects:

```bash
helm template demo-hooks ./charts/nginx-demo -n helm-lab \
  --set image.pullPolicy=Sometimes | kubectl apply --dry-run=server -f -
```

*Expect:* `Unsupported value: "Sometimes": supported values: "Always", "IfNotPresent", "Never"`.

> [!IMPORTANT]
> In Helm 3.19, `helm upgrade --dry-run=server` did **not** report this error in
> testing; it only rendered the manifest. Piping `helm template` into
> `kubectl apply --dry-run=server` is what gives you real API-server validation.

### 3. What will change? (`helm diff`)

`helm diff` is a plugin. Check if it is already installed, and install it if missing:

```bash
helm plugin list

# If diff is not listed, install it:
helm plugin install https://github.com/databus23/helm-diff
```

```bash
helm diff upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --set replicaCount=3
```

*Expect:* a colored diff showing `-   replicas: 2` and `+   replicas: 3` and nothing
else. Use `helm diff` in reviews and CI before every upgrade.

### 4. What is actually deployed? (`helm get`)

```bash
helm get values demo-hooks -n helm-lab        # only what you supplied
helm get values demo-hooks -n helm-lab -a     # supplied + chart defaults
helm get manifest demo-hooks -n helm-lab      # what Helm applied
helm get all demo-hooks -n helm-lab           # everything, including notes and hooks
helm history demo-hooks -n helm-lab
```

### 5. A stuck release (`pending-upgrade`)

If a `helm upgrade` process is killed (CI timeout, closed laptop), the release can
be left in `pending-upgrade`, and the next upgrade refuses to run. Simulate it:

```bash
timeout -s KILL 3 helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --set replicaCount=3 --wait --timeout 120s

helm history demo-hooks -n helm-lab | tail -2      # latest revision: pending-upgrade
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab -f ./charts/nginx-demo/values-dev.yaml
```

*Expect:* `Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress`.

Recover by rolling back to the last good revision (look at `helm history` and pick the latest revision marked `deployed`, e.g. `5`):

```bash
helm rollback demo-hooks <last-deployed-revision> -n helm-lab --wait --timeout 60s
helm history demo-hooks -n helm-lab | tail -3
```

*Expect:* a new `deployed` revision with description `Rollback to N`. If a rollback
is refused, the last resort is to delete the stuck revision's Secret
(`kubectl get secret -n helm-lab -l owner=helm,name=demo-hooks`). Read it first, and
never delete the latest *deployed* revision.

## Verify

Local:

```bash
helm lint ./charts/nginx-demo
helm template demo-hooks ./charts/nginx-demo | grep -c "kind: Job"                                # 1
helm template demo-hooks ./charts/nginx-demo --set migration.enabled=false | grep -c "kind: Job" || true   # 0 (Note: grep exits with code 1 when 0 matches are found)
helm template demo-hooks ./charts/nginx-demo --set migration.fail=1 2>&1 | grep "got number"
```

Cluster:

```bash
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
helm test demo-hooks -n helm-lab --timeout 60s
helm status demo-hooks -n helm-lab      # STATUS: deployed
```

## Break it and recover

Parts B, C and D5 are the break-and-recover exercises. Do not commit with
`migration.fail: true` or a bad image tag in `values.yaml`.

## Explain

- Why did the Deployment keep its old replica count when the pre-upgrade hook failed?
- Why are hook resources absent from `helm get manifest`, and what does that mean for `helm uninstall`?
- Which failures does `--atomic` protect against, and which does it not (think: an application that starts but is broken)?
- Why is `helm diff` different from `helm template`?

> [!TIP]
> See [10-hooks-and-failure-recovery-explained.md](10-hooks-and-failure-recovery-explained.md) for detailed explanations.

## Cleanup and checkpoint

```bash
helm uninstall demo-hooks -n helm-lab
kubectl get job -n helm-lab      # a leftover failed hook Job, if any, is not managed by Helm; delete it
```

Keep `demo-dev`. Commit your work, tick Lab 10 in the README, and create `lab-10-complete`.

References: [Chart hooks](https://helm.sh/docs/topics/charts_hooks/),
[helm upgrade flags](https://helm.sh/docs/helm/helm_upgrade/),
[helm-diff](https://github.com/databus23/helm-diff).

## Your notes

Record versions, observations, failures, and explanations here.
