# Lab 10: Hooks, failure recovery, and debugging — Explained

[Back to Lab 10](10-hooks-and-failure-recovery.md)

---

## Overview

You added a `pre-install,pre-upgrade` hook Job, watched it block an upgrade,
used `--atomic` to auto-undo a bad rollout, and practiced the debugging ladder:
render → API validation → diff → inspect → recover.

---

### Question 1: Why did the Deployment keep its old replica count when the pre-upgrade hook failed?

#### TL;DR

Helm runs `pre-upgrade` hooks **before** it applies any regular resource. When the hook fails, Helm stops and marks the release `failed`; the new manifest is never sent to the cluster.

#### Deep Dive

1. Upgrade order: render → run `pre-upgrade` hooks and wait → apply the manifest → run `post-upgrade` hooks.
2. A `Job` hook is "complete" only when the Job succeeds. `backoffLimit: 0` turned the first failure into `BackoffLimitExceeded` immediately.
3. Revision 2 is stored as `failed`, but revision 1 is still what runs. Note the mismatch: `helm history` shows a newer revision than the one actually running. Read `helm get manifest --revision 1` if unsure.
4. This is the point of a migration hook: never roll out new code against an unmigrated database. It is also why hooks must be **idempotent**; you will run them again after fixing the cause.

---

### Question 2: Why are hook resources absent from `helm get manifest`, and what does that mean for `helm uninstall`?

#### TL;DR

Helm does not manage hooks as part of the release. It creates them, waits, and applies the **delete policy**. It only tracks them in `helm get hooks`.

#### Deep Dive

- With `hook-succeeded`, the Job is deleted right after it succeeds, so nothing is left to uninstall.
- A hook with no delete policy, or a *failed* hook under `hook-succeeded`, stays in the cluster. `helm uninstall` does not remove it unless a `pre-delete`/`post-delete` policy or the `hook-failed` policy applies. That is why the cleanup step checks for leftover Jobs.
- Choose policies deliberately:

| Policy | Use it when |
| --- | --- |
| `before-hook-creation` (default) | You want the last run kept for debugging, and replaced on the next run |
| `hook-succeeded` | You do not need successful runs kept |
| `hook-failed` | You want failures cleaned up (rarely what you want; you lose the logs) |

---

### Question 3: Which failures does `--atomic` protect against, and which does it not?

#### TL;DR

`--atomic` protects against failures Kubernetes **reports**: an image that cannot pull, Pods that never become Ready, a hook that fails, a timeout. It does not protect against an application that starts, passes its probes, and behaves wrongly.

#### Deep Dive

1. `--atomic` implies `--wait`. Helm waits until Deployments have their Pods Ready, Jobs complete, and so on, up to `--timeout` (default 5 minutes).
2. On failure or timeout it performs `helm rollback` to the previous good revision. That is why history shows `failed` followed by `Rollback to N`.
3. A weak readiness probe defeats it. NGINX serving the wrong page returns 200 and is "Ready". Good probes and `helm test` are what tell Helm (and you) an app is actually healthy.
4. Rolling back does not undo **state** changes such as a database migration a hook already ran. Design migrations to be backward compatible.
5. Set `--timeout` to something realistic. Too short and a slow-but-healthy rollout is rolled back; too long and CI hangs.

---

### Question 4: Why is `helm diff` different from `helm template`?

#### TL;DR

`helm template` shows what the chart **would** produce. `helm diff upgrade` compares that against what is **currently deployed**, so you see only the delta.

#### Deep Dive

- `helm template` output for a large chart is hundreds of lines and does not tell you what will *change*.
- `helm diff upgrade` reads the deployed manifest from the release Secret and diffs it against the new render. It can also `--detailed-exitcode` for CI gates.
- Neither talks to the API server for validation. For that use `helm template | kubectl apply --dry-run=server -f -`. In testing with Helm 3.19, `helm upgrade --dry-run=server` did not surface an invalid `imagePullPolicy`, so do not rely on it alone.
- `helm diff` compares Helm's records, not live cluster state. If someone ran `kubectl edit`, the drift will not appear (Argo CD's diff, from Lab 9, does show it).

