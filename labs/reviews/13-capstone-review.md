# Lab 13 review: Capstone, a three-tier release

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified:** Every step and break-it reproduced again (render counts, deploy, idempotent seed, failed post-hook `desired=2`, `--atomic`, DB restart recovery, the rotation trap and fix, 34 unit tests, ct, the signed OCI install, the label hijack, and build order).

## Still open (minor)

- **I1:** Step 9's "1 ServiceAccount" depends on the optional Identity extension.
- **I2:** "compare with the Roadmap's Lab 16" is still in the lab (line ~1222). Link to Lab 16.
- **I3:** `kubectl run --rm -i -q` prints the output twice (`couldn't attach to pod ..., falling back to streaming logs`).
- **I5:** Fixed `/tmp/...` paths.
- **S1–S5** as before.
