# Helm Lab

Learn Helm by evolving one small NGINX application, one lab at a time.
The working chart starts with a Deployment and Service. You implement the later
features yourself; lab instructions explain what to change and how to verify it.

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

For a local cluster, install Docker and [kind](https://kind.sigs.k8s.io/docs/user/quick-start/),
then run:

```bash
kind create cluster --name helm-lab --wait 120s
kubectl config use-context kind-helm-lab
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

Continue with [Lab 1](labs/01-first-chart.md) to install the application.

## Learning path

Check off a lab when its verification steps pass and you can answer its questions.
If you already completed the original fundamentals, use Labs 1–3 as a short review.

- [ ] [1. First chart](labs/01-first-chart.md) — connect values, templates, and running resources
- [ ] [2. Release lifecycle](labs/02-release-lifecycle.md) — upgrade, inspect, rollback, and recover
- [ ] [3. Values and environments](labs/03-values-and-environments.md) — precedence and separate releases
- [ ] [4. Template logic](labs/04-template-logic.md) — conditionals, loops, scope, and indentation
- [ ] [5. Helpers and labels](labs/05-helpers-and-labels.md) — reuse code without breaking selectors
- [ ] [6. ConfigMaps and rollouts](labs/06-configmaps-and-rollouts.md) — change the page through Helm
- [ ] [7. Validation and tests](labs/07-validation-and-tests.md) — catch invalid inputs and test HTTP
- [ ] [8. Dependencies](labs/08-dependencies.md) — compose charts and lock versions
- [ ] [9. Packaging and GitOps](labs/09-packaging-and-gitops.md) — distribute and reconcile the chart

Optional extensions after Lab 7:

- [Networking](labs/extensions/networking.md): Service types and Ingress
- [Workload health and scaling](labs/extensions/health-and-scaling.md): probes, resources, and HPA
- [Identity and secrets](labs/extensions/identity-and-secrets.md): ServiceAccounts, RBAC, and Secret references
- [Storage and other workloads](labs/extensions/storage-and-workloads.md): persistence, Jobs, and StatefulSets

## Save your progress

There are no prebuilt completed-lab tags or solution charts. Each lab names the
checkpoint **you create after completing it**. Save the initial scaffold in a
commit first and tag that commit `lab-00-start`. For each completed lab, review
and commit your chart, lab notes, and progress checkbox, then tag that commit:

```bash
git diff
# Stage the specific files you changed, then commit them.
git commit -m "Complete lab 1: first chart"
git tag lab-01-complete
```

A Git checkpoint captures source files. Helm revisions capture a release's
cluster history; rolling back Helm does not roll back your Git files.

Inspect a checkpoint without replacing your working files:

```bash
git show lab-01-complete:charts/nginx-demo/templates/deployment.yaml
git diff lab-01-complete lab-02-complete -- charts/nginx-demo
```

To retry a completed lab, create a separate worktree from its starting tag (once
that tag exists), and use a different release name or clean up the earlier lab
release before installing. See [the lab template](labs/TEMPLATE.md) for a place
to record observations, commands, failures, and explanations.

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

If you used the dedicated kind cluster and want to remove all its resources:

```bash
kind delete cluster --name helm-lab
```

## References

- [Using Helm](https://helm.sh/docs/v3/intro/using_helm/)
- [Template guide](https://helm.sh/docs/v3/chart_template_guide/)
- [Chart format and values schemas](https://helm.sh/docs/v3/topics/charts/)

This is a learning chart. Advanced features are introduced by the labs as you
need them.
