# Browser portal (platform_web)

`developer/ab_platform_web` is the browser runtime that every end user and builder loads.
It boots the portal, builds the browser `ABFactory` from the definitions the server sends,
renders the user's web applications with Webix, and keeps them live over a socket. The
builder IDE ([abdesigner.md](../plugins/abdesigner.md)) and the HR Teams widget
([hrteams-widget.md](../plugins/hrteams-widget.md)) are plugins loaded into this portal. Every widget
type and its settings are in [widgets.md](widgets.md).

Verified on 2026-10-02 against platform_web `560b6d80` (branch `master`, 2026-09-01,
version `1.26.2+c22000`), with its nested `AppBuilder/core` at class_core `2ecde31`
(v2.20.0). This was a code read: no build, test or browser session was run for this page.
The checkout is at `8707f2fe` (1.26.5, class_core `a0008f4` = 2.20.1) since 2026-10-30.
Paths are relative to `developer/ab_platform_web/` unless they start with `developer/`.

---

## 1. Where things are

| Path | What it is |
|---|---|
| `index.js` | Webpack entry `app`: CSS, telemetry, lazy Webix, waits for the preloader, then `Bootstrap.init()` |
| `init/Bootstrap.js` | The boot steps (§2.3) |
| `init/initDiv.js`, `initConfig.js`, `initUser.js` | Find or create the portal `<div>`; copy the `window.__AB_*` globals into `Config` |
| `init/sailsIo.js` | Webpack entry `sailsio`: sails.io.js over socket.io-client v2; resolves `__AB_socketReady` on connect |
| `init/formio.js` | Lazy Form.io bundle, used by the `formiopreview` and `formiobuilder` views |
| `config/` | `Config.js` (settings store and defaults) and the desktop and mobile size constants |
| `resources/` | Account, Multilingual, Network (+ NetworkRest, NetworkRestSocket), Storage (+ StorageLocal), Tenant |
| `AppBuilder/ABFactory.js` | Browser factory on top of `core/ABFactoryCore` |
| `AppBuilder/platform/` | Browser platform classes (§5): objects, models, data collections, 20 field classes, views, process, ql, mobile |
| `AppBuilder/platform/plugins/` | Plugin base classes. `included/` holds the 21 built-in widgets; `developer/` holds a NetSuite plugin that is not loaded |
| `AppBuilder/rules/` | Form record rules, submit rules and their actions ([widgets.md](widgets.md) §3.4) |
| `AppBuilder/uiSettings/` | `AB.UISettings`: size sets and the icon list |
| `AppBuilder/core` | Nested class_core checkout ([domain-model.md](domain-model.md)) |
| `ui/` | Portal shell, work portal, page renderer, login screens, inbox, user windows, managers (§4) |
| `webix_custom_components/` | 15 custom Webix views (§5.8) |
| `utils/performance.js`, `utils/networkTest.js` | Sentry or User Timing telemetry; the slow-network Web Worker |
| `js/webix/` | Vendored Webix 10.1.0 Pro and its Pro components (gantt, kanban, pivot, query, reports, scheduler and others) |
| `styles/` | `loader.css`, `ui.css`, Font Awesome |
| `webpack.*.mjs`, `webpack/index.ejs` | Build (§8). The template becomes `developer/web/assets/index.html` |
| `test/` | mocha + jsdom unit tests (§9) |

Dead code, imported by nothing (grep): `init/initAttach.js`, `AppBuilder/AppBuilder_New.js`,
`AppBuilder/rules/ABViewGridFilterMenu.js`, `webix_custom_components/savablelayout.js`.
`js/selectivity/` is vendored, but its import is commented out (`init/Bootstrap.js:22-23`).

---

## 2. Boot

### 2.1 HTML shell and preloader

`webpack/index.ejs` (built into `assets/index.html`) creates two promises,
`window.__AB_preload` and `window.__AB_socketReady`, shows a static spinner, and loads
`/config/preloader` with `defer` (`webpack/index.ejs:22-30`). Webpack injects the
`runtime`, `app` and `sailsio` scripts.

api_sails serves `/config/preloader` from `SiteController.preloader`, rendered with
`developer/api_sails/views/web_preloader.ejs`. That script:

