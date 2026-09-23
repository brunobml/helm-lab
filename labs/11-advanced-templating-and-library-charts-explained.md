# Lab 11: Advanced templating and library charts — Explained

[Back to Lab 11](11-advanced-templating-and-library-charts.md)

---

## Overview

You learned where common template functions surprise you (`default`, `required`, `tpl`, `lookup`),
then extracted shared helpers into a library chart and used it through a dict-based interface.

---

### Question 1: Why did `defaultReplicas` become `5` when you set `replicas: 0`, and what would you use instead?

#### TL;DR

`default` replaces any **empty** value: `0`, `false`, `""`, `nil`, empty list or map. `0` and `false` are empty, so a deliberate `0` is discarded.

#### Deep Dive

| You want | Use |
| --- | --- |
| A default that only applies when the key is absent | Put it in `values.yaml`; drop `default` from the template |
| "Was this key set at all?" | `hasKey .Values "debug"` |
| Choose between two outputs on a boolean | `ternary "verbose" "quiet" .Values.debug` |
| First non-empty of several candidates | `coalesce .Values.name .Values.other "fallback"` |
| Safe nested access on maybe-missing maps | `.Values.team \| default dict \| dig "name" "unassigned"` |

Note that `coalesce` has the same emptiness rule as `default`. It is the right tool for
"first usable value", not for "first value that was set".

`required "message" value` fails the render when the value is `nil` or `""`. It does **not** fail on `0`,
`false`, or an empty map, which is why the library uses an explicit `fail` for its empty-data check:

```yaml
{{- if not $data -}}{{- fail "clear, actionable message" -}}{{- end -}}
```

Prefer schema validation (`values.schema.json`) for shape and type errors, `required` for missing
mandatory strings, and `fail` for cross-field rules a schema cannot express.

---

### Question 2: Why must `lab-common.configmap` receive a dict with `root`, and what would break if it took `.`?

#### TL;DR

A named template gets **one** argument. Passing `.` gives it only the current scope; a dict lets you pass the root context **and** extra parameters together.

#### Deep Dive

1. Inside `range $name, $data := ...`, `.` is the current item, so `.Release` and `.Values` no longer exist. Passing `.` would give the library a ConfigMap map instead of the release.
2. `$` always refers to the root context passed to the template, so `dict "root" $ ...` carries it through.
3. The library needs `root` for `.Release.Name`, `.Chart`, and to give `tpl` a context. Without it, `{{ .Release.Name }}` in a value would fail to render.
4. The convention: templates that only need the chart context take `.`; templates with parameters take a `dict` and document its keys in the comment above the `define`.

`tpl (toString $value) $root` also explains the output `MAX_CONN: "100"`: a ConfigMap `data` value must be a string, and `toString` turns the YAML number into one before rendering.

---

### Question 3: Why did the label refactor need to leave `nginx-demo.selectorLabels` alone?

#### TL;DR

A Deployment's `spec.selector` is **immutable**. Changing selector labels makes every upgrade of existing releases fail.

#### Deep Dive

- `nginx-demo.labels` is descriptive metadata; changing it triggers a rolling update at worst.
- `selectorLabels` feed `spec.selector.matchLabels`. Editing them yields `field is immutable` on upgrade, and only deleting the Deployment fixes it.
- The `diff - $LAB_TMP/before-dev.yaml` check is the safety net: identical output means existing releases are unaffected. Run it for every shared-helper refactor.
- Library-defined names are **global** across a chart and its dependencies (all templates share one namespace). Always prefix (`lab-common.labels`, not `labels`). A parent's `define` with the same name silently overrides a library's; this is also how a chart can customize a library default, but do it on purpose.
- Library charts are versioned and packaged like any chart: bump `lab-common`, run `helm dependency update` in consumers, and commit the new `Chart.lock`.

---

### Question 4: Where should `lookup` not be used, and why?

#### TL;DR

Anywhere rendering happens without a live API connection: `helm template`, `--dry-run=client`, `helm lint`, and GitOps renderers such as Argo CD. There `lookup` returns an empty map.

#### Deep Dive

1. With a cluster connection (`helm install`, `helm upgrade`, `--dry-run=server`), `lookup` returns real objects. That gave a stable token across upgrades.
2. Without one, the `else` branch always runs, so `randAlphaNum` produces a **new** value on every render. In Argo CD this can cause an endless out-of-sync loop and rotating secrets.
3. `lookup` also makes charts non-deterministic: the same chart and values render differently depending on cluster state, which undermines the diff and review workflow from Lab 10.
4. Good uses: check whether a CRD or Secret exists before referencing it, or preserve a generated value in a Helm-driven (non-GitOps) flow. For secrets under GitOps, use an external secret manager.

---

## Quick reference

| Task | Tool |
| --- | --- |
| Render a string from values as a template | `tpl .Values.x .` |
| Fail with a message when a string is missing | `required "msg" .Values.x` |
| Fail on any custom condition | `fail "msg"` |
| Safe nested lookup in values | `dig`, or `default dict` |
| Share helpers across charts | `type: library` chart + `dependencies` |
| Pass extra args to a named template | `include "name" (dict "root" $ "key" value)` |
| Ensure a refactor changed nothing | `helm template ... \| diff - before.yaml` |

## Common pitfalls

- `.Values.a.b` where `a` is missing is a **nil pointer** error, not a `required` failure.
- `include ... | nindent` for blocks; `template` cannot be piped.
- A library chart's `templates/` files must start with `_` unless you truly want them rendered; only `define` blocks belong there.
- Helm packages dependencies into `charts/` as `.tgz`, which is git-ignored. After a fresh clone run `helm dependency build`.

