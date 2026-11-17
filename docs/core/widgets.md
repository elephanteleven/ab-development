# Web widgets (view types)

A builder places widgets on pages. Each widget is a view definition with a stored `key`
(for example `grid`) and a `settings` object. This page lists every web widget, its
settings and their defaults, and what it does at runtime. Mobile view types (`mobile-*`)
are in [mobile.md](mobile.md). The portal that renders widgets is in
[frontend.md](frontend.md), and the designer that edits them is in
[abdesigner.md](../plugins/abdesigner.md).

Verified on 2026-10-02 against platform_web `560b6d80` and ABDesigner `ca9b449` (both on
`master`). This was a code read: no widget was exercised in a browser for this page. Path
prefixes used below:

| Prefix | Expands to |
|---|---|
| `included/` | `developer/ab_platform_web/AppBuilder/platform/plugins/included/` (runtime half) |
| `designer/` | `developer/plugins/ABDesigner/src/plugins/` (designer half) |
| `views/` | `developer/ab_platform_web/AppBuilder/platform/views/` (core views and helpers) |
| `rules/` | `developer/ab_platform_web/AppBuilder/rules/` |

"DC" means the data collection a widget reads, stored in `settings.dataviewID`.

---

## 1. How a widget is built

- **Two halves in two repos.** The runtime half (view class plus component) lives in
  `included/view_<x>/`. The designer half (property panel plus edit-mode editor) lives in
  `designer/web_view_<x>/`. Both are v1 plugin factories, `(pluginAPI) => Class | Class[]`
  ([frontend.md](frontend.md) §6).
- **Runtime registration.** `included/index.js` lists the 21 modules and calls
  `AB.pluginRegister` on each during core init (`included/index.js:1-53`). The view class
  extends `ABViewWidgetPlugin` (type `view`) and declares `common()` (`key`, `icon`,
  `labelKey`) and `defaultValues()` (the settings defaults). Its component extends
  `ABViewComponentPlugin`. Modules that own sub-views return an array: chart returns
  `[chart, area, bar, line, pie]`; form returns the form, `form-url` and every field
  sub-view; detail returns the detail and its items.
- **Designer registration.** `designer/index.js` registers a properties class
  (`getPluginType()` is `"properties-view"`; extends `ABViewPropertiesPlugin`) and usually
  an editor class (`"editor-view"`; extends `ABViewEditorPlugin`), both keyed by the widget
  key (`designer/index.js:40-100`). `list` has no editor, so the designer falls back to
  its `_default` editor.
- **Core views.** Nine view keys are still built into class_core instead of plugins:
  `view`, `page`, `viewcontainer`, `menu`, `data-filter`, `connect-data-filter`,
  `conditionalcontainer`, `reportsManager` and `scheduler`
  (`developer/ab_platform_web/AppBuilder/core/ABViewManagerCore.js:1-130`). See §6.
- **Lookup order.** `ABViewManager.newView` asks the plugin registry first, then core
  (`developer/ab_platform_web/AppBuilder/platform/ABViewManager.js:10-24`), so the
  built-in widgets keep their historic keys. A **new external** widget's key must start
  with `plugin_`; otherwise every definition that uses it logs "not yet defined" until
  the plugin loads ([frontend.md](frontend.md) §6.4).
- **Keys are stored in definitions.** Renaming a widget key breaks every page that uses it
  (AGENTS.md §6).
- **Layout.** Children of a container carry `position` `{x, y, dx, dy}`, and the container
  lays them out in `settings.columns` with a `gravity` per column
  ([frontend.md](frontend.md) §5.6).

---

## 2. Index

