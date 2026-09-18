# Roadmap

Where the Helm Lab stands and what comes next. Each lab follows the conventions in
[labs/TEMPLATE.md](labs/TEMPLATE.md): a start checkpoint, runnable steps, verification, a
break-and-recover exercise, an `-explained` companion, and a `lab-NN-complete` tag. Every lab is
executed on a real cluster before it is committed, and findings go into
[lab-validation.md](lab-validation.md).

## Where we are

| Stage | Labs | Skill level |
| --- | --- | --- |
| Fundamentals | 0-3: scaffold, install, upgrade/rollback, values and environments | Can use a chart someone else wrote |
| Authoring | 4-7: template logic, helpers, ConfigMaps/rollouts, validation and tests | Can write a correct single chart |
| Composition and delivery | 8-9: dependencies, packaging, OCI, GitOps | Can ship a chart |
| Operating and hardening | 10-12: hooks and recovery, advanced templating and library charts, secrets/signing/CI | Can run charts in a team pipeline |
| **Integration** | **13: capstone (this milestone)** | **Can design and operate a multi-service release end to end** |
| Advanced track | 14-18 (below) | Can consume, harden, and evolve charts at scale |

Kubernetes-focused extensions (networking, health and scaling, identity and secrets, storage)
stay optional and are referenced by the labs that need them.

## Next: Lab 13, Capstone: an umbrella chart for a three-tier app

**Goal:** apply Labs 0-12 together, with no new Helm concepts, so gaps show up.

- **App:** `web` (the existing `nginx-demo` chart, reused as a dependency alias), `api` (PostgREST),
  `db` (PostgreSQL). New charts: `shop-db`, `shop-api`, and the `shop` umbrella.
- **Exercises:** umbrella with aliased dependencies; a credentials Secret from SOPS-encrypted values; a
  `post-install,post-upgrade` migration hook that seeds data; a smoke test through all three tiers;
  dev and prod value sets; unit tests and `ct` coverage; failure recovery with `--atomic`; package,
  sign, and publish to OCI; optional GitOps hand-off.
- **Traps it teaches:** label and selector collisions between subcharts; hook ordering when a hook
  needs the database it is migrating; database password rotation versus persistent volumes; the
  handoff between `helm secrets` and GitOps.
- **Needs:** cluster, Docker, and the Lab 12 tools.

## Advanced track (planned)

Each lab below is independent of the others unless noted. Order is a recommendation, not a rule.

### Lab 14: Consuming third-party charts and upgrading safely

**Why:** most real-world Helm use is other people's charts.
- Add a repo and search; `helm show values/readme/chart`; pin `--version`; install a real chart
  (a small one, such as a Bitnami or ingress-nginx chart).
- Override safely: minimal values file, `--set` versus `-f`, and reading the chart's templates to find what a value does.
- **Upgrade playbook:** `helm diff` between chart versions, reading changelogs/`UPGRADE` notes,
  handling renamed values, and rollback rehearsal.
- **When values cannot do it:** `--post-renderer` with Kustomize, and why forking is the last resort.
- **Break it:** upgrade across a breaking chart version; recover.
- **Verify needs:** cluster and internet. **Risk:** upstream chart drift; pin exact versions and record them.

### Lab 15: CRDs and operators

**Why:** CRDs are the most common Helm surprise.
- The `crds/` directory: installed once, never upgraded or deleted by Helm. What that means in practice.
- Patterns: separate CRD chart, CRDs applied by the pipeline, or the operator installing its own.
- Install a real operator chart (cert-manager) and create a custom resource; ordering with hooks.
- Upgrade the CRDs by hand and prove what Helm leaves alone.
- **Break it:** create a custom resource before its CRD exists. **Verify needs:** cluster and internet.

### Lab 16: Production hardening and chart best practices

**Why:** a chart that works is not yet a chart that is safe to run.
- `securityContext` defaults that pass the Pod Security `restricted` profile (non-root, read-only root filesystem, dropped capabilities).
- `NetworkPolicy`, `PodDisruptionBudget`, topology spread, and resource requests as chart features with tests.
- `helm.sh/resource-policy: keep` and other lifecycle annotations.
- A strict values schema (`additionalProperties: false`, `$ref`s), and generated values docs with `helm-docs`.
- Enforce the rules in CI with a policy scan (for example `kubeconform` and a policy tool).
- **Break it:** deploy into a namespace enforcing `restricted`; fix the chart until it is admitted.

### Lab 17: Many releases: Helmfile (and Argo CD ApplicationSet)

**Why:** one chart is easy; twenty releases across environments is the real job.
- Helmfile: declare releases, environments, layered values, `needs:` ordering, and `helmfile diff/apply`.
- The same fleet as an Argo CD `ApplicationSet` (for those with Argo CD from Lab 9).
- Promotion workflow: dev to prod by changing a version, not a template.
- **Break it:** an unpinned chart version changes under you.

### Lab 18: Helm internals and advanced operations

**Why:** understanding the machinery is what turns guesses into diagnoses.
- How release state is stored (Secrets, drivers); reading a revision by hand.
- The three-way merge: manual `kubectl edit` drift and what `helm upgrade` does about it.
- Adopting existing resources into a release (ownership annotations, `--take-ownership`), and `--keep-history`.
- Deprecated API removal and migrating releases (`mapkubeapis`).
- **Helm 3 versus Helm 4:** server-side apply, renamed flags (`--rollback-on-failure`), plugin changes; what to test before upgrading.

### Stretch (unscheduled)

- Writing a Helm plugin, or using the Helm SDK from Go.
- OCI-hosted dependencies and provenance inside Argo CD.
- Values validation with CUE or `$ref` schema composition.
- Chart supply-chain policy (admission enforcement of signed charts).

## Definition of done for every lab

1. Steps were executed end to end on a live cluster (or the unexecuted part is labeled).
2. Verification commands and expected outputs match what was observed.
3. A break-and-recover exercise, with the failing layer identified.
4. `-explained` companion answering each Explain question.
5. README path and tags table updated, `lab-validation.md` row added, tag created.
6. Tools installed only for the lab are named in its prerequisites, and removed from the author's machine afterwards.

## Mastery checklist

A learner can claim working mastery when they can do each of these without notes:

| Skill | Labs |
| --- | --- |
| Scaffold, render, install, upgrade, roll back a chart | 0-2 |
| Layer values correctly and predict precedence | 3 |
| Write templates with loops, conditionals, helpers, and `tpl` | 4, 5, 11 |
| Roll pods on config or secret change | 6, 12 |
| Validate inputs and test a chart at three levels | 7, 12 |
| Compose charts with dependencies and library charts | 8, 11, 13 |
| Package, publish, sign, and verify | 9, 12, 13 |
| Use and recover from hooks and failed upgrades | 10, 13 |
| Handle secrets without committing them | 12, 13 |
| Consume, upgrade, and patch third-party charts | 14 |
| Reason about CRDs | 15 |
| Harden a chart for production | 16 |
| Operate fleets and understand Helm's internals | 17, 18 |

## Known gaps in the current material

- The Argo CD steps (Lab 9 Part C, Lab 12 workflow, Lab 13 GitOps) were not executed against a live Argo CD or GitHub.
- All labs target Helm 3.19; Helm 4 differences are only planned (Lab 18).
- Cluster checks used a single-node k3d/kind cluster; multi-node scheduling behavior is untested.
