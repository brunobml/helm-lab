# Lab 12: Secrets, signing, and CI

**Start:** Lab 11 complete (`lab-11-complete`). Use the `helm-lab` namespace and Docker (for the local registry from Lab 9).
**Goal:** Keep secrets out of Git, prove a chart is unmodified, and have machines test every change.

Four parts, each usable on its own:

| Part | Topic | Tools |
| --- | --- | --- |
| A | Encrypted secrets in Git | `sops`, `age`, `helm-secrets` |
| B | Chart unit tests | `helm-unittest` |
| C | Signing and verification | `gpg`, `helm verify`, `cosign` |
| D | CI | `ct` (chart-testing), GitHub Actions |

## Prerequisites: install the tools

Plugins (work on every platform):

```bash
helm plugin install https://github.com/helm-unittest/helm-unittest
helm plugin install https://github.com/jkroepke/helm-secrets
```

Binaries. On macOS: `brew install sops age cosign chart-testing yamllint`. On Linux (amd64),
install into `~/.local/bin` (make sure it is on your `PATH`):

```bash
mkdir -p ~/.local/bin && cd ~/.local/bin
curl -fsSL -o sops   https://github.com/getsops/sops/releases/download/v3.13.3/sops-v3.13.3.linux.amd64
curl -fsSL -o cosign https://github.com/sigstore/cosign/releases/download/v3.1.3/cosign-linux-amd64
chmod +x sops cosign
curl -fsSL https://github.com/FiloSottile/age/releases/download/v1.3.2/age-v1.3.2-linux-amd64.tar.gz | tar xz --strip-components=1 age/age age/age-keygen
curl -fsSL https://github.com/helm/chart-testing/releases/download/v3.14.0/chart-testing_3.14.0_linux_amd64.tar.gz | tar xz ct
pip install --user --break-system-packages yamllint yamale
cd - >/dev/null
sops --version; age --version; cosign version | grep GitVersion; ct version | head -1
```

Also `gpg` (usually preinstalled) for Part C. Newer versions of these tools should work;
the ones above are what this lab was verified with.

---

## Part A: Encrypted secrets in Git

Lab 10 and the Identity extension referenced a Secret by name (`existingSecret`), leaving open how it
gets into the cluster. Here the chart can create one from values, and those values live in Git
**encrypted**.

### Step 1: Make the chart able to create a Secret

Add a helper at the end of `charts/nginx-demo/templates/_helpers.tpl`:

```yaml
{{/*
Secret name used for envFrom: an existing Secret, or the one this chart creates.
*/}}
{{- define "nginx-demo.envSecretName" -}}
{{- if and .Values.existingSecret .Values.secret.create -}}
  {{- fail "set either existingSecret or secret.create, not both" -}}
{{- else if .Values.existingSecret -}}
  {{- .Values.existingSecret -}}
{{- else if .Values.secret.create -}}
  {{- printf "%s-secret" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
```

Create `charts/nginx-demo/templates/secret.yaml`:

```yaml
{{- if .Values.secret.create }}
{{- if not .Values.secret.data }}
{{- fail "secret.create is true but secret.data is empty" }}
{{- end }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "nginx-demo.envSecretName" . }}
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
type: Opaque
stringData:
  {{- toYaml .Values.secret.data | nindent 2 }}
{{- end }}
```

In `charts/nginx-demo/templates/deployment.yaml`, add a second checksum below `checksum/config`
so Pods restart when the Secret changes:

```yaml
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
        {{- if .Values.secret.create }}
        checksum/secret: {{ include (print $.Template.BasePath "/secret.yaml") . | sha256sum }}
        {{- end }}
```

and replace the `existingSecret` block under the container with:

```yaml
          {{- with (include "nginx-demo.envSecretName" .) }}
          envFrom:
            - secretRef:
                name: {{ . }}
          {{- end }}
```

Append to `charts/nginx-demo/values.yaml`:

```yaml
# Secret created by this chart. Supply secret.data from an encrypted values file
# (Lab 12); never commit plaintext secret values. Mutually exclusive with existingSecret.
secret:
  create: false
  data: {}
```

Add to the top-level `properties` in `charts/nginx-demo/values.schema.json`. Notice the comma `,` added after `"migration": { ... }`:

```json
    "migration": {
      "type": "object",
      "properties": {
        "enabled": { "type": "boolean" },
        "image": { "type": "string", "minLength": 1 },
        "fail": { "type": "boolean" }
      }
    },
    "secret": {
      "type": "object",
      "properties": {
        "create": { "type": "boolean" },
        "data": { "type": "object" }
      }
    }
```

Bump `version` in `charts/nginx-demo/Chart.yaml` to `0.5.0`. Make sure nothing changed by default:

```bash
helm lint ./charts/nginx-demo
helm template d ./charts/nginx-demo --set secret.create=true --set secret.data.API_KEY=abc \
  -s templates/secret.yaml -s templates/deployment.yaml | grep -E "kind:|API_KEY|secretRef|checksum/secret"
```

### Step 2: Keep encrypted files out of the package

Before creating any secrets file, protect the chart archive. Append to `charts/nginx-demo/.helmignore`:

```text
/secrets.*.yaml
/.sops.yaml
```

> [!IMPORTANT]
> Without these lines, `helm package` bundles `secrets.dev.yaml` and `.sops.yaml` into the archive you
> publish. Even encrypted, secrets files do not belong in a distributed artifact. You will prove this in
> the break-it section.

Also make sure decrypted temporary files and private keys can never be committed. Append to the
repository `.gitignore`:

```text
# Decrypted secrets and private keys must never be committed
*.dec
*.dec.yaml
age-keys.txt
keys.txt
```

### Step 3: Create an age key

`age` is a small public-key encryption tool. `sops` encrypts *to* your public key and needs the
private key to decrypt. The private key stays on your machine, **outside the repository**.

```bash
mkdir -p ~/.config/sops/age
test -f ~/.config/sops/age/keys.txt || age-keygen -o ~/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
grep "public key" "$SOPS_AGE_KEY_FILE"
```

> [!WARNING]
> Back up `keys.txt` (a password manager works). If you lose it, files encrypted to it cannot be recovered.
> In a team, encrypt to several recipients (`age: key1,key2` in `.sops.yaml`) and to a CI key.

### Step 4: Tell sops what to encrypt

`charts/nginx-demo/.sops.yaml` (use your own public key from the previous step):

```bash
PUB=$(grep "public key" "$SOPS_AGE_KEY_FILE" | awk '{print $NF}')
cat > charts/nginx-demo/.sops.yaml <<YAML
creation_rules:
  - path_regex: secrets\..*\.yaml\$
    encrypted_regex: ^(data)\$
    age: $PUB
YAML
cat charts/nginx-demo/.sops.yaml
```

`path_regex` selects which files the rule applies to. `encrypted_regex: ^(data)$` encrypts only the
values under keys named `data`, so `secret.create: true` stays readable in diffs.

### Step 5: Write and encrypt a secrets file

```bash
cat > charts/nginx-demo/secrets.dev.yaml <<'YAML'
secret:
  create: true
  data:
    API_KEY: dev-api-key-12345
    DB_PASSWORD: s3cr3t-p4ssw0rd
YAML
cd charts/nginx-demo && sops --encrypt --in-place secrets.dev.yaml && cd ../..
cat charts/nginx-demo/secrets.dev.yaml
```

*Expect:* `create: true` is readable; `API_KEY` and `DB_PASSWORD` are `ENC[AES256_GCM,data:...]`; there is a
`sops:` block with your `age` recipient. **This file is safe to commit.** The plaintext no longer exists anywhere.

### Step 6: Deploy with `helm secrets`

`helm secrets` decrypts files on the fly (to a temporary `.dec` file, deleted afterwards) and passes them to Helm.

```bash
helm secrets template d ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml \
  -f ./charts/nginx-demo/secrets.dev.yaml -s templates/secret.yaml

helm secrets install demo-secret ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml -f ./charts/nginx-demo/secrets.dev.yaml \
  --wait --timeout 120s
kubectl exec deploy/demo-secret-deployment -n helm-lab -- printenv API_KEY DB_PASSWORD
```

*Expect:* the plaintext values inside the Pod: `dev-api-key-12345` and `s3cr3t-p4ssw0rd`.

### Step 7: Rotate a secret

