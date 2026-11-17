# AppBuilder developer documentation

Reference documentation for this repo and its 17 submodules. Start with
[AGENTS.md](../AGENTS.md) (rules, destructive scripts, traps, validation) and
[architecture.md](core/architecture.md) (how the pieces fit). Then open the page for the area
you are changing.

All pages were verified against the code in late September / early October 2026. Each page
states the commits it was checked against. Claims are cited as `path:line`. Line numbers
drift, so search by symbol name first. "Inferred" marks behavior reasoned from code but not
run.

This repo documents the AppBuilder **platform**: `core/` and `plugins/`, plus a few pages
here at the top. Apps that users build with AppBuilder are the user's side, and their pages
belong in the app's own repo. The one exception for now is NetSuite HR Update, kept here at
the top because the HR Teams plugin is built on it (owner, 2026-10-04).

### [core/](core/): the AppBuilder platform (the code in the submodules)

| Page | Read it when you work on |
|---|---|
| [architecture.md](core/architecture.md) | Anything: messaging (cote), definitions, core/platform split, multi-tenancy, request lifecycle, front-end generations |
| [domain-model.md](core/domain-model.md) | class_core: applications, objects, the 19 field types, queries, data collections, filters, process query language, translations |
| [server-platform.md](core/server-platform.md) | platform_service: per-tenant factories, knex/Objection, condition-to-SQL compiler, scopes, DDL from definitions, NetSuite and API objects |
| [service-runtime.md](core/service-runtime.md) | ab-utils: controller, the `req` object, `serviceRequest` retries, validation, pub/sub, notifications, telemetry |
| [services.md](core/services.md) | Backend microservices: every handler key, config, write lifecycle, traps |
| [processes.md](core/processes.md) | BPMN: element types, engine, triggers, timers, inbox and user forms, designer, building a process from the browser console |
| [api.md](core/api.md) | api_sails: every route, policies, authentication, sockets and realtime, boot payload, security findings |
| [database.md](core/database.md) | Databases, tables, seed data, stored procedures, migration patches, tenant creation |
| [frontend.md](core/frontend.md) | platform_web: the browser portal, boot, network layer, browser platform classes, plugin system, build, building definitions from the browser console |
| [widgets.md](core/widgets.md) | Every built-in web widget (view) type and its settings |
| [mobile.md](core/mobile.md) | The mobile PWA and mobile view types |
| [site-administration.md](core/site-administration.md) | The built-in Site Administration app, the apps in the tenant, and the tenant's users, roles and scopes |

### [plugins/](plugins/): the plugins

| Page | Read it when you work on |
|---|---|
| [abdesigner.md](plugins/abdesigner.md) | AB Designer, the builder IDE (an *app*-type plugin) |
| [hrteams-widget.md](plugins/hrteams-widget.md) | **Everything about the HR Teams plugin** (a *widget*-type plugin): build and cache-busting, the principal flow in the widget, data collections, every feature, testing notes. Its §6 overlaps netsuite-hr-update.md on purpose |

### Here at the top: no category

| Page | Read it when you work on |
|---|---|
| [netsuite-hr-update.md](netsuite-hr-update.md) | **Everything about the NetSuite HR Update app**: objects, processes and their run history, who can see what (HR scope), the cross-entity principal change (`cache-principal-change` + "Principal Change Approval": design, tests, test plan, production checklist), and the separate Global HR Update web app where it meets the app (§13). Old definitions are in [backups/definitions/](../backups/definitions/). An app page, kept here for now (see above) |
| [known-issues.md](known-issues.md) | The backlog: every known problem, with an ID and a priority, to fix later |
| [testing.md](testing.md) | Cypress e2e harness, unit tests, and testing by hand in the browser (switcheroo, REST calls from the console, browser automation) |
| [orchestration.md](orchestration.md) | Compose services, environment variables, scripts, logs (reference tables) |

## Keeping these pages right

- The house rule in AGENTS.md §2.0 applies: write down every verified finding, and correct
  a wrong claim in place instead of adding a second, conflicting note.
- When you change behavior that a page describes, update that page in the same change.
- Everything about the NetSuite HR Update app goes in netsuite-hr-update.md, everything
  about the HR Teams plugin in hrteams-widget.md (they may overlap); add a section there
  rather than a new page for one feature. New platform pages go in `core/` (built-in apps
  such as Site Administration included) or `plugins/`, otherwise here at the top; pages of
  apps that users build with AppBuilder belong in those apps' own repos (owner, 2026-10-04).
  Platform facts learned in a test app go into the page of their subject, not into a page
  about the test app.
- Re-verify before relying on a line number; prefer quoting the symbol name.
