# Lab 1 review: First chart

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** Install, verify, and port-forward all work as written (`<title>Welcome to nginx!</title>`). The explained page gives a wrong reason for the "Break it" outcome.

## Bugs

### B1: The explained page says the API server rejects `replicas: null`, but it doesn't (high)

`01-first-chart-explained.md` step 4 claims:

```text
error: ... ValidationError(Deployment.spec.replicas): invalid type: got "null", expected "integer"
```

Tested with `kubectl apply --dry-run=server` on the broken render: the Deployment is **accepted** (`created (server dry run)`) and `spec.replicas` defaults to **1**.
The quoted message is from the old client-side `kubectl --validate` (swagger 1.x era) and is not what current clusters return. Helm's install path also wouldn't show it.

The real consequence is a stronger teaching point: **a typo silently scales `demo-dev` from 2 replicas to 1, and nothing errors.**

**Fix:** Replace the error block with something like:

```bash
helm template brk ./charts/nginx-demo | kubectl apply --dry-run=server -n helm-lab -f -
# deployment.apps/brk-deployment created (server dry run)   <- accepted, replicas defaults to 1
```

Then keep the conclusion (`required` / schema in Lab 7).

## Accuracy issues

- **I1:** Explained Q3: "kube-proxy / CoreDNS load-balances the traffic across those healthy Pod IPs". CoreDNS only resolves the Service name to the ClusterIP; kube-proxy (iptables/IPVS/nftables) does the load balancing. Drop "/ CoreDNS" or explain the split.
- **I2:** Explained Q1 says the release Secret is created "inside the release's namespace (e.g., `sh.helm.release.v1.demo-dev.v1`)". That's correct. Consider adding `kubectl get secret -n helm-lab -l owner=helm` as a one-liner so learners can see it now. Lab 18 goes deeper later.

## Ease-of-following suggestions

- **S1:** The Verify block mixes a blocking command (`kubectl port-forward`) with non-blocking ones. Learners who paste the whole block get stuck at port-forward. Split it into two blocks, or background it:

  ```bash
  kubectl port-forward -n helm-lab service/demo-dev-service 8080:80 &
  curl --fail http://localhost:8080
  kill %1
  ```

- **S2:** `--wait` together with the separate `kubectl rollout status` is redundant. Keep `rollout status` as a teaching point, but say that `--wait` already waited.
- **S3:** "Break it" asks the learner to "inspect `replicas`". Give the exact command: `helm template demo-dev ./charts/nginx-demo | grep replicas`.
- **S4:** Step 2 asks the learner to *predict* names. A collapsed "Answer" block (`demo-dev-deployment`, `demo-dev-service`, 2 replicas) would help self-checking.
- **S5:** The checkpoint says "create `lab-01-complete`", but that tag already exists in the repo. `git tag lab-01-complete` fails with `already exists` for anyone practicing on a branch of this repo (the README's Approach 1). Suggest a personal prefix, for example `git tag my-lab-01`. **This applies to every lab's checkpoint section.**
- **S6:** `lab-01-complete` is identical to `lab-00-start`, which is expected because Lab 1 doesn't change files. Say so, so learners aren't confused by an empty `git diff lab-01-complete`.
