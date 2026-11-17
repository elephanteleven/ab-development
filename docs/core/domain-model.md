# Domain model (class_core)

How AppBuilder represents what builders design: applications, objects (tables), fields,
queries, data collections, filters, the process query language, translations, roles and
scopes. The code is the class_core repo (branch **`v2`**). It is checked out as a nested
submodule wherever it is used: `AppBuilder/core` inside each AppBuilder service (cited
here as `developer/appbuilder/AppBuilder/core`), `developer/ab_platform_web/AppBuilder/core`
and `developer/pwa/src/js/AppBuilder/core`.

Verified against class_core `2ecde314` (version 2.20.0, `class_core/version`) on
2026-10-01. The services and ab_platform_web pin that same commit; pwa pins an older one
(`d52cad3`). Paths below are relative to class_core's root unless they start with
`developer/`. Line numbers drift; search by symbol name first.
"Inferred" marks behavior reasoned from code but not run.

Related docs: [architecture.md](architecture.md) (core/platform split, messaging),
[server-platform.md](server-platform.md) (server subclasses, SQL), [widgets.md](widgets.md)
(views), [processes.md](processes.md) (BPMN).

---

## 1. Shape of the model

Every design artifact is a row in the tenant's `appbuilder_definition` table:
`{id, name, type, json}`. A per-tenant **factory** (`ABFactoryCore`) turns rows into class
instances. Each "*Core" class here is the shared, environment-neutral half; the platform
half (server in `developer/appbuilder/AppBuilder/platform/`, browser in
`developer/ab_platform_web/AppBuilder/platform/`) extends it with DDL/SQL or UI and network
code. See [architecture.md §3](architecture.md#3-the-coreplatform-split).

### File map

| File | Responsibility |
|---|---|
| `ABMLClassCore.js` | Base for every translatable definition: `translations[]`, `translate()`, `unTranslate()`, `toDefinition()` |
| `ABDefinitionCore.js` | Wrapper for one definition row, with `save()` / `destroy()` that call the factory |
| `ABFactoryCore.js` | Per-tenant registry: builds instances from rows, lookups, `definitionSync`, `rules` helpers, class registry, system-object getters |
| `ABFieldManager.js` | Registry of field classes keyed by `defaults().key` |
| `ABApplicationCore.js` | An application: ID lists of children, pages, access rules, version data |
| `ABApplicationMobileCore.js` | Mobile (PWA) application subclass (`appType:"mobile"`) |
| `ABMobileAppCore.js` | Older `mobile.application` wrapper |
| `ABObjectCore.js` | An object (table): properties, fields, indexes, `model()`, REST URLs, labels |
| `ABObjectQueryCore.js` | A query object: join tree + picked fields + where; a MySQL VIEW on the server |
| `ABObjectApiCore.js` | Object backed by a generic REST API |
| `ABObjectApiNetsuiteCore.js` | Object backed by NetSuite (REST + SuiteQL) |
| `ABModelCore.js` | Data-access helpers: stale refresh batching, CSV pack/unpack, `normalizeData` |
| `ABDataCollectionCore.js` | Data collection: datasource, filters, sort, cursor, paging, realtime handlers |
| `FilterComplexCore.js` | The active filter engine (client-side checks, operator menus) |
| `RowFilterCore.js` | Legacy flat filter engine; no live caller found |
| `ABIndexCore.js` | DB index definition |
| `ABHintCore.js`, `ABStepCore.js` | Tutorials ("hints") and their steps |
| `ABRoleCore.js`, `ABScopeCore.js` | Old classes, imported by nothing (roles/scopes now live in system objects, §10) |
| `ABComponentCore.js` | EventEmitter base, used only by the server's `ABComponent` |
| `dataFields/` | The field classes (§5) |
| `ql/` | The process query language (§8) |
| `labels/` | `labels.js` (`{en}` index) and `en.js` (flat key to English map, about 400 keys) |
| `process/`, `views/`, `mobile/`, `ABProcessCore.js`, `ABViewManager*.js` | Covered in [processes.md](processes.md), [widgets.md](widgets.md), [frontend.md](frontend.md) |

---

## 2. Definitions and the factory

### Which definition types the factory tracks

`ABFactoryCore.init()` builds, in order: object, query, datacollection, process, hint,
step, application, then emits `init.objects_ready` (nothing listens to it)
(`ABFactoryCore.js:261-298`). Tracked lists (`objectKeysByDef`, `:317-347`):

| Definition `type` | List | Builder |
|---|---|---|
| `application` | `_allApplications` | `applicationNew` (mobile apps go to `applicationMobileNew`, `:508-527`) |
| `datacollection` | `_allDatacollections` | `datacollectionNew` |
| `hint` | `_allHints` | `hintNew` |
| `steps` (see trap) | `_allSteps` | `stepNew` |
| `object` | `_allObjects` | `objectNew` |
| `process` | `_allProcesses` | `processNew` |
| `query` | `_allQueries` | `queryNew` |

Child types (`field`, `index`, `page`/`view`, `process.*` elements, mobile types) are built
by their parents through `definitionByID`.

### What the factory exposes

- **Definitions:** `definitionByID(id, isRaw)` (returns the stored json **without copying
  it**, `:364-373`), `definitionNew`, `definitionsParse`, and `definitionSync(op, id, def)`
  (`:425-469`): `created` pushes the instance and emits `definition.created`; `updated`
  replaces it and emits `definition.updated` on the old instance; `destroyed` removes it
  and emits `definition.deleted`.
- **Lookups:** `applications`/`applicationByID` (id only), `objects`/`objectByID`,
  `queries`/`queryByID`, `datacollections`/`datacollectionByID`, `processes`/`processByID`,
  `hints`/`hintID`, `steps`/`stepID`. All except `applicationByID` also match by **name or
  label**.
- **Builders:** `applicationNew`, `applicationMobileNew`, `datacollectionNew`, `fieldNew`,
  `indexNew`, `objectNew`, `queryNew`, `hintNew`, `stepNew`, `processNew`,
  `processElementNew`, `filterComplexNew(idBase, options)`, `rowfilterNew` (legacy),
  `viewNewDetatched`.
- **System objects** (fixed UUIDs, `:698-748`): `objectFile`, `objectLanguage`,
  `objectPlugin`, `objectPluginLinks`, `objectProcessDefinition`, `objectProcessForm`,
  `objectProcessInstance`, `objectRole`, `objectScope`, `objectToken`, `objectUser`,
  `objectKey`, `objectSecret`.
- **Plugins:** `pluginAPI`, `pluginLocalLoad`, `pluginRegister(factory)` (one class or an
  array, `:753-776`).
- **`Label()`** fills `{0}`, `{1}` placeholders. **`notify`** (must be overridden by the
  platform) with `notify.builder` / `notify.developer`.
- **`rules`** (core, `:118-232`): `isUUID` (v1 to v5), `nameFilter`,
  `toApplicationNameFormat` (`AB_` prefix), `toFieldRelationFormat` (`__relation` suffix),
  `toJunctionTableFK` (64-char cap), `toJunctionTableNameFormat`, `toObjectNameFormat`.
  Platform additions: server `toSQLDate`, `toSQLDateTime` (UTC), and both platforms
  `toDate`, `toDateFormat`, `addDate`, `subtractDate`, `getUTCDayTimeRange`
  (`developer/appbuilder/AppBuilder/ABFactory.js:189-333`,
  `developer/ab_platform_web/AppBuilder/ABFactory.js:435-560`).

**Server vs browser:** the browser applies realtime `ab.abdefinition.create/update/delete`
socket events through `definitionSync` (`developer/ab_platform_web/AppBuilder/ABFactory.js:587-631`).
The server never updates in place: any `definition.*` event (local or over cote pub/sub,
including `definition.stale`) drops the tenant's whole factory, and the next request rebuilds
it (`developer/appbuilder/AppBuilder/ABBootstrap.js:160-180`).

### ABDefinitionCore

`fromValues` takes `name` from `name`, `json.name`, `json.label` or
`json.translations[0].label`, else raises `notify.builder` (`ABDefinitionCore.js:16-45`).
`save()` calls `AB.definitionUpdate(id, obj)` or `AB.definitionCreate(obj)`; `destroy()`
calls `AB.definitionDestroy(id)` (`:73-89`). On the server only `definition_manager` may
call these (see [services.md](services.md#2-definition_manager)).

---

## 3. Applications

`ABApplicationCore` parses everything in its constructor (`ABApplicationCore.js:45-240`).

| Child | Stored as | Notes |
|---|---|---|
| Objects | `objectIDs` | ID list only (`:157`) |
| Queries | `queryIDs` | (`:163`) |
| Data collections | `datacollectionIDs` | (`:170`) |
| Hints | `hintIDs` | (`:150`) |
| Processes | `processIDs` | Missing IDs emit `warning` but are kept (`:204-215`) |
| Pages | `pageIDs` | Instantiated via `pageNew(def)` into `_pages` (`:178-197`). **Missing page IDs are dropped on the next save** (trap 1) |
| Mobile apps | separate application definitions with `appType:"mobile"` | not children |
| Roles | `roleAccess[]` (role UUIDs) | no child list |

Other attributes: `appType` (`web` default or `mobile`), `icon` (default `fa-rocket`),
`isSystemObject`, `isAccessManaged` + `accessManagers`, `isTranslationManaged` +
`translationManagers`, `isTutorialManaged` + `tutorialManagers`, `versionData`
(`{versionNumber:"1.0.0", changeLog}`), `objectListSettings` (designer list state).
Translatable: `label`, `description`.

**The JSON is nested twice.** `toObj()` (`:323-371`) produces
`{id, type:"application", appType, name, icon, isSystemObject, roleAccess, translations,
...managers, json:{translations, name, versionData, objectIDs, objectListSettings, hintIDs,
queryIDs, datacollectionIDs, pageIDs, processIDs}}`, and `toDefinition()` stores that whole
object as the row's `json`. So a row is `{..., json:{..., json:{objectIDs, ...}}}`.

**Access:** `isAccessibleForRoles(roles)` (`:266-302`) checks `roleAccess` when the app is
not access-managed; otherwise `accessManagers.role` (if `useRole`) or whether any page is
accessible.

**Browser lifecycle:** `objectInsert/Remove`, `queryInsert/Remove`,
`datacollectionInsert/Remove`, `processInsert/Remove` each save the application
immediately (`developer/ab_platform_web/AppBuilder/platform/ABApplication.js:93-193`);
`pageInsert/Remove` (`:296-323`); `exportIDs` walks every child for export.

**Lookups:** `objectsIncluded/Excluded`, `queriesIncluded/Excluded`,
`datacollectionsIncluded/Excluded`, `hintsIncluded/Excluded`, `processes`, `pages(fn, deep)`,
`pageByID(id, deep=true)`, `views(fn)` (recursive), `viewAll`, `isWebApp`, `isMobile`.

---

## 4. Objects

### 4.1 Persisted properties (`ABObjectCore.js` `fromValues` `:63-237`, `toObj` `:302-347`)

| Property | Meaning |
|---|---|
| `name` | Untranslated name |
| `labelFormat` | Template with `{<field.id>}` tokens (field **id**, not column name) |
| `labelSettings` | `{isNoLabelDisplay, noLabelText}` |
| `isImported` | Deprecated |
| `isExternal` | Existing table, no DDL |
| `tableName` | Only `[a-zA-Z0-9_ ]` kept. Empty on the server becomes `AB_<appName>_<name>` via `createdInAppID` (`developer/appbuilder/AppBuilder/platform/ABObject.js:76-93`) |
| `primaryColumnName` | `PK()` returns it or `"uuid"` |
| `transColumnName` | HRIS translation-table workaround |
| `urlPath`, `isSystemObject`, `createdInAppID`, `connName` (legacy) | |
| `objectWorkspace` | Designer grid preferences `{sortFields, filterConditions, frozenColumnID, hiddenFields}` |
| `fieldIDs`, `importedFieldIDs`, `indexIDs` | Unknown IDs are parked (`_unknownFieldIDs`, `_unknownIndex`) and written back out |
| `translations` | Only `label` is translatable |

`isReadOnly` is `isImported || isExternal || readonly` (`:805-807`).

### 4.2 Fields, indexes, data access

- Fields: `fields(fn)`, `fieldByID`, `connectFields(fn)` (connect + user fields),
  `fieldNew`, `fieldAdd/Save`, `fieldRemove`, `fieldReorder`, `fieldImport`, `imageFields`,
  `multilingualFields()`; indexes: `indexes`, `indexByID`, `indexSave`, `indexRemove`.
- `model()` returns a **new** `ABModel` on every call (`:663-671`).
- `displayData(row)` translates, fills `labelFormat`, falls back to the first label-able
  field, then `noLabelText` or `"ID: <id>"` (`:952-1018`). `minRelationData()` lists the
  columns a relation needs. `whereCleanUp(cond)` removes empty groups/rules.

REST URLs (`:682-729`) and the api_sails routes behind them
(`developer/api_sails/config/routes.js`):

| Method | URL | Route |
|---|---|---|
| `urlRest()` | `/app_builder/model/:id` | GET model-get, POST model-post |
| `urlRestItem(id)` | `/app_builder/model/:id/:rowId` | PUT model-update, DELETE model-delete |
| `urlRestBatch()` | `/app_builder/batch/model/:id` | POST, PUT |
| `urlRestCount()` | `/app_builder/model/:id/count` | GET |
| `urlRestLog()` | `/app_builder/object/:id/track` | GET `log_manager/rowlog-find` |
| `urlRestRefresh()` | `/app_builder/model/refreshobject/:id` | **no route** |

### 4.3 Which class `objectNew()` builds (`ABFactoryCore.js:668-696`)

1. `plugin_key` set: `ClassManager.createObject` (plugin object, e.g. `ab-object-netsuite-api`).
2. `isExternal`: `ABObjectExternal` (platform only).
3. `isImported`: `ABObjectImport` (platform only).
4. `isNetsuite`: `ABObjectApiNetsuite`.
5. `isAPI`: `ABObjectApi`.
6. Otherwise `ABObject`.

### 4.4 Query objects (`ABObjectQueryCore.js`)

`isQuery = true`, `type:"query"`. Persisted:

| Key | Shape |
|---|---|
| `joins` | `{objectID, links:[{alias, fieldID, type, links:[...]}]}`; root alias `BASE_OBJECT`; join types `innerjoin`, `left`, `right`, `fullouterjoin` |
| `fields` | `[{alias, objectID, fieldID}]`: each field is a clone of another object's field, marked with `.alias` |
| `where` | `{glue, rules}` (missing glue becomes `and`) |
| `viewName` | Server default `AB_<app>_View_<name>` |
| `settings` | `{grouping, hidePrefix}`; `isGroup` = `settings.grouping` |

In the browser the clone's `columnName` becomes `"<alias>.<column>"`, which is why query
rows are keyed like `BASE_OBJECT.name`. Queries are always read-only; `model()` returns
`ABModelQuery`. On the server the query is a `CREATE OR REPLACE VIEW` and reads come from
that view; create/update/relate are stubs (details in [server-platform.md](server-platform.md)).

### 4.5 API objects (`ABObjectApiCore.js`)

Stores `isAPI`, `readonly`, `apiType` (default `Read`), `isFetched`, `request`
(`{url, verb, headers:[{key,value}], paging:{type:"queryString"|"header", start, limit,
total}}`) and `response` (`{dataKey:"a.b.c", fields}`). Secrets are stripped before saving
and stored server-side with `AB.Secret`. Reads go through the normal model-get route with
`cond.isAPI` and `cond.url`; the server fetches the URL, resolves `SECRET:<name>` headers,
applies `dataKey`, and ignores `where`/`sort`. **Writes are not implemented** (browser
`ABModelApi` rejects them).

### 4.6 NetSuite objects (`ABObjectApiNetsuiteCore.js`)

Adds `isNetsuite`, `credentials{}` and `columnRef{}` (maps AB `created_at`/`updated_at` to
NetSuite columns). Credential keys: `NETSUITE_CONSUMER_KEY`, `NETSUITE_CONSUMER_SECRET`,
`NETSUITE_TOKEN_KEY`, `NETSUITE_TOKEN_SECRET`, `NETSUITE_REALM`, `NETSUITE_BASE_URL`,
`NETSUITE_QUERY_BASE_URL`. A value `ENV:<VAR>` is read from the service's environment;
`SECRET:` values are not decoded yet (TODO). `tableName` is the NetSuite record type. Server
routing (`developer/appbuilder/AppBuilder/platform/ABModelApiNetsuite.js`): reads via
SuiteQL `POST <QUERY_BASE_URL>/suiteql` (`Prefer: transient`), create `POST`, update
`PATCH`, delete `DELETE`, all signed with OAuth 1.0a HMAC-SHA256. The browser model only
normalizes keys and `"T"`/`"F"` booleans.

---

## 5. Fields

### 5.1 Registry and base API

`ABFieldManager` imports 20 platform classes and registers each under `defaults().key`
(`ABFieldManager.js:8-60`): the 19 data types below plus `ABFieldSelectivity`, a browser
rendering helper (key `selectivity` in the browser; registered under `undefined` on the
server). `newField` with an unknown key logs and returns `undefined` (see trap 3).

**Persisted** (`dataFields/ABFieldCore.js` `toObj` `:188-201`):
`{id, type:"field", key, icon, isImported, columnName, settings, translations}`; the
definition `name` is `"<objectName>-><label>"`. `fromValues` defaults `columnName` to the
label (only `[a-zA-Z0-9_ ]` kept), parses `showIcon` (1), `required` (0), `unique` (0),
`width` (0) and merges the class's `defaultValues()` into `settings`.

**Type flags** from `defaults()`: `key`, `icon`, `menuName`, `description`,
`isFilterable`, `isSortable`, `useAsLabel`, `supportQuery` (boolean or `(field)=>bool`),
`supportRequire`, `supportUnique`, `compatibleOrmTypes`, `compatibleMysqlTypes`. Reserved
column names: `id`, `created_at`, `updated_at`, `properties`, `createdAt`, `updatedAt`.

**Values:** `defaultValue(values)`, `isValidData(data, validator)`, `dataValue(row)` (reads
`row[col]` or `row["<alias|objectName>.<col>"]`), `format(row)`, `isMultilingual`.
Server adds `dbPrefix()`, `conditionKey()`, `requestParam()`, migrations; browser adds
`columnHeader`, `formComponent`, `detailComponent`, `isValid`, `save` (which also calls the
migrate endpoints).

### 5.2 The 19 field types

**Keys are persisted in definition rows and are case-sensitive** (`AutoIndex`, `LongText`,
`TextFormula` are capitalized). Flags: F filterable, S sortable, Rq supportRequire, U
supportUnique, L useAsLabel ("fn" = depends on settings).

| Key | Menu name | F/S/Rq/U/L | Main settings (`defaultValues()`) | Stored value |
|---|---|---|---|---|
| `string` | Single line text | T/T/T/F/T | `default`, `supportMultilingual` | text, max 255 |
| `LongText` | Long text | T/T/T/F/T | `default`, `supportMultilingual` | text, max 5000 |
| `number` | Number | T/T/T/**T**/T | `typeFormat`, `typeDecimals`, `typeDecimalPlaces`, `typeRounding`, `typeThousands`, `validation`, `validateMinimum/Maximum` | number |
| `date` | Date | T/T/T/F/T | `dateFormat`, `defaultDate`, `defaultDateValue`, `validateCondition`, range settings | `YYYY-MM-DD` |
| `datetime` | Date & Time | T/T/T/F/T | date settings + `timeFormat`, `defaultTime`, `defaultTimeValue` | ISO-8601 UTC |
| `boolean` | Checkbox | T/**F**/T/F/T | `default` | 1 / 0 |
| `list` | Select list | fn/fn/T/F/T | `isMultiple`, `hasColors`, `options:[{id,text,hex,translations}]`, `default`, `multipleDefault` | option id, or array of options when multiple |
| `tree` | Data Tree | F/F/F/F/F | `options` | tree option data |
| `email` | Email | T/F/T/**T**/T | `default`, `defaultCheckbox` | text (regex-checked) |
| `file` | File Attachment | F/F/F/F/F | `removeExistingData`, `fileSize`, `fileType` | JSON `{uuid, filename}` |
| `image` | Image Attachment | F/F/F/F/F | `useWidth/imageWidth`, `useHeight/imageHeight`, `removeExistingData`, `useDefaultImage`, `defaultImageUrl` | SITE_FILE uuid |
| `user` | User | T/fn/F/F/T | `editable`, `isMultiple`, `isCurrentUser`, `isShowProfileImage`, `isShowUsername` | username(s); really a connect field to SiteUser |
| `connectObject` | Connect to another record | T/fn/F/F/F | `linkObject`, `linkType`, `linkViaType`, `linkColumn`, `isSource`, `isCustomFK`, `indexField`, `indexField2` | FK column or junction rows (§5.4) |
| `calculate` | Calculate | fn/F/F/F/T | `formula`, `decimalSign`, `decimalPlaces` | virtual (no column) |
| `TextFormula` | Text Formula | F/F/F/F/T | `textFormula` | virtual |
| `formula` | Formula | T/F/F/F/F | `field`, `object` (read) / `objectLink` (default, unused), `fieldLink`, `type` (sum/average/max/min/count), `where` | virtual (SQL or client) |
| `AutoIndex` | Auto Index | T/T/F/F/T | `prefix`, `delimiter`, `displayLength`, `previewText` | `INT UNSIGNED AUTO_INCREMENT UNIQUE` |
| `json` | JSON | F/F/F/F/T | none | JSON column |
| `combined` | Combined Field | T/F/F/F/T | `combinedFields` (comma-separated field IDs), `delimiter` | text column filled by MySQL BEFORE INSERT/UPDATE triggers (CONCAT) |

### 5.3 Per-type notes

- **string / LongText:** with `supportMultilingual=1`, per-language defaults live in
  `settings.translations`; a default containing `{uuid}` generates a UUID.
- **number:** `typeDecimals:"none"` means integer; min/max only checked when
  `validation`; formats `none, dollar, yen, pound, euroBefore, euroAfter, percent`;
  separators `none, comma, period, space`.
- **date / datetime:** `defaultDate` 2 = current date, 3 = specific date. Validation
  conditions `dateRange, between, notBetween, =, <>, >, <, >=, <=, lessCurrentDate,
  lessEqualCurrentDate`. Display uses Webix format codes (`webix.Date.dateToStr` in the
  browser). datetime `timeFormat` 2 = `%h:%i %A`, 3 = `%H:%i`; `dateFormat==1` = time only.
- **list:** multi-select lists cannot be filtered or sorted; the server converts option
  text to option ids in conditions.
- **connectObject:** `relationName()` = `"<col>__relation"` (or with alias for queries);
  `datasourceLink` / `fieldLink` raise `notify.builder` when missing; custom foreign keys
  use `indexField` / `indexField2`; sortable only for `one:many` and `one:one`.
- **user:** on first save the browser points it at SiteUser with `isCustomFK=1` (single:
  `one:many` keyed by username; multiple: `many:many`) and creates a reverse connect field
  on SiteUser (`developer/ab_platform_web/AppBuilder/platform/dataFields/ABFieldUser.js:13-53`).
- **calculate:** formula with `{column}` tokens and `(CURRENT)`; values are pasted in and
  the string is run with `eval()` (`ABFieldCalculateCore.js:216-287`). Helper functions
  are defined as `_AGE`, `_YEAR`, `_MONTH`, `_DAY`, `_DATE`, `_HOUR`, `_MINUTE`,
  `_MINUTE_TO_HOUR` (trap 9).
- **formula:** rolls up connected records through `settings.field` (connect field) to
  `settings.fieldLink`, optional `where` checked with FilterComplex.
- **TextFormula:** fills `{column}` tokens, then runs built-ins: left, right, mid, trim,
  trimLeft, trimRight, length, regexReplace, extractRegex, replace, lower, upper,
  capitalize, random, numberToWords, getDateDayOfWeekName, getDateMonthOfYearName,
  formatDate.
- **AutoIndex:** shown as prefix + delimiter + zero-padded number.
- calculate, formula, AutoIndex and combined remove their column from new-record defaults.

### 5.4 How connections are stored (server)

From `developer/appbuilder/AppBuilder/platform/dataFields/ABFieldConnect.js`:

| Link | Storage |
|---|---|
| 1:M (`one:many`) | FK column in this table |
| 1:1 (`one:one`, `isSource=1`) | unique FK column on the source side |
| M:1 (`many:one`) | FK column in the linked table |
| M:N (`many:many`) | junction table `AB_JOINMN_<src15>_<tgt15>_<col14>` (`rules.toJunctionTableNameFormat`; `settings.joinTable` overrides) |

---

## 6. Data collections (`ABDataCollectionCore.js`)

A data collection (DC) is the bridge between a datasource and widgets: it loads rows,
holds a cursor, filters, and applies realtime updates.

### 6.1 Settings (`fromValues` `:163-323`, `DefaultValues` `:12-39`)

| Setting | Meaning |
|---|---|
| `datasourceID` | An object id or query id (looked up as object first, then query) |
| `linkDatacollectionID` + `linkFieldID` | Parent DC and the connect field on **this** DC's object that points at the parent's object |
| `followDatacollectionID` | Copy the parent's cursor (only when link settings are empty) |
| `objectWorkspace.filterConditions` / `.sortFields` | Own filter (`{glue,rules}`) and sort (`[{key: fieldId, dir}]`) |
| `loadAll` | Load every row at once instead of paging |
| `populate` | `true`, `false` or a column list (legacy `preventPopulate` converted) |
| `fixSelect` | `_CurrentUser`, `_FirstRecord`, `_FirstRecordDefault` or a row id |
| `skipPack` | Disable server CSV packing |
| `select` | Column list sent as `cond.select` |
| `syncType` | 1 server / 2 client; nothing outside class_core reads it |

A grouped query (`isGroup`) gets a Webix TreeCollection.

### 6.2 Cursor

`setCursor(id)` does nothing when `fixSelect` is set (except `_FirstRecordDefault`)
(`:528-567`); `getCursor()` returns the row object; `setStaticCursor()` applies `fixSelect`
and emits `collectionEmpty` on no rows. The store is a Webix `DataCollection` (server: none).

### 6.3 Loading and paging

`loadData(start, limit)` (`:2369-2476`): set status `initializing`, wait for the link or
follow parent and for any DC named in `in_data_collection` rules, build
`cond = {where, skip, sort, populate, limit?, select?, skipPack?, jobID}`, call
`model.findAll`, then `processIncomingData` (parses in 250-row chunks, sets `total_count`,
refreshes link cursor, resolves). Browser default page size is **20**
(`developer/ab_platform_web/AppBuilder/platform/ABDataCollection.js:142`). Data loads lazily
on a widget's first `onShow`.

`getWhereClause()` combines the saved filter (or `__reloadWheres`), AND the temporary
`filterCondition()` (ABViewDataFilter), AND the link rule (`contains` for a query alias,
`have_relation` for `many:one`, otherwise `equals`) or, for follow DCs,
`PK equals followCursor[PK]`.

**`getData(fn)` only searches loaded rows** (a page, not the table). Guard every
`dc.getData((r) => r.id == x)[0]`.

### 6.4 Webix binding (browser)

`bind(component)`: datatable, dataview, treetable and kanban sync to the DC with
`datafetch 20` / `datathrottle 500` and request more pages through `loadNext`; other
widgets `component.bind(dc)` and follow the cursor. Linked DCs without `loadAll` use
`dc.bind(parent, fieldLink.id)` plus a `dataFeed` that reloads on parent cursor change.

### 6.5 Realtime

Socket events `ab.datacollection.create|update|stale|delete` are deduplicated for 5 s and
normalized once (`developer/ab_platform_web/resources/NetworkRestSocket.js:16-19,160-211`),
re-emitted on `AB`, and every DC handles them (`init()` `:804-2150`): add the row if it
passes this DC's filters (re-fetching joined rows for queries), replace or remove on update
depending on filters, patch relation and formula columns, emit `cursorStale` when the cursor
row changed. Three client-side filters decide validity (`refreshFilterConditions`
`:2923-3074`): the query's `where`, the DC's own filter + link rule, and the user's scopes
(`AB.Account.scopes()`). Linked children reload or recompute on the parent's `changeCursor`
/ `cursorStale`; followers clear and reload.

**Events emitted:** `changeCursor`, `collectionEmpty`, `create`, `update`, `delete`,
`cursorStale`, `cursorSelect`, `initializingData`, `loadData`, `initializedData`,
`warnRefresh`, `destroyed`.

---

## 7. Filters and conditions

### 7.1 Condition JSON

```
{ glue: "and" | "or", rules: [ { key, rule, value, alias? } | { glue, rules } ] }
```

`key` is a field id or column name; `alias` is for query columns; the key `this_object`
means "this record".

### 7.2 Operators offered per field type (`FilterComplexCore.fieldsToQB`, `:824-1014`)

Every field also gets `in_query_field` / `not_in_query_field`; connectObject and "this
object" get `in_query` / `not_in_query` instead.

| Field key | Operators |
|---|---|
| boolean | `checked`, `unchecked` |
| date, datetime | `less`, `greater`, `less_or_equal`, `greater_or_equal`, `is_current_date`, `less_current`, `greater_current`, `less_or_equal_current`, `greater_or_equal_current`, `last_days`, `next_days`, `is_empty`, `is_not_empty` |
| number, calculate, formula | `equals`, `not_equal`, `less`, `greater`, `less_or_equal`, `greater_or_equal` |
| string, LongText, AutoIndex | `contains`, `not_contains`, `equals`, `not_equal`, `is_empty`, `is_not_empty` |
| email | string set + `is_current_email`, `is_not_current_email` |
| list | `equals`, `not_equal` |
| user | `is_current_user`, `is_not_current_user`, `contain_current_user`, `not_contain_current_user`, `equals`, `not_equal` |
| connectObject | `same_as_user`, `not_same_as_user`, `in_data_collection`, `not_in_data_collection` (+ some string and query-field ops for 1:M / source 1:1) |
| this object (`uuid`) | `in_data_collection`, `not_in_data_collection` |

Extra sets: record rules `same_as_field` / `not_same_as_field` (client handler is a TODO
that returns true); process context `context_equals`, `context_not_equal`, `context_in`,
`context_not_in`.

### 7.3 Where they are evaluated

- **Client:** `FilterComplexCore.isValid(row, cond)` (`:144-243`) dispatches by field key.
  It cannot check `last_days`, `next_days`, `is_current_email`, `same_as_user`,
  `have_relation`, AutoIndex, combined or `this_object` (`uuid`): those evaluate false or
  null (trap 12). `RowFilterCore` is the legacy flat engine (no live caller).
- **Server:** `ABModel.parseCondition` turns rules into **raw SQL strings** quoted only by a
  local `quoteMe()` (`developer/appbuilder/AppBuilder/platform/ABModel.js:1157-1645`).
  Before parsing, five policies rewrite special rules (`in_data_collection`, M:N
  `is_current_user`, `same_as_user`, `in_query`, `in_query_field`), and `have_relation` is
  applied separately. Full operator list in [server-platform.md](server-platform.md).

---

## 8. Process query language (`ql/`)

A small chain of JSON operations stored in a BPMN Query task's `qlObj` and rebuilt with
`ABQLManager.fromAttributes` (`process/tasks/ABProcessTaskServiceQueryCore.js:36-50`). No
other caller. Saved form: `{key, params, objectID, next:{...}}` (`ql/ABQLCore.js:161-176`).

| key | Class | Params | Allowed next ops |
|---|---|---|---|
| `object` | ABQLRootObjectCore | `params.name` | `find` |
| `find` | ABQLFindCore | `params.cond` | `first`, `set_pluck`, `set_save` |
| `first` | ABQLSetFirstCore | none | `update`, `row_save`, `row_pluck` |
| `set_pluck` | ABQLSetPluckCore | `fieldID` | same as previous op |
| `set_save` | ABQLSetSaveCore | `task_param` | same as previous op |
| `update` | ABQLRowUpdateCore | `values` | same as previous op |
| `row_save` | ABQLRowSaveCore | `task_param` | none |
| `row_pluck` | ABQLRowPluckCore | `fieldID` | depends on the field type |
| `value_save` | ABQLValueSaveCore | `task_param` | same as previous op (no list points to it; likely unreachable) |

On the server each op's `do()` adds a `.then` step; `find` calls `findAll` after turning
`this_object` into `uuid` and `context_*` rules into plain rules with live process values;
the save ops call `task.stateUpdate(instance, value)`. See [processes.md](processes.md).

---

## 9. Multilingual

- `ABMLClassCore`: `mlFields` default `["label"]`; `translate()` copies the current
  language's values, else the first entry prefixed `"[<lang>]"`; `unTranslate()` writes
  them back. Default language: `en` on core/server, `AB.Account.language()` in the browser.
- Translatable properties: application `label`, `description`; object, query, DC, field,
  index `label`; hint `name`, `description`; step `name`, `text`; plus string/LongText
  `settings.default` and list/tree option `text`.
- **Row data:** multilingual string/LongText columns live in the row's `translations` JSON
  (`[{language_code, <col>: value}]`); `prepareMultilingualData` untranslates before
  writes, `normalizeData` translates on read, and the server queries them with
  `JSON_EXTRACT`.
- **UI labels:** a flat `en` map (`labels/en.js`) served by `appbuilder.labels`; other
  languages fall back to `en`.

---

## 10. Roles, scopes, models, tutorials

- **Roles and scopes** are rows in the system objects `objectRole()` (SITE_ROLE) and
  `objectScope()` (SITE_SCOPE), not class_core classes (`ABRoleCore`/`ABScopeCore` are dead
  code). The server's `pullScopes` gathers the scopes of the user's roles
  (`{filter, allowAll, objectIds}`) (`developer/appbuilder/AppBuilder/platform/ABObject.js:902-972`);
  the browser applies them as a DC filter. See [services.md](services.md#8-user_manager).
- **ABModelCore:** `count`, `staleRefresh` (200 ms buffer, one `findAll` by PK list),
  `findConnected`, `upsert` (no route), `csvPack/csvUnpack`, `normalizeData` (sets `.id`,
  parses `__relation`, translates, converts dates via `AB.rules.toDate`, computes calculate
  fields). **Browser `ABModel`:** `findAll` (GET), `create` (POST, fills defaults),
  `update` (PUT, **removes null values**, so a field cannot be cleared to null),
  `delete`, `batchCreate`, `batchUpdate`, `logs`. Over plain REST (not sockets) the model
  emits the `ab.datacollection.*` events itself.
- **Tutorials:** a hint (`{name, description, settings:{active, transition, showIntroStep,
  view}, stepIDs}`) holds steps (`{name, text, settings:{event:"click", el:<CSS selector>}}`).
  A view with `settings.hintID` shows a Webix `hint` widget on first show; steps target
  `[data-cy='...']` elements picked in the Tutorial Manager
  (`developer/ab_platform_web/ui/portal_tutorial_manager.js:1049-1080`).

---

## 11. Known traps and bugs

Verified in code unless marked inferred.

1. **Missing page references are deleted on save.** Unknown `pageIDs` only emit a warning
   during construction, and `toObj()` writes `pageIDs` from the instantiated pages
   (`ABApplicationCore.js:178-197,343`). This breaks the "parked, never dropped" rule the
   other ID lists follow.
2. **Query problem lists are reset after construction** (`ABObjectQueryCore.js:81-89`), so
   `__cantFilter` / `__missingFields` entries are not written back out; saving a query with
   problems can silently drop those fields (inferred).
3. **An unregistered field key breaks the object:** `newField` returns `undefined`, it is
   pushed into `_fields`, and `toObj()` then throws on `f.id` (inferred).
4. **Instances share objects with the definition cache:** `definitionByID` returns the
   stored json uncopied, and fields/objects/DCs mutate their settings in place (inferred
   impact: unsaved edits leak into the cache).
5. `ABFieldDateTimeCore.defaultValues()` mutates the Date class's default object, so plain
   date fields also get `timeFormat`/`defaultTime` settings (inferred).
6. Date bugs: `case (1, 2):` uses the comma operator (`ABFieldDateCore.js:372,384`);
   `notBetween` can never pass; the comparison checks call `startDate.getTime` without null
   checks.
7. Number display: `format()` always adds spaces around prefix/postfix; decimals are joined
   to an unrounded integer part (inferred).
8. "Required" checks let `""` through (`ABFieldCore.js:293-299`); email skips the base
   check.
9. **Calculate helper functions likely fail:** core defines `_AGE`, `_YEAR`, ... but the
   designer writes `AGE({col})`, `YEAR(CURRENT)` (`developer/plugins/ABDesigner/src/rootPages/Designer/properties/dataFields/ABFieldCalculate.js:335-381`)
   and nothing maps the names before `eval()` (`ABFieldCalculateCore.js:286`). Inferred
   (not run in a built bundle). `eval` also executes builder text with row values in it.
10. TextFormula without any `{column}` token returns `""`; `formatDate` ignores its format.
11. The formula field reads `settings.object`; the default `objectLink` is never read.
12. **Client filter gaps** (§7.3). Because DC socket handlers drop rows that fail
    `isValidData`, realtime updates may remove valid rows from DCs that use those rules
    (inferred).
13. **DC races:** the 100 ms incoming throttle can cancel a response whose page is then
    never parsed nor requested again (seen at runtime on 2026-10-02, see
    [frontend.md §10](frontend.md#10-traps) trap 28); concurrent first `loadData` calls can hang; query DCs
    never remove deleted rows (`:1797-1811`); `connection-added` is never forwarded in the
    browser; each browser `init()` adds `AB.on` listeners that are never removed (all
    inferred from code).
14. **Model:** `staleRefreshProcess` has no `.catch`, so one failed fetch blocks later
    stale refreshes on that model; browser `update()` drops nulls; `upsert` and
    `urlRestRefresh` have no route.
15. **Factory:** `init()` loads type `"step"` but `objectKeysByDef` matches `"steps"`
    (`ABFactoryCore.js:284,331`), so `AB.steps()` is always empty (hints still build their
    own steps); the core emits `definition.deleted` while the server emits
    `definition.destroyed`.
16. **API objects:** constructors run `fromValues` two or three times; NetSuite `SECRET:`
    credentials are unsupported; `appbuilder.model-get` builds a mock API object from a
    client-supplied `cond.url` when the object id is unknown and fetches it server-side
    (SSRF risk, inferred).
17. A missing translation shows as `"[th]Label"`, and saving from that language stores the
    prefixed text (inferred).
18. `ABObjectCore.displayData` uses the browser global `AB` and would throw on the server
    (inferred).
19. **Missing child views pile up in `viewIDs`.** `ABViewCore.fromValues()` appends every
    unknown id to `this.__missingViews` without clearing it first
    (`views/ABViewCore.js:209-216`), and `toObj()` writes the real ids plus that whole list
    (`:117-118`). Every later `fromValues()` on the same instance (inferred: each
    definition update) adds the same ids again, and the next save stores them. Nothing
    removes duplicates. `mobile/ABMobileViewCore.js:111`, `205-211` has the same code.
    Seen 2026-10-02 in the admin tenant: "Edit Responsibility.form" had 2,680 `viewIDs`
    (15 distinct; checked with `JSON_LENGTH(json,'$.viewIDs')` on
    `appbuilder_definition`, last updated 2025-11-12), so ABDesigner reported 2,672
    copies of the same 7 "references unknown View" warnings. Fix idea: reset
    `__missingViews` in `fromValues()` and de-duplicate in `toObj()`; clean the stored row
    once.
