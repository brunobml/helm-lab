# Lab 11 review: Advanced templating and library charts

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The rebuild instructions for the library experiment (after `helm dependency update --skip-refresh` the `required` variant renders an empty `data:`, and restoring works), the `tpl` trust warning, and the `--dry-run=server` note for `lookup`. The lab works as written.

## Still open (minor)

- **I2:** `lab-common.labels` still includes the selector label `app: <release>`. Consider `lab-common.selectorLabels` + `lab-common.labels`.
- **S2:** Cleanup `cd - && rm -rf /tmp/tplplay` fails if the learner changed shells.
- **S3, S5–S7** as before.
