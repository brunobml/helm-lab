# Lab walkthrough review: summary

**Date:** 2026-09-22/23
**Method:** Every core lab (0–18) and all four extensions were executed step by step, as a learner would, on a fresh **kind** cluster. Cluster-sensitive parts were also spot-checked on **k3d**: Ingress via bundled Traefik, and HPA via bundled metrics-server. Chart edits were made on the scratch branch `lab-walkthrough` (one commit per lab) and compared with the repository's `lab-NN-complete` tags. The explained pages were read and their quoted outputs checked against real output.

**Environment:** Helm v3.19.0, kubectl/Kubernetes v1.35.0 (kind) and v1.35.5+k3s1 (k3d), helm-diff 3.15.13, helm-secrets 4.8.0-dev, helm-unittest 1.1.2, helm-mapkubeapis 0.5.2, sops 3.13.3, age 1.3.2, cosign 3.1.3, ct 3.14.0, helmfile 1.8.0, Argo CD (stable manifests), Docker Desktop on WSL2.

## Reports

| Lab | Report | Status | Top issue |
| --- | --- | --- | --- |
| 0 | [00](00-chart-creation-review.md) | ⚠️ | The break-it (`version: 1`) gives a different error. Quoted, it **passes** lint |
| 1 | [01](01-first-chart-review.md) | ✅ | The explained page says the API rejects `replicas: null`, but it defaults to 1 |
| 2 | [02](02-release-lifecycle-review.md) | ✅ | The explained history samples don't match the lab's revision sequence |
| 3 | [03](03-values-and-environments-review.md) | ✅ | The explained page misstates when `helm upgrade` reuses values |
| 4 | [04](04-template-logic-review.md) | ✅ | Several quoted error messages are wrong. The untrimmed-whitespace example contradicts itself |
| 5 | [05](05-helpers-and-labels-review.md) | ✅ | The explained page answers different questions than the lab asks, and there's no link |
| 6 | [06](06-configmaps-and-rollouts-review.md) | ✅ | The explained break-it would itself trigger a rollout |
| 7 | [07](07-validation-and-tests-review.md) | ⚠️ | The schema error format and the `helm test` output format are both outdated |
| 8 | [08](08-dependencies-review.md) | ✅ | `main` tracks `.tgz` files the lab says are ignored |
| 9 | [09](09-packaging-and-gitops-review.md) | ⚠️ | The Argo CD install command fails (needs `--server-side`). No login/Git-remote guidance |
| Ext | [networking](extension-networking-review.md) | ⚠️ | Upgrade commands drop the dev values. The explained break-it deletes the Ingress. ingress-nginx is retired |
| Ext | [health](extension-health-and-scaling-review.md) | ⚠️ | Enabling the HPA scales 3 → 1 immediately. The break-it doesn't empty the endpoints |
| Ext | [identity](extension-identity-and-secrets-review.md) | ✅ | Missing Deployment and values hints |
| Ext | [storage](extension-storage-and-workloads-review.md) | ⚠️ | The PVC break-it can't be "restored" by upgrade (immutable). Job/CronJob step has no content |
| 10 | [10](10-hooks-and-failure-recovery-review.md) | ⚠️ | **The migration Job Pod joins the app Service as a Ready endpoint** |
| 11 | [11](11-advanced-templating-and-library-charts-review.md) | ✅ | Library edits need `helm dependency update` to take effect |
| 12 | [12](12-secrets-signing-and-ci-review.md) | ⚠️ | The ct version gate fails for anyone using this repo (compares with the finished `main`) |
| 13 | [13](13-capstone-review.md) | ✅ | Best lab. Everything reproduced |
| 14 | [14](14-consuming-third-party-charts-review.md) | ⚠️ | Verify and break-it 2 use release `test`, but the Kustomize patch targets `my-podinfo` |
| 15 | [15](15-crds-and-operators-review.md) | ❌ | `crd-demo` is missing at the start, and its CRD already has `replicas`, so the trap can't happen |
| 16 | [16](16-production-hardening-and-best-practices-review.md) | ❌ | Security contexts are never rendered, so **Step 9 fails**. The `shop` chart breaks (also on `main`) |
| 17 | [17](17-many-releases-helmfile-and-applicationset-review.md) | ❌ | The API points at the wrong DB host and is never Ready. Files are missing at the start. `needs:` doesn't wait |
| 18 | [18](18-helm-internals-and-advanced-operations-review.md) | ⚠️ | The label-only `pending-upgrade` break-it does nothing. The `--take-ownership` version is wrong |

