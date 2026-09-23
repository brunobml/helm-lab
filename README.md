# Helm Lab

Learn Helm by evolving one small NGINX application, one lab at a time.
The working chart starts with a Deployment and Service. You implement the later
features yourself; lab instructions explain what to change and how to verify it.

> [!TIP]
> Preparing for the Linux Foundation **SC104: Developing Helm Charts** certification?
> See the [SC104 Study Guide & Competency Mapping](SC104/README.md) for 100% exam curriculum alignment, command cheat sheets, and trap walkthroughs.

## Names and layout

| Name | Meaning |
| --- | --- |
| `helm-lab` | This learning repository and the local cluster/namespace |
| `nginx-demo` | The chart: a reusable application package |
| `demo-dev`, `demo-prod` | Releases: independently configured installations |
| `nginx` | The container running inside each application Pod |

```text
charts/nginx-demo/   Your evolving chart
labs/               Ordered exercises, hints, and completion checks
labs/extensions/    Optional Kubernetes-focused exercises
```

The chart previously lived at `helm-lab/`; its path is now `charts/nginx-demo/`.
Existing cluster releases are not migrated by this repository change. Start these
labs with the release names below in a dedicated learning namespace.

## Set up once

Use Bash (or a compatible shell), Git, Helm, kubectl, curl, and a disposable
Kubernetes cluster. You should recognize a Pod, Deployment, Service, and namespace;
Lab 1 connects those objects to Helm.

Local linting and rendering were checked with **Helm 3.19.0**. Cluster exercises
have not been executed as part of this restructuring. Record your Helm and
Kubernetes server versions in your learning notes. These instructions use Helm 3
semantics; consult the matching documentation if using another major version.

