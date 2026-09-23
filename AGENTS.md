# AGENTS.md — ab-development

---

## 1. What this repo is

`ab-development` is a **thin orchestration shell**, not the product. It contains a
`docker-compose.yml`, an `.env` pinning every image tag, a few bash scripts, the Cypress
e2e harness, and log/fail2ban conventions. **Almost no application code lives here.**

All real code lives in **20 git submodules** under `developer/` (see `.gitmodules`).
Each submodule checkout is bind-mounted over the corresponding published image's `/app`,
so you edit source on the host and the container picks it up.

The product is **AppBuilder (AB) v2** — a multi-tenant, definition-driven low-code
platform. Builders design applications in a browser IDE (ABDesigner); those designs are
stored as JSON "definition" rows, and a fleet of Node microservices interprets them at
runtime to create real MySQL tables, run CRUD, execute BPMN processes, render reports,
and push live updates to browsers.

Upstream's canonical installer is a separate external tool, `ab_cli`
(<https://github.com/CruGlobal/ab-cli>) — every submodule README points there. This repo
is a hand-rolled alternative. CI uses a third path (`CruGlobal/ab-install-action@v1`).

---

## 2. Read this before running anything

### 2.1 Destructive scripts

Two scripts perform **parallel, destructive git operations across every submodule**.
`build.sh` is entirely unguarded and will discard uncommitted work; `dev-update.sh` stashes
and restores tracked changes, but still `rm -rf`s asset trees and `git restore`s every
submodule. Check `git status` across submodules before running either.

**Commit before running `dev-update.sh`.** It stashes the root repo at line 23 — so if
`dev-update.sh` itself is modified-but-uncommitted, the stash reverts the script *while bash
is executing it*, and restores it again at line 78.

| Script | npm script | What it does |
|---|---|---|
| `build.sh` | `npm run build`, `npm run build:prod` | `rm -rf` on asset trees, `git add . && git reset . && git restore .` (discards changes), `git checkout master/develop`, `git submodule deinit --all -f`, then **`docker build` + `docker push` of 13 images to Docker Hub**. |
| `dev-update.sh` | `npm run dev:update` | `git stash` → `checkout <canonical branch>` → `pull` → `checkout <prior branch>` → `npm install -f` → `git add/reset/restore` → `stash apply/drop`, for the root repo **and all 20 submodules in parallel background subshells**. In the `developer/services/web` subshell it also `rm -rf`s **both** `developer/services/web/assets` and `developer/ui/web/assets`, then re-copies the former over the latter (lines 31–46). Tracked changes survive (the stash restores them), but `developer/ui/web/assets/mobile/**` is **deleted on every run** — those files are tracked and are not present in `services/web/assets`, so the copy does not restore them. |

`dev-update.sh`'s stash is **guarded**: it compares `git stash list` before and after and
runs `stash apply` + `stash drop` only if that run created an entry (lines 18–28, 77–79). A
pre-existing `stash@{0}` is left alone. Before the guard, the unconditional apply/drop
restored and then permanently deleted whatever stash happened to be there, across 21 repos.

Two kinds of output are **expected and harmless**: `rm: cannot remove …: Is a directory` ×9
from the `developer/services/web` subshell (that `rm` omits `-rf` deliberately — see the
comment at line 37), and `No local changes to save` from every clean repo.

`npm run build` also **publishes to a public registry**. Do not run it to "test the build."

### 2.2 Confirm before

- Anything that pushes images, commits, or touches a remote.
- `npm run build`, `npm run build:prod`, `npm run dev:update` — all three perform destructive
  git operations across every submodule in parallel (§2.1).
- `npm run swarm:start` / `npm run swarm:stop` — these deploy to / tear down a Docker Swarm
  stack, not the local compose stack.
- `docker compose down -v` or removing the `mysql_data` / `files` volumes — that destroys
  the local tenant databases and uploaded files.
- Editing files inside `developer/**` — those are **separate git repos**. A change there is
  a change to a CruGlobal submodule, not to this repo. Check `git -C <submodule> status`
  and which branch you are on before editing.

### 2.3 Paths that are not what they look like

| Path | Reality |
|---|---|
| `nginx/default.conf`, `nginx/custom_log.conf` | **Not mounted by anything.** The nginx config comes from `developer/services/web/default.conf` — but that file is **not mounted either**. `services/web/Dockerfile` copies it to `/etc/nginx/conf.d/default.conf` at **image build time**; the bind mount only places it at `/app/default.conf`, which nginx never reads. Editing it changes nothing until `ab-web` is rebuilt, not even after `docker compose restart web`. Branch matters too: `services/web`'s `master`/`staging` carry the gzip block and the `application/javascript mjs` MIME type (PDF.js); its canonical `develop` does **not**. |
| `config/local.js` | **Not mounted into any container.** Byte-identical to `config/example.local.js`; only `dev-update.sh` touches it. Runtime config comes from env vars via `developer/libs/ab-utils/utils/defaults.js`, and each service reads its **own** `<service>/config/local.js`. |
| `start.sh` (repo root) | Byte-identical dead duplicate of `developer/ui/start.sh`. Only the latter executes. |
| `assets/` (repo root) | Mounted by nothing. Legacy copy. The live tree is `developer/ui/web/assets`. |
| `test/setup/test-compose.yml`, `test/setup/ci-test.overide.yml` | Referenced by nothing. The main `docker-compose.yml` already mounts `reset.sh` + supplies the `CYPRESS_*` vars. |
| `developer/ui/web` vs `developer/services/web` | The first is the **build-output asset root**; the second is the **nginx service submodule** that carries a committed copy for the image. Scripts copy between them in both directions. |
| `developer/components/platform_service/core/`, `developer/ui/platform_web/AppBuilder/core/`, `developer/ui/platform_pwa/src/js/AppBuilder/core/`, `developer/services/<svc>/AppBuilder/` (all 6 AppBuilder services) | **Empty on disk.** They are **uninitialized** nested submodules — the root `git submodule init && update` (`dev-update.sh:9`) is not recursive, so `npm run dev:update` will not populate them; `build.sh` additionally deinits the nested copies under `developer/ui/platform_web` (line 29) and `developer/services/<svc>` (lines 67, 69). They are populated only by compose bind mounts. Static navigation through them fails locally — see the resolution table below. |
| `.gitmodulescp` | Used by nothing. A stale copy of `.gitmodules` (it still lists `relay`, removed from `.gitmodules`) — but the only file in the repo that records the canonical `branch =` pins; `.gitmodules` has **zero** `branch =` lines. |
| `web_assets` volume | Declared in `docker-compose.yml`, mounted by nothing. Dead. |

**Cross-repo import resolution.** Imports that cross submodule boundaries do not resolve on
disk. Resolve them by hand:

| Import seen in | Resolves on disk to |
|---|---|
| `<service>/handlers/*.js`: `../AppBuilder/...` | `developer/components/platform_service/...` |
| `platform_service/platform/*.js`: `../core/...` | `developer/components/class_core/...` |
| `platform_web/AppBuilder/platform/*.js`: `../core/...` | `developer/components/class_core/...` |
| `class_core/*.js`: `../platform/...` | `developer/components/platform_service/platform/...` (server) or `developer/ui/platform_web/AppBuilder/platform/...` (browser) |

`../AppBuilder/...` is by far the most common — 73 files across the 6 AppBuilder services,
including line 1 of `appbuilder/handlers/model-get.js`.

---

## 3. Commands

Every docker/cypress command is wrapped in `env-cmd`. Compose itself already reads `./.env`,
so a bare `docker compose config` resolves the `- VAR` passthrough entries identically
(verified: `MYSQL_PASSWORD: root`, `CAS_ENABLED: "false"`). `env-cmd` is load-bearing for the
cypress commands, which need `CYPRESS_*` in the real process environment, and for the
`test-*.sh` wrappers, which read `${CYPRESS_STACK}` / `${STACKNAME}` from the shell — always
run those via `npm run …`.

For anything the npm scripts do not cover, prefix with env-cmd rather than inventing a
script: `npx env-cmd docker compose restart api_sails`,
`npx env-cmd docker compose logs -f --tail=100 appbuilder`,
`npx env-cmd docker compose exec db mysql -uroot -p$MYSQL_PASSWORD`.

**npm 12 gates.** npm 12 added `allow-*` policies that this repo trips twice.

- `allow-git` (valid values: `all`, `none`, `root`) must be **`all`**. It defaults to `none`,
  refusing the `github:CruGlobal/ab-utils#<ver>` dependency that **11 services** declare
  (`EALLOWGIT`). **`root` is not sufficient** — it permits git URLs only for *direct*
  dependencies, and `api_sails` pulls `cas` transitively via `passport-cas2`. npm offers no
  narrower option, so do not "tighten" this back to `root`.
- `allow-scripts` is rejected as a **command-line flag** on any local install — and `npm run`
  exports every npmrc value to child processes *as a flag*. So an `allow-scripts` entry in any
  npmrc (yours, or the repo's) makes every `npm install` nested inside an npm script die with
  `EALLOWSCRIPTS`. The value's shape is irrelevant: a boolean and a list both fail. Only its
  **absence from the environment** works.

`dev-update.sh` handles both itself — it clears the inherited variable with
`env -u npm_config_allow_scripts` and passes `allow-git` explicitly — so it works regardless
of your personal npmrc. Any *new* script that shells out to `npm install` must do the same.
For installs you run by hand inside a submodule, put `allow-git=all` and
`allow-scripts[]=` entries in your `~/.npmrc`. Do **not** add an `allow-scripts` entry to a
project `.npmrc` at the repo root — `npm run` will export it and reintroduce `EALLOWSCRIPTS`.

```bash
# First-time setup (seeds .env + config/local.js, inits submodules, npm installs each)
npm run dev:update            # see §2.1 — destructive across submodules

# Run the stack
npm start                     # docker compose up -d
npm stop                      # docker compose down
npm run logs                  # docker compose logs -f — ALL 15 services interleaved.
                              # `npm run logs -- <service>` does NOT work: npm appends the
                              # arg to the end of the whole string, which is the `||`
                              # fallback branch, so everything is tailed anyway, silently.
                              # One service: npx env-cmd docker compose logs -f --tail=100 <svc>

# Second, isolated stack for e2e (same compose file, -p $CYPRESS_STACK)
npm run start:test
npm run stop:test
npm run logs:test
npm run test:reset            # reset DB in the test stack, then run migration_manager

# e2e
npm run cypress:open
npm run test:e2e
npm run test:e2e:ab-runtime
npm run test:e2e:app
npm run test:e2e:ab-designer  # BROKEN: matches 0 specs (see below)

# Build + PUSH images (see §2.1 before running)
npm run build                 # tag: guy-latest
npm run build:prod            # tag: guy-prod, then guy-latest

# Swarm — NOT the dev path; deploys to a Docker Swarm cluster
npm run swarm:start           # docker stack deploy -c docker-compose.yml $STACKNAME
npm run swarm:stop            # docker stack rm $STACKNAME
npm run swarm:logs            # BROKEN: `node logs` — logs/ has no index.js or package.json
```

Per-submodule quality gates (run inside the submodule you changed):

```bash
npm run lint                  # eslint, always --max-warnings=0 where it exists.
                              # WRITES TO YOUR FILES: 14 of the 16 lint scripts pass --fix.
                              # Only api_sails is read-only. Diff or commit first.
npm test                      # where a test/ dir exists
```

**No `lint` script exists in `class_core` (no `package.json` at all), `platform_service`,
`ABDesigner`, `platform_pwa`, `services/web`, or `services/db`.** For changes confined to
those repos report lint as *not applicable*, not as failed.

### Local URLs and ports

`.env` is gitignored and per-developer — these are **this checkout's** values; a fresh clone
gets `example.env` copied by `dev-update.sh`, whose defaults differ. Read your own `.env`.

| What | Where |
|---|---|
| App (nginx → api_sails) | `http://localhost:23802` (`WEB_PORT`; `example.env` default 8080) |
| Stack names | `STACKNAME=ab-development`, `CYPRESS_STACK=ab-development-test` (`example.env` defaults: both `ab_runtime`) |
| api_sails direct (bypasses nginx) | `http://localhost:1337` |
| MariaDB | `localhost:8899` (`DB_PORT`) |
| Node inspectors | host `9229`–`9241`, in compose declaration order (see §4.1) |

---

## 4. Architecture

### 4.1 Container topology

`docker-compose.yml` declares 4 named volumes, 1 attachable `default` network, and
**15 active services**. The `AB_*_VERSION` variables are a different set: `.env` and
`example.env` each declare **14**, all of which feed active compose blocks. `ui_compiler` is
versioned by `$NODE_VERSION`, not an `AB_*` var.

- `ui_compiler` — plain `node:$NODE_VERSION`, runs `developer/ui/start.sh`, which spawns
  `npm run watch` (webpack `--watch`) for platform_web, platform_pwa, ABDesigner, HRTeams.
  **It never runs `npm install`** — `node_modules` must already exist on the host.
- `web` — `digiserve/ab-web` (nginx), `$WEB_PORT:80`.
- `db` — `digiserve/ab-db` (MariaDB 10), `$DB_PORT:3306`.
- `redis` — stock redis, no published port.
- 11 Node microservices, all `working_dir: /app`, `depends_on: [redis]`, and
  `command: ["node","--inspect=0.0.0.0:9229","--watch","app.js"]`, with host debug ports
  allocated per service (9235 and 9239 are now unused): `migration_manager` 9229 (depends_on
  **db**), `api_sails` 9230, `appbuilder` 9231, `custom_reports` 9232,
  `definition_manager` 9233, `file_processor` 9234, `log_manager` 9236,
  `notification_email` 9237, `process_manager` 9238, `tenant_manager` 9240,
  `user_manager` 9241.

**`api_sails` is the exception**: it has no `command:` override, so it runs the image
entrypoint with CMD `app_waitMysql.js` and **no `--watch`**. Editing api_sails source
requires `docker compose restart api_sails`. Every other Node service hot-restarts.

There are **no healthchecks and no restart policies**. `depends_on` gives start order only;
services race redis/db on boot. Only `api_sails` compensates (`app_waitMysql.js`).

Bind-mount pattern — this is the dev loop:

- every **Node** service (the 11 above): its own submodule → `/app`, plus `./developer/libs`
  → `/app/node_modules/@digiserve` (local ab-utils shadows the published package).
  `ui_compiler` mounts `./developer/ui` (a plain tracked directory, not a submodule) and
  `web` mounts `./developer/services/web` at `/app`, but neither gets the libs mount; `db`
  and `redis` get neither;
- services with AppBuilder business logic additionally get
  `./developer/components/platform_service` → `/app/AppBuilder` and
  `./developer/components/class_core` → `/app/AppBuilder/core`:
  `appbuilder`, `custom_reports`, `definition_manager`, `file_processor`,
  `process_manager`, `user_manager`;
- thin services without those: `api_sails`, `migration_manager`, `log_manager`,
  `notification_email`, `tenant_manager`. `api_sails` alone also mounts
  `./logs/appbuilder/` → `/var/log/appbuilder/`, `./test/e2e/cypress/e2e` → `/app/imports`,
  and the `files` volume at `/data`.

### 4.2 Subsystem reference

Subsystem detail lives in **[`docs/architecture.md`](docs/architecture.md)** — read it when
you are working inside one of these areas:

| Section | Covers |
|---|---|
| 1. Messaging — cote | axon TCP vs Redis discovery, the `<service>.<handler>` key convention, the wire envelope, pub/sub channels, what `ABServiceController` supplies |
| 2. Domain model | why everything is a row in `appbuilder_definition`, ID-reference graphs, parked broken references |
| 3. The core/platform split | the alternating core↔platform inheritance chain and the rule for where new behaviour goes |
| 4. Multi-tenancy | database-per-tenant, the load-bearing `admin` tenant identity, why SQL must be DB-qualified |
| 5. Request lifecycle | browser → nginx → api_sails policy stack → cote → service → knex, and the socket return path |
| 6. Front end | vendored Webix Pro, the four webpack projects, the v0/v1 plugin generations, config-as-executable-JS |

Widget-level detail for the HR org chart lives in
**[`docs/hrteams-widget.md`](docs/hrteams-widget.md)** — its build/cache-bust chain, the
progress-status card, the change-to-Principal flow, and the Webix clipping and paged-`getData()`
traps that cost the most time to diagnose.

---

## 5. Where things live

| Concern | Location |
|---|---|
| Shared service runtime (cote, req objects, config, logging, telemetry) | `developer/libs/ab-utils` |
| Isomorphic domain model | `developer/components/class_core` (branch **`v2`**) |
| Server-side platform (ABModel, knex/Objection, migrations, ABFactory) | `developer/components/platform_service` |
| HTTP/socket front door | `developer/services/api_sails` |
| Runtime CRUD data plane | `developer/services/appbuilder` |
| Definition ownership + schema migration + `definition.*` events | `developer/services/definition_manager` |
| BPMN process engine | `developer/services/process_manager` |
| Uploads (clamav + imagemagick, shared `files` volume) | `developer/services/file_processor` |
| Tenants / identity | `developer/services/tenant_manager`, `developer/services/user_manager` |
| Platform SQL patches (`yyyymmdd.sql`) | `developer/services/migration_manager` |
| Site/tenant DB seed SQL, MariaDB conf | `developer/services/db` (`init/*.sql` → `/docker-entrypoint-initdb.d`) |
| Browser runtime portal | `developer/ui/platform_web` |
| Design IDE plugin | `developer/ui/plugins/ABDesigner` |
| nginx image + committed asset snapshot | `developer/services/web` (branch **`develop`**) |

Canonical submodule branches: `class_core` → `v2`, `services/web` → `develop`, everything
else → `master` (recorded in `.gitmodulescp`, enforced by `dev-update.sh:37-42` and
`build.sh:15,83`).

**Definition ownership is strictly one-way.** Only `definition_manager` calls
`AB.definitionCreate/Update/Destroy`. `appbuilder` and `custom_reports` are pure consumers
via `ABBootstrap.init(req)`.

---

## 6. Conventions

### Style

Enforced mechanically by `.editorconfig` + eslint/prettier (3-space indent, LF, 80 columns) —
run the submodule's `lint` script rather than matching style by hand. See §3 for the caveats.

### Adding a cote handler (the common case)

Drop a file in `<service>/handlers/`. There is no route table — the controller
`fs.readdirSync`s the directory and registers anything exporting both `.key` and `.fn`.

```js
module.exports = {
   key: "<service_key>.<handler-name>",   // convention only — NOT enforced. The loader
                                          // registers any module exporting .key + .fn
                                          // (ab-utils/utils/controller.js:212-228); it never
                                          // looks at the filename. Several handlers diverge
                                          // on purpose. The key is the wire contract —
                                          // never rename it to match a filename.
   inputValidation: {
      objectID: { string: { uuid: true }, required: true },
   },
   fn: function handler(req, cb) {
      // req.param(...) values are already joi-validated
      // req.log(...) / req.notify.developer(err, {context}) / cb(err, data)
   },
};
```

Rules:

- Read params with `req.param(k)`, never `req.body`/`req.query`.
- Read config with `req.config()`, never by requiring `config/local.js` directly.
- Log with `req.log()` / `req.log.verbose()`; report faults with `req.notify.developer()`
  (operational) or `req.notify.builder()` (tenant/app-configuration).
- Any handler touching tenant data starts with `const AB = await ABBootstrap.init(req)`.
- Wrap DB/network work in `req.retry(() => ...)`.
- Long calls pass `{ longRequest: true }` as the **options argument**, never inside `jobData`.
- Handlers must be **idempotent** — the request layer can re-send a timed-out call up to
  5 + 50 times.
- Both module systems are live. Declared ESM (`"type": "module"`): `appbuilder`,
  `custom_reports`, `definition_manager`, `file_processor`, `migration_manager`,
  `notification_email`, `process_manager`, `user_manager` (and `platform_service`). No `type`
  field: `api_sails`, `log_manager` (CommonJS source) and
  `tenant_manager` (**ESM source with no marker** — it only loads because Node detects module
  syntax, and logs a `MODULE_TYPELESS_PACKAGE_JSON` warning on every boot). Match the service
  you are in. New code should prefer ESM.

### Adding an api_sails endpoint

One controller file per endpoint at `api/controllers/<service_domain>/<handler>.js`, a route
in `config/routes.js`, a module-level `var inputParams = {...}`, then:
`req.ab.log()` → `req.ab.validUser()` / `req.ab.validateParameters(inputParams)` →
build `jobData` → `req.ab.serviceRequest(key, jobData, opts, cb)` →
`res.ab.success()` / `res.ab.error()`.

Also add any new backend service to the `servicesToPing` lists in **both**
`api/hooks/healthcheck.js` and `api/hooks/versionCheck.js`.

### Adding a service to the stack

1. submodule entry in `.gitmodules`;
2. a compose block following the house pattern — image
   `docker.io/digiserve/ab-<name-with-hyphens>:$AB_<NAME>_VERSION`, next free `92xx:9229`,
   `COTE_DISCOVERY_REDIS_HOST=redis`, `MYSQL_PASSWORD`, the 2-or-4 bind mounts,
   `depends_on: [redis]`, `working_dir: /app`, the `node --inspect --watch app.js` command;
3. an `AB_<NAME>_VERSION` line in `example.env`;
4. the service name in `build.sh`'s loop list.

Compose service names are `snake_case`; Docker image names are `kebab-case`. `build.sh`
translates with `${ab_service/_/"-"}`, which replaces **only the first underscore** — so a
service name may contain at most one.

Do **not** copy `migration_manager`'s compose block as a template: it is a run-once program,
not a long-lived cote responder.

### Adding a field type or widget

- **Field type:** core class + `static defaults()` / `static defaultValues()` + registration
  in `ABFieldManager`, **plus** a platform subclass in *every* platform repo you care about
  (`migrateCreate(req, knex)`, `jsonSchemaProperties(props)`, usually `conditionKey()`).
  Fields cannot yet ship as plugins — `createField` is commented out in both `ABClassManager`
  implementations, and `platform_web`'s has no `registerFieldType` at all (nothing ever writes
  to its `classRegistry.FieldTypes` map).
- **Widget/view:** ship it as a v1 plugin factory `(pluginAPI) => Class`, extending a base
  from `getPluginAPI()`. Persisted view keys for plugin-supplied widgets **must start with
  `plugin_`** so `ABViewManagerCore.isPlugin()` suppresses the not-yet-defined error before
  the plugin loads.

A `key` string is persisted into definition rows. **Renaming a field/view/task `key` breaks
every existing definition.**

### Naming that is load-bearing

Table/column identifiers must come from helpers (`object.dbTableName()`, `field.dbPrefix()`,
`field.relationName()`, `req.tenantDB()`), never hand-built strings.

---

## 7. Traps

Architectural:

- **Conditions compile to raw SQL strings**, not bound parameters — escaped only by a local
  `quoteMe()` that doubles single quotes, then applied via `query.whereRaw()`. Any new rule
  type must do its own quoting.
- **`includeScopes()` is called by the handler, not by `ABModel.findAll()`.** A new entry
  point that queries data bypasses scope filtering unless it calls it explicitly. It is also
  a deliberate no-op for `username === "_system_"`.
- **`req.broadcast` completes *before* `cb()`** in appbuilder's write handlers — other
  clients see the change before the editing client gets its reply. Only rowlog, process
  trigger, and cache invalidation are fire-and-forget after `cb()`; errors there cannot
  reach the client.
- `BroadcastManager` keys live requests by **`user.username` alone**. Only 4 controllers
  register (`model-get`, `model-get-count`, `model-post`, `model-post-batch`) — `model-update`
  and `model-delete` never do — and `unregister` is called *unconditionally* while `register`
  is guarded by `if (req.isSocket)`. A plain HTTP request from the same user can evict a
  concurrent socket registration.
- **`ABDataCollection.getData()` searches only the rows already loaded**, which is a page,
  not the table (measured: 941 of 942 rows in one collection). Any
  `dc.getData((e) => e[pk] == id)[0]` can return `undefined` for a real record — most often a
  brand-new one, or one created earlier in the same session. Guard the lookup; do not assume a
  hit.
- `req.workerExec()` does not exist on the controller. Use `req.worker()`.
- `AB.config()` returns a **Promise** since the ESM conversion; at least one caller does not
  await it.

Environment / configuration:

- **The `relay` service is gone, but its auth strategy is not.** The submodule and its
  compose block were removed, yet `api_sails` still registers the `relay` passport strategy
  (`api/policies/authUser.js:32`) and still reads `RELAY_ENABLE` / `RELAY_SERVER_TOKEN`
  (`api_sails/config/local.js:58-66`, passed through by compose). `RELAY_ENABLE` defaults to
  **true** and compose passes the misspelled `RELAY_ENABLED`, so it **cannot be disabled from
  `.env`**; `RELAY_SERVER_TOKEN` is empty and `ab-utils`' `env()` treats `""` as unset
  (`utils/defaults.js:15`), so the token falls through to `"There is no spoon."`. Net effect:
  `authorization: relay@@@There is no spoon.@@@<SiteUser.uuid>` still authenticates as any
  user (`api/lib/authUserRelay.js:22-26`) — now with nothing legitimately using it. Removing
  that strategy is unfinished work. The same env-name typo shape exists for
  `CUSTOM_REPORTS_ENABLED` vs `CUSTOM_REPORTS_ENABLE`.
- **`AB_TESTING=true` is hardcoded on api_sails in the default (non-test) stack**
  (`docker-compose.yml:148`), un-404ing `POST /test/reset`, `POST /test/import` (reads a
  caller-supplied path under `process.cwd()`, `test-import.js:41-43`) and `POST /testlog`.
  All three still run the default policy stack, so they require a logged-in user.
  `GET /versioncheck` and `GET /healthcheck` are **not** `AB_TESTING`-gated — they are
  registered unconditionally in `routes.before` and are always exposed.
- A request from `localhost`/`127.0.0.1` with **no `tenant-token` header and no `?tenant=`
  query param** is treated as the **admin tenant** whenever `NODE_ENV !== "production"`
  (`authTenant.js:35-58`), and compose sets `NODE_ENV=development`.
- **CSRF is not enabled anywhere** (`config/security.js` has every option commented out), and
  there is no `GET /csrfToken` route.
- All 11 Node inspectors are published on the host with `--inspect=0.0.0.0`.
- `authTenant`'s prefix→uuid `hashLookup` is module-level and never invalidated; a renamed
  tenant key resolves to the old uuid until api_sails restarts.
- `developer/services/db/init/*.sql` runs **only when the `mysql_data` volume is empty**.
  Editing it does nothing to a running stack — the site DB, `site_tenant` seed and site
  tables were created on first boot. `test/setup/reset.sh` (via `npm run test:reset`) re-runs
  only `03-site_tables.sql` and `02-tenant_manager.sql` against one tenant DB.

Local environment:

- **`GET /` 404s until `ui_compiler` finishes its first webpack build.**
  `./developer/ui/web/assets` is mounted *over* `/app/assets` and currently holds only the
  9 static directories — no `index.html`, no bundles. The fully populated
  `developer/services/web/assets` is shadowed by that mount. `build.sh` wipes the former at
  the end of every run.
- `reset.sh` pipes `test/setup/reset-user.sql` into mysql, but that path is gitignored and
  ships with no source file — so Docker materializes it as an empty **directory** on a fresh
  checkout. When that happens `cy.ResetDB()` restores the schema but never the test user.
  Check with `ls -ld test/setup/reset-user.sql`.
- **Cypress will hit the wrong port.** `CYPRESS_BASE_URL` is `http://localhost:8080` in both
  env files while `.env` sets `WEB_PORT=23802`, and none of the four cypress configs declares
  a `baseUrl` — so `CYPRESS_BASE_URL` is the only source of it.
- `test-reset.sh` hardcodes `digiserve/ab-migration-manager:master`, ignoring
  `AB_MIGRATION_MANAGER_VERSION`, and mixes `STACKNAME` with `CYPRESS_STACK`. The names line
  up only because `.env` happens to set `ab-development` and `ab-development-test`.
- **Image/source desync.** Compose mounts host source over `/app` while `node_modules` stay
  baked into the image, so source and image diverge silently as submodules are pulled forward
  without a rebuild. Before trusting a module-resolution or interop error, compare
  `docker images` dates against `git -C <submodule> log -1`.
- **`ab-utils` must be checked out at the commit the services declare.** `node_modules/uuid`
  is a *symlink* to `@digiserve/ab-utils/shims/uuid`, and compose mounts `./developer/libs`
  over `/app/node_modules/@digiserve` — so that symlink resolves into whatever `ab-utils` is
  **checked out**, not what npm installed. Check out a branch whose tree lacks `shims/`, and
  every service dies with `Cannot find package 'uuid'` from `/app/AppBuilder/queries/…`.
  Switching `ab-utils` branches also requires reinstalling its `node_modules`, or
  `telemetrySentry.js` resolves a stale `@sentry/node` and every service fails telemetry init
  (`Sentry.SentryContextManager is not a constructor`).
- **Nothing restarts.** There are no `restart:` policies, so a Docker daemon restart leaves
  every container `Exited (255)` and the stack simply stays down until you `npm start`.
- **`docker compose ps` is not a health signal.** The Node services run under `node --watch`,
  which keeps the container alive after `app.js` throws ("Failed running 'app.js'. Waiting for
  file changes..."). A stack reporting 14/16 `running` can have zero working services. Only
  `api_sails` (no `--watch`) and `web` fail visibly. Check logs or `/healthcheck`.
- `migration_manager` never sorts its patch list (`fs.readdirSync` order) while the
  applied-check is a lexical compare — an out-of-order read silently skips a patch forever.
- A tenant created by `tenant_manager.tenant-add` gets **no `SITE_CONFIG` table**; that only
  appears when `migration_manager` runs. Nothing triggers the migrator automatically.

---

## 8. Feature work spanning submodules

A feature usually spans three repos: the service handler, the api_sails controller + route,
and the ABDesigner/platform_web UI. Each is a separate git repo with its own branch.

**Because of that, a repo-wide grep is not evidence a feature is missing** — the other halves
may exist on a branch the submodule is not currently checked out on. Check
`git -C <submodule> branch -a` and `git diff --stat master...<branch>` before concluding
anything is unimplemented.

Read a file off a branch with `git -C <submodule> show <branch>:<path>` rather than checking
the branch out — checking a submodule branch out desyncs it from the superproject pin.

---

## 9. Validation

There are no unit tests at the orchestration level. Proportional validation for a change:

1. `npm run lint` in each submodule you touched (most enforce `--max-warnings=0`).
2. `npm test` in submodules that have a `test/` directory (not all do — check before
   assuming a test gate exists).
3. Bring the stack up and check the service actually started — `npx env-cmd docker compose
   logs -f --tail=100 <service>`, or
   `curl -s -w '\n%{http_code}\n' 'localhost:1337/healthcheck?timeout=5000'`.
   **200 = all services OK; 207 = one or more unhealthy** — it never returns 5xx for a down
   service, so "curl returned JSON" is not a pass. The default per-service ping timeout is
   30 s, hence the `timeout` query param.
4. For anything touching the browser tier, confirm `ui_compiler` rebuilt (`npm run logs`)
   before testing in the browser.
5. e2e via `npm run test:e2e*` — note the `CYPRESS_BASE_URL` and `reset-user.sql` issues in
   §7 first.

Report each gate as passed / failed / blocked / not run, with the exact command. Do not
report "should work" for a gate that was not executed.