```bash
cd charts/nginx-demo && sops --set '["secret"]["data"]["API_KEY"] "rotated-key-999"' secrets.dev.yaml && cd ../..
kubectl get pods -n helm-lab -l app=demo-secret -o name
helm secrets upgrade demo-secret ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml -f ./charts/nginx-demo/secrets.dev.yaml --wait --timeout 120s
kubectl get pods -n helm-lab -l app=demo-secret -o name
kubectl exec deploy/demo-secret-deployment -n helm-lab -- printenv API_KEY
```

*Expect:* a **new** Pod name (the `checksum/secret` annotation changed) and `rotated-key-999`. Without that annotation,
Pods would keep the old environment variables until something else restarted them.

### Step 8: Where does the plaintext still live?

```bash
helm get values demo-secret -n helm-lab | grep -E "API_KEY|DB_PASSWORD"
helm get manifest demo-secret -n helm-lab | grep API_KEY
kubectl get secret demo-secret-secret -n helm-lab -o jsonpath='{.data.API_KEY}' | base64 -d; echo
```

*Expect:* all three show plaintext. Encryption protects the secret **in Git**. Helm stores release values and
manifests in a Secret in the cluster (`sh.helm.release.v1.*`), and Kubernetes Secrets are only base64-encoded.
Restrict who can read Secrets in the namespace (RBAC), and enable encryption at rest on the cluster.

---

## Part B: Unit tests with helm-unittest

`helm lint` checks syntax; `helm test` checks a running release. Unit tests check what a chart **renders** for
given values, in milliseconds and without a cluster.

Tests live in `charts/nginx-demo/tests/` (not `templates/tests/`, which holds the `helm test` hook Pod).
Each file is a *suite*; each `it:` is a test.

### Step 9: Keep the tests out of the package, carefully

Append to `charts/nginx-demo/.helmignore`:

```text
/tests/
/ci/
```

> [!IMPORTANT]
> The leading `/` matters. A bare `tests/` matches a directory named `tests` at **any depth**, including
> `templates/tests/`, and would silently drop your Lab 7 `helm test` hook, from renders, installs and packages alike.
> Check with `helm template d ./charts/nginx-demo | grep -c http-test` (expect `1`) and
> `helm package ./charts/nginx-demo -d /tmp/pk && tar tzf /tmp/pk/nginx-demo-*.tgz | grep templates/tests`.

### Step 10: Write the first suites

`charts/nginx-demo/tests/secret_test.yaml`:

```yaml
suite: secret
templates:
  - templates/secret.yaml
tests:
  - it: renders nothing by default
    asserts:
      - hasDocuments:
          count: 0

  - it: creates a Secret from secret.data
    release:
      name: shop
    set:
      secret.create: true
      secret.data:
        API_KEY: abc
    asserts:
      - isKind:
          of: Secret
      - equal:
          path: metadata.name
          value: shop-secret
      - equal:
          path: stringData.API_KEY
          value: abc

  - it: fails when create is true but data is empty
    set:
      secret.create: true
    asserts:
      - failedTemplate:
          errorPattern: secret.create is true but secret.data is empty

  - it: fails when both existingSecret and secret.create are set
    set:
      existingSecret: my-secret
      secret.create: true
      secret.data.API_KEY: abc
    asserts:
      - failedTemplate:
          errorPattern: set either existingSecret or secret.create, not both
```

`charts/nginx-demo/tests/deployment_test.yaml`:

```yaml
suite: deployment
templates:
  - templates/deployment.yaml
  - templates/configmap.yaml
  - templates/secret.yaml
tests:
  - it: uses the replica count from values
    template: templates/deployment.yaml
    set:
      replicaCount: 4
    asserts:
      - equal:
          path: spec.replicas
          value: 4

  - it: omits replicas when autoscaling is enabled
    template: templates/deployment.yaml
    set:
      autoscaling.enabled: true
    asserts:
      - notExists:
          path: spec.replicas

  - it: builds the image from repository and tag
    template: templates/deployment.yaml
    set:
      image.repository: myrepo/web
      image.tag: "9.9"
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: myrepo/web:9.9

  - it: names the Deployment and selector after the release
    template: templates/deployment.yaml
    release:
      name: shop
    asserts:
      - equal:
          path: metadata.name
          value: shop-deployment
      - equal:
          path: spec.selector.matchLabels.app
          value: shop

  - it: has a config checksum annotation
    template: templates/deployment.yaml
    asserts:
      - matchRegex:
          path: spec.template.metadata.annotations["checksum/config"]
          pattern: "^[a-f0-9]{64}$"

  - it: renders extra env vars from a map
    template: templates/deployment.yaml
    set:
      extraEnv:
        LAB_NAME: dev
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: LAB_NAME
            value: dev

  - it: does not reference a Secret by default
    template: templates/deployment.yaml
    asserts:
      - notExists:
          path: spec.template.spec.containers[0].envFrom

  - it: references an existing Secret
    template: templates/deployment.yaml
    set:
      existingSecret: my-secret
    asserts:
      - equal:
          path: spec.template.spec.containers[0].envFrom[0].secretRef.name
          value: my-secret

  - it: references the chart-created Secret and rolls pods when it changes
    template: templates/deployment.yaml
    release:
      name: shop
    set:
      secret.create: true
      secret.data.API_KEY: abc
    asserts:
      - equal:
          path: spec.template.spec.containers[0].envFrom[0].secretRef.name
          value: shop-secret
      - exists:
          path: spec.template.metadata.annotations["checksum/secret"]
```

Two behaviors to notice:

- The deployment suite lists `configmap.yaml` and `secret.yaml` even though it asserts only on the Deployment.
  The Deployment `include`s them to compute checksums, and helm-unittest can only resolve templates that are listed
  in `templates:`. Without them: `no template "nginx-demo/templates/secret.yaml" associated with template`.
- `failedTemplate` matches the error text with `errorPattern` (a regex). `errorMessage` needs an *exact* match and
  breaks on messages containing `:`.

<details>
<summary>Hint: suites for the migration hook, the extra ConfigMaps, and the helm test hook</summary>

`charts/nginx-demo/tests/migration_test.yaml`:

```yaml
suite: migration hook
templates:
  - templates/migration-job.yaml
tests:
  - it: is a pre-install and pre-upgrade hook that cleans up after itself
    asserts:
      - isKind:
          of: Job
      - equal:
          path: metadata.annotations["helm.sh/hook"]
          value: pre-install,pre-upgrade
      - equal:
          path: metadata.annotations["helm.sh/hook-delete-policy"]
          value: before-hook-creation,hook-succeeded

  - it: is not rendered when disabled
    set:
      migration.enabled: false
    asserts:
      - hasDocuments:
          count: 0

  - it: exits non-zero only when migration.fail is set
    set:
      migration.fail: true
    asserts:
      - matchRegex:
          path: spec.template.spec.containers[0].args[0]
          pattern: exit 1

  - it: does not fail by default
    asserts:
      - notMatchRegex:
          path: spec.template.spec.containers[0].args[0]
          pattern: exit 1
```

`charts/nginx-demo/tests/extra_configmaps_test.yaml`:

```yaml
suite: extra configmaps (lab-common library)
templates:
  - templates/extra-configmaps.yaml
tests:
  - it: renders nothing by default
    asserts:
      - hasDocuments:
          count: 0

  - it: renders one ConfigMap per key, with tpl applied to values
    release:
      name: shop
    set:
      global.environment: prod
      extraConfigMaps:
        settings:
          ENVIRONMENT: "{{ .Values.global.environment }}"
          MAX_CONN: 100
    asserts:
      - isKind:
          of: ConfigMap
      - equal:
          path: metadata.name
          value: shop-settings
      - equal:
          path: data.ENVIRONMENT
          value: prod
      - equal:
          path: data.MAX_CONN
          value: "100"
      - equal:
          path: metadata.labels["app.kubernetes.io/instance"]
          value: shop
```

`charts/nginx-demo/tests/helm_test_hook_test.yaml` (guards the Lab 7 hook Pod, see the `.helmignore` warning above):

```yaml
suite: helm test hook
templates:
  - templates/tests/http.yaml
tests:
  - it: is a test hook Pod that calls the Service
    release:
      name: shop
    asserts:
      - isKind:
          of: Pod
      - equal:
          path: metadata.annotations["helm.sh/hook"]
          value: test
      - matchRegex:
          path: spec.containers[0].args[2]
          pattern: http://shop-service:80/
```

