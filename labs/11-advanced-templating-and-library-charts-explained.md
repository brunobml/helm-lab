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
- The `diff - /tmp/before-dev.yaml` check is the safety net: identical output means existing releases are unaffected. Run it for every shared-helper refactor.
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
