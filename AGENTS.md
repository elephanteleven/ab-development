# AGENTS.md — ab-development

---

## 1. What this repo is

`ab-development` is a **thin orchestration shell**, not the product. It contains a
`docker-compose.yml`, an `.env` pinning every image tag, a few bash scripts, the Cypress
e2e harness, and log/fail2ban conventions. **Almost no application code lives here.**

All real code lives in **17 git submodules** under `developer/` (see `.gitmodules`), plus
the submodules nested in them: platform_service (`AppBuilder`) and class_core
(`AppBuilder/core`) inside six services, and class_core inside ab_platform_web and pwa.
Each service's checkout is bind-mounted over the corresponding published image's `/app`,
so you edit source on the host and the container picks it up. The UI repos are built on
the host with `npm run watch` into `developer/web/assets`, which nginx serves (§4.1).

The product is **AppBuilder (AB) v2** — a multi-tenant, definition-driven low-code
platform. Builders design applications in a browser IDE (ABDesigner); those designs are
stored as JSON "definition" rows, and a fleet of Node microservices interprets them at
runtime to create real MySQL tables, run CRUD, execute BPMN processes, render reports,
and push live updates to browsers.

**The three apps you see, and what they are for** (repo owner, 2026-10-02). In the portal
everything is an "app", but they are different kinds of thing:

- **Site Administration**: a built-in definition app for managing users, roles and
  permissions.
- **AB Designer**: the IDE for AppBuilder developers to build apps. It is delivered as a
  plugin of the *app* type. In theory app-type plugins should be installable and removable;
  that work is not done and is not planned for now.
