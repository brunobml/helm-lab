# Lab 13: Capstone — Explained

[Back to Lab 13](13-capstone.md)

---

## Overview

You built and operated a three-tier release from parts you already knew. The interesting material is not the
charts themselves but the **interactions** between them: labels, hooks, secrets, and probes that are each correct on their own.

---

### Question 1: Why must `api` and `db` avoid the `app: <release>` label, and where else could that assumption hide?

#### TL;DR
`nginx-demo` (from Lab 5) selects its pods with `app: <release>`. A Service selects by label alone, across **every** pod in the namespace, so any pod from any subchart carrying that label becomes an endpoint.

#### Deep Dive
1. Helm renders all subcharts into one release. Names like `<release>-service` come from `.Release.Name`, which every subchart shares. Nothing scopes a selector to "my chart".
2. When you added `app: <release>` to `shop-api`'s labels, `helm install --wait` still succeeded: the API pod is Ready, so it is a valid endpoint of the web Service. The failure is in traffic: the Service has a `targetPort` of 80 and PostgREST does not listen on 80, so a share of requests is refused.
3. Nothing reports it. Probes pass, Pods are Running, and `helm test` may pass or fail at random. That is why the wiring test asserts on *selectors and labels*, not on the API answering.
4. You cannot fix it in `nginx-demo` cheaply: Deployment selectors are immutable, so changing `app: <release>` on the web chart breaks every existing release (Lab 5, Lab 11). The convention for new charts is to select on `app.kubernetes.io/name` **and** `instance`, and to keep charts from sharing generic labels.
5. Same class of problem elsewhere: two subcharts creating a resource with the same name (each named `<release>-config`), a PodDisruptionBudget or NetworkPolicy whose selector is too broad, or `.Release.Name`-based names colliding when the same chart is used twice in one release (the reason `nginx-demo` is aliased only once).

---

### Question 2: Why is the migration a post-install/post-upgrade hook, and how does a failure differ from Lab 10?

#### TL;DR
A `pre-*` hook runs **before** the database exists on a fresh install, so it cannot connect. A `post-*` hook runs after the resources are applied (and ready, with `--wait`). The cost: a failed post hook cannot stop the change.

#### Deep Dive
| | Lab 10: `pre-upgrade` | Lab 13: `post-upgrade` |
| --- | --- | --- |
| Runs | before new manifests are applied | after new manifests are applied |
| Failure leaves the cluster | with the **old** resources | with the **new** resources (you saw `desired=2`) |
| Release status | `failed` | `failed` |
| What protects you | the hook itself blocks the change | `--atomic`, which rolls back to the previous revision |

1. For a fresh install, the only possible order is: create the database, then migrate. That is why the migration is a post hook and the Job waits with `pg_isready` in case the database Pod is still starting.
2. A post hook that fails leaves a half-deployed release: the new application code is running against a database that did not migrate. `--atomic` (Lab 10) is what turns that into "rolled back to the last good revision".
3. Rolling back does not undo what the migration already changed in the database. Write migrations that are backward compatible with the previous application version, and idempotent, because the hook runs on **every** upgrade (the `serial` gap, id 3 instead of 2, is the visible trace of the second run).
4. The `-5` weight on the SQL ConfigMap makes it exist before the Job at weight `0`. Hooks are ordered by weight, then by kind, then by name.
5. Both hook resources use `hook-succeeded`, so they disappear on success, but a **failed** Job stays for `kubectl logs`, and `before-hook-creation` clears it on the next run.

---

### Question 3: Why did rotating the password break the migration, and why was the API not restarted?

#### TL;DR
Changing the Secret changed only Kubernetes. PostgreSQL reads `POSTGRES_PASSWORD` once, when it initializes an empty data directory, so the database kept the old password. And Pods read environment variables at start, so the running API kept its old connection string.

