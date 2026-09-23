# Lab 15 review: CRDs and operators

**Tested with:** Helm v3.19.0, cert-manager chart v1.16.2 (the repo's latest is v1.21.2), kind (Kubernetes v1.35.0), 2026-09-23
**Result:** Part B (cert-manager) and Part C Trap 1 reproduce exactly:

- 3 Pods and 6 CRDs, with the `keep` annotation.
- The Certificate reaches `READY True`, and the TLS Secret is created.
- Uninstall prints the "kept due to the resource policy" list.
- The CRDs, Certificate, and Secret survive.
- Trap 1: `the server could not find the requested resource (post issuers.cert-manager.io)`.

**Part A (the lab's core lesson) can't be done as written.** The chart it depends on isn't provided, and the chart in the tag makes the trap impossible to observe.

## Bugs

### B1: `charts/crd-demo` doesn't exist at the lab's starting point, and the lab never provides it (high)

The lab starts from `lab-14-complete` and says "Inspect `charts/crd-demo`". But:

- `git ls-tree lab-14-complete` has **no** `charts/crd-demo`.
- The lab contains **no** file contents for it (unlike Labs 8, 11, and 13, which spell out every file).

A learner following the path gets `ls: cannot access 'charts/crd-demo'`. The only way forward is `git checkout lab-15-complete -- charts/crd-demo`, which the lab never mentions.
**Fix:** Add a "Step 0: create the demo chart" with the 5 files (Chart.yaml, values.yaml, crds/crontabs.yaml, templates/crontab.yaml, NOTES.txt), or tell learners to check it out from the tag.

### B2: The shipped CRD already contains `replicas`, so the "Silent Drop Trap" never happens (high)

`charts/crd-demo/crds/crontabs.yaml` (tag `lab-15-complete`, chart 0.2.0) already defines `spec.replicas: {type: integer}`. Following Steps 2–3 as written:

- Step 2's schema check shows `{"cronSpec":...,"image":...,"replicas":{"type":"integer"}}`. The lab hedges with "(or schema with `replicas` depending on chart version)".
- Step 3's `--set crontab.replicas=3` **works fine**, with no warning, and the live CR has `"replicas":3`.

So the warning box ("Helm reported success... Kubernetes silently stripped the field") describes something the learner never sees, and Step 4's "manual CRD upgrade playbook" has nothing to fix.

**Verified that the lesson itself is correct.** When I pre-installed a v1 CRD **without** `replicas` and then ran the lab's commands:

```text
helm upgrade ... --set crontab.replicas=3
  → Warning: unknown field "spec.replicas"
  → Release "crd-demo" has been upgraded. Happy Helming!
kubectl get crontab my-cron -o jsonpath='{.spec}'      → {"cronSpec":"...","image":"busybox:latest"}    (dropped)
helm get manifest crd-demo | grep replicas             → replicas: 3                                     (Helm thinks it's there)
kubectl apply -f charts/crd-demo/crds/crontabs.yaml    → configured
helm upgrade ... --set crontab.replicas=3  (same value) → CR still has NO replicas   (3-way merge sees no change)
helm upgrade ... --set crontab.replicas=5              → {"...","replicas":5}
```

Every claim in the warning box is confirmed, including the subtle "same value won't re-apply" point (which deserves its own explicit step, because it's the most valuable insight in the lab).

**Fix:** Ship the chart as **0.1.0 without `replicas`** in the CRD, and without `replicas` in `values.yaml` (the current default `replicas: 1` is rendered even on the first install). Then have Step 3 *edit* the CRD file (the "upstream maintainer" change) and bump to 0.2.0. That also shows directly that `helm upgrade` ignores `crds/`.

### B3: Lab 15 has no "Break it", "Explain", or link to its explained page (medium)

Every other lab ends with Explain questions and a `> [!TIP] See ...-explained.md` link. Lab 15 has neither, so learners won't find `15-crds-and-operators-explained.md`. The explained page is organized by topic ("Why Helm releases and CRDs clash", "Pattern 1/2/3") rather than questions, so either add matching questions to the lab or just link it.

## Accuracy issues

- **I1:** Step 6 expects the CRD annotations to be `{"helm.sh/resource-policy":"keep"}`. Actual: `{"helm.sh/resource-policy":"keep","meta.helm.sh/release-name":"cert-manager","meta.helm.sh/release-namespace":"cert-manager"}`. Use `jsonpath='{.metadata.annotations.helm\.sh/resource-policy}'` to print just `keep`.
- **I2:** cert-manager **v1.16.2** is several minors behind (the repo's current version is v1.21.2). Pinning is correct, but note the date, or bump. Also mention `crds.keep: true` (the default), which is what adds the annotation. The lab attributes it to `crds.enabled` alone.
- **I3:** Step 8 doesn't mention that the kept CRDs still carry `meta.helm.sh/release-name: cert-manager`. Reinstalling with the **same** release name re-adopts them. A *different* release name fails with the ownership error from the Lab 3 review B2. That's worth a line, since it's the next thing that goes wrong in real clusters.
- **I4:** Part C Trap 2 says "Helm renders and validates **all templates across all subcharts simultaneously**... the API server rejects `issuer.yaml`". In Helm 3, the failure usually occurs **client-side before anything is applied** because Helm builds its REST mapping for all resources up front. Verified with a one-template chart:
  `Error: INSTALLATION FAILED: unable to build kubernetes objects from release manifest: resource mapping not found for name: "x" namespace: "" from "": no matches for kind "Issuer" in version "cert-manager.io/v1" ensure CRDs are installed first`.
  Quote this real message; nothing is applied, so there's no half-installed release to clean up.

## Ease-of-following suggestions

- **S1:** Step 5 cleanup and the final cleanup both delete the demo CRD. Also add `helm uninstall crd-demo` output expectations (the CR is deleted, the CRD kept), which I confirmed.
- **S2:** The Verify section only checks `helm template` behavior (no cluster). Add a check for the key lesson, for example that after an upgrade the CRD schema is unchanged unless it was `kubectl apply`'d.
- **S3:** Part B's Step 7 `sleep`-free check can race: the Certificate is `READY False` for a few seconds. Suggest `kubectl wait --for=condition=Ready certificate/lab-demo-tls -n helm-lab --timeout=60s`.