| Key | Icon | What the user sees | Runtime folder | Designer folder |
|---|---|---|---|---|
| `grid` | table | Data table with toolbar, inline edit, mass update and export | `view_grid` | `web_view_grid` |
| `form` | list-alt | Data entry form | `view_form` | `web_view_form` |
| `detail` | file-text-o | Read-only record | `view_detail` | `web_view_detail` |
| `list` | list-ul | List of one field | `view_list` | `web_view_list` (properties only) |
| `dataview` | th | Cards that repeat child views per row | `view_dataview` | `web_view_dataview` |
| `layout` | columns | Columns container | `view_layout` | `web_view_layout` |
| `tab` | window-maximize | Tabs, or a sidebar | `view_tab` | `web_view_tab` |
| `label` | font | Static text | `view_label` | `web_view_label` |
| `text` | font | Template text with field placeholders | `view_text` | `web_view_text` |
| `image` | picture-o | Static image | `view_image` | `web_view_image` |
| `carousel` | clone | Image carousel over an image field | `view_carousel` | `web_view_carousel` |
| `data-select` | chevron-circle-down | Combo that moves a DC cursor | `view_data-select` | `web_view_data-select` |
| `comment` | comments | Comment thread | `view_comment` | `web_view_comment` |
| `csvExporter` | download | Server-side CSV export button | `view_csvExporter` | `web_view_csvExporter` |
| `csvImporter` | upload | CSV upload, column mapping, preview, import | `view_csvImporter` | `web_view_csvImporter` |
| `pdfImporter` | file-pdf-o | PDF pages stored as images | `view_pdfImporter` | `web_view_pdfImporter` |
| `docxBuilder` | file-word-o | Word file built from a template | `view_docxBuilder` | `web_view_docxBuilder` |
| `gantt` | tasks | Webix Gantt | `view_gantt` | `web_view_gantt` |
| `kanban` | columns | Webix Kanban | `view_kanban` | `web_view_kanban` |
| `pivot` | cube | Webix Pivot | `view_pivot` | `web_view_pivot` |
| `chart` (+ `area`, `bar`, `line`, `pie`) | bar-chart | Chart container and its chart types | `view_chart` | `web_view_chart` |

Sub-views: form fields (§3.3) and detail items (§3.5). Core views: §6.

---

## 3. Data widgets

### 3.1 Grid (`grid`)

Files: `included/view_grid/FNAbviewgrid.js`, `FNAbviewgridComponent.js` (about 2,400
lines), `ABViewGridPopupExport.js`, `ABViewGridPopupMassUpdate.js`. It uses the filter
helper, the link-page helper and the sort popup (§7).

| Setting | Default | Meaning |
|---|---|---|
| `label` | `""` | Widget label |
| `dataviewID` | `""` | The DC that drives the grid |
| `padding` | 17 | Padding around the grid |
| `showToolbar` | 1 | Show the toolbar |
| `isEditable` | 0 | Inline editing |
| `massUpdate` | 0 | Row checkboxes plus the mass update popup |
| `allowDelete` | 0 | Trash column plus mass delete |
| `isSortable` | 1 | Sort button |
| `isExportable` | 0 | Export button |
| `detailsPage` / `detailsTab` | `""` | Page (and tab) that shows the details view |
| `editPage` / `editTab` | `""` | Page (and tab) with the edit form |
| `trackView` | 0 | Change-history column |
| `frozenColumnID` | `""` | Freeze columns up to this one |
| `hiddenFields` | `[]` | Hidden columns |
| `summaryColumns` / `countColumns` | `[]` | SUM and count footers |
| `objectWorkspace` | copies of the four settings above | Legacy, marked "TODO: get rid of" |
| `gridFilter` | `{filterOption 1, userFilterPosition "toolbar", isGlobalToolbar 1}` | Filter helper settings (§7) |
| `height` | 0 | Grid height |
| `hideHeader` | 0 | Hide the header row |
| `labelAsField` | 0 | Add a label column |
| `hideButtons` | 0 | Hide the detail-view icon column |
| `groupBy` | `""` | Field(s) to group into a tree |
| `columnConfig` | `[]` | Column order and widths saved by the designer |
| `saveLocal` | 1 | Keep each user's column changes in the browser |

Evidence: `included/view_grid/FNAbviewgrid.js:22-159`; `fromValues` parses the numeric
flags and migrates the `objectWorkspace` copies (`:234-338`).

What it does (`included/view_grid/FNAbviewgridComponent.js`):

- **Toolbar:** Edit (mass update), Delete selected, Filters (with a badge), Sort, Export,
  and a global search box that drives the filter helper (`:453-541`, `796-838`).
- **Table:** a datatable, or a treetable when `groupBy` is set. Rows are selectable when
  the grid is not editable and has a details or edit page; otherwise cells are
  (`:189-199`).
