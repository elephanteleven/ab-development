# HRTeams widget — `developer/ui/plugins/HRTeams`

The org-chart widget used by the NetSuite HR Update app. It renders teams as an
`<org-chart>` web component, with each team card holding a Leader section and a Member
section of assignment records.

Everything below was verified against the running stack. Anchors are symbol names first,
line numbers second — the line numbers drift.

---

## 1. How it is built and served

| | |
|---|---|
| Entry | `index.js` → `window.__AB_Plugins.push(plugin)` (a **v0** plugin) |
| Dev build | `webpack.dev.js` → emits **straight into** `developer/ui/web/assets/tenant/default/` |
| Bundle | `HRTeams.js` — **no content hash** |
| CSS | `styles/team-widget.css` is inlined into the JS by `style-loader` (`webpack.common.js`). The standalone `team-widget.css` sitting next to the bundle is a stale **prod** artifact and is not what the dev build serves. |
| Labels | `index.js` exports `labels: () => []`, so `this.label("Some English sentence")` returns the sentence unchanged. That is the established pattern here — full English strings are passed to `label()` throughout. |

### 1.1 The cache-busting trap

**This will silently hide every change you make.**

`api_sails` injects the plugin with a query string built from a file on disk
(`SiteController.js:672-680`):

```js
const hrTeamVersion = (await lookupHrTeamVersion()).replace(/[^a-zA-Z0-9 ]/g, "");
pluginListV0.push(`/assets/tenant/default/HRTeams.js?v=${hrTeamVersion}`);
```

`lookupHrTeamVersion()` (`SiteController.js:861`) fetches `http://web:80/version_hrteam`.
That file is written by `webpack-version-file` in **`webpack.prod.js` only** — the dev
`watch` build never writes it.

Consequence: a dev rebuild produces a new `HRTeams.js` behind a **byte-identical URL**, and
the browser serves its cached copy indefinitely. The bundle on the server is correct; nothing
ever requests it.

Symptoms: you edit, webpack says "compiled successfully", `curl` of the asset shows your
change, and the browser shows the old behaviour.

To confirm which side is stale:

```bash
curl -s localhost:23802/version_hrteam                       # the cache-buster
curl -s localhost:23802/config/preloader | tr ',' '\n' | grep -o 'HRTeams.js?v=[^"]*'
curl -s localhost:23802/assets/tenant/default/HRTeams.js | grep -c '<your new string>'
```

and in the browser console:

```js
document.querySelector('script[src*="HRTeams"]').src   // is the ?v= the current one?
```

Workarounds: restart `ui_compiler` (the first build after start does write the file), hard-
refresh, or add a `VersionFile`/`done`-hook plugin to `webpack.dev.js`. Note
`webpack-version-file` writes **only on the first build**, not on watch rebuilds — a plain
copy of the prod plugin fixes the restart case but not the hot-reload case.

### 1.2 Which tenants load it at all

`SiteController.js:666` hard-codes the tenants that get the plugin:

```js
const hrPluginTenants = ["admin", "1ad43361-…", "1729957e-…"];
```

`admin` is in the list "for local testing only", which is why it loads on localhost.

---

## 2. The progress status card

The white rounded card with a spinner that appears centred under the toolbar.

- Queue: `this._progressStatusQueues`, entries of `{key, value}`.
- Add/remove: `_addProgressStatusQueue(key, value)` (~1756) and
  `_removeProgressStatusQueue(key, value)` — the latter is **async** and throttled by
  `PROGRESS_STATUS_DELAY` (500 ms).
- Render: `_refreshProgressStatus()` (~2822). Non-empty queue → `busy()`, build the template,
  `show()`. Empty queue → swap `fa-refresh` for `fa-check-circle`, add `progress-status-done`,
  `hide()`, `ready()`.
- Markup: `_uiProgressStatusTemplate(messages)` (~2801). Shape is
  `.progress-status` › spinner + `.progress-status-messages` (positioning wrapper only) ›
  `.progress-status-title` ("Please wait", unboxed) + **one** `.progress-status-card`
  holding every line as a `.progress-status-message`. One card, not a pill per message —
  `.progress-status-card` carries the background/shadow, `.progress-status-messages` must
  stay transparent or you get a box inside a box.

Keys (`PROGRESS_STATUS_KEY_*`, top of file): `common`, `team`, `principal`, `approval`. For
`common`/`team` the `value` is a message string; for `principal`/`approval` it is the
employee's **email**, used as an identity so concurrent operations dedupe.

Originally the messages were rendered into a Webix **tooltip** only, so they were visible
solely on hover — which read as "a bare spinner with no explanation". They are now rendered
into the card as well.

### 2.1 The Webix clipping trap

The card is `position: absolute` inside an 80px-wide toolbar cell in a **50px-high toolbar**,
and Webix sets `overflow: hidden` on its views. Anything taller than the toolbar is present
in the DOM at full size and **never painted**.

The full chain that must be opened up:

| element | default | needed |
|---|---|---|
| `.progress-status` | visible | — |
| `.webix_template` (cell inner) | hidden | `visible` |
| `.webix_view` (the cell, `css: "progress-status-cell"`) | hidden | `visible` |
| `.webix_scroll_cont` | visible | — |
| **`.webix_toolbar`** (`css: "orgchart-teams-toolbar"`) | **hidden** | **`visible`** |

Ancestors above the toolbar are also `overflow: hidden` but are ~738px tall, so they do not
clip a card of this size.

Diagnosing this class of bug: if `innerText` reads correctly but nothing is on screen, walk
the ancestors and print `getComputedStyle(el).overflow` with each `getBoundingClientRect()`.
A correct-looking DOM plus an empty screen almost always means a short `overflow: hidden`
ancestor.

The message block hangs off the card with `top: 100%; left: 50%; transform: translateX(-50%)`.
That is deliberate: `.progress-status` is already `position: absolute`, so it is the
containing block and those offsets resolve against the spinner rather than some unpredictable
ancestor. Do **not** add `left`/`transform` to `.progress-status` itself — its containing
block is far up the tree and the card will jump.

---

## 3. The "change to Principal" flow

Triggered by double-clicking an assignment record → **Edit Team Assignment** → tick
**Is Principal** → Save. Measured end to end at roughly **40 seconds**.

1. Save handler (~902) calls `_checkIfDataChanged()`; bails if nothing changed.
2. Confirm dialog: *"Caution: Creating New Assignment"* — changing Role type, Job title or
   Principal **closes the current assignment and creates a new one**. Every test run adds a
   record.
3. `_fnBusyRecord($teamRecord)` (~1469) — shows the small per-record spinner and hides the
   edit pencil.
4. `_addProgressStatusQueue(PROGRESS_STATUS_KEY_PRINCIPAL, email)`.
5. `customProcessTasks.run({isChanging: true})` — this is where `needApproval` is decided
   (cross-entity user ⇒ true). Observed ~2.6 s.
6. If `needApproval`: `_addProgressStatusQueue(PROGRESS_STATUS_KEY_APPROVAL, email)`, then
   `await Promise.all([...])` on a `_addUserFormQueue()` promise — which resolves only when
   the **`ab.task.userform` socket event** arrives from the server-side process. This is the
   long wait, and why the card says "around 15 seconds".
7. Queues removed, `_fnReadyRecord()`, `_refreshDataPanel()`.

`_addUserFormQueue()` (~2447) matches the inbound form to the queued request by employee email
via a hard-coded `processFormDataKey`.

---

## 4. `getData()` only searches loaded rows

`ABDataCollection.getData()` searches the rows the collection has **actually loaded**, which
is a page, not the table. Measured live: `DcContainer.list.content` ("All Assignments") held
**941 of 942** rows.

This broke `_checkIfDataChanged()`:

```js
const oldValue = dc.getData((e) => e[objPK] == newValue[objPK])[0];
// oldValue === undefined  ->  TypeError: Cannot read properties of undefined
```

Two ways to land outside the page: a **brand-new record** (no PK yet), or a record **created
earlier in the same session** by a principal change — which is exactly the record you then
edit, so the crash is most reproducible right after a principal change.

The thrown property name is deterministic: `isInactive` is `fields()[0]` of that datasource,
so the loop always dereferences that column first. `reading 'isInactive'` is the signature of
this bug, not a clue about that column.

Guard any `getData()` lookup that assumes a hit. Prefer treating "not found" as *changed* /
*unknown* over crashing or silently dropping the user's edit.

---

## 5. Testing notes

Reaching the widget: pick an entity in the top select, e.g. **World Headquarters** → team
**Innovation Hub**.

- **The chart is enormous and mostly off-screen.** Measured 15672 × 5370 px in a 1707 × 591
  viewport, 65 nodes. An apparently blank canvas usually means you are scrolled away from the
  content, not that it failed to render. Scroll, or:

  ```js
  const oc = document.querySelector("org-chart");
  [...oc.querySelectorAll(".node")]
     .find(n => /innovation hub/i.test(n.querySelector(".title")?.innerText || ""))
     .scrollIntoView({ block: "center", inline: "center" });
  ```

- **"Warning: No Team — No team is assigned to this entity" is unreliable.** It appeared for
  World Headquarters while 65 team nodes were rendered and the TEAMS datacollection held rows
  for that entity. Check the DOM before believing it.

- Driving the entity select by coordinates is fiddly; set it programmatically instead:

  ```js
  const combo = Object.keys(webix.ui.views).map(k => webix.$$(k))
     .find(v => v?.config?.view === "combo" && v.getList && v.getList().count() > 50);
  let t; combo.getList().data.each(i => { if (!t && /^World Headquarters$/.test(i.value)) t = i; });
  combo.setValue(t.id);
  ```

- To observe a transient card, poll rather than screenshot — the visible window is short and
  easy to miss:

  ```js
  setInterval(() => {
     const v = webix.$$(Object.keys(webix.ui.views).find(k => /progressStatus/.test(k)));
     const m = v?.$view.querySelector(".progress-status-messages");
     console.log(v?.isVisible(), m?.innerText);
  }, 100);
  ```

- Changing Principal **writes data** — a new assignment record per run. Do not use a real
  person as a scratch fixture without saying so.
