# Backend services

One section per Node microservice under `developer/`: what it owns, every cote
handler it exposes, its configuration, and the traps found in its code. process_manager is
documented in [processes.md](processes.md); api_sails in [api.md](api.md); the shared
runtime (controller, `req`, retries) in [service-runtime.md](service-runtime.md).

Verified against the working tree on 2026-10-01 (all services on `master`, ab-utils
`master` = 1.11.1). Paths are relative to `developer/<service>/` inside each
section unless they start with `developer/`. "Inferred" marks behavior reasoned from code
but not run. Handler keys are the wire contract: never rename one to match its filename.

---

## 0. Behavior every service shares

- **Startup:** `AB.controller("<key>").init()` (migration_manager is the exception). The
  controller imports every file in `handlers/` and registers any module exporting `key` +
  `fn`, then adds default `healthcheck` / `versioncheck` handlers
  (`node_modules/@digiserve/ab-utils/utils/controller.js:109,208-233,260`). **A handler file that
  throws on import is only logged (`console.log("::", e)`) and silently disappears** while
  the service keeps running.
- **Telemetry defaults to Sentry** with an upstream DSN hardcoded in each `app.js` (e.g.
  `appbuilder/app.js:8-20`) unless `SENTRY_DSN` or `TELEMETRY_PROVIDER` is set. Neither
  compose nor `example.env` sets `TELEMETRY_PROVIDER`, so a local stack reports its errors
  to that upstream Sentry project (inferred from config).
- **Config:** `config/local.js` is loaded from `process.cwd()`. **`AB.config()` returns a
  Promise** since ab-utils `38833bb` (`node_modules/@digiserve/ab-utils/utils/config.js:14-29`).
  Two callers still use it synchronously: `appbuilder/app.js:26` (harmless, defaults
  happen to match) and `notification_email/src/send.js:7` (**breaks email**, §6).
  Requests fail with `EMISSINGCONFIG` / `EDISABLED` when config is missing or
  `enable:false`.
- **Datastores** (`node_modules/@digiserve/ab-utils/utils/defaults.js:30-48`): `appbuilder`
  (database `MYSQL_DBPREFIX`, default `appbuilder`) and `site` (database `MYSQL_DBADMIN`,
  default `appbuilder-admin`), both on `MYSQL_HOST` (default `db`), `MYSQL_PORT`,
  `MYSQL_USER` (`root`), `MYSQL_PASSWORD`. `req.tenantDB()` builds
  `` `<prefix>-<tenantID>` ``.
- **Validation does not strip undeclared params**, so `req.param(k)` can read keys a
  handler never declared.
- **Notifications:** `req.notify.developer/builder` go to Sentry when it is active;
  otherwise to cote `log_manager.notification` (`node_modules/@digiserve/ab-utils/utils/telemetryDefault.js:21-47`).
- **Stub tests:** `test/unit/handler.js` in appbuilder, definition_manager, log_manager,
  tenant_manager and user_manager imports a `src/handler.js` that does not exist; they
  would fail if run. Only file_processor and migration_manager have `src/`.

### Handler key inventory (89 handler files)

| Service | Keys |
|---|---|
| appbuilder (12) | `csv-export`, `env-verify`, `labelMissing`, `labels`, `languages`, `model-delete`, `model-get`, `model-post`, `model-update`, `netsuite-data-verify`, `netsuite-metadata-catalog`, `netsuite-table-fields` |
| definition_manager (26) | `definition-create`, `definition-delete`, `definition-update`, `definitions-app`, `definitions-check-update`, `definitions-mobile-check-update`, `definitionsForRoles`, `export-all`, `export-app`, `find`, `information-field`, `information-object`, `json-import`, `json-reset`, `migrate-field-create`, `migrate-field-down`, `migrate-field-update`, `migrate-index-create`, `migrate-index-delete`, `migrate-object-create`, `migrate-object-down`, `mobile-config-settings`, `plugin-add`, `plugin-links`, `plugins`, `tenants-update-application` |
| custom_reports (3) | `report`, `well-invoice`, `well-receipt` |
| file_processor (10) | `file-upload`, `image-upload`, `file-get`, `file-base64`, `file-base64-upload`, `file-export`, `file_import` (underscore), `image-rotate`, plus legacy `model.find` and `file.upload` |
| log_manager (3) | `rowlog-create`, `rowlog-find`, `notification` |
| notification_email (1) | `email` |
| tenant_manager (8) | `config`, `config-site`, `config-site-version`, `site-version-cache-stale`, `config.list`, `find`, `tenant-add`, `tenant-url` |
| user_manager (12) | `user-find`, `user-find-password`, `new-user-password`, `config`, `config-user-version`, `user-version-cache-stale`, `config-meta`, `user-for-token`, `user-password-reset-request`, `user-password-reset-url`, `password-reset` (stub), `user-password-reset` (stub) |
| process_manager (14) | see [processes.md](processes.md) |

