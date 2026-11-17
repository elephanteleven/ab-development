# Known issues (backlog)

One list of every problem found while reading and documenting the codebase, from late
September to 2026-10-03. **Nothing here is fixed in git yet:** section 1 lists fixes that
exist only in the working tree, and everything else is still open. The evidence and the
full explanation live in the linked doc sections. This page gives each item a stable
ID and a priority, so we can come back later and work through them.

## How to use this page

- **Before fixing**, read the linked section and re-check the code: line numbers drift,
  and a submodule may have moved on.
- **After fixing**, update the linked doc in place (AGENTS.md §2.0), then tick the box here
  and add the date and commit, for example `(fixed 2026-10-15, api_sails 1a2b3c4)`.
- Keep the IDs. Do not renumber; add new items at the end of their section.
- Labels: **V** = verified by reading the code. **I** = inferred from the code, not run.
  **T** = seen at runtime.
- Priority: **P1** = security, data exposure, or a feature that is broken today.
  **P2** = wrong behavior users or builders can hit. **P3** = environment, tooling, tests.
  **P4** = small bugs and code quality.

---

**Owner decisions of 2026-10-03:** platform-level problems are listed here and not fixed
for now, while work focuses on the NetSuite HR Update app, its processes and the HR Teams
plugin ([AGENTS.md §2.0](../AGENTS.md#20-house-rules)). PE14 and PE15 were the next step:
on 2026-10-03 the cross-entity principal change moved to a cache row and a new process
([netsuite-hr-update.md §12](netsuite-hr-update.md#12-the-cross-entity-principal-change-since-2026-10-03); C9, C10), which takes PE11, PE13,
PE14, PE16, PE17, W26 and B25 off that path. PE13 is ignored for now. The platform causes
(B25, PE15, S35/D6, W24 and the rest) stay listed.

## 1. Finish first: fixes made but not committed

Fixes made here that no upstream branch has. Committing needs the owner's go-ahead
(AGENTS.md §2.2).

On 2026-10-30 the owner had every repo under `developer/` put back to its clean upstream
state, because local edits on top of old checkouts made it unclear which version was
running. C1 to C5 and C7 were dropped then (C2 had already gone with an earlier checkout of
`staging`); their patches stay in `backups/patches/2026-10-05/`, and the state of each repo
before that day is in `backups/patches/2026-10-30/state-before-restore.txt`. The problems
they fixed are back, and each entry says how it shows (AGENTS.md §7.1).

- [x] **C1** Dropped 2026-10-30. ab-utils: `utils/defaults.js` no longer logged env values
  (it printed `SMTP_PASSWORD`, S39), and `utils/controller.js` closed the MySQL probe with
  `end()`. The edits were made by hand in each service's installed copy. Patch:
  `backups/patches/2026-10-05/ab-utils.patch`; re-apply from the repo root with
  `for s in api_sails appbuilder custom_reports definition_manager file_processor log_manager migration_manager notification_email process_manager tenant_manager user_manager; do git -C developer/$s apply --directory=node_modules/@digiserve/ab-utils --include='*/utils/*' "$PWD/backups/patches/2026-10-05/ab-utils.patch"; done`
  (removed on 2026-10-30 with `git apply -R` and the same arguments). A lasting fix needs
  an ab-utils release that the services declare.
- [x] **C2** Dropped before 2026-10-30, when api_sails was checked out on `staging`.
  api_sails: relay removed (strategy, routes `GET /relay/user-qr` and `GET /mobile/qr/:ID`,
  ping lists, config block, README sections; S38), `app_waitMysql.js` used `end()`, the dead
  `/admin` route was commented out, and `config/local.js` had `datastores` uncommented, which
  `app_waitMysql.js` needs (E14). Patch: `backups/patches/2026-10-05/api_sails.patch`.
- [x] **C3** Dropped 2026-10-30. migration_manager: `app.js` used `end()` and closed ab-utils'
  shared pool. Patch: `migration_manager.patch`.
- [x] **C4** Dropped 2026-10-30. platform_service: `ABFactory.js` knex pool `min: 0` (stops
  `ECONNRESET`) in the nested copy of each AppBuilder service. Patch:
  `platform_service.patch`; to put it into a copy again, run
  `git -C developer/<service>/AppBuilder apply "$PWD/backups/patches/2026-10-05/platform_service.patch"`
  from the repo root.
- [x] **C5** Dropped 2026-10-30. tenant_manager: `package.json` got `"type": "module"`.
  Patch: `tenant_manager.patch`.
- [ ] **C6** root repo (branch `main`): `docker-compose.yml`, `example.env`, `.gitignore`,
  `.gitmodules`, `.gitmodulescp`, `build.sh` and `dev-update.sh`; `AGENTS.md` and every page
  under `docs/`.
- [x] **C7** Restored 2026-10-30. The `package-lock.json` changes in platform_service (each
  `AppBuilder`) and definition_manager came from `npm install` and changed only the
  package's own version string, so the installed `node_modules` still match.
- [ ] **C8** Not in git at all: the ACL on `logs/appbuilder` for rootless Docker. It must be
  redone on every new checkout ([AGENTS.md §7](../AGENTS.md#7-traps)).
- [ ] **C9** (committed by the owner on 2026-10-16 as `cc217ce` "Caching principal
  assignment" on `guy/enhancements`, identical to
  [backups/patches/2026-10-05/HRTeams.patch](../backups/patches/2026-10-05/HRTeams.patch),
  then `18ed42d`, which moves the principal cleanup out of the `try` so the spinner change
  matches C11. The owner later recommitted that move as `e1757fe` (same content) and merged
  `master` (`d47738c`, the spinner fix and 1.0.22) into the branch as `2e39ac6`: no
  conflict, the same tree as an automatic merge, and the only files it brought in were
  `package.json` and `package-lock.json`. Checked on 2026-10-16: lint as in `cc217ce`, the
  build compiles, and 4 hard reloads as hr.mock.cni loaded in 11 to 12 s with the
  `cache-principal-change` DC loaded, no console error, and 5 dropped loads settled each
  time. Pushed to GitHub on 2026-10-30 at the owner's request (`2e39ac6`; the branch had
  been deleted there after PR #50, so the push made it again); no PR, not on `master`
  yet) HRTeams on branch **`guy/enhancements`** (not `master`), 2026-10-03 and
  2026-10-04: `ABViewOrgChartTeamsComponent.js`, `libs/CustomProcessTasks.js`,
  `components/constants.js` and `components/dcContainer.js`. A principal change that needs
  approval writes a `cache-principal-change` row (reason dialog, one pending request per
  person) instead of saving `"1"` then `"0"`, through the widget's own data collection;
  finished rows are deleted when the process's status change reaches an open chart (with a
  message to the requester and a reload of the chart) or on the next refresh; the
  reason-Form hiding code is removed. Lint: no new errors against HEAD (the plugin's lint
  already fails there). Must be released together with C10. On 2026-10-04 also the 7-day
  expiry: `expires_on` on create, the duplicate check and the cleanup skip and delete
  expired requests, new messages
  ([netsuite-hr-update.md §12.9](netsuite-hr-update.md#129-expiry-after-7-days-since-2026-10-04)).
  On 2026-10-05 the fix for the stuck "Please wait" card (W27): `components/utils.js`
  (`guardDC()`), `components/data_panel/rcDataPanel.js` and `refresh()` in
  `ABViewOrgChartTeamsComponent.js`
  ([hrteams-widget.md §5](plugins/hrteams-widget.md#5-testing-notes)).
  [netsuite-hr-update.md §12](netsuite-hr-update.md#12-the-cross-entity-principal-change-since-2026-10-03)
- [ ] **C10** Not in git: definitions and data in the local `admin` tenant, 2026-10-03. New
  object `cache-principal-change` and process "Principal Change Approval" (renamed on
  2026-10-04 from "cache-principal-change approval") in NetSuite
  HR Update; "Updated Assignments" without its cross-entity part (24 elements deleted); the
  object and two rules added to the "Netsuite Entity" scope. Backups of what changed are in
  [backups/definitions/](../backups/definitions/). Getting this to production is D8. On
  2026-10-04 also the field `expires_on`, the gateway "Has the Request Expired?", "Mark the
  Request Expired", the notice "Principal Change Expired", the approval form's expiry lines
  and Close button, and "Is Approved?" No = not `approve` (backups of both definitions
  before that change are in the same folder). On 2026-10-30, with the owner's go-ahead,
  "Updated Assignments" was put back to its 2026-10-03 version (41 elements, with the
  reason Form) for the GitHub #537 tests with HR Teams `master`; the object, the new process
  and the scope rules stay. The 17-element version and every definition of the tenant from
  just before are in `updated-assignments-2026-10-30.json` and
  `admin-tenant-definitions-2026-10-30.json` there. Switch back before testing
  `guy/enhancements`, whose widget no longer hides the reason Form
  ([netsuite-hr-update.md §2.4](netsuite-hr-update.md#24-switching-versions-in-this-tenant)).
- [x] **C11** (done 2026-10-16: merged as PR #51, `master` `992d96b`; web `master` and
  `staging` at `0f0e6298`, the same content as `943c3ec1` below; the branch was deleted on
  GitHub after the merge) HRTeams on branch **`guy/fix-spinner`**, made from `master` on 2026-10-16 at
  the owner's request so the W27 fix can ship without the principal change, which waits
  for approval. Committed that day as `b1df20a` and pushed to `origin/guy/fix-spinner`.
  The owner merged it into HRTeams `master` the same day (PR #51: `f244609`, same content as
  `b1df20a`; merge `992d96b`; version 1.0.22 in `d47738c`). Its production build is on web
  `master` as `943c3ec1` "Update the HRTeam plugin" (`HRTeams.js*` and `version_hrteam`,
  made in a separate worktree so the web checkout stayed on `develop`); the owner pushed it
  as `0f0e6298` to both `master` and `staging`, and GitHub Actions deployed `staging` to
  `ldhr-test.hrupdate.org`, which served 1.0.22 with the fix from 11:52 UTC
  ([hrteams-widget.md §1.1](plugins/hrteams-widget.md#11-the-cache-busting-trap)). Only the spinner part of `cc217ce`: `components/utils.js` and
  `components/data_panel/rcDataPanel.js` as in `cc217ce`, and the `try/catch/finally` of
  `refresh()` without the `_removeFinishedPrincipalChanges()` call. Lint: 60 problems in
  the component against 62 on `master`, the same in the other two files. Tested that day
  with hard reloads of `/` as hr.mock.cni: `master` hung 4 times in 6 loads; this branch 0
  times in 6 (three of them took 45 to 80 s while NetSuite was slow and rejecting reads,
  and the guard retried, gave up, and let the chart go on; see W27). As made, it conflicts
  with `cc217ce` in `refresh()`: `cc217ce` calls `this._removeFinishedPrincipalChanges()` on
  the first line of the same `try`. Moving that call on `guy/enhancements` to just above
  the `_addProgressStatusQueue()` call that adds "Refreshing" makes the spinner change the
  same in both branches; that move is `18ed42d` (C9). Checked with `git merge-tree` on the
  committed branches (2026-10-16): merging `b1df20a` and `18ed42d` into `master`, in either
  order, has no conflict and gives the same tree, with `utils.js` and `rcDataPanel.js` as
  in `cc217ce`. The cleanup call is not awaited, so its place does not change what it does.
- [x] **C12** HRTeams branch **`guy/fix-principal-changes`**, made from `master`
  (`d47738c`, 1.0.22) on 2026-10-30 for GitHub #537 (W47, W48), and deleted after the
  merge, on GitHub and locally (2026-11-03). Committed that day as
  `28d7b02` "Fix spinning principal changes", pushed, and opened as PR #52 to `master`
  (it says "Related to" #537, so the merge did not close the issue). The owner merged it
  on 2026-11-03 (`abcc4ab`); the release workflow made it 1.0.23 (`5073c51`, tag
  `v1.0.23`), and its production build went to web `master` as `4cdfc151` "Update HRTeams
  plugin" and, by a fast-forward, to `staging` the same day
  ([hrteams-widget.md §1](plugins/hrteams-widget.md#1-how-it-is-built-and-served)).
  Production (web `main`) does not have it yet.
  Changes:
  - `libs/CustomProcessTasks.js`: the constructor no longer throws when the employee or team
    row is missing from its data collection; a new `load()`, called at the start of `run()`,
    reads a missing row from the server (`findAll` on the object's primary key).
  - `ABViewOrgChartTeamsComponent.js`: the edit form calls `load()` before it uses the
    employee's email; `_addUserFormQueue()` stores the email (passed in, or read null-safe)
    and the listener matches on it without throwing; a change that needs approval stops
    waiting for its reason Form after 2 minutes (`TIMEOUT_REASON_FORM`) and says the Form
    will open when it arrives, which it still does; `_showUserForm()` holds a Form while
    the portal's Form window is open and shows it when that window closes; the progress
    card is taken down in a `finally`, so a failed step no longer leaves it up; the card
    text says "it can take a minute or two" instead of "around 15 seconds".

  Lint: 60 errors in the component and 3 in `CustomProcessTasks.js`, as on `master`. Dev
  build compiled. Tested on 2026-10-30 against the 41-element process (C10), on Andorra
  LDHR with real saves: Ed's save with an empty employee collection (made empty for that
  click) went on and read the row from the server; Keith's and Ed's Forms arrived 36 s and
  107 s after their saves and showed one after the other, Ed's when Keith's closed. With
  the writes answered by the test page instead (no Form can come), the spinner stopped
  after 120 s with the message, and a Form sent later still opened. With the save made to
  fail by the test page, the spinner and the progress card went away 1.5 s after the
  failed write. Retested on 2026-10-30 after every repo under `developer/` was put back to
  its clean upstream state (the commit `28d7b02` built and served, api_sails on `app.js`),
  same steps and the same results: Ed's save with an empty employee collection went on;
  Keith's Form came 43.5 s after his save and Ed's 106 s after his (through
  `processTriggerQueue`, PE24), Ed's shown when Keith's closed; the 2-minute limit fired
  at 120.2 s with the message and a later Form still opened; a failed save took the
  spinner and the progress card down within 1.5 s. Four real saves, four runs and four
  `history` rows; both assignments ended at principal `"0"`, and no definition was
  written.

  C12 changes only which Form the browser shows, and when. Answering a Form still goes
  through the portal's window and `userform.update`, which runs the process on. The tests
  above never answered one (the test page blocked `/process/userform`); on 2026-10-31:
  - One of Keith's waiting runs (`f7ed0a4b`) was answered as admin, the user that started
    it, with the request the window sends (`POST /process/userform/<processID>/<taskID>`;
    a Form is pushed only once). The run went on at once and created "Ask Other Entity HR
    to Approve" for admin 67 s later. At the owner's request it was then rejected
    (`PUT /process/inbox/<uuid>`, `response: "reject"`): "Is Approved?" took No, and the
    run waits at "Notify Fails in App", pending for admin. No NetSuite write.
  - Two principal changes made together in the chart, with real saves and both Forms
    answered in the portal's window: Keith's (58906) and Ed's (58905), saved 21 s apart.
    Keith's Form came 46 s after his save. Ed's came 111 s after his, while Keith's was
    open, and did not replace it (Keith's `"0"` run and both of Ed's started together at
    10:34:23 UTC from `processTriggerQueue`, PE24). Keith's answer was posted (200) and
    Ed's Form showed at once; his answer was posted too (200). Each run then created "Ask
    Other Entity HR to Approve" with its own reason, 32 s and 43 s after the answer:
    Keith's for admin, Ed's for admin and hr.mock.cni (Ed has records in 14 other
    entities). As admin, `GET /process/inbox` and the portal's Inbox listed both, beside
    "Notify Fails in App" (all three under one "Notify Fails in App" entry, W28). The two
    `"0"` runs created "Notify of an Edited Assignment" with no recipients, as Andorra has
    no local `entity` row. Writes: four Team Assignment updates (both back at principal
    `"0"`), two answers, four runs and four `history` rows; the four definition saves of
    W24 were blocked, and both definitions were unchanged. process_manager logged no
    error; appbuilder logged the known `rowlog-create` `EINVALIDINPUTS` for each save
    (R26) and the trigger resends. Both
    approvals are still pending; approving one ends and creates Team Assignments in
    NetSuite
    ([netsuite-hr-update.md §9.5](netsuite-hr-update.md#95-after-approval-only-in-the-41-element-version)).

  The other 7 runs of 2026-10-30 that asked for a reason still wait at the Form, and the
  other 8 at "Notify of an Edited Assignment". Keith and Ed have records in several other
  entities, so B25 did not apply. For a person with records in exactly one other entity
  that Approval still goes to nobody (B25, seen twice on 2026-10-03; the code is unchanged
  in process_manager's class_core `2ecde31`, checked 2026-10-31), and C12 does not change
  that. A Form closed with the window's X is never answered
  ([processes.md §5](core/processes.md#5-inbox-and-user-forms)).
- [x] **C13** HRTeams branch **`guy/fix-name-sort`**, made on 2026-11-03 for GitHub #227
  (W49). Committed on top of `master` `5073c51` (1.0.23) as `7a4cfa4` "Fix sorting of
  names with diacritics", pushed, and opened as PR #53 to `master` the same day (labels
  bug and patch; it says "Related to" #227, so the merge did not close the issue). Merged
  at the owner's request on 2026-11-04 (`ecba849`); the release workflow made it 1.0.24
  (`16c05c5`, tag `v1.0.24`). It went to web `master` and `staging` with C14, in the
  1.0.25 build ([hrteams-widget.md §1](plugins/hrteams-widget.md#1-how-it-is-built-and-served)).
  Production (web `main`) does not have it yet. The branch was deleted on GitHub and
  locally on 2026-11-04, after the merge.
  Changes:
  - `components/utils.js`: names compare with one `Intl.Collator("en", { sensitivity:
    "base" })`, so a letter with a diacritic mark sorts with its base letter and case does
    not count, the same for every user. The new `compareNames()` returns only -1, 0 or 1
    (the card code checks `=== -1` and `=== 0`), and a missing record no longer throws.
  - `ABViewOrgChartTeamsComponent.js`: `sortByTeamName()` uses it, and the Change
    Supervisor list breaks a tie on the first name.
  - `components/data_panel/staffDataPanel.js`: the panel breaks a tie on the name it
    shows (preferred name, else first name). Base sensitivity makes "Agoston" and "Ágoston"
    equal, so without it their order would depend on the data.

  Lint: no new errors (2, 8 and 60, as on `master`). Tested on 2026-11-03 as admin in MBE
  (testing.md §3.3, every write held), on 1.0.22, before the branch moved onto 1.0.23,
  which does not touch this code: under Unplaced "Ágoston, Lili" is 1st of 15; under
  Placed "Ágoston, Misi" is 1st and "Végh, Balázs" 58th of 58, and all 17 pairs with the
  same last name are in first-name order ("Tarjányi, Krisztina" before "Tarjányi,
  Tamás"); the member cards and the Change Supervisor list sort the same way ("Adriány",
  "Ágoston Géza", "Ágoston Liliána", "Albu").
- [x] **C14** HRTeams branch **`guy/fix-pending-edits`**, made on 2026-11-03 for GitHub
  #320 (W50). Committed on top of `master` `5073c51` (1.0.23) as `a2e8f9e` "Block edits to
  records with pending saves", pushed, and opened as PR #54 to `master` the same day
  (labels bug and patch, "Related to" #320). Merged at the owner's request on 2026-11-04
  (`30b830f`), once C13's release and web runs had ended; the release workflow made it
  1.0.25 (`083f169`, tag `v1.0.25`). The production build of 1.0.25 (with C13) went to web
  `master` as `4c30b649` "Update HRTeams plugin" and, by a fast-forward, to `staging` the
  same day ([hrteams-widget.md §1](plugins/hrteams-widget.md#1-how-it-is-built-and-served)).
  Production (web `main`) does not have it yet. W52 is still open. The branch was deleted
  on GitHub and locally on 2026-11-04, after the merge. Changes, all in
  `ABViewOrgChartTeamsComponent.js`:
  - `_savingEmployees` counts the saves running for each team member (employee id).
    `_startEmployeeSave()` and `_endEmployeeSave()` mark each save of the edit form and
    each drop. While one runs, every card of that person (now with `data-employee-id`)
    shows the spinner, has no pencil and cannot be dragged, also when the chart draws it
    again, and `_fnReadyRecord()` leaves such a card alone.
  - `_canEditEmployee()` refuses, with a message, the edit form and any drop of a person
    whose save runs ("This team member has changes that are still saving. Please wait until
    they're done."), and a drop of a person whose edit form is open ("Please save or close
    the edit form of this team member first."), since that form would later save old
    values.
  - One edit form at a time: opening the form of the record already open does nothing, and
    opening another closes the open one (`_closeContentForm()`, also used by Save and X).
  - `_settleAll()` replaces `Promise.all()` where one save makes several writes, so the
    save counts as running until every write has ended.
  - A card's `dragend` clears `_$eventTarget`, so a drop from the panel no longer puts the
    spinner on another person's card.

  Lint: 59 errors against 60 on `master` (one unused parameter less). Tested on
  2026-11-03 as admin in MBE, with the test page holding every model write in the browser
  and then failing it, so nothing reached NetSuite, no process ran and no `history` row was
  written (testing.md §3.3); the four W24 definition saves were blocked, and both
  definitions stayed unchanged. With a save of Kovács, Kálmán held: both of his cards
  (teams "2126-National Leadership Team" and "Specialized Ministry Strategies") showed the
  spinner and others stayed editable; a double click, a move of his card and a drop of him
  from the panel were all refused with the message, and still were after a full
  `refresh()`; once the write failed, his cards were editable again. One window per form,
  a refused drop while his form was open, the "Creating New Assignment" confirm (cancel
  writes nothing and frees the person; continue holds the end and the create), a second
  drop of a person being created (refused), and a first write failing early (the person
  stayed blocked until the second write ended, 1.3 s later) all behaved as above. Those
  tests ran on 1.0.22. Run again the same day on the committed branch (1.0.23, where C12
  changed the same save code): a held save of Kovács (both of his cards with the spinner
  and not draggable), a refused double click on each of his cards and a refused move,
  another person's form opening and closing, and his release after the failed write.
  Again nothing was written: apart from the inbox register, only GET calls reached
  api_sails, both definitions stayed unchanged, and there were still 210 process runs and
  125 `history` rows. The
  console error seen when a form closes is W51, which happens on `master` too.
  The ends of successful saves were run the same day on the PR #54 build, with the test
  page answering each held write as a success (nothing was sent): a form save, a move
  (the "Change Supervisor" dialog, during which Kovács was already blocked, then the end
  and the create of the assignment) and a drop from the panel (a new assignment). Each
  time he stayed blocked until the last write ended and could be edited right after it,
  and the new card was drawn and its form opened. Not covered: the supervisor write of a
  move (W52).

  Both branches start at `master` `5073c51` (1.0.23, with C12). `git merge-tree` on
  2026-11-03: PR #53 and PR #54 merge with each other in either order without a conflict,
  to the same tree. On 2026-11-04 `master` with both (1.0.25) had no new lint errors: 59,
  2 and 8 in `ABViewOrgChartTeamsComponent.js`, `components/utils.js` and
  `components/data_panel/staffDataPanel.js`, against 60, 2 and 8 on 1.0.23. The 1.0.25
  build went to staging before anyone opened it in a browser. On 2026-11-05 the dev build
  of `083f169` (the file the local stack served, with the same MD5 as a fresh build) was
  tested as admin in MBE with the test page (testing.md §3.3), both changes together:
  - Names: under Unplaced "Ágoston, Lili" was 1st of 15; under Placed "Ágoston, Misi"
    was 1st and "Végh, Balázs" last of 58, and the 34 names that share a last name were
    in first-name order. The Change Supervisor list (99 names) started with "Adriány
    Dalma", "Ágoston Géza", "Ágoston Liliána", "Albu Levente", and the team names under
    each parent team were in order too. No pair was out of order anywhere.
  - Saves: with a save of Kovács held, both of his cards showed the spinner and could not
    be dragged, and a double click, a move and a drop of him from the panel were refused
    with the message. Another person's cards opened one form at a time, and a move while
    his form was open got "Please save or close the edit form of this team member first."
    He could be edited again after a failed write, and after a form save and a move (two
    writes) answered as successes. W52 was still there, and a failed write showed no
    message (W53).
  - Nothing was written: apart from the two register calls, only GET calls reached
    api_sails, both definitions stayed unchanged, and there were still 210 process runs
    and 125 `history` rows.

---

## 2. Decisions needed from the owner

- [ ] **D1** Master-built `ab-web` images answer 502 for every API call locally (hardcoded
  AWS resolver). Offered fix on our side: mount an empty file over
  `/etc/nginx/templates/app.conf.template` (tested 2026-09-29). Waiting for a yes.
  [AGENTS.md §7](../AGENTS.md#7-traps)
- [ ] **D2** `dev.sh` starts Claude Code with `--dangerously-skip-permissions`. Keep or
  remove? [orchestration.md §3](orchestration.md#3-npm-scripts-and-shell-scripts)
- [ ] **D3** How much do we trust builders? Several items (S7, S9, S21, S24, S32) are only
  problems if a Builder is not fully trusted. Either role can already run server code
  through plugins. [abdesigner.md §2.4](plugins/abdesigner.md#24-who-can-do-what)
- [ ] **D4** `AB_TESTING` is on in the default dev stack, which exposes the test routes
  (S10). Keep it there, or move it to the test stack only?
  [AGENTS.md §7](../AGENTS.md#7-traps)

- [ ] **D5** Should HR Generalists see Responsibility Centres? The Netsuite Entity scope
  does not list that object, so an HR user's RC section is empty (0 rows; admin sees 14).
  [netsuite-hr-update.md §7](netsuite-hr-update.md#7-a-test-run-as-a-mock-hr-generalist-2026-10-02)
- [ ] **D6** How much should HR Generalists read? The Netsuite Entity scope restricts only
  entity, employee, NS Entity, Team and Team Responsibility; every HR user can read all Team
  Assignments and all NetSuite employee records (S35). The HR Teams cross-entity check needs
  to see the other entity's employee and assignment, so a plain fix would break it.
  **Owner, 2026-10-03: keep it this way for now and keep it listed.** The owner's reason:
  the NetSuite HR Update processes (built in ABDesigner's Process Manager) would otherwise
  be held back by the permissions of the HR user who triggered them. Evidence to weigh
  before any change: the process query path does not
  apply scopes at all (only appbuilder's model-get handler calls `includeScopes()`, and the
  NetSuite credentials come from the object, not the user), and run `cb71ef03`, started by
  `hr.mock.pxr`, read NS Entity 2715 ("PXY"), which that user's own reads cannot see. So
  the broad read is needed by the widget's check in the browser
  (`libs/CustomProcessTasks.js`), not by process_manager.
  [netsuite-hr-update.md §11](netsuite-hr-update.md#11-who-can-see-what-hr-generalists)
- [ ] **D7** People are matched across entities by **email**, in the widget and in the
  process. Some emails belong to 14 to 28 employee records in different subsidiaries (seen
  2026-10-03); whether those are one person or a shared placeholder was not checked. If
  placeholders, different people get linked. A stable person id would avoid it.
  [netsuite-hr-update.md §8](netsuite-hr-update.md#8-a-cross-entity-principal-move-end-to-end-2026-10-03)
- [ ] **D8** How do the C10 definitions reach production, and when? They must keep their
  ids, go out with the C9 plugin release, and the scope change has to be made by hand in
  Site Administration. Pending "Ask Other Entity HR to Approve" forms should be finished
  first. [netsuite-hr-update.md §12.8](netsuite-hr-update.md#128-before-this-reaches-production)
- [ ] **D9** A principal-change request that never finishes stays `pending`, and the widget
  then refuses every new request for that person ("Already waiting for approval"). It
  happens when nobody receives the approval (the other entity has no row in the local
  `entity` table, or no HR user linked to it; PE23), when nobody answers, or when the run
  fails half way. Only an admin deleting the row frees the person. Addressed in the
  working tree on 2026-10-04 (C9, C10): a request expires after 7 days
  ([netsuite-hr-update.md §12.9](netsuite-hr-update.md#129-expiry-after-7-days-since-2026-10-04)).
  The box stays open until that is committed.
  [netsuite-hr-update.md §12.8](netsuite-hr-update.md#128-before-this-reaches-production)

---

## 3. P1: security and data exposure

- [ ] **S1** api_sails (V): `copyTo` broadcasts reach every connected browser of every
  tenant. Fix: use the adapter room lookup the main room already uses.
  [api.md §9](core/api.md#9-security-findings)
- [ ] **S2** api_sails (V): CAS and Okta users are created with the passwords `CAS` /
  `Okta`, and local login is always on, so anyone who knows their email can log in.
  [api.md §9](core/api.md#9-security-findings)
- [ ] **S3** api_sails (V): the caller of `POST /auth/login/reset` chooses the URL the reset
  email links to. [api.md §9](core/api.md#9-security-findings)
- [ ] **S4** api_sails (V, impact I): logout does not clear `switcherooID`, so the session
  can keep acting as the impersonated user. [api.md §9](core/api.md#9-security-findings)
- [ ] **S5** api_sails + platform_service (I): the client `where` reaches a SQL compiler
  that builds strings; `quoteMe` does not escape `\`, and several rules and the sort
  direction go in unescaped. [api.md §9](core/api.md#9-security-findings),
  [server-platform.md §9](core/server-platform.md#9-traps) trap 11
- [ ] **S6** api_sails (V): reflected XSS in `/mobile/preloader/:tenantID/:appID`
  (`appID` printed with `<%-`). [api.md §9](core/api.md#9-security-findings)
- [ ] **S7** definition_manager + api_sails (I): builders can push an app into every tenant
  (`/definition/tenants-update-application`); `applicationUUID` is used in a file path and
  in SQL. [api.md §9](core/api.md#9-security-findings),
  [services.md §2](core/services.md#2-definition_manager)
- [ ] **S8** api_sails (I): `POST /tenant/add` needs only a login.
  [api.md §9](core/api.md#9-security-findings)
- [ ] **S9** platform_service (V): plugin URLs (`SITE_PLUGIN_LINK`) are run as server code
  in every AppBuilder service; builders can add them.
  [server-platform.md §9](core/server-platform.md#9-traps) trap 2,
  [services.md §2](core/services.md#2-definition_manager)
- [ ] **S10** api_sails (V): unauthenticated routes: `POST /test/reset` (tenant taken from a
  param), `/testlog`, `/metrics`, `/config` (tenant list), `/healthcheck` and
  `/versioncheck` (caller-controlled timeout), `/okta-error` (sends the session to
  telemetry). The `AB_TESTING` gate only checks that the variable is defined.
  [api.md §9](core/api.md#9-security-findings), [AGENTS.md §7](../AGENTS.md#7-traps)
- [ ] **S11** api_sails (I): `POST /test/import` reads any JSON under `process.cwd()`;
  `..` escapes it. [api.md §9](core/api.md#9-security-findings)
- [ ] **S12** api_sails (I): `tenant-token` is trusted as sent; on a non-production stack,
  a localhost request without a tenant (or `X-Forwarded-Host: localhost` on port 1337)
  becomes the admin tenant. [api.md §9](core/api.md#9-security-findings),
  [AGENTS.md §7](../AGENTS.md#7-traps)
- [ ] **S13** api_sails (V/I): sessions: hardcoded fallback secret, no new session id on
  login (fixation, I), insecure cookies outside production, no CSRF, no socket origin
  check. [api.md §9](core/api.md#9-security-findings)
- [ ] **S14** user_manager (V, impact I): accounts lock forever after 6 failed logins, and
  nothing resets the counter, so anyone can lock any account they know the email of.
  [services.md §8](core/services.md#8-user_manager)
- [ ] **S15** user_manager + api_sails (V): deactivated users (`isActive` false) can still
  log in locally. [services.md §8](core/services.md#8-user_manager)
- [ ] **S16** user_manager (V): the reset-URL handler reveals whether an email exists, and
  the password compare is not constant time. [services.md §8](core/services.md#8-user_manager)
- [ ] **S17** api_sails (V): fail2ban can be dodged: the logged IP is the first
  `X-Forwarded-For` entry, which the client controls, and CAS/Okta errors do not end in
  `FAILED`. [api.md §9](core/api.md#9-security-findings)
- [ ] **S18** several (V): secrets reach logs and telemetry: NetSuite credentials in GET
  query strings, reset tokens in logs, passwords in Sentry job data, and the SMTP password
  on email failures. [api.md §9](core/api.md#9-security-findings),
  [services.md §6](core/services.md#6-notification_email)
- [ ] **S19** ab-utils + platform_web (V): local stacks send errors to an upstream Sentry
  project unless `TELEMETRY_PROVIDER` or `SENTRY_DSN` is set; the web prod build hardcodes a
  DSN. [service-runtime.md §5](core/service-runtime.md#5-validation-pubsub-notifications-telemetry),
  [frontend.md §8](core/frontend.md#8-build)
- [ ] **S20** platform_service (V, impact I): the `in_query` rewrite (the "Query" policy)
  uses only `ids[0]` for many:one links, and an empty query result becomes `1=1`, which
  matches every row. A filter or scope built on `in_query` can then show everything.
  [server-platform.md §9](core/server-platform.md#9-traps) trap 15
- [ ] **S21** appbuilder + platform_service (I): server-side requests to caller-chosen
  URLs (SSRF): `model-get` fetches a client `cond.url` for unknown objects; NetSuite
  objects accept any `ENV:<name>` and any base URL; `env-verify` tells which env vars
  exist. [services.md §1](core/services.md#1-appbuilder),
  [abdesigner.md §12](plugins/abdesigner.md#12-traps) trap 7
- [ ] **S22** appbuilder (V): scopes are checked on reads only; writes never check them.
  [services.md §1](core/services.md#1-appbuilder)
- [ ] **S23** process_manager (I): inbox answers, form submits, external callbacks and
  resets need only a login; nothing checks that the user is an assignee.
  [processes.md §7](core/processes.md#7-traps) trap 25
- [ ] **S24** process_manager + class_core (I): builder text is run as code on the server:
  InsertRecord formulas (`eval`), Email and External templates (EJS), calculate fields
  (`eval`). [processes.md §7](core/processes.md#7-traps) trap 23,
  [domain-model.md §11](core/domain-model.md#11-known-traps-and-bugs) trap 9
- [ ] **S25** file_processor (I): base64 upload and import write to caller-chosen names
  (overwrite, `../`); image commands are built as shell strings; the scan runs after the
  file is in place. [services.md §4](core/services.md#4-file_processor)
- [ ] **S26** several (I): SQL built by string interpolation: `csv-export` labels,
  accounting SQL, `applicationUUID`. [services.md §1](core/services.md#1-appbuilder),
  [processes.md §7](core/processes.md#7-traps) trap 24
- [ ] **S27** api_sails (I): uploaded files are public through nginx `/data/`;
  `/assets/ab_plugins` publishes plugin folders. [api.md §9](core/api.md#9-security-findings)
- [ ] **S28** tenant_manager (V): `tenant-add` writes `new-<key>.sql`, which holds the admin
  hash and salt, and never deletes it.
  [services.md §7](core/services.md#7-tenant_manager-esm-typemodule-since-2026-09-29)
- [ ] **S29** api_sails (I): `/mobile/definitions` returns the full app export plus system
  objects to any logged-in user of the tenant. [mobile.md §8](core/mobile.md#8-traps)
- [ ] **S30** platform_pwa (I): the mobile timeline template is `eval`ed with record values
  (XSS). [mobile.md §7](core/mobile.md#7-mobile-view-types-class_core-mobile)
- [ ] **S31** compose (V): all 11 Node inspectors are published on the host with
  `--inspect=0.0.0.0`. [AGENTS.md §7](../AGENTS.md#7-traps)
- [ ] **S32** ABDesigner (V, effect I): Builder versus System Builder is enforced only in
  the browser. [abdesigner.md §2.4](plugins/abdesigner.md#24-who-can-do-what)

- [ ] **S33** platform_service (V, T): scopes fail open on a wrong rule. `includeScopes()`
  keeps only top-level rules whose `key` is a field id of the object being read
  (`platform/ABObject.js:352-376`); any other rule (a typo, a deleted field, a nested
  group) is dropped silently, and if none is left the user sees **every** row. Seen
  2026-10-02 with a test scope keyed `"Sandbox Item.Status"`.
  [site-administration.md §3.1](core/site-administration.md#31-what-a-scope-does-tested-on-2026-10-02)
- [ ] **S34** platform_service (V, T): process query tasks store whole `SITE_USER` rows in
  `SITE_PROCESS_INSTANCE.context`, including `password` (hash) and `salt` for users with a
  local password (seen for admin in a 2026-09-14 NetSuite HR Update run). Who can read the
  context through the API was not checked. [processes.md §7](core/processes.md#7-traps) trap 34
- [ ] **S35** NetSuite HR Update (V, T): the HR scope does not restrict Team Assignment, NS
  Employee Record, Role Type, Team Strategy, the strategy lists or Responsibility List (no
  rule matches them, see S33), so any HR Generalist can read every NetSuite employee record
  of every entity; that object includes birth date and mobile phone. Checked 2026-10-03 as
  a one-entity HR user. Read D6 before changing it.
  [netsuite-hr-update.md §11](netsuite-hr-update.md#11-who-can-see-what-hr-generalists)
- [ ] **S36** platform_service (T, minor): process_manager logs every NetSuite SuiteQL
  statement with its values (`"Netsuite SQL:" … email = '…'`), so employee emails end up
  in the service log.
- [ ] **S37** appbuilder + platform_service (V, T): `populate` reads related rows without
  scopes. As hr.mock.pxr, a Team Assignment read with `populate: [team, entity]` returned
  the other entity's Team and NS Entity names, rows the HR scope hides from that user
  (2026-10-03). `includeScopes()` is applied to the main query only. The HR Teams widget
  now relies on this for the other side's names (C9), so a fix must give it another way.
  [netsuite-hr-update.md §12.2](netsuite-hr-update.md#122-the-flow)

- [ ] **S38** api_sails (V): the `relay` passport strategy is live in upstream api_sails
  (`master` and `staging`, both `7c6e655` since 2026-10-30). It accepts
  `authorization: relay@@@<token>@@@<SiteUser.uuid>` as any user; compose cannot switch it
  off (it passes `RELAY_ENABLED`, the config reads `RELAY_ENABLE`, default `true`), and the
  token defaults to `"There is no spoon."`. api_sails publishes port 1337 on every host
  interface. The local removal (C2) was dropped. Fix upstream: remove the strategy, or at
  least default it to off with no default token.
  [AGENTS.md §7](../AGENTS.md#7-traps)
- [ ] **S39** ab-utils (V, T): `env()` (`utils/defaults.js`) logs a variable's value when
  it fails to parse it as JSON, so notification_email's boot log prints env values in plain
  text, `SMTP_PASSWORD` included (four such blocks on 2026-10-30). Inferred: the same goes
  for any service and any deployment with such a value. The local fix (C1) was dropped; a
  fix needs an ab-utils release. [AGENTS.md §7.1](../AGENTS.md#71-startup-log-triage)
---

## 4. P1: broken features

- [ ] **B1** notification_email (V): **email sending is broken**: `src/send.js:7` treats
  the `AB.config()` Promise as the config. Password-reset emails and BPMN Email tasks fail.
  [services.md §6](core/services.md#6-notification_email)
- [ ] **B2** migration_manager (V): patch `20261111.sql` has a year typo, so every new patch
  dated before 2026-11-11 is skipped silently. Until fixed, name new patches to sort after
  it. [database.md §5](core/database.md#5-migrations)
- [ ] **B3** platform_service (V): one failed factory build breaks that tenant in that
  service until a restart (`PendingFactory` kept on failure).
  [server-platform.md §9](core/server-platform.md#9-traps) trap 1
- [ ] **B4** process_manager (V, T, high impact): timer-started instances all get the key
  `"UUID()"`, and the UNIQUE index is on `instanceKey` alone, so after the first one no
  timer run of any process in the tenant can start (seen 2026-10-02; the test row was
  deleted afterwards). Check:
  `SELECT COUNT(*) FROM SITE_PROCESS_INSTANCE WHERE instanceKey='UUID()'`.
  [processes.md §7](core/processes.md#7-traps) trap 5
- [ ] **B5** tenant_manager (V, effect I): the portal's own labels are always English,
  because `config-site` reads `req.user`, which service requests do not have; api_sails then
  caches the result per tenant. [frontend.md §10](core/frontend.md#10-traps) trap 11
- [ ] **B6** platform_web (V): a 2xx socket reply carrying `{status:"error"}` hangs forever
  (`JSON.Stringify` typo). [frontend.md §10](core/frontend.md#10-traps) trap 1
- [ ] **B7** platform_service (I, high confidence): dropping a File field fails, so object
  drops never reach `dropTableIfExists`.
  [server-platform.md §9](core/server-platform.md#9-traps) trap 6
- [ ] **B8** platform_service (I): `migrate-field-update` likely throws for connect, user,
  file, image and tree fields (`req.logError` called with one argument).
  [server-platform.md §9](core/server-platform.md#9-traps) trap 7
- [ ] **B9** class_core (I): calculate field functions likely fail: the designer writes
  `AGE(...)`, the core defines `_AGE`.
  [domain-model.md §11](core/domain-model.md#11-known-traps-and-bugs) trap 9
- [ ] **B10** process_manager (I): Monitor "Reset" skips the failed task (element `id` sent,
  `diagramID` expected). [processes.md §7](core/processes.md#7-traps) trap 3
- [ ] **B11** process_manager (I): an Api task stalls the run; a SubProcess runs only one
  wave. [processes.md §7](core/processes.md#7-traps) traps 1-2
- [ ] **B12** process_manager (V, T): timers fire up to 60 times in their minute (seconds
  field is `*`; 59 seen 2026-10-02). [processes.md §7](core/processes.md#7-traps) trap 4
- [ ] **B13** process_manager (T): the seeded "TestSendMail" process errors on every new
  user, in every tenant (seen 2026-10-02 when test users were created). [processes.md §7](core/processes.md#7-traps) trap 30
- [ ] **B14** ABDesigner (V, effect I): the "Import CSV" new-object tab creates the table
  but drops the object from the app, with no columns or rows.
  [abdesigner.md §12](plugins/abdesigner.md#12-traps) trap 1
- [ ] **B15** platform_web + ABDesigner (V): the CSV "Space" separator splits on the letter
  `s`. [widgets.md §8](core/widgets.md#8-traps) trap 16
- [ ] **B16** platform_web (V): form submit rule "Send a custom email" posts to a route that
  does not exist; "Open another website" turns `https://x` into `http://https://x`.
  [widgets.md §8](core/widgets.md#8-traps) traps 12-13
- [ ] **B17** platform_web (V, not tested): grid Excel, PDF and PNG export likely fail; the
  Webix export libraries are not served. [widgets.md §8](core/widgets.md#8-traps) trap 4
- [ ] **B18** ABDesigner (V): the process "Test" tab throws when opened.
  [abdesigner.md §12](plugins/abdesigner.md#12-traps) trap 9
- [ ] **B19** api_sails + platform_pwa (I): `/mobile/version/:ID` calls a deleted handler,
  so the PWA's update dialog never appears. [mobile.md §8](core/mobile.md#8-traps)
- [ ] **B20** platform_service (I): `ABSecretManager._decrypt` slices the buffer wrongly, so
  reading a secret should always throw. [server-platform.md §9](core/server-platform.md#9-traps)
  trap 18
- [ ] **B21** appbuilder (V): the circuit-breaker env vars are ignored, for the same
  `AB.config()` Promise reason as B1 (`app.js:26`). [services.md §1](core/services.md#1-appbuilder)

- [ ] **B22** platform_service (V, T): after a field is added to an object that a service
  has already used, that service keeps the old Objection model until it restarts. Creates
  then report `unknown relation "<field>__relation"` although the row **was** inserted
  (M:N links are not). Workaround: restart the service. It crosses apps: a `user` field
  added in a test app gave `SITE_USER` a new relation and broke NetSuite HR Update's
  "Updated Assignments" in process_manager until it was restarted.
  [server-platform.md §9](core/server-platform.md#9-traps) trap 21
- [ ] **B23** platform_service (V, T): an object stored with an empty `tableName` resolves to
  `AB_<Object>` (no app prefix) after a factory rebuild, because objects are built before
  applications; field migrations then fail with `ER_NO_SUCH_TABLE`.
  [server-platform.md §9](core/server-platform.md#9-traps) trap 22
- [ ] **B24** api_sails (V, T): **the CSV Exporter widget crashes api_sails and takes the
  whole site down.** `api/controllers/appbuilder/csv-export.js:70` calls
  `sails.getDatastore()`, but `config/hooks.js` turns the ORM hook off (`orm: false`, commit
  `5ce8600`, 2025-09-05), so the call throws inside a callback and the process exits.
  api_sails has no `--watch` and compose has no restart policy, so every page answers
  502/504 until someone runs `npm start` again. Seen 2026-10-02 from the Claude Sandbox
  app. [widgets.md §8](core/widgets.md#8-traps)
- [ ] **B25** class_core + NetSuite HR Update (V, T): **a cross-entity principal change
  never reaches the other entity's HR when the person has records in exactly one other
  entity** (until 2026-10-03; the new process looks HR users up with a single-value
  `equals`, C10, so the principal change no longer hits it; the engine cause remains).
  "Get HR Users in other Entities" filters with `context_in` on a list that then
  has one entry; `ABProcessCore.processData()` returns it as a bare value and the `in` rule
  compiles to `1=0`. The approval form is created with no recipients, the run waits
  forever, and the person is never made principal. Seen twice on 2026-10-03, in both
  directions. The root cause is general ([processes.md §7](core/processes.md#7-traps) trap 31).
  [netsuite-hr-update.md §8](netsuite-hr-update.md#8-a-cross-entity-principal-move-end-to-end-2026-10-03)
---

## 5. P2: server correctness and reliability

- [ ] **R1** definition_manager (V): `json-import` sets a server-wide MariaDB lock timeout
  to 1 s and never restores it on error. [services.md §2](core/services.md#2-definition_manager)
- [ ] **R2** migration_manager (V): patch list read unsorted; no transactions; the `;` split
  breaks strings; some patches are not safe to re-run (`20231031` wipes `SITE_SECRET`);
  system-definition upserts overwrite tenant changes. [database.md §5](core/database.md#5-migrations)
- [ ] **R3** tenant_manager (V): a new tenant has no `SITE_CONFIG` (and other tables) until
  migration_manager runs; nothing triggers it; no rollback for a half-built tenant; the
  comment regex cuts values containing ` #`.
  [services.md §7](core/services.md#7-tenant_manager-esm-typemodule-since-2026-09-29),
  [database.md §6](core/database.md#6-creating-a-tenant)
- [ ] **R4** platform_service: combine fields never update their triggers (V); DateTime
  values cannot be cleared (V); connect one:many resolves before its DDL ends (I); some
  ABIndex/Connect promises can hang (I); self M:N and second AutoIndex fail (I).
  [server-platform.md §9](core/server-platform.md#9-traps) traps 5, 8-10
- [ ] **R5** platform_service: `includeScopes` has no `.catch` (a DB error hangs the
  request); `ABModelQuery` deletes from the wrong array; formula SQL unquoted (I); unknown
  rules emitted raw inside groups; `DATE("<id>")` never matches (I).
  [server-platform.md §9](core/server-platform.md#9-traps) traps 12-16
- [ ] **R6** platform_service: NetSuite `findCount` waits forever if `findAll` fails; MySQL
  syntax sent into SuiteQL. [server-platform.md §9](core/server-platform.md#9-traps) trap 17
- [ ] **R7** platform_service (I): a `definition.*` event during a pending build is lost;
  notifications go out through the last-built factory's request (wrong tenant).
  [server-platform.md §9](core/server-platform.md#9-traps) traps 3-4
- [ ] **R8** appbuilder + log_manager: rows with integer or NetSuite ids are never logged
  (T: every NetSuite write logs `"row" must be a valid GUID` and a developer notification); delete broadcasts carry no data (I); deleting a record never deletes its files;
  rowlogs are never pruned. [services.md §1](core/services.md#1-appbuilder),
  [services.md §5](core/services.md#5-log_manager-commonjs)
- [ ] **R9** file_processor (V): there is no delete path for files.
  [services.md §4](core/services.md#4-file_processor)
- [ ] **R10** several (I): handlers that call `cb` twice or never (definition_manager,
  custom_reports unknown `reportKey`, `userform.create`); a handler that throws on import
  silently disappears; async throws never answer, so callers retry for minutes.
  [services.md §2](core/services.md#2-definition_manager),
  [service-runtime.md §10](core/service-runtime.md#10-traps)
- [ ] **R11** ab-utils + api_sails (V): shared-closure helpers misattribute notifications
  under load; `BroadcastManager` keys by username across tenants; possible double responses
  in a few api_sails controllers. [api.md §9](core/api.md#9-security-findings) items 17-19
- [ ] **R12** api_sails (V): caches never expire (`hashLookup`, tenant options), and
  user-specific JS gets a 1-year `Cache-Control`; temp files are never cleaned.
  [api.md §9](core/api.md#9-security-findings) items 20-21
- [ ] **R13** user_manager (unverified): token expiry compares a DATETIME with
  `Date.now()` milliseconds. [services.md §8](core/services.md#8-user_manager)
- [ ] **R14** compose (V): `CUSTOM_REPORTS_ENABLED` is passed, `CUSTOM_REPORTS_ENABLE` is
  read, so the switch does nothing; several other env vars have readers but are never
  passed. [AGENTS.md §7](../AGENTS.md#7-traps),
  [orchestration.md §2](orchestration.md#2-environment-variables-exampleenv)
- [ ] **R15** platform_service (V): one knex pool per tenant per process in six services,
  on top of ab-utils' pools. [server-platform.md §9](core/server-platform.md#9-traps) trap 20
- [ ] **R16** class_core (V/I): missing page references are deleted on save; query problem
  lists are reset (I); an unknown field key breaks the object (I); instances mutate the
  definition cache (I); `AB.steps()` is always empty.
  [domain-model.md §11](core/domain-model.md#11-known-traps-and-bugs) traps 1-4, 15
- [ ] **R17** class_core (V): field validation bugs: date `case (1, 2):`, `notBetween`
  never passes, "required" lets `""` through, number format spacing and rounding.
  [domain-model.md §11](core/domain-model.md#11-known-traps-and-bugs) traps 5-8, 10-11
- [ ] **R18** class_core (I; the throttle part seen at runtime, see W16): data collection
  races (throttle drops a page, concurrent
  first loads hang, query DCs keep deleted rows, listeners never removed);
  `staleRefreshProcess` has no `.catch`.
  [domain-model.md §11](core/domain-model.md#11-known-traps-and-bugs) traps 12-14
- [ ] **R19** class_core (I): a missing translation shows `"[th]Label"`, and saving from
  that language stores the prefixed text.
  [domain-model.md §11](core/domain-model.md#11-known-traps-and-bugs) trap 17
- [ ] **R20** class_core (V, T): a view's missing child ids are stored again on every save,
  so `viewIDs` grows without limit. Seen 2026-10-02: the admin tenant's
  "Edit Responsibility.form" (`a990f863-…`) holds 2,680 `viewIDs`, only 15 distinct, and
  the NetSuite HR Update app shows 2,672 copies of 7 warnings.
  [domain-model.md §11](core/domain-model.md#11-known-traps-and-bugs) trap 19

- [ ] **R21** definition_manager (T, cause unknown): one `migrate-field-create` took 41 s
  (the `ALTER TABLE` itself had run), so api_sails timed out after 25 s; the next one took
  100 ms. [abdesigner.md §13](plugins/abdesigner.md#13-walkthrough-building-an-app-from-scratch-observed)
- [ ] **R22** platform_service (T): a transient NetSuite error (here SuiteQL **503 Service
  Unavailable** from Akamai) is not retried and reaches the user as `Rejected by NetSuite.`
  with an empty detail. [netsuite-hr-update.md §7](netsuite-hr-update.md#7-a-test-run-as-a-mock-hr-generalist-2026-10-02)
- [ ] **R23** platform_service (T): NetSuite `findAll` passes a `limit` above 1000 straight
  to SuiteQL, which rejects it; callers must page themselves.
  [server-platform.md §9](core/server-platform.md#9-traps) trap 23
- [ ] **R24** platform_service (T): for NetSuite Team rows the boolean field `isInactive`
  reads `false` through the model and the app's DCs even when NetSuite has
  `isinactive = "T"` (team 20704, 2026-10-03). The HR Teams widget's own team DC hid the
  inactive team correctly, so the cause is in how values are mapped (not yet traced).
- [ ] **R25** platform_service (V, T): NetSuite `create()` and `update()` read the saved row
  back with `populate: true` (`ABModelApiNetsuite.js`, end of both), so every write costs one
  more query per relation of the object. In the first approved principal change (55 s,
  2026-10-03), ending one Team Assignment took 15 s, 14 s of it in that read. In the runs
  logged since, that read took 1 to 3 s per end date and a whole change 11 to 20 s.
  [netsuite-hr-update.md §10.1](netsuite-hr-update.md#101-after-the-redesign-2026-10-03)
  and [§12.10](netsuite-hr-update.md#1210-how-long-an-approved-change-takes)
- [ ] **R26** appbuilder + log_manager (V, T): every write to a NetSuite object logs an
  `EINVALIDINPUTS` developer error from `log_manager.rowlog-create`, whose `row` input must
  be a uuid while NetSuite ids are numbers. No row log is kept for NetSuite objects.
- [ ] **R27** api_sails (T, cause I): **a user switch (switcheroo) can be undone by requests
  still running in another tab of the same session.** Seen 2026-10-04: a chart was loading
  as hr.mock.pxy in one tab when `POST /auth/switcheroo/<hr.mock.pxr>` answered 200 in
  another, yet api_sails logged hr.mock.pxy on every request after it, and the first tab's
  chart then reloaded its data as hr.mock.pxy. Inferred cause: each request saves the
  session it loaded, so a request that started before the switch writes the old
  `switcheroo` back after it. [testing.md §3.1](testing.md#31-acting-as-another-user-switcheroo)
- [ ] **R28** api_sails (T, cause not found): **api_sails stopped for 78 s** on 2026-10-16,
  from 07:46:12 to 07:47:30 UTC. It had just logged `Loading HR Teams Plugin` while serving
  `GET /config/preloader`, then logged nothing and answered nothing: `/config/site` timed out
  after 20 s and `/config/user` took 15 s. At 07:46:18 the other services logged
  `service.offline` for api_sails' cote nodes; they kept running. At 07:47:30 api_sails
  logged every peer offline and online again, then served the queued requests. Host IO
  pressure was about 21 % over the minutes around it (`/proc/pressure/io`); api_sails had
  only 5 MB in swap. It happened once since the container started (2026-10-15 05:57 UTC),
  and 30 requests right after it answered in 3 to 13 ms each. A page opened during such a
  stall waits that long for every API call.

---

## 6. P2: process engine

All in [processes.md §7](core/processes.md#7-traps).

- [ ] **PE1** (V, T) Timer time of day drifts by the browser's UTC offset on each save
  (+7 h seen from Thailand); a
  monthly timer set to "last" stops that tenant's other timers. Traps 6-7.
- [ ] **PE2**  (V/I) Exclusive gateway has no default branch; a task with no outgoing flow
  does not mark the instance as error; "Terminate" End does not terminate; several pools
  likely break the engine. Traps 8-12.
- [ ] **PE3**  (V) In-flight instances mix the snapshot with the live definition. Trap 13.
- [ ] **PE4**  (I) Shared element objects across concurrent instances; `InsertRecord.results`
  grows forever. Trap 15.
- [ ] **PE5**  (V) Participant `users()` ignores field-based users; Email reports most errors
  as "server refusing to connect". Traps 16-17.
- [ ] **PE6**  (V/I) Promises that never settle (AccountingFPYearClose, External), an
  Approval without `formBuilder` throws, External URL templates call a missing method.
  Traps 18-21.
- [ ] **PE7**  (I) Form tasks depend on the request user: skipped for timer runs, sent to
  whoever's request is running, and a closed popup leaves the instance waiting. Trap 22.
- [ ] **PE8**  (V) Answered approvals stay in other inboxes until reload; thin error handling
  in `userform.*`. Traps 26-27.
- [ ] **PE9**  (I) Instance columns are TEXT (about 64 KB) while `_prevState` grows; an
  unknown element key breaks the tenant until restart. Traps 28-29.

- [x] **PE10** Not a bug (owner, 2026-10-02): NetSuite HR Update "New Assignments" has no
  flow out of Start on purpose, because new assignments no longer need follow-up actions.
  [netsuite-hr-update.md §3](netsuite-hr-update.md#3-new-assignments-is-switched-off-on-purpose)
- [ ] **PE11** (T, cause V) NetSuite HR Update "Updated Assignments": 15 runs wait forever
  at the Form "Ask this User to confirm with the reason" (a popup, no inbox row); 19 more
  wait on unanswered inbox notices. The 15 are left by the HR Teams widget on purpose: it
  hides that popup when it decided no approval is needed, so each such save adds one
  waiting run. [netsuite-hr-update.md §5](netsuite-hr-update.md#5-run-history-in-this-stack-2026-10-02)
  **Fixed in the working tree on 2026-10-03** (C9, C10): the Form and the hiding code are
  gone, so no new run waits on it. Runs already waiting stay so.
- [ ] **PE12** (T) A run that logs a configuration error is saved as `completed`, not
  `error`, so the Monitor's error filter misses it (inferred). Seen on the intentionally
  switched-off New Assignments process (PE10), so a real misconfiguration would look the same. [processes.md §7](core/processes.md#7-traps)
- [ ] **PE13** (V, T) NetSuite HR Update: the Email tasks "Notify Success" and "Notify
  Fails" crash with `Cannot read properties of undefined (reading 'users')` (From is the
  current lane; the process has no lanes), so the run ends as `error` after the data was
  already changed. Code side: `resolveAddresses()` does not check for a missing lane.
  **Owner, 2026-10-03: ignore for now.** Email tasks are not in use yet, and the tasks
  before them work. [processes.md §7](core/processes.md#7-traps) trap 33
  Both tasks went with the cross-entity part on 2026-10-03 (C10); `resolveAddresses()` is
  unchanged.
- [ ] **PE14** (V, T) NetSuite HR Update: "Get Other Entity IDs by Principal Assignment" has
  no employee filter, so it returns every entity with any current principal (155), and
  the HR-users query that uses it asks the HR of every other entity where the person has a
  record. **Owner, 2026-10-03: this is the next step to fix**, together with PE15.
  [netsuite-hr-update.md §9.4](netsuite-hr-update.md#94-the-cross-entity-part-only-in-the-41-element-version)
  **Gone in the working tree on 2026-10-03** (C10): the block was removed; the new process
  asks only the entity that holds the principal.
- [ ] **PE15** (V, T) `set_pluck` on a connect field re-reads the linked rows with every
  relation populated; through a NetSuite object that is one SuiteQL read per relation
  (PE14's pluck read 22 pages of results). [processes.md §7](core/processes.md#7-traps) trap 32
  The new principal process plucks no connect field (C10), but the lookups that remain in
  "Updated Assignments" (§9.2 of netsuite-hr-update.md) still do, on every assignment
  save.
- [ ] **PE16** (V, T) NetSuite HR Update: in "Ask Other Entity HR to Approve", the field
  "Entity of the current Principal Team Assignment" shows the requesting entity (it is bound
  to "Get Entity Name in this Assignment").
  [netsuite-hr-update.md §9.4](netsuite-hr-update.md#94-the-cross-entity-part-only-in-the-41-element-version)
  **Gone in the working tree on 2026-10-03** (C10): the new approval form takes both
  entity names from the request row.
- [ ] **PE17** (V) NetSuite HR Update: "Get Job Description in the other Entity" filters on
  `custrecord_team_assign_job_desc` = the assignment id instead of `id`, so it finds nothing
  and the new assignment in the other entity loses its job description.
  [netsuite-hr-update.md §9.5](netsuite-hr-update.md#95-after-approval-only-in-the-41-element-version)
  **Gone in the working tree on 2026-10-03** (C10): the new process copies the job
  description from the request row.
- [ ] **PE18** (T) NetSuite HR Update: runs for the same assignment that start in the same
  second each insert a "latest" `history` row; one keeps the column default
  `2026-01-26 21:00:23`, which a notice can then show as "Submitted Timestamp" (2 of 21
  records). Owner: leave `history` alone for now; listed only.
  [netsuite-hr-update.md §9.1](netsuite-hr-update.md#91-bookkeeping-in-history)
- [ ] **PE19** (V, P4) NetSuite HR Update: the application definition lists two process ids
  with no definition (`856d977a-…`, `014580b4-…`).
- [ ] **PE20** (V) No process element can delete a record: the query language has find,
  first, pluck, save and update, and there is no delete task. "cache-principal-change
  approval" therefore only sets a status, and the HR Teams widget deletes finished rows.
  [netsuite-hr-update.md §12.2](netsuite-hr-update.md#122-the-flow)
- [ ] **PE21** (V, T) An exclusive gateway cannot test a query task's output unless the
  saved parameter is named after the plucked field's id. `getFieldVal()`
  (`class_core/FilterComplexCore.js:7-45`, the lookup at `:35-36`) looks for a process key
  ending in `.<field id>`; query outputs are keyed `<task id>.<parameter>`
  (`class_core/ql/ABQLSetSaveCore.js:72`). Only trigger data and approval answers work as
  built in the designer. **Proven on 2026-10-04:** two processes that differ
  only in the saved names read the same item; with ordinary names both gateways chose No
  although the run held `Done = 1` and `Name = "Gear"`, with field-id names both chose Yes
  ([processes.md §7.1](core/processes.md#71-proof-for-trap-36-pe21-2026-10-04)).
  "Principal Change Approval" uses the field-id names on purpose. A Calculate task's value
  probably cannot be tested either (its fake field has no id; read from code, not tested).
  [processes.md §7](core/processes.md#7-traps) trap 36
- [ ] **PE22** (T) A run that takes longer than about 25 s after an inbox answer logs
  `Request timed out.` and `EOVERTIME:[process_manager.run] Handler response after timout`
  developer errors: the answer's call to `process_manager.run` gives up after its resends
  while the run carries on and completes (55 s on 2026-10-03; every run since took 11 to
  20 s and stayed under the limit).
  [netsuite-hr-update.md §10.1](netsuite-hr-update.md#101-after-the-redesign-2026-10-03)
- [ ] **PE23** (V, T) An Approval whose recipients resolve to nobody is created anyway and
  waits forever. `ABProcessTaskUserApproval._requestNewForm()` passes an empty list on, and
  process_manager `handlers/userform-create.js` creates the form for no user and no role; it
  warns only when names were given and none matched. 19 such forms were pending in this
  tenant on 2026-10-04. In NetSuite HR Update it leaves a principal-change request
  `pending` for good (D9). [processes.md §7](core/processes.md#7-traps) trap 40
- [ ] **PE24** (V, T) Process triggers from appbuilder go through a circuit breaker with a
  3 s timeout (`utils/processTrigger/manager.js`, opossum; the defaults, because
  `appbuilder/app.js` passes the `AB.config()` promise unawaited, AGENTS.md §7). A trigger
  whose run holds `process_manager.trigger` longer, as a run of the 41-element "Updated
  Assignments" does (28 to 54 s before it raises the reason Form), times out and is saved
  in `processTriggerQueue`, which retries every 30 s; once half the calls fail, the breaker
  opens for 30 s and sends every trigger straight to the queue. Seen on 2026-10-30: with two
  principal changes saved together (four saves), the other three triggers reached
  process_manager only from the queue, 64 to 84 s after their saves, so the second change's
  Form came 107 s after its save (W47). No run was started twice.

---

## 7. P2: browser portal and widgets

Trap numbers refer to [frontend.md §10](core/frontend.md#10-traps) and
[widgets.md §8](core/widgets.md#8-traps).

- [ ] **W1** (V) `E_REAUTH` leaves the caller's promise unsettled. Frontend trap 2.
- [ ] **W2** (V) `networkType: "relay"` crashes boot (web and PWA), and `Network.init` has
  unreachable reconnect code. Frontend trap 3, [mobile.md §8](core/mobile.md#8-traps).
- [ ] **W3** (I) Under the `rest` network type other widgets never see saves. Frontend
  trap 4.
- [ ] **W4** (V) Boot errors never reach Sentry; the disconnect banner is never installed.
  Frontend traps 6-7.
- [ ] **W5** (V) Plugin labels are never used, so ABDesigner and HRTeams cannot be
  translated. Frontend trap 10.
- [ ] **W6** (V, effect I) The client-side app filter passes every tenant role, so it
  filters nothing. Frontend trap 14.
- [ ] **W7** (V) `ABDataCollection.warningsEval` calls `datacollectionById` and throws on
  linked DCs; `!x ?? y` never skips removed child views. Frontend traps
  16-17.
- [ ] **W8** (V) Grid filters apply to every widget on the same DC; grid sort can reload
  the whole table. Widgets traps 1-2.
- [ ] **W9** (V/I) Form validation rules leak between forms; fast cursor changes can show
  stale data; server save errors can show nothing. Widgets traps 6-7
  and 9.
- [ ] **W10** (V) The custom foreign key filter picks the wrong column when `indexField2` is
  set. Widgets trap 10.
- [ ] **W11** (I) Connect options and the CSV importer load the whole linked table. Widgets
  traps 11 and 17.
- [ ] **W12** (V) DOCX builder crashes when a followed DC has no cursor; the scheduler
  extends the reports backend. Widgets traps 18-19.
- [ ] **W13** (I) Charts count only the loaded rows (a page, not the table). Widgets trap 15.
- [ ] **W14** (V) The `?v=ecs` cache buster never changes, so browsers can keep old
  ABDesigner and HRTeams bundles.
  [hrteams-widget.md §1.1](plugins/hrteams-widget.md#11-the-cache-busting-trap)
- [ ] **W15** (V) Mobile QR menu entries remain for a retired feature; upstream api_sails
  still routes their endpoints (`GET /relay/user-qr`, `GET /mobile/qr/:ID`; S38).
  Frontend trap 23. Site Administration also still has a "Settings / Relay / QR Codes" tab
  ([site-administration.md §2](core/site-administration.md#2-site-administration)).
- [ ] **W16** (V, T) Two `loadData` replies for one DC within 100 ms: the first reply's
  promise never settles, and anything awaiting it waits forever. Seen 2026-10-02: two
  "Employee" DCs of NetSuite HR Update kept pending jobs on 2 of 2 loads. Seen again on
  2026-10-05: 6 DCs of the HR Teams chart with a pending job, 3 of them with a pending
  `reloadPromise`; it hangs the chart's "Refreshing" (W27). Seen on 2026-10-16 on HR Teams
  `master` (without the W27 guard): every load as hr.mock.cni had 4 or 5 such jobs, which
  the server had answered in 1 to 9 s, and 4 loads of 6 hung on them. Seen on 2026-10-30 on
  `master` (1.0.22, with the guard): after each save of a Team Assignment, "Employee
  Assigned" and "Employee Unassigned" still held a `reloadPromise` and a `reloadTimer`
  145 s and more after their rows were back, twice in two tries. Frontend trap 28.
- [ ] **W17** HRTeams (V, T): the chart finishes "Refreshing" only while its tab is
  visible (it waits on `requestAnimationFrame`), and `refresh()` has no timeout or
  `catch`. Fine for normal users; a trap when testing in a background tab.
  [hrteams-widget.md §5](plugins/hrteams-widget.md#5-testing-notes)

- [ ] **W18** ABDesigner (T): when a migrate call times out, the "Create Field" popup
  stays busy forever; only a page reload frees it. [abdesigner.md §13](plugins/abdesigner.md#13-walkthrough-building-an-app-from-scratch-observed)
- [ ] **W19** platform_web or api_sails (T, cause I): every load of `SITE_SCOPE` rows logs
  `Error parsing JSON data for column: objectIds`. The column holds valid JSON arrays in
  the DB, but the browser receives them comma-joined, so the CSV pack/unpack loses the
  JSON (inferred).
- [ ] **W20** HRTeams (T): the "HR Teams" widget is offered in Add Widget for every app,
  although it is designed only for NetSuite HR Update (AGENTS.md §1). Decide whether to
  hide it.
- [ ] **W21** platform_web (T): a form widget with no data collection yet makes
  `warningsEval` throw (`View[form] didn't define a dataviewID`) instead of listing a
  warning; the error repeats in the console while the designer redraws.
  [abdesigner.md §13](plugins/abdesigner.md#13-walkthrough-building-an-app-from-scratch-observed)
- [x] **W22** Withdrawn 2026-10-03: the "Unplaced" panel does **not** list inactive
  employees; it filters `isinactive` = `"T"` out (`components/data_panel/staffDataPanel.js`,
  also in the built bundle). Only the app DC "Employee Unassigned" holds them, and the panel
  does not use that data. The NetSuite refusal seen on 2026-10-02 came from a test that
  created an assignment for an inactive employee through the model, not through the UI.
- [ ] **W23** platform_service / platform_web (T): NetSuite date fields. A JS `Date` sent
  through the model is stored as its UTC date, a day early east of UTC (local midnight
  2026-10-03 at UTC+7 was stored as 2026-10-02); a `"YYYY-MM-DD"` string is stored as
  given. A reply like `2026-10-01T17:00:00.000Z` is only local midnight of 2026-10-02, so
  the 2026-10-02 case was fine. Once (2026-10-02) dates read through the model came back as
  `{}`; not seen again. [server-platform.md §9](core/server-platform.md#9-traps) trap 24
- [ ] **W24** HRTeams (V, T): every portal load in a tenant that loads the plugin sends
  four `PUT /definition` (`index.js` `apply()` calls `viewRemove` and `viewInsert` on the
  parent, and each saves it), whichever page is opened: seen on the Claude Sandbox "Tasks"
  page on 2026-10-03. Builders and admins rewrite two NetSuite HR Update definitions (the
  "Teams" page and its widget) just by opening the portal; other users get four
  `Forbidden.` errors and four uncaught rejections.
  [hrteams-widget.md §1.3](plugins/hrteams-widget.md#13-every-page-load-re-saves-two-definitions)
- [ ] **W25** HRTeams (T): the edit form refuses an End Date equal to the Start Date ("The
  End Date must be later than the custrecord_team_assign_date_begin.", a raw column name),
  so an assignment cannot be ended on its first day, though the process does exactly that.
- [ ] **W26** HRTeams (V, I): when a principal change needs approval, the form saves only the
  principal flag (`"1"`, then `"0"`); any other change made in the same form is dropped
  (`ABViewOrgChartTeamsComponent.js:1042-1068`).
  [hrteams-widget.md §3](plugins/hrteams-widget.md#3-the-change-to-principal-flow)
  **Fixed in the working tree on 2026-10-03** (C9): the other changes wait in the request
  and are applied with the approval.
- [x] **W27** HRTeams (T, V; fixed 2026-10-16, HRTeams `master` `992d96b` (PR #51), built
  as 1.0.22 on web `master` and `staging` `0f0e6298`; one gap left, W41):
  the "Please wait" card could hang for good with the tab visible; a reload cleared it.
  Two causes, both proven on 2026-10-05. (1) W16 left DCs with a pending job and a
  `reloadPromise` that never settles ("Refreshing", owner's reload as admin; the server had
  answered every read). (2) A read that failed (NetSuite answered 503 to "Team
  Responsibility") left that DC "initializing" for good (W38) ("Initializing DCs").
  `waitDCReady()` (`components/utils.js`) waited on both with no timeout. Fixed by
  `Utils.guardDC()` and a `try/finally` in `refresh()`. Checked again on 2026-10-16: on
  `master`, which does not have the fix, hard reloads of `/` as hr.mock.cni hung 4 times in
  6 (once on "Refreshing", three times on "Initializing DCs"), each with DCs holding load
  jobs that the server had answered in 1 to 9 s (cause 1); every one of the 6 loads had 4
  or 5 such jobs. With the fix, 30 such reloads and 45 admin loads did not hang that way,
  nor 6 more on the spinner-only branch (C11). When NetSuite is slow or rejects reads, the
  guard makes the card wait for its retries (up to about a minute) and then lets the chart
  go on without the failed DC: on 2026-10-16 "Strategy List" failed three times and the
  card cleared after about 80 s. On staging (`ldhr-test.hrupdate.org`) after the deploy, 8
  loads of the Teams page 30 s apart as the owner's builder account all finished in 9 to
  13 s, and the guard settled 4 or 5 dropped loads on each, so W16 happens there too
  (2026-10-16; loaded in a frame that blocked the four W24 saves, testing.md §3.3). After
  the owner switched to a non-builder HR user there, 8 more such loads all finished in 16
  to 17 s, each with the same 65 teams and 464 assignment cards on the chart, 4 or 5
  dropped loads settled and no retry. The gap that is left is W41.
  [hrteams-widget.md §5](plugins/hrteams-widget.md#5-testing-notes)
- [ ] **W28** platform_web inbox (T): the forms of one process are grouped under one entry
  named after one of them, and the dialog keeps that title while paging, so "Notify Success
  in App" showed up as page 2 of "Notify of an Edited Assignment".
- [ ] **W29** HRTeams (V; not reproduced, P4): dropping an RC on a team: the "already exists"
  test `team?.id ?? team == teamId` would be true for any linked object. At runtime
  (2026-10-03) the arrays held plain ids, so drops worked; it only bites if objects appear.
  [hrteams-widget.md §7.5](plugins/hrteams-widget.md#75-responsibility-centre-rc)
- [ ] **W30** HRTeams (V; not reproduced, P4): removing an RC filters with
  `relatedTeam.id ?? relatedTeam != rcId`, which would keep every object entry. At runtime
  the column held plain ids and the link was removed in NetSuite. [hrteams-widget.md §7.5](plugins/hrteams-widget.md#75-responsibility-centre-rc)
- [ ] **W31** HRTeams (V, T): dropping a team node on its own parent returns from
  `_fnDropNode()` without `ready()`, so the Filter button stays disabled (seen 2026-10-03;
  the next action that calls `ready()` clears it).
  [hrteams-widget.md §7.7](plugins/hrteams-widget.md#77-other-details)
- [ ] **W32** HRTeams (V): the Responsibilities picker lists only Team Responsibilities whose
  "updated by" email is the current user's (`is_current_email`), so one HR user cannot pick
  another's. Intended or not is unknown. [hrteams-widget.md §7.4](plugins/hrteams-widget.md#74-responsibilities)
- [ ] **W33** HRTeams (T, cause unknown): seen once each on 2026-10-03, not reproduced: after
  a move that also changed the supervisor, the old card stayed in the new team and the new
  record was not drawn; later the panel listed everyone as Unplaced. NetSuite was right; a
  reload fixed it. [hrteams-widget.md §7.8](plugins/hrteams-widget.md#78-seen-at-runtime-2026-10-03)
- [ ] **W34** HRTeams (V, I): paths that send a JS `Date` straight to the model (the edit
  form's "close and create new", `_updateWithNoPrincipal()`) inherit W23: between 00:00 and
  07:00 Thailand time they would write yesterday's date. The drop paths format dates first.
- [ ] **W35** HRTeams (V, P4): the designer's Pan, Zoom, Depth and Export settings do nothing;
  `_refreshOrgChart()` hardcodes `pan: true, zoom: false` and nothing reads the others.
- [ ] **W36** HRTeams (T, cause not traced, P4): when the process ends an assignment that an
  open chart holds, the chart reloads its data collections by itself (GET Team ×2, Team
  Assignment ×2, Responsibility Centre, Team Responsibility, NS Employee Record ×5, seen at
  17:30:16 and 17:34:31 UTC on 2026-10-03). That reload runs before the process has created
  the new rows, so on its own it leaves the chart stale; `_refreshWhenIdle()` reloads again
  after the request finishes (C9). Which code starts the first reload was not traced.
- [ ] **W37** HRTeams (V, T, P2): `_fetchAllData()` loads a DC to its end with
  `while (records.length < totalCount) await dc.loadData(0, CONST.RECORD_LIMIT)`. Each pass
  asks for the same first 1000 rows (the paged call `loadData(records.length)` is commented
  out above it), so a DC with more than 1000 rows never leaves the loop: requests without
  end, and "Refreshing" for good. **Seen on 2026-10-29** on HR Teams `master` (1.0.22), as
  admin: after switching the entity to "Korea, South", the browser read NS Employee Record
  (`527e22a3`) again every 3.5 s (50 reads in 3 minutes) and the card stayed on "Changing
  to a new entity / Refreshing", with 2 teams drawn and no cards, until the page was closed.
  The loop starts again on every refresh. This is GitHub issue #365 ("KCCC Team Data doesn't
  finish loading"). That Korea's DC holds more than 1000 rows is inferred, not counted.
  [hrteams-widget.md §5](plugins/hrteams-widget.md#5-testing-notes)
- [ ] **W38** platform_web (V, T, P2): a load that fails leaves the DC "initializing" for
  good. `loadData()` sets the status before it asks the server, and on a failed request
  (`platformFind().catch()`) it only rejects, so the DC never emits `initializedData` and
  anything waiting for it (`waitForDataCollectionToInitialize()`, `waitReady()`, linked
  DCs) waits forever. Seen 2026-10-05: NetSuite answered one "Team Responsibility" read with
  a 503 ("Service Unavailable"), and the HR Teams chart stayed on "Initializing DCs" (W27).
  Seen again on 2026-10-16 on "NS Entity" at page load (a 503 after 21 s, during a test
  that reloaded every 10 to 20 s), with the same result. And on 2026-10-29, after about ten page loads and
  entity switches in 15 minutes (one of them W37's endless reads): an `appbuilder.model-get`
  timed out after its 5 resends (`Request timed out.`, 14:20:45 UTC), and the chart stayed on
  "Initializing DCs".
  [frontend.md §10](core/frontend.md#10-traps) trap 30
- [ ] **W39** platform_web (V, T, P2): `waitForDataCollectionToInitialize(DC)` calls
  `eventRemove("initializedData", DC)` before it adds its own listener, so when one DC
  starts two loads that both wait on the same DC, the first load's listener is removed and
  that load never sends its request: no pending job, and a `reloadPromise` that never
  settles. Seen 2026-10-05 on "Employee Assigned" and "Employee Unassigned" (both filter on
  "All Assignments"); the HR Teams chart does not wait on those two. Seen again on every
  load checked on 2026-10-16 (6 of 6, as admin and as hr.mock.pxr): both DCs were loaded by
  another call, yet each kept its `reloadTimer`, had no pending job, and held a
  `reloadPromise` that never settled. The Staff Assignment panel still showed its lists.
  [frontend.md §10](core/frontend.md#10-traps) trap 31
- [ ] **W40** HRTeams (V, T, P2): **every chart draw sends one NetSuite read per team, all at
  once.** `_fnCreateNode()` runs `teamCanDelete()` for each team node (an async block at the
  end of the node setup), and for a team that may be inactivated and has no loaded
  assignment it asks the server for one (`Team Assignment` where the team is that team,
  `limit: 1`). They all start together while the card shows "Refreshing": the api_sails log
  of 2026-10-15 has about 40 such reads within 0.2 s at 06:01:34, and again at 06:04:34.
  appbuilder sends at most 35 NetSuite requests at a time and queues the rest
  (`CONCURRENCY_LIMIT_MAX` in `ABModelApiNetsuite.js`). The owner says NetSuite rejects
  reads that come too often. A small entity such as AEP (2 teams) sends almost none.
- [ ] **W41** HRTeams (V, T, P2): **a failed "NS Entity" read at page load still hangs the
  card on "Initializing DCs"**, with the W27 fix in place. The entity DC's first load starts
  before `DcContainer.init()` attaches the guard: `init()` starts the team DC first, and the
  team DC's load starts the entity's through `waitForDataCollectionToInitialize()`. That
  load is never tried again, W38 leaves NS Entity "initializing" for good, and Team, Team
  Assignment and NS Employee Record wait on it. Caught on 2026-10-16 on the 34th scripted
  admin reload, after NetSuite answered the read with a 503 after 21 s; the owner points out
  that this 503 came from the test's pace (a reload every 10 to 20 s), as NetSuite rejects
  reads that come too often. A fix in HRTeams: guard the entity DC before the team DC loads,
  or load a DC again when it stays "initializing" with no job pending.
  [hrteams-widget.md §5](plugins/hrteams-widget.md#5-testing-notes)
- [ ] **W42** HRTeams (V, T, P2): **a filter can leave out the cards of the teams it
  finds.** A team that only leads to a match is drawn as a title-only box, with no sections
  (`_fnCreateNode()`, `data.filteredOut`). When such a team has an RC, `_refreshRcView()`
  finds its box but no RC section in it, and `_addRcToGroup()` throws `TypeError: Cannot
  read properties of null (reading 'appendChild')`: it has no null check, unlike
  `_addContentRecordToGroup()`. `refresh()` then skips `_refreshContentView()`, so the
  matching teams show no cards, and the RCs after the failing one are not drawn either. Up
  to 1.0.21 the same error also kept "Refreshing" up for good, with the Filter button
  disabled, because the RC step was a `new Promise(async (next) => …)` that never called
  `next()`; clicking the card hid it. Reported from staging on 2026-10-16, before 1.0.22
  reached it (CNI - NS Track, team name "Test": "5451-National Leadership Team" and "QX" as
  title-only boxes, "Test" with empty sections, the card on "Refreshing", Filter greyed).
  Reproduced locally as hr.mock.cni the same day, each time after a page load that had
  finished cleanly: with 1.0.21 the card stayed up for 46 s, until clicked, and "Test"
  showed 0 of its 2 cards; with 1.0.22 (the W27 fix) the card left after 0.6 s and the
  Filter button came back, but "Test" still showed 0 of 2, with the same error. The box
  that fails is "QX", which has 5 RCs: the team name "QX" draws it in full (5 RCs, 3 cards)
  with no error. Fix: return early in `_addRcToGroup()` when the box has no RC section
  (`if ($groupSection == null) return;`). Tried on 2026-10-16 by patching the method in the
  browser only (testing.md §3.3): "Test" showed its 2 cards, with no error, and the chart
  without a filter was unchanged (14 teams, 37 cards, 8 RCs). Not in the code yet.
  [hrteams-widget.md §7.6](plugins/hrteams-widget.md#76-filter)
- [ ] **W43** HRTeams (V, T, P2): **a card can be left out when the cards of its team are
  sorted.** `_addContentRecordToGroup()` puts a new card in place by comparing NS Employee
  Record rows of the data panel DC. It checks the new card's row for null, but not the row
  of the card it is compared with, which is `undefined` when that row is not in the DC
  (`getData()` searches loaded rows only, AGENTS.md §7). `sortByEmployeeLastname()` then
  reads `.lastname` of `undefined` and throws inside the async block, before the new card
  is inserted. Seen on staging on 2026-10-16: two `TypeError: Cannot read properties of
  undefined (reading 'lastname')` on each page load as the user the owner had switched to;
  none locally as hr.mock.cni. From the code, each one leaves one card out (inferred, not
  counted). A fix in HRTeams: skip the comparison when the other card's row is missing.
- [ ] **W44** HRTeams (T, P2): **every card can be drawn twice after an entity switch.**
  Seen once in three tries on 2026-10-29 on HR Teams `master` (1.0.22), as admin: the page
  loaded on AEP ("No Team"), the entity was then set to "CNI - NS Track", and the chart
  showed 74 cards for 37 assignments, each card twice with the same element id
  (`contentnode_<id>`), on one chart of 14 teams. The two other switches from AEP to CNI
  that day drew 37. Not traced. Inference: two `refresh()` calls overlapped (nothing stops a
  second one while the first runs), and both added the cards to the same chart.
- [ ] **W45** HRTeams (V, T, P2): **extra "Add Team" windows cannot be closed with X**
  (GitHub #361). `_showTeamFormPopup()` builds a new Webix window with the same id each time
  the "+" of a team is pressed, without removing the one already open, and the X handler
  looks the window up by that id (`$$(self.ids.teamFormPopup)`). After the first X, the id
  points to nothing, so every other X throws `Cannot read properties of undefined (reading
  'blockEvent')`. Reproduced on 2026-10-29 on `master` (1.0.22): "+" three times on "QX"
  opened three windows; one closed with X, the two others only with Esc.
- [ ] **W46** HRTeams (V, T, P3): **collapsing and expanding teams can leave teams hidden
  until a reload** (GitHub #200, #424). The chart library (`js/orgchart-webcomponents.js`,
  unchanged since 2025-02-12) hides siblings with the parent, and `showParent()` shows only
  the parent, so siblings and their children stay hidden. Reproduced on 2026-10-29 on
  `master` in CNI - NS Track: collapsing and re-expanding above and below "Beijing City" left
  4 of 14 teams on screen; toggling the side arrows of "5451-National External Support" and
  then the National Leadership Team's own arrow brought back only External Support. Adding or
  moving a team calls `addSiblings()`, which ends with `showSiblings()` and so expands teams
  the user had collapsed (GitHub #376, #415; read in code, not run).
- [x] **W47** HRTeams (V, T, P2): **a principal change that needs approval spins until the
  reason Form arrives, with no time limit, and a second Form replaces the first** (GitHub
  #537; fixed 2026-11-03 in HRTeams 1.0.23, `abcc4ab`, C12; on staging since that day,
  production still runs 1.0.21). Up to 1.0.22 such a change saves the flag
  `"1"` then `"0"` and stops its card spinner only when the reason Form of the 41-element
  "Updated Assignments" reaches the browser (`ab.task.userform`, matched by the employee's
  email in `_userFormQueues`). No timeout, no error message, and the card says "around 15
  seconds". Tested on 2026-10-30 on the local stack, with that process put back (C10), on
  the two people in the issue's screenshot (Andorra LDHR: Keith Beyar and Ed Graham V; both
  hold a principal assignment at World Headquarters, so both need approval):
  - One change: Form 69 s after Save (the first trigger of the day also waited for
    appbuilder to connect to process_manager), 41 s later in the day.
  - Two changes saved within 3 s: both cards spun, as in the issue's screenshot. Keith's
    Form came after 43 s and Ed's after 65 s; in a later run after 36 s and 107 s, because
    the triggers of the second change went through `processTriggerQueue` (PE24).
  - The portal shows process Forms in one window (`portal_work_task_user_form`), so Ed's
    Form replaced Keith's: Keith's reason could no longer be entered, and its run waits on
    the Form for good.

  So the widget does stop when the Forms come; on staging, a slower NetSuite or process
  makes the wait longer, and nothing tells the user how long (staging logs were not
  checked). The 2026-10-21 comment on the issue (the card goes for a second and comes back)
  matches a change that needs no approval, which does not wait for a Form (inferred).
  Before the test, the same steps with every write answered by the test page instead
  (no Form can come) spun for over 80 s until a stand-in Form was sent. Fixed by C12
  (PR #52, HRTeams 1.0.23). `guy/enhancements` (`cc217ce`) waits for no
  Form at all, but needs the 17-element process: the two must reach staging and production
  together ([netsuite-hr-update.md §2](netsuite-hr-update.md#2-updated-assignments)).
- [x] **W48** HRTeams (V, T, P2): **a second change saved right after the first can be
  lost without a message** (fixed 2026-11-03 in HRTeams 1.0.23, `abcc4ab`, C12; not on
  production yet). After every save of a Team Assignment, the platform reloads
  the chart's data collections (about 7 at once: Team Assignment, Team, Team
  Responsibility and five of NS Employee Record), and a reload empties a collection first
  (`ABDataCollectionCore.reloadData()`: `clearAll()`, then `loadData()`). In that window:
  - `new CustomProcessTasks()` reads the employee row with `getData()` and throws
    `TypeError: Cannot read properties of undefined (reading 'email')`. In the edit form this
    happens after the form has closed, so the change is dropped with no spinner and no
    message. Seen on 2026-10-30 on `master`: Ed's form was opened before Keith's save came
    back and saved 2 s after it.
  - `_addUserFormQueue()` stores `undefined` for the employee, and the `ab.task.userform`
    listener then throws on `e.dataPanelRecord.email` for every Form that reaches that
    entry, so those Forms never stop their spinners (read in code; the test timing did not
    hit it).

  Opening the edit form inside the window is already blocked ("Caution: Fetching Data",
  seen the same day). Fixed by C12 (PR #52, HRTeams 1.0.23).
- [x] **W49** HRTeams (V, T, P4): **a name that starts with a letter with a diacritic mark
  sorts after "Z"** (GitHub #227; fixed 2026-11-04 in HRTeams 1.0.24, `ecba849`, C13; on
  staging since that day, production still runs 1.0.21). Up to 1.0.23,
  `sortByEmployeeLastname()` and
  `sortByEmployeeFirstname()` (`components/utils.js`) compare lowercased names with `>`,
  which compares UTF-16 code units, so "á" (U+00E1) comes after every plain letter. They
  sort the Staff Assignment panel (Unplaced and Placed), the member cards of a team and the
  Change Supervisor list; `sortByTeamName()` sorts the teams under a parent the same way.
  The panel and the Change Supervisor list sort on the last name only, so people with the
  same last name keep the order of the data collection. Seen on 2026-11-03 in MBE on the
  local stack: "Ágoston, Lili" was 15th of 15 under Unplaced, after "Tavsancea", and
  "Ágoston, Misi" 58th of 58 under Placed, after "Végh, Balázs" (the names in the issue).
  Fixed by C13 (PR #53, HRTeams 1.0.24).
- [x] **W50** HRTeams (V, T, P2): **a team member whose save is still running can be
  edited again, and two edit forms can be open at once** (GitHub #320, a follow-up to
  #280; fixed 2026-11-04 in HRTeams 1.0.25, `30b830f`, C14; on staging since that day,
  production still runs 1.0.21). Up to 1.0.24 a save shows a spinner on the saved card,
  hides its pencil and turns
  off its dragging (`_fnBusyRecord()`, added for #280 so other cards stay editable), but:
  - a double click on that card still opens its edit form;
  - the person's other cards stay editable, and dropping the person from the Staff
    Assignment panel starts another save, so two quick drops can create two assignments;
  - a redraw (`refresh()`) draws the cards again without the spinner;
  - the edit window is not modal and always gets the same Webix id (`ids.contentForm`),
    so a second double click opens a second window (the issue's screenshot shows two for
    one card). `$$()` then finds only the newer one, so Save in the older window reads the
    newer form's values and closes it: the older record would be saved with the other
    form's values (read in code, not run);
  - a drop from the Staff Assignment panel puts the spinner on the card that was dragged
    last, which can be another person's (`_$eventTarget` is set by a card's `dragstart`
    and never cleared; read in code);
  - when one write of a save that makes two fails (ending the old assignment, creating the
    new one), `Promise.all()` gives up at once, and the card is shown ready while the other
    write still runs (read in code; on 2026-11-03 a first version of the fix did the same,
    and the create was sent 7 s after the card was ready).

  Fixed by C14 (PR #54, HRTeams 1.0.25), except the supervisor write of a move (W52).
- [ ] **W51** platform_web (V, T, P4): **closing a form while a connect field still loads
  its options logs an unhandled `TypeError`** in the console: "Cannot read properties of
  null (reading 'getElementsByTagName')", from Webix's `getInputNode()` under
  `setValue()`. For a connection to one record, `_onChange()` in
  `viewComponent/FNAbviewformConnectComponent.js` (ab_platform_web `8707f2fe`, lines
  188-249) takes `$$(ids.formItem)`, awaits `field.getAndPopulateOptions()`, then sets the
  value on that item, which may have been destroyed during the wait. Seen on 2026-11-03 in
  the HR Teams edit form (MBE, card 46): on HR Teams `master` 1.0.23 when the form was
  closed with its X 0.3 s after it opened, and with C14 when Save closed it 0.8 s after it
  opened. Nothing else goes wrong; the form is already gone
  ([widgets.md §8](core/widgets.md#8-traps) trap 23).
- [ ] **W52** HRTeams (V, T, P2): **the supervisor change made while moving a card is sent
  without waiting for it.** A move of a card, to another team or to the other section of
  the same team, first asks "Change Supervisor for …"; after "Assign New Supervisor" and
  "Yes", `_fnContentDrop()` writes the employee's `custentity_ccc_supervisor` with
  `dataPanelDisplayDC.model.update()`, and nothing awaits or catches it. Seen on
  2026-11-03 with the PR #54 build (C14) and every write held by a test page (testing.md
  §3.3): the end and the create of the assignment were answered as successes while the
  supervisor write stayed held, and Kovács could already be edited again, so C14 does not
  count this write; when it then failed, the user got no message and the console showed
  an unhandled rejection. The silent failure is the same on `master` (read in code). A
  second move of the same person in that time can start a second supervisor write
  ([hrteams-widget.md §6.5](plugins/hrteams-widget.md#65-what-happens-on-drag-and-drop)).
  Still open in 1.0.25, which is on staging since 2026-11-04. Seen again with the 1.0.25
  build on 2026-11-05: with the end and the create answered, Kovács could be edited while
  the supervisor write was still held, and when it failed there was no message.
- [ ] **W53** HRTeams (V, T, P2): **a save that fails tells the user nothing.** The save
  of the edit form (`_fnShowContentForm()`) and a drop (`_fnContentDrop()`) catch the
  error and only log it (`console.error`, under "TODO (Guy): The update data error."), and
  platform_web only rejects the request and emits `error.badRequest` or
  `error.badServer`, which nothing listens to. The lock of C14 ends, so the cards can be
  edited again, but no message or window says that the change was not saved: after a
  failed form save the card keeps its old values, and after a failed move the card stays
  where it was dropped until the page loads again. Seen on 2026-11-05 on 1.0.25, with the
  test page failing held writes with a 409 (testing.md §3.3). 1.0.21 (production) has the
  same catches, and so does `_fnDropNode()`, which moves a team (read in code, not run).
  W52 is the same problem for the supervisor write of a move.

---

## 8. P2: ABDesigner

All in [abdesigner.md §12](plugins/abdesigner.md#12-traps) (trap numbers in brackets).

- [ ] **A1** (V) Label format save reports an error after it succeeded. [3]
- [ ] **A2** (V) System apps are shown to plain Builders and system objects are hidden from
  the query join tree (`isSystemObj` typo). [4]
- [ ] **A3** (V) Object workspace views live only in one browser's storage. [5]
- [ ] **A4** (V) Bulk writes from the browser, one request per row (required field with a
  default, CSV import). [6]
- [ ] **A5** (V) API response field clearing never works. [8]
- [ ] **A6** (I) Deleting a process shape deletes its element at once, while the diagram
  saves only on Save; unconfigured tasks have no visible marker. [10-11]
- [ ] **A7** (V, effect I) Copy page lands at the root and stacks listeners. [12]
- [ ] **A8** (V) Property edits save 3 seconds late; Add Widget has no error path; "Data used
  in…" does nothing; an incomplete DC filter wipes the filter. [13-16]
- [ ] **A9** (V) Sidebar and list settings never restore (`AB.Storage.get()` Promise). [18]
- [ ] **A10** (V) App import reloads the whole page. [20]
- [ ] **A11** (V) The mobile app form still offers `relay` and sets `apptype: "web"`; the web
  app form piles up tutorial-manager views. [21-22]
- [ ] **A12** (V) Small UI bugs: imported-field flags ignored, duplicate-column message
  shows "undefined", warnings HTML not escaped. [23-25]
- [ ] **A13** (V) Chart and gantt panels hide system DCs from System Builders and show them
  to everyone else. [widgets.md §8](core/widgets.md#8-traps) trap 20

---

## 9. P3: mobile PWA

All in [mobile.md §8](core/mobile.md#8-traps).

- [ ] **M1** (I) Bundles are unhashed and loaded without `?v=`, so phones can run an old
  build; labels and meta reuse the definitions timestamp as their cache buster.
- [ ] **M2** (V) `AB.notify` only logs to the console, so PWA errors never leave the device.
- [ ] **M3** (V) "Log out" never calls `/auth/logout`; login goes to the demo `/list` page.
- [ ] **M4** (V) The nested core tracks `importOnly`, not `v2`, so the PWA runs an older
  class_core than the web portal.
- [ ] **M5** (I) `build.sh` never builds platform_pwa; the web image ships whatever
  `assets/mobile` exists. [orchestration.md §3](orchestration.md#3-npm-scripts-and-shell-scripts)

- [ ] **M6** platform_pwa (T): a mobile app with `networkType: "socket"` never boots
  (`io is not defined`; the socket.io client is still a TODO). Only `rest` works, but the
  ABDesigner form offers all three. [mobile.md §8](core/mobile.md#8-traps)
---

## 10. P3: dev environment, scripts and tests

- [ ] **E1** (V) `build.sh` is unguarded and destructive, always pushes, breaks under
  `npm run build` with an `allow-scripts` npmrc entry. [AGENTS.md §2.1](../AGENTS.md#21-destructive-scripts)
- [x] **E2** Withdrawn 2026-10-05.
  [AGENTS.md §2.1](../AGENTS.md#21-destructive-scripts)
- [ ] **E3** (V) No restart policies and no healthchecks; `docker compose ps` is not a
  health signal. [AGENTS.md §7](../AGENTS.md#7-traps)
- [ ] **E4** (V) e2e setup: `reset-user.sql` is missing (becomes a directory),
  `CYPRESS_BASE_URL` points at the wrong port, `test-reset.sh` hardcodes its image and exits
  0 on failure, and the reset always hits the admin database (I).
  [AGENTS.md §7](../AGENTS.md#7-traps), [testing.md §2.4](testing.md#24-imports-and-reset)
- [ ] **E5** (V) `npm run test:e2e:ab-designer` matches 0 specs; spec `0003_import_cars`
  fails because `app_test.json` was never committed; the test stack reuses the dev stack's
  ports (I). [testing.md §2.1](testing.md#21-configs),
  [testing.md §2.2](testing.md#22-specs-teste2ecypresse2e)
- [ ] **E6** (V) `npm run logs -- <service>` tails everything; `npm run swarm:logs` is
  broken. [AGENTS.md §3](../AGENTS.md#3-commands)
- [ ] **E7** (V) api_sails lint fails at HEAD (1401 errors on 2026-09-28), so its
  `npm test` fails too; tenant_manager's `npm test` is lint with `--fix`; several unit test
  stubs import a missing `src/handler.js`. [AGENTS.md §9](../AGENTS.md#9-validation),
  [testing.md §1](testing.md#1-overview)
- [ ] **E8** (V) api_sails `npm run doc` fails on
  `api/controllers/metric_manager/metrics-information.js`. [AGENTS.md §6](../AGENTS.md#6-conventions)
- [ ] **E9** (V) Dead or misleading files: `nginx/default.conf`, root
  `assets/`, `test/setup/test-compose.yml`, the stale `.gitmodulescp`, the `web_assets`
  volume. [AGENTS.md §2.3](../AGENTS.md#23-paths-that-are-not-what-they-look-like)
- [ ] **E10** (V) Dependency hygiene: undeclared imports in platform_web (`lodash`,
  `moment`, `nanoid`) and platform_service (`knex`, `uuid`, `async`, `mysql`); `chai` as a
  runtime dependency; ABDesigner's missing `url-loader` and unused `semver`.
  [frontend.md §10](core/frontend.md#10-traps), [abdesigner.md §12](plugins/abdesigner.md#12-traps),
  [server-platform.md §9](core/server-platform.md#9-traps)
- [ ] **E11** (V) Telemetry: Sentry's 5% sample rate also drops 95% of
  `AB.notify.developer` reports; the slow-network worker pings google.com from every
  browser. [frontend.md §10](core/frontend.md#10-traps) trap 26
- [ ] **E12** (V) MariaDB `--wait-timeout=60` still aborts idle connections from ab-utils'
  shared mysql pool, which has no idle timeout (harmless log noise).
  [AGENTS.md §7.1](../AGENTS.md#71-startup-log-triage)
- [ ] **E13** (T) On rootless Docker, api_sails cannot store an upload: `POST
  /definition/import` (AB Designer's Import) answered `{"status":"error"}` on 2026-10-30,
  and the log said `Error writing file /app/.tmp/uploads/<uuid>.json ... EACCES`. Same cause
  as the `auth.log` problem ([AGENTS.md §7](../AGENTS.md#7-traps), Local environment); not
  fixed. Definitions can still be written one by one
  ([netsuite-hr-update.md §2.4](netsuite-hr-update.md#24-switching-versions-in-this-tenant)).
- [ ] **E14** (T) Upstream api_sails cannot start with its image's command under this
  compose. The image runs `app_waitMysql.js`, which reads `config.datastores.site` from
  `config/local.js`, and upstream has had that line commented out since 2025-09 (`5ce8600`,
  "try to remove the db required to lift"): `TypeError: Cannot read properties of undefined
  (reading 'site')`, exit 1, and then `web` exits too ("host not found in upstream
  api_sails"). Seen on 2026-10-30 after the restore; a process started before then had kept
  running the old code (C2 had uncommented the line). Since then compose runs
  `command: ["app.js"]`, which lifts without the database and reached every service.
  [AGENTS.md §4.1](../AGENTS.md#41-container-topology)

---

## 11. P4: small bugs and code quality

- [ ] **Q1** platform_web (V): `AB.isString()` is always false; `pluginAPI.platform` is
  undefined in the browser; `ABViewEditorPlugin` reads `view.AB` before its null check;
  `ABPropertiesObjectPlugin.formIsValid()` never returns true. Frontend traps 9, 15,
  18-19.
- [ ] **Q2** platform_web (V): console noise on every socket event, DC load and form
  render. Frontend trap 12.
- [ ] **Q3** platform_web (V/I): login button comes back after "too many attempts"; the
  reset screens ignore errors; `index.ejs` typo `margin:0q`. Frontend traps 21-22
  and 27.
- [ ] **Q4** platform_web (V): grid `ignoreLocal` never set; failed mass update leaves the
  popup stuck; form tree lookup uses the wrong key; `form-url` cannot reach external URLs
  over the socket (I). Widgets traps 3, 5, 8
  and 14.
- [ ] **Q5** platform_web (V): the Lighthouse workflow names `ciLighthouseAuth.js`, the file
  is `.cjs`. Frontend trap 25.
- [ ] **Q6** ABDesigner (V): label panel latent errors (unverified whether they run); dead
  property and editor copies drift from the live ones. Widgets traps 21-22.
- [ ] **Q7** ABDesigner (V): build nits: version string `"0.0.0"`, `.gitignore` uses `//`
  comments. [abdesigner.md §12](plugins/abdesigner.md#12-traps) trap 26
- [ ] **Q8** platform_web (unverified): where the `Selectivity` global comes from.
  Frontend trap 20.

---

## Not listed here

Behavior that is surprising but works as designed (for example `getData()` searching only
loaded rows, or `req.broadcast` finishing before `cb()`) stays in the "Traps" lists of
AGENTS.md and the docs. Add it here only when we decide it is a bug to fix.
