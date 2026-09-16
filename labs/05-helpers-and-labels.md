# Lab 5: Write a label once, reuse it everywhere

**Start:** You have completed Lab 4 and have `values-dev.yaml`.
**Goal:** Understand a Helm helper by using one to remove repeated template code.

Run commands from the repository root. Steps 1–5 work without a cluster.
Step 6 needs the `demo-dev` release running in namespace `helm-lab`.

If your chart already contains these helpers, read each step and compare it with
your files. Do not add a second definition with the same name. If you have done
later labs, keep their settings and helpers: edit only the sections shown here.

## First, understand the three words

| Word | Plain meaning | Example |
| --- | --- | --- |
| Label | A tag attached to a Kubernetes object | A Pod has `app: demo-dev` |
| Selector | A rule that matches objects by their labels | A Service sends traffic to Pods with `app: demo-dev` |
| Helper | A named piece of template code you can reuse | Write the `app` label once, then insert it in several places |

Today, your templates repeat this line:

```gotemplate
app: {{ .Release.Name }}
```

For release `demo-dev`, Helm turns it into:

```yaml
app: demo-dev
```

The same label connects three parts of your application:

```text
Deployment selector: app=demo-dev ── matches ──┐
                                             │
                                      Pod: app=demo-dev
                                             │
Service selector:    app=demo-dev ── matches ──┘
```

The Deployment uses the match to identify its Pods. The Service uses the match
to find Pods to send traffic to. A Pod may have extra labels and still match.

**Our first change:** put the repeated line in one helper. The generated label
will stay the same.

## Step 1: Give the repeated line a name

Open or create `charts/nginx-demo/templates/_helpers.tpl`.
Add this definition if it is not already there:

```gotemplate
{{- define "nginx-demo.selectorLabels" -}}
app: {{ .Release.Name }}
{{- end -}}
```

Read it as: “Save this piece of template code under the name
`nginx-demo.selectorLabels`.”

- `define` starts the helper; `end` finishes it.
- The line between them is the text the helper produces.
- `nginx-demo.selectorLabels` is a name we chose, not a built-in Helm command.
- `_helpers.tpl` holds reusable templates. Helm does not turn this file into a
  separate Kubernetes object.

Creating a helper does not insert its output anywhere yet. Next, we call it.

## Step 2: Use the helper in the Service

Open `charts/nginx-demo/templates/service.yaml`.
Find the `selector` under `spec` and replace this:

```gotemplate
  selector:
    app: {{ .Release.Name }}
```

with this:

```gotemplate
  selector:
    {{- include "nginx-demo.selectorLabels" . | nindent 4 }}
```

Here is how to read that new line, from left to right:

| Part | What it does |
| --- | --- |
| `include "nginx-demo.selectorLabels"` | Runs the helper and returns its text |
| `.` | Gives the helper the current data, including `.Release.Name` |
| `\|` | Passes that text to the next function |
| `nindent 4` | Starts a new line and adds four spaces before each line of text |

The `-` in `{{-` removes whitespace before the template expression. Then
`nindent` supplies the newline and spaces needed for the YAML output.

**Check this small change now:**

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml --show-only templates/service.yaml
```

Near the bottom, you should still see:

```yaml
  selector:
    app: demo-dev
```

You changed how the YAML is produced, but the Service selector is the same.
That is the purpose of this first step.

## Step 3: Reuse it in the Deployment

Open `charts/nginx-demo/templates/deployment.yaml`.
Replace the label below `spec.selector.matchLabels` with the helper call:

```gotemplate
spec:
  # Keep the other fields already in your file.
  selector:
    matchLabels:
      {{- include "nginx-demo.selectorLabels" . | nindent 6 }}
```

This is a section of the file, not a complete replacement. Keep fields such as
`replicas`, your container settings, and any work from later labs.

Next, replace the labels under `spec.template.metadata.labels` with:

```gotemplate
  template:
    metadata:
      labels:
        {{- include "nginx-demo.selectorLabels" . | nindent 8 }}
```

Keep any existing `annotations` beside `labels`.
This location describes the labels that new **Pods** will receive.

Why 6 spaces in one place and 8 in another? The helper's output must sit one
YAML level inside its parent key. Each level in these files uses two spaces:

| Location | Spaces before the generated `app:` line |
| --- | --- |
| Service `spec.selector` | 4 |
| Deployment `spec.selector.matchLabels` | 6 |
| Deployment `spec.template.metadata.labels` | 8 |

Render the Deployment:

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml --show-only templates/deployment.yaml
```

**Check:** both `matchLabels` and the Pod's `labels` contain `app: demo-dev`.
You now have one definition supplying the matching label in three places.

## Step 4: Add useful information to the labels

We also want labels that answer questions such as “Which application version is
this?” Those labels help us inspect objects, but we will not use them to select Pods.

Add this second helper to `_helpers.tpl`, below the first:

```gotemplate
{{- define "nginx-demo.labels" -}}
{{ include "nginx-demo.selectorLabels" . }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
```

This helper calls the first helper, then adds four more labels. For this lab's
chart version, the result is:

```yaml
app: demo-dev
app.kubernetes.io/name: nginx-demo
app.kubernetes.io/instance: demo-dev
app.kubernetes.io/version: "1.30.4"
app.kubernetes.io/managed-by: Helm
```

The version comes from `appVersion` in `Chart.yaml`; yours may differ.
`quote` puts quotation marks around it so YAML treats it as text.