The library's own "empty data" `fail` cannot be unit-tested this way: the values schema rejects an empty ConfigMap
first, and helm-unittest reports that as an error, not a failed template. That is Lab 11's
`--skip-schema-validation` check.

</details>

### Step 11: Run them

```bash
helm dependency build ./charts/nginx-demo
helm unittest ./charts/nginx-demo
```

*Expect:* all suites `PASS`, for example `Tests: 20 passed, 20 total` with every suite from the hint.

## Part C: Sign and verify

A version number says nothing about who built an archive or whether it changed after publication.
Helm has built-in **provenance**: a detached, signed `.prov` file containing the chart's SHA-256.

### Step 12: Create a throwaway signing key

Use a temporary GnuPG home so your real keyring is untouched:

```bash
export GNUPGHOME=$(mktemp -d); chmod 700 "$GNUPGHOME"
gpg --batch --pinentry-mode loopback --passphrase '' \
  --quick-generate-key "Helm Lab <helm-lab@example.com>" rsa3072 default 1y
# Helm 3 reads the legacy keyring format:
gpg --export > "$GNUPGHOME/pubring.gpg"
gpg --batch --pinentry-mode loopback --passphrase '' --export-secret-keys > "$GNUPGHOME/secring.gpg"
```

> [!NOTE]
> A key with an empty passphrase is for this lab only. Real signing keys have passphrases and live in a hardware key or your CI's secret store.

### Step 13: Package with a signature and verify it

```bash
mkdir -p /tmp/signed
helm package ./charts/nginx-demo --sign --key "Helm Lab" --keyring "$GNUPGHOME/secring.gpg" -d /tmp/signed
ls /tmp/signed        # nginx-demo-0.5.0.tgz  nginx-demo-0.5.0.tgz.prov
helm verify /tmp/signed/nginx-demo-0.5.0.tgz --keyring "$GNUPGHOME/pubring.gpg"
```

*Expect:* `Signed by: Helm Lab <helm-lab@example.com>` and `Chart Hash Verified: sha256:...`.

Install refusing anything unverified:

```bash
helm install demo-signed /tmp/signed/nginx-demo-0.5.0.tgz -n helm-lab --verify \
  --keyring "$GNUPGHOME/pubring.gpg" -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 90s
helm uninstall demo-signed -n helm-lab
```

### Step 14: Tamper with it

```bash
rm -rf /tmp/tampered && mkdir -p /tmp/tampered/x && cp /tmp/signed/* /tmp/tampered/
tar xzf /tmp/tampered/nginx-demo-0.5.0.tgz -C /tmp/tampered/x
echo "# evil" >> /tmp/tampered/x/nginx-demo/values.yaml
tar czf /tmp/tampered/nginx-demo-0.5.0.tgz -C /tmp/tampered/x nginx-demo

helm verify /tmp/tampered/nginx-demo-0.5.0.tgz --keyring "$GNUPGHOME/pubring.gpg"
helm verify /tmp/signed/nginx-demo-0.5.0.tgz --keyring /dev/null
```

*Expect:* `sha256 sum does not match ...` for the modified archive, and `signature made by unknown entity`
when the verifier does not trust the signer. **Both** matter: a valid hash proves integrity; a trusted key proves origin.

### Step 15: Publish to OCI and verify on pull

```bash
docker start helm-registry 2>/dev/null || docker run -d -p 5001:5000 --name helm-registry registry:2
helm push /tmp/signed/nginx-demo-0.5.0.tgz oci://localhost:5001/helm-lab
```

*Expect:* `Pushed: localhost:5001/helm-lab/nginx-demo:0.5.0` and a `Digest: sha256:...`. Copy that digest.

```bash
mkdir -p /tmp/pull
helm pull oci://localhost:5001/helm-lab/nginx-demo --version 0.5.0 --verify \
  --keyring "$GNUPGHOME/pubring.gpg" -d /tmp/pull
ls /tmp/pull          # .tgz and .prov both came from the registry
```

`helm push` uploads the `.prov` next to the chart when it exists.

### Step 16: Sign the OCI artifact with cosign (optional)

