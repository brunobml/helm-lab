# Lab 11 review: Advanced templating and library charts

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** This lab is excellent, and every prediction and error message matched:

- the Part A render table (`defaultReplicas: "5"`, `defaultDebug: "true"`, ...)
- `lookup` gives differing tokens under `helm template` and stable tokens across install/upgrade
- the refactor diff prints `identical`
- the 4 ConfigMaps and `{"ENVIRONMENT":"dev","MAX_CONN":"100","RELEASE":"demo-tpl"}`
- `library charts are not installable`
- all three break-it errors, including the `required` swap rendering an empty `data:`

The explained page agrees with the lab. Only small gaps remain.

## Bugs

### B1: Editing the library chart has no effect until dependencies are rebuilt (medium)

Break-it 2 says "Try changing the library's `fail` check to `required` and see what renders... Restore it." The parent chart renders from the **packaged** `charts/nginx-demo/charts/lab-common-0.1.0.tgz`, not from `charts/lab-common/`. Editing `_configmap.tpl` changes nothing until you run `helm dependency update ./charts/nginx-demo` (and again after restoring).
A learner will see the same `fail` message, conclude that `required` behaves like `fail`, and learn the wrong lesson. Add the rebuild step to both the experiment and the restore. It's also a great reinforcement of Lab 8's archive/lock lesson.

## Accuracy issues

- **I1:** The `lookup` warning says it "returns nothing under plain `helm template` and `--dry-run=client`". Also mention that `helm template --dry-run=server` (and `helm install/upgrade --dry-run=server`) **does** perform lookups. Verified: it returned the live token. That's the correct way to preview lookup-dependent charts.
- **I2:** `lab-common.labels` includes the selector label `app: {{ .Release.Name }}`. Putting a *selector* label into a shared *metadata* labels helper means every chart that uses the library gets that selector label on every object, including Job Pods (see the Lab 10 review B1). Consider splitting it into `lab-common.selectorLabels` + `lab-common.labels` so the library carries Lab 5's lesson forward.

## Ease-of-following / best-practice suggestions

- **S1: Security note on `tpl`.** `tpl` on user-supplied values lets anyone who controls the values execute arbitrary template code at install time, including `lookup` to read Secrets from namespaces the installer can see. Add one sentence: only `tpl` values that come from trusted sources, and never from end users of a multi-tenant platform.
- **S2:** Part A uses `/tmp/tplplay` and cleanup uses `cd -`. If the learner ran Step 3 in a new shell, `cd -` fails. Use `cd ~/path/to/helm-lab` or tell them to return to the repo root explicitly.
- **S3:** Step 8 says "Append `lab-common` to `dependencies`" but shows the whole list. Say "Your `dependencies:` should now look like this".
- **S4:** Step 8 runs `helm dependency update`. As in the Lab 8 review S2, suggest `--skip-refresh` for `file://` dependencies. It avoids refreshing every unrelated repo on the learner's machine.
- **S5:** Break it 1: the actual message begins with a very long `template: ... error calling include: template: ... _configmap.tpl:23:17 ...` prefix before the `error calling tpl` part. Tell learners to look for `error calling tpl: ... nil pointer evaluating interface {}.name` near the *end*.
- **S6:** The `dig` guard example works (verified: renders `OWNER: "unassigned"`), but writing it inside a quoted YAML string requires escaping inner quotes (`\"name\"`). Show the exact YAML line, since learners will try it.
- **S7:** Step 6's snapshot is taken **before** the version bump to 0.4.0. That's fine because no label includes the chart version. If a learner followed the Lab 5 explained page and added `helm.sh/chart`, the diff won't be identical. Worth a one-line note.
