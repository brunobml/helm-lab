# Lab 17 review: Many releases with Helmfile (and Argo CD ApplicationSet)

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (helmfile 1.8.0, Helm v3.19.0, kind v1.35.0), using `main`'s `helmfile/`, `charts/shop-api`, and `charts/shop-db`.

**Fixed and verified:**

- **B1:** `dbHost: backend-db-db` and `API_URL: http://backend-api-api:3000`. All 4 Pods are `1/1` in dev and prod.
- **B3:** `helmDefaults: { wait: true, timeout: 300 }` gates the DAG, and the note now explains it. The dev apply took about 31 s with each release Ready before the next.
- **C1 / C2:** The cleanup `cd "$(git rev-parse --show-toplevel)/helmfile"` works from anywhere, and the `grep -E 'helm-lab-(dev|prod)'` check prints "All lab releases cleanly destroyed".
- The lab now shows `db.yaml.gotmpl` and `api.yaml.gotmpl`, and has Explain questions and a link.

## Still open

### B2: The API still can't serve data (high)

Re-verified: `curl http://backend-api-api:3000/` returns `{"code":"22023","message":"role \"web_anon\" does not exist"}`. The fleet has no migration (Lab 13's lives in the `shop` umbrella hook). Add a small migration release or a Helmfile `postsync` hook, or state explicitly that the fleet only demonstrates orchestration. Either way, add a check that proves the stack works end to end.

### B4: The files are still missing at the start, and the chart changes are unmentioned (high)

- `lab-16-complete` has **no `helmfile/` directory**, and the lab gives no checkout instruction. `environments/dev.yaml` and `prod.yaml` are still only "inspected" (`cat`), never shown.
- The lab still never mentions that `charts/shop-db` and `charts/shop-api` need new `templates/secret.yaml` files and `secret`/`user`/`database`/`dbHost` values. Without them, `backend-db` hits `CreateContainerConfigError`.

**Fix:** Add a Step 0: `git checkout main -- helmfile charts/shop-db charts/shop-api` (not the `lab-17-complete` tag, which has the old `dbHost: backend-db`), or spell out the files.

### Minor (unchanged)

- **I1:** Step 7 still says prod shows "`replicas: 2` (scaled up from 1)" and the probe "promoted from 6.14.0". Re-verified: the prod diff has **17 "has been added" and 0 "has changed"**, because it compares with the empty `helm-lab-prod`, not with dev.
- **I2:** The cycle error text differs. The actual text uses namespaced names and has no `in release` prefix.
- **I3:** The ApplicationSet covers only `frontend-web`, and `probeVersion` is unused. It isn't "the equivalent" of the fleet.
- **I4:** The ApplicationSet targets the same namespaces and release name as Helmfile, so applying it causes Argo CD and Helm to fight over the same objects.
- **I5:** Plaintext passwords are in `values/*.gotmpl`. Mention helmfile `secrets:` with SOPS.
- **S1:** Suggest `--skip-deps` and `--context 3` for faster, quieter diffs.