Helm provenance signs the *archive*. `cosign` signs the *registry object by digest*, the same way
container images are signed, so one policy engine (Kyverno, Sigstore policy-controller) can enforce both.

```bash
cd /tmp && COSIGN_PASSWORD="" cosign generate-key-pair
DIGEST=sha256:<paste the digest from helm push>

COSIGN_PASSWORD="" cosign sign --key /tmp/cosign.key --yes --allow-insecure-registry \
  --use-signing-config=false --tlog-upload=false localhost:5001/helm-lab/nginx-demo@$DIGEST

cosign verify --key /tmp/cosign.pub --allow-insecure-registry --insecure-ignore-tlog=true \
  localhost:5001/helm-lab/nginx-demo@$DIGEST
```

*Expect:* `The signatures were verified against the specified public key`.

> [!WARNING]
> `--allow-insecure-registry`, `--tlog-upload=false`, and `--insecure-ignore-tlog` exist only because this lab uses a
> plain-HTTP registry and no public Sigstore services. In production use **keyless** signing from CI (OIDC identity plus
> the transparency log) or a KMS-held key, and verify with `--certificate-identity` / `--certificate-oidc-issuer`.

Prove it rejects the wrong key, and unsigned artifacts:

```bash
cd /tmp && COSIGN_PASSWORD="" cosign generate-key-pair --output-key-prefix other
cosign verify --key /tmp/other.pub --allow-insecure-registry --insecure-ignore-tlog=true \
  localhost:5001/helm-lab/nginx-demo@$DIGEST
```

*Expect:* `no matching attestations ... accepted signatures do not match threshold`. Any digest you push but do not sign
fails with `no signatures found`.

## Part D: CI with chart-testing

Everything so far you ran by hand. CI makes it a gate that no pull request skips.
`ct` (chart-testing) lints charts (`helm lint`, `yamllint`, `Chart.yaml` schema), enforces a version bump when a chart
changes, and installs each changed chart on a real cluster and runs its `helm test`.

### Step 17: Add the ct configuration

Get ct's default schema and lint rules into the repository (so they are versioned and tweakable), and add `ct.yaml`:

```bash
mkdir -p ct
curl -fsSL -o ct/chart_schema.yaml https://raw.githubusercontent.com/helm/chart-testing/v3.14.0/etc/chart_schema.yaml
curl -fsSL -o ct/lintconf.yaml     https://raw.githubusercontent.com/helm/chart-testing/v3.14.0/etc/lintconf.yaml
```

`ct.yaml` (repository root):

```yaml
# chart-testing configuration (https://github.com/helm/chart-testing)
chart-dirs:
  - charts
chart-yaml-schema: ct/chart_schema.yaml
lint-conf: ct/lintconf.yaml
target-branch: main
validate-maintainers: false
check-version-increment: true
helm-extra-args: --timeout 120s
```

`ct` requires every chart to have a `values.yaml`, even a library. Create `charts/lab-common/values.yaml`:

```yaml
# Library charts have no configurable values; ct lint requires the file to exist.
```

### Step 18: Lint everything

```bash
ct lint --config ct.yaml --all
```

*Expect:* `All charts linted successfully` for `lab-banner`, `lab-common`, `nginx-demo`, and `storage-demo`.

> [!NOTE]
> `ct lint` runs `yamllint`, which forbids trailing empty lines at the end of YAML files (`empty-lines: max: 0`). If you see `error too many blank lines (1 > 0) (empty-lines)`, ensure `values.yaml` ends with a single newline and no trailing blank lines.

### Step 19: Give ct install scenarios

`ct install` installs the chart once **per file** in the chart's `ci/` directory, then runs `helm test`. Create three:

`charts/nginx-demo/ci/default-values.yaml`:

```yaml
# ct runs one install per file in this directory. Defaults only.
{}
```

`charts/nginx-demo/ci/secret-values.yaml`:

```yaml
# Dummy values for CI only; real secrets come from encrypted files.
secret:
  create: true
  data:
    API_KEY: ci-dummy-key
extraConfigMaps:
  settings:
    ENVIRONMENT: ci
```

`charts/nginx-demo/ci/autoscaling-values.yaml`:

```yaml
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 2
```

(`/ci/` is already in `.helmignore` from Step 9.)

