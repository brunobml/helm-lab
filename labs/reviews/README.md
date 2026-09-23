# Lab walkthrough review: summary

**First pass:** 2026-09-22 (all labs executed on kind, with k3d spot checks).
**Re-validation:** 2026-09-23 against commit `44d3404` ("fix: address review findings...").
**Full re-run (third pass):** 2026-09-23. All clusters and scratch state were deleted first. Then every core lab (0–18) and all four extensions were executed step by step on a **fresh kind cluster**, starting from an **empty workspace**, with code taken verbatim from the lab text, plus k3d spot checks (Traefik Ingress, HPA 1→4 under load). Every previously open item reproduced.

## Third-pass changes to the findings

- **New, Lab 0 (high):** `helm create charts/nginx-demo` fails in an empty workspace (`stat .../charts: no such file or directory`). Add `mkdir -p charts`.
- **New, Lab 9 (low):** the new `argocd login` line prompts for the password. Part C was re-verified end to end with a local `git daemon` remote.
- **New, Lab 14 (low):** Pods can still be `0/1` right after `--wait`. The post-renderer diff noise is quantified at 184 vs 10 lines.
- **New, Lab 15 (low):** `kubectl apply` on the Helm-created CRD prints a harmless `last-applied-configuration` warning.
- **Withdrawn, Lab 18 I2:** mapkubeapis *does* print the `Set status ... 'superseded'` line. My earlier claim was wrong.
- **Confirmed again:** Lab 10 fails as written without a `hookLabels` define. Lab 15's tag checkout brings back the old CRD (no trap). Lab 17's files are missing at the start and its API still returns `role "web_anon" does not exist`. Lab 16 still lacks the `# --` step and `hardening_test.yaml`.

## What the fix commit changed

`44d3404` edited **Labs 0, 9, 10, 12, 14, 15, 16, 17, 18**, plus `charts/crd-demo`, `charts/nginx-demo` (the `hookLabels` helper), `charts/shop` (the dependency range), and `helmfile/`. I re-ran those labs step by step.

It did **not** touch Labs 1–8, 11, and 13, **any** `*-explained.md` page, any extension, `README.md`, `labs/TEMPLATE.md`, or any git tag. `git diff b2c7374 HEAD` is empty for all of them. Their reviews therefore still apply unchanged, and each carries a re-validation note.

**No review could be deleted:** every lab still has at least one open item.

## Status

| Lab | Report | First pass | Now | Headline |
| --- | --- | --- | --- | --- |
| 0 | [00](00-chart-creation-review.md) | ⚠️ | ❌ | Break-it fixed, but **`helm create` fails in an empty workspace (needs `mkdir -p charts`)**. Start line/README overwrite risk remains. The explained page still teaches `version: 1` |
| 1–7 | [01](01-first-chart-review.md) … [07](07-validation-and-tests-review.md) | ✅/⚠️ | unchanged | Not edited. Lab 7's outdated schema/`helm test` output is the main lab-text issue. The rest are explained-page errors |
| 8 | [08](08-dependencies-review.md) | ✅ | ✅ | **B2 withdrawn** (my mistake: the `.tgz` files were never tracked) |
| 9 | [09](09-packaging-and-gitops-review.md) | ⚠️ | ⚠️ | Argo CD install and login fixed. Missing break-it and the Git-remote blocker remain |
| 10 | [10](10-hooks-and-failure-recovery-review.md) | ⚠️ | ❌ | Endpoint bug fixed in the chart, but **the lab never defines `nginx-demo.hookLabels`**, so a literal run fails |
| 11 | [11](11-advanced-templating-and-library-charts-review.md) | ✅ | unchanged | The library-rebuild step is still missing |
| 12 | [12](12-secrets-signing-and-ci-review.md) | ⚠️ | ✅ | ct version gate and sops break-it fixed. Only minor items remain |
| 13 | [13](13-capstone-review.md) | ✅ | ✅ | The chart-side I4 is resolved. Doc items remain |
| 14 | [14](14-consuming-third-party-charts-review.md) | ⚠️ | ✅ | Release-name bug and temp-dir fixed. Minor items remain |
| 15 | [15](15-crds-and-operators-review.md) | ❌ | ❌ | Works with `main`'s chart, but **Step 1 checks out the unmoved `lab-15-complete` tag (old CRD with `replicas`)**, so the trap disappears |
| 16 | [16](16-production-hardening-and-best-practices-review.md) | ❌ | ⚠️ | Step 9 now passes, and `shop` builds on `main`. helm-docs descriptions and `hardening_test.yaml` are still missing |
| 17 | [17](17-many-releases-helmfile-and-applicationset-review.md) | ❌ | ❌ | Host and `wait` fixed (all Pods Ready). **The files are still missing at the start**, and the API still returns `role "web_anon" does not exist` |
| 18 | [18](18-helm-internals-and-advanced-operations-review.md) | ⚠️ | ⚠️ | The pending-upgrade break-it works now. The Helm 4 table and the adoption warning remain |
| Ext | [networking](extension-networking-review.md), [health](extension-health-and-scaling-review.md), [identity](extension-identity-and-secrets-review.md), [storage](extension-storage-and-workloads-review.md) | ⚠️ | unchanged | Not edited |

✅ works as written (minor docs only) · ⚠️ works with workarounds or misleading steps · ❌ a learner following the text gets stuck

## New findings from the re-validation

1. **Lab 10:** `include "nginx-demo.hookLabels"` with no `define` anywhere in the labs gives `no template "nginx-demo.hookLabels"` (verified).
2. **Lab 15:** `git checkout lab-15-complete -- charts/crd-demo` restores the **old** CRD (verified: no warning, `replicas: 3` kept). Use `main`, or move the tag.
3. **Tags were not updated.** `lab-10-complete` (old Job labels), `lab-15-complete` (old CRD), `lab-16-complete`/`lab-17-complete` (old `shop` pin, old `dbHost`) no longer match the fixed text. Any lab that tells learners to check out from a tag, or to `git diff` against one, will mislead them. Re-tag or point to `main`.
4. **Lab 0:** the new expected lint output shows 3 of the 6 lines Helm prints.
5. **Lab 18:** Method 2 follows a successful Method 1, so learners delete an already superseded revision. Present the methods as alternatives.

## Verified healthy on `main`

A fresh worktree of `main`:

- builds `charts/shop`
- passes `helm unittest charts/nginx-demo charts/shop` (**42/42**) and `ct lint --all`
- renders the web migration Pod without the `app:` selector label

## Cross-cutting items still open

1. The optional extensions are effectively required (Lab 13's ServiceAccount, Lab 16's probes). Either put them in the core path or remove the dependencies.
2. All 19 explained pages are unchanged. Many quote outdated errors or answer different questions (Labs 0–9).
3. `--reset-values -f values-dev.yaml` is still missing in the extensions and several explained pages.
4. The "create `lab-NN-complete`" checkpoint instructions clash with the existing tags.
5. There are still fixed `/tmp/...` paths (Labs 11–14) and uneven lab structure (`labs/TEMPLATE.md`).

## Suggested next priority

1. Lab 0: add `mkdir -p charts` before `helm create`.
1. Lab 10: add the `hookLabels` define.
1. Lab 15: change the checkout source.
1. Lab 17: add a Step 0 checkout from `main` and a migration or an end-to-end check.
1. Re-tag `lab-10/15/16/17-complete`, or stop referencing tags as sources.
1. Refresh the explained pages for Labs 0–9 and the extensions' `--reset-values` usage.
