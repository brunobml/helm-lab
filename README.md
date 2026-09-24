# Helm Lab

Learn Helm by evolving one small NGINX application, one lab at a time.
The starter scaffold (`lab-00-start`) starts with a minimal Deployment and Service. You implement the later
features yourself; lab instructions explain what to change, what pitfalls to watch for, and how to verify it.
The `main` branch contains the fully completed, hardened reference code (from Lab 18).

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
labs/extensions/    Kubernetes-focused exercises (do them before Lab 10)
```

## Before you start

You need a terminal with Bash (macOS, Linux, or WSL2 on Windows) and these tools:

| Tool | Why | Install |
| --- | --- | --- |
| Git | Get the labs and track your progress | [git-scm.com](https://git-scm.com/downloads) |
| Docker | Runs the local Kubernetes cluster | [Docker Desktop / Engine](https://docs.docker.com/get-docker/) |
| kind **or** k3d | Creates a disposable local cluster | [kind](https://kind.sigs.k8s.io/docs/user/quick-start/#installation), [k3d](https://k3d.io/#installation) |
| kubectl | Talks to the cluster | [kubectl](https://kubernetes.io/docs/tasks/tools/) |
| Helm 3 (v3.17+) | The tool you are learning | [Helm](https://helm.sh/docs/intro/install/) |
| curl | Tests HTTP from your machine | usually preinstalled |

Later labs add a few more tools (for example `sops` and `cosign` in Lab 12, `helmfile` in Lab 17);
each lab lists and installs what it needs, and the [learning path](#learning-path) shows where.

You should recognize a Pod, Deployment, Service, and namespace. If those words are new, spend
30 minutes on the official [Kubernetes Basics tutorial](https://kubernetes.io/docs/tutorials/kubernetes-basics/)
first; Lab 1 then connects those objects to Helm.

All labs and extensions were verified end to end on Kubernetes v1.35.0 (kind and k3d) with Helm v3.19.0.
These instructions use Helm 3 semantics.

## Start here

1. **Get the labs and check your tools:**

   ```bash
   git clone https://github.com/brunobml/helm-lab.git
   cd helm-lab
   helm version --short      # v3.17 or newer
   kubectl version --client
   docker info --format '{{.ServerVersion}}'
   ```

2. **Create a disposable local cluster** (pick one):

   ```bash
   # With kind (if a cluster with this name already exists, reuse it or `kind delete cluster --name helm-lab` first):
   kind create cluster --name helm-lab --wait 120s
   kubectl config use-context kind-helm-lab

   # Or with k3d:
   k3d cluster create helm-lab
   kubectl config use-context k3d-helm-lab

   # Either way, check that the cluster answers:
   kubectl get nodes          # expect one node with STATUS Ready
   ```

3. **Create your practice branch.** `main` holds the finished reference solution, so do your own work
   on a branch that keeps the current lab instructions but puts the chart back to the minimal scaffold:

   ```bash
   git switch -c my-learning main
   git restore --source=lab-00-start --staged --worktree -- charts ct ct.yaml helmfile .github/workflows/chart-ci.yaml
   git commit -m "Start from the lab-00-start chart"
   ```

   The commit lists many `delete mode` lines; that's expected, since it removes the finished solution.
   `ls charts` now shows only `nginx-demo`. The later charts and CI files come back as you build them.

   > [!IMPORTANT]
   > Don't branch directly from a tag (`git switch -c my-learning lab-00-start`). A tag saves the whole
   > repository, including the lab instructions as they were back then, so you would get outdated labs
   > and no Labs 0 or 10–18.

4. **Start with [Lab 0](labs/00-chart-creation.md)** (build the starter chart yourself), or go straight
   to [Lab 1](labs/01-first-chart.md) (the branch already contains Lab 0's result).

Run **every lab command from the repository root**. Rendering and linting work without a cluster;
installs, upgrades, port-forwarding, and Helm tests need one.

## Learning path

Work through the stages in order. Check off a lab when its verification steps pass and you can
answer its questions.

### Stage 1 — Foundations (no extra tools)

- [ ] [0. Chart creation](labs/00-chart-creation.md) — scaffold with helm create, strip boilerplate, and set metadata
- [ ] [1. First chart](labs/01-first-chart.md) — connect values, templates, and running resources
- [ ] [2. Release lifecycle](labs/02-release-lifecycle.md) — upgrade, inspect, rollback, and recover
- [ ] [3. Values and environments](labs/03-values-and-environments.md) — precedence and separate releases
- [ ] [4. Template logic](labs/04-template-logic.md) — conditionals, loops, scope, and indentation
- [ ] [5. Helpers and labels](labs/05-helpers-and-labels.md) — reuse code without breaking selectors
- [ ] [6. ConfigMaps and rollouts](labs/06-configmaps-and-rollouts.md) — change the page through Helm
- [ ] [7. Validation and tests](labs/07-validation-and-tests.md) — catch invalid inputs and test HTTP

### Stage 2 — Composing and shipping charts

- [ ] [8. Dependencies](labs/08-dependencies.md) — compose charts and lock versions
- [ ] [9. Packaging and GitOps](labs/09-packaging-and-gitops.md) — distribute and reconcile the chart (Part C optionally uses Argo CD)

### Stage 3 — Kubernetes features in your chart (extensions)

These four short exercises add Ingress, probes and autoscaling, identity, and storage. They are
listed separately because they focus on Kubernetes rather than Helm, but **Labs 10–18 build on the
chart features they add** (for example, Lab 12's unit tests check the autoscaling and
`existingSecret` logic). Do them before Lab 10.

- [ ] [Networking](labs/extensions/networking.md) — Service types and Ingress (installs Traefik on kind)
- [ ] [Workload health and scaling](labs/extensions/health-and-scaling.md) — probes, resources, and HPA
- [ ] [Identity and secrets](labs/extensions/identity-and-secrets.md) — ServiceAccounts, RBAC, and Secret references
- [ ] [Storage and other workloads](labs/extensions/storage-and-workloads.md) — persistence, Jobs, and StatefulSets

### Stage 4 — Operating releases (extra tools: helm-diff; Lab 12: sops, age, cosign, chart-testing)

- [ ] [10. Hooks and failure recovery](labs/10-hooks-and-failure-recovery.md) — lifecycle hooks, `--atomic`, diffing, and stuck releases
- [ ] [11. Advanced templating and library charts](labs/11-advanced-templating-and-library-charts.md) — `tpl`, `required`, `lookup`, and shared helpers
- [ ] [12. Secrets, signing, and CI](labs/12-secrets-signing-and-ci.md) — SOPS secrets, unit tests, provenance/cosign, and chart-testing
- [ ] [13. Capstone: a three-tier release](labs/13-capstone.md) — umbrella chart, hooks, secrets, probes, CI, and publishing

### Stage 5 — Production and advanced topics (extra tools: helmfile in Lab 17)

- [ ] [14. Consuming third-party charts](labs/14-consuming-third-party-charts.md) — repositories, minimal overrides, diffing, post-rendering with Kustomize, and rollback
- [ ] [15. CRDs and operators](labs/15-crds-and-operators.md) — the `crds/` directory, cert-manager, upgrade traps, and ordering
- [ ] [16. Production hardening and chart best practices](labs/16-production-hardening-and-best-practices.md) — Pod Security restricted, PDB, NetworkPolicy, helm-docs, and kubeconform
- [ ] [17. Many releases: Helmfile (and Argo CD ApplicationSet)](labs/17-many-releases-helmfile-and-applicationset.md) — Helmfile orchestration, environments, DAG dependencies, label filtering, and Argo CD ApplicationSet
- [ ] [18. Helm internals and advanced operations](labs/18-helm-internals-and-advanced-operations.md) — release Secrets, 3-way merge patch, `--take-ownership`, deprecated APIs (`mapkubeapis`), and Helm 4 SSA

## If you get stuck

Most problems learners hit are one of these:

| Symptom | Likely cause and fix |
| --- | --- |
| `Error: Kubernetes cluster unreachable` or resources appear in the wrong cluster | Wrong kubectl context. Run `kubectl config current-context` and switch with `kubectl config use-context kind-helm-lab` (or `k3d-helm-lab`). |
| `Error: path "./charts/nginx-demo" not found` | You are not in the repository root. `cd` back to the `helm-lab` folder. |
| First `helm install ... --wait` fails with `context deadline exceeded` | The image is still downloading. Check with `kubectl get pods -n helm-lab` and `kubectl describe pod ...`; rerun with a longer `--timeout 300s`. |
| `YAML parse error` or `did not find expected '-' indicator` | Indentation in a template. Render with `helm template demo-dev ./charts/nginx-demo --debug` to see the generated YAML and the line number. |
| `cannot re-use a name that is still in use` | The release already exists. Use `helm upgrade` instead, or `helm uninstall <name> -n helm-lab` first. |
| `another operation (install/upgrade/rollback) is in progress` | A previous command was interrupted. See [Lab 10, Part D5](labs/10-hooks-and-failure-recovery.md). |
| `bind: address already in use` on `port-forward` | Another port-forward is still running. Stop it (`kill %1` or Ctrl+C), or use another local port such as `8081:80`. |
| An upgrade "forgot" your dev settings (replicas, page, env vars) | Upgrades with `--set` start from chart defaults. Always add `--reset-values -f ./charts/nginx-demo/values-dev.yaml` (explained in Lab 3). |
| Your files differ from the lab and you can't see why | Compare with the reference: `git diff lab-NN-complete -- charts/nginx-demo` (NN = the lab you just finished). |

Each lab also links an `-explained.md` page with the reasoning behind every step and a walkthrough of its "Break it and recover" exercise.

## Checkpoints and how to use this repository

This repository includes prebuilt, cluster-verified reference tags for every milestone in the learning path.
Use them for their **charts** (compare or restore with `-- charts`). The lab instructions saved in a tag are
older than the ones on `main`, so always read the labs from `main` or your practice branch.

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

1. **Start from the clean scaffold** with the branch from [Start here, step 3](#start-here).

2. Follow the labs in order, from `labs/00-chart-creation.md` to `labs/18-helm-internals-and-advanced-operations.md`.
3. Test commands against your cluster and commit your progress as you complete each lab:

   ```bash
   git commit -am "Complete my lab 1"
   ```

4. **Compare against the reference solution at any time:**

   ```bash
   # See how your chart compares to the official solution:
   git diff lab-01-complete -- charts
   ```

5. **Look at the fully completed reference anytime** (commit your work first, then come back):

   ```bash
   git switch main
   git switch my-learning
   ```

#### Approach 2: Jump directly into a specific lab

Want to practice a specific topic (e.g., Lab 4: Template Logic or Lab 6: ConfigMaps) without completing prior labs?

1. Create a branch from `main` and restore the charts from the prerequisite checkpoint (same pattern as
   [Start here, step 3](#start-here), with a different tag):

   ```bash
   # To start Lab 4, start from Lab 3's completion:
   git switch -c practice-lab-04 main
   git restore --source=lab-03-complete --staged --worktree -- charts ct ct.yaml helmfile .github/workflows/chart-ci.yaml
   git commit -m "Start Lab 4 from lab-03-complete"
   ```

   For Lab 6 use `lab-05-complete`; for Lab 10 use `extension-storage-complete` (the state after the
   four extensions). In general, start Lab NN from the tag of the lab before it.

2. Follow the lab guide, make your changes, and test.
3. Compare your result with the completion checkpoint:

   ```bash
   git diff lab-04-complete -- charts
   ```

> [!NOTE]
> Each tag `lab-NN-complete` marks the reference state at the completion of Lab NN. When practicing and creating checkpoint tags locally, name your tags `my-lab-NN-complete` (e.g., `git tag my-lab-01-complete`) so you do not collide with the repository's reference tags.

#### Approach 3: Practice in a separate folder via Git worktree (Zero conflict)

If you want to keep this repo as your read-only manual while coding in an independent directory:

```bash
# Create an isolated practice workspace with its own branch, then reset its charts to the scaffold:
git worktree add ../helm-lab-practice -b my-practice main
cd ../helm-lab-practice
git restore --source=lab-00-start --staged --worktree -- charts ct ct.yaml helmfile .github/workflows/chart-ci.yaml
git commit -m "Start from the lab-00-start chart"

# Work through labs, run cluster tests, and commit freely in this folder!
```

When you are done:

```bash
cd ../helm-lab   # back to this repository
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
