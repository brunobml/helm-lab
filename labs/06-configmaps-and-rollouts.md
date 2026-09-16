# Lab 6: Change the web page and roll out new Pods

**Start:** Lab 5 complete, including its label and name helpers.
**Goal:** Serve your own HTML from NGINX, then change that HTML and watch
Kubernetes replace the Pods automatically.

Run every command from the repository root. Steps 1–4 only need Helm. From
Step 5 onward, you need your lab cluster and the `demo-dev` release in namespace
`helm-lab`.

If you already have these settings, compare them with the examples instead of
adding duplicates. Keep work from later labs; the Deployment snippets below
show only the sections to edit.

## What you are building

You will give NGINX a different `index.html` without building a new container image.

```text
pageContent in your values file
          │ Helm renders the text
          ▼
ConfigMap: demo-dev-page
  data key: index.html
          │ Kubernetes makes the data available as a file
          ▼
NGINX container: /usr/share/nginx/html/index.html
          │ NGINX serves the file
          ▼
Your browser or curl sees the custom page
```

| Term | Meaning in this lab |
| --- | --- |
| ConfigMap | A Kubernetes object that stores non-secret configuration, such as our HTML text |
| Volume | The Pod's source of files; here, it reads a ConfigMap |
| Volume mount | The folder where a container can read those files |
| Checksum | A fingerprint calculated from text; changing the text changes the fingerprint |
| Rollout | Kubernetes replaces Pods to apply a changed Deployment Pod template |

First make the page available. Then add the checksum that connects page changes
to Pod replacement.

## Step 1: Write your page in values

Open `charts/nginx-demo/values.yaml`. Add or update this **top-level** value,
aligned with `replicaCount`, not nested under `service` or `image`:

```yaml
pageContent: |
  <h1>Hello from Helm Lab</h1>
  <p>This page comes from a ConfigMap.</p>
```

The `|` means “the indented lines below are one text value, keeping line breaks.”
The HTML lines need two spaces before them.

Now open `charts/nginx-demo/values-dev.yaml`. Add or update its `pageContent`
to the same text for this exercise. Keep the file's other settings.

**Why both files?** `values.yaml` supplies the default. We deploy with
`-f values-dev.yaml`, so a `pageContent` in the dev file overrides the default.
From Step 6 onward, edit the **dev file** to change the deployed page.

## Step 2: Put the page in a ConfigMap

Create or update `charts/nginx-demo/templates/configmap.yaml`:

```gotemplate
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-page
  labels:
    {{- include "nginx-demo.labels" . | nindent 4 }}
data:
  index.html: |
    {{- .Values.pageContent | nindent 4 }}
```

Read the important parts:

- `name` becomes `demo-dev-page` for our release.
- `data` contains the text entries stored in the ConfigMap.
- `index.html` is the entry name. It will become the filename when mounted.
- `.Values.pageContent` supplies the HTML you wrote.
- `nindent 4` adds a newline and four spaces before each HTML line, placing it
  inside the `index.html` text value.

**Check before continuing:**

```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml --show-only templates/configmap.yaml
```

The output should contain this section:

```yaml
data:
  index.html: |
    <h1>Hello from Helm Lab</h1>
    <p>This page comes from a ConfigMap.</p>
```

If the text differs, check the dev override from Step 1. This command renders
locally; it has not created or changed anything in the cluster.

## Step 3: Make NGINX read the ConfigMap as a file

Open `charts/nginx-demo/templates/deployment.yaml`. Make two related edits.

### 3a. Add a volume to the Pod

Under `spec.template.spec`, add this `volumes` block **alongside `containers`**:

```gotemplate
      volumes:
        - name: html
          configMap:
            name: {{ .Release.Name }}-page
```

This says: “The Pod has a volume called `html`, populated from `demo-dev-page`.”
The ConfigMap name must match the one from Step 2.

### 3b. Mount that volume in the NGINX container

Inside the container named `nginx`, add `volumeMounts` **alongside `image` and
`ports`**:

```yaml
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
```

This says: “Make the `html` volume visible in NGINX's web-page folder.”
`readOnly` prevents the container from writing through this mount.

Here is how the two pieces fit together. This is a placement guide, not a
replacement for your whole Deployment:

```gotemplate
spec:
  template:
    spec:
      containers:
        - name: nginx
          # Keep image, ports, env, resources, and other container settings here.
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
              readOnly: true
      volumes:
        - name: html
          configMap:
            name: {{ .Release.Name }}-page
```

The two `name: html` entries connect the mount to the volume. The ConfigMap's
`index.html` entry appears at `/usr/share/nginx/html/index.html`.

Mount the directory as shown; do not add `subPath` for this exercise. The mounted
folder hides the image's original files at that location while the mount is active.

## Step 4: Tell Kubernetes when to replace the Pods

Updating a ConfigMap by itself does not change the Deployment's Pod template.
We will put the ConfigMap's checksum in that template so a page change also
becomes a Pod-template change.

Find **`spec.template.metadata`** in `deployment.yaml`. Add `annotations`
alongside its `labels`:

```gotemplate
  template:
    metadata:
      annotations:
        checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}
      labels:
        {{- include "nginx-demo.labels" . | nindent 8 }}
```

If `annotations` already exists, add the checksum inside it. Keep its other entries.

Read the checksum expression in three parts:

| Part | What it does |
| --- | --- |
| `print $.Template.BasePath "/configmap.yaml"` | Builds the template path for this chart's ConfigMap |
| `include (...) .` | Renders that template using the current chart and release data |
| `\| sha256sum` | Calculates a fingerprint of the rendered text |

`.` passes the current data, just as it did with helpers in Lab 5. Here `$`
refers to the root template context. `checksum/config` is an annotation name we
chose; Kubernetes reacts to the Pod-template change, not to a special meaning
of this name.

The checksum covers the **whole rendered ConfigMap**, including metadata. In
this experiment, we will change only the HTML to make the cause easy to observe.

```text
HTML changes → ConfigMap text changes → checksum changes
             → Pod template changes → Kubernetes rolls out new Pods
```

**Placement matters:** top-level `metadata.annotations` describes the
Deployment itself. `spec.template.metadata.annotations` describes the Pods it
creates. Put the checksum in the second location.

Render the Deployment to check your edits:

```bash
helm lint ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml --show-only templates/deployment.yaml
```

Look for `checksum/config` under `spec.template.metadata.annotations`, a long
hexadecimal checksum value, and both volume blocks from Step 3.

## Step 5: Deploy and read your first page

Apply the working chart to the existing lab release:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
kubectl rollout status deployment/demo-dev-deployment -n helm-lab --timeout=120s
```

Expect the upgrade and rollout to finish successfully. Check the stored HTML
and the actual file inside a running container:

```bash
kubectl get configmap demo-dev-page -n helm-lab -o yaml
kubectl exec -n helm-lab deployment/demo-dev-deployment -- cat /usr/share/nginx/html/index.html
```

Both should contain your heading and paragraph.

In **terminal A**, start a connection to the Service:

```bash
kubectl port-forward -n helm-lab service/demo-dev-service 8080:80
```

Leave it running. In **terminal B**, request the page:

```bash
curl --fail http://localhost:8080
```

Expected response:

```html
<h1>Hello from Helm Lab</h1>
<p>This page comes from a ConfigMap.</p>
```

You can also open `http://localhost:8080` in a browser. If you changed
`service.port` in another lab, replace the final `80` in the port-forward command
with that Service port.

Stop port-forwarding with Ctrl+C in terminal A before the next step.

## Step 6: Change the page and prove a rollout happened

### 6a. Record the current state

Run these commands and copy their output into your notes:

```bash
kubectl get pods -n helm-lab -l app=demo-dev -o custom-columns='NAME:.metadata.name,UID:.metadata.uid'
kubectl get deployment demo-dev-deployment -n helm-lab -o go-template='{{ index .spec.template.metadata.annotations "checksum/config" }}{{ "\n" }}'
```

The first lists Pod names and their unique IDs. The second prints the checksum.
These are your **before** observations.

### 6b. Edit only the dev page content

In `charts/nginx-demo/values-dev.yaml`, replace the existing `pageContent` with:

```yaml
pageContent: |
  <h1>Hello from Updated Helm Lab</h1>
  <p>I changed this page with helm upgrade.</p>
```

Keep all other settings unchanged. Save the file, then deploy it:

```bash
helm upgrade demo-dev ./charts/nginx-demo -n helm-lab --reset-values -f ./charts/nginx-demo/values-dev.yaml --wait --timeout 120s
kubectl rollout status deployment/demo-dev-deployment -n helm-lab --timeout=120s
```

