# Lab 4: Template logic — Explained

[Back to Lab 4: Template logic](04-template-logic.md)

---

## Overview

In Lab 4, you mastered Go template control structures: context scoping (`.` vs `$`), loops (`range`), conditionals (`with`), type quoting, and whitespace trimming (`{{-` and `nindent`).

Below are in-depth explanations and answers for the questions posed in the **Explain** section.

---

### Question 1: What does `.` mean inside `with` and `range`?

#### TL;DR
In Go templates, the dot (`.`) represents the **current execution context (scope)**. Inside a `with` or `range` block, the dot is **re-scoped (shadowed)** to the specific object or element being iterated over, not the root Helm context.

#### Deep Dive & Mechanism
1. **The Root Context:**
   - At the top level of a template, `.` represents the root context containing `.Values`, `.Release`, `.Chart`, `.Files`, and `.Capabilities`.
2. **Re-scoping with `with`:**
   ```gotemplate
   {{- with .Values.resources }}
     # Inside this block, . is no longer the root context!
     # . is now strictly .Values.resources
     limits: {{ .limits }}
   {{- end }}
   ```
3. **Re-scoping with `range`:**
   ```gotemplate
   {{- range $name, $value := .Values.extraEnv }}
     # Inside this loop, . is set to $value (the current item).
     # Trying to access .Release.Name here fails because $value has no field named "Release"!
   {{- end }}
   ```
4. **The Dollar Sign (`$`) Solution:**
   - Go templates reserve `$` to **always reference the root context**, regardless of how deeply nested your `with` or `range` blocks are.
   - Therefore, inside any loop or conditional, use **`$.Release.Name`** or **`$.Values.global`** to safely reference top-level variables.

---

### Question 2: Why must an environment variable value be rendered as a string?

#### TL;DR
In Kubernetes API specifications, the `value` field of a container `env` item (`EnvVar`) is strictly typed as a **string** (`string`), not a boolean, integer, or float.

#### Deep Dive & Mechanism
- Look at the Kubernetes OpenAPI schema for `v1.EnvVar`:
  ```yaml
  name: <string>
  value: <string>  # NOT any type!
  ```
- If your `values.yaml` contains:
  ```yaml
  extraEnv:
    FEATURE_ENABLED: false
    PORT: 8080
  ```
- And your template outputs:
  ```yaml
  env:
    - name: FEATURE_ENABLED
      value: false  # Parsed by YAML as boolean
    - name: PORT
      value: 8080   # Parsed by YAML as integer
  ```
- The Kubernetes API server will reject the manifest with a validation error:
  ```text
  spec.template.spec.containers[0].env[0].value: Invalid value: "boolean": expected string, got boolean
  ```
- **The Solution:** Always pipe variable values through `quote` or `toString | quote`:
  ```gotemplate
  value: {{ $value | quote }}
  ```
  This ensures output is rendered with double quotes (`value: "false"`, `value: "8080"`).

---

### Question 3: What does the leading dash in `{{-` remove?

#### TL;DR
The leading dash `{{-` strips all **preceding whitespace and newlines** immediately before the template tag. Similarly, `-}}` strips all following whitespace and newlines.

#### Deep Dive & Mechanism
1. **The Whitespace Problem in YAML:**
   - YAML is indentation-sensitive.
   - Every Go template tag (`{{ if ... }}`, `{{ end }}`) leaves behind an invisible blank newline in the rendered output if whitespace trimming is not used.
   - Example without trimming:
     ```gotemplate
     spec:
       {{ if .Values.enabled }}
       replicas: 1
       {{ end }}
     ```
     Renders as:
     ```yaml
     spec:

       replicas: 1

     ```
2. **Whitespace Trimming Syntax:**
   - `{{-` : Removes all whitespace/newlines to the **left**.
   - `-}}` : Removes all whitespace/newlines to the **right**.
3. **The `nindent` Function:**
   - When injecting blocks of YAML (e.g., using `toYaml`), `nindent N` writes a newline first, then indents each line by `N` spaces:
     ```gotemplate
     resources:
       {{- toYaml . | nindent 12 }}
     ```
   - Combining `{{-` with `nindent` ensures clean, perfectly aligned indentation without orphan blank lines.

---

## Break It and Recover — Detailed Walkthrough

The "Break it and recover" exercises simulate the most common real-world template bugs in Helm: context scoping errors and YAML whitespace indentation errors.

---

### Challenge 1: Scoping Loss Inside `range` (`.Release.Name` vs `$.Release.Name`)

