# Lab 12 review: Secrets, signing, and CI

**Tested with:** Helm v3.19.0, sops 3.13.3, age 1.3.2, helm-secrets 4.8.0-dev, helm-unittest 1.1.2, cosign v3.1.3, ct v3.14.0, yamllint 1.38.0, gpg 2.4.4, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** This is a large, ambitious lab, and almost everything works exactly as documented:

- **SOPS:** encrypt, `helm secrets` install, rotation producing a new Pod, and plaintext still visible in `helm get values`, the manifest, and the Secret.
- **helm-unittest:** `Tests: 20 passed, 20 total`, as predicted.
- **GPG provenance:** sign and verify pass, tampering gives `sha256 sum does not match`, and an untrusted key gives `signature made by unknown entity`.
- **OCI:** push/pull with `--verify` brings the `.prov` along.
- **cosign:** sign/verify works and the wrong key is rejected.
- **ct:** `ct lint --all` passes 4 charts, and `ct install` runs 3 scenarios in about 70 s.
- **Break-its 1–4:** all reproduce.

Two problems block or mislead learners.

## Bugs

### B1: The Step 20 version-bump gate fails before any change for learners using this repo (high)

`ct` compares against `origin/main`. In this repository, `origin/main` holds the **finished** chart (`nginx-demo` **0.6.0**). A learner following the README's recommended workflow (a branch from `lab-00-start` in this repo) has 0.5.0 at this point, so:

```text
Old chart version: 0.6.0
New chart version: 0.5.0
 ✖︎ nginx-demo ... > chart version not ok. Needs a version bump!
```

This appears **before** the "tweak" commit, and the lab's advice ("Bump `version`... and the same command passes") fails too: 0.5.1 is still lower than 0.6.0. The note about pushing `main` first doesn't help, because `main` isn't the learner's branch.

**Fix (verified):** Compare against a local snapshot through a temporary self-remote. `ct` insists on a `<remote>/<branch>` ref, so `--remote ""` and `--remote .` both fail with `targetBranch '/ct-base' does not exist`.

```bash
git branch -f ct-base HEAD                       # snapshot of your current progress
git remote add ctlocal "$(git rev-parse --show-toplevel)" && git fetch ctlocal ct-base
git switch -c bump-test
echo "# tweak" >> charts/nginx-demo/values.yaml && git commit -am "tweak values"
ct lint --config ct.yaml --remote ctlocal --target-branch ct-base   # Old 0.5.0 / New 0.5.0 -> Needs a version bump!
# bump to 0.5.1, commit, rerun -> All charts linted successfully
git switch - && git branch -D bump-test ct-base && git remote remove ctlocal
```

Or state explicitly that Step 20 only works in the learner's **own** fork, where `main` holds their progress.

### B2: Break-it 5 (wrong key) shows a misleading message (medium)

`XDG_CONFIG_HOME=$(mktemp -d) SOPS_AGE_KEY_FILE=/dev/null helm secrets decrypt charts/nginx-demo/secrets.dev.yaml` prints:

```text
[helm-secrets] File is not encrypted: charts/nginx-demo/secrets.dev.yaml
Error: plugin "secrets" exited with error
```

The file **is** encrypted (`sops filestatus` → `{"encrypted":true}`). helm-secrets misreports the failure, probably because the isolated `XDG_CONFIG_HOME` also affects Helm/plugin config. A learner will conclude that encryption failed.
The same experiment with sops directly gives the correct, educational message:

```bash
XDG_CONFIG_HOME=$(mktemp -d) SOPS_AGE_KEY_FILE=/dev/null sops --decrypt charts/nginx-demo/secrets.dev.yaml
# Failed to get the data key required to decrypt the SOPS file. ... Group 0: FAILED
```

Use `sops --decrypt` for this break-it, or explain the helm-secrets message.

### ~~B3~~ (withdrawn): `$GNUPGHOME` across labs

Lab 12 cleanup deletes `$GNUPGHOME`, but Lab 13 Step 17 recreates the key when `$GNUPGHOME` is unset or missing, so this works. Optionally mention in Lab 12's cleanup that Lab 13 will create a fresh signing key.

## Accuracy issues

- **I1:** Step 12 exports `pubring.gpg`/`secring.gpg` **into** `$GNUPGHOME`. The next `gpg` command then prints `gpg: starting migration from earlier GnuPG versions ... porting secret keys from '.../secring.gpg'`, which alarms learners. Export to a separate directory (for example `$GNUPGHOME/../helm-keys/`) or mention that the message is expected.
- **I2:** The plugin install commands (`helm plugin install https://github.com/jkroepke/helm-secrets`) install from the default branch. I got **`4.8.0-dev`**. Pin versions (`--version v4.7.x`) like the binaries are pinned, for reproducibility. Same for helm-unittest.
- **I3:** `sops --encrypt` reformats the YAML with 4-space indentation. That's harmless, but learners comparing with the lab's snippet may think something changed. Worth one line.
- **I4:** The repository `.gitignore` already contains the Step 2 lines on `main`. Learners practicing in this repo will append duplicates. Say "Make sure `.gitignore` contains".

## Ease-of-following suggestions

- **S1:** The lab is long (4 parts, 21 steps, about 930 lines). Consider splitting it into 12a (SOPS + unittest) and 12b (signing + CI), or at least add per-part "checkpoint" commands so learners can stop and resume.
- **S2:** Many paths use `/tmp/...` (`/tmp/signed`, `/tmp/tampered`, `/tmp/cosign.key`, ...), and Step 16 does `cd /tmp` without returning. Use a single `LAB_TMP=$(mktemp -d)` variable throughout, and `cd -` at the end of Step 16.
- **S3:** Step 16: capture the digest automatically instead of "paste the digest":
  `DIGEST=$(helm push ... 2>&1 | awk '/Digest/{print $2}')`.
- **S4:** Step 7: after the upgrade, `kubectl get pods -l app=demo-secret` can briefly list the old terminating Pod too. Add `--field-selector=status.phase=Running`, or rely on `--wait`, which the lab already uses.
- **S5:** Part B could add a test asserting that the migration Job's Pod template does **not** carry the selector label. That would have caught the Lab 10 review B1.
- **S6:** Step 21's workflow uses `helm/chart-testing-action@v2.7.0` and `azure/setup-helm@v4`. Fine, but mention pinning actions by SHA for supply-chain hygiene, which fits this lab's theme.
