# Lab 8: Dependencies — Explained

[Back to Lab 8: Dependencies](08-dependencies.md)

---

## Overview

In Lab 8, you composed charts using subcharts, explored dependency locking via `Chart.lock`, and learned value scoping boundaries between parent and child charts using subchart namespaces and `global` values.

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: Which values are visible to the child?

#### TL;DR

A child (subchart) only sees:

1. Its own default values defined in its local `values.yaml`.
2. Parent values explicitly namespaced under its subchart name (e.g. `lab-banner:`).
3. Values declared under the **`global:`** key.
The child **cannot** see any other parent values (e.g., `replicaCount`, `image`, or `service`).

#### Deep Dive & Mechanism

1. **Value Isolation & Encapsulation:**
   - In parent `values.yaml`:

     ```yaml
     replicaCount: 2
     lab-banner:
       message: "Hello from the parent"
     global:
       environment: "dev"
     ```

   - Inside `lab-banner/templates/configmap.yaml`:
     - Accessing `.Values.message` evaluates to `"Hello from the parent"` (Helm strips the `lab-banner.` prefix when passing values into the subchart context).
     - Accessing `.Values.global.environment` evaluates to `"dev"`.
     - Accessing `.Values.replicaCount` returns **`nil`** (the child has no knowledge of the parent's top-level values).
2. **The Power of `global`:**
   - `global:` is a reserved Helm keyword. Any key placed under `global:` is automatically broadcast and accessible to the parent chart and **every single subchart** via `.Values.global.*`.
   - **Common Use Cases:** Global environment name (`dev`/`prod`), shared domain names (`example.com`), registry mirrors, or shared TLS configuration.

---

### Question 2: Why commit the lock file but ignore generated archives?

#### TL;DR

- **Commit `Chart.lock`:** It guarantees deterministic, reproducible builds by pinning the exact version and repository/digest of declared dependencies.
- **Ignore `charts/*.tgz`:** Compressed archives are compiled binary build artifacts. Storing them in Git causes repository bloat and merge conflicts.

#### Deep Dive & Mechanism

1. **The Role of `Chart.lock`:**
   - Similar to `package-lock.json` in Node.js, `Cargo.lock` in Rust, or `poetry.lock` in Python.
   - When you declare a dependency in `Chart.yaml` with SemVer ranges (e.g., `version: ^1.2.0`), `helm dependency update` resolves the newest matching version and records its exact version, repository URL, and cryptographic digest in `Chart.lock`.
   - Committing `Chart.lock` ensures that teammates, CI/CD pipelines, and GitOps engines install the exact same dependency versions every time. (Note: For local `file://` dependencies, the digest records the dependency declaration rather than hashing every file in the child source directory; Git tracks the source files).
2. **Why `.gitignore` generated archives (`charts/*.tgz`):**
   - Storing tarballs in Git bloats the repository size over time because Git stores binary diffs inefficiently.
   - Anyone cloning the repository can recreate the exact `charts/` folder in one second by running `helm dependency build`.

---

### Question 3: When would you intentionally use `update` instead of `build`?

#### TL;DR

- Use **`helm dependency build`** for regular day-to-day development, CI/CD, and deployments. It strictly respects `Chart.lock`.
- Use **`helm dependency update`** only when you intentionally want to check for, resolve, and lock **new dependency versions or update the lockfile**.

#### Deep Dive & Mechanism

1. **`helm dependency build` (Deterministic):**
   - Reads `Chart.lock`.
   - Downloads or packages the exact archives specified in the lockfile into the `charts/` folder.
   - If `Chart.lock` is missing or out of sync with `Chart.yaml`, it warns you or fails.
   - Always used in CI/CD pipelines to guarantee build reproducibility.
2. **`helm dependency update` (Resolution & Mutating):**
   - Disregards `Chart.lock`.
   - Inspects `Chart.yaml` dependencies, queries the remote chart repositories (or local file paths), calculates the latest compatible versions according to SemVer ranges, downloads them, and **overwrites `Chart.lock`**.
   - Use this when:
     - You just added a new dependency to `Chart.yaml`.
     - You want to upgrade an existing subchart to a newer version.
     - You changed the version number of a local subchart.

---

## Break It and Recover — Detailed Walkthrough

### What the challenge asks
>
> Delete only the generated `charts/nginx-demo/charts/lab-banner-0.1.0.tgz`, keeping the source chart and lock file. Try rendering, observe the missing-dependency error, then recover with `helm dependency build`.

#### 1. What to Break

Simulate cloning a fresh Git repository (where generated `charts/*.tgz` archives are gitignored) by deleting the packaged subchart archive:

```bash
rm -f charts/nginx-demo/charts/lab-banner-0.1.0.tgz
```

#### 2. Run the Command

Attempt to render the parent chart:

```bash
helm template demo-dev ./charts/nginx-demo
```

#### 3. The Error Observed

```text
Error: found in Chart.yaml, but missing in charts/ directory: lab-banner
```

#### 4. Why This Failed

- When Helm inspects `Chart.yaml` and `Chart.lock`, it validates that every declared dependency exists as a packaged `.tgz` archive or directory inside the chart's `charts/` directory.
- Unlike tools like `npm` or `pip`, `helm template` and `helm install` will **not** automatically download or package missing dependencies on the fly.
- If dependencies are missing from `charts/`, Helm halts immediately to prevent deploying an incomplete or broken release.

#### 5. How to Recover

Rebuild the dependencies strictly from the pinned `Chart.lock`:

```bash
helm dependency build ./charts/nginx-demo
```

*Output:*

```text
Saving 1 charts
Deleting outdated charts
```

Verify that rendering works again:

```bash
helm template demo-dev ./charts/nginx-demo | grep -A 5 "kind: ConfigMap"
```

*Output:*
Both the subchart's `demo-dev-banner` ConfigMap and the parent's `demo-dev-page` ConfigMap render cleanly.

---

## Key Takeaways

| Concept | Explanation |
| :--- | :--- |
| Value Visibility | Subcharts only see their own values, their parent subchart block, and `global`. |
| `Chart.lock` | Pins exact dependency versions. Always commit to Git. |
| `build` vs `update` | `build` uses the lockfile (safe for CI); `update` recalculates and writes a new lockfile. |
