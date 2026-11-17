# HTTP and socket API (api_sails)

`developer/api_sails` is the Sails.js front door: every browser request goes
nginx (`web`) to api_sails, which authenticates, resolves the tenant, validates parameters
and forwards a cote request to a backend service. It also owns the Sails sockets used for
realtime updates.

Verified against api_sails `master` `2bea82b` (v2.8.0) with the uncommitted relay-removal
edits of 2026-09-29, on 2026-10-02. Since 2026-10-30 the checkout is `master` `7c6e655`
with no local edits, so relay is back (§9 item 10). That day `master` was fast-forwarded to
`staging` (PRs #230 and #231), so the two branches are the same commit. Paths are relative to `developer/api_sails/`
unless they start with `developer/`. "Inferred" = reasoned from code, not run.

Related: [service-runtime.md](service-runtime.md) (cote, `req.ab`),
[services.md](services.md) (the handlers behind each route),
[architecture.md §5](architecture.md#5-request-lifecycle).

---

## 1. Startup and configuration

- Compose runs `app.js` (no `--watch`: **edits need `docker compose restart api_sails` or
  `npm stop && npm start`**). The image's own command, `app_waitMysql.js`, retries a MySQL
  connection every 500 ms with `config.datastores.site` before it requires `app.js`, and
  crashes because `config/local.js` has `datastores` commented out (known issues E14).
- `config/bootstrap.js` calls `done()` first, then in the background warms caches:
  `GET /healthcheck`, `tenant_manager.config.list`, one `GET /config/site` per tenant (1 s
  apart), `GET /versioncheck`.
- Config files that matter:

| File | What matters |
|---|---|
| `config/local.js` | `datastores` (commented out upstream, E14), `cas` (`CAS_ENABLED`, `CAS_BASE_URL`, `CAS_UUID_KEY`, `SITE_URL`), `okta` (`OKTA_ENABLED`, `OKTA_DOMAIN`, `OKTA_CLIENT_ID`, `OKTA_CLIENT_SECRET`), `file_processor` (`/data`, `tmp`, 10 MB), `http.trustProxy: true` |
| `config/routes.js` | The route table (§4) |
| `config/policies.js` | Policy stacks (§2) |
| `config/hooks.js` | `orm: false` (no Waterline, so no `sails.getDatastore`) |
| `config/session.js` | Secret = `SAILS_SESSION_SECRET` or a **hardcoded fallback**; redis store db 1 |
| `config/sockets.js` | Redis adapter db 1; `beforeConnect` allows every origin |
| `config/security.js` | CORS and CSRF commented out (no CSRF anywhere) |
| `config/env/production.js` | Secure cookies, 1-year static cache, trustProxy |

---

## 2. Policies

`config/policies.js`: the default stack is **abUtils, telemetry, authTenant, authUser,
authSwitcheroo**; `noAuth` (abUtils, telemetry, authTenant) applies to
`SiteController.favicon`, `mobile/app`, `mobile/favicon`, `auth/reset-password-verify`;
`SiteController.datadog` gets none. **No policy enforces login or roles**: every
controller must call `req.ab.validUser()`, `validBuilder()` or `validSwitcheroo()` itself.

| Policy | Behavior |
|---|---|
| `abUtils` | Creates `req.ab` / `res.ab`; a `jobID` request param overrides the jobID; logs `METHOD path` |
| `telemetry` | Sentry span per route when Sentry is on |
| `authTenant` | Resolves the tenant (below) |
| `authUser` | Passport session; else the `token` strategy (header `user-token`); else anonymous |
| `authSwitcheroo` | If `req.session.switcherooID`: load that user and act as them (the real user goes to `userReal`) |

**Tenant resolution (`api/policies/authTenant.js`):**

1. A `tenant-token` header is used **verbatim**.
2. Host `localhost` / `127.0.0.1` without `?tenant=`, when `NODE_ENV != production`, means
   `admin` (compose sets `development`).
3. Otherwise the first DNS label of `X-Forwarded-Host` (or the hostname, or the Referer when
   the host is `api_sails`) is the tenant key; in development `?tenant=` overrides it.
4. Key-to-uuid lookups are cached in a module-level `hashLookup` (seeded
   `"appbuilder-stage":"admin"`) and **never invalidated**; numeric prefixes (IP access)
   get 404; unknown keys get 404 after `tenant_manager.find`.

---

## 3. Request helpers (`req.ab` and `res.ab`)

`req.ab` (ab-utils `utils/reqApi.js`): `tenantID`, `user`, `userReal`, `tenantSet()`,
`isSwitcherood()`, `switcherooToUser()`, `param(k)` (normalized value first, then Sails
`req.param`), `validateParameters(desc)` (JSON-parses string params for object/array/number
rules; on failure HTTP 400 with body code 422), `validUser()` (sends `E_REAUTH` as **400**,
not 401), `validBuilder()` (roles System Builder `6cc04894-...` or Builder
`e1be4d22-...`), `validSwitcheroo()` (role `320ef94a-...`), `validRoles(ids)`,
`serviceRequest()`, `log()`, `notify.*`.

`res.ab` (`utils/resApi.js`): `success(data)` → `{status:"success", data}`;
`error(err, code=400)` → `{status:"error", jobID, data, id, message, code, mlKey,
errors}` (**`jobID` is always `"??"`** in api_sails, and `validationErrors` are dropped);
`reauth()` → 401. Both replace only the first `"true"`/`"false"` string in the JSON with a
boolean.

Pattern for a new endpoint (AGENTS.md §6): one controller file, a route, a module-level
`inputParams`, then `req.ab.log()`, a guard, `validateParameters`, `serviceRequest`,
`res.ab.success()` / `res.ab.error()`.

---

## 4. Route table

90 entries in `config/routes.js` plus 3 hook routes. Guards: **U** `validUser`, **B**
`validBuilder`, **S** `validSwitcheroo`, **none** = no login check. Controllers live in
`api/controllers/`.

### Hook routes (no policy stack)

| Route | Guard | Behavior |
|---|---|---|
| `GET /healthcheck` | none | Pings `<svc>.healthcheck` for 9 services plus 6 real test requests; 200, or 207 if any is unhealthy (never 5xx); `?timeout=` (default 30 s) |
| `GET /versioncheck` | none | Map of service to version, always 200 |
| `POST /testlog` | none | Prints a banner; enabled whenever `AB_TESTING` is defined |

### Site and config

| Route | Action | Guard | cote keys |
|---|---|---|---|
| `ANY /favicon.ico` | SiteController.favicon | none | redirect to `/assets/tenant/<tenant>/favicon.ico` |
| `GET /config` | SiteController.config | none | legacy combined payload (includes every tenant's uuid/key/title, even anonymously) |
| `GET /plugin/:tenant/:key` | SiteController.pluginLoad | none | redirect |
| `GET /config/preloader` | SiteController.preloader | none | `tenant_manager.config-site-version`, `user_manager.config-user-version`, `definition_manager.definitions-check-update`, `definition_manager.plugin-links` |
| `GET /config/site` | SiteController.configSite | none | `tenant_manager.config-site {relay:false}` |
| `GET /config/user` | SiteController.configUser | none | `user_manager.config` |
| `GET /config/inbox` | SiteController.configInbox | none | `process_manager.inbox.find`, `inbox.meta` |
| `GET /settings` | SiteController.settings | none | none |
| `GET /monitors/lb` | SiteController.dataDog | none (no policies) | none |

### Auth

| Route | Action | Guard | cote keys |
|---|---|---|---|
| `GET /auth/password/reset` | auth/reset-password-verify (noAuth) | none | `user_manager.user-for-token` |
| `POST /auth/password/reset` | auth/reset-password-update | U | `appbuilder.model-update` |
| `POST /auth/login/reset` | auth/reset-password-request | none | `user_manager.user-password-reset-request` |
| `GET /auth/login` | auth/login-start | none | `tenant_manager.config` |
| `POST /auth/login` | auth/login | none | `user_manager.user-find-password` |
| `POST /auth/logout` | auth/logout | none | none |
| `POST /auth/switcheroo/:userID` | auth/switcheroo | S | none |
| `DELETE /auth/switcheroo` | auth/switcheroo-clear | S | none |
| `GET /okta-error` | auth/okta-error | none | none |
| `GET /authorization-code/callback` | auth/okta-callback | none | `user_manager.user-find`, `appbuilder.model-post` |
| `GET /mobile/whoami` | auth/whoami | none (401 if no user) | none |

### Files

| Route | Guard | cote key |
|---|---|---|
| `POST /file/upload/:objID/:fieldID/:isWebix` | U | `file_processor.file-upload` |
| `POST /file/upload/base64/:objID/:fieldID` | U | `file_processor.file-base64-upload` |
| `GET /file/:ID` | U | `file_processor.file-get` (then redirect to the stored path) |
| `GET /file/:ID/base64` | U | `file_processor.file-base64` |
| `POST /image/upload/:isWebix` | U | `file_processor.image-upload` |
| `PUT /image/rotate/:ID` | U | `file_processor.image-rotate` |

### Data (appbuilder), tenants, logs

| Route | Guard | cote keys |
|---|---|---|
| `GET /app_builder/model/:objID` | U | `appbuilder.model-get` |
| `GET /app_builder/model/:objID/count` | U | `appbuilder.model-get` (returns `total_count`) |
| `POST /app_builder/model/:objID` | U | `appbuilder.model-post` |
| `POST /app_builder/batch/model/:objID` | U | `model-get`, `model-post`, `model-update` |
| `PUT /app_builder/model/:objID/:ID` | U | `appbuilder.model-update` |
| `PUT /app_builder/batch/model/:objID` | U | `appbuilder.model-update` |
| `DELETE /app_builder/model/:objID/:ID` | U | `appbuilder.model-delete` |
| `GET /appbuilder/csv-export/:viewID` | U | `appbuilder.csv-export`, then direct MySQL |
| `ANY /multilingual/label-missing` | U | `appbuilder.labelMissing` |
| `GET /app_builder/object/:objID/track` | U+B | `log_manager.rowlog-find` |
| `POST /tenant/add` | U | `tenant_manager.tenant-add` |
| `GET /env/verify/:ID` | U+B | `appbuilder.env-verify` |
| `GET /netsuite/metadata` | U+B | `appbuilder.netsuite-metadata-catalog` |
| `GET /netsuite/table/:ID` | U+B | `appbuilder.netsuite-table-fields` |
| `GET /netsuite/dataverify/:table` | U+B | `appbuilder.netsuite-data-verify` |

### Definitions (definition_manager)

| Route | Guard | Key (`definition_manager.`) |
|---|---|---|
| `POST /definition/create` | U+B | `definition-create` |
| `PUT /definition/:ID` | U+B | `definition-update` |
| `DELETE /definition/:ID` | U+B | `definition-delete` |
| `POST /definition/register` | U+B | none (joins the `<tenant>-abdesigner` socket room) |
| `GET /definition/myapps` | U (except `v=unknown`) | `definitionsForRoles` |
| `GET /definition/check-update` | U | `definitions-check-update` |
| `GET /definition/allapplications` | U+B | `export-all` |
| `GET /definition/export/all` | U+B | `export-all` |
| `GET /definition/export/:ID` | U+B | `export-app` |
| `ANY /definition/import` | U+B | `json-import` |
| `POST /definition/tenants-update-application` | U+B | `tenants-update-application` |
| `POST /definition/plugin/add` | U+B | `plugin-add` |
| `GET /definition/info/object/:ID` | U+B | `information-object` |
| `GET /definition/info/object/:objID/field/:ID` | U+B | `information-field` |
| `POST/DELETE /definition/migrate/object/:ID` | U+B | `migrate-object-create` / `-down` |
| `POST/PUT/DELETE /definition/migrate/object/:objID/field/:ID` | U+B | `migrate-field-create` / `-update` / `-down` |
| `POST/DELETE /definition/migrate/object/:objID/index/:ID` | U+B | `migrate-index-create` / `-delete` |
| `POST /test/import` | U (only if `AB_TESTING` defined) | `json-import` |
| `POST /test/reset` | **none** (`AB_TESTING`) | `json-reset` |

### Processes and reports

| Route | Guard | cote key |
|---|---|---|
| `GET /process/inbox` | U | `process_manager.inbox.find` |
| `POST /process/inbox/register` | U | `user_manager.config` + socket room joins |
| `PUT /process/inbox/:ID` | U | `process_manager.inbox-update` |
| `POST /process/inbox/meta` | U | `process_manager.inbox.meta` |
| `POST /process/external` | U | `process_manager.external` |
| `PUT /process/reset/:taskID` | U | `process_manager.reset` |
| `POST /process/userform/:processID/:taskID` | U | `process_manager.userform.update` |
| `PUT /process/timer/:ID/start` / `stop`, `GET /process/timer/:ID` | U+B | `process_manager.timer-start` / `-stop` / `-status` |
| `GET /custom_reports/well-receipt`, `/well-invoice` | U | `custom_reports.well-receipt` / `well-invoice` |
| `GET /report/:key` | U | `custom_reports.report` (`longRequest`) |
| `GET /metrics` | **none** | Prometheus metrics |

### Mobile PWA

| Route | Guard | cote key |
|---|---|---|
| `GET /mobile/app/:tenantID/:ID` | none | HTML shell (`views/mobile_pwa.ejs`) |
| `GET /mobile/preloader/:tenantID/:appID` | none | `definition_manager.definitions-mobile-check-update` |
| `GET /mobile/definitions/:ID` | U (else empty) | `definition_manager.definitions-app` |
| `GET /mobile/config/settings/:appID` | **none** | `definition_manager.mobile-config-settings` |
| `GET /mobile/config/labels`, `languages`, `meta`, `tenants` | U | `appbuilder.labels`, `appbuilder.languages`, `user_manager.config-meta`, `tenant_manager.config` |
| `GET /mobile/config/user` | U | `user_manager.config` |
| `GET /mobile/app/:ID/favicon.png` | none | redirect to the default favicon |
| `GET /mobile/app/:tenantID/:ID/manifest.json` | none | static manifest |
| `GET /mobile/version/:ID` | (broken) | `definition_manager.mobile-config`: **no such handler exists** (deleted in definition_manager `84a8d59`), so it always times out |

`definition/mobile-config-user.js` has no route and calls a key no service declares (dead).

---

## 5. Authentication

Strategies (`api/hooks/initPassport.js`): **`local` and `token` are always registered**;
`cas` only when `cas.enabled`; `oidc` (Okta) only when `okta.enabled`. The session stores
`user.uuid`; deserialization looks it up in the **current request's tenant** through
`user_manager.user-find` (no `.catch`).

| Flow | Details |
|---|---|
| Local | `POST /auth/login {email, password}` → `user_manager.user-find-password`; logged to authLogger |
| Token | Header `user-token` → `user_manager.user-for-token` (SITE_TOKEN rows) |
| CAS | passport-cas2; user found by `authname`, else **created on the fly** through `appbuilder.model-post` with `password:"CAS"` |
| Okta | passport-openidconnect; user found by email, else created with `password:"Okta"`; failures go to `/okta-error` |
| Login start | `GET /auth/login` picks cas/okta/local from the tenant's `options.authType` (cached forever per tenant) |
| Logout | Clears `tenant_id`/`user_id`, calls `req.logout()`; with CAS returns `<cas>/logout?service=<param>` |
| Password reset | `POST /auth/login/reset {email, url}` → token (10 min) emailed as `<url>auth/password/reset?a=<token>&t=<tenant>`; `GET /auth/password/reset?a=&t=` logs the user in with the token; `POST /auth/password/reset {password}` updates SiteUser |
| Switcheroo | `POST /auth/switcheroo/:userID` (role Switcheroo) stores `session.switcherooID`; the policy applies it on every request; `DELETE` clears it |
| Session | Redis db 1; cookie `secure` only in production |
| authLogger | Appends `ISO  [ip]  message` to `/var/log/appbuilder/auth.log` (fail2ban filter `logs/fail2ban/filter.d/appbuilder.conf` matches lines ending `FAILED`); the IP is the first `X-Forwarded-For` entry. On rootless Docker the log needs an ACL (AGENTS.md §7) |

---

## 6. Sockets and realtime

**Joining rooms:**

- Data rows: a socket request to model-get, model-get-count, model-post or model-post-batch
  registers the live request with `BroadcastManager` (keyed by **username only**); the
  appbuilder handler then calls `api.broadcast-register {ID:[rowIds]}` and api_sails joins
  the socket to rooms `<tenant>-<rowId>`.
- Inbox: `POST /process/inbox/register` joins `<tenant>-<user.uuid>`, `<tenant>-<username>`
  and `<tenant>-<roleUUID>` for every role.
- Designer: builder socket calls to definition create/update/delete or
  `POST /definition/register` join `<tenant>-abdesigner`.

**Pushing:** a service calls `req.broadcast([{room, event, data, copyTo?}])`, which sends
`api.broadcast` to api_sails; `api/lib/broadcastManager.js` collects the sockets in `room`
(and in each `copyTo` room) and calls `sails.sockets.broadcast(socketId, event, data)`.

| Event | Room | Payload | Source |
|---|---|---|---|
| `ab.datacollection.create` / `.update` / `.delete` | `<tenant>-<rowId>` + copyTo rooms of connected records | `{objectId, data, jobID}` | appbuilder writes; ab-utils `dcCreate/dcUpdate/dcDelete` |
| `ab.inbox.create` / `.update` | user and role rooms | inbox item | process_manager |
| `ab.task.userform` | `<tenant>-<userId>` | `{processId, taskId, instanceId, formio, formData}` | BPMN Form task |
| `ab.abdefinition.create` / `.update` / `.delete` | `<tenant>-abdesigner` | definition | definition_manager |

---

## 7. What the browser receives at boot

- `index.html` loads `/config/preloader`, a script that sets `window.__AB_Config_User_Real`,
  loads `/config/site?v=`, `/config/user?v=`, `/definition/myapps?v=` and `/settings`, and
  the v0 plugins: `ABDesigner.js?v=ecs` for Builder/System Builder roles and `HRTeams.js?v=ecs`
  for the hardcoded tenants (`SiteController.js:670-675`: `admin`, `ldhr`, two uuids);
  `window.__AB_plugins_v1` comes from `definition_manager.plugin-links`. The `v` for plugins
  is the constant `"ecs"`, so it never busts caches.
- `/config/site` sets `window.__AB_Config` (tenant_manager.config-site; cached per tenant
  until `api_sails.site-cache-stale`); `/config/user` sets `window.__AB_Config_User`; both
  send a 1-year `Cache-Control` and rely on `?v=` versions.
- `/settings` sets `window.__AB_Settings` (`appbuilder-tenant`, `appbuilder-view`; the
  password-reset flow sets the view).
- Mobile: `/mobile/app/...` renders the shell, `/mobile/preloader/...` loads the bundles and
  `/mobile/definitions` + `/mobile/config/*` into `window.__ab_definitions` /
  `window.__ab_config` (details in [frontend.md](frontend.md)).

---

## 8. Files, CSV, reports

- **Upload:** skipper writes to `/data/tmp` (10 MB max), then `file_processor.file-upload`;
  returns `{uuid, status:"server"}` for Webix. `file-base64-upload` passes a client-supplied
  `uploadedBy`.
- **Download:** `GET /file/:ID` redirects to the stored path (webp for images). **nginx
  serves `/data/` statically with no authentication**, so file URLs are protected only by
  being hard to guess.
- **CSV export:** `appbuilder.csv-export` returns SQL; api_sails then calls
  `sails.getDatastore("appbuilder")`, which does not exist with the ORM hook disabled, so the
  export likely throws and, with no uncaughtException handler, may crash api_sails
  (inferred).
- **Reports:** `custom_reports.report` HTML sent raw with `res.send`.

---

## 9. Security findings

Status: **verified** = confirmed by reading the code paths on 2026-10-02 (not exploited at
runtime); **inferred** = reasoned from code.

### High

1. **Cross-tenant data leak through `copyTo` broadcasts (verified).**
   `api/lib/broadcastManager.js` collects copyTo sockets with
   `sails.io.sockets.in(r).sockets`. In the bundled socket.io 2.5.0, `Namespace.in(name)`
   returns the namespace itself, and its `.sockets` map holds **every connected socket**
   (`node_modules/sails-hook-sockets/node_modules/socket.io/lib/namespace.js:55,147-150,179`).
   So every create/update/delete of a row that has connected records is sent to **every
   browser of every tenant**. The main room was already fixed to use
   `sails.io.sockets.adapter.rooms[room]` (with a comment warning about exactly this); the
   copyTo branch was not. Fix: use the same adapter lookup for copyTo rooms.
2. **SSO-created accounts have fixed passwords (verified).** CAS and Okta auto-provisioned
   users are created with `password:"CAS"` / `"Okta"` (`api/lib/authUserCAS.js:118`,
   `authUserOkta.js:99`), appbuilder hashes them like any password, and the `local`
   strategy is always registered with no check for SSO accounts. Anyone who knows such a
   user's email can log in locally with that literal password.
3. **Password-reset link poisoning (verified):** the caller of `POST /auth/login/reset`
   chooses the `url` the emailed token link points to.
4. **Logout does not end impersonation (verified that `switcherooID` is not cleared;
   impact inferred):** `auth/logout.js` clears `tenant_id`/`user_id` only, so later requests
   on that session can still act as the impersonated user.
5. **Raw SQL fragments from the client `where` (inferred):** api_sails forwards `where`
   untouched; the server compiler uses keys verbatim and passes some values unquoted
   ([server-platform.md §5.5](server-platform.md#55-sql-compiler-platformabmodeljs-parsecondition-1157-1654)).
6. **Reflected XSS in `/mobile/preloader/:tenantID/:appID` (verified that `appID` is
   printed unescaped with `<%-` in `views/pwa_preloader.ejs:43-44`).**
7. Builders can push an app's definitions into **every tenant** that has it
   (`/definition/tenants-update-application`); the api_sails side also builds a file path
   from the free-form `applicationUUID` (inferred traversal).
8. `POST /tenant/add` needs only a login (no role check found; inferred).
9. **Plugin code execution:** `POST /definition/plugin/add` (builder) registers URLs whose
   code every AppBuilder service then executes ([server-platform.md trap 2](server-platform.md#9-traps)).
10. **Any user through the relay header (verified in code on 2026-10-30).**
    `api/lib/authUserRelay.js` (set up in `api/hooks/initPassport.js`, tried by
    `api/policies/authUser.js`) accepts `authorization: relay@@@<token>@@@<SiteUser.uuid>`
    as that user. `config/local.js` turns it on by default (`RELAY_ENABLE`, `true`) with the
    token `"There is no spoon."` when `RELAY_SERVER_TOKEN` is empty, and compose sets
    neither (known issues S38).

### Medium

10. Unauthenticated surface: `/testlog`, `/test/reset` (tenant from a param), `/metrics`,
    `/config` (tenant list), `/healthcheck` and `/versioncheck` (about 15 internal calls
    each, caller-controlled `?timeout`), `/mobile/config/settings/:appID`, `/okta-error`
    (sends the session and headers to telemetry). The `AB_TESTING` gate checks "defined",
    so `AB_TESTING=false` still enables test routes; compose sets it on the default stack.
11. Uploaded files are public via nginx `/data/`; `/assets/ab_plugins` publishes plugin
    folders (inferred).
12. `tenant-token` is trusted verbatim; with `trustProxy` and a non-production `NODE_ENV`,
    `X-Forwarded-Host: localhost` on port 1337 resolves to the admin tenant (inferred).
13. Sessions: hardcoded fallback secret, no session regeneration on login (fixation,
    inferred), cookies not secure outside production, no CSRF, no socket origin check.
14. fail2ban can be evaded: the logged IP is the client-controllable first
    `X-Forwarded-For` entry; CAS/Okta errors do not end in `FAILED`.
15. `test-import` reads any JSON at `path.join(cwd, file)`; `..` escapes the folder.
16. Secrets in logs/telemetry: NetSuite credentials as GET params, reset tokens logged,
    passwords in Sentry job data.

### Correctness

17. Shared-closure helpers in `req.ab` misattribute notifications under concurrency.
18. `BroadcastManager` keys live requests by username across tenants; with several
    api_sails replicas, `api.broadcast` reaches only one instance's sockets (inferred).
19. Possible double responses / hangs: `mobile/version.js` (reauth without return),
    mobile config endpoints after `validUser()` auto-responds, `reset-password-verify`,
    deserializeUser without a catch.
20. Caches that never expire (`hashLookup`, tenant options) and 1-year `Cache-Control` on
    user-specific JS.
21. Temp files are never cleaned (json-import uploads, tenants-update files).
