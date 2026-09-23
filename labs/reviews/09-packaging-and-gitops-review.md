# Lab 9 review: Packaging and GitOps

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (Helm v3.19.0, Argo CD stable, kind v1.35.0).

**Fixed and verified:** the Argo CD install now uses `--server-side --force-conflicts` (it applies with 0 errors), the `kubectl wait` works, and the new login block works (`argocd admin initial-password -n argocd` prints the password; `argocd login ... --insecure --grpc-web` was already verified).

## Still open

### B2: The explained break-it refers to a challenge that isn't in the lab (medium)

`09-packaging-and-gitops-explained.md` still walks through "Edit `pageContent`... render the folder and archive separately", but the lab has no "Break it and recover" section. Add it back to the lab. The explained "restore" snippet is also still a one-line `pageContent`, not Lab 6's two-line default.

### M2: The Git remote is still a hard blocker (medium)

The prerequisites still require a GitHub/GitLab remote. A local option works (verified in the first review): serve a bare repo with `git daemon --export-all --base-path=<dir> --port=9418` and use `repoURL: git://<host-ip>/helm-lab.git`. On Docker Desktop + WSL2, use the WSL `eth0` IP, because the kind gateway refuses the connection.

### M3: The GitOps change/revert steps have no commands (low)

"Change the dev replica count in Git, commit, push, refresh..." Add `argocd app get nginx-demo --refresh`, `argocd app diff nginx-demo` (note that it exits **1** when a diff exists), and `argocd app sync nginx-demo`.

### New N1: The new `argocd login` line prompts for a password (low)

`argocd login localhost:8443 --username admin --insecure --grpc-web` has no `--password`, so it stops at an interactive prompt after the learner has just printed the password with `argocd admin initial-password`. Either tell learners to paste it, or use `--password "$(argocd admin initial-password -n argocd | head -1)"` (verified).

The full re-run also confirmed Part C end to end with the local `git daemon` remote: Synced/Healthy, change to 2/2, revert to 1/1, with no Helm release and no test Pod in `helm-lab-gitops`.

### Minor (unchanged)

- **I1:** Expected `saved it to: ./dist/...` → Helm prints `dist/...`.
- **I2:** Explained Q2: `registry:2` silently overwrites a re-pushed tag (re-verified: pushing `0.2.0` twice succeeds both times). Say so.
- **I3:** Explained Q3: Argo CD doesn't run `helm test` hooks.
- **S1:** Mention `helm package --dependency-update`.
- **S2:** The `localhost:5001` registry isn't reachable from inside kind, so an OCI-sourced Argo Application isn't possible as-is.
- **S3:** Say what to do with `gitops/nginx-demo.yaml` (don't commit a personal repo URL to the shared repo).
- **S4:** Cleanup deletes `helm-registry`, but Labs 12/13 recreate it. Mention that.
- **S5:** Give the namespace delete command.
