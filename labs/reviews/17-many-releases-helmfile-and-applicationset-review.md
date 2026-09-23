# Lab 17 review: Many releases with Helmfile (and Argo CD ApplicationSet)

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** Step 0 (`git checkout main -- helmfile/ charts/shop-db charts/shop-api`), the fleet with `wait: true` (all 4 Pods `1/1`), the prod-diff wording, label filtering, cycle detection, the ApplicationSet dry run, and cleanup.

## New bug

- **N1 (high): The new end-to-end data step fails twice over.**
  1. `kubectl exec -n helm-lab-dev deploy/backend-db-db` fails with `Error from server (NotFound): deployments.apps "backend-db-db" not found`, because the database is a **StatefulSet**.
  2. Using the Pod directly, `psql -U postgres` fails with `FATAL: role "postgres" does not exist`, because the chart sets `POSTGRES_USER=shop`. The API also connects to database `shop`, so the objects must live there.

  So the API still answers `role "web_anon" does not exist`. **Verified fix:** `kubectl exec -n helm-lab-dev statefulset/backend-db-db -- psql -U shop -d shop -c "..."`, after which the API returns `[{"id":1,"name":"helmfile item"}]`.

## Still open (minor)

- **I2:** The cycle error text differs (namespaced names, no `in release` prefix).
- **I3 / I4:** The ApplicationSet covers only `frontend-web` and targets the same namespaces as Helmfile.
- **I5:** Plaintext passwords in `values/*.gotmpl`. Mention helmfile `secrets:`.
- **S1** as before.
