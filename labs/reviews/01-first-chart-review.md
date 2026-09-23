# Lab 1 review: First chart

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** Explained B1 (`replicas: null` is accepted and defaults to 1) and I1 (CoreDNS vs kube-proxy). Install, port-forward, curl, and break-it all work as written.

## Still open (suggestions only)

- **S1:** The Verify block runs `kubectl port-forward` in the foreground, so a learner who pastes the whole block blocks there. Background it with `&` and `kill %1`, or split the block.
- **S5:** "create `lab-01-complete`" fails with `tag already exists` when practicing in this repo. This applies to every lab's checkpoint. Suggest `my-lab-NN`.
- **S2–S4, S6** as before (`--wait` redundancy, exact `grep replicas`, a prediction answer, and noting that `lab-01-complete` == `lab-00-start`).
