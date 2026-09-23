# Lab 7 review: Validation and tests

**Full re-run (third pass):** 2026-09-23 — every step re-executed end to end on a fresh kind cluster (Kubernetes v1.35.0), from an empty workspace, with k3d spot checks (Traefik Ingress, HPA). The items below were reproduced again unless marked otherwise.

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** The schema, test hook, and NOTES all work. All three lints pass, invalid values are rejected, `helm test` succeeds, and the break-it test fails and then recovers as described. **Three documented outputs don't match Helm 3.19**, so learners will think something is wrong.

## Bugs

### B1: The lab's schema error messages use the old format (high)

Helm ≥ 3.18 switched JSON Schema libraries (to `santhosh-tekuri/jsonschema`), which changed the error wording.

| Lab says | Helm 3.19.0 prints |
| --- | --- |
| `- replicaCount: Must be greater than or equal to 0` | `- at '/replicaCount': minimum: got -1, want 0` |
| `- service.port: Must be less than or equal to 65535` | `- at '/service/port': maximum: got 70,000, want 65,535` |

The **explained page already has the new format**, so the two pages contradict each other. Update the lab (and optionally note that Helm < 3.18 prints the older style).

### B2: The documented `helm test` output format doesn't exist in Helm 3 (high)

The lab (Verify 3) and the explained page (break-it and recovery) show:

```text
RUNNING: demo-dev-http-test
PASSED:  demo-dev-http-test
```

Helm 3.19 actually prints the release status block followed by:

```text
TEST SUITE:     demo-dev-http-test
Last Started:   ...
Last Completed: ...
Phase:          Succeeded
NOTES: ...
POD LOGS: demo-dev-http-test
<h1>Hello from Updated Helm Lab</h1>
```

The failure case prints `Error: 1 error occurred: * pod demo-dev-http-test failed` (not `ERROR: ... pod failed with status "Failed"` / `Error: 1 test(s) failed`).
Also, the failing logs show `wget: bad address 'does-not-exist:80'` (with the port), not `'nonexistent-service'`.

### B3: The expected page content is stale (medium)

Verify 3 expects `<h1>Hello from Helm Lab</h1>`, but at the end of Lab 6 the dev page is `<h1>Hello from Updated Helm Lab</h1>` + `<p>I changed this page with helm upgrade.</p>` (both in the lab text and in the `lab-06-complete` tag). Update it to the Lab 6 final content, or say "your current `pageContent`".

## Accuracy issues

- **I1:** The schema's `$schema` is `https://json-schema.org/draft-07/schema#`. Draft-07's canonical ID is `http://json-schema.org/draft-07/schema#` (http). Helm doesn't fetch it, so this works, but the canonical form avoids confusion with validators that do check the URI.
- **I2:** Step 2's claim about `hook-succeeded` breaking `--logs` is **correct** (verified: `Error: unable to get pod logs for demo-dev-http-test: pods "demo-dev-http-test" not found`). Consider showing that exact error, since it makes the rationale concrete. A related gotcha I hit: switching the policy *from* `before-hook-creation` while an old test Pod still exists makes the next `helm test` fail with `pods "demo-dev-http-test" already exists`. Delete the old Pod first.
- **I3:** The test Pod labels are hand-written (4 `app.kubernetes.io/*` labels) instead of using a helper. That's intentional (no selector label), but it contradicts Lab 5's "write once" lesson. Suggest adding a small `nginx-demo.commonLabels` helper (without `app:`), or at least note why it's duplicated.

## Ease-of-following suggestions

- **S1:** Break it: give the exact edit (`http://does-not-exist:{{ .Values.service.port }}/`) and state that the **upgrade is necessary** because test hooks are stored in the release manifest. Editing the file and rerunning `helm test` alone runs the *old* test. This is a great insight to make explicit.
- **S2:** Verify 2: add a type error case, which is instructive:
  `--set replicaCount=1.5` → `at '/replicaCount': got string, want integer`. `--set` does not parse floats, so the value arrives as a string, and the message surprises most people.
- **S3:** Explain Q3 (`replicaCount: 0`): suggest actually running it (`helm upgrade ... --set replicaCount=0`, then `helm test`) to see the test fail while the schema passes, then restore.
- **S4:** Cleanup: "Remove any retained failed test Pod after inspection". Give the command: `kubectl delete pod demo-dev-http-test -n helm-lab`. A successful rerun also replaces it thanks to `before-hook-creation`.
- **S5:** The test image reuses `nginx:1.30.4-alpine` for `wget`. That's clever (no extra pull), but Lab 16 switches to `nginxinc/nginx-unprivileged`, where BusyBox `wget` is still present. Worth a one-line comment explaining the choice.
