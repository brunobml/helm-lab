# Lab 0 review: Chart creation

**Tested with:** Helm v3.19.0, kind v1.35.0 (no cluster needed for this lab), 2026-09-22
**Result:** All steps work. The "Break it and recover" step does **not** produce the documented error.

## Bugs

### B1: "Break it" produces a different error than documented (high)

The lab and the explained page say `version: 1` produces:

```text
[ERROR] Chart.yaml: version "1" is not a valid SemVer
```

What actually happens with Helm 3.19.0:

| Value in `Chart.yaml` | Actual `helm lint` result |
| --- | --- |
| `version: 1` (unquoted) | `[ERROR] Chart.yaml: version should be of type string but it's of type float64` |
| `version: "1"` (quoted) | **Passes.** Masterminds semver coerces `1` to `1.0.0` |
| `version: "1.0"`, `version: v0.1` | **Passes** (coerced) |
| `version: latest` | `[ERROR] Chart.yaml: version 'latest' is not a valid SemVer` (plus `unable to load chart`) |
| `version: 1.0.0.1` | `[ERROR] Chart.yaml: version '1.0.0.1' is not a valid SemVer` |

So the explanation in `00-chart-creation-explained.md` ("A single integer `1` lacks the minor and patch segments... triggering an immediate linter failure") is factually wrong. Helm accepts partial versions, and the unquoted failure is a YAML type problem, not a SemVer problem.

**Fix:** Use `version: latest` for the break step and update the expected output. Optionally keep `version: 1` as a second exercise about YAML typing, which pairs well with the `appVersion` quoting lesson.
Also correct the Golden Rule table ("Must follow SemVer (`x.y.z`)"): Helm requires *parseable* SemVer, and coerces `1` and `1.0`.

### B2: `helm create` silently overwrites an existing chart (medium)

`README.md` says "The working chart starts with a Deployment and Service", but `main` contains the **finished** chart (0.6.0, with subcharts, schema, and tests).
A learner on `main` who runs Step 1 (`helm create charts/nginx-demo`) gets `WARNING: File ... already exists. Overwriting.`. The result mixes generated files with the old ones (`configmap.yaml`, `migration-job.yaml`, and so on). Step 3's `rm -rf templates/*` hides part of this, but the stale `ci/`, `tests/`, `values.schema.json`, `Chart.lock`, and `charts/*.tgz` remain. The next `helm lint` then fails or behaves strangely.

**Fix:** Make the **Start** line concrete, for example:

```bash
git switch --orphan my-lab-00   # or: git worktree add ../helm-lab-practice lab-00-start
# or on a practice branch from main:
git rm -r --quiet charts/nginx-demo && rm -rf charts/nginx-demo
```

Also fix the README sentence "The working chart starts with a Deployment and Service". It is true only at the `lab-00-start` tag.

## Accuracy issues

- **I1:** The Step 2 file list omits `templates/httproute.yaml`. Helm ≥ 3.17 generates it (Gateway API HTTPRoute). Add it to the list.
- **I2:** `helm lint` on the finished Lab 0 chart prints `[INFO] Chart.yaml: icon is recommended`. The Verify section only shows `1 chart(s) linted, 0 chart(s) failed`, so mention the INFO line so learners don't think something is wrong.
- **I3:** The `lab-00-start` tag differs from what the lab tells you to write:
  - The tag's `Chart.yaml` keeps all the `helm create` comments, while the lab says "Replace ... with clean, minimal metadata".
  - The tag's `values.yaml` and `deployment.yaml` contain explanatory comments the lab does not (`# Explicit application version...`, `# targetPort must match NGINX's listening port...`). These comments are helpful, so consider adding them to the lab snippets.
  - The tag contains `charts/nginx-demo/README.md`, which the lab never asks you to create.

  Result: `git diff lab-00-start` (Approach 1 in the README) shows noise even for a learner who followed the lab exactly.
- **I4:** The Step 3 note says "Keep `.helmignore` and the `charts/` folder intact", but git doesn't track empty directories, so `charts/` disappears after the commit/checkout round trip. That's harmless, but worth a one-line note.

## Ease-of-following suggestions

- **S1:** In Step 3, show the expected state after deletion (`ls -A charts/nginx-demo/templates` prints nothing) so learners can confirm it.
- **S2:** Explain that `helm create` generates `nginx` as the default image with `appVersion` as the tag. That motivates why the lab replaces `values.yaml`.
- **S3:** The Verify section could add `helm template demo-dev ./charts/nginx-demo | grep -E '^kind|name:'` for a quick visual check instead of reading the whole output.
- **S4:** In the Explain section, the answer to Question 2 says `.helmignore` applies when "rendering templates". It actually applies when Helm *loads* a chart directory (install, template, lint, and package all use the loader), so the wording is roughly right but could be clearer.
