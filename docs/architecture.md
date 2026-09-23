# Architecture — AppBuilder (AB) v2

Reference detail for the AppBuilder platform. Load this when you are working inside a
specific subsystem; `AGENTS.md` carries everything needed to act safely without it.

Container topology, ports and bind mounts live in `AGENTS.md` §4.1, not here — those change
what you do on your first command, so they stay in the always-loaded file.

---

## 1. Messaging — cote

All inter-service traffic is **cote** RPC. Precisely:

- All payloads — req/rep **and** pub/sub — travel over **@dashersw/axon sockets on raw TCP**.
- **Redis carries discovery only** — `COTE_DISCOVERY_REDIS_HOST=redis` enables cote's redis
  discovery plugin, whose pub/sub carries node-discover hello/advertisement beacons in place
  of UDP broadcast. No application payload of any kind touches Redis; the only Redis traffic
  is node-discover's beacon channel, literally named `cote`. No service uses Redis directly.

Message key convention: **`<service_key>.<handler-name>`**. The *whole string* is the cote
message `type` the responder dispatches on; only `key.split(".")[0]` is the advertisement
domain used to find peers. Only dots split; underscores do not. That is why multi-dot keys
(`tenant_manager.config.list`, `process_manager.inbox.find`,
`process_manager.userform.create`) route fine, and why `api_sails` can host domain `api`
(`api.broadcast`, `api.broadcast-register`) separately from domain `api_sails`.

Wire envelope, identical for request/publish/subscribe:
`{type: <full key>, param: {jobID, requestID, tenantID, user, userReal, data}}`.

Pub/sub channels in use: `definition.stale | created | updated | destroyed`, published by
`definition_manager`, consumed by `platform_service/ABBootstrap.js` to invalidate factories.

`@digiserve/ab-utils`' `ABServiceController` supplies everything cross-cutting: handler
auto-loading, joi `inputValidation`, duplicate suppression by `requestID`, telemetry spans,
`EDISABLED` gating from `config.enable`, worker-thread JSON serialization, and auto-injected
`<service>.healthcheck` / `<service>.versioncheck`.

## 2. Domain model — everything is a definition row

Applications, objects, fields, views, pages, processes, queries and indexes are **all rows
in one table**, `appbuilder_definition`, shaped `{id, name, type, json}`. There is no
per-entity table.

- The object graph is **ID-reference, not nesting**: `ABApplication` holds
  `objectIDs/queryIDs/pageIDs/...`, `ABObject` holds `fieldIDs/indexIDs`, `ABView` holds
  `viewIDs`. It is reconstructed by ID-chasing at load time.
- Broken references are **parked, never dropped** (`_unknownFieldIDs`, `__missingViews`,
  `__missingObject`) and re-emitted by `toObj()`, so a broken reference survives a save
  round-trip and stays diagnosable. Preserve this behaviour.
- Saving a page is **N definition writes**, not one.

## 3. The core/platform split

`class_core` is a submodule mounted **at** `<platform-repo>/core`, and every core file
imports its base class via `../platform/...`. The inheritance chain therefore alternates
repos on every hop:

```
platform/dataFields/ABFieldString.js  extends
core/dataFields/ABFieldStringCore.js  extends
platform/dataFields/ABField.js        extends
core/dataFields/ABFieldCore.js        extends
platform/ABMLClass.js                 extends
core/ABMLClassCore.js
```

One core body, three platform bodies: `platform_service` (Node), `platform_web` (Webix
browser), `platform_pwa` (Framework7 mobile). This is why `AB.objectByID(x).fields()` means
the same thing on server and browser.

**Rule:** put behaviour in `core` only if *both* web and service can honour it. Otherwise
implement in `platform/` and stub the other platform. Never add browser/Webix code to a
`*Core` file. Never import another `*Core` file as a base class.

## 4. Multi-tenancy

**Database-per-tenant on one MariaDB server** — not schemas, not prefixed tables.

- Tenant DB = `appbuilder-<tenant uuid>`; site DB = `appbuilder-admin`.
- The seeded `admin` tenant has uuid literally `"admin"`, so **its tenant DB *is* the site
  DB**. That identity is load-bearing: changing `MYSQL_DBPREFIX`, `MYSQL_DBADMIN` or
  `TENANT_MANAGER_TENANT_ID` independently breaks the seed scripts.
- Table names are identical in every tenant DB. Isolation comes from fully qualifying the
  database in raw SQL (`${tenantDB}.\`SITE_ROLE\``) or from a knex connection whose
  `database` is the tenant DB — **not** from separate pools. `ab-utils` keeps one
  module-level mysql pool per process, so an unqualified query hits the wrong database.
- `tenantID` is `site_tenant.uuid`, resolved per request in
  `api_sails/api/policies/authTenant.js` and then carried on every cote hop.

## 5. Request lifecycle

Browser (Webix, `io.socket.request` by default) → nginx `web` → `api_sails` → policy stack
`[abUtils, telemetry, authTenant, authUser, authSwitcheroo]` → controller validates and
calls `req.ab.serviceRequest("appbuilder.model-get", jobData, opts, cb)` → cote/axon →
service handler → `ABBootstrap.init(req)` → per-tenant `ABFactory` → `ABModel` →
Objection/knex → tenant DB.

Return path: `req.broadcast(...)` → `api.broadcast` back into api_sails → socket.io rooms
keyed `${tenantID}-${rowID}`.

`api_sails` is a **pure adapter**: no models, no blueprints, `config/blueprints.js` is `{}`.
All data work happens in other services.

## 6. Front end

- **Webix UI 10.1.0 Pro, vendored** into `platform_web/js/webix/` under a commercial
  licence. It is not in `package.json`. Upgrading it is a licensing action, not an npm bump.
  There is no React and no Vue. The mobile PWA is Framework7 9.x (its JSX is Framework7's
  `$jsx`, not React).
- Four independent webpack projects emit under one shared output **root**,
  `developer/ui/web/assets` — `platform_web` at the root, `platform_pwa` into
  `assets/mobile`, `ABDesigner` and `HRTeams` into `assets/tenant/default` (HRTeams' *prod*
  config instead writes to its own `./build`). They meet only in the browser, via globals.
- Two plugin generations coexist: **v0** (`window.__AB_Plugins`, used by ABDesigner and
  HRTeams) and **v1** (`window.__AB_plugins_v1` URL list → `AB.pluginRegister(factory)`).
  The 21 built-in widgets use the same v1 factory signature as external plugins.
- Widget code is split in half by design: the **runtime** half lives in
  `platform_web/AppBuilder/platform/plugins/included/view_x/`, the **designer** half in
  `ABDesigner/src/plugins/web_view_x/`.
- Config arrives as **executable JS, not JSON**: `/config/site`, `/config/user`,
  `/settings` respond `text/javascript` assigning `window.__AB_Config` etc.