---

## The debugging ladder

| Question | Tool | Catches |
| --- | --- | --- |
| Does it render? | `helm lint`, `helm template --debug` | Template errors, schema violations |
| Will Kubernetes accept it? | `helm template \| kubectl apply --dry-run=server -f -` | Invalid enum values, missing CRDs, admission rejections |
| What changes? | `helm diff upgrade` | Unintended edits, checksum annotation churn |
| What is deployed? | `helm get values/manifest/hooks/all`, `helm history` | Wrong values, drift from expectations |
| Why did it fail? | `kubectl describe`, `kubectl logs`, `kubectl get events` | Pod-level causes |
| Release stuck? | `helm rollback`, then (last resort) Secret surgery | `pending-upgrade`, `failed` |

## Common pitfalls

- `--set migration.fail=1` is a **number**, not a boolean; the schema rejects it. Use `=true`.
- `hook-weight` must be a quoted string in YAML.
- A `pending-upgrade` release usually means a killed client, not a broken chart. Roll back; do not delete first.
- Hooks are not rolled back by Helm. If they change external state, plan how to reverse it.

---

## Break It and Recover — Detailed Walkthrough

Lab 10 features three distinct failure modes. Here is the step-by-step walkthrough for each:

### Scenario 1: A Pre-Upgrade Hook Fails (Part B)

#### Scenario 1 — What to Break

Simulate a database migration failure during an upgrade that also attempts to scale replicas:

```bash
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml \
  --set migration.fail=true --set replicaCount=3 --wait --timeout 60s
```

#### Scenario 1 — The Error Observed

```text
Error: UPGRADE FAILED: pre-upgrade hooks failed: 1 error occurred:
    * job demo-hooks-migrate failed: BackoffLimitExceeded
```

#### Scenario 1 — Why This Failed & Cluster Impact

- Helm renders the chart and executes the hook Job (`demo-hooks-migrate`) *before* applying the updated Deployment manifest.
- The hook Job exited with code 1 (`exit 1` in the migration script), and because `backoffLimit: 0` was configured, Kubernetes terminated the Job immediately without retries.
- Because the pre-upgrade hook failed, Helm aborted the upgrade and recorded revision 2 as `failed`.
- Crucially, the regular Deployment manifest was **never applied**. The running Deployment remained untouched with its original replica count (`1`), protecting your live environment from running against an unmigrated database.
- You can verify the failure state and job logs:

  ```bash
  helm history demo-hooks -n helm-lab
  kubectl get deployment demo-hooks-deployment -n helm-lab -o jsonpath='{.spec.replicas}{"\n"}'  # Still 1
  kubectl logs job/demo-hooks-migrate -n helm-lab                                                # "Migration failed on purpose"
  ```

#### Scenario 1 — How to Recover

Fix the failure cause and upgrade again:

```bash
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --set replicaCount=2 --wait --timeout 60s
```

Because `demo-hooks-migrate` has `"helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded`, Helm automatically deletes the previous failed Job before launching the new one. Once the new migration Job completes successfully, Helm deletes it (`hook-succeeded`) and completes the rollout to revision 3.

---

### Scenario 2: Bad Image Rollout with `--atomic` Auto-Rollback (Part C)

#### Scenario 2 — What to Break

Attempt an upgrade using a non-existent container image tag while enabling `--atomic`:

```bash
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --set replicaCount=2 \
  --set image.tag=does-not-exist --atomic --timeout 40s
```

#### Scenario 2 — The Error Observed

```text
Error: UPGRADE FAILED: release demo-hooks failed, and has been rolled back due to atomic being set: context deadline exceeded
```

#### Scenario 2 — Why This Failed & Cluster Impact

