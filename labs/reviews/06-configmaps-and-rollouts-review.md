# Lab 6 review: ConfigMaps and rollouts

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** The lab itself is excellent and fully accurate. Every step, check, and claim held up:

- The ConfigMap renders correctly, and the file inside the container and the curl response both show the custom page.
- Changing `pageContent` in dev changed the checksum (`03056f…` → `491bad…`) and replaced the Pod.
- **Optional experiment verified:** with the checksum in top-level `metadata.annotations`, the Pod was *not* replaced, and the mounted `index.html` updated on its own after about 55–60 s. That matches the lab's warning that the page can change without a rollout.

The problems are all in `06-configmaps-and-rollouts-explained.md`.

## Bugs

### B1: The explained break-it demo would actually trigger a rollout (high)

Explained step 3 runs:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --set pageContent="<h1>Rollout Test</h1>" --wait
```

It has no `-f values-dev.yaml` and no `--reset-values`. Because a `--set` is passed, Helm drops the previous values (see Lab 3 review B1). The Pod template loses `extraEnv` and `resources` (verified: the rendered Deployment has **0** `env:`/`resources:` lines) and `replicaCount` goes from 1 to 2.
That changes `spec.template`, so **the Pods are replaced**, which is the opposite of the output the page shows ("The Pod was NOT replaced!").

**Fix:** Use the lab's own method: edit `pageContent` in `values-dev.yaml` and upgrade with `--reset-values -f values-dev.yaml`.

### B2: The explained Q2 contradicts the lab about NGINX (medium)

It says: "most software (including NGINX...) does not watch the filesystem... retains the old configuration in memory".
For **static content** that's wrong. NGINX reads `index.html` from disk on every request, which is exactly why the lab warns that "NGINX may therefore serve the changed page while the Pod IDs stay the same". I observed this.
The statement is true for NGINX's *config* (`nginx.conf`, which needs a reload) and for many apps' config files. Rephrase to separate "config read at startup" from "content read per request".

### B3: The explained page answers different questions than the lab asks (medium)

Same drift as Lab 5: the lab's "Check your understanding" has 4 questions (with inline answers), while the explained page answers 3 different ones (checksum mechanics, file update vs replacement, indentation). The lab also doesn't link to the explained page. Align them or link with a note that it contains *extra* questions.

## Accuracy issues

- **I1:** Explained Q3 quotes `yaml: line 6: mapping values are not allowed in this context` for `nindent 2`. Actual output: `yaml: line 14: could not find expected ':'`.
- **I2:** Explained Q2: "kubelet syncs ... typically every 60–90 seconds". That's a reasonable approximation (sync period plus the ConfigMap cache TTL). I measured ~55–60 s on kind. Fine as is, or say "up to about a minute or two".
- **I3:** Explained Q2, "guarantees zero-downtime reloads", overstates things. Without readiness probes (not added until the extensions) and with `replicaCount: 1`, a rollout still briefly depends on the new Pod starting quickly. Soften to "enables".
- **I4:** The `lab-06-complete` tag's dev `pageContent` has only `<h1>Hello from Updated Helm Lab</h1>` (no `<p>` line), while the lab's final state has two lines. Minor noise when running `git diff lab-06-complete`.

## Ease-of-following suggestions

- **S1:** Step 3a: `volumes` must be added at the *end* of the Pod spec **after** the container list. Many learners put it inside the container. The placement guide handles this well, so perhaps move it *before* 3a/3b.
- **S2:** Step 6a: the Pod listing briefly includes terminating Pods. Add `--field-selector=status.phase=Running` or tell learners to wait for `rollout status` first. The lab mentions this but the command doesn't enforce it.
- **S3:** Step 4: mention that the checksum covers the **rendered** ConfigMap, so a change to labels (for example a chart `appVersion` bump) also triggers a rollout. That's relevant in Lab 9 when the chart version changes.
- **S4:** The volume/ConfigMap name `{{ .Release.Name }}-page` is repeated in two templates, right after Lab 5 taught helpers. Suggest a `nginx-demo.pageConfigMapName` helper as an optional stretch.
- **S5:** "Mark Lab 6 complete in the README": inconsistent with other labs, same as Lab 5 I2.
