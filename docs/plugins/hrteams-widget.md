# HRTeams widget: `developer/plugins/HRTeams`

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
| Dev build | `webpack.dev.js` → emits **straight into** `developer/web/assets/tenant/default/`. The plugin's `version` comes from `npm_package_version` (`webpack.common.js`): the `package.json` version when built through npm or `npx webpack-cli`, `undefined` with `node_modules/.bin/webpack-cli` alone, so two builds of one commit can differ by one byte (seen 2026-11-03) |
| Production build | `npm run build:update` (`webpack.prod.js`) → `HRTeams/build/`: `HRTeams.js` and the chunks `HR556.js`, `HR702.js`, `HR709.js`, each with `.gz`, `.map` and `.map.gz`, plus `version_hrteam` (`hrteamwidget@<version>` and the build date). `build.sh` copies `build/*` into `developer/web/assets/tenant/default/` and deletes `build/`. The result goes to web `master` by hand: "Update the HRTeam plugin" for 1.0.22 (2026-10-16), `4cdfc151` "Update HRTeams plugin" for 1.0.23 (2026-11-03, at the owner's request, from a separate worktree of web so its checkout stayed on `develop`) and `4c30b649` "Update HRTeams plugin" for 1.0.25 (2026-11-04, the same way). Each time only `HRTeams.js*` and `version_hrteam` changed; the chunks came out byte-identical |
| Bundle | `HRTeams.js` — **no content hash** |
| CSS | `styles/team-widget.css` is inlined into the JS by `style-loader` (`webpack.common.js`). The standalone `team-widget.css` sitting next to the bundle is a stale **prod** artifact and is not what the dev build serves. |
| Labels | `index.js` exports `labels: () => []`, so `this.label("Some English sentence")` returns the sentence unchanged. That is the established pattern here — full English strings are passed to `label()` throughout. |

**Releases.** Merging a PR into HR Teams `master` starts its "PR Merged" workflow: e2e
tests, a version commit ("Update version 1.0.23", by github-actions), a release tag, and a
`web_new_version` event to the web repo (`CruGlobal/ab_service_web`). That event starts
the web run "Update plugin_HRTeams to <version>" ("Update Platform Web",
`call-update-build-release.yml`), which builds the plugin for web `master` and `develop`.
Its `master` part has failed on every release so far (1.0.19 to 1.0.25, in the e2e job's
"Checkout Repo" step), which is why web `master` is updated by hand (table above). Its
`develop` part merged 1.0.22 and 1.0.24 into web `develop` (1.0.24 as `6bd8f5b8`, which
the workflow names "Update platform_web to 1.0.24" whatever the plugin, then the version
commit `a9e4e2f7`); for 1.0.23 and 1.0.25 its e2e failed ("Run Cypress Tests") and it
opened PR #129 and PR #130 into `develop` instead, whose checks wait for approval. On
2026-11-03 the plugin's run took 8.5 min (05:05:00 to 05:13:30 UTC) and the web run 15 min
(05:13:23 to 05:28:14).

**Merge one PR at a time.** Two chains running together can get in each other's way (read
in the workflows, not seen): the version bump has no concurrency guard, so two "PR Merged"
runs can race for the same version, and two web runs branch from the same web `develop`
and both try to merge into it. On 2026-11-04 PR #53 was merged at 02:58:53 UTC (1.0.24
tagged at 03:07, its web run done at 03:25) and PR #54 only then, at 03:25:54 (1.0.25 at
03:34, its web run done at 03:49); web `master` and `staging` then got the 1.0.25 build
once.

