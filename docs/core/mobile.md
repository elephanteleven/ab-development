# Mobile PWA (platform_pwa) and mobile views

A builder can create an application with `appType: "mobile"`. It runs on phones as a
Framework7 progressive web app served by api_sails. Code: `developer/pwa`
(branch `master`, v1.1.2) and the mobile classes in `developer/appbuilder/AppBuilder/core/mobile/`.

Verified on 2026-10-02 against platform_pwa `530e3a0` (2026-03-16). Its nested
`src/js/AppBuilder/core` is pinned to class_core `d52cad32`, which is only on
`origin/importOnly`, **not on `v2`**, so the PWA runs an older core than the web portal.
Paths are relative to `developer/pwa/` unless they start with `developer/`.

---

## 1. What it is

A Framework7 9 single-view app (Framework7's own `$jsx`, not React), created with the F7
CLI (`framework7.json`). It renders **one** AppBuilder application (`AB.applications()[0]`).
Dependencies include framework7, dom7, swiper, lodash, moment, nanoid, papaparse, semver,
uuid, eventemitter2, atomicjs; `src/js/sails.io.js` and `src/js/atomic.js` are vendored.

---

## 2. Boot sequence

1. The phone opens `GET /mobile/app/<tenantID>/<appID>` (noAuth). api_sails renders
   `views/mobile_pwa.ejs` with `appID` and the tenant from `authTenant` (the URL's
   `:tenantID` segment is not read). The shell creates `window.__AB_preload` and
   `window.__ab_config`, sets `<div id="app" appbuilder-tenant=...>`, links the favicon and
   manifest, and loads `/mobile/preloader/<tenantID>/<appID>`.
2. The preloader (`views/pwa_preloader.ejs`) loads in parallel: the bundles
   `/assets/mobile/mobile_runtime.js`, `mobile_vendors.js`, `mobile_app.js`;
   `/mobile/definitions/<appID>?v=` (into `window.__ab_definitions`);
   `/mobile/config/settings|labels|languages|user|meta|tenants?v=` (into
   `window.__ab_config.*`). Cache-busters come from
   `definition_manager.definitions-mobile-check-update` (per-process timestamps refreshed on
   definition changes) and `user.updated_at`.
3. `src/js/AppBuilder/ABFactory.js` awaits `__AB_preload`, builds
   `new ABFactory(definitions)`, applies `__ab_config`, and `AB.init()` starts Account,
   Multilingual, Network, Tenant and Storage and subscribes to `ab.abdefinition.*` for live
   definition sync. `platform = "pwa"`.
4. `src/js/app.js` creates the Framework7 app with `routes(AB)` and `store(AB, version)`
   (version hardcoded `"0.0.9"`). A service worker is registered only in production builds
   (and the stack never builds that path).

All `/mobile/config/*` and `/mobile/definitions` responses send a 1-year `Cache-Control`;
only the `?v=` values bust them. Endpoint table: [api.md §4](api.md#mobile-pwa).

Seen on 2026-10-02 with a one-page test app (a `mobile-page` holding a `mobile-list` of an
object's names, built from the console as in
[frontend.md §11](frontend.md#11-building-definitions-from-the-browser-console)): opening
`/mobile/app/admin/<app id>` loaded the preloader, the three `mobile_*.js` bundles, then
`/mobile/definitions/<app id>?v=<timestamp>` (an export object with `abVersion`,
`filename`, `date`, `definitions`, `files`) and the `/mobile/config/*` scripts. With
`networkType: "socket"` it stopped there (trap 9); switched to `rest`, it showed the left
panel (app title, page list, Log out, v1.0.0) and a Sign In form (trap 10).

---

## 3. Authentication and tenant

REST calls send `tenant-token`, an optional `Authorization`, and the Sails session cookie.
With no user config, `Account.init()` redirects to `/auth/login` (saving the URL in
`sessionStorage.refererUrlPWA`; the portal sends the browser back after login) unless the
tenant's `authType` is `"login"`, in which case the built-in login screen posts
`{email, password}` to `/auth/login`. The login screen also opens on a network `reauth`.

---

## 4. Routing: how a definition becomes screens

- Fixed routes `/`, `/form`, `/list`, `/inbox` (unauthenticated users get only these).
  `/form` and `/list` are "temporary reference pages" bound to a hardcoded DC.
- Root pages with `menuType == "tab"` build one `/tabs/` route with a bottom tab bar;
  every `menuType == "menu"` page becomes its own route; a NotFound route comes last.
- `/` shows `Application.pageDefault` or the first page; `?route=<route>` picks the start.
- `ABApplicationMobile.pageNew()` builds `ABMobilePage`, whose `routeComponent()` inits each
  view's data collection, re-renders from the Framework7 store, loads data on `pageInit`,
  then calls each view's `html($h)`.

---

## 5. Data, network, offline

- **Data collections:** `ABMobileDC` stands in for the Webix DataCollection and keeps rows
  in the Framework7 store (`$state[dc.id]`). Linked and tree DCs are not supported
  (`dc.define` / `webix.TreeCollection` missing; inferred TypeErrors).
- **Network:** `networkType` from the mobile app settings: `socket` uses
  `NetworkRestSocket` (forwards `ab.datacollection.*`, `ab.inbox.*`), anything else
  `NetworkRest` (atomicjs XHR, 6 s timeout, 3 retries). **`relay` crashes boot**
  (`_network` stays null), yet ABDesigner still offers it. Without sockets the model emits
  the realtime events itself.
- **Offline:** one unencrypted JSON blob per tenant in `localStorage` (`local_settings` and
  a request queue). Offline REST calls are queued (`{status:"queued"}`) and replayed by
  `queueFlush()`, but the reconnect/online flush handlers are never registered (inferred).
  Record data is not cached.

---

## 6. Build

Run `npm run watch` in `developer/pwa` (development mode) to build it into
`developer/web/assets/mobile/mobile_{app,vendors,runtime}.js`, CSS inlined; the stack
does not build it.
Every webpack script uses development mode (`webpack.prod.js` is referenced by nothing).
The Vite scripts (`dev`, `build_main`) and `update.sh` (a personal rsync deploy) are stale:
the Vite entry `src/index.html` was deleted in 2023. `proxy-server.js` / `proxy.sh` are a
CORS proxy for running the PWA against a remote AppBuilder. There is no lint script.

---

## 7. Mobile view types (class_core `mobile/`)

`ABViewManagerMobileCore` registers 21 classes by key; unknown keys fall back to
`mobile-view` (which has no `html()`, so the page breaks); `detailselectivity` is renamed to
`detailconnect`.

| Key | Purpose and main settings | PWA rendering |
|---|---|---|
| `mobile-page` | Screen: `type` (page/popup/reportPage), `defaultPage`, `hideTitle`, `hideTabs`; `route`, `menuType` (menu/tab), sub `pageIDs` | Framework7 route |
| `mobile-view` | Base / fallback | none |
| `mobile-custom` | Builder code widget (`initCode`, `htmlCode`, `datacollections`) | `new Function` |
| `mobile-form` | Form: `dataviewID`, label settings, `clearOnLoad`, `clearOnSave`, `displayRules`, `recordRules`, `submitRules` | Save flow |
| `mobile-button` | Save/Cancel/Reset buttons | Save works; Cancel and Reset are TODO |
| `mobile-checkbox` | | Toggle (1/0) |
| `mobile-connect` | Connected-record picker: `formView`, `filterConditions`, `sortFields` | Single or multi select by `linkType` |
| `mobile-date`, `mobile-datetime` | `timepicker` | F7 calendar (datetime `valueLoad` TODO) |
| `mobile-email` | | `type=email` |
| `mobile-file`, `mobile-image` | | Upload in `valuePrepare()` (image: `accept=image/*`) |
| `mobile-formula`, `mobile-fieldreadonly` | | Read-only inputs |
| `mobile-numberbox` | `isStepper` (unused) | `type=number` |
| `mobile-selectmultiple`, `mobile-selectsingle` | `type` richselect/radio | F7 smart-select / native select (single `valueLoad` TODO) |
| `mobile-textbox` | `type` single/multiple/rich, `placeholder` | input/textarea (`rich` not implemented) |
| `mobile-label` | `text`, `format`, `alignment` | `<div>` |
| `mobile-list` | `dataviewID`, `field`, `linkPageDetail`, `linkPageAdd` | Swipe-to-delete, infinite scroll |
| `mobile-timeline` | List plus `dateField`, `templateItem` | Groups by date; the template is `eval`ed with record values (XSS risk, inferred) |

---

## 8. Traps

1. **`/mobile/version/:ID` is dead:** it calls `definition_manager.mobile-config`, deleted
   in `84a8d59` (2025-02-14). The PWA calls it on every `visibilitychange`, the request times
   out, and the update dialog never appears (inferred).
2. Bundles are unhashed (`mobile_[name].js`), loaded without `?v=`, and nginx caches
   `/assets/` for a year, so phones can run an old build (inferred).
3. Labels, languages, meta and tenants reuse the definitions timestamp as their
   cache-buster, so tenant/role changes appear only after a definition changes (inferred).
4. `networkType: "relay"` crashes boot; the offline queue never auto-flushes.
5. `AB.notify` only logs to the console: PWA errors never leave the device.
6. "Log out" never calls `/auth/logout`; login navigates to the demo `/list` page.
7. `/mobile/definitions` returns the full app export plus system objects to any logged-in
   tenant user (no role filter; inferred).
8. The nested core tracks `importOnly`, not `v2` (it pins `d52cad3`).
9. **`networkType: "socket"` also breaks boot** (seen 2026-10-02): the PWA logs
   `TODO: install socket.io client for sails updates.` and then
   `ReferenceError: io is not defined` in `NetworkRestSocket`, so nothing loads. A mobile
   app must use `rest` today. The ABDesigner mobile form offers `rest`, `socket` and
   `relay`; only `rest` works (§2).
10. **The PWA asks for its own sign-in** (E-mail and Password) even when the browser
    already has a portal session (seen 2026-10-02, inferred cause: the PWA authenticates
    separately).