1. sets `window.__AB_Config_User_Real` (the real user while switcheroo'd, else 0) and
   `window.__AB_Plugins = []`;
2. loads four scripts in parallel:
   - `/config/site?v=` sets `window.__AB_Config` (cached per tenant in api_sails, sent with
     a 1-year `Cache-Control`);
   - `/config/user?v=` sets `window.__AB_Config_User`;
   - `/definition/myapps?v=` sets `window.definitions` (`[]` when not logged in);
   - `/settings` sets `window.__AB_Settings` (`appbuilder-tenant`, `appbuilder-view`);
3. loads the v0 plugin scripts: `ABDesigner.js` for builders and `HRTeams.js` for a
   hardcoded tenant list (`developer/api_sails/api/controllers/SiteController.js:624-685`);
4. sets `window.__AB_plugins_v1` to the URLs from `definition_manager.plugin-links`
   (platform `web`). Plugins of type `properties` go only to builders;
5. waits for every script and the socket, then resolves `__AB_preload`.

The `?v=` values for site, user and apps come from real version lookups. The web and
HRTeams versions are the constant `"ecs"` (`SiteController.js:852-853`, `868-869`), so
those plugin URLs never change and browsers can keep an old bundle after a rebuild.

`window.__AB_Config` comes from `tenant_manager.config-site`: `site` (`relay`, `tenants`,
`privacyPolicy`), `tenant`, `labels`, `languages`, `meta` (roles, scopes, users) and
`settings`. The server sends no `site.appbuilder` block, so the client defaults in §3.1
always apply.

### 2.2 `index.js`

1. Imports the CSS (Font Awesome last, on purpose) and runs `performance.init()`.
2. Starts the dynamic import of `webix.min.js`. When it lands, it sets `window.webix` and
   fires a non-awaited import of `js/webix/webixResources.js`, which sets
   `window.gantt/kanban/pivot/reports/scheduler`.
3. Waits for `__AB_preload` and `__AB_socketReady`, then calls `Bootstrap.init(webixLoading)`.
   Errors other than `ENODEFS` show "Error initializing Portal:" (`index.js:39-55`).

### 2.3 `Bootstrap.init()`

| Step | What happens | Evidence |
|---|---|---|
| 0 | Start the lazy `AppBuilder/ABFactory` import and the network-test worker | `init/Bootstrap.js:65-119` |
| 1 | `initDiv`: find `div[appbuilder-portal]` or create one (id `AppBuilder`); read its `appbuilder-*` attributes into settings | `init/initDiv.js:12-45` |
| 2 | `initConfig`: load `__AB_Settings` and `__AB_Config`. On "Failed to fetch" it redirects to `/` (an OKTA/CAS CORS hotfix) | `init/initConfig.js:6-17` |
| 3 | `initUser`: load `__AB_Config_User` and the real user | `init/initUser.js:6-10` |
| 4 | Logged in: set the Sentry user and honour `sessionStorage.refererUrlPWA`. Not logged in, and the tenant's `authType` is not `login`: go to `/auth/login` and stop | `init/Bootstrap.js:139-163` |
| 5 | Copy `window.__AB_Plugins` (v0) | `:168-170` |
| 6 | Build `new ABFactory(definitions + each v0 plugin's definitions())` and set `window.AB` | `:178-198` |
| 7 | Load each v1 plugin URL (ESM import, then fetch + blob import, then UMD reading `window.Plugin`) and call `AB.pluginRegister(fn)` | `:200-379` |
| 8 | `await AB.init()`, then `await webixLoading` | `:381-382` |
| 9 | The user has 0 roles: show the "Access required" screen and throw `ENODEFS` | `:385-399` |
| 10 | v0 plugins: `p.apply(AB)`, then load their labels | `:402-406` |
| 11 | `webix.ready`: map `en`, `zh-hans` and `th` to Webix locales, attach `ui/ui.js`, remove the spinner, run `UI.init(AB)` | `:413-452` |

### 2.4 Tenant and user

The browser never picks the tenant. api_sails resolves it per request
([architecture.md](architecture.md) §4) and sends the tenant record in
`__AB_Config.tenant`. `Tenant.id()` returns `tenant.id`, or null for `"??"`
(`resources/Tenant.js:36-41`). Every REST or socket call sends `tenant-token: Tenant.id()`
(`resources/NetworkRest.js:232-235`). The `appbuilder-tenant` setting is stored but never
read.

Authentication rides on the session cookie. `Account.authToken` is read by NetworkRest
(`resources/NetworkRest.js:222-224`), but nothing ever sets it (grep).

### 2.5 Factory construction and `AB.init()`

- The constructor attaches the resources plus `AB.Webix`. It adds `AB.Class.FilterComplex`,
  `ABViewManager`, `SortPopup` and `ABViewComponent`, no-op `Analytics` and `Lock`
  placeholders, `AB.Validation`, and the platform `rules` helpers (`toDate`, `addDate`,
  and so on) (`AppBuilder/ABFactory.js:99-557`).
- `init()` starts Account, Multilingual, Network and Tenant in parallel, then Storage. It
  then loads `local_settings`, registers the `ab.abdefinition.*` handlers and calls core
  `init()` (`AppBuilder/ABFactory.js:566-632`).
- Core `init()` registers the 21 included widgets first (`pluginLocalLoad`). It then builds
  definitions in this order: object, query, datacollection, process, hint, step,
  application (`AppBuilder/core/ABFactoryCore.js:261-298`).

### 2.6 Plugin generations at boot

| Generation | Who | How it loads |
|---|---|---|
| Included widgets | The 21 built-in widgets | `AB.pluginRegister` during core init, before definitions are parsed |
| v1 | Tenant-installed plugins (`window.__AB_plugins_v1`) | Bootstrap step 7, before `AB.init()`. Same `(pluginAPI) => Class \| Class[]` factory as the included widgets |
| v0 | ABDesigner and HRTeams (`window.__AB_Plugins`) | Definitions merged at step 6; `apply(AB)` and labels at step 10. Plugin "applications" with `pages` appear in the sidebar (`ui/portal_work.js:289-295`) |

---

## 3. Config and resources

### 3.1 `Config`

| Key | Default | Evidence |
|---|---|---|
| Div settings `autoenter`, `fullscreen`, `tenant`, `view`, `prefix` | true, true, null, `work`, null | `config/Config.js:7-28` |
| `site.appbuilder.networkType` | `socket` (options `rest`, `relay`, `socket`) | `:30-50` |
| `site.appbuilder.networkNumRetries` | 3 | |
| `site.appbuilder.urlCoreServer` | `window.location.origin` | |
| `site.storage.encrypted` | false (encryption is a TODO) | |

`uiSettings()` switches to the mobile size set below 768 px of window width
(`config/Config.js:205-210`).

**Network types.** `socket`, the default, sends every request with `io.socket.request` and
receives realtime events. `rest` uses XHR and gets no realtime events. `relay` leaves the
transport undefined, so `Network.init` throws (`resources/Network.js:52-67`).

### 3.2 `Network` (the facade)

- `get`, `post`, `put` and `delete` call the transport and return `data.data || data`
  (`resources/Network.js:117-177`, `280-307`).
- **The jobResponse pattern.** A caller passes `{key, context}`, and the transport emits
  `key(context, err, data)` on `AB.Network` when the reply arrives (`:273-278`). ABModel
  uses one-shot keys; the factory uses fixed keys for definition CRUD.
- **Offline queue.** Requests made while offline are saved to Storage key `networkQueue`,
  and their callbacks are kept only in memory (`:35-40`, `338-379`). It emits `queued`,
  polls every 250 ms, and `queueFlush` resends them and emits `queue.synced`
  (`:183-199`, `385-505`).
- **Slow network.** `utils/networkTest.js` (a Web Worker) treats a round trip over 350 ms
  as slow. It uses `navigator.connection.rtt` when the browser has it; otherwise it times
  5 fetches of a google.com pixel every 30 s (`utils/networkTest.js:7-28`). Network then
  emits `networkslow`.

### 3.3 `NetworkRest`

- Retries up to `networkNumRetries`, then fails with `E_TOMANYRETRIES`. Uses a fixed
  6000 ms timeout and retries on "Request timeout" and "disconnected"
  (`resources/NetworkRest.js:198-293`).
- A server packet `{status:"error"}` with `id 5` or `code E_REAUTH` emits `reauth` and
  returns **without settling the promise** (`:315-320`). Other error packets reject with
  `error.response = packet`.
- While offline it queues the request and resolves `{status:"queued"}` (`:369-380`).

### 3.4 `NetworkRestSocket` (the default transport)

- Subscribes to `ab.datacollection.create|update|stale|delete`, `ab.inbox.create|update`
  and `ab.task.userform` (`resources/NetworkRestSocket.js:148-214`). Definition events are
  left to the factory.
- Each event is logged with `console.warn` and de-duplicated for 5 s. Datacollection events
  are CSV-unpacked and normalized. The event is then re-emitted on `AB` (`:40-211`).

### 3.5 Other resources

| Resource | Notes | Evidence |
|---|---|---|
| `Account` | User config plus the tenant-wide `rolesAll()`, `scopes()` and `userList()` from `meta`. `logout()` POSTs `/auth/logout`. `canSwitcheroo()` and `isSystemDesigner()` test hardcoded role uuids (`320ef94a-…`, `6cc04894-…`) | `resources/Account.js:23-95` |
| `Multilingual` | `label(key, altText, values)`: a missing label falls back to the alt text; `{0}` placeholders are filled. Missing labels are POSTed to `/multilingual/label-missing` only after someone runs `AB.Multilingual.enableLabelUpdates()` in the console | `resources/Multilingual.js:22-187` |
| `Storage` | Always `StorageLocal`: `webix.storage.local` with a per-tenant prefix (`noAuth` before login). Every method returns a Promise | `resources/Storage.js:13-33`; `resources/StorageLocal.js:25-70` |
| `Tenant` | `id()`, `setting(key, value)` on `tenant.options`, `textClickToEnter` | `resources/Tenant.js:13-51` |
| `AB.Dialog` | `Alert`, `Confirm`, `ConfirmDelete`, `Message` over Webix | `AppBuilder/_factory_utils/Dialog.js:14-137` |
| Telemetry | Sentry when `SENTRY_DSN` is defined (prod builds); User Timing tables in dev. Sentry `sampleRate` and `tracesSampleRate` are both 0.05. `AB.notify.developer` and `AB.notify.builder` report through it | `utils/performance.js:24-106` |

Storage keys in use: `local_settings` (factory), `networkQueue` (Network),
`portal_work_state` (last app and pages), `abviewgrid_settings` (grid column layouts),
`<tabId>-state` (tab sidebars), and ABDesigner's `workspaceviews`.

---

## 4. Portal UI

### 4.1 Shell

- `ui/ClassUI.js` is the base of every UI class: `ids` built from a base plus keys,
  `CYPRESS_REF` (sets `data-cy`), `attach`, `show`, `hide`, `label` and the warning icons
  (`ui/ClassUI.js:4-165`).
- `ui/ui.js` is a "click to enter" label plus the portal popup. It opens the popup at once
  when `autoenter` is set.
- `ui/portal.js` is a fullscreen popup holding a multiview of Loading, Auth and Work. It
  reacts to `AB.emit("portal.show", key)`, to Account `logout` (it follows
  `data.redirect`), to Network `reauth` (it shows the login screen) and to PortalWork
  `ready` (`ui/portal.js:20-133`).

### 4.2 Work portal (`ui/portal_work.js`)

The layout is a network warning banner, a switcheroo banner, a dark toolbar (hamburger,
app title, root-page buttons, inbox, settings cog, user icon), a sidebar of applications
with the privacy policy link, and the page area (`ui/portal_work.js:20-263`).

`init()` (`:266-753`):

1. Applications: web apps that pass `isAccessibleForRoles(Account.rolesAll())`, plus
   plugin applications that have pages (`:289-295`). See trap 14.
2. User menu: Profile, Logout, one QR entry per mobile app, Switcheroo when allowed, and
   "Connect Mobile App" only when `site.relay` is true (never, now that relay is retired).
3. Network banners, by priority: `no_network`, `no_server` (with a retry button), `slow`.
4. Start page: the deep link `?app=<appId>&page=<pageId>` (both are required; `?app=` alone
   is ignored without a message, checked 2026-10-02), else the saved
   `portal_work_state`, else the first app with an accessible page (`:502-548`).
5. A placeholder for every accessible root page, and one shared `App` from
   `new AB.Class.ABComponent(...)`, which also registers the custom Webix views. The
   default page renders now; the others render the first time they are shown
   (`:606-695`).
6. Settings menu, inbox badge, task window, `emit("ready")`, and a network queue flush.

Selecting an app rebuilds the page buttons and skips pages whose `getUserAccess()` is 0
(`:823-935`). The cog menu shows Access Manager, Translation Tool and Tutorial Manager to
users who are managers (by account or by role) under the current app's
`isAccessManaged`, `isTranslationManaged` and `isTutorialManaged` flags (`:1026-1157`).
ABDesigner only sets those flags ([abdesigner.md](../plugins/abdesigner.md) §9.2).

### 4.3 Page rendering (`ui/ClassUIPage.js`)

- There is one instance per root page. `init(AB, render)` inits every data collection of
  the app, renders the page tree, and shows the root page (`ui/ClassUIPage.js:78-119`).
- `renderPage` calls `page.component(App)` (the access level comes from
  `getUserAccess()`). It builds popup pages as Webix windows (`popupWidth` default 700,
  `popupHeight` default 450, plus a 44 px title bar) and turns pages into multiview
  batches (`:211-364`).
- It re-renders on `ab.interface.update` for its root page, and on
  `ab.datacollection.update` carrying a `datacollectionId` of this app, which means a DC
  definition was saved (`:140-201`).
- `showPage(pageID, viewId)` keeps a page stack; calling it with no id goes back
  (`:414-497`).

### 4.4 Login screens

- `ui/portal_auth.js` implements only `authType "login"`. `passwordless`, `facebook` and
  `google` are empty cases (`ui/portal_auth.js:29-48`).
- Login form: POST `/auth/login`. `EINVALIDLOGIN` shows an inline error,
  `EFAILEDATTEMPTS` hides the button, and success reloads the page
  (`ui/portal_auth_login_form.js:120-293`).
- Reset request: a tenant select (hidden when the current tenant matches) and an email
  field; POST `/auth/login/reset {email, tenant, url}`; it always shows "Email Sent"
  (`ui/portal_auth_login_resetRequest.js:118-238`). The server side and its traps are in
  [api.md](api.md).
- Reset password: at least 8 characters; POST `/auth/password/reset`; then it switches to
  the work portal on any response (`ui/portal_auth_login_resetPassword.js:64-186`).

### 4.5 Other screens

| Module (`ui/`) | What it does | Calls |
|---|---|---|
| `portal_work_inbox.js` (+ `_accordion`, `_taskWindow`) | Process user tasks grouped by app and process, rendered with `formiopreview` | `GET /config/inbox`, `POST /process/inbox/meta`; answers with `PUT /process/inbox/<task.uuid>`; realtime `ab.inbox.create|update` |
| `portal_work_task_user_form.js` | Form.io popup that the server pushes (`ab.task.userform`) | `POST /process/userform/<processID>/<taskID>` |
| `portal_work_user_switcheroo.js` | Act as another user | `POST` or `DELETE /auth/switcheroo…`, then a reload |
| `portal_work_user_profile_window.js` | Image, language, email notifications, password | User model update; `POST /auth/password/reset` |
| `portal_work_user_qr_window.js`, `portal_work_user_mobile_qr.js` | Mobile QR codes | `/relay/user-qr` and `/mobile/qr/<appId>`, both still routed in upstream api_sails (a local removal was dropped on 2026-10-30) |
| `portal_access_level_manager.js` | Per-page, per-role access levels (`page.accessLevels[role]`) | Definition saves |
| `portal_translation_tool.js` | Translate app labels | Language object rows; definition saves |
| `portal_tutorial_manager.js` | Tutorial hints and steps | `hint.save()`, `step.save()` |
| `error_noDefs.js` | Shown to users with no roles; can clear a switcheroo | |

The server side of the inbox and user forms is in [processes.md](processes.md).

---

## 5. Browser platform classes

### 5.1 Factory additions

- `AB.Validation.validator()` returns an `ABValidator` (`addError`, `pass`, `fail`,
  `updateForm`, `updateGrid`). `isFormValidationError` and `isGridValidationError` mark
  fields or cells from a server `E_VALIDATION` error (`AppBuilder/ABFactory.js:44-338`).
- Definition CRUD: `definitionCreate` sends `POST /definition/create`, `definitionUpdate`
  sends `PUT /definition/:id` (a "Not Found" reply falls back to create), and
  `definitionDestroy` sends `DELETE /definition/:id`. Each one also emits the matching
  `ab.abdefinition.*` event locally (`AppBuilder/ABFactory.js:363-431`, `707-831`).
- Utilities: `scriptLoad`, `cssLoad`, `csvToJson`/`jsonToCsv` (Papaparse), lodash
  wrappers, `uuid`, `jobID` (nanoid), `localSettings` (`:892-1094`).

### 5.2 `ABModel`: every data call

The URLs come from core: `/app_builder/model/<objectId>` and
`/app_builder/batch/model/<objectId>` (`AppBuilder/core/ABObjectCore.js:682-692`). They map
to the api_sails `appbuilder/model-*` controllers ([api.md](api.md)).

| Method | HTTP | Notes (`AppBuilder/platform/ABModel.js`) |
|---|---|---|
| `findAll(cond)` | GET with `params: cond` (where, sort, offset, limit, populate) | Rewrites `is_current_date` rules to today's UTC range (`:318-400`) |
| `create(values)` | POST | CSV unpack, `normalizeData` (`:250-288`) |
| `update(id, values)` | PUT `/app_builder/model/<obj>/<id>` | (`:560-600`) |
| `delete(id)` | DELETE | (`:290-316`) |
| `batchCreate({batch})` | POST to the batch URL | (`:204-248`) |
| `batchUpdate({rowIds, values})` | PUT to the batch URL | Resolves `true` (`:607-633`) |
| `logs(options)` | GET the log URL | Row history (`:508-533`) |

**ABModel never emits data collection events itself** (`:61-194`). Other widgets see a
save only when the server's socket broadcast comes back (§7). Writes through
`ABModelQuery` and `ABModelApi` reject: queries and API objects are read-only.

### 5.3 Objects

`ABObject` adds `isValidData(row)`; migrate calls on save and destroy
(`POST`/`DELETE /definition/migrate/object/:id`, with fields at
`/definition/migrate/object/:obj/field/:id`); grid `columnHeaders()`;
`customDisplays()`; and `getDbInfo()`, which calls `GET /definition/info/object/:id`
(`AppBuilder/platform/ABObject.js:167-787`). `ABObjectApi.fetchData()` calls the external
URL **directly from the browser** with the definition's request headers, then creates
rows through the model (`AppBuilder/platform/ABObjectApi.js:9-66`).

### 5.4 `ABDataCollection` (Webix binding)

- `init()` forwards `ab.datacollection.*` events from `AB` to the DC. A child DC is linked
  to its parent's cursor with a `dataFeed` that reloads 20 rows on each parent cursor
  change (`AppBuilder/platform/ABDataCollection.js:77-140`).
- `loadData(start, limit = 20)`. `bind(component)` uses `data.sync(dc)` with `datafetch 20`
  and `datathrottle 500` for datatable, dataview, treetable and kanban, and Webix `bind`
  for other views. Without `loadAll`, it pages on `onDataRequest` (`:142-379`).
- Events that widgets listen to (emitted by core): `changeCursor`, `cursorStale`,
  `cursorSelect`, `collectionEmpty`, `create`, `update`, `delete`, `initializingData`,
  `initializedData`, `loadData` (`AppBuilder/core/ABDataCollectionCore.js`).
- `getData()` sees only the loaded rows (AGENTS.md §7).

### 5.5 Field types in the browser

| Field key | Grid editor | Form component | Detail component |
|---|---|---|---|
| `AutoIndex`, `calculate`, `combined`, `formula` | none | `fieldreadonly` | `detailtext` |
| `boolean` | checkbox template | `checkbox` | `detailcheckbox` |
| `connectObject`, `user` | `multiselect` or `combo` | `connect` | `detailconnect` |
| `date` | `date` (`thaidate` for Thai users) | `datepicker` | `detailtext` |
| `datetime` | `datetime` | `datepicker` | `detailtext` |
| `email`, `string` | `text` | `textbox` (single) | `detailtext` |
| `LongText` | `text` | `textbox` (multiple) | `detailtext` |
| `number` | `number` | `numberbox` | `detailtext` |
| `json` | `text` | `json` | `detailtext` |
| `list` | `multiselect` or `combo` | `selectmultiple` or `selectsingle` | `detailtext` |
| `file` | custom uploader | `fieldcustom` | `detailcustom` |
| `image` | custom uploader | `fieldcustom` | `detailimage` |
| `TextFormula` | none | none | `detailtext` |
| `tree` | template | `formtree` | `detailtree` |

Evidence: the `columnHeader`, `formComponent` and `detailComponent` methods in
`AppBuilder/platform/dataFields/*.js`.

- File and image fields upload to `/file/upload/<obj>/<field>/1`, are served from
  `/file/<id>`, and rotate images with `PUT /image/rotate/<id>?direction=left|right`.
- Connect options (`getOptions`) fetch the linked table with **no limit**, then filter by
  the typed text in the browser (`AppBuilder/platform/dataFields/ABFieldConnect.js:244-440`).
- `mobile-*` keys exist only in the `formComponentMobile` variants, for the PWA
  ([mobile.md](mobile.md)).

### 5.6 View base classes

- `ABView.component()` returns `new ABViewComponent(this)`. `componentList()` hides the
  form, detail, chart and report sub-widgets from the generic "add widget" list
  (`AppBuilder/platform/views/ABView.js:14-68`).
- `ABViewWidget` loads its DC when it is shown.
- `ABViewComponent` is the base of every widget component. It has de-duplicated
  `eventAdd`/`eventsClear`, and `onShow` renders an active hint and loads `notInitial` DCs
  (`AppBuilder/platform/views/viewComponent/ABViewComponent.js:51-196`).
- `ABViewContainerComponent` places children by `position.x/y` into `settings.columns`
  with a `gravity` per column, and initializes children only when `accessLevel > 0`
  (`ABViewContainerComponent.js:39-188`).
- `ABViewManager.newView` asks ClassManager (plugins) first, then the core registry
  (`AppBuilder/platform/ABViewManager.js:10-24`).

### 5.7 Filters and updaters

- **FilterComplex** (`AB.filterComplexNew()`) wraps the Webix `query` widget. It adds
  rules such as `is_current_user`, `contain_current_user`, `same_as_user`,
  `in_data_collection`, `in_query`, `in_query_field` (and their `not_` forms), process
  "context" values and `this_object`. `isValid(row)` evaluates in the browser;
  `getValue()` and `setValue()` use `{glue, rules}` (`AppBuilder/platform/FilterComplex.js`).
  What each operator means on the server is in [server-platform.md](server-platform.md).
- **RowFilter** is the older filter UI, reachable through `AB.rowfilterNew()`. Nothing in
  platform_web creates one directly.
- **RowUpdater** renders "set field X to value" rows (with `ab-current-user` and
  `ab-current-date`). The grid mass update and ABQL use it.

### 5.8 Other classes

- `ABComponent` creates the shared `App` (`AB._App`) and registers the custom Webix views
  once: `activelist`, `countfooter`, `datetimepicker`, `editlist`, `edittree`,
  `editunitlist`, `focusabletemplate`, `formiopreview`, `formiobuilder`, `numbertext`,
  `thaicalendar`, `timepicker`, `tinymce-editor` (lazy), `totalfooter`, `treesuggest`
  (`webix_custom_components/customComponentManager.js:23-56`).
- `ABHint` and `ABStep` render tutorials with the Webix `hint` component.
- `process/` is mostly designer support. `ABProcessTriggerTimer.save()` calls
  `PUT /process/timer/:id/start|stop`.
- `mobile/` lets mobile app definitions load in the web factory. The work portal shows
  only `isWebApp` apps.

---

## 6. Plugin system

### 6.1 Registration

1. `AB.pluginRegister(factory)` calls `factory(AB.pluginAPI())` and registers each class it
   returns, or each element of a returned array (`AppBuilder/core/ABFactoryCore.js:753-776`).
2. `ABClassManager.pluginRegister` files the class by `static getPluginType()`: `object`,
   `properties-object`, `view`, `properties-view` or `editor-view`. Anything else throws.
   The registry key is `static getPluginKey()` (`AppBuilder/platform/ABClassManager.js:148-173`).
3. Lookups: `createObject` (used when `values.plugin_key` is set), `allObjectProperties`,
   `viewClass`, `viewCreate`, `viewAll`, `viewPropertiesAll`, `viewEditorCreate`,
   `viewEditorAll` (`:91-146`). `createField` is commented out, so fields cannot be
   plugins.

### 6.2 What a plugin gets (`getPluginAPI()`)

`ABUIPlugin`, `ABPropertiesObjectPlugin`, `ABObjectPlugin`, `ABModelPlugin`,
`ABViewPlugin`, `ABViewWidgetPlugin`, `ABViewComponentPlugin`, `ABViewPropertiesPlugin`,
`ABViewEditorPlugin`, `ABViewContainer`, `ABViewContainerComponent`,
`ABViewPropertyFilterData`, `ABViewPropertyLinkPage`, `ABViewRuleListFormRecordRules`,
`ABViewRuleListFormSubmitRules`, `ABViewPropertyAddPage`, `ABViewPropertyEditPage`,
`ABFieldImage` and `ABViewPopupSortFields`, plus `AB` and `platform`
(`AppBuilder/platform/ABClassManager.js:60-84`). ABDesigner wraps its own factories to add
`FABViewContainer` and `FABViewContainerEditor` ([abdesigner.md](../plugins/abdesigner.md) §2.2).

### 6.3 Base classes

| Base (`AppBuilder/platform/plugins/`) | Type | Provides |
|---|---|---|
| `ABViewPlugin`, `ABViewWidgetPlugin` | `view` | `toObj()` adds `plugin_key`; `newInstance` through `application.viewNew`. Most widgets use the widget base, which loads its DC when shown |
| `ABViewComponentPlugin` | | Pass-through to `ABViewComponent` |
| `ABObjectPlugin`, `ABModelPlugin` | `object` | `getDbInfo()` built from the fields; `toObj()` adds `plugin_key` |
| `ABUIPlugin`, `ABClassUIPlugin` | | `Current*` getters, `L()` through `labelPlugin`, warnings propagation |
| `ABPropertiesObjectPlugin` | none declared | Builder "new object" form with Save and Cancel |
| `ABViewPropertiesPlugin` | none declared | Designer property form with a `name` field; emits `changed` |
| `ABViewEditorPlugin` | none declared | Designer editor that wraps `view.component()` at access level 2 |

Subclasses of the last three must declare `getPluginType()` themselves (inferred from the
base classes).

### 6.4 The `plugin_` key rule

When core meets a view key it does not know, it builds a generic `ABView` and logs "not
yet defined", unless the key starts with `plugin_`
(`AppBuilder/core/ABViewManagerCore.js:174-220`). That hides the error for a plugin widget
whose code has not loaded yet. The built-in widgets keep their historic keys (`grid`,
`form`, and so on) because the ClassManager lookup runs first. Keys are stored in
definitions: never rename one (AGENTS.md §6).

### 6.5 The NetSuite plugin in `plugins/developer/`

This is a builder UI for NetSuite-backed objects (key `ab-object-netsuite-api`):
credentials, a table picker (`GET /netsuite/metadata`, `/netsuite/table/<t>`), a field
picker, connections, and a data test (`GET /netsuite/dataverify/<table>`). Credentials
default to `ENV:<NAME>` references (`NETSUITE_CONSUMER_KEY`, `NETSUITE_CONSUMER_SECRET`,
`NETSUITE_TOKEN_KEY`, `NETSUITE_TOKEN_SECRET`, `NETSUITE_REALM`, `NETSUITE_BASE_URL`,
`NETSUITE_QUERY_BASE_URL`). They are checked with `GET /env/verify/<key>` (builders only)
and resolved on the server
(`developer/appbuilder/AppBuilder/platform/ABModelApiNetsuite.js:870-871`).

**This copy is not loaded:** `registerLocalPlugins` is empty and its imports are
commented out (`AppBuilder/platform/ABClassManager.js:176-187`). Inferred: the copy in use
is the external `ab_plugin_object_netsuite_api`, installed per tenant as a v1 plugin. The
server half is in [server-platform.md](server-platform.md).

---

## 7. Realtime and data flow

| Event | Consumer |
|---|---|
| `ab.datacollection.create\|update\|stale\|delete` `{objectId, data, jobID}` | `AB`, then every DC's `init()` forwards it. Core inserts, updates or removes rows and emits `create`, `update`, `delete`, `cursorStale` |
| `ab.inbox.create\|update` | The inbox |
| `ab.task.userform` | The task user form popup |
| `ab.abdefinition.create\|update\|delete` | Emitted locally by the factory's definition CRUD and handled by `definitionSync` (`AppBuilder/ABFactory.js:587-630`) |
| `ab.interface.update` | `ClassUIPage` re-render. Nothing in platform_web emits it (grep) |

How a save shows up: grid, dataview, list and kanban are bound with `dc.bind` and follow
the DC on their own; form, detail, text and chart listen to DC events. Because ABModel
never emits locally, a change appears when the server broadcast arrives. Only the grid
also updates its own row right after an inline save. The server half of this path is in
[architecture.md](architecture.md) §5 and [api.md](api.md).

---

## 8. Build

- Entries `app` (`index.js`) and `sailsio` (`init/sailsIo.js`). Output goes to
  `developer/web/assets/[name].[contenthash].js` with `publicPath /assets/`
  (`webpack.common.mjs:12-20`).
- `CleanWebpackPlugin` deletes old `*.js`, `*.map`, `*.gz` and `*.LICENSE.txt` files from
  that shared root (`:35-42`). There are split chunks for pdf.js, Form.io, tinymce, vendor
  and orgchart, and lazy chunks for Webix, the Webix Pro components, the factory, the
  included widgets, the network worker, pdf.js, Form.io and tinymce.
- Dev config: source maps, style-loader, writes `assets/index.html`, and sets
  `SENTRY_DSN=undefined` (`webpack.dev.mjs:16-35`). Prod config: extracted and critical
  CSS, gzip, a hardcoded Sentry DSN, and source map upload when `SENTRY_AUTH_TOKEN` is set
  (`webpack.prod.mjs:24-65`).
- Cache busting: content hashes in file names. nginx serves `/assets/` with a 1-year
  max-age and `/` with `no-cache` (`developer/web/default.conf`).
- The stack does not build it. Run `npm run watch`
  (`webpack-cli --config webpack.dev.mjs --watch`) in `developer/ab_platform_web` by hand,
  and the same in the other UI repos (owner). `npm install` first if
  `node_modules` is missing; `postinstall` applies `patches/webpack-log+3.0.2.patch`.

---

## 9. Tests and CI

- `npm test` runs mocha with jsdom and mock `webix` and `$$` globals (`package.json:9`;
  `test/_setup.js:1-52`). The files are a placeholder `ABField.test.js`, seven
  `ABViewDetail*` tests, three component tests, and `Common.test.js`, which checks every
  `views/viewComponent/ABView*.js` and still special-cases components that have moved to
  plugins. Not run for this page.
- A `lint` script exists, but CI does not run it.
- CI workflows: `unit-tests.yml` (`npm test` on every push); `e2e-tests.yml` (builds
  against ab_service_web, installs with `CruGlobal/ab-install-action@v1`, runs the
  kitchensink Cypress suite); `pr-merge-release.yml`; `lighthouse.yml` (logs in with a test
  account hardcoded in `ciLighthouseAuth.cjs`); `update-core-version.yml`; CodeQL.

---

## 10. Traps

**Verified** means the code says so. **Inferred** means the effect is reasoned from the
code and was not run.

Network and boot:

1. **A 2xx reply carrying `{status:"error"}` hangs forever over the socket.** `salSend`
   calls `JSON.Stringify` (capital S), which throws before `reject`
   (`resources/NetworkRestSocket.js:309`). Verified.
2. **`E_REAUTH` leaves the caller's promise unsettled.** Only the portal reacts, by showing
   the login screen (`resources/NetworkRest.js:315-320`). Verified.
3. **`networkType: "relay"` crashes boot**, and the reconnect and queue-flush block after
   the early `return` in `Network.init` is unreachable (`resources/Network.js:51-89`).
   Verified.
4. **Under `rest`, other widgets never see saves.** Realtime events arrive only over the
   socket transport, and ABModel never emits locally. Inferred.
5. **The offline queue survives a reload, but its callbacks do not**
   (`resources/Network.js:35-40`). Verified.
6. **Boot errors never reach Sentry.** `Bootstrap.error` emits an event named after its
   first argument, and only `"error"` is listened to (`init/Bootstrap.js:56-58`,
   `475-479`). Verified.
7. **The disconnect banner is never installed.** `init/initConnectListerner.js` is
   imported only for side effects, but it just exports an object whose `init()` nobody
   calls. Verified.
8. **Possible Webix race at boot.** The factory is built and initialized before
   `await webixLoading`, and the Pro component globals come from an import nobody awaits
   (`init/Bootstrap.js:189`, `381-382`; `js/webix/webixResources.js:13-38`). Inferred.
9. **`pluginAPI.platform` is undefined in the browser.** The web factory never sets
   `this.platform` (`AppBuilder/core/ABFactoryCore.js:756`). Verified.
10. **Plugin labels are never used.** `labelPlugin` first calls `label(altText, altText)`,
    which always returns the alt text, so `pluginLabels` and the missing-label record are
    never reached (`resources/Multilingual.js:102-116`). ABDesigner and HRTeams therefore
    always show their English source strings. Verified.
11. **Site labels are always built for English.** `tenant_manager.config-site` picks the
    label language with `req.user?.languageCode ?? "en"`
    (`developer/tenant_manager/handlers/config-site.js:117-126`), but a service
    request has no `user` property: ab-utils keeps the user in `req._user` and offers
    `req.languageCode()` (`node_modules/@digiserve/ab-utils/utils/reqService.js:116`, `514-519`).
    api_sails then caches that result per tenant (`SiteController.js:116-147`). Verified
    code. Inferred effect: `window.__AB_Config.labels` is English for every user, whatever
    their language. Fixing only the handler would still leave one cached language per
    tenant.
12. **Console noise.** Every socket event (`console.warn`), every `loadData` call and every
    form render is logged. Verified.
13. **One event name, two meanings.** `ab.datacollection.update` carries row changes from
    the socket, and also "DC definition saved" `{datacollectionId}` from
    `ABDataCollection.save()`. `ClassUIPage` re-renders a whole page only for the second
    (`AppBuilder/platform/ABDataCollection.js:30-32`; `ui/ClassUIPage.js:189-199`).
    Verified.
14. **The client-side app filter filters nothing.** It passes `Account.rolesAll()` (every
    role in the tenant) instead of the user's roles (`ui/portal_work.js:289-295`;
    `resources/Account.js:90-95`). So the apps a user sees depend only on
    `/definition/myapps`. Verified code, inferred effect.

