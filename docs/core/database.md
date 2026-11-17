# Database

Where AppBuilder data lives, how databases and tables are created, the seeded system data,
the accounting stored procedures, and how schema migrations work. Verified on 2026-10-01.
Paths are relative to the repo root.

Related: [services.md](services.md) (who reads/writes what),
[server-platform.md](server-platform.md) (how object definitions become tables),
[architecture.md §4](architecture.md#4-multi-tenancy) (tenant model).

---

## 1. Databases

| Database | What it holds |
|---|---|
| `appbuilder-admin` | The **site** database: `site_tenant`, plus a complete tenant schema for the built-in `admin` tenant (the admin tenant's DB *is* the site DB) |
| `appbuilder-<tenantUUID>` | One per additional tenant, created by `tenant_manager.tenant-add` |
| `appbuilder` | Empty; it exists because it is the default database of the `appbuilder` datastore (inferred) |

Connections come from ab-utils `datastores` (`node_modules/@digiserve/ab-utils/utils/defaults.js:30-48`):
`site` uses database `MYSQL_DBADMIN` (default `appbuilder-admin`), `appbuilder` uses
`MYSQL_DBPREFIX` (default `appbuilder`); `req.tenantDB()` returns
`` `<prefix>-<tenantID>` ``. Because one connection serves many tenant DBs, **SQL must be
DB-qualified**. Locally MariaDB is on `localhost:8899` (`DB_PORT`).

**MariaDB server** (`docker-compose.yml:59-86`): image `digiserve/ab-db` (`FROM mariadb:10`,
a floating tag), started with `mysqld --alter-algorithm=copy --wait-timeout=60
--interactive-timeout=60`. `alter-algorithm=copy` is the documented cure for
`ER_CRASHED_ON_USAGE`; the 60 s timeouts drop idle connections (see the triage table in
AGENTS.md §7.1). `conf.d/my.cnf` contains only `[mysqld]`. The stock image config sets
`expire_logs_days = 10` without binary logging, hence the `--log-bin` warning at boot.

---

## 2. Init scripts (`developer/db/init/`)

These run **only when the `mysql_data` volume is empty**. Editing them does nothing to an
existing stack.

| File | Does |
|---|---|
| `01-CreateDBs.sql` | Creates `appbuilder` and `appbuilder-admin` (utf8mb4), grants root@% everything |
| `02-tenant_manager.sql` | Creates `site_tenant` (`id`, `uuid` (non-unique index), `key` (no index), `properties` longtext JSON) and seeds the `admin` tenant: `{"title":"Tenant Admin","authType":"login","url":"https://[tenantKey].site.url"}` |
| `03-site_tables.sql` | The tenant schema for `appbuilder-admin` plus 217 seed definitions (§3) |
| `04-08` | Accounting stored procedures (§4) |

---

## 3. Tenant schema (`03-site_tables.sql`)

| Table | Purpose and key columns |
|---|---|
| `appbuilder_definition` | Every design artifact: `{id PK, name, type, json, createdAt, updatedAt}` |
| `SITE_USER` | `username` (unique), `password`, `salt`, `email`, `failedLogins`, `isActive`, `languageCode`; several columns default to the **string** `'NULL'` |
| `SITE_ROLE` | Roles (`translations`, `Default Role`); seeds System Admin `dd6c2d34`, System Builder `6cc04894`, Builder `e1be4d22`, Tenant Admin `ee52974b` |
| `SITE_SCOPE` | Scopes: `objectIds`, `Filters`, `allowAll`, `createdBy`; seeds "All Access" `838beeb9` (`allowAll=1`) |
| `AB_JOINMN_ROLE_USER_users` | User-role links (admin gets System Admin + System Builder) |
| `AB_JOINMN_SCOPE_ROLE_roles` | Scope-role links (System Admin gets All Access) |
| `SITE_LANGUAGE` | `language_code` (unique); seeds en, zh-hans, th, ko |
| `site_multilingual_label` | Translated UI labels (`label_key`, `label_label`, `language_code`) |
| `SITE_FILE` | Uploaded file records: `uuid, field, pathFile, file, info JSON, object, size, type, uploadedBy` |
| `SITE_TOKEN` | Login/reset tokens: `uuid, token, context JSON, expires` (default `expires` is a fixed past date) |
| `SITE_ROWLOG` | Record history: `record, timestamp, object, row, level, username` (`usernameReal` added by patch 20221125) |
| `SITE_PROCESS_INSTANCE` | Running BPMN instances: `xmlDefinition`, `context`, `processID`, `status` (default `created`), `triggeredBy` |
| `SITE_PROCESS_FORM` | Inbox items (user forms/approvals): `status` (default `pending`), `ui`, `data`, `process`, `responder` |
| `AB_JOINMN_ProcessForm_ROLE_roles`, `AB_JOINMN_ProcessForm_USER_users` | Inbox recipients |
| `SITE_QR_APPUSER`, `SITE_RELAY_APPUSER`, `SITE_RELAY_REQUEST_QUEUE`, `SITE_RELAY_USER` | Leftovers of the retired relay/mobile-QR feature |

Tables **added later by migration patches** (§5): `SITE_CONFIG`, `SITE_PENDING_TRIGGER`,
`SITE_KEY`, `SITE_SECRET`, `AB_JOINMN_KEY_ROLE_roles`, `SITE_PROCESS_DEFINITION`,
`SITE_PLUGIN`, `SITE_PLUGIN_LINK`.

**Object tables** created from builder definitions live in the same tenant DB (named
`AB_<app>_<object>` unless the definition sets `tableName`), with junction tables
`AB_JOINMN_...` and query VIEWs `AB_<app>_View_<name>`. See
[server-platform.md §4](server-platform.md).

### Seed data

- **Admin user:** username `admin`, email `admin@email.com`, active, precomputed hash and
  salt (the plaintext is not in the repo).
- **System definitions** mapping the SITE_* tables to AB objects (for example USER
  `228e3d91-5e42-49ec-b37c-59323ae433a1` = SITE_USER, ROLE `c33692f3` = SITE_ROLE), their
  fields, views, data collections and the **Site Administration** application.
- **Seeded processes:** "New User Default Roles" (started by `USER.added`), "approve new
  Role" (approval + email), and **"TestSendMail"**, which on every new user emails a reset
  URL for `no-reply@digiserve.org` to `no-reply@digiserve.org` (looks like leftover test
  data, inferred; patch 20230324 upserts it too).

---

## 4. Accounting stored procedures (`04`-`08`)

Created only in `appbuilder-admin`, against app-generated tables, with hardcoded
list-option ids. Called by BPMN accounting tasks
(`developer/appbuilder/AppBuilder/platform/process/tasks/`):

| Procedure | File | Caller |
|---|---|---|
| `BALANCE_PROCESS` | `04-balance_store_procedure.sql` | `ABProcessTaskServiceAccountingBatchProcessing.js` |
| `JEARCHIVE_PROCESS` | `05-jeArchive_store_procedure.sql` | `ABProcessTaskServiceAccountingJEArchive.js` |
| `CLOSE_FP_PROCESS` | `06-accounting_fp_close.sql` | `ABProcessTaskServiceAccountingFPClose.js` |
| `CLOSE_FY_YEAR_PROCESS` | `07-fp_year_close.sql` | `ABProcessTaskServiceAccountingFPYearClose.js` |
| `REVIEW_EXPENSE_REPORT_INBOX` | `08-review_expense_report_inbox.sql` | no caller found |

Traps (inferred): other tenants do not get these procedures, so accounting tasks there
would fail; `06` computes `(month+1) MOD 12`, so closing M11 yields `M00`; `08` deletes
from a database named `site`, which does not exist.

---

## 5. Migrations

Two different things are called "migration":

1. **Definition-driven DDL** (objects/fields/indexes/queries to tables, columns, views):
   run by `definition_manager.migrate-*` handlers when the designer saves. See
   [server-platform.md §7](server-platform.md).
2. **Platform SQL patches** in `developer/migration_manager/patches/`, applied to
   every tenant by migration_manager on each `npm start`. Described here.

### How patches are applied (`developer/migration_manager/app.js`)

- Discover every file in `patches/` (`readdirSync` order, no explicit sort).
- For each tenant in `site_tenant` (in parallel): `USE <tenantDB>`, read
  `SITE_CONFIG.value` where `key = "migration-last-patch"` (`ER_NO_SUCH_TABLE` means
  start from `""`), and apply every patch whose **filename compares greater as a string**
  (`if (lastPatch < patch)`, `:265`).
- Each patch is split on every `;`; empty fragments are skipped; the first error stops that
  tenant and the last good patch name is saved. No transactions.

### Patch list

| Patch | Committed | What it does |
|---|---|---|
| `00000000.sql` | 2023-01-11 | Creates `SITE_CONFIG` (key/value) with `migration-last-patch` |
| `20221125.sql` | 2023-01-11 | Switcheroo: "Switcheroo" role `320ef94a`; `SITE_ROWLOG.usernameReal` |
| `20230112.sql` | 2023-01-20 | Failed-trigger cache: unique `SITE_PROCESS_INSTANCE.instanceKey`, `SITE_PENDING_TRIGGER`, 5 definitions |
| `20230321.sql` | 2023-03-21 | `SITE_PROCESS_FORM.scopeQuery` JSON |
| `20230324.sql` | 2023-03-24 | Scope editing in Site Admin: upserts 73 definitions (incl. "TestSendMail", "New User Default Roles") |
| `20230501.sql` | 2023-05-01 | Tenant Admin user management: Site Administration app update, "User Management" scope `fc5055b6` |
| `20231024.sql` | 2023-10-24 | Adds the `_system_` user (inactive, no password) for cron/system processes |
| `20231031.sql` | 2023-10-31 | KEY/SECRET: `SITE_KEY`; **drops and recreates** `AB_JOINMN_KEY_ROLE_roles` and `SITE_SECRET` |
| `20240619.sql` | 2024-06-25 | `SITE_PROCESS_DEFINITION` (hash + JSON); `SITE_PROCESS_INSTANCE.definition` FK |
| `20261111.sql` | **2025-11-11** | Plugins: SitePlugins (`SITE_PLUGIN`) and SitePluginLinks (`SITE_PLUGIN_LINK`, platform list service/web/pwa) objects, "Plugin Add" page, Plugins grid; overwrites Site Administration id lists |

### Traps

1. **The year typo in `20261111.sql` hides new patches.** It was committed on 2025-11-11
   (author pong.promrat, "Add new PlugIn definitions and tables"), so every tenant has
   recorded `migration-last-patch = 20261111.sql`. **Any new patch named with a real date
   before 2026-11-11 compares lower and is skipped forever, silently.** Until this is
   fixed, name new patches so they sort after `20261111.sql` (for example `20261112.sql`,
   or a zero-padded scheme that sorts higher).
2. **The `;` split** means no semicolons inside string literals or JSON values, and no
   stored procedures, in patches.
3. **Not every patch is re-runnable:** re-running `20231031` wipes `SITE_SECRET` and the
   key-role links (happens if `SITE_CONFIG` is missing or after a partial failure);
   `20240619` adds an unnamed FK each time (inferred).
4. Patches that upsert system definitions or `JSON_SET` id arrays overwrite any tenant
   changes to those system definitions.
5. `USE <db>` runs on an isolated pool; a reconnect mid-run would send the remaining
   statements to the default `appbuilder` database (inferred).
6. If `SITE_CONFIG` exists without the `migration-last-patch` row, `results[0].value`
   throws and that tenant is skipped.
7. `node --watch` reruns migration_manager when JS changes, not when a patch is added:
   restart with `npm stop && npm start`.

---

## 6. Creating a tenant

`tenant_manager.tenant-add` (details in [services.md §7](services.md#7-tenant_manager-esm-typemodule-since-2026-09-29)):
inserts `site_tenant`, fills `developer/tenant_manager/utils/new_tenant.sql`
(`CREATE DATABASE appbuilder-<uuid>`, the core SITE_* tables without the relay tables,
admin user, four roles, All Access scope, 218 definitions), writes it to `new-<key>.sql`
in the service directory (never deleted, contains the admin hash), and runs it statement by
statement.

The new tenant has **no** `SITE_CONFIG`, `SITE_PENDING_TRIGGER`, `SITE_KEY`, `SITE_SECRET`,
`SITE_PROCESS_DEFINITION`, `SITE_PLUGIN*` and no stored procedures until migration_manager
runs (next `npm start`). AGENTS.md §7 already notes the missing `SITE_CONFIG`.

---

## 7. Test reset

`test/setup/reset.sh` (used by `npm run test:reset` and Cypress `cy.ResetDB()`) pipes
`03-site_tables.sql` and `02-tenant_manager.sql` into `appbuilder-$TENANT`, but both files
start with `USE appbuilder-admin`, so the reset always hits the admin database (inferred).
It also removes `SITE_CONFIG`, so migration_manager must run afterwards. See
[testing.md](../testing.md).