#### Deep Dive
1. **Database.** The `postgres` image's entrypoint applies `POSTGRES_PASSWORD` only for a new cluster. With persistence on (prod) the same is true across every restart, because the data directory already exists. The role's password lives in the database, so it must be changed *there* (`ALTER ROLE`). Order matters: change the database, apply the new Secret, then restart consumers.
2. **API.** The Deployment has no checksum annotation for the credentials. Lab 12's `checksum/secret` pattern works when the Secret and the Deployment are in the same chart (the template can `include` the Secret's file). Here the Secret belongs to the umbrella and the Deployment to a subchart, and a subchart cannot include a parent's template file.
3. **Options to make rotation safe:**
   - move the Secret into the chart that consumes it (the API and the database then each own a credentials Secret);
   - add a pod annotation hook, for example a `podAnnotations` value the umbrella sets from a hash of the password (a plaintext-derived value in Git is a trade-off; hash a *version number* you bump instead);
   - run [Reloader](https://github.com/stakater/Reloader) to restart Deployments when a referenced Secret changes;
   - `kubectl rollout restart` in the runbook, as in the lab.
4. **Better still:** use a database operator or a managed database whose credentials are rotated by the platform, and let the application fetch them (External Secrets, CSI driver). Rotating a superuser password by editing a Helm value is a lab convenience.
5. A rotation runbook is exactly the sort of thing to write down and rehearse *before* an incident; this step was your rehearsal.

---

### Question 4: Why use liveness probes that check the dependency, and what could go wrong with them?

#### TL;DR
After a database restart, PostgREST kept answering `/ready` with 503 and never recovered on its own. With no ready endpoints, the Service sent no traffic, so nothing ever nudged it. A liveness probe that also fails in that state gets the Pod restarted.

#### Deep Dive
1. **What you observed:** deleting the database Pod left both API Pods `0/1`; a direct request to port 3000 worked, yet `/ready` stayed 503. Kubernetes only *removes* an unready Pod from a Service, it never restarts it. Liveness is what restarts.
2. **The design:** a `startupProbe` on `/ready` (150 seconds of grace) protects a fresh install, when the API legitimately starts before the database. After it passes, the `livenessProbe` on `/ready` (six failures at ten seconds) restarts a Pod stuck for about a minute.
3. **The danger of dependency-aware liveness:** a database outage now restarts every API replica together, repeatedly, and restarts add load and log noise exactly when the system is degraded. In the worst case, a slow database causes a restart storm that slows recovery. Mitigations: generous thresholds (as here), a startup probe, backoff (Kubernetes provides it), and never making liveness depend on *several* services.
4. **The rule of thumb:** readiness answers "should I get traffic?", and may depend on downstream services. Liveness answers "am I wedged?", and should depend on downstream services only when you have seen the wedge, as here. Document why in the chart (there is a comment in the Deployment).
5. You could also `PGRST_DB_CHANNEL_ENABLED=false` to avoid the listener, at the price of losing the automatic schema reload that the migration's `NOTIFY` relies on.

---

### Question 5: Which parts change if Argo CD deploys this instead of `helm secrets`?

#### TL;DR
Anything that needs Helm CLI features: secret decryption, `helm test`, `--atomic`, release history. Argo CD renders with `helm template` and applies the result itself.

#### Deep Dive
| Concern | With the Helm CLI (this lab) | With Argo CD |
| --- | --- | --- |
| Secrets | `helm secrets` decrypts on the fly | plugin (KSOPS/helm-secrets), or `credentials.create=false` plus a Secret from ESO, Sealed Secrets, or manual creation |
| Hooks | run by Helm | mapped to sync hooks (`post-*` becomes PostSync) |
| Failure recovery | `--atomic`, `helm rollback` | Git revert and re-sync, plus sync waves/health checks |
| Tests | `helm test` | a separate step or a PostSync Job |
| Dependencies | `helm dependency build` on your machine | Argo runs it, but **only for the app chart**: nested `file://` dependencies break |
| Release name | `helm install <name>` | the Application name (this sets the `<release>-credentials` name) |

1. The `credentials.create` switch exists for exactly this handoff: the chart works with or without the Secret being its own.
2. The nested dependency problem (break-it exercise 4) is why real multi-chart repositories publish subcharts to a registry and depend on them by version. That is planned for Lab 17.
3. `lookup`-based tricks (Lab 11) do not work under Argo either.

---

### Question 6: What would you change before running this in production?

A starting list; the Roadmap's Lab 16 covers most of it:

- **Database:** use a managed service or an operator. Backups, restores, HA, and version upgrades are not a chart's job. A single StatefulSet replica is a single point of failure.
- **Least privilege:** the API should use a separate login role with `SELECT` on what it needs, not the database owner.
- **Pod security:** `securityContext` (non-root, read-only filesystem, dropped capabilities), tested against the `restricted` Pod Security level.
- **Network:** a `NetworkPolicy` so only the API reaches the database, and only the web tier reaches the API.
- **Availability:** `PodDisruptionBudget`s, anti-affinity or topology spread, HPA on the API.
- **Secrets:** rotation runbook, `existingSecret` support in each subchart, and encryption at rest in the cluster.
- **Supply chain:** pin image digests, sign the chart (Lab 12), and verify on install.
- **Observability:** metrics and alerts on the API and database, and structured logs.

---

## Quick reference

| Situation | What to do |
| --- | --- |
| Umbrella renders fail with `no template ... associated with template "gotpl"` | Build nested dependencies first (`helm dependency build` on the inner chart) |
| A hook needs something the release creates | Use `post-install`/`post-upgrade`, and make it wait |
| Release `failed` after a post hook | The new manifests are applied; fix and re-upgrade, or `--atomic` to roll back |
| Rotated a Secret, the app still uses the old value | Restart consumers; rotate inside stateful systems first |
| Service routes to the wrong pods | `kubectl get endpointslices -l kubernetes.io/service-name=<svc>`; check for label overlap |
| StatefulSet data after `helm uninstall` | PVCs stay; delete them deliberately |

## Common pitfalls

- Assuming `helm install --wait` proves the application is correct. It proves Kubernetes considers the Pods ready.
- Using generic labels (`app: web`) in charts that may be combined.
- Non-idempotent migrations, and migrations that are not backward compatible with the previous app version.
- Treating a persistent database's Secret as the source of truth for its password.
- Forgetting that `helm uninstall` leaves StatefulSet volumes behind (`kubectl delete pvc ...`).
