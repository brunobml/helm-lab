# Lab 6 review: ConfigMaps and rollouts

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** Explained B2 (NGINX static content vs config) and the explained-page link. The lab works as written (the checksum changes and the Pod is replaced).

## Still open

- **B1 (high):** The explained break-it still runs `helm upgrade demo-dev ... --set pageContent="<h1>Rollout Test</h1>"` **without** `--reset-values -f values-dev.yaml`. That drops `extraEnv` and `resources` from the Pod template, so the Pods **are** replaced, the opposite of what the page shows.
- **B3 (medium):** The explained questions still differ from the lab's 4 questions.
- **I1:** The `nindent 2` error text. **I3, I4, S1–S5** as before.
