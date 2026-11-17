# Testing

What tests exist, how to run them, and what they really check (§1, §2), and how to check
things by hand in the browser (§3). Verified on 2026-10-02.
For the per-change validation checklist (lint baselines, startup smoke test) see
AGENTS.md §9; this page explains the harnesses behind it.

---

## 1. Overview

| Layer | Where | Runs with | State |
|---|---|---|---|
| e2e (Cypress) | `test/e2e/` in this repo | `npm run test:e2e*` | 3 specs; needs setup (§2.5) |
| ab-utils unit | `test/` in the ab-utils repo (not part of this workspace; clone `CruGlobal/ab-utils` to run it) | `npm test` (mocha, no lint) | 134 passing, 1 pending (2026-09-29) |
| appbuilder unit | `developer/appbuilder/test/unit/**/*.test.js` | `npm test` | Process-trigger queue/manager tests; the old `handler.js` stub is not in the glob |
| platform_service | `test/platform/ABProcess.test.js` | `npm test` (mocha) | Likely cannot pass (CommonJS proxyquire against ESM; inferred) |
| Other services | `test/unit/handler.js` stubs | various | Import a missing `src/handler.js` (would fail); tenant_manager's `npm test` is lint with `--fix` |
| platform_web, ABDesigner, HRTeams, platform_pwa | their own `test/` / CI | CI workflows | See [frontend.md](core/frontend.md), [abdesigner.md](plugins/abdesigner.md) |

**Lint writes to files** in 12 of the 13 repos that have a lint script (`--fix`); api_sails'
lint is read-only but already fails at HEAD. Compare per-file counts against HEAD instead
(AGENTS.md §9).

Upstream CI (e.g. platform_service, platform_pwa workflows) installs a full stack with
`CruGlobal/ab-install-action@v1`, checks out app suites such as `CruGlobal/kitchensink_app`
into `test/e2e/cypress/e2e/`, and runs `test:e2e:ab-runtime`.

---

## 2. The Cypress harness (`test/e2e/`)

Cypress 13.17.0.

### 2.1 Configs

| File | Settings |
|---|---|
| `cypress.config.mjs` | `defaultCommandTimeout` 12000, `responseTimeout` 60000, no video, **no `baseUrl`** |
| `cypress.ab_runtime.mjs` | Excludes `cypress/e2e/plugins/**` |
| `cypress.app.mjs` | Also excludes `**/test_cases/*` |
| `cypress.plugin.ab_designer.mjs` | `specPattern cypress/e2e/plugins/**/*.js`: **matches 0 specs** (no `plugins/` folder) |

`CYPRESS_X` env vars become `Cypress.env("X")`; `CYPRESS_BASE_URL` becomes `baseUrl`,
which is the **only** source of it (and `.env` defaults it to port 8080 while the app is on
`WEB_PORT`, 23802 here). `cypress/plugins/index.js` and `support/index.js` are pre-Cypress-10
leftovers; only `support/e2e.js` loads.

### 2.2 Specs (`test/e2e/cypress/e2e/`)

| Spec | What it does |
|---|---|
| `0001_portal_auth_login.cy.js` | Login page: valid login shows the sidebar; logout; bad email shows an error. Reset password: request a reset, read the token from the SITE_TOKEN object (`ModelFind`), open `/auth/password/reset?a=<token>`, set `newpassword`, log in with it. ("Loading" suite is skipped) |
| `0002_portal_work.cy.js` | Adds admin to the Switcheroo role, deletes the default-role process definition, creates user `test`; opens the "Site Administration" app (title, 1 page, inbox and user icons, `window.AB`); switcheroo to `test` and back |
| `0003_import_cars.cy.js` | `POST /test/import {file:"imports/test_import/app_test.json"}`, then expects app "CARS" with 2 pages. **`app_test.json` was never committed**, so this spec fails |

**The specs change data:** 0001 sets the admin password to `newpassword`; 0002 deletes a
process definition and creates a user. Against the dev stack, `cy.ResetDB()` silently
resets nothing (below), so those changes stick (inferred).

### 2.3 Support commands (`support/commands.js`)

