# Lab 8 review: Dependencies

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** Every step works:

- `helm dependency update` creates `Chart.lock` and `lab-banner-0.1.0.tgz`.
- `demo-dev-banner` renders with `{"environment":"dev","message":"Hello from the parent"}`, and the condition removes it.
- `helm list` shows a single release.
- Deleting the `.tgz` breaks rendering, and `helm dependency build` fixes it.

My files match `lab-08-complete`.

## Bugs

### B1: The explained page says `Chart.lock` pins a checksum of every dependency (medium)

Explained Q2: "It guarantees deterministic, reproducible builds by pinning the exact version **and checksum** of every dependency."
The `digest:` in `Chart.lock` is a hash of the dependency *declarations* (the `dependencies:` list in `Chart.yaml` + lock), **not** a hash of each dependency's contents. The lab itself states this correctly ("A local lock is not a content hash for every source file"), so the two pages contradict each other. Integrity of remote chart contents comes from provenance/signatures (Lab 12), not from `Chart.lock`.

### B2: The repository contradicts the lesson about ignored archives (medium)

The lab says "Generated `.tgz` files are ignored", and `.gitignore` has `*.tgz`. But `main` **tracks** `charts/nginx-demo/charts/lab-banner-0.1.0.tgz` and `lab-common-0.1.0.tgz` (they must have been force-added). A learner comparing against `main` sees the opposite of what the lab teaches. Either `git rm --cached` them on `main`, or explain why the reference branch keeps them (for example so the finished chart renders without `helm dependency build`).

## Accuracy issues

- **I1:** The explained break-it error is shortened. Actual:
  `Error: An error occurred while checking for chart dependencies. You may need to run`helm dependency build`to fetch missing dependencies: found in Chart.yaml, but missing in charts/ directory: lab-banner`.
  The full text is more helpful because it *tells you the fix*. Quote it.
- **I2:** The explained recovery output shows `Getting lab-banner 0.1.0 from source chart / Saving 1 charts to charts/`. Helm 3.19 prints `Saving 1 charts` / `Deleting outdated charts`.
- **I3:** Explained Q3 says `helm dependency update` "Disregards `Chart.lock`". It re-resolves from `Chart.yaml` and **rewrites** the lock, which is effectively right, but say "re-resolves and overwrites" to avoid implying the lock is read and ignored.

## Ease-of-following suggestions

- **S1:** The lab has a duplicated `## Steps` heading (lines 11 and 13).
- **S2:** `helm dependency update` refreshes **every** repo in the learner's `helm repo list` before resolving a `file://` dependency. On my machine that meant 9 network fetches. Suggest `helm dependency update --skip-refresh ./charts/nginx-demo` for local-only dependencies, or at least mention why the output lists unrelated repos.
- **S3:** Verify 3's comments say what to expect but not how to check. Give focused commands:
  `helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml --show-only charts/lab-banner/templates/configmap.yaml`
  and for the disabled case `... --set lab-banner.enabled=false | grep -c banner` (expect `0`).
- **S4:** Verify 4 uses `kubectl get configmap ... -o yaml`, while `-o jsonpath='{.data}'` gives the two facts in one line.
- **S5:** The Step 3 callout says the condition checks `.Values.lab-banner.enabled`. Also mention that a hyphenated key **cannot** be accessed as `.Values.lab-banner` in templates (it's a template parse error). You need `index .Values "lab-banner"`. This matters in Lab 11+ and is a classic trap caused by this chart name.
- **S6:** The subchart has no labels helper or `helm.sh/chart` labels. That's fine for isolation, but a one-line note ("kept minimal on purpose") would stop learners from applying Lab 5 here unprompted.
- **S7:** Explain Q1: suggest the learner *prove* isolation by temporarily adding `{{ .Values.replicaCount | default "not visible" }}` to the child ConfigMap.
