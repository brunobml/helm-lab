# Lab 0 review: Chart creation

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (Helm v3.19.0).

**Fixed and verified:** the break-it now uses `version: latest` (it fails as documented), the note on `1`/`"1"` is accurate, `httproute.yaml` is listed, and the `[INFO] icon` note is present.

## Still open

### B2: `helm create` on `main` silently overwrites the finished chart (medium)

The **Start** line is unchanged ("An empty workspace, a practice branch, or a new worktree"), and `README.md` still says "The working chart starts with a Deployment and Service". A learner on `main` runs `helm create charts/nginx-demo` over the finished 0.6.0 chart and gets `WARNING: ... already exists. Overwriting.`, and stale `ci/`, `tests/`, `values.schema.json`, and `Chart.lock` survive Step 3's `rm -rf templates/*`.
**Fix:** Give a concrete start, for example `git switch -c my-lab-00 lab-00-start && git rm -rq charts/nginx-demo && rm -rf charts/nginx-demo`, and fix the README sentence.

### New N2: `helm create charts/nginx-demo` fails in an empty workspace (high)

Found in the full re-run, starting from a truly empty workspace as the **Start** line says:

```text
Error: stat .../charts: no such file or directory
```

`helm create` doesn't create missing parent directories. The first pass missed this because `charts/` already existed. **Fix:** Add `mkdir -p charts` before Step 1's `helm create` (verified to fix it).

### New N1: The expected lint output is abridged (low)

The new expected block shows 3 lines. Helm 3.19 prints 6:

```text
[ERROR] Chart.yaml: version 'latest' is not a valid SemVer
[INFO] Chart.yaml: icon is recommended
[ERROR] templates/: validation: chart.metadata.version "latest" is invalid
[ERROR] : unable to load chart
 validation: chart.metadata.version "latest" is invalid
Error: 1 chart(s) linted, 1 chart(s) failed
```

Say "among other lines, you will see...", or paste the full output.

### Explained page (unchanged, still wrong)

`00-chart-creation-explained.md` still teaches `version: 1` → `version "1" is not a valid SemVer`, and still says "A single integer `1` lacks the minor and patch segments... triggering an immediate linter failure". It now contradicts the lab. Update it to `latest`. The Golden Rule "Must follow SemVer (`x.y.z`)" should also mention that Helm coerces `1` and `1.0`.

### Minor (unchanged)

- **I3:** The `lab-00-start` tag keeps the `helm create` comments in `Chart.yaml`, has extra comments in `values.yaml`/`deployment.yaml`, and has a `README.md` the lab never creates, so `git diff lab-00-start` is noisy.
- **I4:** Mention that the empty `charts/` directory isn't tracked by git.
- **S1–S4:** Show `ls -A templates` output after deletion, explain why `values.yaml` is replaced, use a compact Verify (`grep -E '^kind|name:'`), and clarify that `.helmignore` applies whenever the chart is loaded.