- **Extra columns:** label column (`labelAsField`), row checkbox (mass update at access
  level 2), eye icon (details page), history, pencil (edit page), trash (`allowDelete`)
  (`:1991-2063`). `frozenColumnID` becomes Webix `leftSplit` (`:2095-2102`).
- **Clicks:** eye opens the details page with the cursor set; pencil opens the edit page;
  trash asks, then calls `model().delete`; other clicks go to the details or edit page
  (`:695-793`).
- **Inline edit save:** normalizes numbers and dates, enforces `maxLength`, runs
  `isValidData`, then `model().update(id, {column: value})`. Errors go to
  `AB.Validation.isGridValidationError` (`:1355-1516`).
- **Column validation rules** use a FilterComplex per column, applied as datatable `rules`
  (`:1813-1968`).
- **Footers:** sum and total (calculate and formula fields) and count, through the
  `countfooter` and `totalfooter` custom views (`:1793-1800`).
- **Files, images and connections** are drawn by each field's `customDisplay` on the
  visible rows; image columns set the row height from `imageHeight` (`:619-691`,
  `1715-1722`).
- **Column layout** is saved in browser Storage `abviewgrid_settings`, key
  `<viewId>-<objectId>`, when `saveLocal` is on. Minimum column width is 30
  (`:1250-1295`, `1571-1626`).
- **Filtering** sets `dc.filterCondition(rules)` and reloads the DC (`:884-899`).
  **Sorting** is done in the browser; on a partly loaded DC it first reloads every row
  (`:901-928`).
- **Export popup:** CSV, Excel, PDF or PNG through `webix.toCSV/toExcel/toPDF/toPNG`, for
  the checked rows (or all rows when none are checked), without hidden fields
  (`ABViewGridPopupExport.js:56-229`).
- **Mass update:** RowUpdater values sent with `model().batchUpdate({rowIds, values})`
  (`ABViewGridPopupMassUpdate.js:146-238`). **Mass delete** calls `model().delete` per row
  in parallel and waits for realtime events to remove the rows (`:2241-2286`).
- **Events:** `selection`, `selection.cleared`, `column.resize`,
  `column.header.clicked`, `object.track`.

### 3.2 Form (`form`)

Files: `included/view_form/FNAbviewform.js`, `FNAbviewformComponent.js`, 14 field
sub-components, and `core/` factories. It publishes `AB.Class.ABViewForm` and
`AB.Class.ABViewFormItem`.

| Setting | Default |
|---|---|
| `dataviewID` | null |
| `showLabel` | true |
| `labelPosition` | `left` |
| `labelWidth` | 120 |
| `height` | 200 |
| `clearOnLoad` | false |
| `clearOnSave` | false |
| `displayRules` | `[]` (nothing in platform_web reads it) |
| `editForm` | `none` |
| `recordRules` | `[]` (§3.4) |
| `submitRules` | `[]` (§3.4) |

Evidence: `included/view_form/core/ABViewFormCore.js:13-54`. Only label, layout, button
and text widgets can be dropped inside a form.

**Showing data** (`FNAbviewformComponent.js:161-572`): on `changeCursor` or `cursorStale`
the form fills its fields from the cursor row (date pickers 200 ms later). It disables
itself during `initializingData`. The parent DC's cursor pre-fills the link field. With no
row, each field shows its `defaultValue`. `onShow` applies `clearOnLoad`. Below access
level 2 the form is disabled.

**Saving** (`FNAbviewform.js:344-437`):

1. Run the `onBeforeSaveData` callback.
2. Collect values from the visible fields, custom getters, the linked parent cursor, and
   recalculated calculate and formula fields; run `formCleanValues` (`:176-268`).