- `--atomic` automatically turns on `--wait`. Helm watches the Deployment rollout until all pods become Ready or the timeout (`40s`) expires.
- Kubernetes cannot pull `nginx:does-not-exist` (entering `ImagePullBackOff`). When the 40-second timer expires, Helm treats the upgrade as failed.
- Instead of leaving broken pods in the cluster, `--atomic` triggers an automated rollback to the last successful revision.
- Inspecting history and pods:

  ```bash
  helm history demo-hooks -n helm-lab
  kubectl get pods -n helm-lab | grep demo-hooks-deployment
  ```

  You will see:
  - Revision 4: `failed` (`context deadline exceeded`)
  - Revision 5: `deployed` (`Rollback to 3`)
  - All running Pods remain healthy on the previous working image.

#### Scenario 2 — How to Recover

Helm already performed the rollback automatically! You only need to fix your image tag in values before deploying future revisions.

---

### Scenario 3: Stuck Release in `pending-upgrade` (Part D.5)

#### Scenario 3 — What to Break

Simulate an aborted client (such as a CI/CD job being cancelled or a laptop being closed mid-upgrade):

```bash
timeout -s KILL 3 helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml --set replicaCount=3 --wait --timeout 120s
```

#### Scenario 3 — The Error Observed

Check `helm history`:

```bash
helm history demo-hooks -n helm-lab | tail -2
```

*Output:*

```text
5    ...   deployed          nginx-demo-0.3.0    1.30.4    Rollback to 3
6    ...   pending-upgrade   nginx-demo-0.3.0    1.30.4    Preparing upgrade
```

Now attempt to run any regular upgrade:

```bash
helm upgrade demo-hooks ./charts/nginx-demo -n helm-lab -f ./charts/nginx-demo/values-dev.yaml
```

*Output:*

```text
Error: UPGRADE FAILED: another operation (install/upgrade/rollback) is in progress
```

#### Scenario 3 — Why This Failed

- When Helm begins an upgrade, it creates a new release Secret with status `pending-upgrade` to lock the release against concurrent modifications.
- Because the Helm process received `SIGKILL`, it was abruptly terminated without a chance to catch signals, finish the upgrade, or update the Secret status.
- Helm guards against concurrent writes by refusing to perform any further `helm upgrade` or `helm install` while another operation is in progress.

#### Scenario 3 — How to Recover

Roll back to the last revision that had status `deployed` (in this case revision `5`):

```bash
helm rollback demo-hooks 5 -n helm-lab --wait --timeout 60s
```

Verify the release is healthy:

```bash
helm history demo-hooks -n helm-lab | tail -3
```

*Output:*

```text
5    ...   superseded        nginx-demo-0.3.0    1.30.4    Rollback to 3
6    ...   pending-upgrade   nginx-demo-0.3.0    1.30.4    Preparing upgrade
7    ...   deployed          nginx-demo-0.3.0    1.30.4    Rollback to 5
```

*Note on last resort:* If `helm rollback` also fails or is blocked, the emergency recovery is deleting the stuck revision Secret directly (`kubectl delete secret sh.helm.release.v1.demo-hooks.v6 -n helm-lab`). Never delete the active deployed release Secret.

---

## Key Takeaways

| Concept | Key Point |
| :--- | :--- |
| Pre-install / Pre-upgrade hooks | Run before Helm creates or mutates any regular manifest. If they fail, regular resources are never touched. |
| Hook Delete Policies | `before-hook-creation` clears previous runs before executing; `hook-succeeded` cleans up on success; leaving out `hook-failed` preserves logs on errors. |
| `--atomic` | Enforces `--wait` and automatically executes `helm rollback` if the rollout fails or times out. |
| `helm diff upgrade` | Shows the exact delta between deployed release state and upcoming render without touching the cluster. |
| `pending-upgrade` | Caused by interrupted Helm client processes; recovered with `helm rollback <last-deployed-revision>`. |
