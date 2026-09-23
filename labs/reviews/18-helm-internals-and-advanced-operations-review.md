# Lab 18 review: Helm internals and advanced operations

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (Helm v3.19.0, kind v1.35.0).

**Fixed and verified:**

- **B1:** The payload-patching break-it works verbatim. `helm list --pending` shows `pending-upgrade`, `helm upgrade` fails with `another operation (install/upgrade/rollback) is in progress`, and `helm rollback internals-demo` recovers.
- **Method 2:** Deleting the pending Secret also works. The next upgrade succeeds.
- **B2:** The `--pending` note is present.
- **B3:** `--take-ownership` is now correctly "v3.17+".
- **S3:** The lab has Explain questions and a link.

## Still open

- **B3 (rest), low:** The **Start** line still says "Helm v3.14+". Part C Step 2 needs ≥ 3.17 for `--take-ownership`.
- **B4, medium:** The table header still reads "Helm 4 (Upcoming / Design Proposals)", but Helm 4.0 shipped in November 2025. Re-check the rows against the release notes (native CRD upgrades via SSA? HTTP repositories deprecated? I'm not aware of either). Add the post-renderer-as-plugin and `--force-replace` renames.
- **I1:** Part D Step 4's expected error omits the trailing `ensure CRDs are installed first` line, which is misleading for a built-in kind.
- ~~**I2**~~ **(withdrawn):** My earlier claim was wrong. The full re-run shows mapkubeapis 0.5.2 **does** print `Set status of release version 'pdb-demo.v1' to 'superseded'.` (my first pass only looked at the last 4 lines). The lab's sample is accurate apart from the timestamp prefixes.
- **I3:** Mention the `modifiedAt` label on release Secrets.
- **I4:** Strategic merge vs. JSON merge patch for CRDs.
- **S1, medium:** Part C still doesn't warn that **adoption transfers lifecycle ownership**. `helm uninstall` deleted the adopted `legacy-app-service` and `adopt-demo-config`. Mention `helm.sh/resource-policy: keep`.
- **S2:** Adoption rewrites the Service selector to the chart's desired state. Point it out.
- **S4:** Back up the Secret before hand-editing it (Part D and the new break-it script).
- **New N1 (low):** Method 2 now deletes the pending Secret right after Method 1 has already recovered the release, so learners delete a *superseded* revision. Tell them to reproduce the stuck state first (rerun the patch script), or present the two methods as alternatives. When the learner does delete a real pending revision, `helm history` shows the earlier `pending-upgrade` revision from Method 1's run still there, which is cosmetic. Mention it.