All keys are prefixed `<service>.` except file_processor's two legacy keys (`model.find`
in `tmpModelFind.js`, `file.upload` in `upload.js`), which advertise extra cote domains.

---

## 1. appbuilder

The runtime CRUD data plane: interprets object/query definitions to read and write tenant
data, plus CSV export SQL, labels/languages, NetSuite metadata and the process-trigger
retry queue. `waitForDB = true`; `afterStartup` starts the trigger queues and, without
awaiting, `Netsuite.catalog()` (logs `Netsuite.catalog(): returned N entries`)
(`app.js:23-43`).

### Handlers (`handlers/`)

| Key | Inputs | What it does |
|---|---|---|
| `model-get` | `objectID` uuid, `cond` object, `skipPack` | Resolve object/query (reset definitions once if missing); convert, scope (`includeScopes`), reduce and clean conditions; `findAll` + count; register ids with `api.broadcast-register`; CSV-pack unless `skipPack`. Returns `{data, total_count, pos, offset, limit, offset_next}` |
| `model-post` | `objectID`, `values`, `disableStale` (unused), `skipPack` | Insert a row (`"NULL"` string becomes null); SITE_USER passwords hashed through `user_manager.new-user-password` |
| `model-update` | `objectID`, `ID` (string: NetSuite ids are not uuids), `values`, `fromProcessManager`, `skipPack` | Update one row; SITE_USER drops empty password/salt/lastLogin; no process trigger when `fromProcessManager` |
| `model-delete` | `objectID`, `ID` | Read old row (populated), delete, then broadcast/log/trigger |
| `csv-export` | `viewID`, `where` | Build a SELECT (with scopes) and return `{SQL, tenantDB, fileName}`; api_sails runs it |
| `labels` | `languageCode` | Static label map from class_core `labels/` (unknown language falls back to `en`) |
| `languages` | none | `{language_code, language_label}` from SITE_LANGUAGE |
| `labelMissing` | `labels` array | Only when `labelUpdates` is on: rewrites class_core label source files on disk (uses `__dirname` in ESM: would throw, inferred) |
| `env-verify` | `id` | Reports whether `process.env[id]` exists |
| `netsuite-metadata-catalog` | `credentials` | NetSuite record catalog |
| `netsuite-table-fields` | `ID`, `credentials` | NetSuite table definition |
| `netsuite-data-verify` | `table`, `credentials` | Sample query through the NetSuite REST API |

There is **no count or batch handler**: api_sails `model-get-count` calls `model-get` and
returns `total_count`; batch is an api_sails loop over `model-post`/`model-update`.

### Write lifecycle (model-post / model-update / model-delete)

1. Prepare (hash SITE_USER passwords).
2. Write the row (`model().create/update/delete`).
3. Build the broadcast packet: `ab.datacollection.create|update|delete` to rooms
   `<tenantID>-<rowID>` with `copyTo` rooms for connected records (`utils/broadcast.js`).
4. **`await req.broadcast(packets)` happens before the callback**: other clients see the
   change before the editing client gets its reply.
5. `cb()` with the row (delete returns `{numRows}`).
6. After `cb()`, in parallel and fire-and-forget: `log_manager.rowlog-create`, the process
   trigger `<objectID>.added|.updated|.deleted` (re-read data), and cache invalidation.
   Errors here only reach `notify.developer`.

