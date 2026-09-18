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