| Command | What it does |
|---|---|
| `AuthLogin` | `cy.session("admin")` + `POST /auth/login {tenant, email, password}` |
| `ResetDB` | `cy.exec("npm run test:reset <STACK>", {failOnNonZeroExit:false})`, then `POST /test/reset {tenant}` |
| `ModelCreate/Delete/Find/Update` | `window.AB.objectByID(id).model()` CRUD from the browser |
| `DCSetCursor`, `GridScroll` | Drive a data collection / Webix grid |
| `RunSQL` | Concatenate `cypress/e2e/<folder>/test_setup/sql/*`, copy into the `<STACK>-db` container, run against `appbuilder-admin` |
| `TestLog`, `VersionCheck` | `POST /testlog`, `GET /versioncheck` |

`support/e2e.js` stubs every `sentry.io` request and posts each test's title to `/testlog`.

### 2.4 Imports and reset

- api_sails mounts `test/e2e/cypress/e2e` at `/app/imports`; only `/test/import` reads it.
  `.gitignore` keeps only top-level specs, `plugins/` and `test_import/` there.
- `test-reset.sh` finds the `${STACKNAME}-test-db` container and runs `reset.sh` in it, then
  runs `digiserve/ab-migration-manager:master` on the test network (ignoring
  `AB_MIGRATION_MANAGER_VERSION`; passes the whole `.env`). If the container is missing it
  prints `docker ps` and **exits 0**.
- `test/setup/reset.sh` replays `02-tenant_manager.sql` and `03-site_tables.sql`, which both
  start with `USE appbuilder-admin`, so for any tenant other than admin the reset hits the
  admin DB (inferred). It also expects `test/setup/reset-user.sql`, which is gitignored and
  becomes an empty directory on a fresh checkout (AGENTS.md §7).

### 2.5 Running it

1. `CYPRESS_BASE_URL=http://localhost:<WEB_PORT>`; `CYPRESS_STACK` / `STACKNAME` pointing at
   the test project; a real `reset-user.sql` before the db container first starts.
2. The test stack (`npm run start:test`) reuses the dev stack's fixed host ports, so it
   conflicts with a running dev stack (inferred). **House rule: the lifecycle is
   `npm start` / `npm stop` only, so confirm with the repo owner before using the test
   scripts.**
3. `npm run test:e2e:ab-runtime` (or `test:e2e`, `test:e2e:app`, `cypress:open`).

---

## 3. Testing by hand in the browser

For checking things in the running stack from a browser, by hand or with browser
automation. Seen on 2026-10-02 and 2026-10-03.

### 3.1 Acting as another user (switcheroo)