### Process-trigger queue (`utils/processTrigger/`)

An opossum circuit breaker wraps `process_manager.trigger` (timeout 3000 ms, error
threshold 50 %, reset 30000 ms). Failures fall back to a per-tenant in-memory queue
mirrored to `SITE_PENDING_TRIGGER`, reloaded at start and retried every 30 s under the
original user. A slow trigger can be queued and retried while the first call still
finishes, so a process may start twice; the unique `SITE_PROCESS_INSTANCE.instanceKey`
(patch 20230112) appears to absorb this (inferred).

### Other internals

- `utils/cacheManager.js`: when Role, Scope, User or Language rows change, calls
  `api_sails.site-cache-stale`, `tenant_manager.site-version-cache-stale`,
  `api_sails.user-cache-stale`, `user_manager.user-version-cache-stale`.
- `utils/Netsuite.js`: OAuth 1.0a HMAC-SHA256 client; credentials JSON with `ENV:<NAME>`
  substitution; per-process catalog cache with background refresh; SuiteQL helper.
- Dead code: `RetryFind.js`, `broadcastUpdateConnectedFields.js`, `getRightRoles.js`,
  `csvPack.js`. `models/` is empty.

### Config (`config/local.js`)

| Setting | Env var | Default |
|---|---|---|
| `enable` | `APPBUILDER_ENABLE` | true |
| `labelUpdates` | `APPBUILDER_LABEL_UPDATES` | false |
| `processTrigger.circuit.timeout / threshold / reset` | `CIRCUITBREAKER_TIMEOUT`, `CIRCUITBREAKER_THRESHHOLD` (sic), `CIRCUITBREAKER_RESET` | 3000 / 50 / 30000 (ignored: see trap 1) |
| `processTrigger.retryInterval` | none | 30000 |

NetSuite credentials come straight from the service environment (compose passes them).

### Traps

1. The circuit-breaker env vars are ignored: `app.js:26` passes the Promise from
   `AB.config()`, so the hardcoded defaults apply.
2. Scopes are checked only on reads (`model-get`, `csv-export`); writes never check scopes.
3. `rowlog-create` requires a uuid `row`, so rows with integer or NetSuite ids are never
   logged: each such write makes appbuilder log `EINVALIDINPUTS` (`row` "must be a valid
   GUID") and an unhandled rejection (seen 2026-10-31 on Team Assignment saves, known
   issues R26).
4. Delete broadcasts carry no data, so clients showing connected records are not told
   (inferred). Deleting a record never deletes its files.
5. SSRF / secret-leak risks (inferred): `Netsuite.importCredentials` accepts `ENV:<ANY>`
   and a caller-supplied base URL; `model-get` fetches a caller-supplied `cond.url` for
   unknown object ids; `env-verify` reveals which env vars exist.
6. `csv-export` interpolates field labels and list text into SQL without escaping
   (inferred).
7. `cacheManager.js` passes `req.tenantID` (the function) instead of its value; receivers
   fall back to the request's tenant, so it works by accident.

---

## 2. definition_manager

The **only writer** of `appbuilder_definition`: definition CRUD, schema migrations on
request, export/import, cached definition bundles for roles and mobile, plugin
registration, and the `definition.*` events. `afterStartup` publishes `definition.stale`
to warm the publisher. `definitions.js` (old `ab.definition.update` publisher) is dead.

### Handlers

