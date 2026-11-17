# Orchestration reference

Reference tables for this repo's own files: compose services, environment variables,
scripts, logs. AGENTS.md §2-§4 holds the rules and traps; this page holds the inventories.
Verified on 2026-10-02 (root `main` with uncommitted doc/relay edits).

---

## 1. Compose services (`docker-compose.yml`)

All 11 Node services except migration_manager get `COTE_DISCOVERY_REDIS_HOST=redis` and
`MYSQL_PASSWORD`; all except api_sails run `node --inspect=0.0.0.0:9229 --watch app.js`.
Each Node service mounts only its own repo, `./developer/<service>`, at `/app`. The six
AppBuilder services (appbuilder, custom_reports, definition_manager, file_processor,
process_manager, user_manager) carry platform_service and class_core inside that repo as
nested submodules (`AppBuilder`, `AppBuilder/core`), and ab-utils comes from each repo's
own `node_modules`.

| Service | Image | Host ports | Notable mounts / env |
|---|---|---|---|
| web | `digiserve/ab-web:$AB_WEB_VERSION` | `$WEB_PORT:80` | `developer/web` at `/app` (its `assets/` holds the UI builds), `developer/plugins` at `assets/ab_plugins`, `developer/web/default.conf`, `nginx/html`, `files:/data` |
| db | `digiserve/ab-db:$AB_DB_VERSION` | `$DB_PORT:3306` | reset.sh, reset-user.sql, conf.d, init, `mysql_data`; `mysqld --alter-algorithm=copy --wait-timeout=60 --interactive-timeout=60` |
| redis | `redis:$AB_REDIS_VERSION` | none | `redis_data`, `--appendonly yes` |
| migration_manager | `ab-migration-manager` | 9229 | depends on db; run-once script |
| api_sails | `ab-api-sails` | 1337, 9230 | `AB_TESTING=true`, `NODE_ENV=development`, CAS_*, OKTA_*, SITE_URL, SAILS_SESSION_SECRET; logs/appbuilder, `test/e2e/cypress/e2e` at `/app/imports`, `files:/data`; no command override (no `--watch`) |
| appbuilder | `ab-appbuilder` | 9231 | APPBUILDER_ENABLE, CIRCUITBREAKER_*, NETSUITE_* |
| custom_reports | `ab-custom-reports` | 9232 | `CUSTOM_REPORTS_ENABLED` (the service reads `..._ENABLE`) |
| definition_manager | `ab-definition-manager` | 9233 | DEFINITION_MANAGER_ENABLE |
| file_processor | `ab-file-processor` | 9234 | FILE_PROCESSOR_ENABLE, `files:/data` |
| log_manager | `ab-log-manager` | 9236 | SENTRY_ENABLED (read by nothing), SENTRY_DSN, SENTRY_SAMPLE_RATE, SENTRY_SERVER_NAME |
| notification_email | `ab-notification-email` | 9237 | NOTIFICATION_EMAIL_*, SMTP_* |
| process_manager | `ab-process-manager` | 9238 | NETSUITE_* |
| tenant_manager | `ab-tenant-manager` | 9240 | TENANT_MANAGER_ENABLE |
| user_manager | `ab-user-manager` | 9241 | USER_MANAGER_ENABLE, USER_MANAGER_MAX_FAILED_LOGINS |

Images are `docker.io/digiserve/ab-<name>:$AB_<NAME>_VERSION` (`guy-latest` locally; see
AGENTS.md §2.1 for building them).

---

## 2. Environment variables (`example.env`)

`.env` is per-developer and gitignored; never print its values (it can hold real SMTP and
NetSuite credentials).