```bash
ct install --config ct.yaml --charts charts/nginx-demo
```

*Expect (after about a minute):* three `Installing chart with values file ...` lines, each followed by a passing helm test,
each release and its random namespace deleted, and `All charts installed successfully`. The long pod description dump is
normal `ct` output.

### Step 20: See the version-bump gate

`ct` compares your branch with `<remote>/<target-branch>` (by default `origin/main`). In your own repository fork where `main` holds your baseline progress, make sure your commits are pushed (`git push origin main`).

If practicing locally in this repository (where `origin/main` holds the finished chart), create a snapshot branch and a local self-remote so `ct` compares against your current progress:

```bash
# 1. Snapshot your current commit as the comparison base:
git branch -f ct-base HEAD
git remote add ctlocal "$(git rev-parse --show-toplevel)" 2>/dev/null || true
git fetch ctlocal ct-base

# 2. Create a disposable test branch and make a change without bumping version:
git switch -c bump-test
echo "# tweak" >> charts/nginx-demo/values.yaml && git commit -am "tweak values"
ct lint --config ct.yaml --remote ctlocal --target-branch ct-base
```

*Expect:* `chart version not ok. Needs a version bump!`.

Now bump `version` in `charts/nginx-demo/Chart.yaml` (e.g. to `0.5.1`), commit, and rerun:

```bash
git commit -am "fix: bump chart version to 0.5.1"
ct lint --config ct.yaml --remote ctlocal --target-branch ct-base
```

*Expect:* `All charts linted successfully`.

Clean up the temporary experiment:

```bash
git switch - && git branch -D bump-test ct-base && git remote remove ctlocal
```

### Step 21: Wire it into GitHub Actions

Create `.github/workflows/chart-ci.yaml`. It refuses unencrypted secrets files, builds dependencies, runs unit tests, lints,
and installs only what changed onto a temporary `kind` cluster:

```yaml
name: chart-ci

on:
  pull_request:
    paths:
      - "charts/**"
      - "ct.yaml"
      - "ct/**"

jobs:
  lint-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0 # ct compares against the target branch

      - uses: azure/setup-helm@v4

      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"

      - uses: helm/chart-testing-action@v2.7.0

      - name: Refuse unencrypted secrets files
        run: |
          shopt -s nullglob
          bad=0
          for f in charts/*/secrets.*.yaml; do
            if ! grep -q '^sops:' "$f"; then
              echo "::error file=$f::not SOPS-encrypted"
              bad=1
            fi
          done
          exit $bad

      - name: Build chart dependencies
        run: helm dependency build charts/nginx-demo

      - name: Unit tests
        run: |
          helm plugin install https://github.com/helm-unittest/helm-unittest
          helm unittest charts/nginx-demo

      - name: Lint
        run: ct lint --config ct.yaml

      - name: Detect changed charts
        id: changed
        run: |
          changed=$(ct list-changed --config ct.yaml)
          if [[ -n "$changed" ]]; then echo "changed=true" >> "$GITHUB_OUTPUT"; fi

      - uses: helm/kind-action@v1
        if: steps.changed.outputs.changed == 'true'

      - name: Install and test on a temporary cluster
        if: steps.changed.outputs.changed == 'true'
        run: ct install --config ct.yaml
```

Check the secrets guard locally (it should print `BAD` only for the unencrypted file), then delete the bad file:

```bash
printf 'secret:\n  data:\n    K: plain\n' > charts/nginx-demo/secrets.prod.yaml
for f in charts/*/secrets.*.yaml; do grep -q '^sops:' "$f" && echo "$f ok" || echo "$f BAD"; done
rm charts/nginx-demo/secrets.prod.yaml
```

> [!NOTE]
> The workflow file was validated as YAML but not executed here (that needs a GitHub repository and a pull request). If you push
> your branch and open a PR, expect to iterate on action versions. To try it, also commit `charts/nginx-demo/secrets.dev.yaml`; it
> is encrypted, so the guard passes. CI cannot *decrypt* it, which is right: CI never needs the private key.

## Verify

Local:

