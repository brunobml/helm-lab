# Lab 13: Capstone: a three-tier release

**Start:** Lab 12 complete (`lab-12-complete`), with the Lab 12 tools installed and your age key in
`~/.config/sops/age/keys.txt`. Use the `helm-lab` namespace and Docker.
**Goal:** Design, secure, test, operate, and ship one release made of three services. No new Helm
concepts: every step reuses something from Labs 0-12, and the exercises are chosen to expose gaps.

```text
                +-------------------------- release "shop-dev" --------------------------+
                |                                                                       |
  helm test --> |  web (nginx-demo)     api (PostgREST)          db (PostgreSQL)        |
                |  <release>-service -> <release>-api   ->   <release>-db :5432         |
                |                                              StatefulSet, emptyDir    |
                |            Secret <release>-credentials (POSTGRES_PASSWORD, PGRST_DB_URI)
                |            post-install/post-upgrade Job: create schema, seed rows    |
                +-----------------------------------------------------------------------+
```

| Piece | Chart | Reuses |
| --- | --- | --- |
| `web` | `nginx-demo` (your Lab 0-12 chart) as an **aliased dependency** | Labs 0-9, 11, 12 |
| `api` | new `shop-api`: [PostgREST](https://postgrest.org) turns tables into a REST API | Labs 4, 5, 7 |
| `db` | new `shop-db`: PostgreSQL StatefulSet, optional PVC | Labs 4, Storage extension |
| umbrella | new `shop`: dependencies, credentials Secret, migration hook, smoke test | Labs 8, 10, 12 |
| environments | `values-dev.yaml`, `values-prod.yaml`, SOPS-encrypted `secrets.<env>.yaml` | Labs 3, 12 |

Images used: `postgres:16-alpine`, `postgrest/postgrest:v12.2.3`, `busybox:1.36`.

## Design decisions (read before building)

| Decision | Why |
| --- | --- |
| `api` and `db` do **not** use the `app: <release>` label | `nginx-demo`'s Service selects `app: <release>`. Any pod carrying that label, in any subchart, receives web traffic. |
| The umbrella owns the credentials Secret; subcharts reference `<release>-credentials` by convention | One secret, one owner, and subcharts stay usable on their own with a pre-created Secret. |
| Migration is a **post-install/post-upgrade** hook | Lab 10's `pre-*` hook cannot work here: the database it migrates is created by the same release. |
| The migration is idempotent (`IF NOT EXISTS`, `ON CONFLICT DO NOTHING`) | It runs on every upgrade. |
| The web chart's own hook and banner subchart are switched off (`web.migration.enabled`, `web.lab-banner.enabled`) | The capstone has one migration. |
| PostgREST connects as the database owner and switches to a `NOLOGIN` role per request | Fine for a lab; a real deployment would use a separate low-privilege login role. |

## Part A: The two new tiers

Create the directories:

```bash
mkdir -p charts/shop-db/templates charts/shop-api/templates
```

### Step 1: `shop-db`

`charts/shop-db/Chart.yaml`:

```yaml
apiVersion: v2
name: shop-db
description: PostgreSQL for the shop capstone
type: application
version: 0.1.0
appVersion: "16"
```

`charts/shop-db/values.yaml`:

```yaml
image:
  repository: postgres
  tag: 16-alpine
  pullPolicy: IfNotPresent

# Database and role created on first start. The password comes from the
# "<release>-credentials" Secret (key POSTGRES_PASSWORD), never from values.
database: shop
user: shop

persistence:
  enabled: false
  size: 1Gi
  storageClass: ""

resources: {}
```

`charts/shop-db/templates/_helpers.tpl`:

```yaml
{{- define "shop-db.name" -}}
{{- printf "%s-db" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels. Deliberately NOT "app: <release>": the web chart's Service selects on that. */}}
{{- define "shop-db.selectorLabels" -}}
app.kubernetes.io/name: shop-db
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: db
{{- end -}}

{{- define "shop-db.labels" -}}
{{ include "shop-db.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* The Secret is created by the umbrella chart; see the shop chart's credentials-secret.yaml. */}}
{{- define "shop-db.credentialsSecret" -}}
{{- printf "%s-credentials" .Release.Name -}}
{{- end -}}
```

`charts/shop-db/templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "shop-db.name" . }}
  labels:
    {{- include "shop-db.labels" . | nindent 4 }}
spec:
  ports:
    - name: postgres
      port: 5432
      targetPort: postgres
  selector:
    {{- include "shop-db.selectorLabels" . | nindent 4 }}
```

`charts/shop-db/templates/statefulset.yaml`:

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: {{ include "shop-db.name" . }}
  labels:
    {{- include "shop-db.labels" . | nindent 4 }}
spec:
  serviceName: {{ include "shop-db.name" . }}
  replicas: 1
  selector:
    matchLabels:
      {{- include "shop-db.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "shop-db.labels" . | nindent 8 }}
    spec:
      containers:
        - name: postgres
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: POSTGRES_DB
              value: {{ .Values.database | quote }}
            - name: POSTGRES_USER
              value: {{ .Values.user | quote }}
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "shop-db.credentialsSecret" . }}
                  key: POSTGRES_PASSWORD
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata
          ports:
            - name: postgres
              containerPort: 5432
          readinessProbe:
            exec:
              command: ["pg_isready", "-U", {{ .Values.user | quote }}, "-d", {{ .Values.database | quote }}]
            initialDelaySeconds: 3
            periodSeconds: 3
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- if not .Values.persistence.enabled }}
      volumes:
        - name: data
          emptyDir: {}
      {{- end }}
  {{- if .Values.persistence.enabled }}
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]
        {{- with .Values.persistence.storageClass }}
        storageClassName: {{ . | quote }}
        {{- end }}
        resources:
          requests:
            storage: {{ .Values.persistence.size }}
  {{- end }}