| Key | What it does |
|---|---|
| `definition-create` (`id`, `name`, `type`, `json`) | Normalize app/object/query json via `AB.*New().toObj()`, store secrets, `AB.definitionCreate`, clear caches, `cb`, broadcast `ab.abdefinition.create` to room `<tenant>-abdesigner`, publish `definition.created` |
| `definition-update` (`ID`, `values`) | Secrets, update, `cb`, publish `definition.updated`, broadcast `ab.abdefinition.update` |
| `definition-delete` (`ID`) | Find, destroy, `cb`, publish `definition.destroyed`, broadcast `ab.abdefinition.delete` |
| `definitionsForRoles` (`roles`) | Cached per sorted role-id list; system roles get every app; everyone gets system objects; returns a JSON string |
| `definitions-app` (`ID`) | Cached `export-app` for the mobile app (stringified in a worker) |
| `definitions-check-update`, `definitions-mobile-check-update` (`appID`) | Return cache timestamps so clients know when to refetch |
| `export-app` (`ID`) | `{abVersion, filename, date, definitions, files, siteObjectConnections, roles, scopes}`; non-built-in roles (users stripped); image/docx files fetched via `file_processor.file-export` |
| `export-all` | Definitions of all apps |
| `json-import` (`json`) | Import an exported app (order below) |
| `json-reset` | Publish `definition.stale` |
| `migrate-object-create` / `-down`, `migrate-field-create` / `-update` / `-down`, `migrate-index-create` / `-delete` | Run the platform DDL (`migrateCreate/Update/Drop`); resolve the definition, resetting definitions once if missing |
| `information-object` (`ID`), `information-field` (`objID`, `ID`) | `DESCRIBE <table>`, `SHOW COLUMNS ... WHERE Field = <col>` |
| `mobile-config-settings` (`ID`) | `{version, site:{appbuilder:{networkType, networkNumRetries:3}, storage:{encrypted:false}}}` |
| `plugins`, `plugin-links` (`cond`) | `SELECT` from `SITE_PLUGIN` / `SITE_PLUGIN_LINK` |
| `plugin-add` (`url`) | Fetch the plugin's `manifest.json` (GitHub raw or `http://web:80/assets/ab_plugins/<path>`), upsert `SITE_PLUGIN`, sync `SITE_PLUGIN_LINK` rows per platform (service/web/pwa) |
| `tenants-update-application` (`applicationUUID`, `data`) | Run `json-import` on every tenant that has the app |
| `find` | Stub returning success |

**Migrations are never triggered by definition-create/update.** The browser saves the
definition, then calls `/definition/migrate/...` separately
(`developer/ab_platform_web/AppBuilder/platform/dataFields/ABField.js:250-262`,
`ABIndex.js:75-82`, `ABObject.js:460-477`).

**Events:** `definition.created/updated/destroyed` from the CRUD handlers;
`definition.stale` from startup, `json-reset` and the end of `json-import`. Every
AppBuilder service's `ABBootstrap` drops the tenant's factory on any of them.

### json-import order (`handlers/json-import.js`)

1. `SET GLOBAL` and `SET SESSION innodb_lock_wait_timeout = 1` (`:146-154`).
2. Upsert field, object, query, index and application definitions.
3. Create tables without connect, combine or index fields; then normal indexes; then
   connect fields (including `siteObjectConnections` added to site objects); save site
   objects; final indexes; combine fields; queries; all remaining definitions.
4. Files via `file_processor.file_import`; scopes then roles.
5. Collected errors go to `notify.developer/builder`; the import still resolves.
6. Restore `innodb_lock_wait_timeout = 50` (`:656-660`), publish `definition.stale`, `cb`.

Imports only add and update; they never delete existing definitions.

### Traps

1. **json-import changes a server-wide MariaDB setting** (global lock wait timeout 1 s)
   and the error path never restores 50, affecting every tenant until MariaDB restarts.
2. **`plugin-add` leads to code execution in every AppBuilder service:** at factory build,
   `ABBootstrap` loads the tenant's `SITE_PLUGIN_LINK` rows for its platform and runs
   `requireFromURL(p.url)` (`developer/appbuilder/AppBuilder/ABBootstrap.js:76,138,184-194`).
   Treat plugin URLs as trusted code. Who may call `POST /definition/plugin/add` is in
   [api.md](api.md).
3. `tenants-update-application` puts `longRequest: true` inside `jobData` (the pattern
   AGENTS.md forbids) and mutates the shared `req._tenantID`.
4. Several handlers can call `cb` twice (a failure after `cb()` falls into `.catch(cb)`)
   or never (missing catches) (inferred).
5. `processSecrets.js` uses `splice(i, 0)`, which removes nothing (inferred).
6. `applicationUUID` is interpolated into SQL (`queries/getApplicationsByTenantUUID.js`)
   (inferred injection risk).

---

## 3. custom_reports

