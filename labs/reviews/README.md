# Lab walkthrough review: summary

| Pass | Date | Against |
| --- | --- | --- |
| 1 — full run | 2026-09-22 | `b2c7374` |
| 2 — changed labs | 2026-09-23 | `44d3404` |
| 3 — full run | 2026-09-23 | `44d3404` |
| **4 — full run** | **2026-09-23** | **`cafc1b2`** |

**Fourth pass method:** I deleted all clusters and scratch state first. Then every core lab (0–18) and all four extensions were executed step by step on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0), starting from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks (Traefik Ingress, HPA 1 → 4 under load). Each report lists only what's still open or new. Earlier versions are in git history.

**Result:** Most earlier findings are fixed, and a literal learner run now gets through Labs 0–15. **No review file could be deleted**, because every lab still has at least one open item. For many labs these are only optional suggestions.

## Status

| Lab | Report | Now | Headline |
| --- | --- | --- | --- |
| 0 | [00](00-chart-creation-review.md) | ⚠️ | Empty-workspace fix works. The Start line and README still invite overwriting `main` |
| 1 | [01](01-first-chart-review.md) | ✅ | Suggestions only |
| 2 | [02](02-release-lifecycle-review.md) | ✅ | Suggestions only |
| 3 | [03](03-values-and-environments-review.md) | ✅ | Suggestions only |
| 4 | [04](04-template-logic-review.md) | ✅ | Explained-page error text and a "where `env` lands" mismatch |
| 5 | [05](05-helpers-and-labels-review.md) | ⚠️ | The explained page still answers different questions |
| 6 | [06](06-configmaps-and-rollouts-review.md) | ⚠️ | **The explained break-it still uses a bare `--set` upgrade (it would roll the Pods)** |
| 7 | [07](07-validation-and-tests-review.md) | ✅ | Fixed. Minor only |
| 8 | [08](08-dependencies-review.md) | ✅ | Explained `Chart.lock` "checksum" claim |
| 9 | [09](09-packaging-and-gitops-review.md) | ⚠️ | **New:** the `git daemon` URL is wrong (`/helm-lab.git` isn't exported), and the new break-it doesn't show drift |
| 10 | [10](10-hooks-and-failure-recovery-review.md) | ⚠️ | Passes as written. **Tags `lab-10/15/16/17-complete` now equal `main`**, which breaks README Approach 2 |
| 11 | [11](11-advanced-templating-and-library-charts-review.md) | ✅ | Minor only |
| 12 | [12](12-secrets-signing-and-ci-review.md) | ✅ | Minor only |
| 13 | [13](13-capstone-review.md) | ✅ | Minor only (stale "Roadmap" link) |
| 14 | [14](14-consuming-third-party-charts-review.md) | ✅ | Minor only |
| 15 | [15](15-crds-and-operators-review.md) | ✅ | The trap now reproduces exactly. Minor only |
| 16 | [16](16-production-hardening-and-best-practices-review.md) | ❌ | **New:** pasting the helm-docs snippet breaks lint (`image.tag: ""`), and `startupProbe` isn't moved to 8080 |
| 17 | [17](17-many-releases-helmfile-and-applicationset-review.md) | ❌ | **New:** the psql step targets `deploy/` (it's a StatefulSet) and user `postgres` (it's `shop`) |
| 18 | [18](18-helm-internals-and-advanced-operations-review.md) | ⚠️ | **New:** Option B after Option A re-blocks the release. Use a `status=pending-upgrade` label delete |
| Ext | [networking](extension-networking-review.md) | ✅ | Fixed. ingress-nginx retirement note only |
| Ext | [health](extension-health-and-scaling-review.md) | ⚠️ | No HPA scale-down warning, and no values hint |
| Ext | [identity](extension-identity-and-secrets-review.md) | ✅ | Suggestions only |
| Ext | [storage](extension-storage-and-workloads-review.md) | ⚠️ | Step 4 (Job/CronJob) empty; `Recreate` strategy |

✅ works as written (minor items or suggestions only) · ⚠️ works, with a misleading step or doc error · ❌ a learner following the text hits a failure

## Suggested next priority

1. **Lab 16:** replace the helm-docs snippet with comment-only lines, and add `startupProbe` to the 8080 switch.
2. **Lab 17:** `statefulset/backend-db-db` with `psql -U shop -d shop`.
3. **Lab 18:** Option B deletes `-l status=pending-upgrade`, or is practiced on a fresh release.
4. **Lab 9:** fix the `git daemon` URL, and base the break-it on `values.yaml` with a version bump.
5. **Tags:** give `lab-10/15/16/17-complete` their own end-of-lab states, or update README Approach 2.
6. The remaining explained-page errors (Labs 4, 5, 6, 8) and the health extension's values hint.