---

## Break It and Recover — Detailed Walkthrough

Lab 11 covers three templating and validation failure modes. Perform each using a temporary scratch values file (`$LAB_TMP/bad.yaml`) with `-f` so you do not modify `values-dev.yaml`.

### Scenario 1: A `tpl` Expression on a Missing Key

#### 1. What to Break

Pass a template expression in values that attempts to access a nested property (`.Values.team.name`) on a non-existent parent (`team` is not defined in `values.yaml`):

`$LAB_TMP/bad.yaml`:

```yaml
extraConfigMaps:
  settings:
    OWNER: "{{ .Values.team.name }}"
```

#### 2. Run the Command

```bash
helm template d ./charts/nginx-demo -f $LAB_TMP/bad.yaml
```

#### 3. The Error Observed

```text
Error: ... executing "gotpl" at <.Values.team.name>: nil pointer evaluating interface {}.name
```

#### 4. Why This Failed

- When `tpl` evaluates `"{{ .Values.team.name }}"`, it looks up `.Values.team`. Because `team` is not defined in `values.yaml` or `$LAB_TMP/bad.yaml`, it evaluates to `nil`.
- Evaluating `.name` on `nil` triggers a Go template nil-pointer evaluation error.
- Note that this is **not** a `required` validation failure. Go templates panic before any validation logic can run because an uninstantiated map was traversed.

#### 5. How to Recover

There are two ways to resolve this:

1. **Define the parent key:** Add `team: { name: "Platform" }` to `values.yaml`.
2. **Defensive templating (recommended for optional values):** Guard against missing maps using `default dict` and `dig`:

   ```yaml
   extraConfigMaps:
     settings:
       OWNER: '{{ .Values.team | default dict | dig "name" "unassigned" }}'
   ```

   Test rendering:

   ```bash
   helm template d ./charts/nginx-demo -f $LAB_TMP/bad.yaml --show-only templates/extra-configmaps.yaml
   ```

   *Output:* `OWNER: "unassigned"` renders cleanly without errors.

---

### Scenario 2: An Empty ConfigMap (`minProperties` vs Library `fail` Guard)

#### 1. What to Break

Supply an empty ConfigMap map under `extraConfigMaps`:

```bash
helm template d ./charts/nginx-demo --set-json 'extraConfigMaps={"empty":{}}'
```

#### 2. The Error Observed

First, schema validation halts the render:

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
nginx-demo:
- at '/extraConfigMaps/empty': minProperties: got 0, want 1
```

Now bypass schema validation to test the library chart's internal guard:

```bash
helm template d ./charts/nginx-demo --set-json 'extraConfigMaps={"empty":{}}' --skip-schema-validation
```

*Output:*

```text
Error: execution error at (nginx-demo/templates/extra-configmaps.yaml:3:3): lab-common.configmap: "empty" needs at least one key under 'data'
```

#### 3. Why This Failed & Defense in Depth

- **Layer 1 (Schema):** `values.schema.json` defined `"minProperties": 1` for each object under `extraConfigMaps`. This is caught immediately at render/lint time with no templates evaluated.
- **Layer 2 (Library Guard):** If schema validation is bypassed or if another chart uses `lab-common` without a schema, `_configmap.tpl` contains an explicit check:

  ```yaml
  {{- if not $data -}}
    {{- fail (printf "lab-common.configmap: %q needs at least one key under 'data'" $name) -}}
  {{- end -}}
  ```

  Why not use `required` here? In Go templates, `required` only checks if a value is `nil` or empty string `""`. An empty dictionary `dict` passes `required`! If you used `required` instead of `fail`, Helm would render an invalid Kubernetes ConfigMap with empty `data:`:

  ```yaml
  apiVersion: v1
  kind: ConfigMap
  metadata:
    name: d-empty
  data:
  ```

  `fail` guarantees that the template aborts with an actionable message.

#### 4. How to Recover

Provide at least one key-value pair for the ConfigMap, or remove the empty map.

---

### Scenario 3: Wrong Value Type in `extraConfigMaps`

#### 1. What to Break

Pass a scalar number instead of an object map:

```bash
helm template d ./charts/nginx-demo --set extraConfigMaps.settings=1
```

#### 2. The Error Observed

```text
Error: values don't meet the specifications of the schema(s) in the following chart(s):
nginx-demo:
- at '/extraConfigMaps/settings': got number, want object
```

#### 3. Why This Failed

- `values.schema.json` defines `extraConfigMaps` as an object of objects (`"additionalProperties": { "type": "object" }`).
- Setting it to an integer violates the schema contract and Helm rejects it before attempting template rendering.

#### 4. How to Recover

Supply a valid map of key-value pairs (or YAML object). Clean up any temporary files:

```bash
rm -f $LAB_TMP/bad.yaml
```

---

## Key Takeaways

| Concept | Key Point |
| :--- | :--- |
| `tpl` Function | Evaluates a string from values as a template; must be given a valid scope context (`.` or `$`). |
| Nil Pointer vs `required` | Accessing `.Values.missing.key` panics with a nil pointer. Use `dig` or `default dict` for safe traversal. |
| Library Charts (`type: library`) | Contain only named templates in `_*.tpl` files; cannot be installed on their own. |
| Dict Arguments for Helpers | Named templates accept a single argument; use `dict "root" $ ...` to pass both root context and custom parameters. |
| Selector Label Immutability | Never refactor `selectorLabels` on existing deployments; only refactor standard metadata labels (`labels`). |
| `lookup` Function | Only works when connected to a live cluster. Returns empty in `helm template` and GitOps engines (Argo CD). |