Server-rendered HTML reports (EJS). Most are finance reports for one deployment's
accounting/ministry apps, plus invoice/receipt/session pages for a "WELL" app.

| Key | What it does |
|---|---|
| `report` (`reportKey`, `data`) | Look up one of 12 reports, run `prepareData(AB, data, req)`, render `reports/templates/<name>.ejs`, return HTML. Route `GET /report/:key` passes all other request params as `data` with `{longRequest:true}` |
| `well-invoice` (`payeeId`) | Hardcoded object ids; renders `templates/well-invoice.ejs` |
| `well-receipt` (`transactionId`) | Same pattern, `templates/well-receipt.ejs` |

Report keys: `hello-world`, `well-invoice`, `well-receipt`, `well-session`,
`balance-sheet`, `income-vs-expense`, `balance-report`, `team-monthly`,
`local-income-expense`, `budget-vs-expense`, `extend-report-month`, `fcf-due-dates`.
Data comes from `AB.objectByID/queryByID` or `appbuilder.model-get` (`reports/_utils.js`).
Some reports check a hardcoded "Core Finance" role id; `convertFYtoDate` assumes a July
fiscal-year start. Templates include files by absolute container path (`/app/reports/...`).

**Config:** `custom_reports.enable` reads `CUSTOM_REPORTS_ENABLE`, but compose passes
`CUSTOM_REPORTS_ENABLED` (`docker-compose.yml:227`), so it cannot be turned off from
`.env`. **Traps:** an unknown `reportKey` calls `cb` twice; hardcoded object and role ids
tie reports to one deployment.

---

## 4. file_processor

Owns uploaded files on the shared `files` volume (mounted at `/data` in web, api_sails and
file_processor) and their `SITE_FILE` rows. Optional ClamAV (`CLAMAV_ENABLED=true` starts
`freshclam` and `clamd`; commented out in compose) and ImageMagick/Jimp image derivatives.

| Key | What it does |
|---|---|
| `file-upload` (`name`, `object`, `field`, `size`, `type`, `fileName`, `uploadedBy`) | Validate object/field (`defaultImage` allowed), ClamAV scan the temp file, move it to `<basePath>/<tenantID>/file_processor/<name>`, create SITE_FILE `{file, pathFile, size, type, info, object, field, uploadedBy}`, return `{uuid}`. api_sails stages uploads in `<files>/<uploadPath>` first |
| `image-upload` | Fake object/field (SiteUser) to reuse file-upload, then start conversions without awaiting |
| `file-get` (`uuid`, `extension`, `needOriginalFile`) | Return `{url: pathFile}`; for images returns a `.webp` derivative path, creating it without waiting |
| `file-base64` (`uuid`, `mobile`) | `{uuid, file, type, contents}`; mobile images over 1.75 MB get a downscaled `mobile_` copy |
| `file-base64-upload` | Write base64 content to `<dest>/<fileName>`, scan, create SITE_FILE |
| `file-export` / `file_import` | Base64 export and import for app packages (import keeps the original uuid) |
| `image-rotate` (`uuid`, `direction`) | Rotate the `.webp` derivative in place |
| `model.find`, `file.upload` | Legacy/test handlers, no callers |

**Seen on 2026-10-02:** `POST /file/upload/<object>/<field>/1` (multipart, field `file`)
went api_sails → `file-upload` in 2 s, mostly spent creating the cote client the first
time, and answered `{"status":"server","data":{"uuid":…}}`. The file landed at
`/data/admin/file_processor/<uuid>.<ext>` in the `files` volume, with a `SITE_FILE` row
(`file`, `pathFile`, `size`, `type`, `info` with object, field and uploader). No virus scan
ran (ClamAV is off in this stack; inferred from the logs).

**Config:** `FILE_PROCESSOR_ENABLE`, `FILE_PROCESSOR_PATH` (`/data`),
`FILE_PROCESSOR_UPLOAD_DIR` (`tmp`), `FILE_PROCESSOR_MAXBYTES` (not read here; api_sails
enforces its own limit).

