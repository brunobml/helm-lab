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
