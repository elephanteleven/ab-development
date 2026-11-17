# Site Administration, and the tenant's users, roles and scopes

The **Site Administration** app (built in: users, roles, scopes, plugins), the other apps a
builder or admin finds after logging in to the local `admin` tenant, and the tenant's
users, roles and scopes. Renamed from `tenant-apps.md` on 2026-10-04; what concerns only the
NetSuite HR Update app (its HR scope, its local data) is in
[netsuite-hr-update.md](../netsuite-hr-update.md). The owner's intent for the three apps is in
[AGENTS.md §1](../../AGENTS.md#1-what-this-repo-is). Read from the running stack on
2026-10-02 (browser factory and read-only `findAll` calls). No definition was changed; the
test users, role and scope in §3 were added as data.

---

## 1. The entries in the sidebar

| Entry | Kind | What it is |
|---|---|---|
| Site Administration (`227bcbb3-…`) | Definition app, `isSystemObject` | Built-in: users, roles, scopes, plugins. Open to System Builder, System Admin, Builder and Tenant Admin |
| AB Designer | v0 plugin of the *app* type (not a definition) | The IDE for AppBuilder developers ([abdesigner.md](../plugins/abdesigner.md)). Only builders get the script |
| Claude Sandbox (`0f7fe184-…`) | Definition app, created 2026-10-02 | The agents' sandbox for definition experiments ([abdesigner.md §13](../plugins/abdesigner.md#13-walkthrough-building-an-app-from-scratch-observed)); safe to change or delete |
| Claude Mobile Sandbox (`76702f6c-…`) | Mobile definition app, created 2026-10-02 | Sandbox for the PWA ([mobile.md §2](mobile.md#2-boot-sequence)); safe to change or delete |
| NetSuite HR Update (`79e11053-…`) | Definition app | The product app; everything about it is in [netsuite-hr-update.md](../netsuite-hr-update.md). Uses the HR Teams *widget* plugin ([hrteams-widget.md](../plugins/hrteams-widget.md)) |

The tenant holds 559 definitions: 2 applications, 31 objects (16 system, 12 NetSuite),
291 fields, 137 views, 17 data collections, 1 query, 7 processes with their tasks, 5
triggers and 4 indexes. Five system objects belong to no app: ProcessInstance,
ProcessDefinition, Key, Secret, SITE_PENDING_TRIGGER.

---

## 2. Site Administration

One page, "Site Admin", with a tab view:

| Tab | Contents | Notes |
|---|---|---|
| Users - Super Admin | Users grid plus an Info form (username, email, active, send email notifications, failed logins, language, last login) and a Roles tab | Popups: Add User, Adjust Roles |
| Roles & Scopes | Roles grid; per role an Info form, its Scopes and its Users | Popups: Add Role, Assign Scope, Assign Users, Add Scope, Edit Scope (scope filters are edited as JSON) |
| Users | A tenant-admin users grid with a data filter | Only this tab has an access level set: Tenant Admin = 2. "Add User - Default Roles" form |
| Settings | A "Relay" tab with QR Codes text and image | **Leftover of the retired relay service** ([AGENTS.md §7](../../AGENTS.md#7-traps)); the QR image is a stored file, but the mobile QR flow it belongs to no longer exists |
| Plugins | Grid over `SITE_PLUGIN` | Empty here: no v1 plugins are installed, and `SITE_PLUGIN_LINK` is empty, so `window.__AB_plugins_v1` is `[]` |

Its objects are all system tables: `SITE_USER`, `SITE_ROLE`, `SITE_SCOPE`,
`SITE_PROCESS_FORM`, `SITE_ROWLOG`, `SITE_LANGUAGE`, `SITE_FILE`,
`site_multilingual_label`, `SITE_PLUGIN`, `SITE_PLUGIN_LINK`, `SITE_TOKEN`.

Its processes: "approve new Role" (Role added → Approval "Approve Role" → Email "sent
email" → End) and "New User Default Roles" (Get default roles → Update Record → an
intermediate throw event; seeded in every tenant, [processes.md §7](processes.md#7-traps)
trap 30).

---

## 3. Users, roles and scopes here

Users: `admin` (active) and `_system_` (inactive; the identity background jobs run as).
Test users added on 2026-10-02 (no passwords, used through switcheroo): `sandbox.viewer`
(role Sandbox Viewer, §3.1) and `hr.mock.aep` (HR Generalists, linked to
entity 1805 AEP, [netsuite-hr-update.md §7](../netsuite-hr-update.md#7-a-test-run-as-a-mock-hr-generalist-2026-10-02)).
Added on 2026-10-03, the same way: `hr.mock.pxy` (entity 2715 PXY) and `hr.mock.pxr`
(entity 4925 PXR), for the cross-entity test in
[netsuite-hr-update.md §8](../netsuite-hr-update.md#8-a-cross-entity-principal-move-end-to-end-2026-10-03).
Added on 2026-10-05 at the owner's request: `hr.mock.cni`
(`eaca2504-6d9a-479d-a832-b1171c183dfb`, HR Generalists, entity 5451 "CNI - NS Track"),
made with REST calls from a JSON page so the portal never loaded as admin
([testing.md §3.2](../testing.md#32-rest-calls-from-the-browser-console)): `POST` of the
user to the user object (`228e3d91-…`), `POST` of the `entity` row with `User` set, then a
`PUT` of `sendEmailNotifications: 0`, which the plain `POST` had left NULL.

| Role | Scopes | Users |
|---|---|---|
| System Admin (`dd6c2d34`) | All Access | admin |
| System Builder (`6cc04894`) | none | admin |
| Builder (`e1be4d22`) | none | admin |
| Switcheroo (`320ef94a`) | none | admin |
| HR Generalists (`39ae03d7`) | Netsuite Entity | admin |
| Core Finance (`e32dbd38`) | Finance | nobody |
| Tenant Admin (`ee52974b`) | User Management | nobody |

How a scope works is in [server-platform.md](server-platform.md) (`includeScopes`):
the rules of every scope of the user's roles are added to each read on the listed objects.
In the stored `Filters`, each rule's `key` is a **field id**; the table below shows the
field names instead, for reading. A rule whose key is not a field id of the object being
read is dropped without a warning (tested 2026-10-02, §3.1).

| Scope | Objects | Rule |
|---|---|---|
| All Access | all (`allowAll`) | none |
| Netsuite Entity | NetSuite HR Update objects | The HR row-level security, by entity: [netsuite-hr-update.md §11](../netsuite-hr-update.md#11-who-can-see-what-hr-generalists) |
| Finance | NetSuite HR Update objects | The same query, on entity and NS Entity only ([netsuite-hr-update.md §11](../netsuite-hr-update.md#11-who-can-see-what-hr-generalists)) |
| User Management | site user, Role | hides one user uuid and the Switcheroo, System Admin and System Builder roles |

**The HR row-level security** (which entities an HR Generalist sees, what the scope does
not cover, the local `entity` rows and the other local data of the app) moved to
[netsuite-hr-update.md §11](../netsuite-hr-update.md#11-who-can-see-what-hr-generalists) on
2026-10-04, with the rest of what concerns that app.

### 3.1 What a scope does, tested on 2026-10-02

Set up as data in Site Administration's tables (no definition changed): role **Sandbox
Viewer** (`8f2f758e-…`), created with `AB.objectRole().model().create()`; scope **Sandbox
To Do** (`836dfb32-…`: `allowAll: 0`, `objectIds` = one test object, `Filters` with one rule
on its Status field), linked to the role through `AB_JOINMN_SCOPE_ROLE_roles`; user
**sandbox.viewer** (`42c1eb70-…`, `isActive: 1`, no password) with that role
(`AB_JOINMN_ROLE_USER_users` stores the **username**, not the uuid); and the role added to
the test app's `roleAccess`. Switched to that user
([testing.md §3.1](../testing.md#31-acting-as-another-user-switcheroo)):

- Only the test app showed (role access works), and no ABDesigner. The HR Teams plugin
  still loaded, because it is chosen per tenant, not per role
  ([hrteams-widget.md §1.2](../plugins/hrteams-widget.md#12-which-tenants-load-it-at-all)).
- An object that no scope lists returned **0 rows** (`includeScopes` adds `1 = 0`).
- With the rule keyed `"Sandbox Item.Status"`, the scoped object returned **all 4 rows**:
  `includeScopes` keeps only rules whose key is a field id, so it dropped the rule without
  a warning and applied no filter (known issue S33).
- With the key set to the Status field's id, only the **2 "todo" rows** came back, and a
  user filter for "done" on top returned 0 rows: scope rules are ANDed with the request's
  `where`.

The role, scope and user are still in the tenant; they grant access only to the test app.

---

## 4. Testing note

How to test as another user (switching without loading the portal as admin, checking the
switch with `/config/preloader`, role caching), REST calls from the console, and the hidden
tab that browser automation drives:
[testing.md §3](../testing.md#3-testing-by-hand-in-the-browser). Test users in this tenant:
`sandbox.viewer` (§3.1) and the mock HR users `hr.mock.aep`, `hr.mock.pxy`, `hr.mock.pxr`,
`hr.mock.cni` (HR Generalists only).
