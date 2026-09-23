# Lab 15 review: CRDs and operators

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (Helm v3.19.0, kind v1.35.0). Re-run from the Lab 14 state.

**Fixed and verified (with `main`'s `charts/crd-demo`):** Part A now reproduces every claim exactly:

- the initial schema `{"cronSpec":...,"image":...}`
- after editing the CRD and upgrading: `Warning: unknown field "spec.replicas"`, the CR shows `{"cronSpec":"...","image":"busybox:latest"}`, and `helm get manifest` shows `replicas: 3`
- after `kubectl apply` of the CRD, an upgrade with the **same** value still leaves `replicas` absent, and changing to `5` makes it appear
- uninstall deletes the CR and keeps the CRD

The new `keep` jsonpath, the Trap 2 error text, and the Explain section with its link are also good.

## New bug

### N1: The new Step 1 checkout pulls the **old** chart, so the trap disappears again (high)

Step 1 now says:

```bash
git checkout lab-15-complete -- charts/crd-demo
```

The `lab-15-complete` tag was **not moved**. It still has chart 0.2.0 with `replicas` in the CRD and `replicas: 1` in values. Verified by following the lab verbatim:

```text
Step 2 schema: {"cronSpec":{"type":"string"},"image":{"type":"string"},"replicas":{"type":"integer"}}
Step 3 upgrade: no warning; CR = {"cronSpec":"...","image":"busybox:latest","replicas":3}
```

That contradicts Step 2's new `*Expect:*` line and the whole warning box.
**Fix:** Either `git checkout main -- charts/crd-demo`, or move the tag: `git tag -f lab-15-complete <commit with the 0.1.0 chart>` (and force-push tags). Moving the tag also brings `git diff lab-15-complete` back in line. Note, though, that the tag's chart should be the **end-of-lab** state (0.2.0 with `replicas`, after Step 3's edit), while the starter should be 0.1.0, so a separate `lab-15-start` path or `main` is the cleaner source.

## Still open (minor)

- **New N2:** Step 4's `kubectl apply -f charts/crd-demo/crds/crontabs.yaml` prints `Warning: resource customresourcedefinitions/crontabs.stable.example.com is missing the kubectl.kubernetes.io/last-applied-configuration annotation ...`, because Helm created the CRD. It's harmless, so say so, or use `kubectl apply --server-side`.

- **I2:** cert-manager v1.16.2 is pinned while the repo's current version is v1.21.2. Also mention `crds.keep: true` (the default), which is what adds the `keep` annotation.
- **I3:** Step 8: the kept CRDs still carry `meta.helm.sh/release-name: cert-manager`. Reinstalling under a different release name fails with the ownership error.
- **S2:** Verify still only checks `helm template` behavior. Add a check for the CRD-not-upgraded lesson.
- **S3:** Step 7: use `kubectl wait --for=condition=Ready certificate/lab-demo-tls -n helm-lab --timeout=60s` instead of checking immediately.
- The Explain questions are good, but `15-crds-and-operators-explained.md` is organized by topic (sections 1–6), not by those 4 questions. Consider mapping each question to a section.
