# Lab 18 review: Helm internals and advanced operations

**Tested with:** Helm v3.19.0, helm-mapkubeapis 0.5.2, jq, python3, kind (Kubernetes v1.35.0), 2026-09-23
**Result:** Parts A–D are excellent, and every documented output reproduced:

- **Secret decoding:** the keys `chart, config, hooks, info, manifest, name, namespace, version`, and `.config` = `{"replicaCount":1}`.
- **3-way merge:** the out-of-band annotation survives (`replicas: 2, incident-id: INC-9901`), and manual scale 5 is reset to 2.
- **Ownership:** the collision error text matches **verbatim**, `--take-ownership` adopts, manual metadata adoption works (`managed-by-helm`), and `--keep-history` shows `uninstalled`.
- **The mapkubeapis flow:** the simulated `policy/v1beta1` blocks the upgrade, the dry run lists the mapping, the repair creates v2, and the upgrade gives REVISION 3.

**The final break-it doesn't work**, and a few version claims are wrong.

## Bugs

### B1: Relabeling the Secret doesn't create a `pending-upgrade` release (high)

The break-it sets only the **label** `status=pending-upgrade` on the latest release Secret. Verified results:

| Lab expects | Actual |
| --- | --- |
| `helm list` shows `pending-upgrade` | `helm list` still shows **`deployed`**. `helm list --pending` is empty |
| `helm upgrade` → `another operation ... is in progress` | **Upgrade succeeds** (a new revision is created) |

Helm reads the status from the encoded payload (`.info.status`), not from the label. The label is only a query index. So the learner sees none of the failure, and the "recover" steps are meaningless.

**Fix (verified):** Patch the payload the same way Part D already does, or reuse Lab 10's `timeout -s KILL 3 helm upgrade ...`:

```bash
python3 - "$SECRET_NAME" <<'EOF'
import subprocess, base64, gzip, json, sys
s = sys.argv[1]
raw = subprocess.check_output(["kubectl","get","secret",s,"-n","helm-internals","-o","jsonpath={.data.release}"])
obj = json.loads(gzip.decompress(base64.b64decode(base64.b64decode(raw))))
obj["info"]["status"] = "pending-upgrade"
enc = base64.b64encode(base64.b64encode(gzip.compress(json.dumps(obj).encode()))).decode()
subprocess.check_call(["kubectl","patch","secret",s,"-n","helm-internals","-p",
  json.dumps({"data":{"release":enc},"metadata":{"labels":{"status":"pending-upgrade"}}})])
EOF
```

With that, `helm list --pending` shows it, the upgrade fails with `another operation (install/upgrade/rollback) is in progress`, and `helm rollback internals-demo` recovers. All verified.
Also, **Method 2 Option A** (resetting only the label to `deployed`) has the same flaw: it wouldn't fix a real stuck release, because the payload still says `pending-upgrade`. Recommend deleting the pending revision's Secret (Option B) as the manual last resort, as Lab 10 does.

### B2: Plain `helm list` hides pending releases (medium)

"Verify that Helm thinks the release is stuck: `helm list -n helm-internals`. Notice the status is `pending-upgrade`." With a genuinely pending release (the payload patch above), plain `helm list` **omits the release entirely**. Only `pdb-demo` is listed, because the default filter shows deployed and failed releases. Use `helm list --pending` or `helm list -a`. That's a valuable operational lesson in its own right ("my release disappeared from `helm list`").

### B3: The `--take-ownership` version claim is wrong (medium)

"In Helm v3.8+ (promoted and stabilized in v3.14+), Helm introduced the `--take-ownership` flag". The flag first shipped in **Helm 3.17.0** (early 2025). There was no v3.8 or v3.14 version of it. The lab's **Start** line also says "Helm v3.14+", but on 3.14–3.16 `helm install --take-ownership` fails with `unknown flag`. Change the requirement to Helm ≥ 3.17.

### B4: The Helm 4 table is out of date (medium)

The table header says "Helm 4 (Upcoming / Design Proposals)", but **Helm 4.0 was released in November 2025**. Several rows appear inaccurate and should be checked against the Helm 4 release notes:

- "CRD Upgrades: Native CRD upgrade support via SSA". I'm not aware of Helm 4 changing the `crds/` directory's install-only behavior. Verify before teaching it.
- "legacy HTTP repositories deprecated". Classic `index.yaml` repositories still work in Helm 4, as far as I know. Verify.
- "`--atomic` → `--rollback-on-failure`" is correct. Also worth listing are post-renderers becoming plugins (relevant to Lab 14) and `--force` → `--force-replace`.

## Accuracy issues

- **I1:** Part D Step 4's expected error is missing the trailing line `ensure CRDs are installed first`, which Helm 3.19 appends. It's misleading here (this isn't a CRD), so mention that learners should ignore it.
- **I2:** Part D Step 5: mapkubeapis 0.5.2 prints timestamped log lines, and there is **no** "Set status of release version 'pdb-demo.v1' to 'superseded'" line. The history does show v1 `superseded` and v2 described as "Kubernetes deprecated API upgrade - DO NOT rollback from this version".
- **I3:** Part A: the Secret labels also include `modifiedAt` (a Unix timestamp) in current Helm versions. Worth listing.
- **I4:** Part B's heading says "strategic merge patch". For CRDs, Helm falls back to a JSON merge patch (strategic merge needs Go struct metadata). One sentence would connect this to Lab 15.

## Safety / pedagogy suggestions

- **S1:** Part C should warn that **adoption transfers lifecycle ownership**. After `--take-ownership` or manual adoption, `helm uninstall` **deleted** the formerly legacy `legacy-app-service` and `adopt-demo-config` (verified: `NotFound` afterwards). In a real migration that deletes production objects the team didn't create with Helm. Mention `helm.sh/resource-policy: keep` for adopted resources.
- **S2:** Part C Step 2: after adoption, the Service's selector was rewritten from kubectl's `app: legacy-app-service` to the chart's `app: legacy-app`. Pointing this out shows that adoption *applies the chart's desired state*, not just labels.
- **S3:** Like Labs 15–17, there's no Explain section and no link to `18-helm-internals-and-advanced-operations-explained.md`.
- **S4:** Part D edits a release Secret by hand. Add a "back up first" line (`kubectl get secret ... -o yaml > backup.yaml`), since this is exactly the kind of operation learners will later try on real clusters.
