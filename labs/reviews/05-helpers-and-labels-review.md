# Lab 5 review: Helpers and labels

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** The lab now links its explained page, and the new server-side dry-run step prints `field is immutable` as documented.

## Still open

- **B1 (medium):** The explained page still answers 3 **different** questions (separate helpers, prefixing, renaming) than the lab's 4 "Check your understanding" questions. It also still references a "What the challenge asks" block that isn't in the lab.
- **B2 (low):** The explained page shows `helm.sh/chart: nginx-demo-0.1.0` in the labels helper. The lab never adds it.
- **I2 (low):** "Mark Lab 5 complete in the README" is inconsistent with the other labs.
- **B3, I1, S2–S5** as before.
