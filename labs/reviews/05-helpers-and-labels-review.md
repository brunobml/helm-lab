# Lab 5 review: Helpers and labels

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** This is the most beginner-friendly lab so far: step-by-step checks, a clear indentation table, and answers included. Every step works. The upgrade keeps the selector `{"app":"demo-dev"}`, the Pods get the five labels, and curl works. The experiment's claim is confirmed: a server-side dry run of the version-in-selector Deployment returns `spec.selector: Invalid value: ... field is immutable`. My templates match `lab-05-complete` (except for comments).

The main problem is that **the lab and its explained page are out of sync**.

## Bugs

### B1: The explained page answers different questions than the lab asks (high)

| Lab 5 "Check your understanding" | `05-helpers-and-labels-explained.md` |
| --- | --- |
| 1. `define` vs `include`? | Q1: Why are metadata and selector labels separate helpers? |
| 2. Why five labels on Pods but one in selectors? | Q2: Why prefix helper names with `nginx-demo`? |
| 3. What does `nindent 8` do? | Q3: Why could renaming resources turn a refactor into replacement? |
| 4. Why keep the same resource names? | — |

The explained page also quotes a "What the challenge asks" block ("Temporarily put the version label in the selector helper and render. Compare with the installed Deployment's selector...") that no longer exists in the lab. The lab was evidently rewritten into the new format ("Small experiment") without updating the companion.
Also, the lab is the **only one without a link** to its explained page (`grep -c explained` returns 0), so learners won't find it anyway.

**Fix:** Either add the explained page's three questions to the lab (they're good, especially helper namespacing), or rewrite the companion around the lab's 4 questions. Then add the usual `> [!TIP] See 05-helpers-and-labels-explained.md` link.

### B2: The explained page shows a `helm.sh/chart` label the lab never adds (low)

Explained Q1 lists `helm.sh/chart: nginx-demo-0.1.0` under the `labels` helper. The lab's helper (and the `lab-05-complete` tag) has no such label. Either add it to the lab (it's the Helm-recommended label, and a nice trigger later for "labels change every chart bump, so never put them in selectors"), or drop it from the explained page.

### B3: The explained selector example contradicts the lab's design (low)

Explained Q1 shows `selectorLabels` as `app.kubernetes.io/name` + `app.kubernetes.io/instance` ("or in our lab: app: demo-dev"). That's fine as an aside. But it should say *why* the lab keeps `app:` (the selector can't change on an existing release, see the lab's Answer 4). Otherwise learners may "improve" the selector and hit the immutability error on `demo-dev`.

## Accuracy issues

- **I1:** The explained immutability error text: the real Helm 3.19 / k8s 1.35 wording is
  `spec.selector: Invalid value: {"matchLabels":{"app":"demo-dev","app.kubernetes.io/version":"1.30.4"}}: field is immutable` (JSON, not `map[string]string{...}`). Minor.
- **I2:** The lab's "Finish" section says "Mark Lab 5 complete in the README". No other lab says this, and editing the README creates merge noise against `main`. Make it consistent with the other labs.

## Ease-of-following suggestions

- **S1:** The "Small experiment" says "Do not upgrade this experimental version". Give a safe way to *see* the rejection, which is much more memorable than being told:

  ```bash
  helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml \
    --show-only templates/deployment.yaml | kubectl apply --dry-run=server -n helm-lab -f -
  ```

  It prints a harmless warning about `last-applied-configuration`, then `field is immutable`. Verified.
- **S2:** Step 4's heading instruction "At the top of both files, add or update `metadata.labels`" is easy to misplace. Show the full `metadata:` block for the Service, since it had no labels before.
- **S3:** Step 1 says "Open or create `_helpers.tpl`". Learners who followed Lab 0 deleted it, so they're creating it. Say "Create" directly, and note that its leading `_` tells Helm not to render it as a manifest.
- **S4:** The lab's port-forward block has the same blocking-command issue as Lab 1 S1.
- **S5:** The lab uses a different structure (no "Break it and recover" / "Explain" headings) from every other lab. It's a better structure, so consider it the template for others (see `labs/TEMPLATE.md`) rather than making this one match.