### 6c. Compare the result

Run both commands from 6a again. Expect:

| Observation | Expected change |
| --- | --- |
| Checksum | A different value |
| Ready application Pods | Replacement Pods with new names and IDs |
| Application image | The same image as before |

Old Pods may briefly remain while terminating. You are looking for the new
running Pods after the rollout finishes.

Restart port-forwarding using Step 5 and curl the page again. Expect the updated
heading and paragraph. Stop port-forwarding afterward.

**You have checked two different things:** curl proves that the page changed;
the checksum and replacement Pods show that the change triggered a rollout.
`kubectl rollout status` alone is not enough proof: it can report success when
an existing rollout is already complete.

## Optional experiment: put the checksum in the wrong place

Try this after the main exercise works, using the disposable lab release.

1. Move `checksum/config` from `spec.template.metadata.annotations` to the
   Deployment's top-level `metadata.annotations`. Keep unrelated annotations.
2. Upgrade using the command from 6b and wait for completion. Removing the
   annotation from the Pod template can itself cause a rollout, so **wait for
   that rollout before recording your new baseline**.
3. Record the Pod names and IDs using the first command from 6a.
4. Change only the heading in `values-dev.yaml`. Upgrade again.
5. Inspect the Deployment with `kubectl get deployment demo-dev-deployment -n
   helm-lab -o yaml`. The top-level checksum changes, but this change alone does
   not replace the Pods. Compare their names and IDs with step 3.
6. Move the checksum back under `spec.template.metadata.annotations`, remove
   the misplaced copy, and upgrade. Verify the rollout and page as before.

The mounted ConfigMap files can update after a delay even without Pod
replacement. NGINX may therefore serve the changed page while the Pod IDs stay
the same. That is why this lab checks both the page and the Pods.

## If something does not work

| Symptom | What to check first |
| --- | --- |
| Helm reports a YAML error | Check spaces around `data`, HTML lines, `volumes`, and `volumeMounts` |
| The rendered HTML is still the old text | Edit `pageContent` in `values-dev.yaml`; it overrides the default |
| Pod cannot mount the ConfigMap | Compare the ConfigMap name with `volumes[].configMap.name`; inspect Pod events |
| NGINX serves its original welcome page | Check that the mount is inside the `nginx` container at `/usr/share/nginx/html` |
| curl cannot connect after an upgrade | Restart port-forwarding; its previous Pod may have been replaced |
| Page changes but Pods do not | Check that the checksum is inside the Pod template and compare its before/after values |

For Pod startup or mount failures:

```bash
kubectl get pods -n helm-lab -l app=demo-dev
kubectl describe pods -n helm-lab -l app=demo-dev
```

Read the Events section near the bottom for the failing resource or operation.

## Check your understanding

1. How does `pageContent` become a file inside NGINX?
2. What connects `volumeMounts` to `volumes`?
3. Why does the checksum belong under `spec.template.metadata`?
4. Does seeing updated HTML prove that a Pod was replaced?

<details>
<summary>Answers</summary>

1. Helm puts the text into a ConfigMap entry named `index.html`. Kubernetes
   exposes that entry through a volume mounted in NGINX's web folder.
2. Their matching volume name, `html`.
3. Changing that part of the Deployment changes the template used to create
   Pods, which triggers a rollout.
4. No. Mounted ConfigMap files can update in an existing Pod. Compare Pod IDs
   and the checksum as well as checking the page.

</details>

## Finish

- [ ] Your custom HTML is visible through the Service.
- [ ] Changing only dev `pageContent` changes the checksum and replaces the Pods.
- [ ] The checksum is back in the correct location after any experiment.
- [ ] Port-forwarding is stopped; `demo-dev` stays installed for Lab 7.

Record your observations, mark Lab 6 complete in the README, and commit your
working changes. Create `lab-06-complete` if that checkpoint does not already exist.

Optional reading: [Kubernetes ConfigMaps](https://kubernetes.io/docs/concepts/configuration/configmap/)
and [Helm's rollout checksum example](https://helm.sh/docs/v3/howto/charts_tips_and_tricks/#automatically-roll-deployments).

Next: [Validation and tests](07-validation-and-tests.md).
