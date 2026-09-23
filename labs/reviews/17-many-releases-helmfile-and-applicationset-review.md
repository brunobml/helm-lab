# Lab 17 review: Many releases with Helmfile (and Argo CD ApplicationSet)

**Tested with:** Helm v3.19.0, helmfile 1.8.0, helm-diff 3.15.13, Argo CD (stable) for the ApplicationSet dry run, kind (Kubernetes v1.35.0), 2026-09-23
**Result:** The Helmfile mechanics work:

- environments, `.gotmpl` layering, and the `needs:` ordering (`db` + `probe` → `api` → `web`)
- the label selectors (`-l tier=backend list`, `-l component=api apply`)
- prod creates 2 web replicas, a PDB, a NetworkPolicy, and podinfo 6.15.0
- cycle detection
- `destroy` in reverse order

**The fleet it deploys is broken**, and the lab can't be started from its stated starting point.

## Bugs

### B1: The API can never reach the database, because the host name is wrong (critical)

`helmfile/values/api.yaml.gotmpl` sets `dbHost: backend-db`, but the `shop-db` chart names its Service `<release>-db`, which is **`backend-db-db`**. Verified:

```text
PGRST_DB_URI = postgres://shop:***@backend-db:5432/shop
kubectl get svc: backend-api-api, backend-db-db, frontend-web-service, monitoring-probe-podinfo
backend-api-api-...   0/1   Running   (never Ready)
PGRST000 ... could not translate host name "backend-db" to address
```

`helmfile apply` still prints `STATUS: deployed` for every release (see B3), so the learner is told everything worked.
The same naming mismatch affects `values/web.yaml.gotmpl`: `API_URL: "http://backend-api:3000"`, but the Service is **`backend-api-api`**.
**Fix:** `dbHost: backend-db-db` and `API_URL: http://backend-api-api:3000`, or better, have the charts accept a `fullnameOverride`. With the fix, the API became Ready (after a `kubectl rollout restart`, since the Secret has no checksum annotation).

### B2: Even when connected, the API can't serve data (high)

The fleet has no equivalent of Lab 13's migration hook (which lives in the `shop` umbrella chart), so the `web_anon` role and the `items` table never exist:

```text
curl http://backend-api-api:3000/ → {"code":"22023","message":"role \"web_anon\" does not exist"}
```

The lab never checks the API, so learners don't notice. Either add a small migration release (or a `postsync` Helmfile hook), or state that the fleet only demonstrates orchestration, and add an explicit check that proves it works.

### B3: "Helmfile waits for dependencies to establish" is false with this helmfile (high)

The `needs:` note and Step 6 say Helmfile guarantees `backend-db` is "deployed and **ready**" before `backend-api` starts. Observed: `backend-api` was installed **about 1 second** after `backend-db`, while PostgreSQL was still starting. `needs:` only orders the `helm upgrade --install` calls. Readiness gating requires `helmDefaults: { wait: true }` (or `wait: true` per release), which this helmfile doesn't set.
**Fix:** Add `helmDefaults: { wait: true, timeout: 300 }` and explain that without it `needs:` is ordering only. This would also have surfaced B1 as a failed apply instead of a false success.

### B4: The lab's files don't exist at its starting point, and the chart changes are never mentioned (high)

The lab says "Inspect `helmfile/environments/dev.yaml`...", but at `lab-16-complete` there is **no `helmfile/` directory**. The lab shows only `web.yaml.gotmpl`, `helmfile.yaml.gotmpl`, and the ApplicationSet. `environments/dev.yaml`, `environments/prod.yaml`, `values/db.yaml.gotmpl`, and `values/api.yaml.gotmpl` appear nowhere.
Worse, `lab-17-complete` also **modifies `charts/shop-db` and `charts/shop-api`** (new `templates/secret.yaml` plus `secret`/`user`/`database`/`dbHost` values) so they can run without the umbrella. The lab never mentions it. Without those changes, `backend-db` fails with `CreateContainerConfigError` (missing `backend-db-credentials`).
**Fix:** Either spell out all files and chart changes (as Lab 13 does), or say "check out `helmfile/` and the chart changes from `lab-17-complete`" at the top.

## Accuracy issues

- **I1:** Step 7 says the prod diff shows "`frontend-web` has `replicas: 2` (**scaled up from 1**)" and "`monitoring-probe` is **promoted from 6.14.0** to 6.15.0". `helmfile -e prod diff` compares against what's deployed in **`helm-lab-prod`**, which is nothing, so every resource is "**has been added**". Nothing is compared against dev. Rephrase ("prod gets 2 replicas / 6.15.0"), or demonstrate a real promotion by changing `dev.yaml`'s probe version and diffing **dev**.
- **I2:** The cycle error text differs. Actual (helmfile 1.8.0): `in ./helmfile.yaml.gotmpl: cycle detected: helm-lab-dev/backend-api -> helm-lab-dev/frontend-web -> helm-lab-dev/backend-db -> helm-lab-dev/backend-api` (namespaced names, and no `in release "backend-db":` prefix).
- **I3:** The ApplicationSet isn't "the equivalent" of the fleet. It only generates **`frontend-web`** (1 of 4 releases), `probeVersion` is declared but never used, and there's no db/api/probe or sync-wave ordering. It's valid (a server dry run succeeds against the Argo CD CRD), but the comparison table overstates it. Either add the other Applications (a matrix generator over `env × component` with sync waves) or label it "partial sketch".
- **I4:** The ApplicationSet targets `helm-lab-dev`/`helm-lab-prod` with release name `frontend-web`, **the same namespace and names Helmfile just deployed**. A learner who applies it (the lab says "inspect", but many will apply) gets Argo CD and Helm fighting over the same objects. Add a warning, or target different namespaces.
- **I5:** Plaintext passwords (`"shop{{ .Values.environment }}password"`) in `values/*.gotmpl` contradict Lab 12's lesson. Mention helmfile's native `secrets:` support (via helm-secrets/SOPS). It's the natural follow-up and is already installed.

## Cleanup issues

- **C1:** The cleanup starts with `cd helmfile`, but the learner is **already** in `helmfile/` since Step 5, so it fails with `cd: helmfile: No such file or directory`. Use `cd "$(git rev-parse --show-toplevel)/helmfile"`.
- **C2:** `helm list -A | grep helm-lab || echo "All lab releases cleanly destroyed"` also matches the **`helm-lab`** namespace, where `demo-dev` is supposed to remain, so it never prints the success message. Use `grep -E 'helm-lab-(dev|prod)'`.

## Ease-of-following suggestions

- **S1:** `helmfile diff` refreshes **every** Helm repo on the learner's machine (9 on mine) and prints the full diff (hundreds of lines). Suggest `helmfile diff --skip-deps` for re-runs and `--context 3`.
- **S2:** No Explain section and no link to the explained page (same as Labs 15/16).
- **S3:** Step 1 installs helmfile to `/tmp` then `~/.local/bin`, which is fine. Also mention that `helmfile init` can install the required plugins.
