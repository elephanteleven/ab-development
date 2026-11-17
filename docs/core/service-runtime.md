# Service runtime (ab-utils)

ab-utils (`@digiserve/ab-utils`, repo `CruGlobal/ab-utils`) is the shared runtime under
every Node service: the controller that loads handlers and talks cote, the `req` object
handlers receive, inter-service requests with retries, validation, pub/sub,
notifications, telemetry, config helpers and the shared MySQL pool. Each service runs the
copy npm installed in its own `node_modules/@digiserve/ab-utils`
(`github:CruGlobal/ab-utils#1.11.1` in all eleven).

Verified against ab-utils `master` `ea8c513` (v1.11.1) on 2026-10-02. The installed
copies have had no local edits since 2026-10-30; the two that were there before
(`utils/controller.js`: the DB probe called `end()`; `utils/defaults.js`: `env()` no longer
logged values) are kept in `backups/patches/2026-10-05/ab-utils.patch` (known issue C1).
Without the second one, `env()` logs values it cannot parse as JSON (known issue S39). Paths are relative to the ab-utils package (`node_modules/@digiserve/ab-utils/` in a
service) unless they start with `developer/`. The generated API docs in
`docs/*.md` (jsdoc) are partly stale; prefer this page and the code.

Related: [architecture.md §1](architecture.md#1-messaging--cote) (cote basics),
[services.md](services.md), [api.md](api.md) (`req.ab` / `res.ab` in api_sails).

---

## 1. Exports (`ab-utils.js:22-53`)

| Export | Value |
|---|---|
| `config` | `config(key?)` returns a **Promise** of `<cwd>/config/local.js` (or its `[key]`); on failure logs and resolves `{}` (`utils/config.js:14-29`) |
| `controller` | `controller(key)` returns a new `ABServiceController` |
| `defaults` | `{ env, datastores }` |
| `reqApi`, `reqService`, `resApi` | Factories for the API request, service request and API response objects |
| `service` | Legacy `ABService` (unused) |
| `telemetry` | The singleton telemetry instance (`AB.telemetry.init(...)`) |
| `uuid` | uuid v4 via the local shim |

### File map

| Path | Purpose |
|---|---|
| `utils/controller.js` | ABServiceController: lifecycle, handler loading, cote responder, dispatch |
| `utils/reqService.js` | ABRequestService: the `req` given to service handlers |
| `utils/reqApi.js`, `utils/resApi.js` | `req.ab` / `res.ab` used by api_sails |
| `utils/serviceRequest.js` | cote Requester wrapper: timeouts, retries, "overtime" |
| `utils/reqServiceCote.js` | Base class; `toParam()` builds the wire envelope |
| `utils/reqServicePublish.js`, `reqServiceSubscriber.js`, `reqServiceResponder.js` | One cote Publisher / Subscriber / Responder per domain |
| `utils/reqValidation.js` | joi validator builder |
| `utils/reqNotification.js` | `notify(domain, error, info)` |
| `utils/reqPerformance.js` | `performance.mark/measure/log` (also opens/closes telemetry spans) |
| `utils/telemetry*.js` | Facade + providers: default (cote to log_manager), Sentry, OpenTelemetry |
| `utils/defaultHealthcheck.js`, `utils/handlerVersion.js` | Auto-added `<key>.healthcheck` / `<key>.versioncheck` |
| `utils/dbConn.js` | Shared mysql pool |
| `utils/defaults.js` | `env()`, `datastores()` |
| `utils/model.js` | Legacy Waterline-style model (only file_processor's legacy `FileUpload` uses it) |
| `shared/utils/utils.js` | PBKDF2 helpers; dead (user_manager has its own copy) |
| `shims/uuid/` | Local `uuid` package re-exporting uuid 11 plus the legacy `./v4` path node-discover needs |
| `test/` | mocha suite (§9) |

---

## 2. ABServiceController

### Construction (`utils/controller.js:90-152`)

Logs `<key> v<version>` (from `<cwd>/package.json`); `waitForDB` defaults to false
(appbuilder and process_manager set it true); SIGINT/SIGTERM call `exit()`;
`unhandledRejection` / `uncaughtException` / `multipleResolves` are only **logged**, the
process keeps running; creates a workerpool. Requiring ab-utils also starts a 1 s
job-status monitor that prints jobs older than 1 s (every process, api_sails included).

### `init()` sequence (`:273-393`)

| Step | Action |
|---|---|
| 0 | Dynamic `import()` of `handlers/*` and `models/*` |
| 1 | `config()`; `this.config = cfg[this.key]`, `this.connections = cfg.datastores` |
| 2 | `new cote.Responder({name: key, key: key, port: 9000})` |
| 2.5 | Only if `waitForDB`: `tryConnect(configDB())` every 500 ms until MySQL answers, then `end()` |
| 3 | `beforeStartup` hooks (`fn(cb)`) |
| 4 | Register every handler |
| 5 | `afterStartup` hooks (`fn(req, cb)`, jobID `<key>.after_startup`) |
| HTTP | Express on **port 80** inside the container: `GET /monitors/lb` returns `v<version>` |
| 6 | `process.send("ready")` if there is an IPC parent |

Any rejection becomes `notify.developer(err, {initState})` and the process stays alive.
Telemetry is initialized by each service's `app.js`, not by the controller.

### Handler discovery

Every file in `handlers/` (except `.DS_Store`, `.gitkeep`) is imported and registered if
`mod.default ?? mod` has `.key` and `.fn`. **Import errors are only logged and the file is
skipped**: a syntax error makes that key vanish and callers just time out. Default
`<key>.healthcheck` (returns `"OK"`) and `<key>.versioncheck` are added unless the service
defines its own.

**Routing rule:** the responder advertises `key: <controller key>`, and requesters find
peers by the request key's first dot-segment. A handler whose key prefix differs from the
controller key registers but can never be reached (file_processor's legacy `model.find` /
`file.upload` are examples).

### Dispatch (`handler._cFN`, `:479-683`)

For each cote message `{type, param, __timeout}`:

1. Build `req` and a telemetry span.
2. No config: `EMISSINGCONFIG` (config/local.js must have a key equal to the controller key).
3. `enable: false`: `EDISABLED` (healthcheck too).
4. `inputValidation` fails: `{message:"Invalid Inputs", code:"EINVALIDINPUTS", errors}`.
5. **Duplicate suppression:** a resend with a requestID that is still pending replaces the
   callback instead of re-running the handler; both get the answer. A resend after
   completion runs the handler again.
6. `handler.fn(req, cb)`. Errors become `{code, message: err.toString(), stack}` (so
   `message` starts with `"Error: "`); strings pass through; other data is JSON-stringified
   **on a worker thread** (falls back to `bfj`, then the raw object).
7. A synchronous throw is reported and answered; **an async throw never calls `cb`**, so
   the caller waits for its timeout and retries.

### Hooks and shutdown

`beforeStartup(fn(cb))`, `afterStartup(fn(req, cb))`, `beforeShutdown(fn(req, cb))`,
`afterShutdown(fn(cb))`. `exit()` runs beforeShutdown, `shutdown()` (fails pending
requests with "Service Shutdown"), afterShutdown, terminates the pool, exits. Use
`req.worker(fn, params)` for worker threads; **`req.workerExec()` is broken** (the
controller has no such method).

---

## 3. The service `req` (`utils/reqService.js`)

### Properties

`jobID`, `requestID`, `_tenantID`, `_user`, `_userReal` (set only under Switcheroo),
`serviceKey`, `performance`, `data` (the request payload), `controller`.

### Methods

| Method | Behavior |
|---|---|
| `log(...a)`, `log.verbose(...)` | Prints `MM:SS.ffffffZ <jobID>::...`; verbose only when `config().verbose` |
| `logError(msg, err)` | Serialized error plus `err._context` |
| `notify(domain, err, info)`, `notify.builder`, `notify.developer` | See §5 |
| `param(k)` | The **raw** `data[k]` (not the joi-normalized value) |
| `params(ignore)`, `allParams(...)` | |
| `config()`, `connections()`, `configDB()` | Service config; tenant set selects the `appbuilder` datastore, else `site` |
| `dbConnection(create, isolate)` | Shared pool (§6) |
| `query(sql, vals, cb)` / `queryAsync` | Shared pool, wrapped in `retry()` |
| `queryIsolate*` | Private 5-connection pool |
| `queryTenantDB(reject)` | Tenant DB name or `ENOTENANT` |
| `queryWhereCondition(cond)` | Values bound with `?`; keys and unknown operators interpolated raw |
| `retry(fn)` | Up to 11 retries (12 attempts); from the 3rd retry waits random(1-3) x count x 100 ms; retryable codes: `ECONNRESET`, `ETIMEDOUT`, `PROTOCOL_*`, `ER_LOCK_DEADLOCK`, `ER_LOCK_WAIT_TIMEOUT`, `KnexTimeoutError`, ... (`:73-86`) |
| `languageCode()` | User's code or `en` |
| `broadcast(packets, cb)` | Sends `api.broadcast` (see [api.md §6](api.md#6-sockets-and-realtime)) |
| `broadcast.inboxCreate/inboxUpdate/dcCreate/dcUpdate/dcDelete` | Packet helpers |
| `socketKey(k)` | `${tenantID}-${k}` |
| `tenantDB()` | Escaped `` `appbuilder-<tenant>` `` or `""` |
| `tenantID()` | `null` when unset (`"??"`) |
| `username()` | `_system_` when there is no user; `usernameReal()`, `userDefaults()` |
| `serviceRequest`, `servicePublish`, `serviceSubscribe` | §4, §5 |
| `worker(fn, params)` | Worker-pool execution |
| `toABFactoryReq()` | Copy without a user, for ABBootstrap |

There is no `tenantSet()`, no switcheroo method and no cache API on the service side.

**Shared-closure defect:** the constructor stores `log.verbose`, `notify.builder`,
`notify.developer` and the five `broadcast.*` helpers as properties **on the prototype
functions** (`:173-397`), so each new request overwrites them with closures over itself.
Under concurrency, `req.notify.developer()` and `req.broadcast.inboxCreate()` run with the
**most recently constructed** request's jobID, tenant, user and `socketKey()` (verified by
reading; impact inferred). `reqApi.js` has the same pattern.

---

## 4. Inter-service requests (`utils/serviceRequest.js`)

`req.serviceRequest(key, data, [options], [cb])` returns a Promise (and calls `cb`).

| Option | Default | Meaning |
|---|---|---|
| `timeout` | 5000 ms | Per-send timeout |
| `longRequest` | off | Use 90000 ms. Pass it in **options**; putting it in `data` still works but notifies a developer warning |
| `maxAttempts` | 5 | Normal sends before giving up |
| `stringResult` | off | Skip `JSON.parse` of string results |

- **Envelope:** `{type: key, param: {jobID, requestID, tenantID, user, userReal, data}}`
  plus `__timeout`. The requestID is created once and reused on every resend, which is what
  lets the responder dedupe.
- **Requesters:** one per domain (the key's first segment), cached per process.
- **Retry:** only cote's `"Request timed out."` is retried. After `maxAttempts` the caller
  gets the error (with `err._serviceRequest`, `err._params`) and a developer notification
  ("Could not request (key) ..."), **then an "overtime" phase keeps resending the same
  envelope up to 50 more times**, starting at 90 s and multiplying by 1.5 each time; a late
  answer is reported as `EOVERTIME`. With defaults that is 5 + 50 sends (asserted by
  `test/unit/serviceRequest.test.js:131-148`). Handlers must therefore be idempotent.
- **Results:** strings are JSON-parsed unless `stringResult` or the value is `"OK"`.
- **Errors callers can see:** cote timeout, `EMISSINGCONFIG`, `EDISABLED`,
  `EINVALIDINPUTS`, `{code, message:"Error: ...", stack}`, any object a handler passed to
  `cb`, or `{}` for thrown Errors (inferred).

---

## 5. Validation, pub/sub, notifications, telemetry

### Validation (`utils/reqValidation.js`)

Handler `inputValidation` rules look like
`{param: {string: true|{email:true}, uuid..., required: true, optional, allow, with, xor,
pattern, min, max, validate: fn}}` and become a `Joi.object`. Validators are cached by
`JSON.stringify(description)`. **Unknown keys are rejected** (joi `allowUnknown:false`), so
callers may send only declared fields. Errors: `Error("Validation Errors")` with
`key:"E_VALIDATION"`, `validationErrors`, `code:422`. api_sails' `req.ab.param` returns the
normalized value; the service `req.param` returns the raw value.

### Pub/sub

`servicePublish(key, data)` uses one cote Publisher per domain; `serviceSubscribe(key,
handler)` one Subscriber per domain (subscribing twice runs the handler twice; no ack or
retry). The platform uses only `definition.*` channels ([server-platform.md §2](server-platform.md#2-abbootstrap)).

### Notifications (`utils/reqNotification.js`)

`req.notify.developer(err, info)` (operational problems) and `req.notify.builder(err,
info)` (app configuration problems) serialize the error, add tenantID, jobID, requestID,
serviceKey and the user, log it, and hand it to telemetry. With the default provider that
becomes cote `log_manager.notification`; **with Sentry active nothing reaches log_manager**.

### Telemetry

- Each service's `app.js` calls `AB.telemetry.init("sentry", {dsn, release})` when
  `TELEMETRY_PROVIDER` (default `"sentry"`) is `"sentry"`, with a **hardcoded upstream DSN
  default** (`o144358.ingest.sentry.io`). Compose passes `TELEMETRY_PROVIDER` to no
  container and `SENTRY_DSN` only to log_manager, so **a local stack reports to that
  upstream Sentry project by default**. Set `TELEMETRY_PROVIDER` (anything but `sentry`)
  or `SENTRY_DSN` to change it.
- Sentry: sample, trace and profile rates 0.1; builder errors become warnings.
- Each request writes its full `data` into Sentry's "Job Data" context, which for
  `user_manager.user-find-password` includes the plaintext password (whether Sentry
  scrubs it is unverified).
- OpenTelemetry provider exists but nothing selects it.

---

## 6. Config helpers and the shared pool

- **`env(key, default)`** (`utils/defaults.js:14-26`): default for undefined or `""`;
  otherwise `JSON.parse` (so `"true"` becomes a boolean, `"123"` a number), falling back to
  the raw string. It no longer logs values that fail to parse.
- **`datastores()`** (`:30-48`): `appbuilder` (database `MYSQL_DBPREFIX`, default
  `appbuilder`) and `site` (database `MYSQL_DBADMIN`, default `appbuilder-admin`); both on
  `MYSQL_HOST` (`db`), `MYSQL_PORT` (3306), `MYSQL_USER` (`root`), `MYSQL_PASSWORD` (read raw).
- **`dbConn.js`:** one lazy module-level `mysql` pool (connectionLimit 10); `isolate`
  returns a fresh 5-connection pool. The pool keeps whichever datastore settings the first
  caller used, another reason all SQL must be DB-qualified. Pool `error` handlers never
  fire (mysql's Pool does not emit `error`; inferred from library source). The pool has no
  idle timeout, so MariaDB's 60 s `wait_timeout` closes idle connections (the harmless
  `Aborted connection ... timeout` lines in AGENTS.md §7.1).

---

## 7. API-side objects (api_sails)

`req.ab` (ABRequestAPI) adds `tenantID`/`user`/`userReal` accessors, `tenantSet()`,
`isSwitcherood()`, `switcherooToUser()`, `validateParameters()`, `validUser()`,
`validBuilder()`, `validRoles()`, `validSwitcheroo()`, `serviceRequest()`; `res.ab`
(ABResponseAPI) has `success()`, `error()`, `reauth()`. Details and traps (every error
packet says `jobID:"??"`, `E_REAUTH` is sent as 400) are in [api.md](api.md#3-request-helpers-reqab-and-resab).

---

## 8. Shims and the uuid trap

`shims/uuid` is a package named `uuid` that re-exports uuid 11 and adds the `./v4` path
node-discover needs. Services' `node_modules/uuid` symlinks into the mounted ab-utils
checkout, so checking out an ab-utils branch without `shims/` breaks every service
(AGENTS.md §7).

---

## 9. Tests

`npm test` = mocha over `test/**/*.test.js` (no lint, safe to run; 134 passing, 1 pending
on 2026-09-29). `npm run lint` uses `--fix` and writes to files. Covered: config, dbConn,
model, reqAPI, reqService helpers, reqNotification, publisher/responder/subscriber,
resAPI, serviceRequest (retry counts, options, loop guard). **Not covered:** controller
(startup, dispatch, dedupe), reqValidation, defaults, reqPerformance, telemetry providers.

---

## 10. Traps

1. A handler file that throws on import silently disappears (callers time out).
2. A handler key whose first segment differs from the controller key is unreachable.
3. Async throws inside a handler never answer; the caller retries for minutes, then the
   overtime phase keeps resending for a very long time (inferred).
4. Shared-closure helpers misattribute notifications and broadcasts under concurrency (§3).
5. `AB.config()` is a Promise: synchronous callers break silently
   (`notification_email/src/send.js:7` breaks email; `appbuilder/app.js:26` falls back to
   defaults).
6. Unknown request keys fail validation: when adding a field to a caller, add it to the
   handler's `inputValidation` first.
7. `longRequest` belongs in the options argument, not in `data`.
8. Local stacks report errors to the upstream Sentry project unless configured (§5).
