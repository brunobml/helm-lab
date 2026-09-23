# Lab 9 review: Packaging and GitOps

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0) on Docker Desktop/WSL2, Argo CD `stable` manifests + `argocd` CLI, `registry:2`, 2026-09-22
**Result:** All three parts completed successfully:

- **A:** packaged `nginx-demo-0.2.0.tgz`, installed `demo-package` from it, `helm test` passed.
- **B:** pushed to and pulled from `oci://localhost:5001/helm-lab`.
- **C:** Argo CD synced the chart from Git (including the `file://../lab-banner` dependency, with no `.tgz` committed). The Git replica change showed OutOfSync with the `replicas: 1 → 2` diff and synced to 2/2. The revert brought it back to 1/1, and `helm list -n helm-lab-gitops` stayed empty.

Part C's setup instructions are the weak spot.

## Bugs

### B1: The Argo CD install command fails (high)

```bash
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```

fails with:

```text
The CustomResourceDefinition "applicationsets.argoproj.io" is invalid: metadata.annotations: Too long: may not be more than 262144 bytes
```

The ApplicationSet CRD is too large for client-side apply's `last-applied-configuration` annotation. Argo CD's docs now say to use server-side apply:

```bash
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait -n argocd --for=condition=Available deploy --all --timeout=300s
```

Lab 17 probably needs the same fix.

### B2: The explained page's break-it refers to a challenge that isn't in the lab (medium)

`09-packaging-and-gitops-explained.md` walks through "Edit `pageContent` in the working chart and render the folder and archive separately...". **Lab 9 has no "Break it and recover" section.** The exercise is good (it shows that the archive is an immutable snapshot), so add it back to the lab.
Also, its "restore" snippet (`pageContent: "<h1>Hello from Helm Lab</h1>"`) doesn't match the two-line default from Lab 6.

## Missing instructions (Part C)

- **M1: No CLI or UI login steps.** The lab runs `argocd app get` and says "Use the Argo CD UI equivalents", but never explains how to reach either. A learner with a fresh install needs:

  ```bash
  kubectl port-forward -n argocd svc/argocd-server 8443:443 &
  argocd admin initial-password -n argocd      # or read secret argocd-initial-admin-secret
  argocd login localhost:8443 --username admin --insecure --grpc-web
  ```

  Without `--grpc-web` over a port-forward, the CLI prints noisy warnings. The UI is at `https://localhost:8443`.
- **M2: The Git remote is a hard blocker for many learners.** Offer a local option. I confirmed that this works:

  ```bash
  git init --bare /tmp/gitops/helm-lab.git && git push /tmp/gitops/helm-lab.git my-branch
  git daemon --reuseaddr --export-all --base-path=/tmp/gitops --port=9418 /tmp/gitops &
  # repoURL: git://<host-ip>/helm-lab.git
  ```

  On Docker Desktop + WSL2, the kind bridge gateway (`172.19.0.1`) **refused** the connection. The WSL `eth0` IP worked. On native Linux Docker, the kind network gateway should work. An in-cluster Gitea is the more portable alternative.
- **M3:** Steps like "Change the dev replica count in Git, commit, push, refresh" have no commands. Add them (`argocd app get nginx-demo --refresh`, then `argocd app diff`, then `sync`).

## Accuracy issues

- **I1:** The expected packaging output shows `saved it to: ./dist/nginx-demo-0.2.0.tgz`. Helm prints `dist/nginx-demo-0.2.0.tgz` (no `./`). Trivial.
- **I2:** Explained Q2: "pushing the same version tag twice can be blocked". True for some registries (ECR immutability, GHCR policies), but `registry:2` from Part B silently **overwrites**. Say so, because it's exactly the risk the question is about.
- **I3:** Explained Q3 is correct about `helm list` being empty (verified). Also mention that Argo CD **does not run `helm test` hooks**: the `demo-dev-http-test` Pod never appeared in the sync. That's a direct consequence of Argo owning the lifecycle, and it links to Lab 7.
- **I4:** `argocd app diff` exits with code **1** when there is a diff. Learners running scripts with `set -e` will be surprised. Mention it.

## Ease-of-following suggestions

- **S1:** Part A: mention `helm package --dependency-update` as a one-step alternative, and explain why `dependency build` is needed (`.tgz` files are git-ignored since Lab 8).
- **S2:** Part B uses the `localhost:5001` registry, which the kind cluster *can't* reach, so Part C can't use the OCI artifact. Mention this, and that a cluster-reachable registry would allow an OCI-sourced Argo Application (`chart: nginx-demo`, `repoURL: <registry>/helm-lab`), which is the real "install a versioned artifact" GitOps pattern.
- **S3:** Part C: tell learners **not to commit `gitops/nginx-demo.yaml` with their real repo URL into the shared repo**, or add `gitops/` to the reference tree. It's currently created but its fate is undefined (and it's not in `lab-09-complete`).
- **S4:** Cleanup deletes `helm-registry`, but Lab 12 (signing/OCI) probably needs a registry again. Consider keeping it running until the end of Lab 12, or say that later labs recreate it.
- **S5:** Cleanup: "Delete the dedicated GitOps namespace afterward" → `kubectl delete namespace helm-lab-gitops`.