✅ works as written (doc fixes only) · ⚠️ works with workarounds or has misleading steps · ❌ a learner following the text gets stuck

## Cross-cutting issues (fix once, everywhere)

1. **The optional extensions are silently mandatory.** `lab-10-complete` and later tags include all extension artifacts (Ingress, HPA, ServiceAccount, RBAC). Lab 13 expects a ServiceAccount, and Lab 16 edits the probes the health extension added. Either move the extensions into the core path (between Labs 9 and 10, as the tag history already does) or remove those dependencies.
2. **Lab text and reference tags drift apart from Lab 15 on.** Labs 15 and 17 say "inspect" files that don't exist at the previous tag, and Lab 16/17 tags contain template changes the text never shows. Labs 0–13 spell out every file, and 15–18 should too, or explicitly say `git checkout lab-NN-complete -- <paths>`.
3. **`--reset-values -f values-dev.yaml` is inconsistent.** Lab 3 establishes it as the convention, but the extensions and several explained pages upgrade with bare `--set`, silently resetting `demo-dev` to chart defaults (replicas, env, page).
4. **The explained pages have drifted from the labs.** In Labs 5 and 6 they answer different questions. Labs 15–18 have no Explain section or link. Many quoted error messages come from older Helm/Kubernetes versions (Labs 0, 1, 3, 4, 6, 7, 8). Consider regenerating the sample outputs from a real run, which `lab-validation.md` could automate.
5. **The checkpoint tag instructions clash with the repo's tags.** Every lab says "create `lab-NN-complete`", but those tags already exist, so `git tag` fails. Suggest a personal prefix (`my-lab-NN`).
6. **The `app: <release>` selector label is leaked into auxiliary Pods** through `nginx-demo.labels` and `lab-common.labels`, so the migration Job Pods become Service endpoints and match the PDB and NetworkPolicy (Labs 10, 11, 16). The capstone avoids it only by disabling the web migration.
7. **`main` can't build the capstone from a fresh clone.** `charts/shop` pins `nginx-demo` 0.5.0, but the chart is 0.6.0 (Lab 16 review B3).
8. **Fixed `/tmp/...` paths and `:latest` images** appear in Labs 11–17. Use `mktemp -d` and pinned tags, consistent with the course's own pinning advice.
9. **Structure has drifted.** Labs 5 and 6 use a friendlier format, Labs 10–12 add "Your notes", and 15–18 drop "Explain". `labs/TEMPLATE.md` could be updated to one format.

## Suggested priority

1. Labs 16, 17, 15 (learners get stuck), and `charts/shop/Chart.yaml` on `main`.
2. Lab 10 migration Job labels (a chart bug that propagates).
3. Lab 14's release-name mismatch, Lab 18's pending-upgrade simulation, Lab 12's ct version gate, and Lab 9's Argo CD install.
4. Explained-page output refresh (Labs 0–8).

## Artifacts left in place

- Branch **`lab-walkthrough`**: the learner's chart progression, one commit per lab. It's safe to delete: `git branch -D lab-walkthrough`.
- Clusters: kind **`helm-lab`** (with Argo CD installed, and `demo-dev` in `helm-lab`) and k3d **`helm-lab`**. Delete them with `kind delete cluster --name helm-lab` and `k3d cluster delete helm-lab`.
- Added to your Helm setup: the plugin `mapkubeapis` (0.5.2). The `podinfo`/`jetstack`/`ingress-nginx` repos were already configured. An `argocd` CLI login context for `localhost:8443` was added.