3. Load the DCs the record rules need, then run the pre-process record rules ("Update
   Record") on the values.
4. Validate with `object.isValidData` plus the required fields; mark bad fields and alert
   (`:270-338`).
5. `model.update(id, values)` when the values carry an `id`, else `model.create(values)`.
6. Run the other record rules (failures go to `notify.developer`), then the submit rules.
7. Clear the cursor and the form when `clearOnSave`, else move the cursor to the saved row;
   emit `saved`.

Server errors with `invalidAttributes` mark fields; `sqlMessage` shows a Webix message;
anything else shows "System could not save your data" (`:371-402`). See trap 9.

### 3.3 Form field sub-views

The base `ABViewFormItem` has `required` 0 and `disable` 0 and finds its field through the
form's DC (`included/view_form/core/ABViewFormItemCore.js:2-58`). The field types each
sub-view serves are in [frontend.md](frontend.md) §5.5.

| Key | Settings (defaults) | Notes |
|---|---|---|
| `button` | `includeSave` true, `saveLabel`, `includeCancel` false, `cancelLabel`, `includeReset` false, `resetLabel`, `includeDelete` false, `deleteLabel`, `afterCancel` null, `alignment` right, `isDefault` false | Save runs the form save. Cancel clears the cursor (unless the DC follows another cursor) and goes to `afterCancel` or the nearest non-popup parent page. Delete asks, then `model.delete` (`viewComponent/FNAbviewformButtonComponent.js:132-242`). A form without a button gets one (`FNAbviewform.js:154-174`) |
| `checkbox` | | Webix checkbox |
| `connect` | `formView`, `filterConditions`, `sortFields`, `popupWidth` 700, `popupHeight` 450 | combo or multicombo; "add new" opens a form page in a popup; "filter by another field" (`filterConnectedValue`); options from `field.getOptions` |
| `fieldcustom` | | File and image uploaders through the field's `customDisplay` |
| `datepicker` | `timepicker` false | |
| `json` | `type` string, systemObject or filter | `filter` embeds a FilterComplex |
| `numberbox` | `isStepper` 0 | Stepper uses Webix `counter` |
| `fieldreadonly` | | Calculated values |
| `selectmultiple` | `type` multicombo | Coloured chips |
| `selectsingle` | `type` richselect or radio | |
| `textbox` | `type` single, multiple or rich | `rich` loads the `tinymce-editor` view on demand |
| `formtree` | | Tree picker |
| `form-url` | `url`, `method`, `headers` | A form type that submits through `AB.Network[method]` instead of a model (`core/ABViewFormURLCore.js:13-38`) |

### 3.4 Form rules

- `ABViewRuleList` holds the rules. Pre-process rules run in order before the save; the
  others run in parallel after it (`rules/ABViewRuleList.js:314-362`).
- Each `ABViewRule` has an action, a FilterComplex condition and `valueRules`
  (`rules/ABViewRule.js:306-475`).
- **Record rules** (`rules/ABViewRuleListFormRecordRules.js:18-47`): **Update Record**
  (pre-process; can use `ab-current-user`, `ab-current-date`, and values taken from other
  DCs), **Insert Connected Object** (`model.create`), **Update Connected Record**
  (`model.update`), **Remove Connected Record** (`model.update` on the parent).
- **Submit rules** (`rules/ABViewRuleListFormSubmitRules.js:18-39`): show a confirmation
  message, redirect to an existing page (optionally switching tabs), redirect to the
  parent page, close the current popup, open another website, send a custom email.
- The CSV importer and PDF importer reuse these rule lists. The designer side is in
  [abdesigner.md](../plugins/abdesigner.md) §7.5.

### 3.5 Detail (`detail`) and detail items

| Key | Settings (defaults) | What it shows |
|---|---|---|
| `detail` | `dataviewID` null, `showLabel` true, `labelPosition` left, `labelWidth` 120, `height` 0 | The cursor row. Refreshes on `changeCursor`, `cursorStale`, `collectionEmpty`, and on `create`/`update` of that row. Only label and text widgets can be dropped in |
| `detailtext` | | Text |
| `detailcheckbox` | | Check icon |
| `detailconnect` | `formView` | Joined relation values |
| `detailcustom` | | The field's `customDisplay` |
| `detailimage` | `height` 80, `width` 120 | Image with a download link from `/file/<id>` |
| `detailselectivity` | `height` 0 | Selectivity chips |
| `detailtree` | | Tree chips |

Evidence: `included/view_detail/core/*.js`;
`included/view_detail/viewComponent/FNAbviewdetailComponent.js:26-81`.

---

## 4. Other plugin widgets

| Key | Settings (defaults) | What it does | Evidence (`included/`) |
|---|---|---|---|
| `list` | `dataviewID`, `field`, `height` 0 (auto) | `dc.bind` on a Webix dataview showing `field.format(item)` | `view_list/FNAbviewlist.js:16-26` |
| `dataview` | `xCount` 1, `detailsPage`, `detailsTab`, `editPage`, `editTab` | Bound cards; each card renders the child views for its row; reload button; link pages | `view_dataview/FNAbviewdataview.js:22-34` |
| `layout` | `label`, `numColumns` 1 | Columns container; passes child `changePage` events up | `view_layout/FNAbviewlayout.js:16-25` |
| `tab` | `height` 0, `minWidth` 0, `stackTabs` 0, `darkTheme` 0, `sidebarWidth` 200, `sidebarPos` left, `iconOnTop` 0, `hintID` null | Tabview, or a sidebar when `stackTabs`. Remembers the last tab and the sidebar state in Storage; handles `changeTab`; tutorial hints | `view_tab/FNAbviewtab.js:14-29` |
| `label` | `text`, `format` 0 normal, 1 title, 2 description, `alignment` left | Static text styled by format | `view_label/FNAbviewlabel.js:19-31` |
| `text` | `text`, `height` 0, `dataviewID` | `{Field Label}` placeholders filled from the cursor row; follows the cursor unless it sits inside a dataview | `view_text/FNAbviewtext.js:16-47` |
| `image` | `filename`, `width` 200, `height` 100 | `<img src="/file/<filename>">`. The designer uploads to `/image/upload/1` | `view_image/FNAbviewimage.js:16-26` |
| `carousel` | `dataviewID`, `field`, `width` 460, `height` 275, `showLabel` true, `hideItem` false, `hideButton` false, `navigationType` corner or side, `filterByCursor` false, details and edit pages | Filter helper, fullscreen, loads more rows, field default image | `view_carousel/FNAbviewcarousel.js:17-39` |
| `data-select` | `dataviewID` | Combo of DC rows; choosing one calls `setCursor` | `view_data-select/FNAbviewdataselect.js:16-24` |
| `comment` | `dataviewID`, `columnUser`, `columnComment`, `columnDate`, `height` 300 | Webix `comments`. New comments go through `model.create` with the current username; edit and delete through the model | `view_comment/FNAbviewcomment.js:16-30` |
| `csvExporter` | `dataviewID`, `where`, `buttonLabel` "Export CSV", `filename` "exportCSV", `hasHeader` true, `width` 150, `hiddenFieldIds` | Opens `/appbuilder/csv-export/<viewId>?where=<widget + user filter>`; the server builds the file ([api.md](api.md)) | `view_csvExporter/FNAbviewcsvexporterComponent.js:94-120` |
| `csvImporter` | `dataviewID`, `availableFieldIds`, `buttonLabel` "Upload CSV", `width` 0, `recordRules` | Accepts CSV files; at most 1,000 rows; validation rules; resolves connected values by loading the whole linked table; saves with `model.batchCreate`; then record rules | `view_csvImporter/FNAbviewcsvimporterComponent.js:855-864`, `1283-1660` |
| `pdfImporter` | `dataviewID`, `fieldID`, `submitRules` | Loads pdf.js on demand, draws each chosen page to a canvas, uploads it as PNG to the field's upload URL, then runs submit rules | `view_pdfImporter/FNAbviewpdfimporterComponent.js:297-386` |
| `docxBuilder` | `buttonlabel` "Download DOCX", `dataviewID`, `width` 0, `filename` (template file id), `filelabel` "output.docx", `language` en, `toolbarBackground`, `buttonPosition` left | Re-queries each DC with `findAll`, downloads images, fills the template from `/file/<filename>` with Docxtemplater 3.0.12 (vendored), and downloads the result | `view_docxBuilder/FNAbviewdocxbuilderComponent.js:176-578` |
| `gantt` | `dataviewID`, `titleFieldID`, `startDateFieldID`, `endDateFieldID`, `durationFieldID`, `progressFieldID`, `notesFieldID` | Webix Gantt with a custom backend: task add, update and remove go through the model; year, month and day scales | `view_gantt/FNAbviewganttComponent.js:427-573` |
| `kanban` | `dataviewID`, `editFields`, `verticalGroupingField`, `horizontalGroupingField`, `ownerField`, `template` | Lanes from list options; dragging a card updates its status through the model; owner change; side panel form; edit and details links | `view_kanban/FNABViewKanbanComponent.js:65-499` |
| `pivot` | `dataviewID`, `removeMissed` 0, `totalColumn` 0, `separateLabel` 0, `min` 0, `max` 0, `height` 0 | Webix Pivot fed with DC data; keeps its `structure` | `view_pivot/FNABViewPivotComponent.js:55-138` |

---

## 5. Charts

`chart` is a container; the builder drops one chart type inside it. The module returns
`[chart, area, bar, line, pie]` (`included/view_chart/FNAbviewchart.js:7-14`).

| Key | Settings (defaults) | Evidence (`included/view_chart/`) |
|---|---|---|
| `chart` | `dataviewID`, `columnValue`, `columnLabel`, `columnValue2`, `isPercentage` 1, `showLabel` 1, `labelPosition` left, `labelWidth` 120, `height` 200, `multipleSeries` 0 | `chart/FNAbviewchart.js:17-34` |
| `area` | `areaType` area, `isLegend` 1, `chartHeight` 200, `labelFontSize` 12, `stepValue` 20, `maxValue` 100 | `area/FNAbviewchartarea.js:18-31` |
| `bar` | `barType` bar, `barPreset` column, `isLegend` 1, `height` 200, `labelFontSize` 12, `stepValue` 20, `maxValue` 100 | `bar/FNAbviewchartbar.js:16-31` |
| `line` | `lineType` line, `linePreset` plot, `isLegend` 1, `chartHeight` 200, `labelFontSize` 12, `stepValue` 20, `maxValue` 100 | `line/FNAbviewchartline.js:17-32` |
| `pie` | `pieType` pie, `isLegend` 1, `height` 200, `innerFontSize` 12, `labelFontSize` 12 | `pie/FNAbviewchartpie.js:19-32` |

The container groups `dc.getData()` by the label column and sums the value column
(calculate and formula fields work). It refreshes on cursor changes, `create`, `update`,
`delete`, `initializedData` and the linked DC's cursor
(`included/view_chart/core/ABViewChartCore.js:115-200`). See trap 15.

---

## 6. Core (non-plugin) views

Components are in `views/viewComponent/`; defaults in
`developer/ab_platform_web/AppBuilder/core/views/`. The designer has built-in property
panels for `page`, `viewcontainer`, `menu`, `conditionalcontainer`, `data-filter`,
`reportsManager` and `scheduler` ([abdesigner.md](../plugins/abdesigner.md) §7.3).

| Key | Settings | What it does |
|---|---|---|
| `page` | `type` page or popup, `popupWidth`, `popupHeight`, `fixedPageWidth`, `pageWidth`, `pageBackground` | A page; popups render as windows ([frontend.md](frontend.md) §4.3) |
| `viewcontainer` | `columns`, per-column `gravity` | Generic container |
| `menu` | `orientation` x, `buttonStyle`, `menuAlignment`, `menuInToolbar` 1, `menuPadding` 10, `menuTheme`, `menuPosition`, `menuTextLeft`/`Center`/`Right`, `pages`, `order` | Page buttons or a menu; a click calls `changePage` (`ABViewMenuComponent.js:38-219`) |
| `data-filter` | `dataviewID`, `field`, `viewType` advanced, `showFilter` 1, `showSort` 1 | Search, filter and sort UI that sets `dc.filterCondition` and reloads (`ABViewDataFilterComponent.js:68-363`) |
| `connect-data-filter` | `dataviewID`, `field` | Combo of connected records that filters the DC (`ABViewConnectDataFilterComponent.js:28-137`). No designer editor |
| `conditionalcontainer` | `dataviewID`, `filterConditions` | Shows the "If" or the "Else" part depending on FilterComplex `isValid(cursor)` (`ABViewConditionalContainerComponent.js:32-164`) |
| `reportsManager` | `dataviewID`, `dataviewFields {name, text, queries}`, `datacollectionIDs`, `editMode` 0, `hideCommonTab`, `hideDataTab`, `hideViewTab` | Webix Reports; report modules are stored as rows of the DC (`ABViewReportsManagerComponent.js:35-805`) |
| `scheduler` | `readonly`, `dataviewID` with a field map (name, start, end, allDay, repeat, calendar, color, sectionID, unitID, notes, originID), `calendarDataviewID` with its field map, `timeline` modes, `timelineSectionList`, `unitList`, `export` | Webix Scheduler; events and calendars are stored through `dc.model` (`ABViewSchedulerComponent.js:84-298`) |

Runtime views with no designer property editor: `connect-data-filter`, `detailconnect`,
`detailselectivity` and `fieldreadonly`.

---

## 7. Shared property helpers

| Helper | Runtime (`views/viewProperties/`) | Designer (`developer/plugins/ABDesigner/src/rootPages/Designer/properties/views/viewProperties/`) |
|---|---|---|
| Link page | `ABViewPropertyLinkPage.changePage(pageId, rowId)` sets the DC cursor, then changes page | `detailsPage`, `editPage` |
| Add page | "Add new" button plus a popup window hosting a form page | `formView` |
| Edit page | Edit form through `urlResolve` | `editForm` |
| Filter data | `filterOption` 1 = user filters (toolbar or form), 2 = predefined rule buttons, 3 = global search (`globalFilterPosition` single or default). Emits `filter.data(fn, rules)` | Filter mode, default or single record, toolbar or form, global input |

Evidence: `views/viewProperties/ABViewPropertyLinkPage.js:35-42`,
`ABViewPropertyAddPage.js:129-273`, `ABViewPropertyEditPage.js:130-151`,
`ABViewPropertyFilterData.js:111-420`.

---

## 8. Traps

**Verified** means the code says so. **Inferred** means the effect is reasoned from the
code and was not run.

Grid:

1. **Grid filters are shared.** They set `dc.filterCondition`, so every widget on that DC
   is filtered too (`FNAbviewgridComponent.js:895-898`). Verified.
2. **Grid sort can load the whole table**: on a partly loaded DC it reloads every row
   first (`:909-913`). Verified.
3. **`ignoreLocal` is never set.** `refreshHeader` defaults to `this.ignoreLocal`, while
   the constructor sets `ignoreLocalSettings` (`:137`, `1696`). Verified.
4. **Excel, PDF and PNG export may fail.** Webix loads its export libraries (xlsx,
   html2canvas, pdfjs) from `webix.cdn`, which the grid sets to `/js/webix` (`:594`).
   Those files are vendored in `developer/ab_platform_web/js/webix/extras/`, but nothing
   imports or copies them into the served assets, and nginx has no `/js` location, so the
   requests go to api_sails, which has no `assets/js/webix`. CSV needs no extra library.
   Verified code, effect not tested.
5. **A failed mass update leaves the popup stuck** with the button disabled and the
   spinner on (`ABViewGridPopupMassUpdate.js:214-225`). Verified.

Form:

6. **Validation rules leak between forms.** `fieldValidations` is a factory-level array
   shared by every form instance and never cleared (`FNAbviewformComponent.js:22`,
   `113`, `290-316`). Verified code, inferred effect.
7. **Fast cursor changes can show stale data**: `displayData` drops calls within 80 ms of
   the last one (`:426-432`). Inferred.
8. **The tree lookup misses.** The form looks up key `"tree"`; the real key is
   `"formtree"` (`FNAbviewform.js:82`). The value is unused. Verified.
9. **Server save errors can show nothing.** `saveData` passes `err.data` to `formError`,
   but network errors carry `.response`; the button is just re-enabled
   (`FNAbviewform.js:411-415`). Inferred.
10. **The custom foreign key filter picks the wrong column** whenever `indexField2` is set:
    `a === b || c` (`viewComponent/FNAbviewformConnectComponent.js:500-506`). Verified.
11. **Connect options load the whole linked table** (no limit;
    `developer/ab_platform_web/AppBuilder/platform/dataFields/ABFieldConnect.js:378-383`).
    Inferred performance risk.
12. **"Send a custom email" posts to a route that does not exist**: `/app_builder/email`
    is not in `developer/api_sails/config/routes.js` (grep)
    (`rules/ruleActions/ABViewRuleActionFormSubmitRuleEmail.js:697-698`). Verified code,
    inferred 404.
13. **"Open another website" breaks https links.** It builds
    `http://${website.replace("http://", "")}`, so `https://x` becomes `http://https://x`
    (`rules/ruleActions/ABViewRuleActionFormSubmitRuleWebsite.js:110-116`). Verified.
14. **`form-url` cannot reach external URLs over the socket transport**, which is the
    default (`core/ABViewFormURLCore.js:13-38`). Inferred.

Other widgets:

- **The CSV Exporter crashes api_sails** (seen 2026-10-02). `csv-export.js:70` calls
  `sails.getDatastore()`, which does not exist because `config/hooks.js` disables the ORM
  hook. The exception kills the api_sails process and the whole site stays down until
  `npm start` (known issue B24). Do not click it until this is fixed.

15. **Charts count only loaded rows**: they aggregate `dc.getData()`, which holds a page,
    not the table (`ABViewChartCore.js:148`; AGENTS.md §7). Inferred.
16. **The CSV importer's "Space" separator splits on the letter `s`.** Its option id is
    `"s"`, used in `row.split(separatedBy)` (`view_csvImporter/CSVImporter.js:29`, `91`).
    The same bug is in ABDesigner's new-object CSV tab. Verified.
17. **CSV import caps at 1,000 rows** and loads the whole linked table to resolve
    connections (`FNAbviewcsvimporterComponent.js:855-864`). Verified.
18. **The DOCX builder can crash** when a followed DC has no cursor: it reads
    `this.datasource.PK()`, which the component lacks
    (`FNAbviewdocxbuilderComponent.js:295`). Verified.
19. **The scheduler extends the wrong backend**: `reports.services.Backend` instead of the
    scheduler's (`views/viewComponent/ABViewSchedulerComponent.js:121-124`). Verified code,
    inferred effect.

Designer side of widgets:

20. **System-object filters are reversed in the chart and gantt panels.** They hide system
    DCs from System Builders and show them to everyone else
    (`designer/web_view_chart/properties/FNAbviewchart.js:205-209`;
    `designer/web_view_gantt/FNAbviewgantt.js:129-133`). The text panel has it right.
    Verified.
21. **The label panel has latent errors**: `fromValues` refers to an undefined
    `ABViewTextPropertyComponentDefaults` (`designer/web_view_label/FNAbviewLabel.js:186`,
    `190`). Whether that path runs is unverified.
22. **Dead copies drift.** ABDesigner still holds old property and editor files for most
    widgets under `src/rootPages/Designer/properties/views/` and `editors/views/`. Edit
    `designer/web_view_<x>/`, not those ([abdesigner.md](../plugins/abdesigner.md) §1).
23. **Closing a form while a connect field still loads its options logs a `TypeError`.**
    For a connection to one record, `_onChange()` takes `$$(ids.formItem)`, awaits
    `field.getAndPopulateOptions()`, then calls `setValue()` on that item
    (`viewComponent/FNAbviewformConnectComponent.js:188-249`). When the form was destroyed
    during the wait, Webix's `getInputNode()` reads a removed node and the promise rejects
    with "Cannot read properties of null (reading 'getElementsByTagName')", which nothing
    catches. Only the console shows it. Seen 2026-11-03 in the HR Teams edit form, closed
    0.3 s after it opened (known issues W51).

---

## 9. Adding or changing a widget

1. Runtime half: add `included/view_<x>/` with a factory that receives the plugin API and
   returns a class extending `ABViewWidgetPlugin` (with `common()` and `defaultValues()`)
   plus a component extending `ABViewComponentPlugin`. Add it to `included/index.js`.
2. Designer half: add `designer/web_view_<x>/` with a properties class
   (`"properties-view"`, extends `ABViewPropertiesPlugin`) and an editor class
   (`"editor-view"`, extends `ABViewEditorPlugin`), keyed by the same widget key. Add both
   to `designer/index.js`.
3. A widget shipped as an external tenant plugin instead must use a key that starts with
   `plugin_` (§1).
4. Never rename an existing key or a setting name: both are stored in definitions.
5. Both repos are separate submodules (AGENTS.md §2.2). The `npm run watch` you run in
   each rebuilds it on save; check that terminal for `compiled` before testing in the
   browser (AGENTS.md §9).

---

## Open questions

1. Do Excel, PDF and PNG grid exports work in this stack (trap 4)?
2. Is `displayRules` on forms used anywhere, for example by the PWA?
3. Do traps 6, 9 and 18 reproduce in a browser? They follow from the code but were not
   exercised.
