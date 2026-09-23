# Lab 3 review: Values and environments

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** Every command works and every expected value matches: renders show replicas 1 / 3 / 4, the two Deployments show 1/1 and 3/3, and each Service selects its own release. My files match `lab-03-complete` exactly. The explained page has three factual errors.

## Bugs

### B1: The explained page misdescribes how `helm upgrade` reuses values (high; this is exactly the concept being taught)

Explained Q1.3 says: "When running `helm upgrade`, Helm retains values supplied in previous revisions by default."
That is only half true. Tested:

| Command on a release installed with `-f values-prod.yaml` (3 replicas) | Result |
| --- | --- |
| `helm upgrade demo-prod ./charts/nginx-demo` (no `-f`/`--set`) | **3 replicas**: previous values reused |
| `helm upgrade demo-prod ./charts/nginx-demo --set image.pullPolicy=Always` | **2 replicas**: previous values *dropped*, chart defaults + new flag |

Helm 3 reuses the previous values **only when no values are passed at all**. As soon as you pass any `-f` or `--set`, it starts from the chart defaults (unless you add `--reuse-values` or `--reset-then-reuse-values`).
This is the most common Helm surprise, so the lab should teach it precisely. `--reset-values` still makes intent explicit, but the reason given for it is wrong.

**Fix:** Rewrite Q1.3 using the table above, and mention `--reuse-values` / `--reset-then-reuse-values`.

### B2: The explained page quotes the wrong error for resource name collisions (medium)

Explained Q2 says a second release with a hardcoded name fails with `Error: rendered manifests contain a resource that already exists`.
Actual Helm 3.19 output, tested with a copy of the chart that hardcodes `nginx-deployment`:

```text
Error: INSTALLATION FAILED: Unable to continue with install: Deployment "nginx-deployment" in namespace "helm-lab" exists and cannot be imported into the current release: invalid ownership metadata; annotation validation error: key "meta.helm.sh/release-name" must equal "hc2": current value is "hc1"
```

The real message is more educational because it introduces the `meta.helm.sh/release-name` ownership annotation, which Lab 18 (`--take-ownership`) builds on. Use it.

### B3: The explained page gets object identity wrong (low)

Q2 says identity is "`[Group, Version, Kind, Name]`". API **version** is not part of identity: `apps/v1` and a hypothetical `apps/v1beta2` Deployment with the same name are the same object. Identity is **group + kind + namespace + name**. Namespace is the key point for Q3 and is missing from the tuple.

## Ease-of-following suggestions

- **S1:** Step 1 and Step 2 say "Create ... with `replicaCount: 1`". Give the one-liners (`echo 'replicaCount: 1' > charts/nginx-demo/values-dev.yaml`) or a code block, as the other labs do.
- **S2:** Verify: `kubectl get service ... -o yaml` prints about 60 lines for a single fact. Suggest:
  `kubectl get svc -n helm-lab -o custom-columns=NAME:.metadata.name,SELECTOR:.spec.selector`
- **S3:** Step 3's third command produces 4 replicas. Add the reversed-order variant right there (`-f prod -f dev` gives 1) so Explain Q1 is answered by doing rather than reading.
- **S4:** Step 4 introduces `--reset-values` without saying why. Add one sentence linking it to B1 above (the previous revision had no overrides, but the flag makes the upgrade deterministic).
- **S5:** "Break it" only *renders*. To actually see the failure, suggest a quick real test:
  `helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --set service.targetPort=8080`, then `kubectl run curl --rm -it --image=curlimages/curl -n helm-lab --restart=Never -- curl -m3 demo-dev-service`, which fails with `curl: (7) Failed to connect to demo-dev-service:80 ... Could not connect to server` (verified). Then restore. Also consider updating the explained page's sample message: current curl (8.x) prints "Could not connect to server" rather than "Connection refused".
- **S6:** Checkpoint tag clash: same as Lab 1 S5.