`POST /auth/switcheroo/<user uuid>` (the caller needs the Switcheroo role) answers
`{"switcherooID": …}`; after a reload the portal runs as that user, with
`window.__AB_Config_User_Real` holding the real one. `DELETE /auth/switcheroo` and a reload
switch back. The switch is stored in the session, so it changes **every tab** of that
browser profile, not just one ([api.md §5](core/api.md#5-authentication)).

- **Check the state with `GET /config/preloader`**: it sets
  `window.__AB_Config_User_Real = {…}` only while a switch is active. `GET /config/user`
  keeps showing the real user, so it cannot tell you.
- **Switch before the portal loads.** Opening any portal page as a builder or admin
  re-saves two NetSuite HR Update definitions (W24). Open a JSON URL on the same origin
  first (for example `/config/site`), call the switcheroo endpoint with `fetch()` from
  there, then open `/`.
- **Role changes made straight in the DB do not reach a switched user**: api_sails caches
  users until appbuilder sends `api_sails.user-cache-stale`, which a model write on the user
  does. Change roles with `PUT /app_builder/model/<SITE_USER object id>/<user uuid>` and a
  body like `{"SITE_ROLE": [<role uuids>]}`.
- Logging out does not end a switch ([api.md §9](core/api.md#9-security-findings)).
- **Switch only while no other tab of the browser profile is busy.** Requests still
  running in another tab can undo the switch (R27): on 2026-10-04, with a chart loading
  as hr.mock.pxy in a second tab, a switch to hr.mock.pxr answered 200, yet every request
  after it still ran as hr.mock.pxy. Close the other tab, switch again, and check the user
  (`AB.Account.username()` in the portal, or the api_sails log).
- **To go from one test user to another, switch back first** (`DELETE /auth/switcheroo`):
  a `POST /auth/switcheroo/<uuid>` sent while switched answers 403, because the switched
  user has no Switcheroo role (seen 2026-10-04).
- The test users in the local tenant have no password and are used only this way
  ([site-administration.md §4](core/site-administration.md#4-testing-note)).

### 3.2 REST calls from the browser console

Useful when the portal must not load (§3.1), or when the page's factory is not the user you
need. Run them with `fetch()` from any page on `localhost:$WEB_PORT`; they use the current
session, and its switch.

| Need | Call |
|---|---|
| Read rows | `GET /app_builder/model/<object id>?where=<JSON>&limit=1&skipPack=true`, with `where` a JSON condition such as `{"glue":"and","rules":[{"key":"id","rule":"equals","value":1903}]}`. Without `skipPack=true` the rows come back packed (`csv_packed`) |
| Create a row | `POST /app_builder/model/<object id>` with a JSON body. Unlike the browser model, this fills **no field defaults**: `ABModel.create()` in the portal sets each missing field's default before posting (`developer/ab_platform_web/AppBuilder/platform/ABModel.js:253-258`). A user made this way on 2026-10-05 got `sendEmailNotifications` NULL where the portal gives 0, so send every default you need. Translated fields can be sent plain (`{"Name": "…"}`): the server moves them into `translations` |
| Update a row | `PUT /app_builder/model/<object id>/<row id>` with a JSON body of the changed fields |
| Answer an inbox form | `PUT /process/inbox/<form uuid>` with `{"response": "approve"}` (or `"reject"`), which is what the inbox UI sends ([processes.md §3.10](core/processes.md#310-a-run-seen-end-to-end-2026-10-02)) |
| Switch user | `POST /auth/switcheroo/<user uuid>`, `DELETE /auth/switcheroo` (§3.1) |

Dates arrive in two shapes for the same day, from NetSuite objects and from local date
fields alike (seen 2026-10-04 on a local one, [processes.md §7.2](core/processes.md#72-expiry-checks-in-an-approval-tested-in-the-sandbox-2026-10-04)): the browser model gives
local midnight in UTC (`2026-10-02T17:00:00.000Z` for 2026-10-03 at UTC+7), while the
unpacked REST read above gave `2026-10-03T00:00:00.000Z`. Compare calendar days, not
strings, and send dates as `"YYYY-MM-DD"` (W23).

### 3.3 Driving the browser with automation

- The tab that browser automation drives is usually **hidden**
  (`document.visibilityState` is `hidden`). The DOM still updates, but screenshots can be
  stale or time out, and anything that waits for `requestAnimationFrame` pauses
  ([hrteams-widget.md §5](plugins/hrteams-widget.md#5-testing-notes)). Read the DOM, the
  factory (`AB.…`) or the database instead, or ask the owner to bring the tab to the front.
- Start long console scripts without `await` and collect their results in a `window.__x`
  array; the automation's 45 s evaluate timeout otherwise cuts them off. Keep wait loops
  short too: on 2026-10-04 loops of 35 to 60 s timed out in a hidden tab, whose timers the
  browser slows down (inferred), so poll with several short calls.
- A hidden tab may not draw at all until it is captured: on 2026-10-04 the HR Teams chart
  stayed at 0 cards until a screenshot was taken, then drew at once. Take a screenshot
  before reading the DOM of something that should have appeared.
- Seen on 2026-10-05, after the tab had been hidden for a few minutes: a 15 s poll took
  44 s (timers slowed further), a screenshot timed out after 30 s ("renderer may be
  frozen"), and a click on the HR Teams "Staff Assignment" button did nothing. What worked:
  right after `navigate`, replace `window.requestAnimationFrame` with
  `(cb) => setTimeout(() => cb(performance.now()), 16)` so a page load does not wait for
  frames the hidden tab never draws, and click Webix buttons by dispatching the event on
  the element that carries the handler's class, e.g.
  `document.querySelector(".data-panel-button").dispatchEvent(new MouseEvent("click", {bubbles: true}))`.
  Done is "the card is gone **and** the chart has nodes": between `init()` and `refresh()`
  the card is gone for a moment while nothing is drawn yet.
- The console tool re-lists earlier messages with new times when it reattaches, so old
  warnings seem to come back. Check the api_sails log before taking that for new activity.
- **Hard reload:** the automation's `key` action with `ctrl+shift+r` reloads the tab
  without the cache. Checked on 2026-10-16: the navigation type was `reload`, and every
  bundle came from the network again (`performance.getEntriesByType("resource")` showed a
  `transferSize` of 1.3 MB for `app.*.js` and 352 KB for `HRTeams.js`, against 0 on a
  plain load). One reload plus a check that polls the card fits in about 10 s, so a
  `browser_batch` can hold five of them. Make the check throw when the card is still up
  after 40 s: the batch then stops and leaves the stuck page for a look.
- **Many reloads in one page (2026-10-16):** open a JSON URL such as `/config/site`,
  replace its body with a full-size `<iframe>`, and drive the portal inside it from a
  script in the outer page. That script survives the reloads and has no tool time limit,
  and it can read the frame's window, including `webpackChunkhrteamwidget`. To load as
  admin without the W24 re-saves, poll the frame every 2 ms and wrap its
  `io.socket.request` so that `put` calls to `/definition/` answer at once with a 403:
  the portal sends API calls through `io.socket.request` (`resources/NetworkRestSocket.js`).
  On 2026-10-16 that blocked the four PUTs of each of 45 admin loads: api_sails logged no
  `PUT /definition` in that half hour, and definition_manager no update. The same frame
  works on staging (`https://ldhr-test.hrupdate.org/config/site`, which sends no
  frame-blocking header), so a builder account can be tested there without W24 rewriting
  the staging definitions. A user switch made in another tab during the run reaches the
  frame too: on 2026-10-16 the last of 8 staging loads ran as the user the owner had just
  switched to. With a switched user the frame still sent the four `PUT /definition` on
  each load (seen with a non-builder user, whose session had no `ABDesigner.js` in
  `/config/preloader`), so keep the block on.
- **A save that stays pending, with nothing written (2026-11-03):** in the same wrapper,
  keep every non-GET call under `/app_builder/` with its callback instead of sending it,
  and answer non-GET calls under `/definition/` and `/process/` with a 403, except
  `POST /definition/register` and `POST /process/inbox/register`. The widget then waits as
  for a slow NetSuite write. To end a held call, run its callback with
  `({status: "error", message: "…"}, {statusCode: 409, body: '{"status":"error","message":"…"}'})`:
  `salSend()` rejects and the widget takes its failure path (a 4xx also emits
  `error.badRequest`, which nothing listens to). To end it as a success instead, run the
  callback with `({status: "success", data: record}, {statusCode: 200, body: JSON.stringify({status: "success", data: record})})`,
  where `record` is what the server would send back: the record's old values (a card's
  `data-source`), then the values sent, then the id (from the path of an update, made up
  for a create). `salSend()` resolves with `data`, and the widget draws the card as saved
  (2026-11-03 and 2026-11-05). On 2026-11-03 api_sails then logged only
  `GET` lines, no process ran and no `history` row was written. A failed save does not undo
  what the widget already changed on screen (a moved card stays moved), so reload the
  frame after such a test. The frame's `window` object stays the same across its reloads,
  so mark each new page (for example `w.__rafPatched = true`) to patch its
  `requestAnimationFrame` again. To reach the live widget instance, wrap a method on its
  prototype (as in "Trying a change ... without a build" below) so that it stores `this`
  when the widget calls it.
- **Catching Webix messages (2026-11-05):** `webix.message` is a getter, so a wrapper
  assigned to it is ignored without an error, and counting `.webix_message` elements
  misleads, because earlier messages can still be on screen. Watch the frame's
  `document.body` with a `MutationObserver` for added `.webix_message` nodes instead.
- The automation tool hides a returned value that looks like cookie or query-string data
  (`[BLOCKED: Cookie/query string data]`, seen on 2026-11-05 with Webix templates in the
  result). Replace `=`, `&` and `?` in the text before returning it.
- **After a rebuild, make the frame load the new bundle:** a frame reload takes the bundle
  from the browser cache, so first run
  `fetch('/assets/tenant/default/HRTeams.js?v=ecs', {cache: 'reload'})` in the outer page.
  On 2026-10-16 the frame then ran the new file (its `performance` entry for `HRTeams.js`
  had the new file's decoded size).
- **Trying a change to the HR Teams widget without a build (2026-10-16):** walk
  `AB.applications()` and each page's `pages()` and `views()` to the view whose `key` is
  `plugin_hr_teams`, call its `component()` for a throwaway instance (the constructor only
  stores references and makes ids), and replace the method on
  `Object.getPrototypeOf(thatInstance)`. The widget on the page shares that prototype, so
  its next call runs the new code; put the old method back, or reload, to undo it. Used to
  try the W42 fix.
- Building test definitions from the console:
  [frontend.md §11](core/frontend.md#11-building-definitions-from-the-browser-console).