Classes:

15. `AB.isString()` is always false: it calls `_.isString(params)` on the rest-parameter
    array (`AppBuilder/ABFactory.js:1030-1032`). Verified.
16. `ABDataCollection.warningsEval` calls `AB.datacollectionById` (lower-case "d"), which
    does not exist, so evaluating warnings on a linked DC throws
    (`AppBuilder/platform/ABDataCollection.js:577`). Verified.
17. `ABViewContainerComponent.init` tests `!x ?? y`, so removed child views are never
    skipped (`ABViewContainerComponent.js:61-65`). Verified.
18. `ABViewEditorPlugin` reads `view.AB` before its `if (view)` check. Verified.
19. `ABPropertiesObjectPlugin.formIsValid()` never returns true and reads an unset
    `this.$form`, so the base `save()` never emits `save` unless a subclass overrides it.
    Verified.
20. `ABFieldSelectivity` uses a global `Selectivity`, but its import is commented out.
    Where it comes from at runtime is unverified.

Portal and login:

21. After `EFAILEDATTEMPTS` the login button is hidden, then shown again by the request's
    `.catch` (`ui/portal_auth_login_form.js:128-136`, `257-260`). Inferred.
22. The reset screens ignore errors: reset password switches to the portal on any reply,
    and reset request always says "Email Sent". Verified.
