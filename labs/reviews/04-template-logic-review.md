# Lab 4 review: Template logic

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** Explained B1 (the untrimmed example now shows blank lines) and B2 (the real env-type error). The lab works as written (`printenv` prints dev/false).

## Still open

- **B3 (low):** The explained Challenge 2 still quotes `mapping values are not allowed in this context`. Helm 3.19 prints `did not find expected '-' indicator` (re-verified).
- **B4 (low):** The lab still says "inspect where `env` lands". A wrong indent gives a parse error, and the explained page breaks `resources` instead. Align them and mention `--debug`.
- **I1 (low):** "`spec:` (7 spaces or column 0)" typo in the explained page.
- **I2 (low):** Step 2 still anchors on `# Declares the image's default port...`, a comment Lab 0 never writes.
- **I3, S1–S5** as before.