```

Points to notice: the password comes from a `secretKeyRef`, never from values; the data directory uses a
`PGDATA` subdirectory (a volume's root contains `lost+found`, which PostgreSQL refuses); and `volumeClaimTemplates`
only appears when persistence is on, otherwise an `emptyDir` is used.

### Step 2: `shop-api`

`charts/shop-api/Chart.yaml`:

```yaml
apiVersion: v2
name: shop-api
description: PostgREST API for the shop capstone
type: application
version: 0.1.0
appVersion: "12.2.3"
```

`charts/shop-api/values.yaml`:

```yaml
replicaCount: 1

image:
  repository: postgrest/postgrest
  tag: v12.2.3
  pullPolicy: IfNotPresent

# Schema exposed by PostgREST and the role it switches to for requests.
dbSchema: public
anonRole: web_anon

service:
  port: 3000

resources: {}
```

`charts/shop-api/templates/_helpers.tpl`:

```yaml
{{- define "shop-api.name" -}}
{{- printf "%s-api" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Selector labels. Deliberately NOT "app: <release>": the web chart's Service selects on that. */}}
{{- define "shop-api.selectorLabels" -}}
app.kubernetes.io/name: shop-api
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: api
{{- end -}}

{{- define "shop-api.labels" -}}
{{ include "shop-api.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}

{{/* The Secret is created by the umbrella chart; see the shop chart's credentials-secret.yaml. */}}
{{- define "shop-api.credentialsSecret" -}}
{{- printf "%s-credentials" .Release.Name -}}
{{- end -}}
```

`charts/shop-api/templates/service.yaml`:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: {{ include "shop-api.name" . }}
  labels:
    {{- include "shop-api.labels" . | nindent 4 }}
spec:
  ports:
    - name: http
      port: {{ .Values.service.port }}
      targetPort: http
  selector:
    {{- include "shop-api.selectorLabels" . | nindent 4 }}
```

`charts/shop-api/templates/deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "shop-api.name" . }}
  labels:
    {{- include "shop-api.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "shop-api.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "shop-api.labels" . | nindent 8 }}
    spec:
      containers:
        - name: postgrest
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          env:
            - name: PGRST_DB_URI
              valueFrom:
                secretKeyRef:
                  name: {{ include "shop-api.credentialsSecret" . }}
                  key: PGRST_DB_URI
            - name: PGRST_DB_SCHEMAS
              value: {{ .Values.dbSchema | quote }}
            - name: PGRST_DB_ANON_ROLE
              value: {{ .Values.anonRole | quote }}
            - name: PGRST_SERVER_PORT
              value: {{ .Values.service.port | quote }}
            - name: PGRST_ADMIN_SERVER_PORT
              value: "3001"
          ports:
            - name: http
              containerPort: {{ .Values.service.port }}
            - name: admin
              containerPort: 3001
          # /ready is 503 while the database is unreachable. After a database restart it can stay
          # 503 (the notification listener does not always recover), so liveness also uses /ready:
          # a stuck pod is restarted and reconnects. The startup probe gives a fresh install time
          # to wait for the database before liveness begins.
          startupProbe:
            httpGet:
              path: /ready
              port: admin
            periodSeconds: 5
            failureThreshold: 30
          readinessProbe:
            httpGet:
              path: /ready
              port: admin
            periodSeconds: 3
          livenessProbe:
            httpGet:
              path: /ready
              port: admin
            periodSeconds: 10
            failureThreshold: 6
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
```

PostgREST serves the API on port 3000 and health endpoints on a separate admin port, 3001. Look closely at the three
probes. They come from an incident you will reproduce in Part E.

```bash
helm lint charts/shop-db charts/shop-api
```

## Part B: The umbrella chart

```bash
mkdir -p charts/shop/templates/tests
```

### Step 3: Chart metadata and dependencies

`charts/shop/Chart.yaml`:

```yaml
apiVersion: v2
name: shop
description: Umbrella chart for the three-tier shop capstone (web, api, db)
type: application
version: 0.1.0
appVersion: "1.0.0"

dependencies:
  - name: nginx-demo
    alias: web
    version: 0.5.0
    repository: file://../nginx-demo
  - name: shop-api
    alias: api
    version: 0.1.0
    repository: file://../shop-api
  - name: shop-db
    alias: db
    version: 0.1.0
    repository: file://../shop-db
```

`alias:` installs a dependency under a different values key: `web`, `api`, and `db` instead of `nginx-demo`, `shop-api`,
and `shop-db`. The alias is also what `condition:` and overrides use.

### Step 4: Values

`charts/shop/values.yaml`:

```yaml
global:
  environment: dev

# Credentials Secret shared by db, api, and the migration hook. The password is
# supplied from an encrypted secrets.<env>.yaml file (see Lab 13); never commit it in plaintext.
# Set create=false to provide a Secret named "<release>-credentials" yourself
# (keys: POSTGRES_PASSWORD, PGRST_DB_URI), for example under GitOps.
credentials:
  create: true
  dbPassword: ""

# Hook that creates the schema and seeds data after the database is up.
migration:
  enabled: true
  seed:
    - first item
  # Extra SQL appended to the migration. Set to invalid SQL in Lab 13 to see a failed hook.
  extraSQL: ""

# ----- subchart overrides (keys are the dependency aliases) -----
web:
  replicaCount: 1
  lab-banner:
    enabled: false
  migration:
    enabled: false
  pageContent: |
    <h1>Shop ({{ .Values.global.environment }})</h1>

api:
  replicaCount: 1

db:
  database: shop
  user: shop
  persistence:
    enabled: false
```

Everything under `web:`, `api:`, and `db:` overrides those subcharts' defaults. `web.lab-banner.enabled` reaches *through*
`web` into `nginx-demo`'s own subchart.

### Step 5: Templates

`charts/shop/templates/_helpers.tpl`:

```yaml
{{- define "shop.credentialsSecret" -}}
{{- printf "%s-credentials" .Release.Name -}}
{{- end -}}

{{/* Labels for resources owned by the umbrella. Not used as selectors. */}}
{{- define "shop.labels" -}}
app.kubernetes.io/name: shop
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: platform
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end -}}
```

`charts/shop/templates/credentials-secret.yaml`:

```yaml
{{- if .Values.credentials.create }}
{{- $password := required "credentials.dbPassword is required; deploy with: helm secrets install ... -f secrets.<env>.yaml" .Values.credentials.dbPassword }}
apiVersion: v1
kind: Secret
metadata:
  name: {{ include "shop.credentialsSecret" . }}
  labels:
    {{- include "shop.labels" . | nindent 4 }}
type: Opaque
stringData:
  POSTGRES_PASSWORD: {{ $password | quote }}
  PGRST_DB_URI: {{ printf "postgres://%s:%s@%s-db:5432/%s" .Values.db.user (urlquery $password) .Release.Name .Values.db.database | quote }}
{{- end }}
```

Notice `required` (a missing password fails the render with instructions) and `urlquery` (the password goes into a URL, so
`/`, `@` and `:` must be encoded; the plain `POSTGRES_PASSWORD` stays raw).

`charts/shop/templates/migration-job.yaml`:

```yaml
{{- if .Values.migration.enabled }}
{{- $db := printf "%s-db" .Release.Name }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ .Release.Name }}-migrations
  labels:
    {{- include "shop.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "-5"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
data:
  001-init.sql: |
    CREATE TABLE IF NOT EXISTS items (
      id serial PRIMARY KEY,
      name text NOT NULL UNIQUE
    );
    {{- range .Values.migration.seed }}
    INSERT INTO items (name) VALUES ({{ . | replace "'" "''" | squote }}) ON CONFLICT (name) DO NOTHING;
    {{- end }}
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '{{ .Values.api.anonRole }}') THEN
        CREATE ROLE {{ .Values.api.anonRole }} NOLOGIN;
      END IF;
    END
    $$;
    GRANT USAGE ON SCHEMA public TO {{ .Values.api.anonRole }};
    GRANT SELECT ON items TO {{ .Values.api.anonRole }};
    GRANT {{ .Values.api.anonRole }} TO {{ .Values.db.user }};
    {{- with .Values.migration.extraSQL }}
    {{ . | nindent 4 }}
    {{- end }}
    NOTIFY pgrst, 'reload schema';
---
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ .Release.Name }}-migrate
  labels:
    {{- include "shop.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": before-hook-creation,hook-succeeded
spec:
  backoffLimit: 0
  activeDeadlineSeconds: 120
  template:
    metadata:
      labels:
        {{- include "shop.labels" . | nindent 8 }}
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.db.image.repository }}:{{ .Values.db.image.tag }}"
          command: ["sh", "-c"]
          args:
            - |
              set -e
              until pg_isready -h {{ $db }} -U {{ .Values.db.user }} -d {{ .Values.db.database }}; do
                echo "waiting for database"; sleep 2
              done
              psql -v ON_ERROR_STOP=1 -h {{ $db }} -U {{ .Values.db.user }} -d {{ .Values.db.database }} -f /migrations/001-init.sql
              echo "migration complete"
          env:
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ include "shop.credentialsSecret" . }}
                  key: POSTGRES_PASSWORD
          volumeMounts:
            - name: migrations
              mountPath: /migrations
      volumes:
        - name: migrations
          configMap:
            name: {{ .Release.Name }}-migrations
{{- end }}
```

Two hook resources: the SQL ConfigMap (weight `-5`, so it exists first) and the Job. `replace "'" "''" | squote` escapes
quotes in seed data, and `.Values.db.image` works because subchart defaults are visible in the parent's values.

`charts/shop/templates/tests/smoke.yaml`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ .Release.Name }}-smoke
  labels:
    {{- include "shop.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": before-hook-creation
spec:
  restartPolicy: Never
  containers:
    - name: smoke
      image: busybox:1.36
      command: ["sh", "-c"]
      args:
        - |
          set -e
          echo "web:"
          wget -qO- --timeout=10 http://{{ .Release.Name }}-service:{{ .Values.web.service.port }}/ | grep -i "shop"
          echo "api:"
          {{- with .Values.migration.seed }}
          wget -qO- --timeout=10 http://{{ $.Release.Name }}-api:{{ $.Values.api.service.port }}/items | tee /dev/stderr | grep -q {{ first . | quote }}
          {{- else }}
          wget -qO- --timeout=10 http://{{ .Release.Name }}-api:{{ .Values.api.service.port }}/ >/dev/null
          {{- end }}
          echo "ok"
```

`charts/shop/templates/NOTES.txt`:

```text
Release {{ .Release.Name }} ({{ .Values.global.environment }}) installed in {{ .Release.Namespace }}.

Tiers:
  web  {{ .Release.Name }}-service   (nginx)
  api  {{ .Release.Name }}-api       (PostgREST on port {{ .Values.api.service.port }})
  db   {{ .Release.Name }}-db        (PostgreSQL, persistence {{ ternary "on" "off" .Values.db.persistence.enabled }})

Try it:
  kubectl -n {{ .Release.Namespace }} port-forward service/{{ .Release.Name }}-api 3000:{{ .Values.api.service.port }}
  curl http://127.0.0.1:3000/items

Verify all three tiers:
  helm test {{ .Release.Name }} -n {{ .Release.Namespace }}
```

### Step 6: Keep secrets and test files out of the archive

`charts/shop/.helmignore`:

```text
/secrets.*.yaml
/.sops.yaml
/tests/
/ci/
```

Anchored with `/`, as in Lab 12.

### Step 7: Environment values

`charts/shop/values-dev.yaml`:

```yaml
global:
  environment: dev
```

`charts/shop/values-prod.yaml` (two replicas per tier, persistence, resources, an extra seed row):

```yaml
global:
  environment: prod

migration:
  seed:
    - first item
    - second item

web:
  replicaCount: 2
  resources:
    requests:
      cpu: 50m
      memory: 32Mi

api:
  replicaCount: 2
  resources:
    requests:
      cpu: 50m
      memory: 64Mi

db:
  persistence:
    enabled: true
    size: 1Gi
  resources:
    requests:
      cpu: 100m
      memory: 128Mi
```

## Part C: Secrets

```bash
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
PUB=$(grep "public key" "$SOPS_AGE_KEY_FILE" | awk '{print $NF}')
cat > charts/shop/.sops.yaml <<YAML
creation_rules:
  - path_regex: secrets\..*\.yaml\$
    encrypted_regex: ^(dbPassword)\$
    age: $PUB
YAML

cd charts/shop
printf 'credentials:\n  dbPassword: dev-Passw0rd\n'       > secrets.dev.yaml  && sops --encrypt --in-place secrets.dev.yaml
printf 'credentials:\n  dbPassword: prod-Str0ng/P@ss\n'   > secrets.prod.yaml && sops --encrypt --in-place secrets.prod.yaml
cd ../..
head -3 charts/shop/secrets.dev.yaml
```

*Expect:* `dbPassword: ENC[AES256_GCM,...]`. The prod password deliberately contains `/` and `@`.

## Part D: Build, render, deploy

### Step 8: Build dependencies, **in order**

`shop` packages `nginx-demo` as a dependency, and `nginx-demo` has dependencies of its own (`lab-banner`, `lab-common`).
Build the inner one first:

```bash
helm dependency build charts/nginx-demo
helm dependency build charts/shop
ls charts/shop/charts
```

*Expect:* `nginx-demo-0.5.0.tgz  shop-api-0.1.0.tgz  shop-db-0.1.0.tgz`.

### Step 9: Render and inspect (no cluster)

```bash
helm lint charts/shop --set credentials.dbPassword=x
helm template s charts/shop                                        # fails on purpose
helm template s charts/shop --set credentials.dbPassword='p@ss/w:rd' > /tmp/shop.yaml
grep -E "^kind:" /tmp/shop.yaml | sort | uniq -c
helm template s charts/shop --set credentials.dbPassword='p@ss/w:rd' -s templates/credentials-secret.yaml
```

*Expect:* the first `helm template` fails with `credentials.dbPassword is required; deploy with: helm secrets install ...`. The
kinds are 2 ConfigMap (page + migrations), 2 Deployment, 1 Job, 2 Pod (the two test hooks), 1 Secret, 3 Service,
1 ServiceAccount, 1 StatefulSet. `PGRST_DB_URI` reads `postgres://shop:p%40ss%2Fw%3Ard@s-db:5432/shop`.

**Predict before running this:** which pods does the `web` Service select?

```bash
grep -B1 -A3 "selector:" /tmp/shop.yaml | grep -E "app|name:"
```

Only `app: s` (the web pods) appears under the web Service; `api` and `db` select on `app.kubernetes.io/name` and
`component`. You will break this on purpose later.

### Step 10: Deploy `dev` and test all three tiers

```bash
helm secrets install shop-dev ./charts/shop -n helm-lab \
  -f ./charts/shop/values-dev.yaml -f ./charts/shop/secrets.dev.yaml --wait --timeout 240s
kubectl get pods,statefulset,job -n helm-lab | grep shop-dev
helm test shop-dev -n helm-lab --timeout 90s
kubectl logs shop-dev-smoke -n helm-lab
```

*Expect:* `STATUS: deployed` after about a minute; three Pods (`shop-dev-api-*`, `shop-dev-db-0`,
`shop-dev-deployment-*`) all Running; **no** Job or migrations ConfigMap left (`hook-succeeded` removed them). Both tests report
`Phase: Succeeded` and the smoke log ends with `[{"id":1,"name":"first item"}]` then `ok`.

Follow the data yourself:

```bash
kubectl run curl --rm -i --restart=Never --image=busybox:1.36 -n helm-lab -q -- wget -qO- http://shop-dev-api:3000/items
```

## Part E: Operate it

### Step 11: An idempotent upgrade

Add a seed row and upgrade. The migration runs again and must not duplicate `first item`:

```bash
helm secrets upgrade shop-dev ./charts/shop -n helm-lab \
  -f ./charts/shop/values-dev.yaml -f ./charts/shop/secrets.dev.yaml \
  --set 'migration.seed={first item,second item}' --wait --timeout 120s
kubectl run curl --rm -i --restart=Never --image=busybox:1.36 -n helm-lab -q -- wget -qO- http://shop-dev-api:3000/items
```

*Expect:* `first item` (id 1) and `second item` (id 3): the skipped id 2 is a `serial` sequence value consumed by the
`ON CONFLICT DO NOTHING` attempt. Harmless, and a reminder that "idempotent" refers to the rows, not the counters.

### Step 12: A migration that fails (post-upgrade hooks are not pre-upgrade hooks)

Set a shell helper so the commands stay short:

```bash
U() { helm secrets upgrade shop-dev ./charts/shop -n helm-lab -f ./charts/shop/values-dev.yaml -f ./charts/shop/secrets.dev.yaml "$@"; }
```

**Predict:** in Lab 10 a failing `pre-upgrade` hook left the Deployment untouched. If this `post-upgrade` hook fails while
you also change `api.replicaCount`, what replica count will the API have?

```bash
U --set api.replicaCount=2 --set 'migration.extraSQL=SELECT * FROM nope;' --timeout 90s
helm status shop-dev -n helm-lab | grep STATUS
kubectl get deployment shop-dev-api -n helm-lab -o jsonpath='desired={.spec.replicas}{"\n"}'
kubectl logs job/shop-dev-migrate -n helm-lab | tail -3
```

*Expect:* `UPGRADE FAILED: post-upgrade hooks failed`, `STATUS: failed`, **`desired=2`** (the new manifest **was** applied; only
the hook after it failed), and `ERROR: relation "nope" does not exist` in the Job log. A post hook cannot prevent the change; it
can only report that the release is unhealthy. Recover with a good upgrade:

```bash
U --wait --timeout 120s
kubectl get deployment shop-dev-api -n helm-lab -o jsonpath='desired={.spec.replicas}{"\n"}'     # desired=1
```

Now let Helm undo it automatically:

```bash
U --set 'migration.extraSQL=SELECT * FROM nope;' --atomic --timeout 120s
helm history shop-dev -n helm-lab | tail -3
```

*Expect:* `has been rolled back due to atomic being set`, and a final revision `Rollback to N`.

### Step 13: Restart the database (the probes earn their keep)

Use `prod` for this: it has a persistent volume, so the data must survive.

```bash
helm secrets install shop-prod ./charts/shop -n helm-lab \
  -f ./charts/shop/values-prod.yaml -f ./charts/shop/secrets.prod.yaml --wait --timeout 240s
kubectl get pods,pvc -n helm-lab | grep shop-prod
helm test shop-prod -n helm-lab --timeout 90s

kubectl delete pod shop-prod-db-0 -n helm-lab
kubectl get pods -n helm-lab -l app.kubernetes.io/component=api,app.kubernetes.io/instance=shop-prod -w
```

Watch for about 90 seconds, then Ctrl+C. *Expect:* both `shop-prod-api-*` pods drop to `0/1`, and after roughly a minute
each is restarted (`RESTARTS 1`) and returns to `1/1`. Then:

```bash
kubectl run curl --rm -i --restart=Never --image=busybox:1.36 -n helm-lab -q -- wget -qO- http://shop-prod-api:3000/items
```

*Expect:* both seed rows (`first item` and `second item`), because the data lives on the PVC, not in the pod.

> [!NOTE]
> Why the restart? After a database restart PostgREST v12 can stay "not ready" (`/ready` returns 503) because its notification
> listener does not reconnect. With no ready endpoints the Service sends it no traffic, so nothing ever heals it. Making
> the **liveness** probe use `/ready` (behind a **startup** probe that tolerates a slow first boot) lets Kubernetes restart the
> stuck pod. Without those two probes, the API stays down until someone deletes its pods.
> The trade-off: a long database outage now restarts the API pods repeatedly, which is noisy but harmless.

### Step 14: Rotate the database password (a trap)

Edit the encrypted file, then upgrade:

```bash
cd charts/shop && sops --set '["credentials"]["dbPassword"] "rotated-Passw0rd"' secrets.dev.yaml && cd ../..
U --wait --timeout 90s
kubectl logs job/shop-dev-migrate -n helm-lab | tail -2
kubectl get pods -n helm-lab -l app.kubernetes.io/component=api,app.kubernetes.io/instance=shop-dev
kubectl get secret shop-dev-credentials -n helm-lab -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d; echo
```

*Expect:* the upgrade **fails**; the Job log shows `FATAL:  password authentication failed for user "shop"`; the API pod is
the same one as before (not restarted); the Secret already holds `rotated-Passw0rd`. Two independent reasons:

1. PostgreSQL applies `POSTGRES_PASSWORD` only when it **initializes an empty data directory**. The running database
   still has the old password.
2. Nothing restarts the API, so it keeps using its old connection string until it happens to restart.

The correct procedure changes the password *inside the database* first, then re-applies, then restarts consumers:

```bash
kubectl exec shop-dev-db-0 -n helm-lab -- psql -U shop -d shop -c "ALTER ROLE shop PASSWORD 'rotated-Passw0rd'"
U --wait --timeout 120s
kubectl rollout restart deployment/shop-dev-api -n helm-lab
kubectl rollout status deployment/shop-dev-api -n helm-lab --timeout=90s
helm test shop-dev -n helm-lab --timeout 90s
```

*Expect:* `ALTER ROLE`, `STATUS: deployed`, and both tests `Succeeded`.

## Part F: Tests and CI

### Step 15: Unit tests

`charts/shop/tests/credentials_test.yaml`:

```yaml
suite: credentials secret
templates:
  - templates/credentials-secret.yaml
tests:
  - it: fails with a helpful message when no password is supplied
    asserts:
      - failedTemplate:
          errorPattern: credentials.dbPassword is required

  - it: creates the Secret the subcharts expect
    release:
      name: shop
    set:
      credentials.dbPassword: pw
    asserts:
      - isKind:
          of: Secret
      - equal:
          path: metadata.name
          value: shop-credentials
      - equal:
          path: stringData.POSTGRES_PASSWORD
          value: pw

  - it: URL-encodes the password inside the connection string only
    release:
      name: shop
    set:
      credentials.dbPassword: "p@ss/w:rd"
    asserts:
      - equal:
          path: stringData.POSTGRES_PASSWORD
          value: "p@ss/w:rd"
      - equal:
          path: stringData.PGRST_DB_URI
          value: "postgres://shop:p%40ss%2Fw%3Ard@shop-db:5432/shop"

  - it: renders nothing when the Secret is managed elsewhere
    set:
      credentials.create: false
    asserts:
      - hasDocuments:
          count: 0
```

`charts/shop/tests/migration_test.yaml`:

```yaml
suite: migration hook
templates:
  - templates/migration-job.yaml
tests:
  - it: runs after install and upgrade, ConfigMap before Job
    documentSelector:
      path: kind
      value: ConfigMap
    asserts:
      - equal:
          path: metadata.annotations["helm.sh/hook"]
          value: post-install,post-upgrade
      - equal:
          path: metadata.annotations["helm.sh/hook-weight"]
          value: "-5"

  - it: runs the Job at weight 0 and cleans up after success
    documentSelector:
      path: kind
      value: Job
    asserts:
      - equal:
          path: metadata.annotations["helm.sh/hook"]
          value: post-install,post-upgrade
      - equal:
          path: metadata.annotations["helm.sh/hook-weight"]
          value: "0"
      - equal:
          path: metadata.annotations["helm.sh/hook-delete-policy"]
          value: before-hook-creation,hook-succeeded
      - equal:
          path: spec.backoffLimit
          value: 0

  - it: seeds one INSERT per item and escapes quotes
    documentSelector:
      path: kind
      value: ConfigMap
    set:
      migration.seed:
        - first item
        - "it's second"
    asserts:
      - matchRegex:
          path: data["001-init.sql"]
          pattern: "VALUES \\('first item'\\)"
      - matchRegex:
          path: data["001-init.sql"]
          pattern: "VALUES \\('it''s second'\\)"

  - it: appends extra SQL before the reload notification
    documentSelector:
      path: kind
      value: ConfigMap
    set:
      migration.extraSQL: "SELECT 1;"
    asserts:
      - matchRegex:
          path: data["001-init.sql"]
          pattern: "SELECT 1;\\s+NOTIFY pgrst"

  - it: is not rendered when disabled
    set:
      migration.enabled: false
    asserts:
      - hasDocuments:
          count: 0
```

`charts/shop/tests/wiring_test.yaml` (it addresses subchart templates as `charts/<alias>/templates/...`):

```yaml
suite: subchart wiring
templates:
  - charts/db/templates/statefulset.yaml
  - charts/api/templates/deployment.yaml
  - charts/web/templates/service.yaml
release:
  name: shop
set:
  credentials.dbPassword: pw
tests:
  - it: db and api read the credentials Secret the umbrella creates
    template: charts/db/templates/statefulset.yaml
    asserts:
      - equal:
          path: spec.template.spec.containers[0].env[2].valueFrom.secretKeyRef.name
          value: shop-credentials

  - it: api reads the connection string from the same Secret
    template: charts/api/templates/deployment.yaml
    asserts:
      - equal:
          path: spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.name
          value: shop-credentials

  - it: web Service selector cannot match api or db pods
    template: charts/web/templates/service.yaml
    asserts:
      - equal:
          path: spec.selector
          value:
            app: shop
      - notExists:
          path: spec.selector["app.kubernetes.io/component"]

  - it: api and db pods do not carry the web selector label
    template: charts/api/templates/deployment.yaml
    asserts:
      - notExists:
          path: spec.template.metadata.labels.app

  - it: db uses a persistent volume claim only when persistence is enabled
    template: charts/db/templates/statefulset.yaml
    set:
      db.persistence.enabled: true
    asserts:
      - exists:
          path: spec.volumeClaimTemplates
      - notExists:
          path: spec.template.spec.volumes
```

```bash
helm unittest charts/nginx-demo charts/shop
```

*Expect:* all suites pass (14 tests for `shop`, plus the `nginx-demo` ones).

### Step 16: `ct` scenario and workflow

`charts/shop/ci/ci-values.yaml`:

```yaml
# Dummy password for CI only; real ones come from encrypted files.
credentials:
  dbPassword: ci-only-password
```

Update `.github/workflows/chart-ci.yaml`: replace the dependency and unit-test steps with

```yaml
      - name: Build chart dependencies (nginx-demo first: shop packages it)
        run: |
          helm dependency build charts/nginx-demo
          helm dependency build charts/shop

      - name: Unit tests
        run: |
          helm plugin install https://github.com/helm-unittest/helm-unittest
          helm unittest charts/nginx-demo charts/shop
```

Then run the same checks locally:

```bash
ct lint --config ct.yaml --all
ct install --config ct.yaml --charts charts/shop
```

*Expect:* every chart passes lint, and the `shop` install passes with its test. The long log output during install is
`ct` printing events; `Connection refused` lines from PostgREST are the API starting before the database, which is expected.

## Part G: Ship it

### Step 17: Package, sign, publish, verify, install

Set up the throwaway GnuPG signing key (or reuse the one from Lab 12 if still in your session):

```bash
if [ -z "$GNUPGHOME" ] || [ ! -f "$GNUPGHOME/secring.gpg" ]; then
  export GNUPGHOME=$(mktemp -d); chmod 700 "$GNUPGHOME"
  gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "Helm Lab <helm-lab@example.com>" rsa3072 default 1y
  gpg --export > "$GNUPGHOME/pubring.gpg"
  gpg --batch --pinentry-mode loopback --passphrase '' --export-secret-keys > "$GNUPGHOME/secring.gpg"
fi

mkdir -p /tmp/shop-pkg
helm package charts/shop --sign --key "Helm Lab" --keyring "$GNUPGHOME/secring.gpg" -d /tmp/shop-pkg
tar tzf /tmp/shop-pkg/shop-0.1.0.tgz | grep -E "secrets\.|\.sops|shop/tests/|shop/ci/"   # no output
docker start helm-registry 2>/dev/null || docker run -d -p 5001:5000 --name helm-registry registry:2
helm push /tmp/shop-pkg/shop-0.1.0.tgz oci://localhost:5001/helm-lab

mkdir -p /tmp/shop-pull
helm pull oci://localhost:5001/helm-lab/shop --version 0.1.0 --verify --keyring "$GNUPGHOME/pubring.gpg" -d /tmp/shop-pull
helm secrets install shop-oci /tmp/shop-pull/shop-0.1.0.tgz -n helm-lab --verify --keyring "$GNUPGHOME/pubring.gpg" \
  -f ./charts/shop/values-dev.yaml -f ./charts/shop/secrets.dev.yaml --wait --timeout 240s
helm test shop-oci -n helm-lab --timeout 90s
```

*Expect:* nothing from the `tar | grep` (no secrets, no tests, no CI files in the archive); `Chart Hash Verified`; the third release
`shop-oci` deployed and tested from a verified artifact. The three releases (`shop-dev`, `shop-prod`, `shop-oci`) coexist in one
namespace because every resource name is prefixed with its release name.

> [!NOTE]
> `shop-oci` starts from `secrets.dev.yaml` as it is *now*, after the rotation in Step 14: a new release initializes an empty
> database, so the current password works.

## Part H (optional, not executed here): GitOps hand-off

Argo CD cannot run `helm secrets`, so the credentials must reach the cluster another way. The chart supports that: set
`credentials.create: false`, and provide a Secret named `<application-name>-credentials` with keys `POSTGRES_PASSWORD` and
`PGRST_DB_URI` (created out of band, or by an External Secrets Operator or Sealed Secrets). Argo CD maps `post-install` and
`post-upgrade` hooks to its PostSync phase.

A sketch of `gitops/shop-dev.yaml` (adapt `repoURL` and `targetRevision` as in Lab 9):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: shop-dev
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/YOUR-ACCOUNT/helm-lab.git
    targetRevision: YOUR-LAB-BRANCH
    path: charts/shop
    helm:
      valueFiles:
        - values-dev.yaml
      parameters:
        - name: credentials.create
          value: "false"
  destination:
    server: https://kubernetes.default.svc
    namespace: helm-lab-gitops
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
```

> [!WARNING]
> This layout **cannot be built from Git alone**: `nginx-demo`'s own dependencies are git-ignored `.tgz` files (the fresh-clone
> failure in the break-it section below). Before GitOps would work, publish the subcharts to a registry and reference them with
> `oci://` repositories, or commit the built archives. Solving that is a Lab 17 topic; this manifest was not applied to a live Argo CD.

## Verify

Local:

```bash
helm dependency build charts/nginx-demo && helm dependency build charts/shop
helm lint charts/shop --set credentials.dbPassword=x
helm unittest charts/nginx-demo charts/shop
ct lint --config ct.yaml --all
helm template s charts/shop --set credentials.dbPassword=x | grep -c "kind: Job"                # 1
helm template s charts/shop --set credentials.dbPassword=x --set migration.enabled=false | grep -c "kind: Job"   # 0
```

Cluster:

```bash
helm list -n helm-lab | grep shop
helm test shop-dev -n helm-lab --timeout 90s
helm test shop-prod -n helm-lab --timeout 90s
kubectl get pvc -n helm-lab | grep shop-prod
```

## Break it and recover

1. **Deploy without the secrets file.** `helm install x ./charts/shop -n helm-lab` fails with the `required` message from Step 5.
2. **Plain `helm` on the encrypted file.** `helm template s charts/shop -f charts/shop/secrets.dev.yaml | grep POSTGRES_PASSWORD`
   renders `ENC[AES256_GCM,...]` as the password. Only `helm secrets` decrypts.
3. **Label collision.** In `charts/shop-api/templates/_helpers.tpl`, add `app: {{ .Release.Name }}` to `shop-api.selectorLabels`, then run
   `helm dependency build charts/shop && helm unittest charts/shop`. *Expect:* the test `api and db pods do not carry the web selector label` fails.
   To see the real harm, install a fresh release with the change (an existing release would fail earlier on Kubernetes' immutable selectors):
   ```bash
   helm dependency build charts/shop
   helm secrets install shop-bad ./charts/shop -n helm-lab -f ./charts/shop/values-dev.yaml -f ./charts/shop/secrets.dev.yaml --wait --timeout 150s
   kubectl get endpointslices -n helm-lab -l kubernetes.io/service-name=shop-bad-service -o jsonpath='{.items[*].endpoints[*].addresses}{"\n"}'
   for i in 1 2 3 4 5 6; do kubectl run c$i --rm -i --restart=Never --image=busybox:1.36 -n helm-lab -q -- wget -qO- --timeout=3 http://shop-bad-service/; done
   ```
   *Expect:* `helm install --wait` still succeeds, the Service lists **two** addresses (the web pod and the API pod), and some requests print
   `<h1>Shop (dev)</h1>` while others fail with `can't connect to remote host` (nothing listens on port 80 in the API pod). Nothing in the release
   is "unhealthy"; only traffic is wrong. Uninstall `shop-bad`, revert the change, and rebuild the dependencies.
4. **Build in the wrong order (fresh clone).** Remove the inner archives and rebuild only the outer chart:
   ```bash
   rm charts/nginx-demo/charts/*.tgz charts/shop/charts/*.tgz
   helm dependency build charts/shop
   helm template s charts/shop --set credentials.dbPassword=x
   ```
   *Expect:* the build says it succeeded, but the render fails with `no template "lab-common.labels" associated with template "gotpl"`.
   The message names a symptom, not the cause: `nginx-demo`'s own dependencies were never built. Run `helm dependency build charts/nginx-demo` first.
5. **A migration that is not idempotent.** Change `CREATE TABLE IF NOT EXISTS` to `CREATE TABLE` in `migration-job.yaml` and run `U --atomic --timeout 90s`.
   *Expect:* `relation "items" already exists` in the Job log, the upgrade fails, and `--atomic` rolls it back. The table survived the first install, so
   even the first upgrade after the change fails. Revert.

## Explain

- Why must `api` and `db` avoid the `app: <release>` label, and where else in a chart could that assumption hide?
- Why is the migration a post-install/post-upgrade hook, and how does a failure differ from Lab 10's pre-upgrade hook?
- Why did rotating the password break the migration, and why was the API not restarted? What would you change in the charts
  so a rotation is safe (think: where could a checksum annotation live, and what is Reloader for)?
- Why use liveness probes that check the dependency, and what could go wrong with them?
- Which parts of this design change if the release is deployed by Argo CD instead of `helm secrets`?
- What would you change before running this in production? (Answer from Labs 10-12, then compare with the Roadmap's Lab 16.)

> [!TIP]
> See [13-capstone-explained.md](13-capstone-explained.md) for detailed explanations.

## Cleanup and checkpoint

```bash
helm uninstall shop-oci shop-dev shop-prod -n helm-lab
kubectl delete pvc -n helm-lab -l app.kubernetes.io/instance=shop-prod       # StatefulSet PVCs outlive the release
# Test-hook Pods and a failed hook Job are not part of the release, so uninstall leaves them:
kubectl delete pod,job -n helm-lab -l 'app.kubernetes.io/instance in (shop-dev,shop-prod,shop-oci)'
kubectl get pvc,pods,job -n helm-lab | grep -i shop                          # nothing should remain
docker rm -f helm-registry 2>/dev/null || true
rm -rf /tmp/shop-pkg /tmp/shop-pull /tmp/shop.yaml "$GNUPGHOME"
unset GNUPGHOME
```

Keep `~/.config/sops/age/keys.txt`. You may commit `charts/shop/secrets.*.yaml` and `.sops.yaml` (encrypted); never commit the private key.
Tick Lab 13 in the README and create `lab-13-complete`.

References: [PostgREST](https://postgrest.org/en/v12/), [Helm subcharts and globals](https://helm.sh/docs/chart_template_guide/subcharts_and_globals/),
[Chart hooks](https://helm.sh/docs/topics/charts_hooks/), [StatefulSet storage](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/#volume-claim-templates).

## Your notes

Record versions, observations, failures, and explanations here.