23. The mobile QR menu entries remain for the retired relay feature; upstream api_sails still routes their endpoints (known issues S38). Verified.

Build and dependencies:

24. `lodash`, `moment` and `nanoid` are imported but not declared in `package.json`; they
    resolve only as transitive dependencies. `chai` is listed as a runtime dependency.
    Verified.
25. The Lighthouse workflow points at `ciLighthouseAuth.js`; the file is
    `ciLighthouseAuth.cjs`. Verified.
26. Sentry's 5% `sampleRate` also drops 95% of `AB.notify.developer` reports, and the
    slow-network worker calls google.com from every user's browser. Verified.
27. `webpack/index.ejs:33` has the typo `margin:0q`. Verified.

Seen at runtime (2026-10-02, admin tenant, NetSuite HR Update app):

28. **A DC can drop a `loadData()` reply and hang its caller.** `processIncomingData()`
    waits 100 ms before parsing and clears the previous timer first
    (`AppBuilder/core/ABDataCollectionCore.js:2576-2626`). Only the timer callback resolves
    `_pendingLoadDataResolves[jobID]`, so when two replies for one DC land within 100 ms,
    the first job's promise never settles, and neither does `reloadPromise`
    (`:2686-2727`), which waits on it. Observed: "Employee Assigned" and "Employee
    Unassigned" each kept one or two pending job ids and a pending `reloadPromise` on 2 of
    2 page loads, still pending after the page had finished and the tab was in front.
    These are leaked promises: anything that awaits that `loadData()` or `reloadPromise`
    waits forever. Seen doing so on 2026-10-05: the HR Teams chart's "Refreshing" never
    cleared because `waitDCReady()` awaited such a `reloadPromise` (known issue W27,
    [hrteams-widget.md §5](../plugins/hrteams-widget.md#5-testing-notes)). The "Refreshing"
    card seen on 2026-10-02 had a different cause, a background tab. Check in the console:
    `dc._pendingLoadDataResolves` should be empty when idle. HR Teams works around it for
    its own DCs (`Utils.settleDroppedReplies()`): seen settling 3 to 5 dropped loads on
    almost every load of its chart on 2026-10-05.
29. **NetSuite reads are slow enough to trigger resends.** `model-get` on NetSuite objects
    took 3 to 9 s; api_sails logged `timeout waiting for request (appbuilder.model-get),
    retrying 1/5` after about 5 s, and appbuilder answered the resend with
    `preventing duplicate request`, so the extra calls did no harm. Normal for this app.
30. **A failed load leaves the DC "initializing" for good** (known issue W38). `loadData()`
    marks the DC `initializing` before it asks the server; when the request fails, the
    catch in `loadData()` only deletes the job and rejects
    (`AppBuilder/core/ABDataCollectionCore.js:2467-2475`), so `initializedData` never
    comes. Seen 2026-10-05 after NetSuite answered a read with a 503.
31. **Two loads of one DC that wait on the same DC: the first never runs** (known issue W39).
    `waitForDataCollectionToInitialize()` removes the waiting DC's earlier
    `initializedData` listener before adding a new one (`:2179-2187`), so the earlier load
    stops before its request: no pending job, and its `reloadPromise` never settles.

Widget traps are in [widgets.md](widgets.md) §8.

---

## 11. Building definitions from the browser console

ABDesigner calls the browser factory, and the same calls work from the console (or browser
automation) and take the same server path. Use them for bulk experiments, and use the UI
when the experiment is about the UI. Work only in a test app of your own (AGENTS.md §2.0).
Seen working on 2026-10-02 and 2026-10-03.

```js
const app = AB.applications().find((a) => a.label == "<your test app>");
// object: always give tableName (server-platform.md §9 trap 22)
let obj = AB.objectNew({ name: "X", label: "X", primaryColumnName: "uuid",
   createdInAppID: app.id, tableName: "AB_<App>_X" });
obj = await obj.save();            // definition + CREATE TABLE
await app.objectInsert(obj);       // adds it to the app
const f = obj.fieldNew({ key: "string", label: "Name", columnName: "Name",
   settings: { showIcon: 1 } });
await f.save();                    // definition + ALTER TABLE
await obj.model().create({ Name: "row" });   // data
```

- **Connect fields** need the reverse field too. Copy the steps from ABDesigner's
  `ui_work_object_workspace_popupNewDataField.js` (around `:453-597`): create both fields,
  set each one's `settings.linkColumn` to the other's id, save both, then `migrateCreate()`
  both. Then restart the services that had already read the object
  ([server-platform.md §9](server-platform.md#9-traps) trap 21).
- **Widgets:** `page.componentList()` lists the view classes the Add Widget menu shows;
  `C.newInstance(app, page)`, set `settings` and `position`, then `save()`.
- **Processes:** [processes.md §6.1](processes.md#61-building-or-changing-a-process-from-the-browser-console).
- **A mobile app:** `AB.applicationMobileNew()`. Its `save()` resolves with nothing, unlike
  `object.save()`. On a mobile page `componentList()` returns web and mobile view classes
  mixed together; only the `mobile-*` ones belong there. What such an app loads:
  [mobile.md §2](mobile.md#2-boot-sequence).
- `model().delete(id)` resolves with nothing.
- What the calls create in MySQL: [server-platform.md §4.2](server-platform.md#42-field-ddl-platformdatafields)
  (fields) and [§4.3](server-platform.md#43-query-objects-platformabobjectqueryjs) (queries).
- Long scripts, and the hidden tab that automation drives:
  [testing.md §3.3](../testing.md#33-driving-the-browser-with-automation).

---

## Open questions

1. Does `npm test` pass at HEAD, and does `npm run lint` pass? Neither was run.
2. Where does the `Selectivity` global come from in production?
3. Does any server code or plugin emit `ab.interface.update`, or is that path dead?
4. Is the `rest` network type still meant to work, given that realtime updates and
   reconnects depend on the socket?
5. Trap 11: log in as a user whose `languageCode` is `th` and check whether the portal's
   own labels are English.
