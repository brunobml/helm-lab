# Lab 12: Secrets, signing, and CI — Explained

[Back to Lab 12](12-secrets-signing-and-ci.md)

---

## Overview

You encrypted secrets so they can live in Git, unit-tested rendered output, signed and verified a chart, and
wired lint/install checks into CI.

---

### Question 1: What exactly does SOPS protect, and where does the plaintext still exist after a `helm install`?

#### TL;DR

SOPS protects the **file at rest in Git and on disk**. Once decrypted for Helm, the plaintext exists in several other places.

#### Deep Dive

1. **The encrypted file.** SOPS encrypts each value (here only under keys named `data`) with AES-256-GCM, using a data key that is itself encrypted
   to each age recipient. The `mac` protects the whole file from tampering. Structure stays readable, so diffs and reviews still work.
2. **During the deploy.** `helm secrets` writes a temporary `.dec` file, runs Helm, then deletes it. That is why `*.dec` is git-ignored.
3. **After the deploy**, the plaintext is in:
   - the release record (`sh.helm.release.v1.*` Secret): `helm get values` and `helm get manifest` print it;
   - the Kubernetes Secret (base64 is encoding, not encryption);
   - Pod environment variables (visible to anyone who can `exec`, and often leaked into crash dumps and logs).
4. **So the real controls are:** RBAC on Secrets and `pods/exec`, encryption at rest for etcd, mounting Secrets as files instead of environment variables for
   sensitive data, and keeping the age private key in as few places as possible (developers' laptops, or only CI).
5. **When SOPS is the wrong tool.** SOPS puts the ciphertext in Git, which is right for a small team and Helm/Argo pipelines. For many secrets, rotation, and audit,
   use an external secret manager with External Secrets Operator or the CSI driver, so the cluster pulls secrets and Git holds only a reference.

Also remember `lookup` (Lab 11) and GitOps: Argo CD renders with `helm template` and cannot run `helm secrets`. Argo needs a plugin (helm-secrets or KSOPS) or one of the external approaches above.

---

### Question 2: Why did the secret rotation need a `checksum/secret` annotation?

#### TL;DR

Pods read `envFrom` at start-up only. Changing a Secret does **not** restart Pods, so the annotation makes Helm change the Pod template, which triggers a rolling update.

#### Deep Dive

- Kubernetes populates environment variables from a Secret when the container starts. Updating the Secret later does not update running containers.
- The same trick from Lab 6 applies: put a hash of the rendered `secret.yaml` in the Pod template annotations. New data means a new hash, which means a new ReplicaSet.
- Mounted Secret **volumes** are refreshed by the kubelet eventually, but the application must re-read the files, so a checksum-driven restart is still common.
- The annotation is only rendered when `secret.create` is true, so releases that do not use the feature render identically to before. A refactor or feature that leaves default output
  unchanged is the safest kind.

---

### Question 3: What does `helm verify` prove that a version number does not, and what does it not prove?

#### TL;DR

It proves the archive is byte-for-byte what the holder of a **trusted key** signed. It says nothing about whether the chart is *safe*.

#### Deep Dive

| Claim | Version number | `helm verify` | `cosign verify` |
| --- | --- | --- | --- |
| Which release is this? | yes | yes | yes |
| Unchanged since it was signed (integrity) | no | yes (SHA-256 in the `.prov`) | yes (signature over the digest) |
| Signed by a key I trust (origin) | no | yes, if my keyring holds only keys I trust | yes, for the public key or identity I pass |
| Free of bugs or malicious templates | no | **no** | **no** |

1. `helm package --sign` records the archive's SHA-256, the chart metadata, and the file hashes in a `.prov` file, signed with OpenPGP.
2. Two failure modes you saw are different: a **tampered archive** fails the hash (`sha256 sum does not match`), while an **untrusted signer** fails the signature
   (`unknown entity`). Verification only means something if the verifier's keyring is small and curated.
3. Helm's provenance covers the chart archive. `cosign` signs the **OCI digest**, so the same signature works with container-image admission policies.
   Using both is common; use either consistently.
4. Signing proves *who published it*, not *what it does*. Still review chart changes, pin exact versions and digests, and pull third-party charts into your own registry after review.
5. In production, keys need protection: passphrases, hardware tokens or a KMS; and for cosign, keyless signing from CI so there is no long-lived key to steal. The lab's empty-passphrase keys and
   `--tlog-upload=false` are shortcuts for offline practice.

---

### Question 4: Why is `tests/` in `.helmignore` written with a leading `/`?

#### TL;DR

Without the slash, the pattern matches a directory called `tests` at **any depth**, including `templates/tests/`, and your `helm test` hook silently disappears from the package.

#### Deep Dive

- `.helmignore` follows gitignore-like rules: a pattern with no slash matches names at every level; a leading `/` anchors it to the chart root.
- The failure is silent. Helm applies `.helmignore` whenever it loads a chart, from a directory or an archive, so `helm lint` passes and `helm template` simply no longer contains the test Pod
  (`helm template d ./charts/nginx-demo | grep -c http-test` drops from 1 to 0). Nothing errors: the hook is just gone, and `helm test` finds nothing to run. A unit test or CI check that asserts the hook exists is the safety net.
- The same care applies to `/ci/`, `/secrets.*.yaml`, and `/.sops.yaml`. Keep a "verify package contents" step (`tar tzf`) in your release process.
- Habit: when adding an ignore rule, package the chart and diff the file list before and after.

---

### Question 5: Which problems does each kind of test catch?

| Check | Needs a cluster | Catches | Misses |
| --- | --- | --- | --- |
| `helm lint` / `ct lint` | no | Syntax, missing required files, schema, YAML style, version bump | Whether rendered output is *correct* |
| `helm unittest` | no | Wrong values in rendered manifests, conditional logic, `fail`/`required` messages, regressions after refactors | Whether Kubernetes accepts or runs them |
| `kubectl apply --dry-run=server` (Lab 10) | yes (API only) | Invalid fields and enum values, admission rejection | Runtime behavior |
| `ct install` (+ `helm test`) | yes | The chart really installs, Pods become Ready, the app answers | Edge cases in values you did not put in `ci/` |
| Your own review | n/a | Intent and design | Anything mechanical |

Notes from the lab:

- Unit tests must be **deterministic**: assert on values you set (`release.name`, `set`), not on things like hashes of unrelated files. The checksum test only asserts the annotation's *shape*.
- helm-unittest can only resolve templates listed in `templates:`, including ones another template `include`s (the checksum `include` of `secret.yaml`).
- `ct install` runs **each `ci/*-values.yaml`**. The scenario files are how you make CI cover optional features (Secret, HPA, Ingress).
- `ct` diffs against `origin/<target-branch>`. If `main` has unpushed commits or was never fetched, every chart looks changed.

---

## Common pitfalls

- Committing `keys.txt`, a `.dec` file, or the GnuPG directory. `.gitignore` is the last line of defense, not the first: keep private keys outside the repo.
- Running `helm install -f secrets.dev.yaml` without `helm secrets`: no error, and the ciphertext becomes the password.
- Encrypting to one key only. Add a second recipient (a teammate or CI) before you need to rotate or someone is unavailable.
- Treating `--tlog-upload=false`, `--insecure-ignore-tlog`, and `--allow-insecure-registry` as normal cosign usage.
- Forgetting to bump the chart `version` after a change: `ct lint` fails the PR, and consumers of a mutable version get inconsistent charts.
- Testing only the defaults. Every optional template (`secret.create`, `autoscaling.enabled`, `ingress.enabled`) needs a unit test and a `ci/` scenario.

---

## Break It and Recover — Detailed Walkthrough

Lab 12 tests five security and automation failure modes:

### Scenario 1: Plain `helm` on an Encrypted Secrets File

#### 1. What to Break

Run standard `helm template` or `helm install` passing an encrypted values file directly without the `helm-secrets` plugin:

```bash
helm template d ./charts/nginx-demo -f ./charts/nginx-demo/secrets.dev.yaml -s templates/secret.yaml | grep API_KEY
```

#### 2. The Error Observed

No error is raised! Instead, Helm renders:

```yaml
API_KEY: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]
```

#### 3. Why This Failed & Real-World Impact

- Helm treats values files as plain YAML dictionaries. Because SOPS preserves valid YAML structure, Helm reads the ciphertext strings without error.
- If deployed, Kubernetes creates a Secret containing the literal ciphertext `ENC[AES256_GCM,...]`.
- Your application attempts to connect to databases or APIs using the ciphertext as the password, resulting in silent authentication failures that are hard to diagnose.
- **Rule:** Always deploy encrypted values via `helm secrets install/upgrade` (or decrypt them in your CI pipeline prior to deployment).

#### 4. How to Recover

Use the `helm secrets` wrapper:

```bash
helm secrets template d ./charts/nginx-demo -f ./charts/nginx-demo/secrets.dev.yaml -s templates/secret.yaml | grep API_KEY
```

*Output:* `API_KEY: dev-api-key-12345`.

---

### Scenario 2: Packaging Without Secrets Ignore Rules

#### 1. What to Break

Remove `/secrets.*.yaml` and `/.sops.yaml` from `charts/nginx-demo/.helmignore`:

```bash
sed -i '/\/secrets\.\*\.yaml/d' charts/nginx-demo/.helmignore && sed -i '/\/\.sops\.yaml/d' charts/nginx-demo/.helmignore
helm package ./charts/nginx-demo -d $LAB_TMP/pk-test
tar tzf $LAB_TMP/pk-test/nginx-demo-*.tgz | grep -E "secrets\.|\.sops"
```

#### 2. The Error Observed

```text
nginx-demo/.sops.yaml
nginx-demo/secrets.dev.yaml
```

#### 3. Why This Failed

- By default, `helm package` bundles every file in the chart directory into the `.tgz` distribution archive unless excluded by `.helmignore`.
- Even though the secret data is encrypted, publishing your `.sops.yaml` (which reveals recipient public keys and path rules) and environment secrets in public or shared chart repositories leaks internal metadata and exposes encrypted payloads to offline cryptanalysis.

#### 4. How to Recover

Restore the ignore rules in `.helmignore`:

```text
/secrets.*.yaml
/.sops.yaml
```

Verify the packaged archive:

```bash
helm package ./charts/nginx-demo -d $LAB_TMP/pk-check
tar tzf $LAB_TMP/pk-check/nginx-demo-*.tgz | grep -E "secrets\.|\.sops"  # No output
```

---

### Scenario 3: A Bare `tests/` Entry in `.helmignore`

#### 1. What to Break

Change the anchored pattern `/tests/` to an unanchored pattern `tests/` in `.helmignore`:

```bash
sed -i 's/\/tests\//tests\//' charts/nginx-demo/.helmignore
```

#### 2. The Error Observed

Check `helm template`:

```bash
helm template d ./charts/nginx-demo | grep -c http-test
```

*Output:* `0` (was previously `1`).
`helm lint` still reports success: `1 chart(s) linted, 0 chart(s) failed`.
However, `helm unittest` immediately fails:

```text
FAIL  helm test hook  charts/nginx-demo/tests/helm_test_hook_test.yaml
      template "nginx-demo/templates/tests/http.yaml" not exists or not selected in test suite
```

#### 3. Why This Failed

- In `.helmignore` and `.gitignore`, an unanchored directory pattern like `tests/` matches any directory named `tests` at any depth in the chart hierarchy, including `templates/tests/`.
- Helm silently drops the `http.yaml` test hook pod during chart loading and packaging.
- `helm lint` does not require a test pod, so linting passes. Only unit tests or inspecting the package manifest reveals that the test hook vanished.

#### 4. How to Recover

Anchor the pattern with a leading slash `/tests/` to match only the top-level unit-test directory:

```bash
sed -i 's/^tests\//\/tests\//' charts/nginx-demo/.helmignore
helm template d ./charts/nginx-demo | grep -c http-test  # Returns 1
```

---

### Scenario 4: Catching Regressions with `helm-unittest`

#### 1. What to Break

Introduce an accidental naming regression in `_helpers.tpl` (e.g., renaming the deployment suffix from `"%s-deployment"` to `"%s-deploy"`):

```bash
sed -i 's/"%s-deployment"/"%s-deploy"/' charts/nginx-demo/templates/_helpers.tpl
helm unittest ./charts/nginx-demo
```

#### 2. The Error Observed

```text
FAIL  deployment  charts/nginx-demo/tests/deployment_test.yaml
      - names the Deployment and selector after the release
        Expected: shop-deployment
        Actual:   shop-deploy
```

#### 3. Why This Failed

- `charts/nginx-demo/tests/deployment_test.yaml` contains an assertion verifying that `metadata.name` equals `shop-deployment`.
- Helm unit tests run locally in milliseconds without spinning up pods or touching Kubernetes. They immediately detect naming drift before changes reach code review or cluster deployment.

#### 4. How to Recover

Revert the unintended change:

```bash
sed -i 's/"%s-deploy"/"%s-deployment"/' charts/nginx-demo/templates/_helpers.tpl
helm unittest ./charts/nginx-demo  # All 20 tests pass
```

---

### Scenario 5: Decrypting With the Wrong Key

#### 1. What to Break

Simulate an attacker or unauthorized CI runner attempting to decrypt the secrets file without access to the age private key:

```bash
XDG_CONFIG_HOME=$(mktemp -d) SOPS_AGE_KEY_FILE=/dev/null helm secrets decrypt charts/nginx-demo/secrets.dev.yaml
```

#### 2. The Error Observed

```text
Failed to get the data key required to decrypt the SOPS file.
Group 0: FAILED
  age1...: FAILED - failed to create reader for decrypting sops data key with age: no identity matched any of the recipients.
[helm-secrets] Error while decrypting file: charts/nginx-demo/secrets.dev.yaml
```

#### 3. Why This Failed

- SOPS requires an age private key matching the public key recipient specified in `.sops.yaml`.
- Setting `XDG_CONFIG_HOME=$(mktemp -d)` isolates SOPS from local fallback keys in `~/.config/sops/age/keys.txt`, and `SOPS_AGE_KEY_FILE=/dev/null` provides no valid identities.
- SOPS terminates with a non-zero exit code, ensuring that encrypted files cannot be decrypted without authorized credentials.

---

## Key Takeaways

| Concept | Key Point |
| :--- | :--- |
| `sops` + `age` | Encrypts secret values at rest in Git while keeping YAML structure and non-secret keys readable in PR diffs. |
| `helm-secrets` Plugin | Decrypts secrets on the fly to temporary memory/files during `helm install` / `upgrade` and automatically removes plaintext files upon completion. |
| Anchored `.helmignore` | A leading slash (e.g. `/tests/`, `/ci/`) anchors ignore rules to the chart root so nested subdirectories like `templates/tests/` are preserved. |
| Unit Tests vs Linting | `helm lint` validates syntax and schemas; `helm unittest` validates exact rendered YAML document structure in milliseconds without a cluster. |
| Provenance & Signing | `helm package --sign` generates `.prov` OpenPGP signatures over the archive hash; `cosign` signs the registry digest for OCI artifacts. |
| Chart-Testing (`ct`) | Enforces SemVer increments, runs `yamllint` / `helm lint`, and spins up clean cluster releases for all `ci/*-values.yaml` scenarios. |
