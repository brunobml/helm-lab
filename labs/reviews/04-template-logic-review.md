# Lab 4 review: Template logic

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** Steps and Verify work exactly as written: the default render has no `env` or `resources`, the dev render has both, and `printenv` prints `dev` / `false`. My template matches `lab-04-complete`. Several error messages on the explained page don't match reality, and one example contradicts its own point.

## Bugs

### B1: The explained Q3 "without trimming" example contradicts the lesson (medium)

The page says every tag "leaves behind an invisible blank newline" if not trimmed. Then it shows the untrimmed template rendering as clean YAML **with no blank lines**:

```yaml
spec:
  replicas: 1
```

Without `{{-`, the actual output has blank (whitespace-only) lines where `{{ if }}` and `{{ end }}` were. Show that output, then the trimmed version.

### B2: The explained page quotes the wrong error for unquoted env values (medium)

It claims the API server returns:

```text
spec.template.spec.containers[0].env[0].value: Invalid value: "boolean": expected string, got boolean
```

Tested by removing `| quote` and upgrading with `--set extraEnv.PORT=8080`. Helm 3.19 returns a very long `cannot patch "demo-dev-deployment" ... patch: Invalid value: "{...entire object JSON...}"` that ends with:

```text
json: cannot unmarshal bool into Go struct field EnvVar.spec.template.spec.containers.env.value of type string
```

It also leaves a **`failed` revision** in `helm history`, with that giant message as the DESCRIPTION.
Show the real tail of the message and tell learners to read the *end* of the error. That's a valuable real-world debugging tip.

Also note that `helm template` does **not** catch this: it renders `value: false` without complaint. That's a good addition to "Does a successful render imply a successful rollout?" from Lab 2.

### B3: The explained Challenge 2 error message is wrong (low)

With `nindent 8`, Helm 3.19 prints:

```text
Error: YAML parse error on nginx-demo/templates/deployment.yaml: error converting YAML to JSON: yaml: line 28: did not find expected '-' indicator
```

The page shows `mapping values are not allowed in this context`. Update it. The line number also depends on whether the learner has the extra comment lines from the tags (see Lab 0 review I3), so say "line N".

### B4: The lab and the explained page describe different indentation exercises (low)

The lab says "try a wrong indentation level and **inspect where `env` lands**". The explained page breaks **`resources`** with `nindent 8`.
Also, for either block, a wrong indent usually doesn't make it "land" somewhere: it produces a **parse error**, so there's nothing to inspect unless the learner uses `helm template --debug` (which prints the invalid YAML).

**Fix:** Align both pages on one exercise, and mention `--debug`. A more instructive variant that renders *valid* YAML in the wrong place is `nindent 10` on `resources`: `requests`/`limits` become siblings of `resources:`, `helm template` succeeds, and the API server rejects the unknown fields.

## Accuracy issues

- **I1:** Explained Challenge 2 recovery: "`spec:` (7 spaces or column 0)" is a typo. It should be column 0.
- **I2:** Lab Step 2 anchors the insertion on a comment line (`# Declares the image's default port...`) that Lab 0 never tells learners to write. It only exists in the `lab-00-start` tag. Learners who followed Lab 0 won't find that anchor. Either add the comments to Lab 0 or anchor on `- containerPort: 80`.
- **I3:** The Q2 recommendation "pipe through `quote` or `toString | quote`" is fine, but note a real gotcha (verified): a large integer in a **values file** (`BIG: 12345678`) renders as `value: "1.2345678e+07"`, because YAML numbers are decoded as float64. `--set extraEnv.BIG=12345678` renders correctly (`"12345678"`) in Helm 3.19. The fix is to quote the value in the values file. This fits naturally next to Q2.

## Ease-of-following suggestions

- **S1:** Step 1 says "add ... to the bottom of the file". A heredoc (`cat >> charts/nginx-demo/values.yaml <<'EOF'`) makes this copy-pasteable, and the same goes for Step 3.
- **S2:** Verify 2 says "neither `env:` nor `resources:`". Give a command: `helm template demo-dev ./charts/nginx-demo | grep -cE 'env:|resources:'` should print `0`.
- **S3:** Verify 4: `kubectl exec deployment/...` can run briefly against a terminating old Pod right after the upgrade. `--wait` makes this unlikely, but `kubectl rollout status` first is safer.
- **S4:** Break it, `.Release.Name` inside `range`: say that the error shows `interface {}` (the map value's type), so learners recognize this message in the future.
- **S5:** Point out that `range` over a map iterates in **sorted key order** (`FEATURE_ENABLED` before `LAB_NAME`). That's why the output order differs from `values-dev.yaml`, and why it gives stable diffs.
