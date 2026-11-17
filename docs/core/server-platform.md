# Server platform (platform_service)

The server half of the domain model: per-tenant factories, knex/Objection data access, the
condition-to-SQL compiler, scopes, and the DDL that turns object/field definitions into
tables. Code: the platform_service repo (branch `master`), a nested submodule named
`AppBuilder` in each AppBuilder service (appbuilder, custom_reports, definition_manager,
file_processor, process_manager, user_manager), with class_core nested in it as
`AppBuilder/core`. Each service's copy has its own `node_modules`, like the images (`npm ci`
in `/app/AppBuilder`). This page cites appbuilder's copy, `developer/appbuilder/AppBuilder`.

Verified against `544b83a` ("Update version 1.14.21") on 2026-10-01, then with a local
knex pool `min: 0` (known issue C4, dropped on 2026-10-30). Since 2026-10-30 each copy is at
the commit its service records, with no local edits: `544b83a` in appbuilder,
definition_manager and process_manager, `d8d8f49` (1.14.22, class_core 2.20.1) in
custom_reports, file_processor and user_manager. Paths are relative to platform_service's
root unless they start with `developer/`. "Inferred" = reasoned from code, not run.

Related: [domain-model.md](domain-model.md) (the core classes this extends),
[services.md](services.md) (who calls what), [processes.md](processes.md) (process task
classes under `platform/process/`), [database.md](database.md).

---

## 1. File map

