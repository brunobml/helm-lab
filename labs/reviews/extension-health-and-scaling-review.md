# Extension review: Workload health and scaling

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The startup-probe template hint, the dev-values upgrades, the `-l app=demo-dev` `top` command, the load command, the metrics-server hint, and a break-it that matches reality (new Pod `0/1`, old Pod serving).

## Still open

- **B1 (high):** There's still no warning that enabling the HPA drops `spec.replicas` immediately (re-verified earlier: 3 → 1).
- **M (medium):** There's no values hint for `livenessProbe`/`readinessProbe`/`startupProbe`/`autoscaling`, unlike the other three extensions. A learner has to invent the shape, including a sensible `startupProbe` (see the Lab 16 review N2 for the port trap).
- **Minor:** On kind, `kubectl top` still needs the commented metrics-server install. Suggest making it an explicit step.