**Traps:** there is **no delete path** for files; base64 upload/import write to
caller-supplied names inside the tenant folder (overwrite / `../` traversal, inferred);
base64 upload scans after the file is in its final place; image commands are built by
shell string interpolation (inferred); derivatives may not exist yet on first request.

---

## 5. log_manager (CommonJS)

| Key | What it does |
|---|---|
| `rowlog-create` (`username`, `usernameReal`, `record`, `level`, `row` uuid, `object` uuid) | Strip id/timestamps from `record`, insert into `<tenantDB>.SITE_ROWLOG` |
| `rowlog-find` (`objectID`, optional `row`, `level`, `username`, `start`, `limit`, `startDate`, `endDate`) | Record history, ordered by time |
| `notification` (in `system-notify.js`) | Logs the params and returns; nothing is stored or emailed |

Only services running **without** Sentry send notifications here. Rowlogs are never
pruned; `rowlog-find` omits `usernameReal`, `row` and `object`. `log_manager.sentry`
config is read by nothing; only `SENTRY_DSN` matters.

---

## 6. notification_email

Sends mail through nodemailer. No templates: callers send a ready
`{from, to, cc, bcc, subject, text, html, attachments}`.

| Key | What it does |
|---|---|
| `email` (`email` object, `transport`) | Pick the transport (param or `config.default`) and send |

Callers: `user_manager.user-password-reset-request` and the BPMN Email task
(`developer/appbuilder/AppBuilder/platform/process/tasks/ABProcessTaskEmail.js`).

**Config:** `NOTIFICATION_EMAIL_ENABLE`, `NOTIFICATION_EMAIL_DEFAULT` (`smtp`),
`SMTP_HOST`, `SMTP_PORT` (465), `SMTP_SECURE` (true), `SMTP_AUTH` (JSON) or
`SMTP_USER` / `SMTP_PASSWORD`.

### Traps

1. **Email sending is broken in this checkout.** `src/send.js:7` stores
   `AB.config("notification_email")`, which is now a Promise, so `config.default` and
   `config[transport]` are undefined and every `send()` rejects with
   `unknown mailer transport`. Password-reset emails and BPMN Email tasks fail. Fix:
   await the config (for example resolve it once at the top of `send()`). Verified in
   code, not by sending (this machine has real SMTP credentials).
2. **The SMTP password leaks on failure:** the handler passes the whole `config` (with
   `smtp.auth.pass`) to `notify.developer` (Sentry by default) and returns it on
   `err.transport`.

---

## 7. tenant_manager (ESM, `"type":"module"` since 2026-09-29)

Tenants live in `site_tenant` in the site DB; this service also assembles the browser's
site configuration.

| Key | What it does |
|---|---|
| `config-site` (`relay` boolean, **required**) | `{site:{relay, tenants, privacyPolicy}, tenant, labels, languages, meta, settings}` built from `tenant_manager.config`, the tenant list, `appbuilder.labels`, `appbuilder.languages`, `user_manager.config-meta` and SITE_CONFIG `privacy-policy` |
| `config-site-version` | In-memory hash of config-site per tenant (cache busting) |
| `site-version-cache-stale` | Clear that cache (`tenantID` param, `"all"` clears every entry) |
| `config` (`uuid`) | `{id, options: properties}` (default tenant when none matches) |
| `config.list` | `[{uuid, key, title}]` |
| `find` (`key`) | First `site_tenant` row with that key (used by api_sails `authTenant`) |
| `tenant-url` (`uuid`) | `{url}` from tenant properties |
| `tenant-add` (`key`, `title`, `authType`, `username`, `password`, `email`, `url`) | Create a tenant and its database (below) |

There is no tenant update or delete handler.

**tenant-add:** reject duplicate keys; insert `site_tenant`; hash the admin password via
`user_manager.new-user-password`; fill placeholders in `utils/new_tenant.sql`
(`##key##` is the new **uuid**, so the DB is `appbuilder-<uuid>`); **write the result to
`new-<key>.sql` in the working directory and never delete it** (it contains the admin hash
and salt); run it statement by statement with a hand-written INSERT parser; then
`api_sails.site-cache-stale`. `new_tenant.sql` creates the core SITE_* tables and seeds
admin, roles and the All Access scope, but **not** SITE_CONFIG, SITE_PENDING_TRIGGER,
SITE_KEY, SITE_SECRET, SITE_PROCESS_DEFINITION, SITE_PLUGIN*, nor the accounting stored
procedures. A new tenant needs migration_manager to run (on the next `npm start`).

