# ABDesigner (the builder IDE)

ABDesigner is the browser IDE where builders design applications: objects and fields,
queries, data collections, pages and widgets, BPMN processes, mobile apps and version
notes. It is not a separate site. It is a v0 plugin that the portal loads for builders and
shows as the "AB Designer" entry in the sidebar ([frontend.md](../core/frontend.md) §2.6). Every
change it makes is a definition row saved through definition_manager
([architecture.md](../core/architecture.md) §2).

Verified on 2026-10-02 against ABDesigner `ca9b449` (branch `master`, "Update version
1.19.0"), plus the platform_web, class_core, api_sails and definition_manager code it
calls. This was a code read: no build, test or browser session was run for this page.
Path prefixes used below:

| Prefix | Expands to |
|---|---|
| `AD/` | `developer/plugins/ABDesigner/` |
| `DS/` | `developer/plugins/ABDesigner/src/rootPages/Designer/` |
| `PL/` | `developer/plugins/ABDesigner/src/plugins/` (the designer half of each widget) |
| `PW/` | `developer/ab_platform_web/` |
| `CC/` | `developer/appbuilder/AppBuilder/core/` |
| `AS/` | `developer/api_sails/` |
| `DM/` | `developer/definition_manager/` |

---

## 1. Where things are

`src/` holds about 310 files and 82,000 lines.

| Path | What it is |
|---|---|
| `AD/index.js` | Webpack entry; pushes the v0 plugin object onto `window.__AB_Plugins` (`AD/index.js:28-104`) |
| `AD/src/application.js` | The plugin "application" shown in the sidebar: id `ABDesigner`, label "AB Designer", icon `fa-connectdevelop`, one root page |
| `AD/src/definitions.js` | `[]`: the plugin ships no definitions |
| `AD/src/labels/` | Label files; `en.js` is empty |
| `PL/` | The designer half of the 21 widgets, `web_view_*` ([widgets.md](../core/widgets.md)) |
| `DS/` | The IDE itself (groups below) |
| `AD/src/utils/` | `CSVImporter.js` and `FieldTypeTool.js`, used by the new-object CSV and API tabs |
| `AD/styles/Designer.css` | Warning animations, list and tab styles |

| `DS/` group | Files | Purpose |
|---|---|---|
| Root | `ui.js`, `ui_class.js` | Root page (chooser or workspace) and the shared base class |
| App chooser | `ui_choose*.js` | Application list, create, edit, import, export, delete |
| Workspace shell | `ui_work.js` | Sidebar tabs and section switching |
| Objects | `ui_work_object*.js` (24) | Object list, new-object tabs, object workspace, popups |
| Queries | `ui_work_query*.js` (7) | Query list, new query, design builder |
| Data collections | `ui_work_datacollection*.js` (8) | DC list, new DC, properties, linked DC |
| Interface | `ui_work_interface*.js` (11) | Page tree, page editor, widget menu, property host |
| Process | `ui_work_process*.js` (11) | Process list, bpmn-js modeler, custom BPMN modules, monitor |
| PWA | `ui_work_pwa*.js` (7) | Mobile page and widget trees, preview, mobile properties |
| Version | `ui_work_version*.js`, `ui_version_list.js` | Change log and version bump |
| Shared UI | `ui_common_*.js`, `ui_warnings.js`, `interface_common/` | Lists, menus, manager picker, key/value, warnings |
| `editors/` | `EditorManager.js` + `views/` | Edit-mode editors for the interface (§7.4) |
| `properties/` | `PropertyManager.js` + `dataFields/`, `views/`, `process/`, `mobile/`, `rules/`, `workspaceViews/` | Property panels for fields, views, process elements, mobile views; rule builders |

**Dead files** (no live import; grep):

- In `DS/editors/views/` and `DS/properties/views/`, the old copies of most widgets
  (carousel, comment, data-select, dataview, docxBuilder, gantt, kanban, layout,
  pdfImporter, pivot, text and others). They appear only as commented-out imports in
  `EditorManager.js` and `PropertyManager.js`. The live versions are in `PL/`.
- `DS/properties/views/viewProperties/ABViewProperty.js` (it imports a path that does not
  exist), `DS/ui_work_version_workspace_properties.js`,
  `AD/src/webix_custom_components/formioBuilder.js` (moved to platform_web).
- `PL/web_view_csvImporter/CSVImporter.js` is used only by a test.

---

## 2. Build, registration and access

### 2.1 Build

- Webpack writes `developer/web/assets/tenant/default/ABDesigner.js`
  (`AD/webpack.common.js:6-11`). One file is shared by every tenant.
- `npm run watch` (dev config with source maps) is what you run by hand during
  development (AGENTS.md §2.0). `build` and
  `build:update` use the prod config with gzip (`AD/package.json:6-14`).
- There is **no `lint` script**, although `.eslintrc.js` exists. Report lint as not
  applicable (AGENTS.md §3).

### 2.2 Registration (v0 plugin)

1. **Who gets the script.** The api_sails preloader adds
   `/assets/tenant/default/ABDesigner.js?v=ecs` only when the user has the System Builder
   (`6cc04894-…`) or Builder (`e1be4d22-…`) role (`AS/api/controllers/SiteController.js:624-667`).
   Builders also get the tenant's v1 plugins of type `properties`, which is how
   object-property plugins such as NetSuite reach ABDesigner.
2. **Plugin object.** `AD/index.js` pushes
   `{version: "0.0.0", key: "ABDesigner", apply, definitions, labels, scripts, stylesheets}`
   (`AD/index.js:28-104`). The version string is hardcoded and differs from the package
   version.
3. **`apply(AB)`** runs after `AB.init()` (`PW/init/Bootstrap.js:402-405`). It registers 41
   designer factories through `AB.pluginRegister` and calls
   `AB.pluginLoad(ApplicationFactory(AB))` (`AD/index.js:39-58`). Each factory receives
   the platform plugin API plus `FABViewContainer` and `FABViewContainerEditor`
   (`PL/index.js:46-100`). ClassManager files each class as `properties-view`,
   `editor-view`, `object`, `properties-object` or `view`
   ([frontend.md](../core/frontend.md) §6.1).
4. **Menu entry.** The portal adds every plugin application with `pages` to the sidebar,
   next to the user's web apps (`PW/ui/portal_work.js:289-295`).

### 2.3 Root page

`DS/ui.js` behaves like an `ABViewPage` (`isRoot()` true, `type()` `"page"`). Its UI is a
multiview of the app chooser and the app workspace. On init it calls
`POST /definition/register`, which requires `validUser` and `validBuilder` and joins the
socket to the `abdesigner` room, so the browser receives live definition updates
(`DS/ui.js:72-102`; `AS/api/controllers/definition_manager/register-updates.js`).

### 2.4 Who can do what

| Layer | Check | Evidence |
|---|---|---|
| Script delivery | Builder or System Builder role | `AS/api/controllers/SiteController.js:624-667` |
| Portal page | `getUserAccess()` always returns 2 | `DS/ui.js:57-59` |
| Server writes | Every definition, migrate, export, import and register endpoint calls `req.ab.validBuilder()`, which accepts either builder role | `node_modules/@digiserve/ab-utils/utils/reqApi.js:473-495` |
| Inside ABDesigner | `AB.Account.isSystemDesigner()` (System Builder only) decides whether system apps, objects, DCs and processes are listed and whether "Information" menus appear | `PW/resources/Account.js:62-67` |

**The System Builder versus Builder split exists only in the browser.** The server
treats both roles the same, so a plain Builder can write system definitions through the
API. Verified code, inferred effect. Either role can also install plugins, which run as
server code ([api.md](../core/api.md) §9), so both must be trusted users.

### 2.5 How the code is organized

Every module is a factory, `export default function (AB) { … }`. `DS/ui_class.js` defines
one subclass of `AB.ClassUI` that stores `this.AB`, keeps `Current*ID` fields with getters
(`CurrentApplication`, `CurrentObject`, and so on), and provides
`L()` = `AB.Multilingual.labelPlugin("ABDesigner", …)` (`DS/ui_class.js:9-121`). Because
plugin labels are never consulted ([frontend.md](../core/frontend.md) §10 trap 10) and `en.js` is
empty, every ABDesigner label is its English source string.

---

## 3. The builder workflow

### 3.1 Application chooser (`DS/ui_choose_list.js`)

- **List.** Applications already in the factory, from `/definition/myapps`. For any default
  system role (System Admin, System Builder, Builder) the server returns **all**
  applications (`DM/handlers/definitionsForRoles.js:59-62`). Sorted by label; each row
  shows a warning count from `warningsAll()`.
- **Toolbar.** "Add new application" opens the popup in §3.2. "Import" uploads a file to
  `/definition/import` and then **reloads the whole page**. "Export All" opens
  `/definition/export/all?download=1`.
- **Gear menu.** Edit; Export (`/definition/export/<appID>?download=1`; the export drops
  the default role ids and clears role user lists, `DM/handlers/export-app.js:16-17`);
  Delete (`DELETE /definition/:id`).
- **Live refresh** from the factory events `definition.created`, `definition.updated` and
  `definition.deleted`.

### 3.2 New or edit application popup

Two tabs: Web App (`DS/ui_choose_form.js`) and Mobile App
(`DS/ui_choose_list_newApp_mobile.js`). In edit mode the other app type's tab is disabled.

| Web App field | Notes |
|---|---|
| `label` | Required, 1 to 20 characters. On create, `name = label`; duplicates are checked by `areaKey()` |
| `version` | Shown, but ignored on save (`version` is a read-only getter, `CC/ABApplicationCore.js:919-921`) |
| `icon` | From `AB.UISettings.icons` |
| `description` | |
| `isSystemObject` | Checkbox |
| `roleAccess` | "Who can use this app?" (all roles) |
| `isAccessManaged` + `accessManagers` | Page and tab access management |
| `isTranslationManaged` + `translationManagers` | Translation tool |
| `isTutorialManaged` + `tutorialManagers` | Tutorial tool |

The mobile form drops `isSystemObject`, access management and translation, and adds
`networkType` (`rest`, `socket`, `relay`). It creates the app with
`AB.applicationMobileNew(values)`. Mobile apps run in the PWA ([mobile.md](../core/mobile.md)).

### 3.3 How every save reaches the server

1. `instance.save()` runs `toDefinition().save()` (`PW/AppBuilder/platform/ABMLClass.js:97-104`).
2. `ABDefinitionCore.save()` calls `AB.definitionUpdate(id, …)` when the item has an id,
   otherwise `AB.definitionCreate(…)`; destroy calls `AB.definitionDestroy(id)`
   (`CC/ABDefinitionCore.js:73-88`).
3. The factory sends `POST /definition/create`, `PUT /definition/:id` (a "Not Found" reply
   becomes a create) or `DELETE /definition/:id`, and emits `ab.abdefinition.*` locally for
   instant feedback ([frontend.md](../core/frontend.md) §5.1).
4. api_sails maps these to `definition_manager.definition-create|update|delete` after
   `validBuilder` ([api.md](../core/api.md), [services.md](../core/services.md)).
5. **Schema changes are separate calls**, sent after the definition save:

   | Change | Request | Evidence |
   |---|---|---|
   | New or deleted object | `POST` / `DELETE /definition/migrate/object/:id` | `PW/AppBuilder/platform/ABObject.js:402-479` |
   | Field add, edit, drop | `POST` / `PUT` / `DELETE /definition/migrate/object/:objID/field/:ID` | `PW/AppBuilder/platform/dataFields/ABField.js:248-265` |
   | Index create, drop | `POST` / `DELETE /definition/migrate/object/:objID/index/:ID` | `PW/AppBuilder/platform/ABIndex.js:75-82` |
   | Query | The object endpoint; the server falls back to `queryByID` and runs the query's `migrateCreate` | `DM/handlers/migrate-object-create.js:55-76` |

6. **Membership lives on the parent.** For example, `objectInsert` adds the id to
   `app.objectIDs` and saves the app (`PW/AppBuilder/platform/ABApplication.js:93-140`).
   Creating an object is therefore at least three writes: the object row, the migrate
   call, and the app row.

What the server does with each call (DDL, events, broadcasts) is in
[server-platform.md](../core/server-platform.md) and [services.md](../core/services.md).

### 3.4 Application workspace (`DS/ui_work.js`)

A toolbar ("Back to Applications page" plus the app label) and a dark sidebar with
Objects, Queries, Data Collections, Process, Interface or PWA (by `application.isMobile`),
and Version. Each tab shows a warning count.

| Section | What the builder does | Details |
|---|---|---|
| Objects | Create, include, exclude, rename and delete objects; edit fields, indexes, label format and data | §4 |
| Queries | Create and include queries; joins, fields, filters, grouping | §5 |
| Data Collections | Source, links, filters, sort, load options | §6 |
| Process | BPMN modeling, element properties, instance monitor | §8 |
| Interface (web apps) | Page tree, widgets, layout, properties, preview | §7 |
| PWA (mobile apps) | Tabs, menu and widget trees, preview, mobile properties | §9.1 |
| Version | Change log and version bump | §9.3 |

---

## 4. Objects

### 4.1 Object list

- Gear menu: Rename (inline, then `save()`), Exclude (`app.objectRemove`), Delete, and
  Information for System Builders (`DS/ui_work_object_list.js:66-80`, `231-335`).
- **Delete** removes the object from every app, disables queries that use it, drops the
  table (unless the object is imported), destroys each field, then deletes the definition
  (`PW/AppBuilder/platform/ABObject.js:300-335`).
- **Information** shows the definition id, table name and column metadata from
  `GET /definition/info/object/:ID`.

### 4.2 Creating objects (`DS/ui_work_object_list_newObject.js`)

Save runs `AB.objectNew(values)` (the class is picked from `plugin_key`, `isExternal`,
`isImported`, `isNetsuite` or `isAPI`, `CC/ABFactoryCore.js:668-686`), validates, sets
`createdInAppID`, saves (which migrates), then calls `application.objectInsert(obj)`. On
error it removes the object from the app and tells the tab (`:261-319`).

| Tab | Settings | Notes |
|---|---|---|
| Create | `name`, `isSystemObject` | `primaryColumnName = "uuid"` |
| Import CSV | `name`, file, separator (comma, tab, semicolon, "space"), header row; per column: include, name, type (string, LongText, number, date, boolean) | Types guessed by `FieldTypeTool`. After the object saves, it creates the fields and inserts **every row from the browser, one `model.create()` at a time**. Broken today: see traps 1 and 2 |
| API | `name`; read-only forced on; only the "Read" sub-tab works. Request: GET only, URI, headers, paging (query string or headers), secrets. Response: data key, fields and types | Fields are saved with `skipMigrate`; `ABObjectApi.save()` never migrates (`PW/AppBuilder/platform/ABObjectApi.js:69-77`) |
| Existing | Objects this app does not include yet | `objectInsert(selectedObj)` |
| Plugin tabs | From each installed `properties-object` plugin, for example NetSuite | The plugin's own UI ([frontend.md](../core/frontend.md) §6.5) |

There is no "import existing table" or "external" tab in this build (commented out,
`:25`, `55-57`), although the factory still knows `ABObjectImport` and
`ABObjectExternal`.

### 4.3 Object workspace (`DS/ui_work_object_workspace.js`)

- **Toolbar:** Add field, Hide fields, Filters, Sort, Freeze, Label, Import, Export, and
  Edit (mass update) and Delete when rows are selected. An index bar ("Add Index" plus one
  button per index), workspace views ("New view" and a views menu), "Add new row", and a
  warnings panel (`:275-677`).
- **Record grid.** It reuses the runtime `ABViewGrid` with editing, mass update, delete
  and history forced on (`DS/ui_work_object_workspace_view_grid.js:61`). The grid loads 30
  rows at a time; kanban and gantt workspace views load all rows (`:1521-1560`).
- **Column header menu:** Hide, Filter, Sort, Freeze, Edit field, Delete field, and
  Information for System Builders. Delete field drops the column (unless the object is
  an API object), deletes the definition, and removes the field from every page
  (`:1009-1069`).
- **Column reorder** rewrites the object's field order and saves the object (`:147-157`).
- **Workspace views (grid, kanban, gantt) and their sort, filter, hidden and frozen
  columns are kept only in browser storage**, key `workspaceviews`, never in a definition
  (`DS/ui_work_object_workspace_workspaceviews.js:73`, `199-206`).
- **Label format** popup: click field tokens to build a template; it stores
  `object.labelFormat` with `{fieldId}` tokens and saves the object. See trap 3.
- **Custom index** popup: `name`, `fieldIDs`, `unique`.
- **Export** runs in the browser (`webix.toCSV`, `toExcel`, `toPDF`, `toPNG`). **Import**
  reuses the CSV importer widget's popup. **Record history** comes from
  `model().logs({rowId})`.
- **Read-only objects** (imported, external, read-only, API objects and every query)
  hide Add field, Import, Index and Add row (`CC/ABObjectCore.js:805-807`).

### 4.4 Field editor (`DS/ui_work_object_workspace_popupNewDataField.js`)

- A searchable picker of every field type (icon plus menu name). Edit mode opens that
  type's panel and disables controls marked `disallowEdit` (Unique is one).
- Imported objects can only add `connectObject` fields.
- On save: NetSuite objects copy `settings.netsuiteOneColumn` into `columnName`; column
  names with special characters are rejected; a default width is computed from the label.
- **New connect fields also create the reverse field** on the linked object. The column
  name is randomized on collisions and for many-to-many joins. Both fields are linked by
  `linkColumn`, saved, then migrated (`:453-597`).
- `field.save()` writes the definition, adds the field to the object (saving the object
  when the field is new), then migrates, except for connect fields (migrated by the
  popup) and API objects (`PW/AppBuilder/platform/dataFields/ABField.js:184-241`).
- **Making a field required when it has a default rewrites every NULL row from the
  browser**: it loads the rows whose value is NULL, then sends one `model.update` per row,
  all at once (`PW/AppBuilder/platform/dataFields/ABField.js:191-218`). The panel warns
  how many rows will change.

### 4.5 Field property panels (`DS/properties/dataFields/`)

All extend `ABField.js`, which supplies the common settings: `label`, `columnName` (locked
after creation), `showIcon`, `required`, `unique`, `validationRules` (a FilterComplex rule
list with a message) and a description. `isValid()` rejects reserved and duplicate column
names. The list is hardcoded in `DS/properties/PropertyManager.js:16-38`: fields cannot
be plugins. What each type does on the server is in
[server-platform.md](../core/server-platform.md); its core class is in
[domain-model.md](../core/domain-model.md).

| Panel | Key | Notable settings |
|---|---|---|
| `ABFieldAutoIndex.js` | `AutoIndex` | `prefix`, `delimiter`, `displayLength`, preview |
| `ABFieldBoolean.js` | `boolean` | `default` |
| `ABFieldCalculate.js` | `calculate` | `formula` builder (operators, number fields, date functions, age), `decimalSign`, `decimalPlaces` |
| `ABFieldCombine.js` | `combined` | `combinedFields`, `delimiter` |
| `ABFieldConnect.js` | `connectObject` | `linkObject`, `linkType` and `linkViaType`, `isCustomFK` with `indexField`/`indexField2`, `netsuiteOneColumn`. For NetSuite objects it lists columns from `GET /netsuite/table/:table` |
| `ABFieldDate.js` | `date` | `dateFormat`, `defaultDate` (none, current, specific), validation (range, between, comparisons, before or after today) |
| `ABFieldDateTime.js` | `datetime` | Date settings plus `timeFormat`, `defaultTime` |
| `ABFieldEmail.js` | `email` | `default` |
| `ABFieldFile.js` | `file` | `limitFileSize`/`fileSize` (MB), `limitFileType`/`fileType` |
| `ABFieldFormula.js` | `formula` | `type` (sum, max, min, average, count), `field` on a connected object, filter |
| `ABFieldImage.js` | `image` | Width, height, default image (uploaded to `/file/upload/<obj>/<field>/…`) |
| `ABFieldJson.js` | `json` | none |
| `ABFieldList.js` | `list` | `isMultiple`, `hasColors`, `options`, defaults |
| `ABFieldLongText.js` | `LongText` | `default`, `maxLength`, `supportMultilingual` |
| `ABFieldNumber.js` | `number` | `default`, `typeFormat`, decimals, rounding, thousands, min and max |
| `ABFieldString.js` | `string` | `default`, `maxLength`, `supportMultilingual` |
| `ABFieldTextFormula.js` | `TextFormula` | `textFormula` with field suggestions |
| `ABFieldTree.js` | `tree` | `options` tree |
| `ABFieldUser.js` | `user` | `isMultiple`, `isCurrentUser`, `editable`, `isShowProfileImage`, `isShowUsername` |

---

## 5. Queries

- **List:** Rename, Exclude (`app.queryRemove`), Delete.
- **New query:** "Create" takes a `name` and a base object from the app; "Existing" picks
  a query the app does not include. Save runs `AB.queryNew`, validates, sets
  `createdInAppID`, saves, then `app.queryInsert` (`DS/ui_work_query_list_newQuery.js:177-209`).
- **Workspace:** "Build Query" and "View Query" (the object workspace in read-only mode).
- **Design builder** (`DS/ui_work_query_workspace_design.js`):
  - Manage Objects: a tree of objects reachable through connect fields; checking a node
    adds a join.
  - Manage Fields: one tab per joined object, with the join type (`innerjoin`, `left`,
    `right`, `fullouterjoin`) and the included fields.
  - Grouping and "Hide prefix labels" checkboxes.
  - Filters: a FilterComplex that saves only when the condition is complete.
- **Save:** builds the nested `joins.links` tree, the fields, `where` and
  `settings {grouping, hidePrefix}`, calls `query.save()`, then `query.migrateCreate()`
  (`:587-732`). The preview loads 50 rows.

---

## 6. Data collections

- **List:** Rename, Exclude (`app.datacollectionRemove`), Delete.
- **New DC:** "Create" stores `{name, label, settings: {datasourceID, isQuery}}`;
  "Existing" picks one the app does not include.
- **Workspace:** a properties panel, a data preview (the object workspace grid) and a
  "Linked cursor" picker.
- **Every control change saves the DC definition at once**
  (`DS/ui_work_datacollection_workspace_properties.js:769-815`).

| Setting | Stored as |
|---|---|
| Source (object or query) | `datasourceID`, `isQuery` |
| Linked To | `linkDatacollectionID` |
| Linked Field | `linkFieldID` |
| Follow Cursor | `followDatacollectionID` (hides Load all and Select) |
| Filter Data | `objectWorkspace.filterConditions` |
| Sort Data | `objectWorkspace.sortFields` |
| Load all | `loadAll` |
| Load Connections | `populate`: true (all), false (none) or a list |
| Select (fixed cursor) | `fixSelect`: current user, first record, default to first record, or a row |
| Data used in… | Read-only list of the views bound to this DC |

How a DC behaves at runtime is in [frontend.md](../core/frontend.md) §5.4 and
[domain-model.md](../core/domain-model.md).

---

## 7. Interface (web apps)

### 7.1 Page tree (`DS/ui_work_interface_list.js`)

- Root pages and sub-pages only; widgets are not listed. Gear menu: Rename, Copy, Delete.
- **Add new page:** Parent Page and Name; the page is created with `parent.pageNew` or
  `app.pageNew` and saved. Saving a page also saves its parent
  (`CC/views/ABViewPageCore.js:214-229`).
- **Copy page:** Parent Page and Name, then `page.copy(null, parent, {newName})`. See
  trap 10.

### 7.2 Page editor

The workspace has the editor, a resizer, the properties panel, and warnings below
(`DS/ui_work_interface_workspace.js:39-99`).

- **Editor bar:** a back button with a history of up to 50 views, a breadcrumb, a
  **Preview** checkbox and an **Add Widget** button. The widget menu lists
  `CurrentView.componentList()`; picking one runs `newInstance(app, CurrentView).save()`
  (`DS/ui_work_interface_workspace_editor_components.js:135-220`).
- **Edit mode (the default)** mounts the editor registered for the view's key, falling
  back to `_default`. **Preview mode** renders the real runtime component, sized like a
  popup for popup pages (`DS/ui_work_interface_workspace_editor_layout.js:31`, `236-238`).
- **Container editor:** a Webix `dashboard`. Dragging or resizing writes `position` to
  every child view and then saves the parent (`DS/editors/views/ABViewContainer.js:223-248`).
- **Property host** (`DS/ui_work_interface_workspace_details_properties.js`): picks the
  panel whose key matches the view (plugin panels win over built-ins), merges its
  `values()` into the view on `changed`, and **saves 3 seconds later**. Pending saves are
  flushed when another view is selected and on `beforeunload` (`:40-104`, `188`).

### 7.3 Property panels

- **Plugin panels**, one per widget in `PL/web_view_<x>/` (list and settings in
  [widgets.md](../core/widgets.md)). Every panel also has the common Name field
  (`PW/AppBuilder/platform/plugins/ABViewPropertiesPlugin.js:45-78`).
- **Built-in panels** (`DS/properties/views/`, registered in
  `DS/properties/PropertyManager.js:80-118`):

  | Key | Settings |
  |---|---|
  | `conditionalcontainer` | `datacollection`, filter condition |
  | `viewcontainer` | `columns`, per-column `gravity` |
  | `data-filter` | `viewType`, `dataviewID`, `field`, `showFilter`, `showSort` |
  | `menu` | Orientation, button style, alignment, toolbar, padding, theme, position, texts, `pages` with drag-and-drop order and icons |
  | `page` | `type` (page or popup), popup size, `fixedPageWidth`, `pageWidth`, `pageBackground` |
  | `reportsManager` | `dataviewID`, field mapping, included DCs, `editMode`, tab hiding |
  | `scheduler` | Event DC and field mapping, calendar DC, timeline views |

- **Shared helpers** (`DS/properties/views/viewProperties/`): link page (`detailsPage`,
  `editPage`), add page (`formView`), edit page (`editForm`), filter data
  ([widgets.md](../core/widgets.md) §7).
- **No panel at all** for `connect-data-filter`, `detailconnect`, `detailselectivity` and
  `fieldreadonly`. Inferred: selecting one leaves the previous panel on screen, because
  the host replaces the panel only when it finds one (`:198-212`).

### 7.4 Edit-mode editors

- Built-ins (`DS/editors/EditorManager.js:13-44`): `_default`, `conditionalcontainer`,
  `viewcontainer`, `menu`, `page`, `tab`.
- Plugin editors for every widget except `list`. The registry is keyed by view key and the
  last one wins, so the plugin `tab` editor shadows the built-in one (inferred).

### 7.5 Rule builders

Used by the form, CSV importer and PDF importer panels:

- **Record rules** (`DS/properties/rules/ABViewRuleListFormRecordRules.js:41-44`): Update
  Record, Insert Connected Object, Update Connected Record, Remove Connected Record.
- **Submit rules** (`DS/properties/rules/ABViewRuleListFormSubmitRules.js:44-49`):
  confirmation message, redirect to a page, redirect to the parent page, close the popup,
  redirect to a website, send a custom email.
- Conditions use `ABViewQueryBuilderObjectFieldConditions`; the big value updater is
  `ABViewRuleActionObjectUpdater.js` (about 2,300 lines). Runtime behavior and its traps:
  [widgets.md](../core/widgets.md) §3.4 and §8.

---

## 8. Processes

The engine is in [processes.md](../core/processes.md); this is the designer.

- **List:** Rename, Exclude (`processRemove`), Delete. New process takes a `name`.
- **Tabs:** Model, Test, Monitor. **Test is a stub that throws** (trap 7).
- **Modeler:** bpmn-js `^9.0.3` with a custom renderer, palette (hand, lasso, space,
  start event, end event, exclusive gateway, task, pool) and replace menu that turns
  generic shapes into AppBuilder task types, plus an `ab` moddle extension
  (`SignalLifecycle`, `SignalTriggerTimer`) (`DS/ui_work_process_workspace_customBPMN*.js`).
- **Element panels** come from `PropertyManager.processElements()`, matched by key
  (`DS/properties/process/`):

  | Key | Settings |
  |---|---|
  | `End` | Name |
  | `GatewayExclusive` | Name; a label and filter per outgoing path |
  | `process.participant` | Name; by role, by account, or by field with a scope query |
  | `Email` | Name, to, from, subject, message |
  | `TaskService` | Picks one of the service tasks below |
  | `AccountingBatchProcessing`, `AccountingFPClose`, `AccountingFPYearClose`, `AccountingJEArchive` | Objects and field mappings for the accounting jobs ([database.md](../core/database.md)) |
  | `Api` | Name, URL, method, headers, body, secrets, response type; `<%= %>` templating |
  | `Calculate` | Name, formula |
  | `GetResetPasswordUrl` | Name, email |
  | `InsertRecord` | Name, `objectID`, repeat mode and column, a value per field |
  | `TaskServiceQuery` | Name, query rules |
  | `SubProcess` | Name, enable, repeat for |
  | `TaskUser` | Picks Approval, External or Form |
  | `Approval` | Name, who, data, a Form.io layout |
  | `External` | Name, who, `url` |
  | `Form` | Name, data, a Form.io layout |
  | `TriggerLifecycle` | Name, object, lifecycle (after add, update or delete) |
  | `TimerStartEvent` | Name, repeat every, time, weekdays, day of month, enable |

- **Saving:** any diagram change shows a **Save** button. Save copies the open panel into
  the element, then `saveXML()`, `process.modelUpdate(xml)` and `process.save()`, which
  saves **every element definition and then the process**
  (`DS/ui_work_process_workspace_model.js:326-346`;
  `PW/AppBuilder/platform/ABProcess.js:87-98`). Switching processes with unsaved changes
  asks first.
- **Deleting a shape destroys its element definition at once** (`:455-466`), while the
  diagram saves only on Save (trap 9).
- **Monitor:** instances filtered by status (completed, created, error) with ID, dates,
  job ID, status, logs, context and errors. Reset (errored only) sends
  `PUT /process/reset/<taskID>`; there is also a Delete button.

---

## 9. Mobile, translations, tutorials and versions

### 9.1 PWA designer (`DS/ui_work_pwa*.js`)

- Three columns: list, preview and properties.
- The list has trees for **Tabs**, **Menu Items** and **Widgets**, with drag-and-drop
  reorder and re-parent (`pageRemove`, `pageInsert`, then save).
- New page takes a `label`; Add Widget uses `componentList()`, then
  `newInstance(...).save()`.
- The preview is an iframe of
  `${origin}/mobile/app/${tenantID}/${appID}?route=<route>` (`DS/ui_work_pwa_display.js:155-181`).
- Properties use `PropertyManager.mobileViews()` with the same 3-second delayed save as
  the web interface (`DS/ui_work_pwa_properties.js:38-88`).

Mobile panels (`DS/properties/mobile/`): `mobile-page`, `mobile-custom` (a CodeMirror 6
JavaScript editor), `mobile-form`, `mobile-button`, `mobile-connect`, `mobile-date`,
`mobile-datetime`, `mobile-email`, `mobile-numberbox`, `mobile-selectsingle`,
`mobile-selectmultiple`, `mobile-textbox`, `mobile-checkbox`, `mobile-fieldcustom`,
`mobile-file`, `mobile-formula`, `mobile-image`, `mobile-fieldreadonly`, `mobile-label`,
`mobile-list`, `mobile-timeline`. Their settings and runtime behavior are in
[mobile.md](../core/mobile.md) §7.

### 9.2 Translations, tutorials and page access

ABDesigner has **no translation or tutorial tool**. It only stores the flags and
managers on the application (§3.2); each manager picker records `useRole` + `role` and
`useAccount` + `account` (`DS/ui_common_participant_selectManager.js:55-262`). The tools
themselves are in the portal's cog menu ([frontend.md](../core/frontend.md) §4.2).

### 9.3 Version log

- Lists `application.json.versionData.changeLog` (seeded with `1.0.0`, "Initial
  Version").
- The form takes author, release notes, version (with major, minor and patch
  suggestions), date and "Force keep this version", then saves the application
  (`DS/ui_work_version_workspace.js:62-395`).
- "Rollback module to this version" (hidden) and "Export" have no click handler.

---

## 10. Shared UI pieces

- **Base classes.** `AB.ClassUI` (ids, events, `data-cy` tags, warning icon);
  `DS/ui_class.js` (`Current*` getters, `L()`, `warningsRefresh`, `warningsPropogate`);
  the property bases `DS/properties/dataFields/ABField.js`,
  `DS/properties/views/ABView.js`, `DS/properties/mobile/ABMobileView.js`.
- **Events.** Plain EventEmitter events between components (`view.workplace`,
  `view.chooser`, `warnings`, `selected`, `save`, `save.successful`, `save.error`,
  `changed`, and others), plus the factory's `definition.*` events.
- **Warnings.** Definitions implement `warningsEval()` / `warningsAll()` (for example, the
  app checks missing objects, queries and DCs, and roles). Counts bubble up to the
  sidebar, list icons, breadcrumbs and the "Show Issues" panel (`DS/ui_warnings.js`).
- **Lists and menus.** `DS/ui_common_list.js` (search, sort, group, rename, delete,
  exclude) and `DS/ui_common_popupEditMenu.js` (the gear menu).
- **Filters.** `AB.filterComplexNew` is used in 15 files; `AB.Class.SortPopup` for
  sorting.
- **Registries.** `DS/properties/PropertyManager.js` (fields, process elements, views,
  mobile views) and `DS/editors/EditorManager.js` (edit-mode editors). Both merge in
  ClassManager plugin classes.

---

## 11. Tests and CI

- `npm test` runs mocha with `@babel/register` and `test/_setup.js`, which stubs CSS,
  `bpmn-js`, `PropertyManager` and a few modules and creates jsdom `webix` and `$$` mocks
  (`AD/package.json:10`; `AD/test/_setup.js:6-84`).
- 15 test files with 96 `it(` cases (grep): CSV importer plugin, DC section, CSV
  new-object tab (constructor, ui and init only), process section, query section, and
  `CSVImporter`. The CSVImporter test imports the plugin copy, not the copy the app uses.
  Nothing tests the object workspace, field panels, interface, process modeler, PWA or
  version code. Not run for this page.
- CI: `merging-rules.yml` (npm test, then e2e on PRs into `master`); `e2e-test.yml`
  (builds into an ab_service_web checkout, installs with `CruGlobal/ab-install-action@v1`,
  runs `npm run test:e2e:ab-designer`); `pr-merge-release.yml` (version bump, release, and
  a `web_new_version` dispatch to ab_service_web).

---

## 12. Traps

**Verified** means the code says so. **Inferred** means the effect is reasoned from the
code and was not run.

Objects and fields:

1. **The "Import CSV" new-object tab is broken.** Its `save.successful` listener calls
   `this.onSuccess()` with no argument, but `onSuccess(newObj)` immediately uses
   `newObj` (`DS/ui_work_object_list_newObject_csv.js:179-181`, `381`). The emit is
   synchronous, so the TypeError lands in the parent's `catch`, which removes the object
   from the app (`DS/ui_work_object_list_newObject.js:300-318`). Verified code. Inferred
   effect: the object row and its table exist, but are not in the app and have no columns
   or rows.
2. **The CSV "Space" separator splits on the letter `s`** (option id `"s"`,
   `AD/src/utils/CSVImporter.js:21`, `106`). The runtime CSV importer widget has the same
   bug ([widgets.md](../core/widgets.md) §8 trap 16). Verified.
3. **Saving a label format reports an error after it succeeded.** The handler calls
   `this.callbackDefineLabel()`, which is commented out (`DS/ui_work_object_workspace.js:191`,
   `794`). Verified code, inferred effect.
4. **System apps are not hidden from plain Builders.** The filter checks
   `app.isSystemObj`, but the property is `isSystemObject`
   (`DS/ui_choose_list.js:457`; `CC/ABApplicationCore.js:104`). The same typo in the query
   builder (`DS/ui_work_query_workspace_design.js:470`) means system objects are always
   hidden from the join tree. Verified (no `isSystemObj` exists anywhere).
5. **Object workspace views live only in one browser** (`workspaceviews` in local
   storage; a quota error is swallowed). Another builder or browser will not see them.
   Verified.
6. **Bulk writes come from the browser, one request per row.** Making a field required
   with a default fires one update per NULL row, all at once (§4.4); the CSV new-object
   import creates rows one at a time. Slow and fragile on big tables. Verified.
7. **NetSuite credentials go in a GET query string**
   (`GET /netsuite/table/:table?credentials=…`, `DS/properties/dataFields/ABFieldConnect.js:667-671`).
   By default the values are `ENV:<NAME>` references, so only names leak into URLs and
   logs; a builder who types a raw secret leaks the secret. Separately, the server
   resolves **any** `ENV:<name>` in any credential field (`pullCredentials()`,
   `developer/appbuilder/AppBuilder/platform/ABModelApiNetsuite.js:866-880`), and
   the base URL can be a plain value the builder types. Inferred, not tested: a builder
   could point a key field at another secret (for example the database password) and send
   it to a host of their choice. Verified code; the security effect is inferred. For
   scale: any builder can already run server code through `POST /definition/plugin/add`
   ([api.md](../core/api.md) §9), so the builder role must be treated as fully trusted.
8. **API response field clearing never works**: `_clearFieldItems()` reads an undefined
   `this.ids.connections` (`DS/ui_work_object_list_newObject_api_read_response.js:268`).
   Verified.

Process:

9. **The Test tab throws.** `TestUI` is a mock with no `ids`, and selecting the tab reads
   `TestUI.ids.component` (`DS/ui_work_process_workspace.js:12-22`, `206`). Verified.
10. **Shape deletes are immediate, diagram saves are not.** Undo, or leaving without
    saving, can leave the XML and the element rows out of step (`:455-466`). Inferred.
11. **Unconfigured tasks are not visibly marked**: the `highlight-undefined-task` marker
    has no CSS anywhere. Verified (grep).

Interface:

12. **Copy page is fragile.** Parent options use `page.id`, but save calls
    `urlResolve()`, which expects a `#/…` pointer, so the copy lands at the root
    (`DS/ui_work_interface_list_copyPage.js:154`, `265`). Each Copy click rebuilds the
    window and adds listeners again, and errors are swallowed. Verified code, inferred
    effect.
13. **Property edits save 3 seconds late.** A crash or killed tab inside that window loses
    them; the flush relies on `beforeunload`. Verified.
14. **Add Widget has no error path**: `newComp.save().then(...)` has no `catch`, so the
    editor stays busy if the save fails. Verified.
15. **"Data used in…" does nothing**: it emits `interface`, which nobody listens to.
    Verified.
16. **An incomplete DC filter wipes the filter** (it resets to empty,
    `DS/ui_work_datacollection_workspace_properties.js:1113-1126`). Verified.
17. **Many small writes per action.** A container drag saves every child plus the parent;
    a process save writes every element; a page save writes the page and its parent.
    Verified.

App level and general:

18. **Sidebar and list settings never restore.** `AB.Storage.get()` returns a Promise,
    but `ui_work.js` and `ui_common_list.js` use it as a value
    (`DS/ui_work.js:357`; `DS/ui_common_list.js:332`; `PW/resources/StorageLocal.js:51-54`).
    Verified.
19. **The ABDesigner bundle URL never changes** (`?v=ecs`), so after a rebuild a browser
    may keep the old bundle until a hard refresh. Verified.
20. **App import reloads the whole page**, losing unsaved edits elsewhere. Verified.
21. **The mobile app form still offers the retired `relay` network type**
    (`DS/ui_choose_list_newApp_mobile.js:539`) and sets `apptype: "web"` on mobile apps
    (the real field is `appType`). Verified.
22. **The web app form piles up tutorial-manager views**: `formReset()` adds a new one
    without removing the old (`DS/ui_choose_form.js:1015`). Verified.
23. **The gear menu's header flags are ignored.** `imported` flags on the column menu are
    declared but never copied, so Edit and Delete field still show for imported fields.
    Verified.
24. **The duplicate-column message prints "undefined"** (`DS/properties/dataFields/ABField.js:877`).
    Verified.
25. **Warnings HTML is not escaped**: messages that include builder-entered labels go
    through `setHTML` (`DS/ui_warnings.js:105`). Builders only. Verified.
26. **Build nits.** `url-loader` is referenced in `AD/webpack.common.js:29` but not
    installed (the rule never fires, inferred); `semver` is declared but unused; the
    plugin reports version `"0.0.0"`; `.gitignore` uses `//` "comments", which git reads
    as patterns. Verified.

Widget-panel traps (reversed system filters, the label panel, dead copies) are in
[widgets.md](../core/widgets.md) §8.

---

## Open questions

1. Do traps 1, 3, 9 and 12 reproduce in the running stack? They follow from the code but
   were not exercised.
2. What does the external NetSuite `properties-object` plugin look like, and which
   tenants have it installed?
3. Is the `test:e2e:ab-designer` suite that CI runs the same one AGENTS.md §3 calls broken
   (0 specs here)? CI runs it inside an ab-install checkout, so the layout may differ.
4. Resolved 2026-10-02: a query's `migrateCreate` creates a SQL view
   `AB_<App>_View_<Query>` ([server-platform.md §4.3](../core/server-platform.md#43-query-objects-platformabobjectqueryjs)).
5. Do the bpmn-js fonts resolve at runtime? With `css-loader url: false`, the bundle keeps
   relative `../font/bpmn.*` URLs; the font files exist under
   `developer/web/assets/font/`.

---

## 13. Walkthrough: building an app from scratch (observed)

Done on 2026-10-02 in the local `admin` tenant through the ABDesigner UI, watching the
logs and the database. The result is the **Claude Sandbox** app (`0f7fe184-…`), a
sandbox for experiments: AGENTS.md §2.0 forbids changing the tenant's existing
definitions, so use this app (or another new one) to try definition changes.

| Step in the UI | What happened behind it |
|---|---|
| Add new application: name, description, "Who can use this app?" = System Admin | One `application` definition. Without a role the app would not show in the portal sidebar |
| Objects → Add new object → Create, name "Sandbox Task" | `POST /definition/create` (object), `POST /definition/migrate/object/:id` (about 1.2 s), app definition updated. Table `AB_ClaudeSandbox_SandboxTask` (`AB_<App>_<Object>`, spaces removed) with only `uuid` (PK), `created_at`, `updated_at`, `properties`. The object warns "has no fields" until a field exists |
| Add field → Single line text "Title", required | `POST /definition/create` (field), `PUT /definition/<object>`, then `POST /definition/migrate/object/<obj>/field/<field>`: `ALTER TABLE` adds `Title varchar(255) NULL` (nullable, because "required" without a default stays nullable) |
| Add field → Long text "Notes" | Same three calls; this time the migrate call took 100 ms |
| Data Collections → Create "All Tasks" on Sandbox Task | One `datacollection` definition. The object picker lists only objects included in this app |
| Interface → Add new page "Tasks" (root) | `view` definition of key `page`; the app saves too |
| Add Widget → Grid, tick edit and delete, Datacollection = All Tasks | `grid` view; property edits are saved about 3 s after the last change (§7.2) |
| Add Widget → Form, Datacollection = All Tasks, Clear on save | `form` view plus one child per field (`textbox` ×2) and a `button`, created automatically |

Opening the app in the portal and saving the form produced this trail (one job id across
services):

1. api_sails: `POST /app_builder/model/<object>` → policies → `appbuilder.model-post`.
2. appbuilder: insert, then "create() successful. Now loading full value from DB."
3. api_sails: `api.broadcast-register` for the new row, then `api.broadcast`
   `ab.datacollection.create` to room `admin-<row uuid>`; the reply to the browser came
   after 168 ms.
4. After the reply (fire and forget): `process_manager.trigger` ("triggered 0 tasks") and
   `log_manager.rowlog-create`. They took 1 to 2 s, mostly creating the cote clients for
   those services the first time.
5. The grid on the same page showed the new row without a reload (socket event).

Things seen on the way (all in [known-issues.md](../known-issues.md)):

- The first "Title" migrate call took **41 s** in definition_manager. api_sails gave up
  after 25 s (5 tries × 5 s), and the field popup stayed busy forever; the column had been
  created anyway. Not reproduced: the next field took 100 ms. Cause unknown (R21, W18).
- The Add Widget menu of a brand-new app offers **HR Teams**, the widget meant only for
  NetSuite HR Update (W20).
- The browser console repeats `Error parsing JSON data for column: objectIds` for
  `SITE_SCOPE` rows (W19).
- A new form widget whose data collection is not set yet makes `warningsEval` **throw**
  (`ABViewCore:get datacollection(): View[form] didn't define a dataviewID`) instead of
  listing a warning; the error repeats in the console while the designer redraws (W21).
- Screenshots of the automation tab often lag, because the tab is hidden; read the DOM
  instead ([testing.md §3.3](../testing.md#33-driving-the-browser-with-automation)).
