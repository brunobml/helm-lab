# Lab 12 review: Secrets, signing, and CI

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified:** The whole lab passes as written: SOPS, rotation, 20/20 unit tests, GPG sign and verify, OCI with verify, cosign, `ct lint`/`ct install`, the Step 20 gate, and the break-its.

## Still open (minor)

- **I1:** Exporting `pubring.gpg`/`secring.gpg` into `$GNUPGHOME` makes gpg print `starting migration from earlier GnuPG versions` (re-observed).
- **I2:** The `helm plugin install` commands are unpinned.
- **I3, I4, S1–S3, S5, S6** as before.
