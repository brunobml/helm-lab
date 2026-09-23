# Lab 2 review: Release lifecycle

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** All commands work. The upgrade to 3 replicas, the rollback to 1, and the image-pull failure (`UPGRADE FAILED: context deadline exceeded` after about 60 s, Pod in `ErrImagePull`) behave as described. Several sample outputs on the explained page don't match what a learner who followed the lab will see.

## Bugs

### B1: The explained page's revision numbers don't match the lab sequence (medium)

Following the lab exactly produces:

```text
1  superseded  Install complete
2  superseded  Upgrade complete            <- --set replicaCount=3
3  deployed    Rollback to 1
4  failed      Upgrade "demo-dev" failed: context deadline exceeded
```

Recovery is therefore `helm rollback demo-dev 3` (or 1), which creates **revision 5**.
The explained walkthrough shows the failed upgrade as **revision 2** and the recovery as **revision 3 "Rollback to 1"**, as if the replica upgrade and first rollback never happened. A learner comparing outputs will think something went wrong.

**Fix:** Update the sample `helm history` outputs to the 1→5 sequence above, or say explicitly that the walkthrough starts from a fresh install.

### B2: The explained page shows the wrong status for the previous revision after a failed upgrade (medium)

The explained output shows revision 1 as `superseded` while the failed revision 2 is `failed`, so **no** revision is `deployed`.
In reality, Helm 3 leaves the last good revision as **`deployed`** when an upgrade fails (revision 3 above stayed `deployed` next to failed revision 4). This matters for the lesson: `helm history` tells you which revision is live and safe to roll back to.

**Fix:** Correct the sample, and add a sentence such as: "The previous revision stays `deployed`: Helm only marks a revision `superseded` after a *successful* replacement."

## Accuracy issues

- **I1:** The explained sample shows the broken Pod in `ImagePullBackOff`. Right after the 60 s timeout, it's often still `ErrImagePull` (that's what I saw). Mention that both states are expected, because the kubelet alternates between them.
- **I2:** Explained Q2 lists "Kubernetes API Validation" as a separate phase. With `helm install/upgrade`, rendering and a client-side OpenAPI schema check happen before the apply. Worth saying because it's why some errors appear before *any* resource changes. Minor.

## Ease-of-following suggestions

- **S1:** Step 1 says "Record the current revision". Point out that it's `1` in the fresh install from Lab 1, and that `helm history demo-dev -n helm-lab --max 1` shows only the latest.
- **S2:** In "Break it", the recovery instruction is vague ("the last successful revision shown in history, using the rollback command above"). Be explicit: "Find the newest revision whose STATUS is `deployed` (revision 3 if you followed this lab) and run `helm rollback demo-dev 3 ...`."
- **S3:** Add a note that `helm upgrade` without `--reuse-values` resets `replicaCount` back to the chart default (2). Learners otherwise wonder why the broken upgrade didn't keep 3 replicas. It also sets up Lab 3's precedence discussion nicely.
- **S4:** Mention `helm get values demo-dev -n helm-lab --revision 2` to show that values are stored per revision.
- **S5:** Foreshadow Lab 10: `--atomic` in Helm 3 (renamed `--rollback-on-failure` in Helm 4; Helm 3.19.0 does not have the new name) would have auto-reverted this failure.
- **S6:** The 60 s wait in "Break it" is long. `--timeout 30s` is enough to demonstrate the failure.
- **S7:** Checkpoint: the `lab-02-complete` tag clash, same as Lab 1 S5.
