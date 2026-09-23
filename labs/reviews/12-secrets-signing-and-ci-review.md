# Lab 12 review: Secrets, signing, and CI

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Re-validated:** 2026-09-23 against `44d3404` (Helm v3.19.0, ct v3.14.0, sops 3.13.3). Re-run from the Lab 12 state.

**Fixed and verified:**

- **B1:** Step 20's local self-remote recipe works verbatim. `ct lint --remote ctlocal --target-branch ct-base` gives `chart version not ok. Needs a version bump!`, then after bumping to 0.5.1 gives `All charts linted successfully`. The teardown (`git switch - && git branch -D bump-test ct-base && git remote remove ctlocal`) leaves only `origin`.
- **B2:** Break-it 5 now uses `sops --decrypt` and prints `Failed to get the data key required to decrypt the SOPS file.`.

## Still open (minor)

- **I1:** Step 12 exports `pubring.gpg`/`secring.gpg` **into** `$GNUPGHOME`, so the next gpg call prints `starting migration from earlier GnuPG versions`. Export to a sibling directory, or mention that the message is expected.
- **I2:** `helm plugin install` for helm-secrets/helm-unittest is unpinned (it installed `4.8.0-dev`). Add `--version`.
- **I3:** `sops --encrypt` reformats YAML to 4-space indentation. Mention it.
- **I4:** Step 2 "Append to `.gitignore`": the lines already exist on `main`. Say "make sure it contains".
- **S1:** The lab is about 950 lines. Consider splitting it (12a SOPS + unittest, 12b signing + CI) or adding per-part checkpoints.
- **S2:** Replace the fixed `/tmp/...` paths with one `LAB_TMP=$(mktemp -d)`, and add `cd -` after Step 16's `cd /tmp`.
- **S3:** Capture the push digest automatically: `DIGEST=$(helm push ... 2>&1 | awk '/Digest/{print $2}')`.
- **S5:** Add a unit test asserting that the migration Job Pod has no `app:` selector label. That guards the Lab 10 fix (`hookLabels`) against regressions.
- **S6:** Pin GitHub Actions by SHA (supply-chain theme).