| Path | Responsibility |
|---|---|
| `ABBootstrap.js` | Builds and caches one `ABFactory` per tenant; loads definitions and remote plugins; drops a factory on `definition.*` events. Exports `init(req)`, `resetDefinitions(req)` |
| `ABFactory.js` | Server `ABFactoryCore`: tenant knex pool, server `rules`, definition CRUD, cache, model pool, `notify`, utilities |
| `platform/` (27 top-level files) | Server subclasses of the core classes (§4) |
| `platform/dataFields/` | `ABField` base + 20 field classes: DDL and request params (§4.2) |
| `platform/views/`, `platform/mobile/` | Thin server views (no UI); mostly empty subclasses |
| `platform/plugins/` | v1 object-plugin base classes; `included/index.js` is empty; `developer/ObjectNetsuite.js` + `ModelNetsuite.js` are an unused plugin copy of NetSuite |
| `platform/ql/` | Server side of the process query language (see [domain-model.md §8](domain-model.md#8-process-query-language-ql)) |
| `platform/process/` | BPMN engine and task classes ([processes.md](processes.md)) |
| `queries/` | Raw, DB-qualified SQL on ab-utils' mysql pool: `definitionCreate/Destroy/Find/Update`, `allDefinitions`, `allPluginLinks` (used); `allPlugins`, `findLanguages` (unused) |
| `policies/` | Condition converters run before SQL compilation (§5.2); `ABModelConvertFieldKey.js` is dead Sails code |
| `rules/` | Empty web-only stubs so class_core mobile form code can import them |
| `utils/cleanReturnData.js` | Strips SiteUser `password`/`salt`, process-instance relations and extra relation keys from rows returned to clients |
| `test/platform/ABProcess.test.js` | Five mocha cases (§9) |

`core/` is an uninitialized nested submodule on disk; its contents come from the bind mount.

---

## 2. ABBootstrap

Module state is per Node process: `Factories` (tenant to factory), `PendingFactory`
(tenant to the build promise, so one build at a time), `KnexPool` (tenant to knex instance,
kept across rebuilds), and the `definition.stale` subscriber.

### `init(req)` (`ABBootstrap.js:216-253`)

1. Require `req.tenantID()`.
2. If no cached factory: log `:: Loading Definitions for tenant[...]`, create or reuse
   `PendingFactory[tenantID]`, await it.
3. On the first success in the process, subscribe to `definition.stale`,
   `definition.created`, `definition.destroyed`, `definition.updated`.
4. Return the factory.

### `setupFactory(req, tenantID)` (`:145-213`)

1. `SELECT * FROM <tenantDB>.appbuilder_definition` (via `queries/allDefinitions.js`),
   hashed by id.
2. Log `Tenant[<id>] Knex pool exists: <bool>`.
3. `new ABFactory(defs, DefinitionManager, req.toABFactoryReq(), KnexPool[tenantID])`.
   `toABFactoryReq()` is a new request with jobID `ABFactory(<tenant>)` and **no user**.
4. Listen to the factory's own `definition.*` events: save the knex pool, drop the factory.
5. **Load remote plugins:** read `SITE_PLUGIN_LINK` rows for `platform: "service"`, fetch
   each URL and run the code in a `vm.Script` with `require`, `process`, `fetch` and timers
   available, then `pluginRegister` (`:76-143,184-196`). Failures are only logged.
6. `await newFactory.init()` (core build order: object, query, datacollection, process,
   hint, step, application), then `Secret.init`.
7. Cache the factory and delete the pending promise. No definitions: notify and throw.

### Staleness

`definition_manager` publishes `definition.created/updated/destroyed` after CRUD and
`definition.stale` after import/reset. `staleHandler` drops the cached factory (saving its
knex pool) and logs `:: Definitions reset for tenant[...]`; the next `init` rebuilds.
Handlers call `resetDefinitions(req)` for a one-time retry when an id is not found.

The knex pool is reused across rebuilds because repeated rebuilds used to exhaust
connections (`ER_CON_COUNT_ERROR`, comment at `:67-72`).

---

## 3. ABFactory (server)

- **Knex** (`ABFactory.js:115-158`): lazy pool, `client: "mysql"`, host/user/port/password
  from `req.connections().appbuilder`, `database` = the tenant DB, `timezone: "UTC"`,
  pool `min: 2` (two idle connections outlive MariaDB's 60 s `--wait-timeout`, so knex
  logs `ECONNRESET` after a quiet minute; known issue C4), `max: config.poolMax || 30`,
  `acquireTimeoutMillis: config.acquireTimeout || 90000`. Nothing sets `poolMax` or
  `acquireTimeout`. `connection()` ignores its `connName` argument.
  `createTransaction(cb)` wraps `knex.transaction` (no callers found).
- **Objection models** (`platform/ABModel.js:824-949`): one `Model` subclass per object,
  named from the object id's letters, with schema-qualified `tableName`,
  `idColumn = object.PK()`, a `jsonSchema` from each field's `jsonSchemaProperties`,
  `jsonAttributes`, lazy `relationMappings`, cached in the factory's model pool.
- **`AB.rules`** adds `toSQLDate` (local), `toSQLDateTime` (UTC), `toDate(text, {format,
  ignoreTime})` (moment, with fallback formats; with no format moment prints the
  deprecation warning listed in AGENTS.md §7.1), `toDateFormat`, `addDate`,
  `subtractDate`, `getUTCDayTimeRange`.
- **Cache:** `cache(key[, data])`, `cacheClear`, `cacheMatch`; lives as long as the factory,
  so any definition change clears it.
- **Definition CRUD:** `definitionCreate(req, def)`, `definitionUpdate(req, id, values)`,
  `definitionDestroy(req, id)`, `definitionFind(req, cond)`. **Only definition_manager calls
  them.** The core `save()`/`destroy()` path does not work on the server (wrong
  signatures).
- **Other:** `notify`, `error` (emits `"error"`: see trap 6), `toError`, `jsonToCsvBatched`
  (10k rows per batch), `uuid`, lodash helpers, `Secret` (§4.9).

---

## 4. Server platform classes

### 4.1 ABObject (`platform/ABObject.js`)

- **Table name:** stored `tableName`, else `AB_<appName>_<name>` (or `AB_<name>`), then
  `[a-zA-Z0-9_ ]` only. `dbTableName(true)` = `<tenantDB>.<table>`. `PK()` =
  `primaryColumnName || "uuid"`.
- **`migrateCreate(req, knex)`:** if missing, `createTable` with `uuid` VARCHAR(255) PK,
  `created_at`/`updated_at`, `properties` TEXT, InnoDB utf8 `utf8_unicode_ci`; then create
  fields **sequentially** (normal, combined, indexes, connect) to avoid
  `ER_TABLE_EXISTS_ERROR #sql-alter`.
- **`migrateDrop`:** all field drops in parallel, then `dropTableIfExists`.
- Also: `requestParams` / `requestRelationParams`, `includeScopes` (§5.3),
  `convertToQueryBuilderConditions` + `reduceConditions` (§5.2), formula subselects,
  `validExtension` (used by file_processor).

### 4.2 Field DDL (`platform/dataFields/`)

Base `ABField`: `dbPrefix()`, `conditionKey()` (`<dbPrefix>.\`col\``), `migrateDrop`
(drop FK, then column, then rebuild every query view using the field, then refresh the
Objection model).

| key | Column created by `migrateCreate` | `migrateUpdate` | Seen in MariaDB (2026-10-02) |
|---|---|---|---|
| `string` | VARCHAR(255) (+DEFAULT unless `{uuid}`, optional UNIQUE); multilingual: only ensures a JSON `translations` column | same as create | `varchar(255)` |
| `LongText` | LONGTEXT; multilingual: JSON `translations` | same as create | `longtext` |
| `number` | INT, or DECIMAL(scale+8, scale) when decimals are set | same as create | `int(11)`; with 2 decimals `decimal(10,2)` |
| `date` | DATE | same as create | `date` |
| `datetime` | DATETIME | same as create | `datetime` |
| `boolean` | TINYINT(1) | same as create | `tinyint(1)` |
| `list` | single: VARCHAR(255); multiple: JSON | same as create | single: `varchar(255)` (the option id); multiple: JSON (below) |
| `email` | VARCHAR(254) | same as create | `varchar(254)` |
| `image` | VARCHAR(255) | base (see trap 7) | `varchar(255)` (the file id) |
| `file` | JSON | base | JSON (below) |
| `json` | JSON | same as create | JSON (below) |
| `tree` | JSON | base | JSON (below) |
| `AutoIndex` | `INT UNSIGNED NULL AUTO_INCREMENT UNIQUE` | same as create | `int(10) unsigned NOT NULL AUTO_INCREMENT` plus a UNIQUE key; shown as `IT-0001` with prefix and length settings |
| `combined` | VARCHAR(535) + BEFORE INSERT/UPDATE triggers (CONCAT) + backfill | **no-op** | not tried |
| `calculate`, `formula`, `TextFormula` | none (virtual; calculate/formula compile to SQL in `conditionKey`) | none | not tried |
| `connectObject`, `user` | see below | base | see below |

The last column was read from a test object with one field of each common type (MariaDB
10, table charset `utf8mb3`). MariaDB has no real JSON type: a JSON column shows as
`longtext` utf8mb4 with `CHECK (json_valid(...))`. Every table starts with `uuid` (PK),
`created_at`, `updated_at`, `properties`, and a required field without a default stays
nullable in the database.

**Connect DDL** (`ABFieldConnect.js:190-724`): one:many adds the FK column to this table
(type from `SHOW COLUMNS` when `indexField` is set, else INT UNSIGNED for `id` or
VARCHAR(255)) with `ON DELETE SET NULL`; one:one source adds a unique FK; many:one adds the
column to the linked table; many:many creates the junction table
`AB_JOINMN_<src15>_<tgt15>_<col14>` (or `settings.joinTable`) with columns named after the
two objects' **names**. Dropping M:N drops the junction table.

Seen in MariaDB (2026-10-02): a single `user` field is `varchar(255)` with an FK to
`SITE_USER.username` `ON DELETE SET NULL`; a many → one connect is `varchar(255)` on the
"many" side with an FK to the other table's `uuid` `ON DELETE SET NULL`; a many ↔ many
connect made `AB_JOINMN_<Object>_<Object>_<column>` (spaces in the object names kept) with
an auto-increment `id` plus one FK column per side.

### 4.3 Query objects (`platform/ABObjectQuery.js`)

`migrateCreate` builds a knex `DISTINCT` select over the join tree (`fullouterjoin`
emulated as `innerJoin ... ON 1=1`), adds connect fields as JSON/`GROUP_CONCAT`
subselects aliased `` `<alias>.<col>__relation` ``, formula fields as aggregate subselects,
plain fields as `alias.col AS "alias.col"` (view column names contain dots), skips
calculate/TextFormula, then runs `CREATE OR REPLACE VIEW <viewName> AS (...)` in the tenant
DB. `migrateDrop` = `DROP VIEW IF EXISTS`.

`ABModelQuery.findAll` reads from the view, numbers rows with `@rownum` (unless
`ignoreIncludeId`), ANDs the query's own `where`, **calls `reduceConditions` itself**, logs
`ABModelQuery.findAll(): <sql>`. `create`/`update`/`relate` reject.

Seen on 2026-10-02: the view is named `AB_<App>_View_<Query>` with spaces removed (query
"Tasks with Item" in app "Claude Sandbox" became `AB_ClaudeSandbox_View_TaskswithItem`),
and `findAll` ran `select @rownum := @rownum + 1 AS id, result.* from (select * from
<view>)`. **A query row's `id` is a row number, not a stable key.**

### 4.4 API and NetSuite objects

- **ABObjectApi:** `migrateCreate` stores secrets with `AB.Secret.create` (not awaited);
  `ABModelApi.findAll` does `fetch(url)` with paging and `SECRET:<name>` header
  substitution, then `dataFromKey`; no `where`; `findCount` = result length.
- **NetSuite** (`platform/ABModelApiNetsuite.js`): OAuth 1.0a HMAC-SHA256 with `realm`;
  credentials `ENV:<VAR>` from `process.env` (unset becomes `"??"`), `SECRET:` not
  implemented. A process-wide limiter allows `NETSUITE_CONCURRENCY_LIMIT || 35` requests
  and dedupes identical ones; a 1 s interval prints `=== Netsuite Concurrency ====`.
  `findAll` builds SuiteQL (`SELECT ... FROM <table> ... WHERE ... ORDER BY`), logs
  `Netsuite SQL: <sql>`, POSTs to `<NETSUITE_QUERY_BASE_URL>/suiteql` with
  `Prefer: transient`, fetches remaining pages in parallel for unlimited queries.
  `findCount` sends no query: it waits for the first `findAll` page's `totalResults`
  (keyed by `cond.jobID`). Writes: POST (new id from `location` header), PATCH, DELETE;
  M:N via `settings.joinTable` with "inactive" handling. `checked`/`unchecked` compile to
  `'T'`/`'F'`, dates to `TO_DATE(...)`.

### 4.5 Other classes

- **ABIndex:** checks `SHOW INDEXES`; unique indexes via raw `ALTER TABLE ... ADD UNIQUE
  INDEX` (tolerates `ER_DUP_KEYNAME`), normal via `table.index`; drop via
  `ALTER TABLE ... DROP INDEX`.
- **ABModel relation mappings:** one:one source `BelongsToOne`, other side `HasOne`,
  many:many `ManyToMany` through the junction columns, one:many `BelongsToOne`, many:one
  `HasMany`.
- **ABObjectExternal / ABObjectImport:** legacy pre-existing tables, no DDL.
- **ABSecretManager:** per-definition 32-byte key in the `Key` object (5 min cache);
  secrets AES-256-GCM stored as hex `ciphertext|iv|tag` in the `Secret` object.
- **ABClassManager:** module-level plugin registry, shared by all tenants in a process.

---

## 5. Query path

### 5.1 Order inside `appbuilder.model-get`

1. `object.convertToQueryBuilderConditions(cond)`
2. `await object.includeScopes(cond, condDefaults, req)`
3. `await object.reduceConditions(cond.where, condDefaults, req)`
4. `object.whereCleanUp(cond.where)`
5. `findAll` and, when `limit` is set, `findCount` in parallel
6. `cleanReturnData`, `api.broadcast-register`, core `csvPack(result, 10000, jobID)`

Performance marks: `convertToQBConditions`, `includeScopes`, `reduceConditions`,
`CSV Pack`; the response is serialized on ab-utils' worker pool (`worker.JSON.stringify`).

### 5.2 Converters and policies

**ConversionList** (always): Sails-style conditions to QueryBuilder rules (`startsWith` to
`begins_with`, `<` to `less`, scalar to `equals`, `""` to `is_empty`, `null` to `is_null`,
array to `in`, `"!"` prefix to `not_`), and the old filter-array format to QueryBuilder.

**PolicyList** inside `reduceConditions` (`policies/`), each repeating until no matching
rule is left:

| Policy | Rewrites |
|---|---|
| DataCollection | `in_data_collection` / `not_in_data_collection` to `in`/`not_in` over ids read from the DC's datasource (its saved filter plus the client's `linkCond`) |
| IsUserMN | M:N `is_current_user` / `is_not_current_user` to `in`/`not_in [username]` |
| SameAsUser | `same_as_user` / `not_same_as_user`: search for the nearest object with a user field, chain lookups, then `in`/`not_in` (`1 = 0` / `1 = 1` when empty) |
| Query | `in_query` / `not_in_query`: run the query, then `in`/`not_in` ids |
| QueryField | `in_query_field` / `not_in_query_field` (`"queryID:fieldID"`) to `in`/`not_in` values |

### 5.3 Scopes: `includeScopes` (`platform/ABObject.js:273-419`)

1. Return immediately for username `_system_`.
2. Load the user (`isActive:1`) with `SITE_ROLE` and `SITE_SCOPE`; unknown/inactive rejects.
3. No roles: replace `where` with `1 = 0`.
4. Collect the scopes of the user's roles; a scope applies when `allowAll` or its
   `objectIds` include this object; `Filters === null` disables filtering.
5. No applicable scope: AND `1 = 0`; otherwise AND the scope rules (joined with OR).

**Callers: only `appbuilder.model-get` and `appbuilder.csv-export`.** `findAll`/`findCount`
never apply scopes themselves (their default user is `_system_`), so every other read path
is unscoped: data reached through `in_query` sub-queries, data collections, ABQL/process
tasks, custom reports, and all writes.

### 5.4 `findAll(cond, conditionDefaults, req)` internals

- `formatCondition`: split `sort`/`offset`/`limit`/`populate` from `where`.
- `queryConditions`: parse each leaf with `parseCondition`, join groups as `( A AND B )`,
  apply with **`query.whereRaw(sql)`**; `have_relation`/`have_no_relation` become
  `leftJoinRelated`/`innerJoinRelated` + `whereRaw`.
- Formula subselects, external multilingual joins, `querySort` (field ids, `JSON_EXTRACT`
  for multilingual, `FIND_IN_SET` order for lists), offset/limit only when truthy,
  `queryPopulate` (`withGraphFetched`, one level deep plus linked users' `username`),
  `populateMin`, core `normalizeData`. Errors carry `_sql`.

### 5.5 SQL compiler (`platform/ABModel.js` `parseCondition`, `:1157-1654`)

Type prefixes stripped first (`number_`, `string_`, `date_`, `datetime_`, `boolean_`,
`user_`, `list_`, `connectObject_`).

| Rules | SQL |
|---|---|
| `equals` / `not_equal` | `=` / `<>` |
| `greater`, `greater_or_equal`, `less`, `less_or_equal` | `>`, `>=`, `<`, `<=` |
| `*_current` variants | same against `NOW()` |
| `last_days` / `next_days` | `BETWEEN DATE_SUB(NOW(), INTERVAL n DAY) AND NOW()` / `BETWEEN NOW() AND DATE_ADD(...)` |
| `checked` / `unchecked` | `IS TRUE` / `IS NOT TRUE` |
| `is_empty` / `is_not_empty` | `NULLIF(col,'') IS NULL` / `IS NOT NULL` |
| `begins_with`, `contains`, `ends_with` (+ `not_`) | `LIKE` patterns |
| `between`, `not_between` | `BETWEEN 'a' AND 'b'` |
| `is_current_user` / `is_not_current_user` | `=` / `<>` username |
| `contain_current_user` / `not_contain_current_user` | `LIKE` for queries; `PK IN (SELECT ... junction ...)` for objects |
| `is_current_email` / `is_not_current_email` | `=` / `<>` email |
| `is_null` / `is_not_null` | `IS NULL` / `IS NOT NULL` |
| `in` / `not_in` | quoted list; empty `in` is `1=0`, empty `not_in` is `1=1` |
| `is_current_date` | `BETWEEN` today's UTC range |
| `like` | `LIKE` |

Before compiling: multilingual keys become `JSON_UNQUOTE(JSON_EXTRACT(translations...))`;
list text becomes option ids; connect/user `contains/equals/in` become junction subselects;
a key of `"1"` stays bare so `1 = '0'` works.

**Escaping is only `quoteMe()`, which doubles single quotes** (`:1316-1322`); values that
look like `FUNC(...)` are not quoted at all (`:1394`). Backslashes are not escaped, and
several sites insert values without escaping (trap 13). Any new rule type must do its own
quoting.

### 5.6 Writes

- `create`: untranslate, request params, generate uuid, timestamps, validate, insert, run
  relates one at a time, read back with `populate: true`.
- `update`: read old, `patch`, diff relations (`unRelate` removed, `relate` added), read
  back. `delete(id)`: `delete().where(PK, id)`. `relate`: `$relatedQuery(rel).relate(v)`.
- Deleting a row that other rows link to (many → one) empties their link column, since the
  FK is `ON DELETE SET NULL` (§4.2; seen 2026-10-02).
- `find(cond, req)`: the Sails-style shortcut (field-key conversion, converters,
  `reduceConditions`, `findAll`, one retry on `ECONNRESET`/`ETIMEDOUT`). **`findAll` does
  not translate `{col: value}` conditions; only `find` does.**

---

## 6. queries/, rules/, policies/, utils/

All `queries/` SQL is DB-qualified and runs on ab-utils' shared mysql pool, not knex.
Inventory and callers are in §1.

---

## 7. Definition-driven migrations

**Trigger chain:** the browser's `ABObject`/`ABField`/`ABIndex` save the definition, then
call `POST/PUT/DELETE /definition/migrate/object/:objID[/field|index/:ID]` (api_sails
`config/routes.js:114-127`), which reach `definition_manager.migrate-*`, which call
`object.migrateCreate/Drop`, `field.migrateCreate/Update/Drop`,
`index.migrateCreate/Drop`. Saving and migrating are **separate calls**: a save without a
migration leaves the table out of sync.

- **Rename:** there is no rename logic. Changing `columnName` makes `migrateUpdate` (=
  create) add a new empty column and leaves the old one (inferred).
- **Delete:** field drop removes FK/unique/index then the column, and rebuilds affected
  query views; object drop drops all fields then the table; query drop drops the view.
- **No transactions** (MySQL commits DDL implicitly anyway): a failure leaves a partial
  schema.
- **Retries:** DDL is wrapped in `req.retry` (connection resets, deadlocks, lock waits,
  `KnexTimeoutError`; up to 10 tries). Tolerated codes include `ER_DUP_FIELDNAME`,
  `ER_DUP_KEYNAME`, `ER_TABLE_EXISTS_ERROR`, `ER_TRG_ALREADY_EXISTS`,
  `ER_CANT_DROP_FIELD_OR_KEY`, `ER_DROP_INDEX_FK`.
- **JSON import** runs its own multi-pass DDL order ([services.md §2](services.md#2-definition_manager)).

---

## 8. Tests

`npm test` = `mocha --recursive`; CI runs it on every push and a Cypress e2e
("kitchen-sink" via `CruGlobal/ab-install-action@v1`) on merges. The only test file is
`test/platform/ABProcess.test.js` (5 cases). It likely cannot pass as written: CommonJS
`proxyquire` against an ESM package, stubs keyed to the wrong module names, and assertions
inside un-returned `.then()` callbacks (inferred, not run). There is no lint script.

---

## 9. Traps

Lifecycle and tenancy:

1. **One failed factory build poisons that tenant until the service restarts:**
   `PendingFactory[tenantID]` is deleted only on success (`ABBootstrap.js:201`), so a
   rejected build promise is re-awaited by every later request (DB not ready at boot, no
   definitions, missing `SITE_PLUGIN_LINK`, missing Key/Secret objects).
2. **Remote plugin code runs with full access** (`require`, `process`) in every AppBuilder
   service; anyone who can write `SITE_PLUGIN_LINK` can run code. The loader imports
   `http` as `https` (`ABBootstrap.js:11`) and has no `error` listener on the request, so
   an unreachable host may raise an uncaught error (inferred).
3. A `definition.*` event during a pending build is lost; the build caches the old
   definitions (inferred).
4. `notify.builder/developer` are attached to the shared `ABFactory.prototype.notify`, so
   any factory's notifications go out through the most recently constructed factory's req
   (possibly the wrong tenant) (inferred).

DDL:

5. Combine fields: `migrateUpdate` is a no-op, so changing sources/delimiter never updates
   the triggers; trigger names are truncated and `ER_TRG_ALREADY_EXISTS` is swallowed.
6. **Dropping a File field likely always fails:** `ABFieldFile.migrateDrop` calls
   `AB.error()`, which emits `"error"` with no listener (`dataFields/ABFieldFile.js:96-98`,
   `ABFactory.js:567`), so the drop rejects and object drops never reach
   `dropTableIfExists` (inferred, high confidence).
7. Base `migrateCreate/Update` call `req.logError(error)` with one argument, which reads
   `undefined._context`: `migrate-field-update` likely fails with a TypeError for connect,
   user, file, image and tree fields (inferred).
8. A DateTime value cannot be cleared: `requestParam` returns early on falsy values.
9. ABFieldConnect one:many resolves before its DDL finishes; later errors only reach
   `notify.developer` (inferred from control flow). Several promises in ABIndex/Connect
   can hang (missing reject paths).
10. Self-referencing M:N would create two junction columns with the same name; a second
    AutoIndex on a table fails (MySQL allows one AUTO_INCREMENT); default index names can
    exceed 64 characters (inferred).

Query layer:

11. SQL is built by string concatenation (trap above): `quoteMe` does not escape `\`;
    `last_days`/`next_days`, `contain_current_user`, `have_relation`, sort `dir` and M:N
    `in` values are inserted unescaped (inferred injection surface).
12. Unknown rules are dropped at the top level but emitted raw inside groups;
    `not_equals` (produced by two converters) is not a compiler rule.
13. `DATE("<identifier>")` makes date `equals`/`in` never match unless `ANSI_QUOTES` is on
    (only programmatic conditions hit it) (inferred).
14. `includeScopes` has no `.catch` (a DB error hangs the request); rules from scopes that
    do not grant access are still ORed in.
15. Query policy many:one uses only `ids[0]`, and an empty result becomes `1=1` (matches
    everything); the DataCollection policy appends to the cached DC filter on every run.
16. `ABModelQuery` deletes from the rows array instead of a row; `convertFormulaField`
    writes `appbuilder-<uuid>.table` unquoted (breaks csv-export formulas) (inferred).

NetSuite, secrets, misc:

17. NetSuite `findCount` waits forever if `findAll` fails; `last_days`/`is_current_date`
    emit MySQL syntax into SuiteQL; literal credentials sit in definition JSON.
18. `ABSecretManager._decrypt` appears to slice the buffer wrongly, so `getValue` should
    always throw (inferred, not run); the data key sits in the same DB as the secret.
19. Undeclared dependencies (`knex`, `uuid`, `async`, `mysql`) resolve from whichever
    `node_modules` is first on the path inside the container.
20. One knex pool per tenant per process in six services (max 30 each) on top of ab-utils'
    mysql pools.

Seen at runtime (2026-10-02, Claude Sandbox app, see
[abdesigner.md §13](../plugins/abdesigner.md#13-walkthrough-building-an-app-from-scratch-observed)):

21. **Schema changes do not reach the Objection models of a running service.**
    `ABModel.modelKnex()` binds its model class with `MyModel.bindKnex(knex)`. Objection
    caches bound classes on the knex instance, keyed by `uniqueTag()` =
    `<db>.<table>_<model name>` (`objection/lib/model/modelBindKnex.js`, objection 3.1.5),
    and the model name is fixed per object (`modelKnexReference()`, the object id's
    letters). `ABBootstrap`'s stale handler keeps the tenant's knex connection
    (`KnexPool[tenantID] = knexConn`, `ABBootstrap.js:47-49`), and `modelKnexRefresh()`
    only clears AppBuilder's own `__ModelPool`. So the first bound class of an object lives
    for the life of the process, with the relations and `jsonSchema` of that moment.
    Observed: after adding connect fields to an object that had already been read, every
    `appbuilder.model-post` failed with `doesn't have relation Item__relation` /
    `unknown relation "Item__relation" in an eager expression`. **The insert itself
    succeeded** (the row and its FK column were written; the many-to-many join row was
    not), and only the re-read with `populate` failed, so the user sees an error for data
    that was saved and may save it again. `docker compose restart appbuilder` cleared it.
    Verified in code and at runtime. process_manager is hit the same way, and across apps:
    a `user` field added to a test object gave `SITE_USER` a new relation, and
    process_manager then failed NetSuite HR Update's "Updated Assignments" until it was
    restarted (B22). Other services are affected when they read the object before the
    change (inferred). After adding connect or user fields, restart appbuilder and
    process_manager.
22. **An object definition saved with an empty `tableName` points at the wrong table after
    the next factory rebuild.** `ABObject.fromValues()` fills an empty `tableName` from the
    app named by `createdInAppID` (`platform/ABObject.js:76-95`), but `ABFactoryCore.init()`
    builds objects **before** applications, so on a rebuilt factory the app is not found and
    the name becomes `AB_<Object>` instead of `AB_<App>_<Object>`. Observed: an object created
    through the browser factory API (`AB.objectNew().save()` plus `objectInsert`) was stored
    with `tableName: ""`; its table had been created as `AB_ClaudeSandbox_SandboxItem`, but
    the next field migrations ran against `AB_SandboxItem` and failed with `ER_NO_SUCH_TABLE`
    (plus a `multipleResolves` warning). Setting `tableName` on the object and saving fixed
    it. The ABDesigner UI path stored the name correctly once (Sandbox Task); why the API
    path lost it is inferred (a later save from a browser instance that never had the name).

Seen at runtime on 2026-10-03 (NetSuite sandbox 3):

23. **NetSuite reads reject a `limit` above 1000.** `ABModelApiNetsuite.findAll()` passes
    the caller's limit to SuiteQL as is, and NetSuite answers `The specified query
    parameter 'limit' is out of bounds. Provide value between 1 and 1000.` Page with
    `limit: 1000` and `skip` (R23).
24. **A JS `Date` sent to a NetSuite date field is stored as its UTC date.** East of UTC
    that is the day before: local midnight 2026-10-03 at UTC+7 was stored as 2026-10-02. A
    `"YYYY-MM-DD"` string is stored as given. A reply that shows
    `2026-10-02T17:00:00.000Z` is just local midnight of 2026-10-03, which is correct (W23).