**Traps:** no rollback on a half-built tenant; the comment-stripping regex truncates values
containing ` #`; `list.js` reads `title` from an unparsed string (titles undefined,
inferred); `config-site` reads `req.user` (unset) so its labels are always English
(inferred).

---

## 8. user_manager

| Key | What it does |
|---|---|
| `user-find` (`uuid` / `email` / `username` / `authname`) | `safeUser` + `SITE_ROLE:[{uuid}]` |
| `user-find-password` (`email`, `password`) | Local login check: refuse when `failedLogins > maxFailedLogins` (`EFAILEDATTEMPTS`); hash and compare; on mismatch `EINVALIDLOGIN` and `failedLogins++` |
| `new-user-password` (`password`) | `{password: hash, salt}` |
| `config` (`user`) | Attach `roles` (SITE_ROLE joined through `AB_JOINMN_ROLE_USER_users`) |
| `config-user-version` / `user-version-cache-stale` (`userUUID`, `"all"`) | Per-user config hash cache |
| `config-meta` | All roles, all scopes, active users `{uuid, isActive, username, languageCode}` |
| `user-for-token` (`token`) | Find an unexpired SITE_TOKEN and return its user |
| `user-password-reset-request` (`email`, `url`) | Create a 16-char token (10 min) and email `<url>auth/password/reset?a=<token>&t=<tenant>` from `no-reply@digiserve.org` |
| `user-password-reset-url` (`email`) | Same token, return the URL (used by a BPMN task) |
| `password-reset`, `user-password-reset` | Stubs |

Passwords: `crypto.pbkdf2(password, salt, 100000, 512, "sha1")` with a 32-byte hex salt
(`utils.js`). Reset completion goes through api_sails, which calls `appbuilder.model-update`
on SiteUser (the update hashes the new password). Switcheroo (impersonation) lives in
api_sails `authSwitcheroo` + the `Switcheroo` role (patch 20221125); rowlogs record
`usernameReal`.

**Config:** `USER_MANAGER_ENABLE`, `USER_MANAGER_MAX_FAILED_LOGINS` (default 5).

### Traps

1. **Accounts lock permanently after 6 failed logins:** `failedLogins` is only ever
   incremented (`handlers/user-find-password.js:83,107-109`); nothing resets it. Fix the
   column by hand to unlock.
2. **Deactivated users can still log in locally:** neither this handler nor api_sails
   `authUserLocal.js` checks `isActive`.
3. Token expiry compares a DATETIME column with `Date.now()` milliseconds (whether expired
   tokens are rejected is unverified).
4. `user-password-reset-url` reveals whether an email exists; the password compare uses
   `==` (not constant time); reset emails are currently broken (§6).

---

## 9. migration_manager

A run-once script, not a cote service. Compose runs it with `node --watch app.js` on every
`npm start` (`depends_on: db`). Full patch details are in
[database.md](database.md#5-migrations).

1. Read every file in `patches/` (`readdirSync` order, no explicit sort).
2. Wait for MariaDB, read `site_tenant`, process all tenants in parallel.
3. Per tenant: `USE <tenantDB>`, read `SITE_CONFIG` key `migration-last-patch`, apply every
   patch whose **filename compares greater as a string**, split each patch on `;`, stop at
   the first error and save the last good patch name.
4. Close connections and exit.

**Critical trap: `patches/20261111.sql` was committed on 2025-11-11 (a year typo).** Every
tenant has recorded `20261111.sql`, so any new patch named with a real date before
2026-11-11 is silently skipped forever. **Name new patches so they sort after
`20261111.sql`** until that is fixed. Other traps: no transactions; `;` inside strings
breaks the split (no stored procedures in patches); some patches are not safe to re-run
(`20231031` drops and recreates `SITE_SECRET`); system-definition upserts overwrite tenant
changes to those definitions; `--watch` does not rerun when a patch file is added.
