# Lab 10 review: Hooks, failure recovery, and debugging

**Fourth pass:** 2026-09-23 against `cafc1b2`. Cleaned up first. Then every step was re-executed on a fresh kind cluster (Kubernetes v1.35.0, Helm v3.19.0) from an empty workspace, with code taken verbatim from the lab text, plus k3d spot checks. Items fixed in earlier passes are not repeated. The previous report version is in git history (`git log -p -- labs/reviews/`).

**Verified fixed:** Step 2a now defines `nginx-demo.hookLabels`, so the lab passes as written. During an upgrade the migration Job Pod was **not** in the Service endpoints. Parts B, C, and D5 and Verify all reproduce.

## Still open

- **B3 (low):** D3 still says the diff shows replicas "and nothing else". It also shows the hook Job (`.Release.Revision` in the echo), re-verified.
- **Tag semantics (medium, new):** `lab-10-complete` now points at the **same commit as `main`/`lab-18-complete`** (`cafc1b2`). The README's "Approach 2" ("To start Lab 11, check out `lab-10-complete`") now hands learners the fully finished repository, and `git diff lab-10-complete` compares against the final chart. The same applies to `lab-15/16/17-complete`. Re-tag each at its end-of-lab state (for example on a rebuilt history), or update the README to stop using those tags as start points.
- **I1–I3, S1–S5** as before.
