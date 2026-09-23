# Lab 16 review: Production hardening and chart best practices

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The literal run passes: restricted Pod Security, PDB, NetworkPolicy, `helm test`, and the break-it and rollback. The `# --` instruction produces descriptions, the hardening test checkout gives **28/28** tests (42/42 with `shop`), and the `shop` dependency note works.

## New bugs

- **N1 (high): The helm-docs snippet breaks the chart if pasted.** It sets `image.tag: ""` and `replicaCount: 1`. Result: `[ERROR] values.yaml: - at '/image/tag': minLength: got 0, want 1`, and lint fails (verified). The comment "Overrides the image tag whose default is the chart appVersion" isn't true for this chart (the template uses `.Values.image.tag` directly), and `replicaCount: 1` silently changes the default from 2. Show only the comment lines added above the **existing** values.
- **N2 (medium): `startupProbe` isn't moved to 8080.** The health extension now introduces `startupProbe`, but Lab 16 Step 1 only moves the liveness and readiness probes to 8080. With a startup probe still on port 80, the new Pod stays `0/1` and the upgrade times out (verified). Add `startupProbe` to Step 1.

## Still open (minor)

- **I1:** The NetworkPolicy ingress still allows every namespace (`namespaceSelector: {}`).
- **I3:** The `1.27-alpine` image doesn't match `appVersion: "1.30.4"` (`1.30-alpine` exists).
- **I4, I5, I8** as before.