```bash
helm dependency build ./charts/nginx-demo
helm lint ./charts/nginx-demo
helm unittest ./charts/nginx-demo
ct lint --config ct.yaml --all
helm package ./charts/nginx-demo -d /tmp/pk-check && tar tzf /tmp/pk-check/nginx-demo-*.tgz | grep -E "secrets\.|\.sops|nginx-demo/tests/|nginx-demo/ci/"   # no output
tar tzf /tmp/pk-check/nginx-demo-*.tgz | grep templates/tests/http.yaml                                                 # still present
```

Cluster:

```bash
helm secrets upgrade --install demo-secret ./charts/nginx-demo -n helm-lab \
  -f ./charts/nginx-demo/values-dev.yaml -f ./charts/nginx-demo/secrets.dev.yaml --wait --timeout 120s
helm test demo-secret -n helm-lab --timeout 60s
ct install --config ct.yaml --charts charts/nginx-demo
```

## Break it and recover

1. **Plain `helm` on an encrypted file.**

   ```bash
   helm template d ./charts/nginx-demo -f ./charts/nginx-demo/secrets.dev.yaml -s templates/secret.yaml | grep API_KEY
   ```

   *Expect:* no error, and `API_KEY: ENC[AES256_GCM,...]`. Helm does not know the file is encrypted, so it would deploy
   the **ciphertext as the password**. Always go through `helm secrets` (or decrypt in your pipeline), and add a CI check that
   a deployed value never starts with `ENC[`.
2. **Package without the ignore rules.** Temporarily remove `/secrets.*.yaml` and `/.sops.yaml` from `.helmignore`, run
   `helm package`, and list the archive. Restore the lines.
3. **A bare `tests/` in `.helmignore`.** Change `/tests/` to `tests/` and run
   `helm template d ./charts/nginx-demo | grep -c http-test`: it prints `0` while `helm lint` still passes, but `helm unittest`
   fails the `helm test hook` suite. Restore.
4. **Break a unit test on purpose.** Change `"%s-deployment"` to `"%s-deploy"` in `_helpers.tpl` and run `helm unittest`.
   *Expect:* the test `names the Deployment and selector after the release` fails with `Expected: shop-deployment`. Restore.
5. **Decrypt with the wrong key.**

   ```bash
   XDG_CONFIG_HOME=$(mktemp -d) SOPS_AGE_KEY_FILE=/dev/null sops --decrypt charts/nginx-demo/secrets.dev.yaml
   ```

   *Expect:* `Failed to get the data key required to decrypt the SOPS file` (simulating an unauthorized machine without your private age key). This demonstrates that without the correct key, the ciphertext is unreadable.

## Explain

- What exactly does SOPS protect, and where does the plaintext still exist after a `helm install`?
- Why did the secret rotation need a `checksum/secret` annotation?
- What does `helm verify` prove that a version number does not, and what does it *not* prove?
- Why is `tests/` in `.helmignore` written with a leading `/`?
- Which problems does unit testing catch that `helm lint`, `ct install`, and `helm test` each do not?

> [!TIP]
> See [12-secrets-signing-and-ci-explained.md](12-secrets-signing-and-ci-explained.md) for detailed explanations.

## Cleanup and checkpoint

```bash
helm uninstall demo-secret -n helm-lab
docker rm -f helm-registry 2>/dev/null || true
rm -rf /tmp/signed /tmp/tampered /tmp/pull /tmp/pk /tmp/pk-check /tmp/cosign.* /tmp/other.* "$GNUPGHOME"
unset GNUPGHOME
```

Keep `~/.config/sops/age/keys.txt` (you need it to decrypt `secrets.dev.yaml`). You can commit
`charts/nginx-demo/secrets.dev.yaml` and `.sops.yaml`; they contain no plaintext. Do **not** commit `keys.txt`, any `*.dec` file,
or the GnuPG directory. Tick Lab 12 in the README and create `lab-12-complete`.

References: [SOPS](https://github.com/getsops/sops), [age](https://github.com/FiloSottile/age),
[helm-secrets](https://github.com/jkroepke/helm-secrets), [helm-unittest](https://github.com/helm-unittest/helm-unittest),
[Helm provenance](https://helm.sh/docs/topics/provenance/), [cosign](https://docs.sigstore.dev/cosign/),
[chart-testing](https://github.com/helm/chart-testing).

## Your notes

Record versions, observations, failures, and explanations here.
