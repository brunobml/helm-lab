# Lab 16 review: Production hardening and chart best practices

**Tested with:** Helm v3.19.0, `nginxinc/nginx-unprivileged:1.27-alpine`, `jnorwood/helm-docs:latest`, `ghcr.io/yannh/kubeconform:latest`, kind (Kubernetes v1.35.0, kindnet enforces NetworkPolicy), 2026-09-23
**Result:** **A learner who follows the lab text literally fails at Step 9**: the Pods are forbidden by PodSecurity `restricted`. Once the missing template changes (taken from `lab-16-complete`) were added, everything else worked:

- The hardened install passes (2 Pods, PDB, NetworkPolicy, `helm test` Succeeded).
- The break-it produces the `would violate PodSecurity "restricted:latest"` warning, `context deadline exceeded`, and `FailedCreate` events while the old Pods keep running. The rollback recovers.
- kubeconform: `Valid: 9`.
- `demo-dev` upgraded onto the hardened chart runs as `uid=101(nginx)`.

## Bugs

### B1: The lab never renders the security contexts, so Step 9 fails (critical)

Steps 1–2 add `podSecurityContext` and `securityContext` to **values.yaml** only. No step adds them to `templates/deployment.yaml`. The tag contains these changes, but the lab text doesn't:

```gotemplate
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      ...
          {{- with .Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

Result of following the text exactly (verified):

```text
Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false (container "nginx" ...
Error: INSTALLATION FAILED: context deadline exceeded
deployment.apps/hardened-demo-deployment   0/2
FailedCreate ... pods "hardened-demo-deployment-..." is forbidden: violates PodSecurity "restricted:latest"
```

Without `--timeout`, the command hangs for the default **5 minutes** first. Add a Step 2b with the template snippet above.

### B2: `containerPort` is never updated to 8080 (medium)

Step 1 switches to the unprivileged image on port 8080 and sets `service.targetPort: 8080`, but the Deployment still declares `containerPort: 80` (hard-coded since Lab 0). Traffic still works because Services route by number, but the manifest lies about the listening port, and the named-port/NetworkPolicy lessons get confusing. The tag changes it to `{{ .Values.service.targetPort | default 80 }}`, and the lab should show that.

### B3: Lab 16 breaks the Lab 13 `shop` chart, including on `main` (high)

The checkpoint bumps `nginx-demo` to **0.6.0**, but `charts/shop/Chart.yaml` pins `nginx-demo` **`version: 0.5.0`** from `file://../nginx-demo`. After Lab 16:

```text
$ helm dependency build charts/shop
Error: can't get a valid version for dependency nginx-demo
```

I verified this on a **fresh worktree of `main`**: `helm dependency build charts/shop` fails, so `helm template charts/shop` fails, and `ct lint --all` (Lab 12/13's CI) would too. **The finished repository's capstone chart can't be built from a clean clone.**
**Fix:** In the chart, use a range (`version: ">=0.5.0 <1.0.0"` or `~0.6.0`) and bump `shop` in Lab 16. Also add a Lab 16 step: "update `charts/shop/Chart.yaml` and run `helm dependency update charts/shop`". It's a great real-world lesson about coupled version pins.

### B4: helm-docs creates a root-owned file and blank descriptions (medium)

- `docker run --rm -v ...:/helm-docs jnorwood/helm-docs:latest` runs as root, so `charts/nginx-demo/README.md` ends up **owned by `root`** in the learner's repo (verified on Docker Desktop/WSL2). Add `--user "$(id -u):$(id -g)"`.
- The lab says "Notice that all descriptions, types, and defaults are automatically cataloged", but **every Description cell is empty**, because no step tells learners to add `# --` comments to `values.yaml`. Add a step with a few `# -- ...` examples (the tag's `values.yaml` has them).
- `:latest` for both images conflicts with the lab's own pinning message. Pin, for example `jnorwood/helm-docs:v1.14.2`.

## Accuracy issues

- **I1: The NetworkPolicy isn't "micro-segmentation".** The ingress rule has two peers, `podSelector: {}` **or** `namespaceSelector: {}`, and the second matches **every namespace**. Verified: a Pod in `default` fetched the page from `hardened-lab`. Egress *is* restricted to DNS (verified: other traffic times out). Either scope ingress (`namespaceSelector` with a `kubernetes.io/metadata.name` match, or `podSelector` only) or rename the section.
- **I2: The NetworkPolicy and PDB selectors also match the migration Job Pod**, which carries `app: <release>` (Lab 10 review B1). The PDB counts it in `minAvailable`, and the NetworkPolicy applies DNS-only egress to it. That's harmless for this busybox Job, but a real migration needs database egress and would silently hang.
- **I3:** Step 1 changes the image to **1.27** while `Chart.yaml` keeps `appVersion: "1.30.4"` (a *downgrade* from the Lab 0 `1.30.4-alpine`). The labels now report the wrong app version. Use an unprivileged tag that matches (`nginxinc/nginx-unprivileged:1.30-alpine` exists, verified) or update `appVersion`.
- **I4:** Step 3 says NGINX needs `/var/run` writable. `nginx-unprivileged` writes its PID to `/tmp/nginx.pid` (verified in `/etc/nginx/nginx.conf`), so `/var/run` isn't needed for this image. It's harmless, but the explanation should match the image.
- **I5:** Step 4 uses `runAsUser: 1000` for the test Pod, while the tag uses `101` (the image's own user). Both pass, but pick one.
- **I6:** Step 6 shows the `topologySpreadConstraints` snippet without saying where it goes (it belongs under `spec.template.spec`, next to `securityContext`).
- **I7:** Step 9 again says "(`2/2`)" for two Pods that are each `1/1`.
- **I8:** kubeconform validates against Kubernetes **1.30.0** while the lab cluster is 1.35. Suggest `-kubernetes-version "$(kubectl version -o json | jq -r .serverVersion.gitVersion | tr -d v)"`, or at least a matching minor.

## Structure

- **S1:** There's no Explain section and no link to `16-production-hardening-and-best-practices-explained.md` (same as Lab 15).
- **S2:** The checkpoint says "run unit tests", but the lab gives none for the new features. `lab-16-complete` contains `tests/hardening_test.yaml` (122 lines), which never appears in the lab. Include it or a short version.
- **S3:** Consider having learners upgrade **`demo-dev`** onto the hardened chart (I verified it works: `uid=101(nginx)`, `helm test` Succeeded). Changing the image and port of a running release is the realistic production step, and it exercises probes on 8080.