A PR into `master` runs "Check Release Labels" (exactly one of `major`, `minor`, `patch`
or `skip-release`, read from the event's label list, which is also what "PR Merged" uses
for the version bump) and "Merging Rules" (the same e2e tests, against web `develop` and
`master`). `gh pr create --label` adds the labels just after the PR opens, so the label
check for the `opened` event fails and the bot comments "Please add one release label";
the checks for the `labeled` events pass (PR #52 to #54). Re-running the failed one does
not help, since a re-run reads the same event. When that failed check ends last,
`gh pr checks` lists it as failing (PR #54), while GitHub still gives the PR the merge state
`CLEAN`. The e2e check can fail before any test runs: on PR #54's first run (2026-11-03),
Cypress's `before all` hook got 400 "Request timed out." from `POST /test/reset`, and the
other matrix job was cancelled; re-running the failed jobs passed both (6.5 and 7 min).

### 1.1 The cache-busting trap

**This will silently hide every change you make.**

`api_sails` injects the plugin with a version query string
(`developer/api_sails/api/controllers/SiteController.js:678-680`):

```js
const hrTeamVersion = (await lookupHrTeamVersion()).replace(/[^a-zA-Z0-9 ]/g, "");
pluginListV0.push(`/assets/tenant/default/HRTeams.js?v=${hrTeamVersion}`);
```

On api_sails `master`, **`lookupHrTeamVersion()` returns the constant `"ecs"`**
(`SiteController.js:868-869`, since commit `162b3f6`, 2025-09-12, "remove http calls to
web"); `lookupWebVersion()` does the same for ABDesigner (`:852-853`). Older branches
fetched `http://web:80/version_hrteam` instead, a file written only by `webpack.prod.js`.
Either way the URL is effectively fixed, and nginx's `location /assets/tenant` sends no
`Cache-Control` header (`developer/web/default.conf:68-71`), so the browser applies
heuristic caching.

Consequence: a dev rebuild produces a new `HRTeams.js` behind a **byte-identical URL**
(`?v=ecs`), and the browser can keep serving its cached copy. The bundle on the server is
correct; the browser just does not ask for it.

Staging is different: `https://ldhr-test.hrupdate.org/assets/tenant/default/HRTeams.js`
answers with `cache-control: no-cache` and an `ETag` (checked 2026-10-16), so a browser asks
again on every page load and gets a new build at once. Staging updates itself: a push to
the web repo's `staging` branch (`CruGlobal/ab_service_web`) starts the GitHub Actions
workflow "Build & Deploy ECS", which runs `build.sh`, builds the image and triggers the
deploy. On 2026-10-16 the push of `0f0e6298` (HR Teams 1.0.22) finished in 1 min 19 s
(run 38896536811), and from then on every request got `version_hrteam`
`hrteamwidget@1.0.22` and a `HRTeams.js` byte for byte the one committed. On 2026-11-03
`staging` was fast-forwarded to `master` `4cdfc151` (HR Teams 1.0.23; it also brought
platform_web 1.26.5 from `master`). The run (41584205808) took 56 s, but the deploy goes
on after it: at 05:32:09 UTC a request got the new `HRTeams.js` (`last-modified` 05:29:58
GMT) while the next one still got the old `version_hrteam` from an old task, and from
05:32:37 six requests of six got both new files. On 2026-11-04 `staging` was
fast-forwarded to `master` `4c30b649` (HR Teams 1.0.25) at 03:50:50 UTC. The run
(41769602394) took 63 s, and from 03:54:12 every request got both new files
(`last-modified` 03:51:26 GMT; nine of nine checked up to 03:55:01).

Production (`https://ldhr.hrupdate.org`) deploys the same way from the web repo's **`main`**
branch: the workflow runs on a push to `main` or `staging` (`.github/workflows/build-deploy-ecs.yml`
on `master`). A push to `master` alone deploys nothing. On 2026-10-29 production served the
`HRTeams.js` of `main` `465882f2` (HR Teams 1.0.21, deployed 2026-09-23 09:05 UTC; same MD5,
`last-modified` 2026-09-23 09:06:27 GMT, also `no-cache`). It still did on 2026-11-03 and
2026-11-04 (`hrteamwidget@1.0.21`, the same MD5 as `main`'s file), so the 1.0.22 spinner
fix (W27), the 1.0.23 fix of principal changes (W47, W48), the 1.0.24 name sort (W49) and
the 1.0.25 edit lock (W50) are on staging only.

Symptoms: you edit, webpack says "compiled successfully", `curl` of the asset shows your
change, and the browser shows the old behaviour.

To confirm which side is stale:

```bash
curl -s localhost:23802/config/preloader | tr ',' '\n' | grep -o 'HRTeams.js?v=[^"]*'   # always ?v=ecs
curl -s localhost:23802/assets/tenant/default/HRTeams.js | grep -c '<your new string>'
```

and in the browser console:

```js
document.querySelector('script[src*="HRTeams"]').src
```

Workarounds: hard-refresh, or keep DevTools open with "Disable cache" ticked. Restarting
the watch build does not change the URL either.

### 1.2 Which tenants load it at all

`SiteController.js:670-675` hard-codes the tenants that get the plugin:

```js
const hrPluginTenants = [
   "admin", // <-- For local testing only
   "ldhr", // <-- ldhr.hrupdate.org AWS
   "1ad43361-d1da-47ac-9ee4-5e5bc6af512c", // ldhr.hrupdate.org
   "1729957e-d3ba-4cd4-901c-aa17982b9766", // ldhr-test.hrupdate.org
];
```

`admin` is in the list "for local testing only", which is why it loads on localhost.

### 1.3 Every page load re-saves two definitions

`index.js` `apply()` turns the already-loaded `plugin_hr_teams` views into the plugin class,
then calls `parent.viewRemove(view)` and `parent.viewInsert(newView)`. Both call
`parent.save()` when the parent's child list changes
(`class_core/views/ABViewCore.js:581-612`), so every page load sends **four**
`PUT /definition/<id>`: two for the "Teams" page and two for the "Teams.plugin_hr_teams"
view (it is the parent of the nested, older `plugin_hr_teams` copy).

This runs when the plugin loads, so **any portal page** triggers it in a tenant that loads
HR Teams (§1.2), not only the Teams page: opening the Claude Sandbox "Tasks" page as admin
sent the same four PUTs (api_sails log, 2026-10-03 14:26:36).

- As a builder or admin the PUTs succeed, so every portal load rewrites those two NetSuite
  HR Update definitions (seen in the api_sails log on 2026-10-02 and 2026-10-03).
  The child lists were the same afterwards, so the content looked unchanged, but
  `updatedAt` moved, and each save is a full definition update.
- As a user without builder rights the PUTs fail: four `Error: Forbidden.` lines and four
  uncaught promise rejections in the console on every load. Nothing else breaks.

Known issue W24. Until it is fixed, use a non-builder test user when you only need to
look, on any page ([AGENTS.md §2.0](../../AGENTS.md#20-house-rules)).

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

Keys (`PROGRESS_STATUS_KEY_*`, top of file): `common`, `team`, `principal`. For
`common`/`team` the `value` is a message string; for `principal` it is the employee's
**email**, used as an identity so concurrent operations dedupe. The `approval` key and its
two messages ("This user has a Principal Team Assignment in another entity", "You'll be
asked to enter a reason") went on 2026-10-03 with the reason Form they announced (§3).

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
**Is Principal** → Save. Rebuilt on 2026-10-03 on branch `guy/enhancements`, committed
there as `cc217ce` on 2026-10-16.
This section is the widget's side; the whole feature (object, scope, process, tests, test
plan) is in [netsuite-hr-update.md §12](../netsuite-hr-update.md#12-the-cross-entity-principal-change-since-2026-10-03).

1. Save handler calls `_checkIfDataChanged()`; bails if nothing changed.
2. Confirm dialogs where they apply: *"Caution: Creating New Assignment"* (changing Role
   type, Job title or Principal on an assignment older than a day **closes it and creates a
   new one**), or the "already has a principal assignment in this entity" warning.
3. `_fnBusyRecord($teamRecord)` shows the small per-record spinner and hides the edit
   pencil.
4. `_addProgressStatusQueue(PROGRESS_STATUS_KEY_PRINCIPAL, email)`.
5. `customProcessTasks.run({isChanging: true})` decides whether the other entity must
   approve (`needApproval`, rules in
   [netsuite-hr-update.md §12.1](../netsuite-hr-update.md#121-who-needs-approval-unchanged)).
   When it must, `run()` also keeps the other principal assignment(s) for the request; if
   there are several (bad data), the request names the first.
6. If `needApproval`: the principal status is removed and `_requestPrincipalChange()`
   runs. It refuses when the person already has a `pending` request that has not expired
   (and says when it expires), deletes expired ones, asks for the reason in its own dialog
   ("Principal change needs approval", `ids.principalChangeWindow`), and saves one
   `cache-principal-change` row, with `expires_on` 7 UTC days ahead, from
   `customProcessTasks.principalChangeRequest()`.
   That method copies this side from the form and the chart's DCs, and reads the other
   principal assignment once with `populate: [team, entity]` for the other side's team and
   entity names, which the HR scope hides from the user (S37); the read runs while the user
   types the reason, and the dialog fills in the entity name when it arrives. If the object
   is missing in the tenant, Save says "The object cache-principal-change is missing in this
   tenant." and the rest of the chart works on.
   **Nothing is written to NetSuite**; the process "Principal Change Approval" does that
   after the other entity approves. Other edits in the same form wait in the row and are
   applied with the approval (this replaces W26).
   Otherwise the assignment is saved as before (update in place, or end and create).
7. Queues removed, `_fnReadyRecord()`, `_refreshDataPanel()`.

The requests live in the widget's own data collection, `DcContainer.list.principalChange`
(a runtime DC made with `createCustomDCByObjID(..., {loadAll: true})`, like the others;
not a saved definition, not linked to the entity). It is loaded once when the chart starts;
the duplicate check reads it, the create adds the new row to it, and nothing else asks the
server. Since 2026-10-04:

- `_onPrincipalChangeUpdate()` listens to the DC's `update` event. The server sends a row's
  changes to every browser that loaded or created it, so when the process sets
  `applied`, `rejected`, `failed` or `expired`, an open chart deletes the row at once, the requester
  gets a short `webix.message`, and for an applied change on the entity on screen
  `_refreshWhenIdle()` waits until nothing is loading and no form is open, reloads the
  content DC and calls `refresh()`. The reload is needed: `refresh()` only redraws what the
  DCs hold, and process_manager creates the new assignments without telling any browser.
- `refresh()` calls `_removeFinishedPrincipalChanges()`, which deletes the finished and
  the expired rows the DC holds, for requests that finished while no chart had them. The process engine
  cannot delete rows (PE20).
- Rows that **another** user creates after the chart loaded do not reach its DC (the
  server's broadcast room is per row), so the duplicate check can miss them; the process's
  NetSuite re-check makes such a duplicate harmless.

**Expiry (since 2026-10-04).** `PRINCIPAL_CHANGE_EXPIRY_DAYS` is 7.
`_principalChangeNewExpiryDay()` gives today + 7 as a UTC day, `_principalChangeExpiryDay()`
reads a row's `expires_on` (or `created_at` + 7 for a row without it),
`_isPrincipalChangeExpired()` compares that with today's UTC day, `_principalChangeDay()`
reads a date field whichever way it arrives (the browser model gives local midnight, the
server UTC midnight), and `_principalChangeDayText()` shows a UTC day in the user's date
format. Design, the approval window and the tests:
[netsuite-hr-update.md §12.9](../netsuite-hr-update.md#129-expiry-after-7-days-since-2026-10-04).

Measured on 2026-10-03 with a one-entity HR user: Save → reason dialog 2.7 s, the other
entity's name in the dialog at 4.4 s, Send → saved in 0.5 s. On 2026-10-04 an approval
reached the requester's open chart as a message and a redrawn chart 12 s after the other
HR approved ([netsuite-hr-update.md §12.6](../netsuite-hr-update.md#126-retest-on-2026-10-04-data-collection-new-name)).

**Removed on 2026-10-03 on `guy/enhancements`:** the `"1"`-then-`"0"` saves,
`_addUserFormQueue()`, the `ab.task.userform` listener override with its hard-coded
`processFormDataKey` (`491956b4-….EmployeeEmail`), and the `approval` progress key. They
exist only to hide the reason Form that the 41-element "Updated Assignments" raises for
every principal save; the 17-element version has no such Form
([netsuite-hr-update.md §2](../netsuite-hr-update.md#2-updated-assignments)).
With them, a principal save that needed no approval left a run waiting on a hidden Form
for good (PE11), and other edits in the same form were dropped (W26). Measured runs of the
old flow are in
[netsuite-hr-update.md §8](../netsuite-hr-update.md#8-a-cross-entity-principal-move-end-to-end-2026-10-03).

**`master` still has all of the above** (1.0.25 on staging since 2026-11-04, 1.0.21 on
production), and it needs the 41-element process, which this tenant runs again since
2026-10-30. Up to 1.0.22 a change that needs approval kept its card spinner until the
reason Form arrived, with no time limit; the Form took 36 to 69 s after Save, and 107 s
for the second of two changes saved together (GitHub #537,
[known-issues.md](../known-issues.md) W47, W48, PE24). Since 1.0.23 (PR #52, merged
2026-11-03, C12) it stops waiting after 2 minutes, shows the Forms one after another,
reads a missing employee or team row from the server, and always takes the progress card
down.

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

- **"Please wait / Refreshing" waits until the tab is visible.** `refresh()` awaits
  `this._utils.waitDOM()`, which is two nested `requestAnimationFrame` calls
  (`components/utils.js:113-125`). Chrome runs no animation frames in a hidden or
  background tab, so the chart pauses there and finishes the moment the tab is shown.
  Seen 2026-10-02: a tab driven by browser automation sat on "Refreshing" for minutes and
  cleared as soon as the owner clicked it. This is not a hang; when testing, keep the tab in
  front (or bring it to front before judging). `refresh()` still has no timeout or `catch`,
  so a real error would leave the card up the same way.

Reaching the widget: pick an entity in the top select, e.g. **World Headquarters** → team
**Innovation Hub**. For sorting, **MBE** has many Hungarian names with diacritic marks
(on 2026-11-03: 18 teams, 61 cards, 15 people under Unplaced and 58 under Placed). As
admin the chart opens on AEP, which shows "No team is assigned to this entity" in this
sandbox.

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
- In NetSuite, tests may write what the chart's own features write: Team, Team Assignment
  and Team Responsibility records, and the supervisor on the employee record through the
  "Change Supervisor" dialog ([AGENTS.md §2.0](../../AGENTS.md#20-house-rules)). Nothing else.

- **A mouse drag from browser automation does nothing.** Chrome on Linux does not start an
  HTML5 drag from DevTools-protocol mouse events, so no `drop` fires (seen 2026-10-03).
  Fire the events in the page instead; the widget's own handlers then run:

  ```js
  const src = document.querySelector('[data-pk="<employee id>"][draggable="true"]');
  const node = [...document.querySelectorAll("org-chart .node")]
     .find((n) => n.dataset.id === "<team id>");
  const section = node.querySelector('.team-group-section[data-pk="2"]'); // 2 = Member
  const dt = new DataTransfer();
  const fire = (el, type) => el.dispatchEvent(
     new DragEvent(type, { bubbles: true, cancelable: true, dataTransfer: dt }));
  fire(src, "dragstart"); fire(section, "dragover"); fire(section, "drop"); fire(src, "dragend");
  ```

- Team nodes drag the same way: fire `dragstart` on the dragged `.node` div and
  `dragover` + `drop` on the target `.node` div (the org-chart library listens there), then
  `dragend`. The widget's own `_fnDropNode()` then runs.
- Model reads and writes go over the socket, so the browser's network log shows none of
  them. Use the api_sails log (`"GET /app_builder/model/<object id>"`) instead.
- Edit forms can be driven without clicks: double-click the card with
  `card.dispatchEvent(new MouseEvent("dblclick", {bubbles: true}))`, then find the form with
  `webix.$$(Object.keys(webix.ui.views).find(k => /contentFormData/.test(k)))` and use its
  `elements` (`setValue()`, `isEnabled()`).
- **"Refreshing" can hang for good with the tab visible** (W27). Seen 2026-10-03, and
  proven on 2026-10-05 on a reload as admin: the server had answered every read, yet the
  "NS Employee Record" DCs (one in `contentDisplays`, two in `dataPanels`) each held a
  pending job and a `reloadPromise` that never settled. That is the platform's dropped
  reply (W16, [frontend.md §10](../core/frontend.md#10-traps) trap 28): two replies for one DC
  within 100 ms, and the first job never resolves. `refresh()` waits on it through
  `_fetchAllData()` → `waitDCReady()`, which awaits `dc.reloadPromise` with no timeout, so
  "Refreshing" stays up. To check a stuck page, run this in its console (read-only); a line
  with `reload WAITING` is this case:

  ```js
  await (async () => {
     let req;
     const chunks = self.webpackChunkhrteamwidget;
     if (!chunks) return "HRTeams bundle not found on this page";
     chunks.push([["diag" + Date.now()], {}, (r) => { req = r; }]);
     const list = req("./components/dcContainer.js").default.list;
     const settle = (p) => Promise.race([
        p.then(() => "done", () => "failed"),
        new Promise((r) => setTimeout(() => r("WAITING"), 50)),
     ]);
     const lines = [];
     for (const [name, value] of Object.entries(list)) {
        for (const dc of [].concat(value || [])) {
           if (!dc) continue;
           const jobs = Object.keys(dc._pendingLoadDataResolves || {}).length;
           const reload = dc.reloadPromise ? await settle(dc.reloadPromise) : "-";
           lines.push(`${name} "${dc.datasource?.label}" status ${dc.dataStatus} rows ${dc.getData().length}/${dc.totalCount ?? "?"} jobs ${jobs} reload ${reload}`);
        }
     }
     const card = document.querySelector(".progress-status-messages")?.innerText.replace(/\s+/g, " ").trim();
     return [`tab ${document.visibilityState}, card: ${card || "(none)"}`, ...lines].join("\n");
  })();
  ```

  It reaches the widget's private DCs through the bundle's webpack runtime
  (`webpackChunkhrteamwidget`); the module ids are paths only in the development build.
- **The fix (2026-10-05; in HRTeams `master` since 2026-10-16, PR #51, version 1.0.22).**
  `Utils.initDC()` now calls
  `Utils.guardDC(dc)` on every DC the widget starts (and `rcDataPanel.init()` on the
  Responsibility Centre DC, which it loads before `initDC()`):
  - `settleDroppedReplies()` wraps the DC's `processIncomingData()`: when a reply replaces
    ones still waiting in the platform's 100 ms throttle, it settles their jobs right after
    the new reply is parsed. The console then shows `HRTeams: settled 1 dropped load(s) of
    "<DC>"`; on 2026-10-05 it did so 3 to 5 times on almost every load as hr.mock.pxr
    ("Team", "Team Assignment", "NS Employee Record"), so the hang was only a matter of
    timing.
  - `retryFailedLoads()` wraps `loadData()`: a failed load is tried again after 1 s and
    2 s (3 tries; console `HRTeams: loading "<DC>" failed, trying again`). If it still
    fails, `waitDCReady()` stops waiting for it (W38), and a failed `reloadPromise` is
    logged instead of thrown.
  - `refresh()` runs in `try/catch/finally`, so "Refreshing" always comes off, and its two
    `new Promise(async …)` wrappers became plain calls, so an error reaches that `catch`.

  Checked on 2026-10-05: unit runs of both guards against a copy of the platform's
  throttle (dropped replies within 100 ms, failures that recover or never do), a failure
  injected into the real `cache-principal-change` DC (loaded on the second try, 1.1 s), and
  reloads as hr.mock.pxr: with the first guard alone one load finished and the next hung on
  the 503 (cause 2 above, which led to the retry); with both guards 6 reloads of 6
  finished (card gone, 4 team nodes, no widget DC waiting; 17 to 19 s each in a hidden tab
  with the frame stand-in of [testing.md §3.3](../testing.md#33-driving-the-browser-with-automation)),
  the guard settling at least 5 dropped loads on each reload checked, and the "Staff
  Assignment" panel opened with 11 people under Unplaced and 4 under Placed. Two things that
  look
  like hangs while testing with browser automation are not: a background tab pauses
  "Refreshing" (W17; take a screenshot and it goes on), and the console tool re-lists old
  messages with new times when it reattaches, so the same warnings seem to repeat with no
  new requests in the api_sails log.
- **Checked against `master` on 2026-10-16.** The owner committed the fix as `cc217ce`
  ("Caching principal assignment", `guy/enhancements`) and checked out `master`, which
  does not have it. With `master` built and served, hard reloads of `/` as hr.mock.cni
  hung 4 times in 6: once on "Refreshing", three times on "Initializing DCs". Every load
  had DCs holding load jobs that the api_sails log shows answered in 1 to 9 s, with no
  error: cause 1 above (W16). With the fix, 30 such reloads (CNI - NS Track: 14 teams, 37
  assignments; the card went from "Initializing page" at 0.3 s to "Refreshing" at 4.1 s and
  was gone by 7 to 11 s) and 45 admin loads did not hang that way. The fix alone, without
  the principal change, went to `master` through branch `guy/fix-spinner` (known issues
  C11): 6 loads, no hang. Three of them took 45 to 80 s while NetSuite was slow and rejecting reads: the
  guard retried, gave up on "Strategy List" after three failures, and let the chart go on.
- **The data stays complete when a dropped load is settled.** `settleDroppedReplies()`
  only ends the waiting job; the platform has already thrown that reply's rows away and
  keeps the rows of the reply it parsed. The two loads usually ask for the same rows; when
  they do not (a page of 20 against `_fetchAllData()`'s 1000), `_fetchAllData()` sees fewer
  rows than `totalCount` and asks again. Checked on 2026-10-16 on `guy/fix-spinner` as
  hr.mock.cni: Team 14 of 14, Team Assignment 37 of 37, NS Employee Record 312 of 312,
  every list DC complete, and the Staff Assignment panel listed 272 Unplaced and 36 Placed,
  which with the 4 inactive people (the panel hides them) is all 312. The panel's own DCs,
  "Employee Unassigned" and "Employee Assigned", hold only their first page (20 of 274 and
  20 of 38, the same on `master`), but those two tabs list from NS Employee Record instead.
  What can be missing: a DC whose load fails three times stays empty until the next page
  load (on 2026-10-16, "Strategy List" while NetSuite was rejecting reads), where `master`
  would hang instead.
- **One gap is left with the guards (known issues W41).** The entity DC's first load starts before
  `DcContainer.init()` guards it: `init()` starts the team DC first, and the team DC's load
  starts the entity's through `waitForDataCollectionToInitialize()`. So a failed "NS
  Entity" read is never tried again, NS Entity stays "initializing" for good (W38), and
  Team, Team Assignment and NS Employee Record wait on it: the card stays on "Initializing
  DCs" with no entity in the select. Caught on 2026-10-16 on the 34th scripted admin reload
  (testing.md §3.3), after NetSuite answered that read with a 503 after 21 s ("Service
  Unavailable - Zero size object"). The owner points out that NetSuite rejects reads that
  come too often, so that 503 came from the test's pace (a reload every 10 to 20 s). W39
  also hit "Employee Assigned" and "Employee Unassigned" on every reload that day (a
  `reloadPromise` that never settles); the chart does not wait on those two. When the card
  hangs, run the snippet above in that tab.
- **Make the browser load a new build** without DevTools: from any page on the same
  origin, `await fetch("/assets/tenant/default/HRTeams.js?v=ecs", {cache: "reload"})`
  replaces the cached copy, and the next page load uses it (§1.1; used 2026-10-03).
- **Screenshot coordinates are not CSS pixels** when the automated window is zoomed: on
  2026-10-03 it ran at `devicePixelRatio` 0.5, so a point from `getBoundingClientRect()`
  had to be halved before clicking it.
- Saving a form without clicks: `form.getChildViews().find((v) => v.config.view ==
  "button").$view.querySelector("button").click()` runs the widget's own Save handler. The
  principal-change dialog's views end in `principalChangeWindow`, `principalChangeForm` and
  `principalChangeNote`; set the reason with `setValues({reason})`.
- Inbox answers can be sent as the switched user with
  `PUT /process/inbox/<form uuid>` and `{response: "approve"}` (or `"reject"`), which is
  what the inbox UI sends ([processes.md §3.10](../core/processes.md#310-a-run-seen-end-to-end-2026-10-02)).

---

## 6. How the NetSuite HR Update app uses the widget

Read from the running stack on 2026-10-02 (admin tenant, app `79e11053-…`, "NetSuite HR
Update"), plus the HRTeams source on `master`. "Inferred" marks what was read in code but
not exercised.

### 6.1 The idea

HR staff of one NetSuite **subsidiary** ("entity") see that entity's teams as an org chart
and place employees into teams. The real data lives in NetSuite: almost every object in
the app is a NetSuite table (`isNetsuite`, read and written through
`ABModelApiNetsuite` on the server, [server-platform.md](../core/server-platform.md)). AppBuilder
adds the UI, the rules about the "principal" assignment, and BPMN processes for approvals
and emails.

### 6.2 Objects

| Object (label) | NetSuite table / local table | Role |
|---|---|---|
| NS Entity | `subsidiary` | The entity being managed; the page's entity picker |
| Team | `customrecord_whq_team` | A chart node. Parent link `custrecord_whq_team_parent_id`, entity link `custrecord_whq_team_entity_record_id`, flags `custrecord_whq_team_is_whq_node` (top team), `isInactive`, `custrecord_whq_team_can_inactivate`, `custrecord_whq_team_is_external_support` |
| Team Assignment | `customrecord_ccc_team_assignment` | One employee in one team: begin and end dates, job title and description, role type, `custrecord_team_assign_is_principal`, FTE |
| NS Employee Record | `employee` | The people. `custentity_ccc_org_relation` value `2` counts as "sent" (`ORG_SENT_STATUSES`) and never gets a principal assignment |
| Team Responsibility, Responsibility List, Scope List | `customrecord_ccc_team_responsibility`, two custom lists | Responsibilities attached to an assignment |
| Role Type | `customlist_ccc_team_role_type` | Groups members inside a team card (Leader, Member, …) |
| Responsibility Centre | `department` | RC section of the chart |
| Team Strategy, Strategy List, Sub Strategy List | `customrecord_whq_teams_strategy`, two lists | Card colour (`strategyColors` 1 to 8) |
| employee, entity, history | local `AB_GlobalHRUpdate_employee`, `AB_GlobalHRUpdate_entity`, `AB_NetSuiteHRUpdate_history` | App-side records: change submissions waiting for approval, which site users manage which entity, and the last-modified history |
| cache-principal-change | local `AB_NetSuiteHRUpdate_cacheprincipalchange` | Principal changes waiting for the other entity's approval (since 2026-10-03, uncommitted; §3) |
| site user | `SITE_USER` | Linked to `entity` (who is HR for which entity) |

### 6.3 Data collections

The app's own DCs, all but two following the cursor of **NS Entity** (`loadAll`, filtered
to real, active, non-elimination subsidiaries), which the page's `data-select` widget
moves:

| DC | Source | Linked by | What the widget does with it |
|---|---|---|---|
| TEAMS | Team | `custrecord_whq_team_entity_record_id` | `datacollectionID`: only its object, link and filter are used; the widget replaces it with its own copy |
| All Assignments | Team Assignment | `custrecord_ccc_team_assign_entity` | Nothing (the page loads it anyway) |
| Employee List ("Employee Unassigned"), Employee Assigned | NS Employee Record | `subsidiary` (+ `not_in` / `in_data_collection` All Assignments) | Named in `dataPanelDCs` and loaded, but the panel lists are built from the widget's own DCs (below) |
| Team Responsibility | Team Responsibility | `custrecord_ccc_team_respons_entity` | Nothing directly; the Responsibilities field reads its own copy |
| Responsibility Centre | Responsibility Centre | `department` | The RC panel's list (`CONST.RESPONSIBILITY_CENTRE_DC_ID`) |
| NS Entity | NS Entity | | Entity picker (`entityDatacollection`) |
| Entity, Role Type | entity, Role Type | | Not loaded on start (`notInitial`) |

**The widget builds its own data collections** (`components/dcContainer.js`,
`utils.createCustomDCByObjID()`, ids `dc.<object id>`): a copy of the team DC with the RC
relation populated; the content DC (Team Assignment, linked to the entity, filter "begin
date set AND ((begin ≤ today AND end > today) OR no end date)", Responsibilities
populated); role types, strategies, strategy codes, sub-strategies and the responsibility
list (all `loadAll`); since 2026-10-04 (uncommitted) the principal-change requests
(`cache-principal-change`, `loadAll`, not linked to the entity, §3); and one display DC per
object in `contentDisplayedFields`, for example NS Employee Record linked to the entity.
Cards, drop checks and the data panel all read these copies, not the app's DCs.

NetSuite reads take 3 to 9 s each here, so the first render takes a while
([frontend.md §10](../core/frontend.md#10-traps) trap 29).

### 6.4 Widget settings that wire it together

The page "Teams" holds `data-select` (on NS Entity) and the `plugin_hr_teams` view. Key
settings of that view:

| Setting | Points at | Meaning |
|---|---|---|
| `datacollectionID` | TEAMS | Nodes of the chart |
| `teamLink`, `teamName`, `topTeam` | Team `Team`, `name`, `custrecord_whq_team_is_whq_node` | Tree shape, label, root. No top team shows the "No team is assigned to this entity" alert |
| `teamInactive`, `teamCanInactivate`, `teamStrategy`, `strategyCode`, `subStrategy` | Team fields | Inactive handling and card colour |
| `contentField` | Team → `custrecord_ccc_team_assign_team_id` | Which assignments belong to a team |
| `contentGroupByField` | `custrecord_ccc_team_assign_role_type` | Sections inside a card |
| `contentFieldDateStart`, `contentFieldDateEnd` | begin and end date | Only current assignments show: `contentFieldFilter` is "begin ≤ today and end > today", and the widget adds "or no end date" (`components/dcContainer.js:69-89`) |
| `contentPrincipleField` | `custrecord_team_assign_is_principal` | The principal flag (§3) |
| `contentDisplayedFields` | Employee email, first and last name, initials; assignment job title; role type name | What a member card shows |
| `dataPanelDCs` | Employee List ("Unplaced"), Employee Assigned ("Placed") | The side panel's two tabs. The lists come from the widget's employee DC: active employees (`isinactive` not `"T"`) of the entity without, or with, a current assignment |
| `contentDisplayedFieldFilters` | email, job title, first name, last name, role type | Extra fields in the Filter popup |
| `dropContentToCreate`, `editContentFieldsToCreateNew` | 1; job title, role type, principal | Moving a member to another team ends the old assignment and creates a new one (only a move to another section of the same team, within a day of the start, edits it in place). In the edit form, changing one of these fields on an assignment older than a day closes it and creates a new one |
| `setEditableContentFields` | employee, job title and description, role type, dates, responsibility, principal | Fields in the edit form |
| `entityDatacollection` | NS Entity | Used by `libs/CustomProcessTasks.js` to know the current entity |

The view also contains a second, nested `plugin_hr_teams` child (`8f1c4159-…`) with an
older copy of the same settings. Inferred: a leftover from editing; nothing showed it.

### 6.5 What happens on drag and drop

- **Drop a person from the data panel onto a team** creates a Team Assignment at once
  (begin date = today, employee, team, and the role type of the section dropped on)
  through `createData()`; nothing is asked (`ABViewOrgChartTeamsComponent.js:294-404`). If
  the person already has a card in that team, a drop on the same section does nothing, and
  a drop on another section moves the card (in place within a day of its start, otherwise
  by ending it and creating a new one). Seen at runtime on 2026-10-03
  ([netsuite-hr-update.md §8](../netsuite-hr-update.md#8-a-cross-entity-principal-move-end-to-end-2026-10-03)).
- **Move a member to another team** first opens a "Change Supervisor for …" dialog; so
  does a move to the other section of the same team (seen 2026-11-03). Choosing a leader
  of the new team and confirming writes `custentity_ccc_supervisor` (with
  `customform: 166`) on the person's **NetSuite employee record** (`:434-548`). Nothing
  waits for that write or catches its error: the move goes on at once, and a failed write
  shows no message (W52, seen 2026-11-03 with the write held). Then it ends the old
  assignment with `updateData()` and creates a new one for the new team (`:586-622`).
- Before saving, `libs/CustomProcessTasks.js` `run()` decides the **principal** flag
  (inferred from reading `:198-290`):
  - external-support teams and "sent" employees (`custentity_ccc_org_relation` = 2) never
    get principal;
  - if the person has no record in another entity, the assignment becomes principal unless
    this entity already has one; on a change, the old principal is cleared;
  - if the person exists in other entities (matched by **email**) and holds a principal
    there, the new one is not principal, and on a change the edit is marked as needing
    approval; the edit form then sends a `cache-principal-change` request instead of
    saving (§3).

  The last two cases were seen at runtime on 2026-10-03. These lookups run with the HR
  user's rights; they see every entity because the HR scope does not restrict Team
  Assignment and NS Employee Record ([netsuite-hr-update.md §11](../netsuite-hr-update.md#11-who-can-see-what-hr-generalists)).
- Writes go to NetSuite through appbuilder (`model-post` / `model-update`), and the
  server's lifecycle triggers start the processes below.

### 6.6 Processes

| Process | Starts on | What it does |
|---|---|---|
| New Assignments | Team Assignment **added** | Nothing: switched off on purpose by leaving Start unconnected ([netsuite-hr-update.md §3](../netsuite-hr-update.md#3-new-assignments-is-switched-off-on-purpose)) |
| Updated Assignments | Team Assignment **updated** | Update the `history` records, then an in-app notice to this entity's HR: "Notify of an Edited Assignment", or "Notify of an End Principal Assignment" when a principal assignment ends. 17 elements since 2026-10-03; before, it also ran the cross-entity approval (41 elements) |
| Principal Change Approval | `cache-principal-change` row **added** by the edit form | Ask the other entity's HR to approve a principal change, check NetSuite again, end and copy the assignments on both sides, notify both HR groups ([netsuite-hr-update.md §12](../netsuite-hr-update.md#12-the-cross-entity-principal-change-since-2026-10-03)) |
| New Submission, Updated Submission | local `employee` **added** / **updated** (Updated only when the row is not already pending) | Mark it pending approval, then an External task "Approve Changes" pointing at `https://localhost:23803/approve/<netsuite_id>?subsidiary=<entity_id>`, the Global HR Update site ([netsuite-hr-update.md §13](../netsuite-hr-update.md#13-global-hr-update-the-sibling-web-app)) |
| Test | | Empty |

Step-by-step flows, run history and what is broken: [netsuite-hr-update.md](../netsuite-hr-update.md).
How triggers and tasks run in general is in [processes.md](../core/processes.md). These processes carry
several designer warnings (missing Save operations; before 2026-10-03 also unresolved Email
lanes and a missing message on "Notify Fails"), and the "Edit Responsibility.form" view has the runaway
`viewIDs` list ([known-issues.md](../known-issues.md) R20).

---

## 7. Every feature, read in the code (2026-10-03)

Read from the whole `ABViewOrgChartTeamsComponent.js` and `components/` on 2026-10-03.
"Not run" marks what has not been tried at runtime yet.

### 7.1 Roles decide what you can do

`_initRole()` checks three hardcoded role uuids (`components/constants.js`): System Admin,
HR Generalists (HRG) and Core Finance.

| Role | Can do |
|---|---|
| HRG | Drop people into Leader and Member sections, edit cards, add and edit teams. The staff data panel |
| Core Finance | Drag Responsibility Centres (RCs) onto teams and remove them. The RC data panel. The Member section is hidden |
| System Admin, or HRG plus Core Finance | Everything, plus a button to switch between the two data panels. Staff drops still need the HRG role (`_getDropZoneSections()` sets the drop handler only for HRG) |

### 7.2 Team management

- **Add a team:** the "+" button on a node (HRG or admin) opens "Add Team": name,
  Strategy (a code that filters the next list), Sub Strategy (the Team Strategy record),
  and an Inactive switch. The parent is the node you clicked. `teamAddChild()` creates the
  Team with the entity of the current cursor and the user's email in
  `custrecord_ccc_team_last_upd_by_in_app`; a team added under an external-support team
  becomes external support too.
- **Edit a team:** the pencil or a double click on the title. The parent can be changed
  here, except for the top team, external-support teams and teams with
  `custrecord_whq_team_can_inactivate` off, which also lock the strategy fields.
- **Move a team:** drag a node onto another node. External-support teams under the top team
  cannot move ("External support teams cannot be moved."). Otherwise the parent changes
  and the team takes the external-support flag of its new parent.
- **Inactivate:** allowed only when `custrecord_whq_team_can_inactivate` is on, no active
  child team and no current assignment is left. Inactive teams are hidden unless the
  Filter's "Show Inactive Teams" is on, which also shows ACTIVE / INACTIVE tags.
- **Delete:** the trash button appears only when the team could be inactivated, has no
  child team and has **no assignment at all, current or ended** (a server check).
  `teamDelete()` then removes the NetSuite record (`model.delete()`, not awaited).

Teams write only the columns `_cleanValue()` allows: name, inactive, strategy, parent,
external support and the entity.

### 7.3 Member cards and the edit form

- Cards are grouped by role type (Leader, Member). Principal cards come first and get a
  border in the team's strategy colour, then non-emeritus before emeritus staff, then by
  last and first name. The card shows job title, first name (or preferred name), last name
  and initials. Names compare with one `Intl.Collator("en", { sensitivity: "base" })`
  (`compareNames()` in `components/utils.js`), so a letter with a diacritic mark sorts
  with its base letter and case does not count, here, in the Staff Assignment panel and
  in the Change Supervisor list; the panel and that list break a tie on the first name
  (since 1.0.24, PR #53, known issues C13; before, "Ágoston" sorted after "Z", W49).
- While any save of a person runs, every card of that person shows a spinner instead of
  its pencil and cannot be dragged (`_fnBusyRecord()`), also after a redraw, and a double
  click, a move of the card or a drop of the person from the panel is refused with a
  message; other people's cards stay editable (GitHub #280, #320). One edit form is open
  at a time (since 1.0.25, PR #54, known issues C14; before, only the saved card was
  blocked, W50). The supervisor change made during a move is not counted, and nothing
  waits for it (W52). When a write fails, the lock ends but no message says so, and a
  moved card stays where it was dropped (W53).
- The edit form (pencil or double click) shows the fields in `setEditableContentFields`.
  "Is Principal" is disabled for "sent" employees and in external-support teams. End Date
  must be **later** than Start Date (a strict check, W25). Dates are sent as local
  `YYYY-MM-DD` strings (`_parseFormValueByType()`), so the form does not hit W23.
- What happens on save is in §3 (principal) and §6.5.

### 7.4 Responsibilities

The Responsibilities field is AppBuilder's own "connect" widget, built on the fly
(`_elementResponsibility()`), with a "+" that opens the app's form view `b0784e31-…` to add
a new Team Responsibility. Its list is filtered to Team Responsibilities of the current
entity that are not inactive **and whose "updated by" email is the current user's**
(`is_current_email`). So an HR user cannot pick a responsibility another HR user created
(W32; intended or not is not known). Not run.

### 7.5 Responsibility Centre (RC)

- The RC panel lists the app DC "Responsibility Centre", with a search box and All /
  Unplaced / Placed. Core Finance and admins drag an RC onto a team's RC section; the team
  record gets the RC in its RC field (`CONST.TEAM_RESPONSIBILITY_CENTRE_FIELD_ID`). The
  trash icon on an RC removes the link.
- Read in the code, two checks look wrong (not run): the "already exists" test is
  `team?.id ?? team == teamId`, which is true for any linked object, so any RC that is
  already on some team may be refused with "Already Exists" (W29); and removal filters
  with `relatedTeam.id ?? relatedTeam != rcId`, which keeps every object entry, so the RC
  may stay linked in NetSuite while it disappears from the screen (W30).
- HR users get no rows from the Responsibility Centre object, so their RC panel is empty
  (D5). The team boxes still show each team's RCs, which come with the team record (the
  team DC populates the RC field): 8 for hr.mock.cni in CNI - NS Track on 2026-10-16.

### 7.6 Filter

The Filter popup has Team Name, Strategy, "Show Inactive Teams", and the fields in
`contentDisplayedFieldFilters` (here email, job title, first and last name, role type).
Team name and strategy match with OR; a team whose own content does not match but has
matching children stays as a title-only node: `_fnCreateNode()` draws no sections in it.
Applying a filter runs `refresh()` (`filterApply()`), which redraws the chart from the rows
the DCs already hold; drawing a team still sends its W40 read. When a title-only team has
an RC, that redraw stops with an error and the matching teams show no cards (W42); up to
1.0.21 the card also stayed on "Refreshing".

### 7.7 Other details

- The data panel is a popup ("Staff Assignment"); Unplaced and Placed tabs, a search on
  initials and names. Dragging is HTML5 drag and drop (§5 for testing). Both tabs sort on
  the last name only (W49).
- Clicking the progress card clears its queue and hides it. The card also drives the
  Filter button: `_refreshProgressStatus()` calls `busy()` while the queue has entries and
  `ready()` when it hides the card, so the click enables the Filter button again (seen
  2026-10-16).
- `_fnDropNode()` returns early, **without** `ready()`, when a team is dropped on its own
  parent, so the Filter button stays disabled (W31, read in code).
- `ABViewOrgChartTeamsCore.fromValues()` defaults `settings.connectFieldDateEnd`, a typo
  for `contentFieldDateEnd` (harmless while the definition sets it).

### 7.8 Seen at runtime (2026-10-03)

Every feature above was run in the real UI as `hr.mock.pxr` (HR Generalists, entity PXR
4925; for the RC part also Core Finance), with drops fired as in §5. NetSuite sandbox 3.

| Feature | What happened |
|---|---|
| Add team | "Claude Test Team" became Team **20704** in about 5 s. NetSuite set `custrecord_whq_team_can_inactivate` on by default; `custrecord_ccc_team_last_upd_by_in_app` got the HR's email |
| Edit team | Rename in about 4 s |
| Move team | Dropped on "Sent Abroad": the parent changed. The card said "Creating a team" during the move, because the node is re-added locally |
| Team dropped on its own parent | The Filter button stayed disabled until a later action called `ready()` (W31, confirmed) |
| Drops | First drop of the test person: principal 1 (no other principal). Second drop, another team: principal 0 |
| Save with principal, same entity | Warning "this team member already has a principal assignment in this entity" → "Save with principal" → the old principal (57205) was ended and copied as non-principal (57207) by `_updateWithNoPrincipal()`; the edited one (57206) became principal; about 10 s with the card "Checking for principal assignment allowance changes" |
| Its process run | Stopped at the reason Form: the form reached the browser and the widget hid it (PE11's cause, seen). Its "principal in other entity" lookup picked 57206 itself |
| External Support | Drop gave principal 0; "Is Principal" disabled in the form |
| "Sent" staff | Drop gave principal 0; "Is Principal" disabled. Real data already holds a principal assignment for a "sent" person (the rule applies only to new saves) |
| Edit an assignment started before today | Start date moved back in place, then a role type change asked "Caution: Creating New Assignment": the old one ended today and a new Leader assignment started today |
| Move with Change Supervisor | Cancel kept the supervisor. Confirming wrote the employee's `custentity_ccc_supervisor` at once (the alert says it takes time); the next dialog showed the new value. Restored afterwards |
| Responsibilities | "+" opened the app's "Add Responsibility" page as a popup (Responsibility list, Data Scope, Start Date required) and created Team Responsibility **1903** with the HR's email in `custrecord_ccc_team_resp_last_upd_in_app`; saving the assignment linked it (`custrecord_ccc_team_resp_assignment_id` on the responsibility). Opening the edit form logs `View[form] didn't define a dataviewID` from `_elementResponsibility()` (harmless) |
| Filter | Team name "Claude" left that team plus its parents as title-only nodes |
| RC (HRG + Core Finance) | The switch button appeared; the panel listed 37 RCs. An RC can sit on several teams; drop and remove both reached NetSuite (join records `customrecord_team_rc`). W29 and W30 did not trigger: the arrays held plain ids. An RC drop made the chart refresh |
| Inactivate team | NetSuite got `isinactive = "T"` and the node left the chart, but the model and the app's TEAMS DC still read the boolean field `isInactive` as `false` (R24) |

Processes: only Team Assignment writes start runs. Each create ran "New Assignments" (does
nothing); each in-place update or end of a non-principal assignment ran "Updated
Assignments" to "Notify of an Edited Assignment"; ending a principal ran "Notify of an End
Principal Assignment". Team, RC, responsibility and supervisor writes start nothing.

Two display problems were seen once each and not again (W33): after a move that also
changed the supervisor, the old card (old record id and team) stayed in the new team and
the new record was not drawn; and later in the same session the panel listed everyone as
Unplaced and nobody as Placed. NetSuite was right both times, and a reload fixed the screen.

Left in place: Team 20704 "Claude Test Team 2" (inactive, under Sent Abroad); assignments
57205 to 57211 and 57305 to 57309, all ended on 2026-10-03 (57211 belongs to a "sent"
staff member, the rest to the test person 2286202); Team Responsibility 1903 (linked to
57210, end date set to 2026-10-03 afterwards); the test person's supervisor was changed twice and restored. In the tenant: 28
process runs, about 15 unanswered notices in `hr.mock.pxr`'s inbox, and run `de60a886`
waiting at the hidden Form. `hr.mock.pxr` had Core Finance only during the RC test.

Test tip: a role added straight in the DB does not reach a switched user, because api_sails
caches users until appbuilder sends `api_sails.user-cache-stale`; change roles through the
model (`PUT /app_builder/model/<SITE_USER object>/<uuid>`) instead.