| Variable(s) | Consumer |
|---|---|
| `NODE_ENV` | npm/Cypress process env only (api_sails hardcodes its own) |
| `STACKNAME`, `CYPRESS_STACK` | Swarm and test scripts (not the compose project name) |
| `PLATFORM`, `SSL_PATH_*`, `BOT_*` | No reader |
| `MYSQL_PASSWORD` | db root password and every Node service (`ab-utils/utils/defaults.js`) |
| `WEB_PORT`, `DB_PORT` | Host port mappings |
| `NETSUITE_*` (7) | appbuilder and process_manager (NetSuite objects) |
| `CAS_*`, `OKTA_*`, `SITE_URL` | api_sails auth |
| `AB_*_VERSION` (14) | Image tags (test-reset.sh ignores the migration manager one) |
| `CYPRESS_TENANT`, `CYPRESS_DB_USER`, `CYPRESS_DB_PASSWORD`, `CYPRESS_USER_EMAIL`, `CYPRESS_USER_PASSWORD`, `CYPRESS_BASE_URL` | Cypress (and db env for reset.sh) |
| `SAILS_SESSION_SECRET` | api_sails session secret (hardcoded fallback if unset) |
| `MYSQL_HOST/PORT/USER/DBPREFIX/DBADMIN` (commented) | Read by ab-utils, but compose passthroughs are commented, so no effect |
| `APPBUILDER_ENABLE`, `CIRCUITBREAKER_*` | appbuilder (the circuit settings are ignored, see [services.md §1](core/services.md#1-appbuilder)) |
| `CUSTOM_REPORTS_ENABLE` | Name mismatch with compose's `..._ENABLED`: no effect |
| `DEFINITION_MANAGER_ENABLE`, `FILE_PROCESSOR_ENABLE`, `TENANT_MANAGER_ENABLE`, `USER_MANAGER_*`, `NOTIFICATION_EMAIL_*`, `SMTP_*` | Passed and read |
| `FILE_PROCESSOR_PATH/UPLOAD_DIR/MAXBYTES`, `CLAMAV_ENABLED`, `LOG_MANAGER_ENABLE`, `SMTP_AUTH`, `PROCESS_MANAGER_ENABLE`, `TENANT_MANAGER_TENANT_ID` | Readers exist, but compose never passes them |
| `SENTRY_DSN` | Read by every service's `app.js`, but passed only to log_manager |
| `TELEMETRY_PROVIDER` | Read by every service (default `sentry`), passed to none |

api_sails reads `RELAY_ENABLE` (default `true`) and `RELAY_SERVER_TOKEN` (default
`"There is no spoon."`), and compose passes neither (it passes the misspelled
`RELAY_ENABLED`), so the relay strategy stays on with its default token (known issues S38).

---

## 3. npm scripts and shell scripts

| Script | Behavior |
|---|---|
| `npm start` / `npm stop` / `npm run logs` | `docker compose up -d` / `down` / `logs -f` (with a `docker-compose` v1 fallback). **The only lifecycle commands to use** (AGENTS.md §2.0) |
| `npm run build` / `build:prod` | `build.sh` with tag `guy-latest` (prod runs it twice). Destructive, pushes images (AGENTS.md §2.1) |
| `npm run dev:update` | `dev-update.sh`: seed `.env` and `config/local.js`, init submodules, per repo pull the canonical branch and return, `git submodule update --init --recursive` in repos with nested submodules, `npm install -f` (clears `npm_config_allow_scripts`, passes `allow-git=all`) and `npm ci` in each `AppBuilder`, guarded stash |
| `npm run watch` in each UI repo | Not an npm script of this repo: run it by hand in `developer/ab_platform_web`, `developer/pwa`, `developer/plugins/ABDesigner` and `developer/plugins/HRTeams`; each writes into `developer/web/assets` (owner) |
| `npm run start:test` / `stop:test` / `logs:test` / `test:reset` | Second stack with `-p $CYPRESS_STACK`; reset via `test-reset.sh` |
| `npm run test:e2e*`, `cypress:open` | Cypress ([testing.md](testing.md)) |
| `npm run swarm:start` / `swarm:stop` | `docker stack deploy/rm $STACKNAME` (not the dev path); `swarm:logs` is broken |
| `dev.sh` | Starts Claude Code with `--dangerously-skip-permissions` (permission prompts disabled) |

`build.sh` never builds pwa: the web image ships the `assets/mobile` that the web repo's
master holds. In the 2026-10-05 build no `assets/mobile` file changed, while the other three
UI builds changed `index.html`, two of its chunks and the HRTeams files in `tenant/default`.

---

## 4. Logs, fail2ban, legacy folders

- `logs/appbuilder/auth.log`: written by api_sails' authLogger (`<ISO>  [<ip>]  <message>`);
  `logs/fail2ban/filter.d/appbuilder.conf` matches `^\s+\[<HOST>\]\s+.+FAILED$` with a jail
  example. On rootless Docker it needs the ACL in AGENTS.md §7.
- `nginx/default.conf` and `nginx/custom_log.conf`: a legacy SSL front-end template
  (redirect 80 to 443, old TLS settings), not mounted. `nginx/html` is mounted but served by
  no nginx location (inferred). `nginx/ssl/`, `redis/data/`, root `assets/`: unused.
- `config/example.local.js` / `config/local.js`: Sails-style local config, not mounted.