For a local cluster, install Docker and either [kind](https://kind.sigs.k8s.io/docs/user/quick-start/)
or [k3d](https://k3d.io/), then run:

```bash
# With kind:
kind create cluster --name helm-lab --wait 120s
kubectl config use-context kind-helm-lab

# Or with k3d:
k3d cluster create helm-lab
kubectl config use-context k3d-helm-lab

# Verify connectivity:
kubectl cluster-info
kubectl get nodes
helm version --short
kubectl version
```

If you already have a disposable cluster, select its context instead. Run **all
lab commands from this repository's root**. Rendering and linting work without a
cluster; installs, upgrades, port-forwarding, and Helm tests need one.

```bash
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo
```

Start with [Lab 0](labs/00-chart-creation.md) to scaffold your chart with `helm create`,
or jump to [Lab 1](labs/01-first-chart.md) if you want to start directly with the prebuilt starter.

## Learning path

Check off a lab when its verification steps pass and you can answer its questions.
If you already completed the original fundamentals, use Labs 0–3 as a short review.

- [ ] [0. Chart creation](labs/00-chart-creation.md) — scaffold with helm create, strip boilerplate, and set metadata
- [ ] [1. First chart](labs/01-first-chart.md) — connect values, templates, and running resources
- [ ] [2. Release lifecycle](labs/02-release-lifecycle.md) — upgrade, inspect, rollback, and recover
- [ ] [3. Values and environments](labs/03-values-and-environments.md) — precedence and separate releases
- [ ] [4. Template logic](labs/04-template-logic.md) — conditionals, loops, scope, and indentation
- [ ] [5. Helpers and labels](labs/05-helpers-and-labels.md) — reuse code without breaking selectors
- [ ] [6. ConfigMaps and rollouts](labs/06-configmaps-and-rollouts.md) — change the page through Helm
- [ ] [7. Validation and tests](labs/07-validation-and-tests.md) — catch invalid inputs and test HTTP
- [ ] [8. Dependencies](labs/08-dependencies.md) — compose charts and lock versions
- [ ] [9. Packaging and GitOps](labs/09-packaging-and-gitops.md) — distribute and reconcile the chart
- [ ] [10. Hooks and failure recovery](labs/10-hooks-and-failure-recovery.md) — lifecycle hooks, `--atomic`, diffing, and stuck releases
- [ ] [11. Advanced templating and library charts](labs/11-advanced-templating-and-library-charts.md) — `tpl`, `required`, `lookup`, and shared helpers
- [ ] [12. Secrets, signing, and CI](labs/12-secrets-signing-and-ci.md) — SOPS secrets, unit tests, provenance/cosign, and chart-testing
- [ ] [13. Capstone: a three-tier release](labs/13-capstone.md) — umbrella chart, hooks, secrets, probes, CI, and publishing
- [ ] [14. Consuming third-party charts](labs/14-consuming-third-party-charts.md) — repositories, minimal overrides, diffing, post-rendering with Kustomize, and rollback
- [ ] [15. CRDs and operators](labs/15-crds-and-operators.md) — the `crds/` directory, cert-manager, upgrade traps, and ordering
- [ ] [16. Production hardening and chart best practices](labs/16-production-hardening-and-best-practices.md) — Pod Security restricted, PDB, NetworkPolicy, helm-docs, and kubeconform
- [ ] [17. Many releases: Helmfile (and Argo CD ApplicationSet)](labs/17-many-releases-helmfile-and-applicationset.md) — Helmfile orchestration, environments, DAG dependencies, label filtering, and Argo CD ApplicationSet
- [ ] [18. Helm internals and advanced operations](labs/18-helm-internals-and-advanced-operations.md) — release Secrets, 3-way merge patch, `--take-ownership`, deprecated APIs (`mapkubeapis`), and Helm 4 SSA

Optional extensions after Lab 7:

- [Networking](labs/extensions/networking.md): Service types and Ingress
- [Workload health and scaling](labs/extensions/health-and-scaling.md): probes, resources, and HPA
- [Identity and secrets](labs/extensions/identity-and-secrets.md): ServiceAccounts, RBAC, and Secret references
- [Storage and other workloads](labs/extensions/storage-and-workloads.md): persistence, Jobs, and StatefulSets

## Checkpoints and how to use this repository

This repository includes prebuilt, cluster-verified reference tags for every milestone in the learning path.

### Available tags

| Checkpoint Tag | Description / State |
| :--- | :--- |
| `lab-00-start` | Completed Lab 0 starter scaffold (Deployment, Service, minimal values) |
| `lab-01-complete` | Lab 1: First chart installed, rendered, and verified |
| `lab-02-complete` | Lab 2: Release lifecycle, upgrades, overrides, and rollbacks |
| `lab-03-complete` | Lab 3: Environment profiles (`values-dev.yaml`, `values-prod.yaml`) |
| `lab-04-complete` | Lab 4: Template logic (`extraEnv`, `resources`, `with`, `range`, `toYaml`) |
| `lab-05-complete` | Lab 5: Helpers (`_helpers.tpl`, named templates, standard labels) |
| `lab-06-complete` | Lab 6: ConfigMaps, volume mounts, and automated rollout checksums |
| `lab-07-complete` | Lab 7: Validation (`values.schema.json`), test hooks (`tests/http.yaml`), and `NOTES.txt` |
| `lab-08-complete` | Lab 8: Dependencies (subchart `lab-banner`, `Chart.lock`, global values) |
| `lab-09-complete` | Lab 9: Packaging (`0.2.0`), OCI registry publishing, and GitOps |
| `lab-10-complete` | Lab 10: `pre-install,pre-upgrade` migration hook Job, chart `0.3.0` |
| `lab-11-complete` | Lab 11: `tpl` values, `lab-common` library chart, `extraConfigMaps`, chart `0.4.0` |
| `lab-12-complete` | Lab 12: `secret.create` + SOPS workflow, `helm-unittest` suites, `ct` config and `ci/` scenarios, GitHub Actions workflow, chart `0.5.0` |
| `lab-13-complete` | Lab 13: `shop` umbrella chart with `shop-api` and `shop-db`, migration hook, smoke test, unit tests |
| `lab-14-complete` | Lab 14: Third-party chart lifecycle (`podinfo`), minimal values, `helm diff`, post-renderer Kustomize, rollback |
| `lab-15-complete` | Lab 15: CRD lifecycle (`charts/crd-demo`), `cert-manager` operator, silent drop trap, manual CRD upgrade playbook |
| `lab-16-complete` | Lab 16: Production hardening (`nginx-demo` 0.6.0), Pod Security `restricted`, PDB, NetworkPolicy, `helm-docs`, `kubeconform` |
| `lab-17-complete` | Lab 17: Many releases with Helmfile (`helmfile/`), DAG sequencing, environment promotion (`dev`/`prod`), and Argo CD ApplicationSet |
| `lab-18-complete` | Lab 18: Helm internals, release Secrets, 3-way merge, resource adoption (`--take-ownership`), `mapkubeapis`, and Helm 4 SSA |
| `extension-networking-complete` | Extension: Ingress and NodePort configuration |
| `extension-health-complete` | Extension: Health probes and HorizontalPodAutoscaler (HPA v2) |
| `extension-identity-complete` | Extension: ServiceAccount, RBAC Role/RoleBinding, and external Secrets |
| `extension-storage-complete` | Extension: Standalone `storage-demo` chart with PVC persistence |

See [lab-validation.md](lab-validation.md) for full cluster verification logs and findings.

---

### How to practice

You can approach the exercises using any of these workflows:

#### Approach 1: Practice on a local branch (Recommended)

Work inside this repository without modifying `main` or losing reference solutions:

1. **Start from the clean scaffold:**

   ```bash
   git checkout -b my-learning lab-00-start
   ```

2. Follow the lab instructions in `labs/01-first-chart.md` through `labs/18-helm-internals-and-advanced-operations.md`.
3. Test commands against your cluster and commit your progress as you complete each lab:

   ```bash
   git commit -am "Complete my lab 1"
   ```

4. **Compare against the reference solution at any time:**

   ```bash
   # See how your code compares to the official solution:
   git diff lab-01-complete
   ```

5. **Return to the fully completed reference anytime:**

   ```bash
   git checkout main
   ```

#### Approach 2: Jump directly into a specific lab

Want to practice a specific topic (e.g., Lab 4: Template Logic or Lab 6: ConfigMaps) without completing prior labs?

1. Check out the prerequisite checkpoint into a new branch:

   ```bash
   # To start Lab 4, start from Lab 3's completion:
   git checkout -b practice-lab-04 lab-03-complete

   # To start Lab 6, start from Lab 5's completion:
   git checkout -b practice-lab-06 lab-05-complete
   ```

2. Follow the lab guide, make your changes, and test.
3. Compare your result with the completion checkpoint:

   ```bash
   git diff lab-04-complete
   ```

#### Approach 3: Practice in a separate folder via Git worktree (Zero conflict)

If you want to keep this repo as your read-only manual while coding in an independent directory:

```bash
# Create an isolated practice workspace pointing to the starting tag:
git worktree add ../helm-lab-practice lab-00-start
cd ../helm-lab-practice

# Work through labs, run cluster tests, and commit freely in this folder!
```

When you are done:

```bash
cd /home/bleite/repos/helm-lab
git worktree remove ../helm-lab-practice
```

#### Approach 4: Inspect solutions without editing code

Inspect what changes between any two labs:

```bash
# See the exact changes introduced in Lab 5:
git diff lab-04-complete lab-05-complete -- charts/nginx-demo

# View the full contents of a file at a specific tag:
git show lab-06-complete:charts/nginx-demo/templates/deployment.yaml
```

## Cleanup

Keep `demo-dev` between labs unless a lab says otherwise. Stop port-forwarding
with Ctrl+C. When finished, list releases and uninstall the ones you created:

```bash
helm list -n helm-lab
helm uninstall demo-dev -n helm-lab
# Run only if you installed these releases:
helm uninstall demo-prod -n helm-lab
helm uninstall demo-package -n helm-lab
```

If you used a dedicated local cluster and want to remove all its resources:

```bash
# With kind:
kind delete cluster --name helm-lab
# Or with k3d:
k3d cluster delete helm-lab
```

## References

- [Using Helm](https://helm.sh/docs/v3/intro/using_helm/)
- [Template guide](https://helm.sh/docs/v3/chart_template_guide/)
- [Chart format and values schemas](https://helm.sh/docs/v3/topics/charts/)

This is a learning chart. Advanced features are introduced by the labs as you
need them.
