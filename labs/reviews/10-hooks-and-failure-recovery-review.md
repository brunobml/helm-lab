# Lab 10 review: Hooks, failure recovery, and debugging

**Tested with:** Helm v3.19.0, helm-diff 3.15.13, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** This is one of the strongest labs. Every documented error message matched **exactly**:

- `pre-upgrade hooks failed: ... job demo-hooks-migrate failed: BackoffLimitExceeded`
- `has been rolled back due to atomic being set: context deadline exceeded`
- `another operation (install/upgrade/rollback) is in progress`
- the `Unsupported value: "Sometimes"` server dry-run
- `at '/migration/fail': got number, want boolean`

The note that `helm upgrade --dry-run=server` misses the invalid `imagePullPolicy` is also confirmed. The explained page matches the lab (including revision numbers 1–7). One real chart bug and a few small inaccuracies remain.

## Bugs

### B1: The migration Job's Pods join the application Service as Ready endpoints (high)

The Job's Pod template uses `nginx-demo.labels`, which includes the **selector label** `app: {{ .Release.Name }}`. While the hook runs, its busybox Pod (no port 80, no readiness probe) matches `demo-hooks-service`'s selector and is immediately Ready. Verified during an upgrade:

```text
10.244.0.76 ready=true 10.244.0.82 ready=true  | job pod IP=10.244.0.82
```

For the duration of the migration, a share of Service traffic goes to a Pod that refuses connections. This contradicts Lab 7's own rule ("Test Pods must never become endpoints in the application Service!"), and it's still present on `main`. It gets worse in Lab 16: the PodDisruptionBudget and NetworkPolicy selectors also match these Pods.

**Fix:** Add a labels helper without the selector label (or add `app.kubernetes.io/component: migration` and exclude it from selectors), and use it for the Job's Pod template, the Lab 7 test Pod, and any future auxiliary Pods. It's also a great teaching moment for Lab 5's selector lesson.

### B2: Step 4's schema snippet silently rewrites the `service` block (medium)

Step 4 says "Add a `migration` entry", but the surrounding context it shows for `service` is **different** from what Lab 7 created:

- no `"required": ["port","targetPort"]`
- no `targetPort` property
- a new `enum` on `type`

A learner who pastes the block over their existing `service` entry loses the `targetPort` validation. The `lab-10-complete` tag kept the Lab 7 version, so the snippet doesn't even match the reference. Show only the `migration` addition, or show the real Lab 7 `service` block as context.

### B3: `helm diff` shows more than "replicas and nothing else" (low)

Part D3 expects "`-   replicas: 2` and `+   replicas: 3` and nothing else". Actual output also includes the **hook Job**:

```text
helm-lab, demo-hooks-migrate, Job (batch) has changed:
-               echo "Running migration for release demo-hooks (revision 3)"
+               echo "Running migration for release demo-hooks (revision 1)"
```

The template embeds `.Release.Revision`, and helm-diff renders the new manifest with revision 1. Either explain this (it's a nice lesson: anything using `.Release.Revision` or `now` always shows up in a diff) or drop `.Release.Revision` from the echo. Adding `--no-hooks` to the diff command is another option.

## Accuracy issues

- **I1:** After D5's recovery, revision 6 stays `pending-upgrade` in `helm history` **forever**, even though the release is healthy. Mention this so learners don't think the recovery failed. Also mention `helm history --max`, and that `helm uninstall` / history-max pruning eventually removes it.
- **I2:** Part C: with `--atomic`, the **pre-upgrade migration hook still runs** (and succeeds) before the bad image fails. The explained Q3.4 covers this conceptually ("Rolling back does not undo state changes"). Pointing out that it happened *in this very exercise* would make it concrete.
- **I3:** Part D2 pipes `helm template` into `kubectl apply --dry-run=server`. This also dry-runs the hook Job and the test Pod as if they were regular resources. That's harmless here, but adding `--no-hooks` to `helm template` excludes both hooks (verified: 2 hook resources → 0), and `--skip-tests` excludes just the test Pod (2 → 1). Recommend `--no-hooks` when validating regular resources, and mention that hooks are otherwise included.

## Ease-of-following suggestions

- **S1:** Part A Step 6 says "If `helm lint` warns that the subchart dependency `lab-banner` is missing". It doesn't warn: it **errors** at template time. Use the actual message from the Lab 8 review.
- **S2:** Part B's recovery upgrade uses `--set replicaCount=2` while the dev file says 1. That's intentional, to show the change applied, but say so explicitly. Learners following "Fix the cause" expect to just drop `migration.fail`.
- **S3:** D5's `timeout -s KILL 3` depends on timing. On a very fast cluster, `--wait` could finish in under 3 s. The 2 s `sleep` in the hook makes this unlikely. Mention that if history shows `deployed`, the learner should rerun with `timeout -s KILL 1`.
- **S4:** Cleanup says "tick Lab 10 in the README". Same inconsistency as Labs 5/6.
- **S5:** The lab's "Your notes" section is unique to this lab. Either add it to every lab (`labs/TEMPLATE.md`) or remove it.