Now use the larger helper on the objects' **metadata**. At the top of both
`deployment.yaml` and `service.yaml`, add or update `metadata.labels`:

```gotemplate
metadata:
  # Keep the existing name here.
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
```

Also change the Pod labels from Step 3 to the larger helper:

```gotemplate
  template:
    metadata:
      labels:
        {{- include "nginx-demo.labels" . | nindent 8 }}
```

Use this table to check all five locations:

| File and location | Helper to use |
| --- | --- |
| Deployment `metadata.labels` | `nginx-demo.labels` |
| Deployment `spec.template.metadata.labels` | `nginx-demo.labels` |
| Service `metadata.labels` | `nginx-demo.labels` |
| Deployment `spec.selector.matchLabels` | `nginx-demo.selectorLabels` |
| Service `spec.selector` | `nginx-demo.selectorLabels` |

**Why two helpers?** The Deployment's selector cannot be changed after the
Deployment is created. Kubernetes calls this *immutable*. If the selector
included an application version, updating that version would change the selector
and Kubernetes would reject the upgrade. Keep the version in metadata labels.

The Service's own `metadata.labels` describe the Service; its `spec.selector`
chooses Pods. Adding metadata labels to the Service does not change its routing.

## Step 5: Reuse the resource names too

You have learned the main idea. Apply the same pattern to the two resource names.
Add these helpers to `_helpers.tpl` if they do not already exist:

```gotemplate
{{- define "nginx-demo.deploymentName" -}}
{{- printf "%s-deployment" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "nginx-demo.serviceName" -}}
{{- printf "%s-service" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
```

For the first helper:

1. `printf "%s-deployment" .Release.Name` joins `demo-dev` and `-deployment`.
2. `trunc 63` keeps at most 63 characters.
3. `trimSuffix "-"` removes a dash if truncation leaves one at the end.

We use a 63-character naming convention here. Kubernetes naming limits depend
on the resource type; 63 is not a universal limit for every Kubernetes name.
For the short release name `demo-dev`, these functions leave the name unchanged.

In the Deployment's top-level `metadata`, use:

```gotemplate
  name: {{ include "nginx-demo.deploymentName" . }}
```

In the Service's top-level `metadata`, use:

```gotemplate
  name: {{ include "nginx-demo.serviceName" . }}
```

These helpers return a single value on the same line, so no `nindent` is needed.

## Step 6: Check the result, then upgrade

### Check locally

```bash
helm lint ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
```

Before continuing, confirm:

- [ ] Lint reports zero failed charts.
- [ ] Names are still `demo-dev-deployment` and `demo-dev-service`.
- [ ] Both selectors contain only `app: demo-dev`.
- [ ] Deployment, Service, and Pod-template metadata contain the five labels.
- [ ] Your existing container settings are still present.

### Check in the cluster

If you are reading without a cluster, stop here and return to this section later.
Otherwise, upgrade the existing lab release:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
kubectl get deployment demo-dev-deployment -n helm-lab -o jsonpath='{.spec.selector.matchLabels}{"\n"}'
kubectl get pods -n helm-lab -l app=demo-dev --show-labels
```

Expect selector output `{"app":"demo-dev"}` and Pods with the new labels.
The Deployment keeps its name. Changing its Pod-template labels can trigger a
rollout, so replacement Pods are expected when these labels are first added.

Check that you can still reach NGINX:

```bash
kubectl port-forward -n helm-lab service/demo-dev-service 8080:80
```

Leave that running. In another terminal:

```bash
curl --fail http://localhost:8080
```

Expect the NGINX welcome page, or your custom page if you have completed Lab 6.
If you changed `service.port` in another exercise, replace the final `80` in the
port-forward command with that Service port. Stop port-forwarding with Ctrl+C.

## Small experiment: why the version stays out of selectors

1. Temporarily add this line inside `nginx-demo.selectorLabels`:

   ```gotemplate
   app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
   ```

2. Render the Deployment locally using the command from Step 3.
3. Look at `spec.selector.matchLabels`. It now asks for both the `app` label and
   a specific version. This differs from the existing Deployment's selector.
4. **Do not upgrade this experimental version.** Remove the added line from
   `selectorLabels`, leaving the original version line in `nginx-demo.labels`.
5. Render again. Confirm that `matchLabels` is back to only `app: demo-dev`.

The lesson: Helm can produce valid YAML that Kubernetes would reject as an
update to an existing object.

## Check your understanding

Try answering before opening the answers:

1. What is the difference between `define` and `include`?
2. Why do the Pods get five labels while the selectors use only one?
3. What does `nindent 8` do?
4. Why do we keep the same resource names during this change?

<details>
<summary>Answers</summary>

1. `define` saves a named template. `include` runs it and returns its text.
2. The extra labels describe the application. The single `app` label is enough
   for these selectors and stays the same across application versions.
3. It adds a newline and eight spaces before each line of the helper's output.
4. A new resource name identifies a different object. Keeping the names avoids
   accidentally asking Helm to replace resources while reorganizing template code.

</details>

## Finish

Save your working changes and observations. Mark Lab 5 complete in the README,
commit your work, and create `lab-05-complete` if that checkpoint does not already
exist. Keep `demo-dev` installed for Lab 6.

Optional reading: [Helm named templates](https://helm.sh/docs/v3/chart_template_guide/named_templates/)
and [Kubernetes Deployment selectors](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#label-selector-updates).

Next: [ConfigMaps and rollouts](06-configmaps-and-rollouts.md).