- **NetSuite HR Update**: our real product app. It uses the HR Teams plugin, a *widget*-type
  plugin. Ideally that widget would be generic so any app could use it like the built-in
  widgets, but it was built in a hurry and is **designed for this app only**, for now
  (also hardcoded per tenant, see [docs/plugins/hrteams-widget.md §1.2](docs/plugins/hrteams-widget.md#12-which-tenants-load-it-at-all)).
  Apart from that, AppBuilder must keep building ordinary apps normally: do not let
  HR-Teams-specific needs leak into the platform.

Upstream's canonical installer is a separate external tool, `ab_cli`
(<https://github.com/CruGlobal/ab-cli>) — every submodule README points there. This repo
is a hand-rolled alternative. CI uses a third path (`CruGlobal/ab-install-action@v1`).

---

## 2. Read this before running anything

### 2.0 House rules

Set by the repo owner. They hold in every session unless the owner says otherwise for that
exact action.

- **Lifecycle is `npm start` / `npm stop` only.** Not `start:test`, not `swarm:*`, not a
  hand-rolled `docker compose up/down`. A fix must take effect through a plain
  `npm stop && npm start`, with no extra manual step. Read-only inspection with
  `npx env-cmd docker compose logs|ps|exec` is fine. The one manual step is the UI build:
  the stack does not build the UI; run `npm run watch` by hand in each UI repo you work on (`developer/ab_platform_web`, `developer/pwa`,
  `developer/plugins/ABDesigner`, `developer/plugins/HRTeams`; owner).
- **`developer/web` stays on `develop`.** Never check out, commit to, or propose
  changes on its `master` yourself. `build.sh` checking master out to build the web image
  (line 10) is expected (§5). The UI builds land in its `assets/`, so its `git status`
  lists them; never commit them by accident.
- **Never touch `main` in any submodule**: no checkout-and-commit, merge, reset, or push, unless
  the owner asks for that exact action.
- **Never change existing definitions in the tenant** (Site Administration, NetSuite HR
  Update, and everything they contain). To experiment with definitions, create a separate app
  of your own and work only inside it (owner, 2026-10-02). Using the existing apps as a user
  (reading, clicking through) is fine. One catch: loading **any** portal page as a builder
  or admin re-saves two NetSuite HR Update definitions (the "Teams" page and its widget),
  because the HR Teams plugin does it when it loads (W24 in
  [docs/known-issues.md](docs/known-issues.md)). Use a non-builder test user when you only
  need to look. One exception was granted for one task (owner, 2026-10-03): new NetSuite
  HR Update definitions for the cross-entity principal change (the object
  `cache-principal-change`, and the process the owner had renamed "Principal Change
  Approval" on 2026-10-04) and the rework of "Updated Assignments", all done
  ([docs/netsuite-hr-update.md §12](docs/netsuite-hr-update.md#12-the-cross-entity-principal-change-since-2026-10-03)).
  On 2026-10-04 the owner approved one more change to those two definitions: the 7-day
  expiry of a request (the field `expires_on`, three new process elements and the
  approval form, §12.9 there). On 2026-10-30 the owner had "Updated Assignments" put back
  to its 2026-10-03 version (41 elements, with the reason Form) for the GitHub #537 tests
  with HR Teams `master`; how, and how to switch back, is in
  [docs/netsuite-hr-update.md §2.4](docs/netsuite-hr-update.md#24-switching-versions-in-this-tenant).
  These exceptions do not extend to other definitions.
- **NetSuite data: only what the HR Teams chart can write** (owner, 2026-10-03). You may
  create or edit Team, Team Assignment and Team Responsibility records, and anything else
  a feature of the HR Teams org chart writes (for example its "Change Supervisor" dialog,
  which sets the supervisor on the employee record). Never create or change other NetSuite
  records outside those chart features. Data in local (AppBuilder) objects may be changed
  freely, except that the NetSuite HR Update `history` records must not be touched until
  the owner says so. The owner allowed it for the GitHub #537 tests, which wrote one row
  per run of "Updated Assignments" (16 on 2026-10-30, 4 on 2026-10-31). These rules are
  about data; the
  definitions rule above still holds.
- **Platform-level problems: list them, do not fix them** (owner, 2026-10-03). The current
  focus is the NetSuite HR Update app, its processes (the flows built in ABDesigner's
  Process Manager, not the process_manager service code) and the HR Teams plugin. When
  work there turns up a problem in the platform itself (class_core, platform_service,
  platform_web, the services), add it to [docs/known-issues.md](docs/known-issues.md) and
  move on, unless the owner asks for that fix.
- **Never read `../global-hr-update/back-end/config`** (the sibling Global HR Update project's
  secrets; owner, 2026-10-02). The rest of `../global-hr-update` may be read.
- **Never read `.env`** (it holds real secrets), and never print secret values from it or
  from a container's environment (owner, 2026-10-02). Use `example.env` and the code for
  variable names.
- **"Take a look" means diagnose, not change.** Find and prove the cause first, with read-only
  checks or throwaway containers, then offer the change and wait for a yes before editing
  compose, scripts, config, or submodules. "Fix it" means fix it.
- **Keep the repos under `developer/` clean and current** (owner, 2026-10-30). Run each on
  its latest upstream commit, with no uncommitted edits, so it is always clear which version
  runs; a change goes on a branch and to a PR, not into the working tree of a checkout that
  stays. Fixes that only lived in working trees were dropped that day (known issues §1).
- **Write down what you learn.** Every verified finding goes into this file (or the matching
  `docs/*.md`) before the task counts as done. When a claim here turns out wrong, correct it in
  place instead of adding a second, conflicting note. Record only verified facts, and label
  inference as inference.
- **Commits and PRs: short, with no AI attribution** (owner, 2026-10-30). One short subject
  line, such as "Fix spinning principal changes", and a PR title that matches it. No
  `Co-Authored-By` trailer naming an AI and no "Generated with ..." line in a PR
  description: the owner's org keeps a separate org for pure-AI work. Committing and
  pushing still need the owner's go-ahead (§2.2).

### 2.1 Destructive scripts

Two scripts perform **parallel, destructive git operations across every submodule**.
`build.sh` is entirely unguarded and will discard uncommitted work; `dev-update.sh` stashes
and restores tracked changes, but still resets the UI build output and `git restore`s
every submodule. Check `git status` across submodules before running either. `build.sh` ran
in full on 2026-10-05 (below). `dev-update.sh` was checked that day with a dry run only:
stand-ins for `git`, `npm` and `rm` that log instead of acting (read-only `git` calls went
through) walked the root repo and all 17 submodules exactly as the table below says. A real
run pulls new commits into every repo, so it was not done.

**Commit before running `dev-update.sh`.** It stashes the root repo at line 30, so if
`dev-update.sh` itself is modified-but-uncommitted, the stash reverts the script *while bash
is executing it*, and restores it again at line 85.

| Script | npm script | What it does |
|---|---|---|
| `build.sh` | `npm run build`, `npm run build:prod` | In `developer/web`: `rm -rf ./assets` + `git add . && git reset . && git restore .` (discards changes), `git checkout master`, then clears the built bundles. Builds ab_platform_web, ABDesigner and HRTeams with their prod configs **straight into `developer/web/assets`** (pwa is not built). In each of the 13 services: `rm -rf node_modules`, `git submodule update --init --recursive` where the repo has nested submodules, **`docker build` + `docker push` to Docker Hub**, `npm install -f` + `git restore ./package-lock.json`. Then web back to `develop`. Nested platform_service and class_core go into the image as checked out (`git submodule update` first moves them to the commits each service records, unless local edits block it, below), and stay initialized. |
| `dev-update.sh` | `npm run dev:update` | For the root repo **and all 17 submodules in parallel background subshells**: `git stash` → `checkout <canonical branch>` → `pull` → `checkout <prior branch>` → `git submodule update --init --recursive` (repos with nested submodules) → `npm install -f` → `git add/reset/restore` → `npm ci` in `AppBuilder` (the six AppBuilder services) → `stash apply/drop`. Before its stash, the `developer/web` subshell deletes `assets/` and checks it out again (line 23), which drops the UI build output; run `npm run watch` again afterwards. |

`dev-update.sh`'s stash is **guarded**: it compares `git stash list` before and after and
runs `stash apply` + `stash drop` only if that run created an entry (lines 25–35, 84–86). A
pre-existing `stash@{0}` is left alone. Before the guard, the unconditional apply/drop
restored and then permanently deleted whatever stash happened to be there, in every repo.

Two kinds of output are **expected and harmless**: `rm: cannot remove …: Is a directory` from
`build.sh` lines 14-16 (that `rm` omits `-rf` deliberately, see the comment above it), and
`No local changes to save` from every clean repo. Nested repos have no stash: `npm ci`
leaves their files alone, but `git submodule update` stops in a nested repo whose local
edits clash with a newly recorded commit, prints that error, and leaves the copy as it is.
Since 2026-10-30 no nested copy has local edits (§2.0).

`npm run build` also **publishes to a public registry**. Do not run it to "test the build."

`build.sh` specifics, verified on full `guy-latest` builds on 2026-09-28 (about 24 minutes)
and 2026-10-05 (about 95 minutes, pushes skipped with the wrapper below):

- **Do not start it through `npm run build` while an `allow-scripts` entry is in any npmrc.**
  `npm run` exports it as `npm_config_allow_scripts`, and unlike `dev-update.sh`, `build.sh`
  does not clear it, so every `npm install -f` it runs hits the §3 `EALLOWSCRIPTS` failure,
  right after line 42 deleted that service's `node_modules`. Run
  `node_modules/.bin/env-cmd bash ./build.sh guy-latest` instead: same `.env`, no npm config
  export.
- **It always pushes.** To build only, put a `docker` wrapper first on `PATH` that exits 0 for
  `push` and `exec`s `/usr/bin/docker` for everything else.
- **Do not start the stack until it exits.** Its last minutes reinstall each service's
  `node_modules`; a stack started meanwhile left api_sails dead on `Cannot find module 'sails'`.
  Wait for the script to finish, then `npm stop && npm start`.
- **Nested submodules must stay initialized.** An empty `AppBuilder/core` makes
  ab_platform_web's webpack fail with 12 `Can't resolve '../core/…'` errors, and an empty
  `AppBuilder` stops an AppBuilder service. Run `git -C <repo> submodule update --init
  --recursive` (plus `npm ci` in a service's `AppBuilder`) and restart the watch build.
- **It discards uncommitted `package-lock.json` edits** in every service (line 54). In `db`,
  which has no `package.json`, that line prints a harmless `pathspec './package-lock.json'` error.
- **An old `Created` date does not mean a failed build.** Docker's layer cache turns an
  unchanged service into a byte-identical image that keeps its old creation time: 10 of 13
  on 2026-09-28, 2 of 13 (log_manager, notification_email) on 2026-10-05. Look for
  `naming to docker.io/digiserve/ab-<svc>:<tag>` in the output instead.
- **A rebuilt service image spends most of its time in `RUN chown -R node:node /app`.** On
  2026-10-05, with the images building in parallel, that step took 48 to 76 minutes per
  rebuilt service (api_sails the longest; BuildKit's `DONE` times in the output), every
  `chown` in disk-wait (`D` state) with IO pressure around 70 %. Inference: on rootless
  Docker's overlayfs each file is copied up again, and this machine's disk is slow.
- **Afterwards the local stack needs a `develop`-built web image.** The script tags
  `digiserve/ab-web:<tag>` with its master build, which answers 502 here (§7). With
  `developer/web` on `develop`, run `docker build -t digiserve/ab-web:guy-latest developer/web`
  (38 s on 2026-10-05, nginx 1.31.6, no `HEALTHCHECK`).
- **It leaves `developer/web/assets` at the committed copy.** Rebuild the UI repos you work
  on afterwards (`npm run watch` or a one-off build, §4.1).

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
| `nginx/default.conf`, `nginx/custom_log.conf` | **Not mounted by anything.** Only `nginx/html` is (→ `/usr/share/nginx/html`). |
| `developer/web/default.conf` | Bind-mounted to `/etc/nginx/conf.d/default.conf`, but **not live with the image `build.sh` makes**. `build.sh:10` builds the `ab-web` image from `developer/web` **master**, whose `nginx.conf` and `templates/app.conf.template` are baked in and covered by no mount. At container start the template renders to `/etc/nginx/conf.d/app.conf` (`listen 80 default_server`, loads first), and this file is shadowed (nginx logs `conflicting server name "localhost" on 0.0.0.0:80, ignored`). So switching the local checkout does not change what nginx serves. Tested 2026-09-29: mounting an empty file over the template (`/dev/null` → `/etc/nginx/templates/app.conf.template`) makes this file the live config again, on master- and develop-built images alike. It is also a **single-file** bind mount: a `git checkout` that replaces it leaves the running container reading the **old** copy until the container is recreated. `develop` has no `conf.d/` at all. |
| `config/local.js` | **Not mounted into any container.** Byte-identical to `config/example.local.js`; only `dev-update.sh` touches it. Runtime config comes from env vars via ab-utils `utils/defaults.js` (in each service's `node_modules/@digiserve/ab-utils`), and each service reads its **own** `<service>/config/local.js`. |
| `assets/` (repo root) | Mounted by nothing. Legacy copy. The live tree is `developer/web/assets`. ABDesigner's webpack alias `assets` (`../../../assets` from `developer/plugins/ABDesigner`) points at this folder; no source file imports through it. |
| `test/setup/test-compose.yml`, `test/setup/ci-test.overide.yml` | Referenced by nothing. The main `docker-compose.yml` already mounts `reset.sh` + supplies the `CYPRESS_*` vars. |
| `developer/web/assets` | The nginx repo's committed asset snapshot **and** where `npm run watch` in each UI repo writes (their webpack configs output to `../web/assets` or `../../web/assets`). After a build, `git -C developer/web status` lists changed bundles: build output, not edits. Mounted with the repo at `/app`. |
| `developer/<svc>/AppBuilder/`, `developer/<svc>/AppBuilder/core/` (the 6 AppBuilder services) | Nested submodules (platform_service, class_core), **initialized on the host** with `git submodule update --init --recursive`, and each `AppBuilder` with its own `node_modules` from `npm ci` (as in the images). The container sees them through the service's own bind mount. Each service runs its own copy, at the commit it records: platform_service `544b83a` (class_core `2ecde31`) in appbuilder, definition_manager and process_manager; `d8d8f49` (1.14.22, class_core `a0008f4` = 2.20.1) in custom_reports, file_processor and user_manager (2026-10-30, no local edits). |
| `developer/ab_platform_web/AppBuilder/core/`, `developer/pwa/src/js/AppBuilder/core/` | Nested class_core, **must be initialized on the host**: webpack reads them directly. ab_platform_web pins `a0008f4` (class_core 2.20.1), pwa an older `d52cad3` (2026-10-30). |
| `.gitmodulescp` | Used by nothing. A copy of `.gitmodules` with `branch =` lines, the only record of the canonical branches (`.gitmodules` has none). |
| `web_assets` volume | Declared in `docker-compose.yml`, mounted by nothing. Dead. |

**Cross-repo imports resolve on disk** now that the nested submodules are initialized:

| Import seen in | Resolves on disk to |
|---|---|
| `developer/<service>/handlers/*.js`: `../AppBuilder/...` | `developer/<service>/AppBuilder/...` (platform_service) |
| `.../AppBuilder/platform/*.js`: `../core/...` | `.../AppBuilder/core/...` (class_core) |
| `developer/ab_platform_web/AppBuilder/platform/*.js`: `../core/...` | `developer/ab_platform_web/AppBuilder/core/...` |
| class_core's `../platform/...` | the platform folder of the repo it sits in: the service's `AppBuilder/platform/` (server) or `developer/ab_platform_web/AppBuilder/platform/` (browser) |

`../AppBuilder/...` is by far the most common: 73 files across the 6 AppBuilder services,
including line 1 of `appbuilder/handlers/model-get.js`. Docs cite appbuilder's copies
(`developer/appbuilder/AppBuilder`, `.../AppBuilder/core`) for platform_service and
class_core.

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
npm run logs                  # docker compose logs -f: ALL 14 services interleaved.
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
                              # WRITES TO YOUR FILES: 12 of the 13 lint scripts pass --fix.
                              # Only api_sails is read-only. Diff or commit first.
npm test                      # where a test/ dir exists
```

**No `lint` script exists in `class_core` (no `package.json` at all), `platform_service`,
`ABDesigner`, `pwa`, `web`, or `db`.** For changes confined to
those repos report lint as *not applicable*, not as failed.

### Local URLs and ports

`.env` is gitignored and per-developer — these are **this checkout's** values; a fresh clone
gets `example.env` copied by `dev-update.sh`, whose defaults differ. Read your own `.env`.

| What | Where |
|---|---|
| App (nginx → api_sails) | `http://localhost:23802` (`WEB_PORT`; `example.env` default 8080) |
| Stack names | `STACKNAME=ab-development`, `CYPRESS_STACK=ab-development-test` (`example.env` defaults: both `ab_runtime`) |
| api_sails direct (bypasses nginx) | `http://localhost:1337` |
| Global HR Update app (the sibling `../global-hr-update`, run separately) | `http://localhost:23803` (owner, 2026-10-29; answered 200) |
| MariaDB | `localhost:8899` (`DB_PORT`) |
| Node inspectors | host `9229`–`9241`, in compose declaration order (see §4.1) |

---

## 4. Architecture

### 4.1 Container topology

`docker-compose.yml` declares 4 named volumes, 1 attachable `default` network, and
**14 active services**. The `AB_*_VERSION` variables are a different set: `.env` and
`example.env` each declare **14**, all of which feed active compose blocks.

The UI is not built by the stack. Run `npm run watch` (webpack `--watch`, development
config) by hand in each UI repo you work on: `developer/ab_platform_web`, `developer/pwa`,
`developer/plugins/ABDesigner`, `developer/plugins/HRTeams` (owner). Each writes into
`developer/web/assets`. Install `node_modules` first if missing; a one-off build is
`npx webpack-cli --config <the watch script's config>` (2 to 15 s each on 2026-10-05).

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

**`api_sails` is the exception**: compose gives it `command: ["app.js"]` (since
2026-10-30), which the image entrypoint runs as `node --inspect=0.0.0.0:9229 app.js`, with
**no `--watch`**. Editing api_sails source requires `docker compose restart api_sails`.
Every other Node service hot-restarts. The image's own CMD, `app_waitMysql.js`, crashes with
upstream api_sails (`TypeError: Cannot read properties of undefined (reading 'site')`):
upstream has had `datastores` commented out in `config/local.js` since 2025-09 (known
issues E14).

Compose defines **no healthchecks and no restart policies**. `depends_on` gives start order
only; services race redis/db on boot. api_sails does not need MySQL to lift, and
appbuilder and process_manager wait for MySQL through `controller.waitForDB`. An
`ab-web` image built from `develop` has no `HEALTHCHECK` either. One built from master does (it
curls `:81/health-check`), and its `(healthy)` proves only that nginx is running, **not** that
nginx can reach api_sails (§7).

Bind-mount pattern, this is the dev loop:

- every **Node** service (the 11 above) mounts only its own repo, `./developer/<service>` →
  `/app`. Its `node_modules` (on the host, from `npm install`) bring ab-utils as the
  published `@digiserve/ab-utils` package, unchanged (since 2026-10-30);
- the services with AppBuilder business logic (`appbuilder`, `custom_reports`,
  `definition_manager`, `file_processor`, `process_manager`, `user_manager`) carry
  platform_service and class_core inside that repo as nested submodules (`AppBuilder`,
  `AppBuilder/core`), so they reach the container through the same mount (§2.3);
- thin services without them: `api_sails`, `migration_manager`, `log_manager`,
  `notification_email`, `tenant_manager`. `api_sails` alone also mounts
  `./logs/appbuilder/` → `/var/log/appbuilder/`, `./test/e2e/cypress/e2e` → `/app/imports`,
  and the `files` volume at `/data`;
- `web` mounts `./developer/web` at `/app` (its `assets/` holds the UI builds),
  `./developer/plugins` at `/app/assets/ab_plugins`, and `./developer/web/default.conf`;
  `db` mounts `./developer/db/conf.d` and `./developer/db/init`; `redis` mounts nothing.

### 4.2 Subsystem reference

Detailed reference lives in **[`docs/`](docs/README.md)**: the platform in `core/`, the
plugins in `plugins/`, a few pages at the top. Read the page for the area you are working in
before changing it.

**[`docs/core/`](docs/core/): the AppBuilder platform** (the code in the submodules).

| Page | Covers |
|---|---|
| [`architecture.md`](docs/core/architecture.md) | Messaging (cote), domain model basics, the core/platform split, multi-tenancy, request lifecycle, front-end generations |
| [`domain-model.md`](docs/core/domain-model.md) | class_core: applications, objects, the 19 field types (keys are persisted and case-sensitive), queries, data collections, filters/operators, process query language, translations |
| [`server-platform.md`](docs/core/server-platform.md) | platform_service: ABBootstrap/ABFactory, knex and Objection, the condition-to-SQL compiler and its escaping, scopes, DDL from definitions |
| [`service-runtime.md`](docs/core/service-runtime.md) | ab-utils: controller lifecycle, the `req` object, `serviceRequest` (5 + 50 resends), validation, telemetry |
| [`services.md`](docs/core/services.md) | Every backend service and all 89 handler keys, config and traps |
| [`processes.md`](docs/core/processes.md) | BPMN: the 21 element types, engine, triggers, timers, inbox/user forms, building a process from the browser console |
| [`api.md`](docs/core/api.md) | api_sails: all routes with their guards and cote keys, policies, auth, sockets, security findings |
| [`database.md`](docs/core/database.md) | Databases, tables, seeds, stored procedures, migration patches, tenant creation |
| [`frontend.md`](docs/core/frontend.md), [`widgets.md`](docs/core/widgets.md) | platform_web portal, building definitions from the browser console, and every built-in web widget |
| [`mobile.md`](docs/core/mobile.md) | Mobile PWA and mobile view types |
| [`site-administration.md`](docs/core/site-administration.md) | The built-in Site Administration app, the apps in the tenant, and the tenant's users, roles and scopes |

**[`docs/plugins/`](docs/plugins/): the plugins.**

| Page | Covers |
|---|---|
| [`abdesigner.md`](docs/plugins/abdesigner.md) | AB Designer, the builder IDE (an *app*-type plugin) |
| [`hrteams-widget.md`](docs/plugins/hrteams-widget.md) | **Everything about the HR Teams plugin** (a *widget*-type plugin): build and cache-busting, progress card, the principal flow in the widget, its data collections, every feature, Webix traps. Its §6 overlaps netsuite-hr-update.md on purpose |

**Top of [`docs/`](docs/README.md): pages without a category.**

| Page | Covers |
|---|---|
| [`netsuite-hr-update.md`](docs/netsuite-hr-update.md) | **Everything about the NetSuite HR Update app**: objects, BPMN processes and run history, who can see what (HR scope), the cross-entity principal change (`cache-principal-change` + "Principal Change Approval": design, tests, full test plan, production checklist; built 2026-10-03, retested 2026-10-04; the widget code committed on HR Teams `guy/enhancements` as `cc217ce` on 2026-10-16, not on `master`), and the sibling Global HR Update web app (`../global-hr-update`). Definition backups are in [`backups/definitions/`](backups/definitions/). An app page, kept here for now because the HR Teams plugin is built on the app's objects and processes (owner, 2026-10-04) |
| [`known-issues.md`](docs/known-issues.md) | The backlog: every known problem with an ID and a priority, plus fixes not yet committed |
| [`testing.md`](docs/testing.md), [`orchestration.md`](docs/orchestration.md) | Test harnesses and testing by hand in the browser (switcheroo, REST calls from the console); compose/env/script reference tables for this repo |

**Where knowledge goes** (owner, 2026-10-04): everything about the NetSuite HR Update app
(its objects, processes, scopes, features built on it, their tests and rollout, and Global
HR Update where it meets the app) goes in
[`docs/netsuite-hr-update.md`](docs/netsuite-hr-update.md), and everything about the HR
Teams plugin in [`docs/plugins/hrteams-widget.md`](docs/plugins/hrteams-widget.md). The two
may overlap, since the plugin is a widget of that app. Do not start a separate page for a
feature of either; add a section to the matching page instead. This repo documents the
**platform**: `core/` for AppBuilder itself, built-in apps included (Site Administration),
`plugins/` for the plugins, anything else at the top of `docs/`. An app that a user builds
with AppBuilder is the user's side, and its docs belong in that app's own repo. NetSuite HR
Update is the one exception for now, kept at the top of `docs/` because HR Teams depends on
it. Platform facts learned in a test app (such as the Claude Sandbox) go into the core or
plugin page of their subject; the test app's own contents (its ids, objects, processes) do
not go in these docs. Backups of tenant definitions, taken before changing them, go in
[`backups/definitions/`](backups/definitions/) at the repo root, not in `docs/` (owner,
2026-10-04).

---

## 5. Where things live

| Concern | Location |
|---|---|
| Shared service runtime (cote, req objects, config, logging, telemetry) | ab-utils: the `@digiserve/ab-utils` package in each service's `node_modules` (repo `CruGlobal/ab-utils`, `#1.11.1` in all eleven) |
| Isomorphic domain model | class_core (branch **`v2`**): nested as `AppBuilder/core` in the AppBuilder services, `developer/ab_platform_web/AppBuilder/core`, `developer/pwa/src/js/AppBuilder/core` |
| Server-side platform (ABModel, knex/Objection, migrations, ABFactory) | platform_service: nested as `AppBuilder` in `developer/{appbuilder,custom_reports,definition_manager,file_processor,process_manager,user_manager}` |
| HTTP/socket front door | `developer/api_sails` |
| Runtime CRUD data plane | `developer/appbuilder` |
| Definition ownership + schema migration + `definition.*` events | `developer/definition_manager` |
| BPMN process engine | `developer/process_manager` |
| Uploads (clamav + imagemagick, shared `files` volume) | `developer/file_processor` |
| Tenants / identity | `developer/tenant_manager`, `developer/user_manager` |
| Platform SQL patches (`yyyymmdd.sql`) | `developer/migration_manager` |
| Site/tenant DB seed SQL, MariaDB conf | `developer/db` (`init/*.sql` → `/docker-entrypoint-initdb.d`) |
| Browser runtime portal | `developer/ab_platform_web` |
| Mobile PWA | `developer/pwa` |
| Plugins (ABDesigner, HR Teams) | `developer/plugins/ABDesigner`, `developer/plugins/HRTeams` |
| nginx image + committed asset snapshot, and the UI build output | `developer/web` (branch **`develop`**) |

Canonical submodule branches: `developer/web` → `develop`, everything else → `master`
(recorded in `.gitmodulescp`); the nested class_core copies follow `v2`, but each sits at the
commit its parent records. **`developer/web` must stay checked out on `develop`.**
`dev-update.sh` pulls each repo's canonical branch (line 50), then returns it to whatever
branch it was on (line 54). `build.sh` still uses web's **master** on purpose: it builds the
`ab-web` image from it (line 10) and returns to develop (line 63). The bind mounts do not make
the image's branch irrelevant: they cover `/app` and `conf.d/default.conf`, not the image's
`nginx.conf` or `templates/` (§2.3, §7).

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
      // inputs are joi-validated and undeclared keys are REJECTED, but
      // req.param(k) returns the raw value, not the normalized one
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
  field: `api_sails`, `log_manager` (CommonJS source), and `tenant_manager` (ESM source).
  `tenant_manager` has ESM source but no marker (its local one was dropped on 2026-10-30), so
  Node re-parses it as ESM and logs `MODULE_TYPELESS_PACKAGE_JSON` on every boot. Its
  `test/unit/handler.js` is CommonJS and fails with `MODULE_NOT_FOUND`. Match the service you are in. New code should prefer
  ESM.

### Adding an api_sails endpoint

One controller file per endpoint at `api/controllers/<service_domain>/<handler>.js`, a route
in `config/routes.js`, a module-level `var inputParams = {...}`, then:
`req.ab.log()` → `req.ab.validUser()` / `req.ab.validateParameters(inputParams)` →
build `jobData` → `req.ab.serviceRequest(key, jobData, opts, cb)` →
`res.ab.success()` / `res.ab.error()`.

Also add any new backend service to the `servicesToPing` lists in **both**
`api/hooks/healthcheck.js` and `api/hooks/versionCheck.js`, and remove it from both when the
service is retired. A stale entry makes every check wait out the full 30 s ping timeout and
pins `/healthcheck` at 207 (relay did exactly this).

### Adding a service to the stack

1. submodule entry in `.gitmodules`;
2. a compose block following the house pattern — image
   `docker.io/digiserve/ab-<name-with-hyphens>:$AB_<NAME>_VERSION`, next free `92xx:9229`,
   `COTE_DISCOVERY_REDIS_HOST=redis`, `MYSQL_PASSWORD`, one bind mount
   (`./developer/<name>` → `/app`; nested submodules come with it),
   `depends_on: [redis]`, `working_dir: /app`, the `node --inspect --watch app.js` command;
3. an `AB_<NAME>_VERSION` line in `example.env`;
4. the service name in `build.sh`'s loop list.

Compose service names are `snake_case`; Docker image names are `kebab-case`. `build.sh`
translates with `${ab_service/_/"-"}`, which replaces **only the first underscore** — so a
service name may contain at most one.

Do **not** copy `migration_manager`'s compose block as a template: it is a run-once program,
not a long-lived cote responder.

### Removing a service from the stack

Undo every step above, then chase its callers. Retiring `relay` took all of these:

1. the submodule (`.gitmodules`), its compose block, its `AB_<NAME>_VERSION` line, and its
   `build.sh` loop entry;
2. env passthroughs other services got for it (compose `environment:` and `example.env`);
3. both api_sails `servicesToPing` lists;
4. every `req.ab.serviceRequest("<service>.…")` caller: api_sails controllers, their routes in
   `config/routes.js`, and their sections in the api_sails `README.md`. `npm run doc`
   regenerates that README from controller comments, but it currently fails on
   `api/controllers/metric_manager/metrics-information.js` (`@api {get} //metrics` has no
   title), so trim it by hand;
5. anything else that trusted it, like relay's passport strategy.

Check handler `inputValidation` before dropping a field named after the service:
`tenant_manager.config-site` still requires a boolean `relay`, so api_sails sends
`relay: false`.

### Adding a field type or widget

- **Field type:** core class + `static defaults()` / `static defaultValues()` + registration
  in `ABFieldManager`, **plus** a platform subclass in *every* platform repo you care about
  (`migrateCreate(req, knex)`, `jsonSchemaProperties(props)`, usually `conditionKey()`).
  Fields cannot yet ship as plugins — `createField` is commented out in both `ABClassManager`
  implementations, and `platform_web`'s has no `registerFieldType` at all (nothing ever writes
  to its `classRegistry.FieldTypes` map). Builders also need a property panel in ABDesigner's
  hardcoded list ([docs/plugins/abdesigner.md §4.5](docs/plugins/abdesigner.md#45-field-property-panels-dspropertiesdatafields)).
- **Widget/view:** ship it as a v1 plugin factory `(pluginAPI) => Class`, extending a base
  from `getPluginAPI()`. Persisted view keys for plugin-supplied widgets **must start with
  `plugin_`** so `ABViewManagerCore.isPlugin()` suppresses the not-yet-defined error before
  the plugin loads. A built-in widget has a runtime half in platform_web and a designer half
  in ABDesigner, each registered in its own `index.js`
  ([docs/core/widgets.md §9](docs/core/widgets.md#9-adding-or-changing-a-widget)).

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
- `AB.config()` returns a **Promise** since the ESM conversion (ab-utils `38833bb`). Two
  callers still use it synchronously: `notification_email/src/send.js:7` (**every email send
  fails**, see [docs/core/services.md §6](docs/core/services.md#6-notification_email)) and
  `appbuilder/app.js:26` (circuit-breaker settings silently fall back to defaults).

Environment / configuration:

- **The `relay` service is retired, but upstream api_sails still trusts it** (`master`
  and `staging`, both `7c6e655` since 2026-10-30; the local removal, known issues C2, was
  dropped). Its passport strategy (`api/lib/authUserRelay.js`, set up in
  `api/hooks/initPassport.js`) accepts `authorization: relay@@@<token>@@@<SiteUser.uuid>` as
  any user. It cannot be switched off from compose (compose passes the misspelled
  `RELAY_ENABLED`; `config/local.js` reads `RELAY_ENABLE`, default `true`), and with
  `RELAY_SERVER_TOKEN` empty the token is `"There is no spoon."` (known issues S38). Both
  ping lists still name `relay`, so `/healthcheck` answers 207 and every check logs
  `Could not request (relay.healthcheck)`; `GET /relay/user-qr` and `GET /mobile/qr/:ID` are
  still routed. api_sails sends `relay: false` to `tenant_manager.config-site` (a
  **required** boolean in its `inputValidation`) and to the browser in `configSite`
  (platform_web shows "Connect Mobile App" only when it is true). Outside api_sails:
  platform_web adds a QR menu entry for every `isMobile` app (`ui/portal_work.js:326`); the
  `relay` network-type option remains in platform_web, platform_pwa and ABDesigner.
- The env-name typo that kept relay on also exists for custom_reports: compose passes
  `CUSTOM_REPORTS_ENABLED` (`docker-compose.yml:227`), the service reads
  `CUSTOM_REPORTS_ENABLE` (`custom_reports/config/local.js:13`). Setting it in `.env` does
  nothing; it stays at the default, `true`.
- **`AB_TESTING=true` is hardcoded on api_sails in the default (non-test) stack**
  (`docker-compose.yml:124`), un-404ing three routes. The gate checks that the variable is
  *defined*, so `AB_TESTING=false` still enables them. Only `POST /test/import` requires a
  logged-in user (it reads a caller-supplied path under `process.cwd()`, and `..` escapes it,
  `test-import.js:41`). `POST /test/reset` has **no** login check and takes the tenant from a
  `tenant` param (`test-reset.js:28`); it publishes `definition.stale`. `POST /testlog` is a
  `routes.before` hook that runs before any policy. `GET /versioncheck` and
  `GET /healthcheck` are not `AB_TESTING`-gated: they are registered unconditionally in
  `routes.before` and are always exposed.
- A request from `localhost`/`127.0.0.1` with **no `tenant-token` header and no `?tenant=`
  query param** is treated as the **admin tenant** whenever `NODE_ENV !== "production"`
  (`authTenant.js:35-58`), and compose sets `NODE_ENV=development`.
- **CSRF is not enabled anywhere** (`config/security.js` has every option commented out), and
  there is no `GET /csrfToken` route.
- All 11 Node inspectors are published on the host with `--inspect=0.0.0.0`.
- `authTenant`'s prefix→uuid `hashLookup` is module-level and never invalidated; a renamed
  tenant key resolves to the old uuid until api_sails restarts.
- `developer/db/init/*.sql` runs **only when the `mysql_data` volume is empty**.
  Editing it does nothing to a running stack — the site DB, `site_tenant` seed and site
  tables were created on first boot. `test/setup/reset.sh` (via `npm run test:reset`) re-runs
  only `03-site_tables.sql` and `02-tenant_manager.sql` against one tenant DB.

Local environment:

- **An `ab-web` image built from `developer/web` master answers 502 for every API call while
  reporting `(healthy)`.**
  `ab-web` images built from `developer/web` **master** (what `build.sh:10` builds)
  hardcode the AWS VPC resolver: `resolver 10.16.0.2` in
  `conf.d/app.conf.template` (upstream `39f85cf2`,
  2025-09-10; it was Docker's `127.0.0.11` before that). On a compose network the only DNS
  server is Docker's embedded one, `127.0.0.11`. `10.16.0.2` never answers, so
  `upstream webapp { server api_sails:1337 resolve; }` never gets an address. Static files and
  `/` still load, so the page shell appears, but `/config/site` and every other proxied request
  is a 502. Signature in the `web` log: `api_sails could not be resolved (110: Operation timed
  out)`. Test the real front door, not port 1337 (which bypasses nginx):
  `curl -s -o /dev/null -w '%{http_code}\n' localhost:$WEB_PORT/config/site` must be **200**.
  The portable upstream fix is `resolver ${NGINX_LOCAL_RESOLVERS} valid=5s ipv6=off;` in the
  template plus `ENV NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1` in the Dockerfile. The nginx base
  image's `/docker-entrypoint.d/15-local-resolvers.envsh` then fills the variable from
  `/etc/resolv.conf`: `127.0.0.11` under Docker, the VPC resolver on AWS. `develop` never had
  the problem: its `default.conf` has no `resolver` line and proxies straight to
  `api_sails:1337`, which nginx resolves through Docker's DNS at startup. But the local checkout
  cannot fix a master-built image, because the template is baked in and no mount covers it:
  with `develop` checked out and the default mounts, `/config/site` still returned 502
  (2026-09-28, and again in a 2026-09-29 test). What did fix it: a develop-built image
  (2026-09-28), or an empty file mounted over the template (2026-09-29 test, §2.3).
- **Until you build the UI, the portal runs the web repo's committed bundles.**
  `developer/web/assets` is both what nginx serves and where the UI builds land, so a fresh
  checkout serves `develop`'s committed `index.html` and bundles, which can be older than the
  UI repos (and `/` answers 200 all the same). Run `npm run watch` in the UI repos (§4.1).
  `build.sh` and `dev-update.sh` reset that folder to the committed copy.
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
- **ab-utils comes from each service's `node_modules`.** Each service runs the
  `node_modules/@digiserve/ab-utils` its own `npm install` brought (`#1.11.1` everywhere),
  and `node_modules/uuid`, a *symlink* to `@digiserve/ab-utils/shims/uuid`, resolves inside
  that same install. Those copies are unchanged since 2026-10-30 (known issues C1 was
  dropped), so ab-utils `env()` prints env values again, `SMTP_PASSWORD` included, in
  notification_email's boot log (§7.1). A change belongs in an ab-utils release that the
  services declare in `package.json`.
- **On rootless Docker, api_sails cannot write `logs/appbuilder/auth.log`** until you grant it.
  This machine runs rootless Docker (data root `~/.local/share/docker`): your files show up as
  root-owned inside containers, and api_sails runs as `node`, which is container uid 1000 =
  host uid `<your /etc/subuid start> + 999` (232071 here). The bind-mounted `logs/appbuilder/`
  (775) and `auth.log` (644) are read-only to it, so `api/lib/authLogger.js` fails with
  `EACCES`, logins never reach the file fail2ban reads, and every login files a
  `notify.developer`. Fixed on 2026-09-29 with an ACL, needed once per checkout (git does not
  store ACLs):
  `setfacl -m u:232071:rwx logs/appbuilder && setfacl -d -m u:232071:rw logs/appbuilder &&
  setfacl -m u:232071:rw logs/appbuilder/auth.log`. Check it with `getfacl logs/appbuilder`,
  or log in and look for a new `Local auth successful` line. The same ownership stops
  api_sails from storing uploads in `/app/.tmp/uploads`, so AB Designer's Import
  (`POST /definition/import`) fails with `EACCES` (seen 2026-10-30, not fixed; known issues
  E13).
- **Nothing restarts.** There are no `restart:` policies, so a Docker daemon restart leaves
  every container `Exited (255)` and the stack simply stays down until you `npm start`.
- **`docker compose ps` is not a health signal.** The Node services run under `node --watch`,
  which keeps the container alive after `app.js` throws ("Failed running 'app.js'. Waiting for
  file changes..."). A stack reporting 14/14 `running` can have zero working services. Only
  `api_sails` (no `--watch`) and `web` fail visibly, and `web` only when nginx cannot start at
  all: a master-built `web` stays `(healthy)` while every proxied request 502s (first bullet
  above).
  Check logs, `/healthcheck`, and `localhost:$WEB_PORT/config/site`.
- `migration_manager` never sorts its patch list (`fs.readdirSync` order) while the
  applied-check is a lexical compare — an out-of-order read silently skips a patch forever.
- A tenant created by `tenant_manager.tenant-add` gets **no `SITE_CONFIG` table**; that only
  appears when `migration_manager` runs. Nothing triggers the migrator automatically.

### 7.1 Startup log triage

A clean `npm start` is not a quiet one. Verified against full boots on 2026-09-28,
2026-09-29, 2026-10-05 and 2026-10-30 (the last with every repo under `developer/` clean at
upstream): only the rows marked **Yes** break anything or leak something.

| Log line (service) | Cause | Harmful? |
|---|---|---|
| `api_sails could not be resolved (110: Operation timed out)` (web) | A `web` image built from `developer/web` master, with its hardcoded AWS resolver (§7 Local environment) | **Yes: every API call 502s** |
| `EACCES: permission denied, open '/var/log/appbuilder/auth.log'` (api_sails, on each login) | Rootless Docker file ownership; fix with the ACL in §7 Local environment | **Yes, for fail2ban**: logins are not recorded |
| `Aborted connection … (Got timeout reading communication packets)` (db, about a minute after activity) | MariaDB runs with `--wait-timeout=60` (`docker-compose.yml:86`) and drops connections idle that long. The ones it still catches belong to ab-utils' shared `mysql` pool (`utils/dbConn.js`), which has no idle timeout. The short timeout looks deliberate, to cap connection counts (inference, from the `ER_CON_COUNT_ERROR` note in `platform_service/ABFactory.js`) | No, the pool reconnects |
| `open() "/app/assets/tenant/<tenant>/favicon.ico" failed (2: No such file or directory)` (web) | `SiteController.favicon` redirects `/favicon.ico` to the tenant's asset folder, and only `tenant/default` ships one | No, the tab icon is just missing |
| `Deprecation warning: value provided is not in a recognized RFC2822 or ISO format`, then an `Error` stack through moment (appbuilder, once per process) | `AB.rules.toDate()` (`platform_service/ABFactory.js`) parses datetime fields with no format. NetSuite sends values like `2026/1/27`, so moment falls back to `new Date()`, which reads them correctly in Node | No |
| `conflicting server name "localhost" on 0.0.0.0:80, ignored` (web) | Only with a master-built `web` image: the bind-mounted `default.conf` duplicates `app.conf`'s server name (§2.3) | No |
| `You need to use --log-bin to make --expire-logs-days or --binlog-expire-logs-seconds work` (db) | MariaDB config sets log expiry with binary logging off | No |
| `WARNING in ./js/webix/components/…min.js` ×6 (your `npm run watch` in ab_platform_web, not the compose logs) | Vendored minified Webix | No |
| `connect() failed (111: Connection refused) while connecting to upstream` for `/socket.io/` (web, first seconds) | A browser reconnecting before api_sails is up | No |
| `io_uring_queue_init() failed with EPERM`, `memory.pressure not writable` (db) | Host kernel / cgroup policy; MariaDB falls back to libaio | No |
| `Redis does not require authentication` (redis) | Dev default, no published port | No |
| `SyntaxError … is not valid JSON` blocks (notification_email, at boot) | ab-utils `env()` (`utils/defaults.js`) parses each value as JSON and logs the value when that fails | **Yes: env values, `SMTP_PASSWORD` included, in plain text in the log** |
| `Could not request (relay.healthcheck)` and `Request timed out.` developer errors (api_sails, log_manager, on every healthcheck) | Upstream api_sails still pings the retired `relay` service (`api/hooks/healthcheck.js`, `versionCheck.js`) | No, but `/healthcheck` answers 207 |
| `Aborted connection … (Got an error reading communication packets)` (db, at boot) | The mysql "ready?" probes call `destroy()` (ab-utils `utils/controller.js`, migration_manager `app.js`), which skips the clean quit | No |
| `Connection Error: Error: read ECONNRESET` (knex, after a quiet minute) | platform_service `ABFactory.js` keeps a pool `min: 2`, and MariaDB drops idle connections at 60 s (not seen in the first 3 minutes on 2026-10-30) | No, the pool reconnects |
| `Ignored attempt to bind route (/admin) to unknown action` (api_sails) | A dead route in `config/routes.js` to the removed `SiteController.index` | No |
| `MODULE_TYPELESS_PACKAGE_JSON` (tenant_manager) | Its `package.json` has no `"type": "module"` (§6) | No |

The last six rows had local fixes (known issues C1 to C5), dropped on 2026-10-30 when the
owner had every repo under `developer/` put back to its clean upstream state; their patches
are in `backups/patches/2026-10-05/`.

### 7.2 Open critical issues

Verified on 2026-10-02 and 2026-10-03 (not fixed). Details and evidence are in the linked docs.
The full backlog, with an ID and a priority for every problem found so far and the list of
fixes still waiting to be committed, is [docs/known-issues.md](docs/known-issues.md).

- **New migration patches can be silently skipped:** `patches/20261111.sql` carries a year
  typo and every tenant recorded it as the last patch, so name new patches to sort after
  `20261111.sql` ([docs/core/database.md §5](docs/core/database.md#5-migrations)).
- **Clicking a CSV Exporter widget takes the whole site down:** `csv-export.js` calls
  `sails.getDatastore()` with the ORM hook disabled, api_sails exits, and nothing restarts it
  until `npm start` ([docs/known-issues.md](docs/known-issues.md) B24, seen 2026-10-02).
- **A one-element list from an earlier process task arrives as a bare value**, and an `in`
  rule built from it matches nothing (class_core `ABProcessCore.processData()`,
  [docs/known-issues.md](docs/known-issues.md) B25). It left cross-entity principal
  approvals with no approver until the 2026-10-03 rework, which is not on HR Teams `master`
  yet (committed on `guy/enhancements`; the definitions live only in the local tenant)
  ([docs/netsuite-hr-update.md §12](docs/netsuite-hr-update.md#12-the-cross-entity-principal-change-since-2026-10-03)); any other process that
  filters with `context_in` can still hit it.
- **Email sending is broken** (async `AB.config()` in notification_email): password-reset
  emails and BPMN Email tasks fail ([docs/core/services.md §6](docs/core/services.md#6-notification_email)).
- **Cross-tenant data leak:** `copyTo` broadcasts reach every connected browser
  ([docs/core/api.md §9](docs/core/api.md#9-security-findings)).
- **Anyone who can reach api_sails can act as any user** through the `relay` header with
  its default token (known issues S38, §7), and notification_email prints env values,
  `SMTP_PASSWORD` included, in its boot log (S39). Both seen on 2026-10-30 with upstream
  code.
- **SSO-provisioned users have fixed local passwords** (`CAS` / `Okta`)
  ([docs/core/api.md §9](docs/core/api.md#9-security-findings)).
- **Logins:** accounts lock permanently after 6 failures; deactivated users can still log in
  locally ([docs/core/services.md §8](docs/core/services.md#8-user_manager)).
- **Plugin URLs are executed as code** in every AppBuilder service
  ([docs/core/server-platform.md §9](docs/core/server-platform.md#9-traps)).
- **One failed factory build disables a tenant in that service until restart**
  ([docs/core/server-platform.md §9](docs/core/server-platform.md#9-traps)).
- **Local stacks send errors to an upstream Sentry project** unless `TELEMETRY_PROVIDER` or
  `SENTRY_DSN` is set ([docs/core/service-runtime.md §5](docs/core/service-runtime.md#5-validation-pubsub-notifications-telemetry)).

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

Merging branches across submodules (learned syncing `master` and `staging`, September 2026):

- Forecast conflicts without touching the work tree:
  `git merge-tree --write-tree <ours> <theirs>` exits 1 and lists each `CONFLICT` when the merge
  would stop (git 2.38+; this machine has 2.43).
- `-X theirs` / `-X ours` settle only **content** conflicts. Rename/rename and modify/delete
  conflicts still stop the merge, so check `git status` after it.
- To confirm which side won a file, compare blobs: `git diff <side>:<path> HEAD:<path>` prints
  nothing when that side won. A grep for a string both sides share looks like a pass either way;
  that is how a lost fix once got reported as kept.
- Comparing after a commit: `git diff A..B` compares the two tips; `git diff A...B` shows only
  what B added since the merge base. `git show <merge>` hides a clean merge's changes, so use
  `git diff <merge>^1 <merge>`.
- After rewriting an already-pushed branch, push with `--force-with-lease`, never bare
  `--force` (and confirm first, §2.2).
- When one branch only adds commits to the other (`git merge-base --is-ancestor`), make them
  the same with a fast-forward push, not a PR: a merged PR adds a merge commit and, on
  services with `pr-merge-release.yml`, a version bump, so the branches differ again. Check
  what a push starts first. In api_sails a push to `master` runs only CodeQL, a push to
  `staging` (or `main`) builds and deploys to ECS (`build-deploy-ecs.yml`), and the release
  runs only when a PR is merged into `master`. On 2026-10-30 api_sails `master` was
  fast-forwarded to `staging` this way (`2bea82b..7c6e655`), at the owner's request.

---

## 9. Validation

There are no unit tests at the orchestration level. Proportional validation for a change:

1. `npm run lint` in each submodule you touched (most enforce `--max-warnings=0`).
   **api_sails' lint already fails at HEAD**: 1401 errors in 118 files on 2026-09-28, mostly
   prettier trailing commas in `tasks/config/*` and `config/models.js`. Its `npm test` is lint
   plus a no-op, so it fails too. Judge a change by per-file error counts against HEAD, and
   report "no new errors", not "passed":
   `git show HEAD:<f> | node_modules/.bin/eslint --stdin --stdin-filename <f> -f json` versus
   `node_modules/.bin/eslint <f> -f json`.
2. `npm test` in submodules that have a `test/` directory (not all do — check before
   assuming a test gate exists).
3. Bring the stack up and check the service actually started — `npx env-cmd docker compose
   logs -f --tail=100 <service>`, or
   `curl -s -w '\n%{http_code}\n' 'localhost:1337/healthcheck?timeout=5000'`.
   **200 = all services OK; 207 = one or more unhealthy** — it never returns 5xx for a down
   service, so "curl returned JSON" is not a pass. The default per-service ping timeout is
   30 s, hence the `timeout` query param. Port 1337 **bypasses nginx**, so also check the real
   front door: `curl -s -o /dev/null -w '%{http_code}\n' localhost:$WEB_PORT/config/site` must be
   **200**. A 502 there while 1337 answers means nginx cannot reach api_sails (§7).
4. For anything touching the browser tier, confirm your `npm run watch` terminal printed
   `compiled` after your last save before testing in the browser.
5. **Startup smoke test**, after `npm stop && npm start` (a clean boot passed all of it in about
   20 s on 2026-09-28, and again on 2026-10-05 after a full image build: healthcheck 200
   after 18 s):
   1. `localhost:1337/healthcheck?timeout=5000` answers **200**, or **207** with only `relay`
      unhealthy: upstream api_sails still pings it (§7; 207 on 2026-10-30).
   2. Each UI repo you build prints `compiled` (`npm run watch`, or a one-off
      `npx webpack-cli --config <its dev config>`). `compiled with N errors` is a failure.
   3. Through nginx, `localhost:$WEB_PORT/config/site` and `/` both return **200**.
   4. Sweep `npx env-cmd docker compose logs --since <boot time>` for error and warning lines
      and compare them with §7.1. Anything not in that table is new.
6. e2e via `npm run test:e2e*` — note the `CYPRESS_BASE_URL` and `reset-user.sql` issues in
   §7 first.

Report each gate as passed / failed / blocked / not run, with the exact command. Do not
report "should work" for a gate that was not executed.
