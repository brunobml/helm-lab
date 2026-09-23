# Lab 16 review: Production hardening and chart best practices

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (Helm v3.19.0, helm-docs v1.14.2, kubeconform v0.6.7, kind v1.35.0). Re-run literally from the Lab 15 state.

**Fixed and verified:**

- **B1 / B2:** Step 2b renders the Pod and container security contexts and `containerPort: 8080`. The literal install into the `restricted` namespace now succeeds (2 Pods `1/1`, PDB, NetworkPolicy, `helm test` Succeeded). The break-it still produces `would violate PodSecurity` / `context deadline exceeded`, and the rollback recovers.
- **B3:** The downstream-dependency note works. With `shop` still pinned at `0.5.0`, `helm dependency build charts/shop` fails. After changing it to `">=0.5.0 <=0.6.0"`, `helm dependency update charts/shop` succeeds and the umbrella renders 13 objects. On a fresh `main` worktree, `shop` builds, `helm unittest charts/nginx-demo charts/shop` passes 42/42, and `ct lint --all` passes.
- **B4 (partly):** helm-docs with `--user` writes a file owned by the user, and both images are pinned.
- **I2:** Resolved by the Lab 10 `hookLabels` change. The migration Pod no longer matches the PDB/NetworkPolicy selectors.
- **I7:** "Two Pods, each `1/1 Running`". The lab now has Explain questions and a link.

## Still open

- **B4 (rest), medium:** The Description column is still **empty for every row** (for example `| replicaCount | int | \`2\` |  |`), because no step tells learners to add`# -- ...` comments to `values.yaml`. The new sentence explains the mechanism but gives nothing to do. Add a short step with 3–4`# --` examples.
- **S2, medium:** The checkpoint says "including the hardening test suite in `tests/hardening_test.yaml`", but the lab never provides that file. A learner has only the Lab 12 suites (**20 tests**, re-verified). `main` has it (42 tests with `shop`). Include the file (or a short version) as a step.
- **I1:** The NetworkPolicy ingress still allows every namespace (`namespaceSelector: {}`), so it isn't micro-segmentation.
- **I3:** The image `1.27-alpine` doesn't match `appVersion: "1.30.4"` (`nginxinc/nginx-unprivileged:1.30-alpine` exists).
- **I4:** `/var/run` isn't needed for nginx-unprivileged (its PID file is `/tmp/nginx.pid`).
- **I5:** The test Pod uses `runAsUser: 1000` while `main` uses `101`.
- **I6:** Step 6's `topologySpreadConstraints` snippet still doesn't say where it goes. (Step 2b places `securityContext` under `spec.template.spec`, so say "next to it".)
- **I8:** kubeconform validates against 1.30.0. Match the cluster minor.
