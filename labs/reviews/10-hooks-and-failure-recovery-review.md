# Lab 10 review: Hooks, failure recovery, and debugging

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (Helm v3.19.0, helm-diff 3.15.13, kind v1.35.0). Re-run from the pre-Lab-10 state (after the extensions).

**Fixed and verified:**

- **B1 (chart):** With `nginx-demo.hookLabels`, the migration Job Pod is **no longer** a Service endpoint. During an upgrade the Job Pod IP `10.244.0.220` was absent from `demo-hooks-service`'s EndpointSlice, which only listed the app Pod.
- **B2:** The schema snippet now shows only `migration`.
- Parts B and C still reproduce exactly (`BackoffLimitExceeded`, replicas unchanged, `--atomic` rollback).

## New bug

### N1: The lab uses `nginx-demo.hookLabels` but never shows its definition (high)

The Job template in Step 2 calls `include "nginx-demo.hookLabels"`, and the `[!IMPORTANT]` note (placed *after* the snippet) only says "define `nginx-demo.hookLabels`". No lab contains the `define` block. A learner following the text gets:

```text
[ERROR] templates/: template: nginx-demo/templates/migration-job.yaml:7:8: executing "..." at <include "nginx-demo.hookLabels" .>: error calling include: template: no template "nginx-demo.hookLabels" associated with template "gotpl"
```

**Fix:** Add a Step 1b before the Job with the helper (as on `main`):

```gotemplate
{{- define "nginx-demo.hookLabels" -}}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: migration
{{- end -}}
```

Also move the IMPORTANT note before the Job snippet. The `lab-10-complete` tag still contains the old Job (with `nginx-demo.labels`), so `git diff lab-10-complete` will show this as a difference. Consider re-tagging or noting it.

## Still open

- **B3:** Part D3 still says the diff shows replicas "and nothing else". It also shows the hook Job (`revision 4` → `revision 1`, re-verified) because the template echoes `.Release.Revision`.
- **I1:** Revision 6 stays `pending-upgrade` in history after D5's recovery. Mention it.
- **I2:** With `--atomic`, the pre-upgrade migration still runs before the rollout fails. Point it out.
- **I3:** D2 pipes hooks and tests into the server dry run. Suggest `helm template --no-hooks` (verified: 2 → 0 hook resources).
- **S1:** Step 6 says lint "warns" about a missing `lab-banner`. It errors.
- **S2:** Say that the recovery's `--set replicaCount=2` is intentional.
- **S3:** `timeout -s KILL 3` depends on timing. Suggest retrying with `1`.
- **S4 / S5:** "tick Lab 10 in the README" and "Your notes" are inconsistent with other labs.
- **Explained page:** `10-hooks-and-failure-recovery-explained.md` doesn't mention `hookLabels` or why the Job must not carry the selector label. Add a Q (it's the lab's most transferable lesson).
