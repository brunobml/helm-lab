# Lab 9 review: Packaging and GitOps

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The non-interactive login (`--password "$ARGOCD_PWD"`), the explicit refresh/diff/sync commands (`|| true` for the diff exit code), and the server-side Argo CD install. Part C passed end to end: Synced/Healthy, change to 2/2, revert to 1/1.

## New bugs

- **N2 (medium): The local `git daemon` hint uses the wrong URL.** `git daemon --export-all --base-path=. --port=9418` run in the repo root, with `repoURL: git://<host-ip>/helm-lab.git`, fails with `access denied or repository not exported: /helm-lab.git`. With `--base-path=.`, the repository is served at `git://<host-ip>/` (verified, and Argo CD synced from it). Either use `repoURL: git://<host-ip>/`, or run from the parent directory with `--base-path=..` and `git://<host-ip>/helm-lab`. Also note that this exposes every ref on port 9418 to the network, and that on Docker Desktop/WSL2 `<host-ip>` is the WSL `eth0` address.
- **N3 (medium): The new break-it doesn't demonstrate archive immutability.** It edits `values-dev.yaml`, but that file isn't part of the chart's defaults, and learners always pass it with `-f` from disk. Rendering the archive with `-f charts/nginx-demo/values-dev.yaml` **does** show the change (verified). Edit `values.yaml` or a template instead, which is what the explained page does. Also, "re-package ... to update the archive" re-publishes the **same** version 0.2.0, which contradicts the lab's immutable-version lesson. Bump the version instead.

## Still open (minor)

- **I1:** Expected `saved it to: ./dist/...`. Helm prints `dist/...`.
- **I2 / I3:** `registry:2` overwrites re-pushed tags; Argo CD doesn't run `helm test` hooks.
- **S1–S5** as before.