#### 1. What to Break
In `charts/nginx-demo/templates/deployment.yaml`, temporarily edit the `extraEnv` loop to reference `.Release.Name` inside the `range` block:

```yaml
          {{- with .Values.extraEnv }}
          env:
            {{- range $name, $value := . }}
            - name: {{ $name | quote }}
              value: {{ .Release.Name | quote }}
            {{- end }}
          {{- end }}
```

#### 2. Run the Command
Attempt to render the chart using the dev values:
```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
```

#### 3. The Error Observed
```text
Error: template: nginx-demo/templates/deployment.yaml:26:32: executing "nginx-demo/templates/deployment.yaml" at <.Release.Name>: can't evaluate field Release in type interface {}
```

#### 4. Why This Failed
- Go templates use the dot `.` as a dynamic cursor representing the **current local scope**.
- Before `with`, `.` is the root context containing `Release`, `Values`, `Chart`, etc.
- Inside `{{- with .Values.extraEnv }}`, `.` shifts to the `extraEnv` map.
- Inside `{{- range $name, $value := . }}`, the dot `.` is re-scoped to the current iteration's value (a primitive string like `"dev"` or `"false"`).
- Evaluating `.Release.Name` fails because a string has no field or method named `Release`.

#### 5. How to Recover
In Go templates, the dollar sign `$` is reserved to always point to the **global root context**, no matter how deeply nested your loops or conditionals are.

Change `.Release.Name` to `$.Release.Name`:
```yaml
          {{- with .Values.extraEnv }}
          env:
            {{- range $name, $value := . }}
            - name: {{ $name | quote }}
              value: {{ $.Release.Name | quote }}
            {{- end }}
          {{- end }}
```

Re-run:
```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
```

*Rendered output:*
```yaml
          env:
            - name: "FEATURE_ENABLED"
              value: "demo-dev"
            - name: "LAB_NAME"
              value: "demo-dev"
```

#### 6. Restore Clean State
Restore the intended output using the loop variable `$value`:
```yaml
          {{- with .Values.extraEnv }}
          env:
            {{- range $name, $value := . }}
            - name: {{ $name | quote }}
              value: {{ $value | quote }}
            {{- end }}
          {{- end }}
```

---

### Challenge 2: Indentation Corruption (`nindent` and YAML Nesting)

#### 1. What to Break
In `charts/nginx-demo/templates/deployment.yaml`, intentionally set the wrong indentation level for `resources` by changing `nindent 12` to `nindent 8`:

```yaml
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 8 }}
          {{- end }}
```

#### 2. Run the Command
```bash
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
```

#### 3. The Error Observed
```text
Error: YAML parse error on nginx-demo/templates/deployment.yaml: error converting YAML to JSON: yaml: line 28: mapping values are not allowed in this context
```

#### 4. Why This Failed
- Go templates perform raw string substitution before any YAML parsing occurs. Helm does not "know" what valid Kubernetes YAML looks like until the template finishes rendering.
- In `deployment.yaml`, the container item `- name: nginx` is indented with 8 spaces, and its attributes (`image:`, `ports:`, `resources:`) are indented with 10 spaces.
- With `nindent 8`, the nested contents (`requests:`, `limits:`) are placed at 8 spaces—the same level as the container list item!
- As a result, `requests:` is parsed as a sibling key to `- name: nginx` instead of a child of `resources:`, generating invalid YAML.

#### 5. How to Recover
Calculate the required indentation:
- `spec:` (7 spaces or column 0)
- `  template:` (2 spaces)
- `    spec:` (4 spaces)
- `      containers:` (6 spaces)
- `        - name: nginx` (8 spaces)
- `          resources:` (10 spaces)
- `            requests:` (12 spaces) -> **requires `nindent 12`**

Restore `nindent 12` in `templates/deployment.yaml`:
```yaml
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

Verify with:
```bash
helm lint ./charts/nginx-demo
helm template demo-dev ./charts/nginx-demo -f ./charts/nginx-demo/values-dev.yaml
```

---

## Key Takeaways

| Directive | Rule |
| :--- | :--- |
| `.` | Current local scope. Changes inside `with` and `range`. |
| `$` | Permanent global root scope. Always points to `.Release`, `.Values`, etc. |
| `quote` | Always quote container environment variables (`value: {{ $val \| quote }}`). |
| `{{-` / `nindent` | Eliminates empty lines and guarantees correct YAML indentation. |
