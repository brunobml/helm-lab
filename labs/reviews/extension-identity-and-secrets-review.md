# Extension review: Identity and secrets

**Tested with:** Helm v3.19.0, kind (Kubernetes v1.35.0), 2026-09-22
**Result:** Everything works:

- All four `serviceAccount.create`/`name` combinations render correctly (`d-sa`, `custom`, `default`, `custom`).
- `printenv LAB_TOKEN` prints `fake-training-value`.
- `kubectl auth can-i` gives `yes` for `configmap/demo-dev-page` and `no` for `configmap/demo-dev-banner`.
- A missing Secret produces `CreateContainerConfigError` while the old Pod keeps serving.

This is the most solid of the four extensions. Most findings are about missing guidance.

## Missing instructions

- **M1: No hint for the Deployment changes.** The lab gives hints for the helper, `serviceaccount.yaml`, and `rbac.yaml`, but not for the two Deployment edits the checkpoint contains:

  ```yaml
      spec:
        serviceAccountName: {{ include "nginx-demo.serviceAccountName" . }}
        containers:
          - name: nginx
            ...
            {{- if .Values.existingSecret }}
            envFrom:
              - secretRef:
                  name: {{ .Values.existingSecret }}
            {{- end }}
  ```

  or the values block (`serviceAccount.create/name/annotations`, `rbac.create`, `existingSecret`). Add a third hint.
- **M2:** Verify: "Render all create/false combinations" has no command. Suggest a loop:

  ```bash
  for c in true false; do for n in "" custom; do
    echo "create=$c name=$n"; helm template demo-dev ./charts/nginx-demo --set serviceAccount.create=$c --set serviceAccount.name=$n \
      | grep -E 'kind: ServiceAccount|serviceAccountName'
  done; done
  ```

- **M3:** Verify: "Deploy the fake Secret reference" has no command. It should include `--set rbac.create=true --set existingSecret=demo-learning` **with** `--reset-values -f ./charts/nginx-demo/values-dev.yaml`.

## Accuracy issues

- **I1:** The explained break-it uses `helm upgrade demo-dev ... --set existingSecret=nonexistent-secret --wait=false` without the dev values file, which drops dev settings (see the networking review B2).
- **I2:** Explained Q2: "Standard Kubernetes users have permissions to create namespaced Roles". They can only create Roles granting permissions they already hold (RBAC escalation prevention). Worth adding, because it explains why Helm installs of RBAC-bearing charts fail for non-admins.
- **I3:** With the default `serviceAccount.create: true`, simply upgrading `demo-dev` after this extension changes `serviceAccountName` from `default` to `demo-dev-sa`, which triggers a rollout. It's expected, but mention it so learners understand why Pods restarted "for no reason".

## Ease-of-following / best-practice suggestions

- **S1:** Add `automountServiceAccountToken: false` (on the ServiceAccount or Pod spec) with a note. NGINX never talks to the API, so mounting a token is unnecessary attack surface. It's also an easy link to Lab 16's hardening.
- **S2:** `rbac.yaml` hard-codes `printf "%s-page" .Release.Name`, a third copy of that name (see the Lab 6 review S4). Use a helper.
- **S3:** `envFrom` exposes **all** Secret keys as env vars. Mention the `valueFrom.secretKeyRef` alternative and the general advice that mounted files beat env vars for secrets (env vars leak into crash dumps, `kubectl describe`-style tooling, and child processes).
- **S4:** Break it: with a rolling update the old Pod keeps serving (as with the health extension). Point out that this is why `--wait` fails without an outage, and link back to Lab 2.
- **S5:** Cleanup order ("Remove the Secret reference via upgrade before deleting `demo-learning`") is correct and important. Explain *why*: a later Pod restart would otherwise hit `CreateContainerConfigError`.
