# NetSuite HR Update

Everything about the "NetSuite HR Update" app (`79e11053-…`), the product app: its objects
(§1.1), its BPMN processes and what they did in this stack (§1 to §10), who can see what
(§11), the cross-entity principal change built on 2026-10-03 (§12), and Global HR Update,
the separate web app that sends change requests into it (§13). The HR Teams
widget's code is in [hrteams-widget.md](plugins/hrteams-widget.md); its §6 also describes how this
app wires the widget (objects, data collections, settings), so the two pages overlap a
little on purpose. How the engine works in general is in [processes.md](core/processes.md).

Read from the running stack on 2026-10-02 to 2026-10-04: definitions through the browser
factory, run history from `appbuilder-admin`.`SITE_PROCESS_INSTANCE` and
`SITE_PROCESS_FORM` (read-only SQL), and the test runs described in §7, §8 and §12.

---

## 1. Overview

| Process (label / definition name) | Starts when | Purpose |
|---|---|---|
| Updated Assignments | a **Team Assignment** (NetSuite `customrecord_ccc_team_assignment`) is **updated** | Bookkeeping in `history`, then notify HR. Until 2026-10-03 it also moved a principal assignment between entities with approval |
| Principal Change Approval (first named "cache-principal-change approval") | a `cache-principal-change` row is **added** (by the HR Teams widget) | The cross-entity principal move, with approval (§12) |
| New Assignments | a Team Assignment is **added** | Nothing, on purpose: switched off by leaving Start unconnected (§3) |
| New Submission | a local `employee` row is **added** | Mark it pending, send it to the external approval site, clear the flag |
| Updated Submission / `external_approval` | a local `employee` row is **updated** | Same, only when it is **not** already pending |
| Test | | Empty |

Triggers fire for NetSuite objects too: appbuilder's `model-post` / `model-update` register
the trigger with no NetSuite exception (`developer/appbuilder/handlers/model-post.js:248-270`).
So every save the HR Teams chart makes (create, move, end, edit an assignment) starts one of
the assignment processes; team, RC, responsibility and supervisor writes start none (seen
2026-10-03, [hrteams-widget.md §7.8](plugins/hrteams-widget.md#78-seen-at-runtime-2026-10-03)). Writes made by process tasks (InsertRecord, queries) do not fire
triggers ([processes.md §4](core/processes.md#4-lifecycle-triggers-from-data-changes)).

### 1.1 Objects

| Kind | Class | Objects | Data lives in |
|---|---|---|---|
| AppBuilder (local) object | `ABObject` | `employee`, `entity`, `history`, `cache-principal-change` (since 2026-10-03, §12.3), `site user` | MariaDB, the tenant database |
| NetSuite API object | `ABObjectApiNetsuite` (`isAPI`, `isNetsuite`) | NS Entity, NS Employee Record, Team, Team Assignment, Team Responsibility, Team Strategy, Responsibility Centre, Role Type and the custom lists | NetSuite (REST record API + SuiteQL), primary key `id` |

`entity` vs `NS Entity`: `entity` is the local copy (plus the HR user links, §11); `NS
Entity` is the live NetSuite `subsidiary` record. They are linked one-to-one by the `NS
Entity` connect field. Verified from the definitions on 2026-10-02.

Table names are stored per object: `AB_GlobalHRUpdate_employee` and
`AB_GlobalHRUpdate_entity` (the app's earlier name), `AB_NetSuiteHRUpdate_history`,
`AB_NetSuiteHRUpdate_cacheprincipalchange`. Global HR Update writes `employee` and fills
`entity` and its HR users (§13.2).
What each object means to the HR Teams chart:
[hrteams-widget.md §6.2](plugins/hrteams-widget.md#62-objects).

---

## 2. Updated Assignments

There are two versions, and they need different HR Teams code (§2.4):

| Version | Runs with | Where |
|---|---|---|
| 41 elements, with the cross-entity part and its reason Form (§9) | HR Teams `master` (1.0.25 on staging since 2026-11-04, 1.0.21 on production), which waits for that Form (since 1.0.23 for up to 2 minutes) | **In this tenant since 2026-10-30**, put back for the GitHub #537 tests; staging and production are assumed to run it too (not checked) |
| 17 elements, without the cross-entity part (below) | HR Teams `guy/enhancements` (§12) | Saved in [backups/definitions/updated-assignments-2026-10-30.json](../backups/definitions/updated-assignments-2026-10-30.json) |

The rest of this section describes the 17-element version.

On 2026-10-03 its cross-entity part (24 elements) was removed with the owner's go-ahead.
Moving a principal between entities is now the job of "Principal Change Approval",
which starts from a row the HR Teams widget writes (§12). 24 elements and 25 flows were
removed, plus 3 stale connections that were not in the diagram, and the end-principal
notice no longer names the deleted "Get HR Users in other Entities". The old definitions
(the process and its 41 elements) are saved in
[backups/definitions/updated-assignments-2026-10-03.json](../backups/definitions/updated-assignments-2026-10-03.json),
and what the removed blocks did is kept in §9.4 and §9.5 as a record.

Flow, read from the diagram's sequence flows:

1. **Start** (Team Assignment updated).
2. **History bookkeeping:** Update the previous latest history → Insert a new latest
   history (InsertRecord) → Update `last_modified_datetime` in the history → Get
   `last_modified_datetime`.
3. **Collect context:** Employee ID in this entity → employee's email → entity ID → HR
   users in this entity → first name → last name → entity name.
4. Gateway **Is Principal Assignment?**
   - **No** → Approval "Notify of an Edited Assignment" (an inbox notice for this entity's
     HR) → End.
   - **Yes** → gateway **Do Date End have value?**
     - **Yes** (the principal assignment is being ended) → Approval "Notify of an End
       Principal Assignment" → End.
     - **No** → "Notify of an Edited Assignment" → End. Until 2026-10-03 this branch was
       the cross-entity part: a hidden reason Form, the other entity's approval, and the
       end-and-copy writes (§9.4, §9.5).

All three paths were run on 2026-10-03 after the change and sent the expected notice
(§12.5).

### 2.1 What the gateways and tasks really check

Read from the task settings (field ids resolved against the Team Assignment object):

- Both gateways test the **updated Team Assignment row** (the trigger data).
  "Is Principal Assignment?" = `custrecord_team_assign_is_principal` checked.
  "Do Date End have value?" is misnamed: **Yes** means `custrecord_team_assign_date_end`
  is today or earlier (the assignment has ended); **No** means it is empty or in the future.
- "Notify …" tasks are Approval tasks used as inbox notices with a Close button:
  "Notify of an Edited Assignment" and "Notify of an End Principal Assignment" go to this
  entity's HR. The end notice also named "Get HR Users in other Entities", which was never
  set on its branch; that reference went with the rework.
- Removed with the cross-entity part on 2026-10-03, and so no longer true of this process:
  PE11 (the hidden reason Form and the runs left waiting on it), PE13 (both Email tasks),
  PE14 and B25 (the recipients of "Ask Other Entity HR to Approve"), PE15 (the heavy
  plucks), PE16 (the wrong entity name on the approval form), PE17 ("Get Job Description"
  on the wrong field), and the dead `undefined.…` and `bbae3677-….EntityHRUsers`
  references.

### 2.2 How the HR Teams widget drives it

Every save the chart makes on an assignment (create, move, end, edit) starts one run, as
before. Since 2026-10-03 a principal change that needs the other entity's approval saves
**nothing** to NetSuite, so it starts no "Updated Assignments" run: the widget writes a
`cache-principal-change` row instead (§12.2).

Before that, the widget (`ABViewOrgChartTeamsComponent.js:1042-1070` at the time) queued
the reason Form, saved principal = `"1"` (run **A**, which asked for the reason and the
other HR's approval) and then principal = `"0"` (run **B**, "Notify of an Edited
Assignment"). One "make principal" click made two runs, and a principal save that needed
no approval still queued a Form the widget then hid (PE11). Seen at runtime on 2026-10-03
(§8).

The widget decides with the HR user's own read rights. The HR scope does not restrict
Team Assignment or NS Employee Record (§11),
so a one-entity HR user still sees the other entity's records and the check works (§8).

### 2.3 In plain words

Every edit of an assignment notifies this entity's HR; ending a principal assignment sends
the end notice instead. Making someone principal here while they are principal in another
entity is handled outside this process: the widget asks for a reason and the other
entity's HR approves or rejects it in "Principal Change Approval".

The Approval tasks named "Notify …" are used as inbox notices, not real approvals.

### 2.4 Switching versions in this tenant

Done on 2026-10-30 (to the 41-element version), with the owner's go-ahead:

1. Back up first. Every row of `appbuilder_definition` went to
   [backups/definitions/admin-tenant-definitions-2026-10-30.json](../backups/definitions/admin-tenant-definitions-2026-10-30.json)
   and the process with its 17 elements to `updated-assignments-2026-10-30.json`, read with
   a `SELECT JSON_OBJECT(...)` in the `db` container. NetSuite credentials in those rows are
   `ENV:` references, not values.
2. `POST /definition/import` (AB Designer's Import) does not work here: api_sails cannot
   write the upload to `/app/.tmp/uploads` (`EACCES`, known issues E13).
3. Write each row through the definition API instead, from a page of the portal's origin
   while logged in as a builder: `POST /definition/create` with `{id, name, type, json}` for
   the 24 rows the target version has and the tenant does not, then `PUT /definition/:id`
   with `{name, type, json}` for the rows that differ (two "Notify" tasks, then the process
   row last). `name` is `json.name`. Each call sends `definition.created` or
   `definition.updated`, and every service reloads the tenant's definitions on its next
   request. The 15 rows that were the same in both versions were not written.
4. Compare the rows with the backup afterwards (all 42 matched, and no other row changed).

The rows the 17-element version does not use stay in the tenant after a switch back unless
they are deleted (`DELETE /definition/:id`); no other definition refers to them.

---

## 3. New Assignments is switched off on purpose

**This is intended. Do not "fix" it.** The requirements changed: a new assignment no
longer leads to any follow-up action (repo owner, 2026-10-02). The process was switched off
by leaving its Start event without an outgoing sequence flow; the old tasks are still in
the diagram, unconnected.

What that looks like, so it is not mistaken for a bug: every Team Assignment create still
starts a run, which logs `StartEvent_1 : Start : Error: Configuration Error: Did not find
any outgoing flows for dID[StartEvent_1]` and is saved as **completed**. All 20 runs
between 2026-09-13 and 2026-09-22 did this.

The unconnected (old) flow, for reference: Is Principal Assignment? → Is Date Start on or
after today? → this entity's ID → its HR users → "Notify Success in App" → Email "Notify
Success" → End.

---

## 4. Submissions and the external approval site

New Submission: Start → Set to pending approval → External "Approve Changes" → Set to NOT
pending approval → End. Updated Submission (definition name `external_approval`) adds a
gateway "Check if pending approval" first: its **Yes** flow is `is_approval_pending`
unchecked (go on and ask for approval), its **No** flow is checked (End). So an update to a
row that is already waiting for approval starts nothing new. The label reads the other
way round; read from the definition on 2026-10-03.

The Global HR Update site is the approval web app behind the External task; see
§13.

The External task sends the user to
`https://localhost:23803/approve/{%= Start.data.netsuite_id %}?subsidiary={%= Start.data.entity_id %}`,
a separate approval web app that is **not in this repo** (port 23803, one above this
stack's `WEB_PORT`). The process waits until that site calls back. New Submission also
holds a second, unconnected External task with an empty URL (the designer warns "should
have another task after this one").

---

## 5. Run history in this stack (2026-10-02)

| Process | completed | waiting (`created`) | error |
|---|---|---|---|
| Updated Assignments | 21 | 32 | 13 |
| New Assignments | 20 (did nothing by design, §3) | | |
| Updated Submission (`external_approval`) | 3 | | |
| New Submission | | 2 (since 2026-06-18) | |

`SITE_PENDING_TRIGGER` is empty, and no instance has the `"UUID()"` key from
[known-issues.md](known-issues.md) B4.

**Waiting Updated Assignments runs (32):**

- 19 wait on a pending "Notify of an Edited Assignment" inbox item (all from 2026-09-14 and
  09-15). They finish when someone opens and answers it in the inbox. Many of them are likely the "run B" half of a make-principal change (§2.2, inferred).
- 15 have no pending form at all. Every one of their logs ends right after "Get Entity Name
  By Principal Assignment ID", so they stopped at the **Form "Ask this User to confirm with
  the reason"**. A Form task is a popup pushed to the user whose request is running
  (`ab.task.userform`, [frontend.md §4.5](core/frontend.md#45-other-screens)); it creates no
  inbox row. The HR Teams widget **hides that popup on purpose** when it decided that no
  approval is needed: it queues the request without `needUserForm`, and drops any such
  form that arrives while its queue is empty (`ABViewOrgChartTeamsComponent.js:1521-1556`
  and `:2450-2470`; the code comment says this stops the next process task). So each
  in-place save of a current principal assignment that needs no approval leaves one run
  waiting here for good. Verified in code; the popup and its matching by email were seen
  at runtime in the approval case (§8).
- 2 New Submission runs wait on the external "Approve Changes" since June.

**Errors (13, all 2026-09-13 to 09-15; later runs of the same tasks completed, so these
look fixed since, inferred):**

| Task | Error | Count |
|---|---|---|
| Create New Assignment in the other Entity (InsertRecord) | `Cannot read properties of null (reading '_user')`; `req.log is not a function` | 3 + 2 |
| Get Entity Name By Principal Assignment ID | NetSuite: `Invalid or unsupported search` | 3 |
| Get Employee ID in this Entity | NetSuite: `Record type 'suiteql' does not exist`; `Invalid URL` | 2 + 2 |
| Notify Success (Email) | `Cannot read properties of undefined (reading 'users')` | 1 |

Even when the flow works, the Email tasks cannot send today, because email sending is broken
([known-issues.md](known-issues.md) B1).

Queries used for this section (run them with `npx env-cmd docker compose exec -T db sh -c
'mysql -uroot -p"$MYSQL_ROOT_PASSWORD"' < file.sql`; the two tables need an explicit
`COLLATE utf8mb3_general_ci` on the join, or MariaDB stops with "Illegal mix of
collations"):

```sql
USE `appbuilder-admin`;
SELECT d.name, i.status, COUNT(*) FROM SITE_PROCESS_INSTANCE i
  LEFT JOIN appbuilder_definition d
    ON d.id COLLATE utf8mb3_general_ci = i.processID COLLATE utf8mb3_general_ci
  GROUP BY d.name, i.status;
SELECT name, status, COUNT(*) FROM SITE_PROCESS_FORM GROUP BY name, status;
```

---

## 6. Designer warnings on these processes

ABDesigner reports, among others: TaskServiceQuery "requires at least one Save operation"
on several query tasks (they only update values), Email "can not resolve the lane
participant for [.from]" on Notify Success and Notify Fails, Email "Notify Fails" "is
missing a message", and "No process Tasks defined" (Test). The query warnings are
expected for update-only tasks (inferred); the Email ones would matter once email works.
Since 2026-10-03 "Updated Assignments" shows 2 issues (both Email tasks went with the
rework) and "Principal Change Approval" shows 5, all of the "Save operation" kind.

---

## 7. A test run as a mock HR Generalist (2026-10-02)

NetSuite here is **sandbox 3** (`3540813-sb3.suitetalk.api.netsuite.com`, seen in the
appbuilder log). The two kinds of objects are in §1.1, the Global HR Update web app in
§13.

Setup (data only, no definition changed):

- user **hr.mock.aep** (`3e06fd78-…`, no password) with the HR Generalists role;
- a local `entity` row for NetSuite subsidiary **1805 AEP**, with `User = hr.mock.aep`
  (what `syncEntities.js` and `importHrGeneralists.js` would write);
- `POST /auth/switcheroo/<user uuid>` as admin.

As hr.mock.aep, NetSuite HR Update was the only app; the NS Entity data collection held only
**AEP** (the Netsuite Entity scope worked), with 2 teams, 0 assignments and 23 "Unplaced"
employees. **Responsibility Centre returned 0 rows** for this user (14 for admin), because
that object is not listed in the Netsuite Entity scope.

Creating a Team Assignment the way the chart's drop does (`model().create` with begin date,
employee, team, role type Member, entity, principal 0):

1. Employee 1744 was refused by NetSuite: `Invalid Field Value 1744 for the following field:
   custrecord_ccc_team_assign_emp_id`. Most employees in the app's "Employee Unassigned"
   DC for AEP have `isinactive = T`; the HR Teams panel itself hides them, so this only
   happens outside the UI (W22, withdrawn).
2. Employee 1748 (active) worked: NetSuite record **57005**. "New Assignments" ran and did
   nothing, by design (§3).
3. Setting the end date to `2026-10-02` was accepted, but the reply showed
   `2026-10-01T17:00:00.000Z`, and re-reading the row returned the dates as `{}` (W23).
4. "Updated Assignments" first **failed** at "Get HR Users in this Entity":
   `unknown relation "SandboxItem_Owner__relation"`. A `user` field added in the Claude
   Sandbox app had given `SITE_USER` a new relation, and process_manager still had the old
   Objection model cached (B22). After `docker compose restart process_manager` the next
   run went: history bookkeeping → employee lookups → HR users → "Is Principal Assignment?"
   → **No** → "Notify of an Edited Assignment" in hr.mock.aep's inbox → answered → End.
5. One update failed with an empty `Rejected by NetSuite.` message: SuiteQL had answered
   **503 Service Unavailable** (an Akamai edge error) and nothing retries (R22). Repeating
   the update worked.
6. Every write logged `log_manager.rowlog-create` → `"row" must be a valid GUID` and a
   developer notification: row logs never work for NetSuite rows (R8).

Assignment 57005 stays in NetSuite sandbox 3, ended on 2026-10-02 with job title "Claude
test (ended)". The mock user, its role link and the AEP `entity` row stay in the tenant.
Switcheroo was cleared afterwards.

---

## 8. A cross-entity principal move, end to end (2026-10-03)

Done in the HR Teams UI as two mock HR users, with the owner's go-ahead to create the test
data. NetSuite sandbox 3. Data only; no definition was changed on purpose (but see W24 in
[known-issues.md](known-issues.md)).

### 8.1 Setup

- A real sandbox employee with active records in two entities and no team assignments:
  employee **3126713** in **PXY** (2715) and **2286202** in **PXR** (4925), same email.
  New NetSuite employees cannot be created through the AppBuilder object: NetSuite asks for
  nine custom fields the object does not have (Marital Status, Staff Unit, Position | Role,
  Organizational Status, Funding Source, Geographic Area of Service, HR Department, Scope,
  Birth Date).
- Users **hr.mock.pxy** and **hr.mock.pxr** (HR Generalists, no password), local `entity`
  rows 2715 → hr.mock.pxy and 4925 → hr.mock.pxr, switching between them with switcheroo.
- Drag and drop: the browser tool's mouse drag does not start an HTML5 drag in Chrome on
  Linux, so drops were made by firing `dragstart`, `dragover` and `drop` with one
  `DataTransfer` on the real elements, which runs the widget's own handlers (recipe in
  [hrteams-widget.md §5](plugins/hrteams-widget.md#5-testing-notes)).

### 8.2 What happened

| Step | Who | Result |
|---|---|---|
| Drop 3126713 on PXY "2715-National Leadership Team", Member | hr.mock.pxy | Assignment **57105**, principal **1** (no principal anywhere else). "New Assignments" ran and did nothing (§3) |
| Drop 2286202 on PXR "PXR National Leadership Team", Member | hr.mock.pxr | **57106**, principal **0**: the widget found the PXY principal by email |
| Edit 57106, tick Is Principal, Save | hr.mock.pxr | Card "This user has a Principal Team Assignment in another entity"; `run()` took about 1.5 s. Two runs: A (principal "1") and B (principal "0", "Notify of an Edited Assignment" to hr.mock.pxr) |
| Reason form | hr.mock.pxr | Arrived about **40 s** after Save (the card says "around 15 seconds"), naming PXY as the principal's entity. Submitted |
| "Ask Other Entity HR to Approve" | nobody | Created with **no recipients** (B25). A recipient row for hr.mock.pxy was added by hand to `AB_JOINMN_ProcessForm_USER_users` to go on |
| Approve in the inbox | hr.mock.pxy | 57105 and 57106 got end date = today; new rows **57107** (PXY, principal 0) and **57108** (PXR, principal 1) start today. "Notify Success in App" went to hr.mock.pxr only. Then the Email task "Notify Success" crashed and the run ended as `error` (PE13) |
| Reverse: edit 57107, tick Is Principal | hr.mock.pxy | Same pattern, and again no recipients (B25, second time). hr.mock.pxr was added by hand and **rejected**: "Is Approved?" → No → "Notify Fails in App" (hr.mock.pxy only) → Email "Notify Fails" crashed the same way. 57107 stayed principal 0 |
| Cleanup: end 57107 and 57108 | each HR | "Notify of an Edited Assignment", and for 57108 the end-principal branch (Yes, Yes → "Notify of an End Principal Assignment" → End) |

On the charts the principal card has a dark border: after the approval the PXR card had it
and the PXY card did not.

### 8.3 What it showed

- **The approval never reaches the other entity's HR when the person has records in only
  one other entity** (B25). "Get Other Entity IDs by this Employee's Email" returns
  `["2715"]`, but `ABProcessCore.processData()` hands a one-element list back as the bare
  value, and the `in` rule built from it compiles to `1=0`, so "Get HR Users in other
  Entities" returns `null` ([processes.md §7](core/processes.md#7-traps) trap 31). The run waits
  forever and the person is never made principal. The owner's September runs worked
  because that person had records in two other entities.
- **The other-entity list "by Principal Assignment" is not filtered by employee** (PE14):
  155 entities. Plucking their ids through the NetSuite object loaded every team
  assignment, team, employee and responsibility of those subsidiaries (22 pages of
  results) on each request (PE15).
- **Both Email tasks always crash** (PE13): their From is the current participant, the
  process has no lanes, and `resolveAddresses()` calls `.users` on `undefined`. The run is
  saved as `error` after all data changes are done, so `error` does not mean the move
  failed.
- The widget's own check works for a one-entity HR user, because the HR scope does not
  restrict Team Assignment and NS Employee Record (S35).
- Rows written by the process carry the **requesting** HR's email in
  `custrecord_ccc_team_assign_update_in_app`, also the row written in the other entity.
- The edit form cannot end an assignment on the day it started (W25), though the process
  does exactly that. Ending through the model with a JS `Date` stored the day before (W23);
  a `"YYYY-MM-DD"` string worked.

### 8.4 Left in place

NetSuite sandbox 3: assignments 57105 to 57108 for employees 3126713 and 2286202, all
starting and ending on 2026-10-03, so the person is "Unplaced" again in both entities.
Tenant: users hr.mock.pxy and hr.mock.pxr, `entity` rows 2715 and 4925, nine process runs
(two "New Assignments", seven "Updated Assignments": five completed, two `error` from PE13)
with their answered inbox forms, and the matching `history` rows. Switcheroo was cleared
afterwards.

---

## 9. "Updated Assignments", block by block (2026-10-03)

Read from the stored definitions (41 elements) with every id resolved to a name. Blocks are
in flow order. "Start" means the updated Team Assignment row (the trigger data). §9.4 and
§9.5 were removed later the same day and put back in this tenant on 2026-10-30 (§2); the
definitions are in
[backups/definitions/updated-assignments-2026-10-03.json](../backups/definitions/updated-assignments-2026-10-03.json).

### 9.1 Bookkeeping in `history`

| Block | Does |
|---|---|
| Update the previous latest history | `history` rows with `object_id` = Team Assignment, `record_id` = this assignment, `is_latest` on → first → set `is_latest` = 0 |
| Insert a new latest history (InsertRecord) | `object_id`, `record_id` = this assignment, `is_latest` = 1 |
| Update last_modified_datetime in the history | the latest row → `last_modified_datetime` = now |
| Get last_modified_datetime in the history | read it back as `last_modified_datetime` |

So `history` keeps, per assignment, one "latest" row with the time a change was last
processed. Its only reader is the "Submitted Timestamp" field of the "Notify of an Edited
Assignment" and "Notify of an End Principal Assignment" notices: nothing in this repo, the
HR Teams plugin or `../global-hr-update` reads the table (grep, 2026-10-03). The owner's
instruction is to leave it alone for now.

When two runs for the same assignment start in the same second, both insert a "latest"
row and one keeps the column's fixed default, `2026-01-26 21:00:23`: 2 of 21 records have
two "latest" rows (PE18). "Get last_modified_datetime" takes the first, so a notice can
show that stale date. 77 rows on 2026-10-03, all for Team Assignment.

### 9.2 Lookups for this assignment

Get Employee ID in this Entity → Get Employee's email in this Entity → Get Entity ID in
this Assignment → Get HR Users in this Entity (the `entity` row of this entity → its `User`
list, saved as `HRUsers`) → first name → last name → Get Entity Name in this Assignment.

### 9.3 The gateways

| Gateway | Yes | No |
|---|---|---|
| Is Principal Assignment? | `custrecord_team_assign_is_principal` checked | unchecked → "Notify of an Edited Assignment" (to `HRUsers`) → End |
| Do Date End have value? | end date ≤ today → "Notify of an End Principal Assignment" (to `HRUsers`) → End | end date empty or later than today → "Notify of an Edited Assignment" → End (until 2026-10-03: the cross-entity part) |
| Is Approved? (removed 2026-10-03) | the approval's answer is `approve` | `reject` |

### 9.4 The cross-entity part (only in the 41-element version)

| Block | Reads | Saves |
|---|---|---|
| Get Team Assignment IDs in other entities by Employee's email | NS Employee Records with this email, active → their assignments | `OtherAssignmentIDsInOtherEntity` (this entity's too) |
| Get Principal Assignment ID in other Entity | those assignments that are principal and current → first | `OtherEntityPrincipalAssignmentID` (may be one in this entity) |
| Get Entity Name By Principal Assignment ID | that assignment's entity | `PrincipalEntityName` |
| Form "Ask this User to confirm with the reason" | popup to the requesting user | the reason |
| Get Other Entity IDs by this Employee's Email | active employee records with this email, not this one → subsidiaries | `OtherEntityIDs` |
| Get Other Entity IDs by Principal Assignment | **every** current principal assignment except this one (no employee filter, PE14) → entities | `OtherEntityIDs` |
| Get HR Users in other Entities | `entity` rows in both lists, not this entity → `User` | `OtherEntityHRUsers` (empty when the first list has one entry, B25) |
| Approval "Ask Other Entity HR to Approve" | to `OtherEntityHRUsers` (and a dead `bbae3677-….EntityHRUsers`) | `approve` / `reject` |

Seen on 2026-10-31 with the reasons answered ([known-issues.md](known-issues.md) C12):
for Keith Beyar (Andorra, principal at World Headquarters) the email lookup found three
other entities (`1314`, `2135`, `1`), for Ed Graham V fourteen; the principal lookup found
155 both times. The HR users are the local `entity` links among the entities in both
lists: admin (World Headquarters) for Keith, admin and hr.mock.cni (CNI) for Ed. Each
Approval carried its own reason and came 32 to 67 s after the answer. A rejected one goes
on to "Notify Fails in App" for the same users and waits there. The run's context holds
each user's whole row, `password` and `salt` included (S34). The Form writes no line to
the run's log.

### 9.5 After approval (only in the 41-element version)

| Block | Does |
|---|---|
| Get the other Entity ID / Job Title / Job Description / Employee ID / Team ID / Role Type ID in the other Entity | read the other entity's principal assignment. **"Get Job Description" filters on `custrecord_team_assign_job_desc` = the assignment id instead of `id`**, so it finds nothing (PE17) |
| End Principal Assignment in the other Entity | that assignment: end date = today |
| End this Assignments | the updated assignment: end date = today |
| Get this Assignments End Date | saves `EndDate` (today) |
| InsertRecord "Create New Assignment in the other Entity" | new Team Assignment: job title, job description, employee, team and role type from the other principal, entity = the other entity, begin = `EndDate`, `update_in_app` copied from Start; principal not set (false). Five of its values still list a dead `undefined.…` source before the live one |
| InsertRecord "Add this Principal Flag" | new Team Assignment copied from Start (job title, job description, employee, entity, team, role type, principal = Start's flag, `update_in_app`), begin = `EndDate` |
| Approval "Notify Success in App" | to `HRUsers` and `OtherEntityHRUsers`; shows the **old** assignment id (Start) |
| Email "Notify Success" | crashes (PE13) |

On rejection: "Notify Fails in App" (same recipients) → Email "Notify Fails" (crashes) → End.

### 9.6 The other processes, for completeness

- **New Assignments** (switched off, §3): besides the unconnected Start, its "Is Principal
  Assignment?" gateway has Yes and No flows with **no conditions** and a third flow with
  no label. Moot while it is off; it would need fixing before it is switched back on.
- **New Submission** and **Updated Submission**: §4.
- **Test**: empty.

---

## 10. Why a principal change is slow (measured 2026-10-03)

Counted from the process_manager log of the cross-entity run in §8 (run A `cb71ef03` and
its partner run B), per request:

| Part | Time | NetSuite queries |
|---|---|---|
| Run A, Save → reason form | 33 s | 38 |
| Run B (the `"0"` save) | 10 s | 20 |
| Run A, reason → approval form | 49 s | 18, plus 22 result pages for "by Principal Assignment" |
| Run A, approve → success notice | 32 s | 35 |

So about two minutes and over 110 NetSuite requests for one change, while the data it
really needs is two employee records, three assignments, two entity names and the local
HR users. Where it goes:

1. **One block carries one value.** A query block is find → first → pluck one field →
   save. Six fields of the same record take six blocks and six reads of the same row
   ("Get … in the other Entity" reads assignment 57105 six times).
2. **Following a connect field reads far more than the link.** `row_pluck`/`set_pluck` on
   a connect field re-reads the rows with that field populated, then reads the linked rows
   with `populate: true`, which loads **every** relation of the linked object; for a
   NetSuite object each relation is another SuiteQL query ([processes.md §7](core/processes.md#7-traps)
   trap 32). "Get Entity ID in this Assignment" read all assignments, teams, employees,
   responsibilities and departments of PXR to return `4925`.
3. **Many hops fetch an id the run already has.** The trigger row already carries the
   employee, entity, team and role type ids, yet "Get Employee ID in this Entity" and "Get
   Entity ID in this Assignment" read them again, each with the fan-out above.
4. **Two runs per change.** The widget saves `"1"` then `"0"` (§2.2); run B repeats the
   `history` bookkeeping and the lookups only to send "Notify of an Edited Assignment".
5. **Everything is sequential, and some reads are slow on their own**: the search by email
   took about 5 s.

The request that starts a run (`process_manager.trigger`) outlives the 5 s service
timeout, so the log shows "preventing duplicate request" every 5 s while it runs; the
resends are dropped and cost little.


### 10.1 After the redesign (2026-10-03)

Measured the same day with the same person after the change in §12:

| Part | Before | After |
|---|---|---|
| Save → the requester can type the reason | about 40 s (a process Form) | 2.7 s (the widget's own dialog) |
| Reason sent → approval form in the other HR's inbox | 49 s, and none at all when B25 hit | 0.5 s to save the row, 0.2 s more for the form |
| Approve → change written | 32 s | 55 s, in the background (11 to 20 s in every run since, §12.10) |
| Runs per change | 2 | 1 |

The approve step still writes two end dates and two new rows in NetSuite, and the platform
reads each written row back with every relation populated (R25), so its time depends mostly
on how fast NetSuite answers. In this run one end date took 15 s, 14 s of it in that read;
in later runs that read took 1 to 3 s (§12.10). Before approval the requester's browser now
makes about six NetSuite reads in all.

An approve step that takes longer than about 25 s, like this one, also shows
`Request timed out.` and `EOVERTIME` developer errors in the process_manager log, because
the inbox answer waits for `process_manager.run` only about 25 s while the run goes on
(PE22). The run itself completes.

---

## 11. Who can see what (HR Generalists)

Moved here on 2026-10-04 from the page now called site-administration.md, where the
tenant-wide role and scope list stays
([site-administration.md §3](core/site-administration.md#3-users-roles-and-scopes-here)). How a
scope works is in [server-platform.md](core/server-platform.md) (`includeScopes`): the
rules of every scope of the user's roles are added to each read on the listed objects. Each
rule's `key` is a field id; a rule whose key is not a field of the object being read is
dropped without a warning (tested 2026-10-02,
[site-administration.md §3.1](core/site-administration.md#31-what-a-scope-does-tested-on-2026-10-02)).

The role **HR Generalists** (`39ae03d7`) has one scope, **Netsuite Entity**
(`387dba7d-…`):

| Objects | Rule |
|---|---|
| entity, employee, NS Entity, Team, Team Responsibility | Their entity column must be `in_query_field` of the query "entity and employee" |
| `cache-principal-change` (since 2026-10-03) | `entity_id` **or** `other_entity_id` `in_query_field` the same query: an HR user sees the requests where their entity is either side (tested as hr.mock.pxr and hr.mock.pxy, §12.3) |
| Team Assignment, NS Employee Record, Team Strategy, the strategy lists, Role Type, Responsibility List | No rule matches them, so the scope gives **full read access** (S35, D6) |

**This is the HR row-level security.** The query "entity and employee" (base object: the
local `entity` table) keeps the `entity` rows whose `User` field is the current user
(`is_current_user`). So an HR Generalist sees only the NetSuite entities an admin has
linked to them in the local `entity` table, **for the objects that have a rule**. Team
Assignments and NetSuite employee records of every entity stay readable: checked on
2026-10-03 as hr.mock.pxr (linked to PXR only), who could read the PXY employee record and
its principal assignment (S35). The HR Teams chart's cross-entity check depends on that
([hrteams-widget.md §6.5](plugins/hrteams-widget.md#65-what-happens-on-drag-and-drop)).

What the scope does not cover:

- **Process runs** read without scopes ([processes.md §7](core/processes.md#7-traps) trap 35):
  a run started by hr.mock.pxr read the PXY subsidiary's name (D6).
- **Writes** are not scope-checked (S22): the chart deletes request rows by id.
- **`populate`** is not scope-filtered (S37): the chart reads the other entity's team and
  entity names through a Team Assignment it can read (§12.2).

Here the `entity` table had one row, "World Headquarters" (entity 1), linked to admin; test
rows were added for 1805 AEP (hr.mock.aep, 2026-10-02), 2715 PXY (hr.mock.pxy), 4925 PXR
(hr.mock.pxr, both 2026-10-03) and 5451 "CNI - NS Track" (hr.mock.cni, 2026-10-05). Each row
is named with the subsidiary's NetSuite `name`, as the test rows before it. As hr.mock.cni,
NS Entity and `entity` each returned only 5451, and the chart drew CNI's teams. The mock
users have no password and are used through switcheroo
([testing.md §3.1](testing.md#31-acting-as-another-user-switcheroo)).
Production fills the name from the subsidiary's `fullname` instead
(`../global-hr-update/back-end/api/netsuite.js`, `fetchEntities()`). Admin
also holds System Admin → All Access, so admin sees every entity anyway (the rules of all
scopes are ORed, [server-platform.md §9](core/server-platform.md#9-traps) trap 14). Global HR
Update fills `entity` from NetSuite and its HR users from import scripts and Celigo
(§13.2).

Scopes do apply to NetSuite-backed objects (seen for NS Entity on 2026-10-02). Inferred, not
tested: an HR user with no `entity` row sees no teams.

The role **Core Finance** (`e32dbd38`) has the scope **Finance**: entity, NS Entity, Team
Assignment, Team, Responsibility Centre, Role Type, Team Responsibility and Responsibility
List, with the same query on entity and NS Entity only. HR Generalists do not get
Responsibility Centres (D5).

Other local data here: `employee` has 2 rows, both `is_approval_pending` (the 2 waiting New
Submission runs, §5); `history` had 77 rows on 2026-10-03 (§9.1).

---

## 12. The cross-entity principal change (since 2026-10-03)

**In short.** A person (one email) has one principal team assignment at a time, across
all entities. When an HR user makes someone principal while that person is principal in
another entity, the other entity's HR must approve. The HR Teams chart now saves the
request as one row of a local object, `cache-principal-change`, and changes nothing in
NetSuite. The process "Principal Change Approval" sends the approval to the other
entity's HR and, on Approve, checks NetSuite again and moves the principal: it ends both
assignments and creates the new pair. The HR users get a notice of the outcome, and an
open chart updates by itself. A request that nobody answers expires after 7 days. Before
this rework the same change took about two minutes and over 110 NetSuite requests before
the approver even saw it; now the requester waits about 3 s, the approval arrives at once,
and an approved change takes about 10 to 20 s in the background, depending on how fast
NetSuite answers (§12.10).

Status: **built and tested in the local tenant on 2026-10-03, changed and retested on
2026-10-04** (§12.6); **requests expire after 7 days since 2026-10-04** (§12.9). The
definitions live only in the local `admin` tenant database, and the HR Teams code is
committed on branch `guy/enhancements` (`cc217ce`, 2026-10-16) but not on `master`; what is
left before production is in §12.8. Why
the old flow was slow is measured in §10. The widget side (dialog, data collection, live
updates) is also in
[hrteams-widget.md §3](plugins/hrteams-widget.md#3-the-change-to-principal-flow).

Codes in parentheses, such as PE20, S37, W23 or B25, are entries in
[known-issues.md](known-issues.md). The test cases in §12.7 are numbered A1 to A10 and B1
to B17.

Design decisions (repo owner, 2026-10-03):

- The HR Teams plugin looks up, with NetSuite queries, the data the approval needs at the
  moment the HR user saves, and writes a copy of that joined data into **one local
  AppBuilder object** that works like a temporary cache. The process never dereferences
  NetSuite to build the request.
- New definitions in NetSuite HR Update are named with the prefix `cache-`. Reworking
  "Updated Assignments" is allowed.
- Plugin work goes on the HR Teams branch **`guy/enhancements`**.
- One pending change per person. Check NetSuite again before writing.
- The rule that needs approval uses the **org relation** (`custentity_ccc_org_relation`).
- Request rows are **deleted** once finished, so they take no space.
- Entity sync (`entity` and its HR users) is already handled well in production.
- 2026-10-04: the widget reads and writes the object through a **data collection**, so a
  second read or a reuse does not go back to the server (§12.3), and the process is named
  **"Principal Change Approval"**, because HR users see that name in the inbox (§12.4).
- 2026-10-04: a request **expires after 7 days**. Once it has, the approval window says
  so (a red line, Approve and Reject hidden, only Close), an answer changes nothing, and
  the HR who asked can send a new one (§12.9).

### 12.1 Who needs approval (unchanged)

Only where the work is done changed; the rules in `libs/CustomProcessTasks.js` `run()`
did not:

| Situation | Result |
|---|---|
| The team is External Support, or this person's record here is "Sent" (`custentity_ccc_org_relation` = 2) | Never principal |
| No record of the person (same email) in another entity, or records but no current principal there | Principal at once; a principal already in this entity is ended and copied as non-principal |
| A current principal in another entity, and the person's record **there** is "Sent" | The widget ends that principal at once and copies it there as non-principal; this one becomes principal; no approval |
| A current principal in another entity, and the record there is not "Sent" (Home, Received or empty) | **Needs approval** by the other entity's HR (§12.2) |

The table is for ticking Is Principal on an assignment (`run({ isChanging: true })`). A new
assignment, made by dropping a person onto a team (`run()`), follows the same rules with two
differences: it does not take the principal from another assignment in this entity, and
where the table says "Needs approval" it is saved as non-principal and no request is made.

If the person is principal in more than one other entity (bad data), the request names the
first one, as "Updated Assignments" used to.

### 12.2 The flow

1. The HR user ticks "Is Principal" in the edit form and saves. `run()` decides as in §12.1
   (about 2.7 s until the next step in the test).
2. When approval is needed, the widget (`_requestPrincipalChange()`):
   1. looks for a `pending` row with the same `employee_email` in its data collection
      (§12.3), without asking the server; if there is one that has not expired it says who
      asked, when, and when the request expires, and stops ("Already waiting for
      approval"); expired ones it deletes (§12.9);
   2. opens its own dialog, "Principal change needs approval", which names the other
      entity and asks for a **reason** (required). Other changes made in the same form wait
      with the request;
   3. meanwhile reads the other principal assignment once with
      `populate: [team, entity]` to get the other team's and entity's names, which the HR
      scope otherwise hides (S37);
   4. creates **one row** in `cache-principal-change` through that data collection, with
      status `pending` and `expires_on` 7 days ahead, and says the other entity's HR will
      get it in their inbox and when it expires.
      **NetSuite is not changed.** The old `"1"`-then-`"0"` saves, their two "Updated
      Assignments" runs and the hidden reason Form are gone.
3. The row starts the process **"Principal Change Approval"** (lifecycle trigger,
   "added"). The approval form reached the other HR's inbox **0.2 s** after the row was
   saved.
4. On **approve** of a request that has not expired (the gateway "Has the Request
   Expired?" comes first, §12.9), the process checks NetSuite again: the other assignment
   must still be principal and current, and this assignment must still be current. Then it
   ends both
   today, creates a non-principal copy of the other one there and a principal copy of this
   one here (with the values from the row, so other edits from the form are applied too),
   sets the row to `applied` and sends "Principal Change Applied" to both HR groups. If a
   check fails it sets `failed` and sends "Principal Change Not Applied", changing nothing.
5. On **reject**, it sets `rejected` and sends "Principal Change Rejected" to this entity's
   HR. NetSuite is untouched. Any answer to an **expired** request, Close or Approve, sets
   `expired` and sends "Principal Change Expired" to this entity's HR instead, also
   without touching NetSuite (§12.9).
6. The process engine cannot delete rows (PE20), so **the widget deletes** finished rows
   (`status` not `pending`) and expired ones, in two ways:
   - **live:** the server sends a row's changes to every browser that loaded or created
     it. When the process sets the status while a chart that holds the row is open,
     `_onPrincipalChangeUpdate()` deletes the row at once, shows the requester a short
     message ("Approved: … is now principal in …", "Rejected by the HR of …", or "Not
     applied: …"), and for an applied change that touches the entity on screen reloads
     the assignments and redraws the chart once nothing is open or loading
     (`_refreshWhenIdle()`);
   - **on load:** each refresh deletes the finished rows the data collection holds
     (`_removeFinishedPrincipalChanges()`), for requests that finished while no chart
     had them open. The HR scope shows a row to the HR of either entity, so whichever
     side opens the chart first cleans it up.

### 12.3 The object `cache-principal-change`

`cache-principal-change` (`044cda33-b858-47d0-851b-a106f149a15f`), table
`AB_NetSuiteHRUpdate_cacheprincipalchange`, in NetSuite HR Update. Plain fields only, no
connect fields, so nothing is dereferenced and `SITE_USER` gets no new relation (known
issue B22).
Ids are text. Free-text values are `LongText`, so a long NetSuite value cannot overflow.

| Group | Fields |
|---|---|
| Request | `status` (`pending`, `applied`, `rejected`, `failed`, `expired`), `reason`, `requested_by` (email), `expires_on` (date: the last UTC day the request is valid; since 2026-10-04) |
| This side | `assignment_id`, `employee_id`, `employee_email`, `employee_firstname`, `employee_lastname`, `entity_id`, `entity_name`, `team_id`, `team_name`, `role_type_id`, `job_title`, `job_description` |
| The principal now in the other entity | `other_assignment_id`, `other_employee_id`, `other_entity_id`, `other_entity_name`, `other_team_id`, `other_team_name`, `other_role_type_id`, `other_job_title`, `other_job_description` |

**The widget's data collection.** `DcContainer.init()` makes a runtime data collection
for the object (`createCustomDCByObjID(CACHE_PRINCIPAL_CHANGE_OBJECT_ID, {loadAll:
true})`, `DcContainer.list.principalChange`), like the widget's other data collections; it
is not saved as a definition. It is loaded once when the chart starts and not linked to
the entity, since a request belongs to two entities. The duplicate check, the create and
the cleanup all use it, so after that first load the chart asks the server about requests
only to create or delete one. Two limits, both checked in the code
(`appbuilder/utils/broadcast.js`, api_sails `api/lib/broadcastManager.js`): the server
sends changes to a room per **row** (`{tenant}-{row id}`), so rows that **others** create
after the chart loaded do not reach it; and a duplicate request that slips through that
gap is harmless, because the process re-checks NetSuite before it writes anything: if both
requests are approved, the second finds the principal already moved and ends as "Not
Applied".

The object id is hard-coded (`CACHE_PRINCIPAL_CHANGE_OBJECT_ID` in
`components/constants.js`), like the widget's other ids, so a production import must keep
it. If the object is missing, the chart still works and a change that needs approval says
"The object cache-principal-change is missing in this tenant."

**Scope.** The object is in the HR Generalists scope "Netsuite Entity"
(`387dba7d-…`) with two rules, `entity_id` and `other_entity_id` `in_query_field` the
query "entity and employee" (the entities of the current user), so an HR user sees the
rows where their entity is either side, and nothing else (tested as both mock users, §11).
The scope's own glue is "and", but the server takes only the rules that point at this
object's fields and joins them with "or" (`AppBuilder/platform/ABObject.js:394-399`), which
is why either side is enough.
Writes are not scope-checked (S22). The scope row is data, not a definition: an app import
does not carry it. The scope row before the change is saved in
[backups/definitions/netsuite-entity-scope-2026-10-03.json](../backups/definitions/netsuite-entity-scope-2026-10-03.json).

### 12.4 The process "Principal Change Approval"

`0d8b7f1a-b561-407d-a768-29f955ea387a`, 22 elements (19 until the expiry was added on
2026-10-04), built from the browser console (recipe
in [processes.md §6.1](core/processes.md#61-building-or-changing-a-process-from-the-browser-console)). First named
"cache-principal-change approval"; renamed on 2026-10-04 at the owner's request, because
the inbox shows the process **label** as the heading of its forms
(`platform_web/ui/portal_work_inbox.js:257`). The trigger is tied to the object's id, and
forms already in an inbox show the new name, since the inbox reads the label when it draws
them.

| Element | Does |
|---|---|
| Principal Change Requested | trigger: `cache-principal-change` added |
| Get HR Users in the Other Entity / in this Entity | local `entity` where `entity_id` **equals** the row's id → `User` (single value, so known issue B25 cannot happen) |
| Approve a Principal Team Assignment Change | Approval to the other entity's HR: request, person, "Principal from now on" and "Principal now" from the row; Approve / Reject. Since 2026-10-04 also "Please answer by <date> (UTC)", and once that date has passed a red line and only a Close button (§12.9) |
| Has the Request Expired? | `expires_on` before today (UTC): Yes; empty, today or later: No (§12.9) |
| Is Approved? | on the approval's response: Yes for Approve, No for anything else (Reject, or Close) |
| Check the Other Principal Is Still Current | Team Assignment `id` = `other_assignment_id`, principal, end empty or later than today |
| Check this Assignment Is Still Current | Team Assignment `id` = `assignment_id`, end empty or later than today |
| Are Both Still Current? | both values found (Yes) or not (No) |
| End the Principal Assignment in the Other Entity / End this Assignment | end date = today |
| Create the Non-Principal Copy in the Other Entity | other side's values from the row, begin today, principal 0 |
| Create the Principal Copy in this Entity | this side's values from the row, begin today, principal 1 |
| Mark the Request Applied / Failed / Rejected / Expired | the row's `status` |
| Principal Change Applied / Not Applied / Rejected / Expired | Approval tasks used as inbox notices with a Close button, like the app's other notices. Rejected and Expired go to this entity's HR, the others to both |

What a builder must know before editing it:

- **The two checks save their value under a task parameter named after the Team Assignment
  field id** (`079f04c9-…` for Is Principal, `99c2b2ec-…` for Internal ID). A gateway can
  only read a query task's output when the parameter name ends with the field's id
  (PE21, [processes.md §7](core/processes.md#7-traps) trap 36, proven in
  [processes.md §7.1](core/processes.md#71-proof-for-trap-36-pe21-2026-10-04)).
  Renaming the parameter to something readable breaks "Are Both Still Current?" without
  any error: it would always answer No, and every approved request would end as "Principal
  Change Not Applied".
- The designer shows 6 issues (5 before the expiry), "requires at least one Save
  operation", on the update-only query tasks. "Updated Assignments" has the same kind; they do no harm.
- Dates come from `ab-current-date`, which the server turns into its own (UTC) date, so
  before 07:00 in Thailand the date is yesterday's (W23, as before).

### 12.5 Test on 2026-10-03 (NetSuite sandbox 3)

Same person as in §8 (3126713 in PXY, 2286202 in PXR), HR users hr.mock.pxy and
hr.mock.pxr, done in the real UI except where noted.

| Step | Result |
|---|---|
| Setup through the model: PXY principal **57405**, PXR member **57505** | 11 s and 7 s per create |
| hr.mock.pxr: edit 57505, tick Is Principal, Save | Reason dialog after 2.7 s; "PXY" filled in at 4.4 s; an empty reason is refused |
| Send | Row saved and "Sent for approval" in 0.5 s; approval form in hr.mock.pxy's inbox 0.2 s after the row. No "Updated Assignments" run |
| hr.mock.pxy approves in the inbox | Both checks Yes; 57405 and 57505 end today; **57605** (PXY, principal 0) and **57406** (PXR, principal 1, job title kept) start today; row `applied`; notice to both. **55 s** in the background |
| hr.mock.pxy opens the chart | The `applied` row is deleted |
| hr.mock.pxy: make 57605 principal, Send | Row pending, approval to hr.mock.pxr |
| hr.mock.pxy: try again | "Already waiting for approval", no dialog |
| hr.mock.pxr rejects | Row `rejected`; "Principal Change Rejected" to hr.mock.pxy; NetSuite unchanged |
| hr.mock.pxy opens the chart | The `rejected` row is deleted |
| Console rows with assignment ids `0`, approved | "Are Both Still Current?" → No, row `failed`, "Principal Change Not Applied" to both |
| "Updated Assignments", three cases | Principal edited, not ended → "Notify of an Edited Assignment"; principal ended → "Notify of an End Principal Assignment"; non-principal ended → "Notify of an Edited Assignment" |

Before, the same change took about two minutes and over 110 NetSuite requests before the
approver even saw it. Now the requester waits about 3 s, the approver gets the form at once,
and the approved change runs in the background. This first run took 55 s, the slowest
measured: one end date took 15 s, 14 s of it the platform re-reading the written row with
every relation populated (R25), and the two new rows about 34 s. Every run since took 11 to
20 s (§12.10).

Left in place: assignments 57405, 57406, 57505 and 57605, all ended on 2026-10-03, so the
person is "Unplaced" in both entities again. Every notice was closed and every run
completed. The cache table is empty.

### 12.6 Retest on 2026-10-04 (data collection, new name)

After the widget moved to its own data collection and the process was renamed. Run just
after midnight in Thailand, so assignments were dated 2026-10-03, the server's (UTC) date.

| Step | Result |
|---|---|
| Setup: PXY principal **57705**, PXR member **57805** | |
| hr.mock.pxr, chart open: edit 57805, Is Principal, Save | "Caution: Creating New Assignment" first (the assignment was over a day old), then the reason dialog; "PXY" filled in after 1.9 s |
| Server log while saving | One request for the object when the chart loaded, then only the create: the duplicate check asked the server nothing |
| Try again on the same card | "Already waiting for approval", from the data collection |
| hr.mock.pxy approves | About 13 s this time. On hr.mock.pxr's open chart: "Approved: … is now principal in PXR." and the row deleted at once. 57706 (PXY, 0) and 57707 (PXR, 1) |
| The chart after that approval | **Did not** show 57707: the reload the chart started itself when 57805's end date arrived ran before the new rows existed, and `refresh()` only redraws. Fixed with `_refreshWhenIdle()`, which reloads the assignments first |
| hr.mock.pxy asks, hr.mock.pxr rejects with no chart open | The row stays `rejected`; deleted when hr.mock.pxy next opened the chart |
| hr.mock.pxr asks again (57708), hr.mock.pxy approves, hr.mock.pxr's chart open | Message at once, then the chart showed the new principal **57711** by itself, 12 s after the approval |
| Inbox meta for the process | Label "Principal Change Approval" |

Left in place: assignments 57705 to 57711 and 57805, all ended on 2026-10-03. Every
notice closed, every run completed, cache table empty.

### 12.7 Full test plan

Written on 2026-10-04 for a manual run of the whole feature. Part A checks that the rest of
the chart behaves as before; part B covers the approval case. "Tested" marks what was run
on 2026-10-03/04 (§12.5, §12.6).

#### 12.7.1 What changed, and what did not

Changed:

1. **The approval case** (a principal in another entity, and the person's record there is
   not "Sent"): the whole of part B.
2. **Saving a principal assignment that is not ended now sends "Notify of an Edited
   Assignment"** to this entity's HR, on every path that does it: first principal,
   same-entity swap, the "Sent" case, editing another field of a principal assignment,
   moving it within its first day. Before, those runs went into the cross-entity part,
   stopped at the reason Form the widget hid, and waited for good with no notice (PE11).
   Seen working on 2026-10-03.

Not changed: who gets principal (`run()`'s rules, §12.1), what the chart writes in every
other case (drag, move, Change Supervisor, end, the same-entity swap, the "Sent" case),
the end notices, the notices for non-principal edits, teams, Responsibility Centres,
responsibilities, and the `history` bookkeeping.

Small: every chart load reads the request table once (one small local query), and charts
delete finished requests.

#### 12.7.2 Setup

- Stack up; the browser must load the new plugin: hard refresh, or run
  `fetch("/assets/tenant/default/HRTeams.js?v=ecs", {cache: "reload"})` on the site first
  ([hrteams-widget.md §1.1](plugins/hrteams-widget.md#11-the-cache-busting-trap)).
- Two HR users, each linked to one entity in the local `entity` table: here hr.mock.pxy
  (PXY 2715) and hr.mock.pxr (PXR 4925); a third, hr.mock.cni (CNI 5451), for B12. Switch
  between them as admin with switcheroo
  ([testing.md §3.1](testing.md#31-acting-as-another-user-switcheroo)), or log in as real
  HR test users.
- A test person with active employee records in both entities under one email, org
  relation not "Sent" on either side: here 3126713 (PXY) and 2286202 (PXR), "Unplaced" in
  both after the tests.
- Test after 07:00 Thailand time: before that the server's "today" is still yesterday, so
  begin and end dates come out a day early (W23).
- Two browser sessions, one per HR user (§12.7.6), so that switching users cannot undo
  itself (R27).
- Where to look, read-only:

  ```bash
  q() { npx env-cmd docker compose exec -T db sh -c "mysql -uroot -p\"\$MYSQL_ROOT_PASSWORD\" -e \"$1\" appbuilder-admin"; }
  q "SELECT uuid, status, assignment_id, other_assignment_id, created_at FROM AB_NetSuiteHRUpdate_cacheprincipalchange"
  q "SELECT uuid, status, created_at FROM SITE_PROCESS_INSTANCE WHERE processID='0d8b7f1a-b561-407d-a768-29f955ea387a' ORDER BY created_at DESC LIMIT 5"
  q "SELECT f.name, f.status, j.USER FROM SITE_PROCESS_FORM f JOIN AB_JOINMN_ProcessForm_USER_users j ON j.ProcessForm=f.uuid WHERE f.status='pending'"
  ```

  A run's steps are in `SITE_PROCESS_INSTANCE.log`; the NetSuite rows can be read from the
  browser console with the Team Assignment model.

#### 12.7.3 Part A: the rest of the chart

| # | Do | Expect |
|---|---|---|
| A1 | Drag the person from the data panel onto a team, as Member | Assignment created; principal if they have none anywhere. "New Assignments" runs and does nothing |
| A2 | Edit a field of a non-principal assignment | Saved; "Notify of an Edited Assignment" to this entity's HR |
| A3 | Edit a field of a principal assignment that is not ended | Saved; "Notify of an Edited Assignment" (**changed**, §12.7.1). Tested |
| A4 | Person principal in team T1 of this entity: tick Is Principal on their T2 assignment | Warning "already has a principal assignment in this entity", then T1 ends and gets a non-principal copy, T2 becomes principal; no approval |
| A5 | Person with no record in another entity: tick Is Principal | Principal at once |
| A6 | Other entity holds the principal and the person's record **there** is "Sent" | No approval: the chart ends that principal itself and makes this one principal. Not tested: needs such a person; changing an employee's org relation is outside what tests may write |
| A7 | The person's record **here** is "Sent", or the team is External Support | Principal is never set |
| A8 | End a principal assignment (the form needs a start date before today, W25) | "Notify of an End Principal Assignment" to this entity's HR. Tested |
| A9 | End a non-principal assignment | "Notify of an Edited Assignment". Tested |
| A10 | Drag a member to another team; Change Supervisor dialog | As before ([hrteams-widget.md §6.5](plugins/hrteams-widget.md#65-what-happens-on-drag-and-drop)) |

#### 12.7.4 Part B: the approval case

Start: the person is principal in PXY and has a non-principal assignment in PXR.

| # | Do (as) | Expect |
|---|---|---|
| B1 | Edit the PXR assignment, tick Is Principal, Save (PXR HR) | "Caution: Creating New Assignment" first if the assignment is over a day old; then "Principal change needs approval", naming PXY within a few seconds. NetSuite unchanged. Tested |
| B2 | Send with no reason | Refused, "Please enter a reason". Tested |
| B3 | Cancel instead | Dialog closes; no request, no NetSuite change, card unchanged |
| B4 | Type a reason, Send | "Sent for approval"; one `pending` row; "Approve a Principal Team Assignment Change" in PXY HR's inbox under "Principal Change Approval"; no "Updated Assignments" run. Tested |
| B5 | Try again for the same person | "Already waiting for approval", with who asked, when, and when it expires; no dialog. Tested |
| B6 | Open the inbox form (PXY HR) | Request (asked by, reason), person, "Principal from now on" (PXR entity, team, job title), "Principal now" (PXY entity, team, job title). Tested |
| B7 | Approve | In about 10 to 20 s (§12.10): the PXY principal and the PXR assignment end today; a non-principal copy in PXY and a principal copy in PXR start today; row `applied`; "Principal Change Applied" to both HR groups. PXR HR's open chart shows "Approved: … is now principal in PXR.", redraws with the new principal and deletes the row. Tested; again on 2026-10-04 after the expiry was added (§12.9) |
| B8 | Reject instead | "Principal Change Rejected" to PXR HR; NetSuite unchanged; row `rejected`, deleted by the next chart that holds it. Tested |
| B9 | While B4's request waits, end the PXY principal (or the PXR assignment); then approve | "Are Both Still Current?" No; row `failed`; "Principal Change Not Applied" to both; nothing written. Only tested with made-up ids |
| B10 | In B1, also change the job title | On approval the new PXR principal has the new title; on rejection nothing changes |
| B11 | Answer while no chart is open | The row keeps its final status until a chart of either entity loads, which deletes it. Tested |
| B12 | Optional: as the HR of a third entity, read the request table | Sees nothing (scope). Not tested; a third HR user exists since 2026-10-05: hr.mock.cni (CNI 5451) |
| B13 | Optional: a person with records in three entities | Only the HR of the entity that holds the principal is asked (before: known issues B25, PE14). Not tested: needs such a person |
| B14 | An expired request: make one through the model with a past `expires_on` (the widget always sets 7 days ahead; changing the row later does not change the copy the process and the form keep) | The other HR's window shows the red line and only Close. Tested 2026-10-04 |
| B15 | Close it, or answer Approve through `PUT /process/inbox/<id>` | `expired`; "Principal Change Expired" to this entity's HR; NetSuite unchanged. Tested |
| B16 | With an expired request pending for the person, try again | No "Already waiting": the reason dialog opens and the expired row is deleted. Tested |
| B17 | Open a chart of either entity while an expired request is pending | The chart deletes the row. Tested |

#### 12.7.5 Afterwards

End the test assignments with a `"YYYY-MM-DD"` end date (through the model if they started
today, W25), close the notices the runs left, and check that the request table is empty and
no form is pending (§12.7.2 queries).

#### 12.7.6 Doing it by hand

- **Use two separate browser sessions**, for example a normal window for the HR who asks
  (hr.mock.pxr) and a private window for the HR who approves (hr.mock.pxy), each logged
  in as admin and switched to its mock user. Switching one session back and forth while a
  chart is open in another tab can be undone by that tab (R27).
- Put the test person in the teams with the chart itself: "Staff Assignment" → drag the
  person from Unplaced onto a team's Member section; for the PXY principal, double-click
  the card, tick Is Principal and Save (no approval is needed while there is no principal
  in another entity).
- The expiry cases (B14 to B17) need a request whose `expires_on` has passed. Console
  helpers, checked on 2026-10-04 (run them on any page of the site, in the session named):

  ```js
  const CACHE = "044cda33-b858-47d0-851b-a106f149a15f";
  // List the pending requests this user can see (any session).
  const pending = encodeURIComponent(JSON.stringify({ glue: "and",
     rules: [{ key: "status", rule: "equals", value: "pending" }] }));
  (await fetch(`/app_builder/model/${CACHE}?where=${pending}&skipPack=true`).then((r) => r.json()))
     .data.data.map((x) => `${x.uuid} ${x.status} ${x.employee_email} ${String(x.expires_on).slice(0, 10)}`);

  // B14: a request that expired already (asking side, in the portal; no NetSuite step runs for it).
  await AB.objectByID(CACHE).model().create({
     status: "pending", reason: "Manual expiry test", requested_by: "manual.test@example.invalid",
     employee_email: "expiry.manual@example.invalid", employee_firstname: "Expiry",
     employee_lastname: "Manual", entity_id: "4925", entity_name: "PXR",
     other_entity_id: "2715", other_entity_name: "PXY", assignment_id: "0",
     other_assignment_id: "0", expires_on: "2026-09-30",
  });

  // B16: let a real request expire now (asking side; uuid from the list above).
  await fetch(`/app_builder/model/${CACHE}/<uuid>`, { method: "PUT",
     headers: { "Content-Type": "application/json" },
     body: JSON.stringify({ expires_on: "2026-09-30" }) }).then((r) => r.status);

  // B15 through the API: answer Approve without the window (approving side).
  const f = (await fetch("/process/inbox").then((r) => r.json())).data.find((x) =>
     x.name == "Approve a Principal Team Assignment Change" &&
     JSON.stringify(x.data).includes("Manual expiry test"));
  await fetch(`/process/inbox/${f.uuid}`, { method: "PUT",
     headers: { "Content-Type": "application/json" },
     body: JSON.stringify({ response: "approve" }) }).then((r) => r.status);
  ```

  A request expired by hand (B16) keeps its old date in the approval window and in the
  process, which copied the row when it started; reject that window afterwards, or an
  Approve would still apply it.
- Any chart load deletes expired requests (B17), so after B14 the list may already be
  empty; the approval form stays in the other HR's inbox all the same.

### 12.8 Before this reaches production

1. Commit the HR Teams changes on `guy/enhancements` (six files; `components/utils.js` and
   `components/data_panel/rcDataPanel.js` carry the 2026-10-05 fix for the stuck "Please
   wait" card, known issue W27) and release the plugin, with the owner's go-ahead.
2. Move the definitions: the object, its 25 fields (`expires_on` since 2026-10-04) and the
   process (new, 22 elements), and "Updated
   Assignments" (changed, 24 elements deleted). How definitions reach production is not
   documented here yet (an exported app JSON, as `appbuilder_global_hr_update.json` in
   Global HR Update suggests?). The object id must stay `044cda33-…`.
3. Add the object and its two rules to the "Netsuite Entity" scope in Site Administration
   (§12.3, §11); an import does not do it.
4. Release the plugin and the definitions together: the new plugin no longer hides the old
   reason Form, and the old process still raises it.
5. Finish or cancel any pending "Ask Other Entity HR to Approve" form first; its element no
   longer exists after the rework, so answering it would fail.
6. A row stays `pending` if its run fails half way (for example a NetSuite error during the
   writes), if nobody ever answers, or if nobody receives the approval. The approval goes
   to the HR users linked to the other entity's row in the local `entity` table (one row
   per entity, `entity_id` unique; the users in `AB_JOINMN_entity_USER_User`). With no row
   or no linked user the form is created for nobody, without a warning, and the run waits
   forever (PE23). Here only 5 entities have a row (1, 1805, 2715, 4925, 5451), with one
   HR user each. A pending row blocked new requests for the person until an admin deleted it (D9);
   since 2026-10-04 it blocks them for 7 days at most and then expires (§12.9). The run
   itself still waits, and the process has no error branch to clean up after itself.

### 12.9 Expiry after 7 days (since 2026-10-04)

Asked for by the owner on 2026-10-04: a request that nobody answers (for example because
nobody received it, PE23) must not block the person for good, and an answer that comes too
late must change nothing. Built and tested the same day; the widget part is in `cc217ce`
on HR Teams `guy/enhancements` (C9), the definitions only in the local tenant (C10). The definitions before the change are in
[backups/definitions/principal-change-approval-2026-10-04.json](../backups/definitions/principal-change-approval-2026-10-04.json)
and [backups/definitions/cache-principal-change-2026-10-04.json](../backups/definitions/cache-principal-change-2026-10-04.json).

**How it works**

- **The date.** The widget writes `expires_on` = today + 7 days when it creates a request.
  Days are UTC days, the days the server's gateway counts in: a request sent on 2026-10-04
  at 06:10 in Thailand (still 2026-10-03 in UTC) is valid through 2026-10-10 and expires
  when 2026-10-11 begins in UTC, at 07:00 in Thailand. The 7 is
  `PRINCIPAL_CHANGE_EXPIRY_DAYS` in `ABViewOrgChartTeamsComponent.js`; the form and the
  process only compare `expires_on` with today, so a different period is a change in the
  widget alone.
- **The approval window** reads `expires_on` from its form data. Until the date has passed
  it shows "Please answer by <date> (UTC)" with Approve and Reject. After that it shows a
  red line, "This request expired on <date> (UTC). Approving it now changes nothing. Close
  it; the HR who asked can send a new request.", and only a **Close** button (response
  `close`). This is Form.io logic stored in the form definition (`customConditional` on the
  lines and buttons, `{{ }}` for the date), worked out each time the window is drawn; the
  date itself sits in a hidden textfield, which keeps it in the form data.
- **The process decides**, whatever was answered: right after the approval, the gateway
  "Has the Request Expired?" sends an expired request to "Mark the Request Expired"
  (status `expired`) and "Principal Change Expired" (a notice to this entity's HR), and
  ends; NetSuite is not touched. Only a request that has not expired goes on to "Is
  Approved?", whose No branch now takes anything that is not `approve`. The window alone
  would not be enough: anyone logged in can send an answer through the API
  ([processes.md §7](core/processes.md#7-traps) trap 25).
- **The widget**: the duplicate check skips expired requests and deletes them, so a new one
  can be sent at once; "Already waiting for approval" says when the request expires; every
  chart load deletes expired rows along with the finished ones; a live `expired` status
  shows the requester "Expired: … You can send the request again." A row without
  `expires_on` (only rows from before the change could lack it; none exist) counts from
  `created_at` in the widget, and as not expired in the process.
- **Not changed:** the run of an expired request still waits at its approval until
  someone answers, and a form that nobody received stays in the database (PE23). Nothing
  can withdraw a form from an inbox, and a timer process cannot expire requests (known issues
  B4, B12).

**Tested on 2026-10-04**, first in the sandbox
([processes.md §7.2](core/processes.md#72-expiry-checks-in-an-approval-tested-in-the-sandbox-2026-10-04)),
then here as hr.mock.pxr and hr.mock.pxy, between 06:00 and 06:40 in Thailand (UTC date
2026-10-03):

| Test | Result |
|---|---|
| Two requests made through the model with `expires_on` 2026-09-30; their window as hr.mock.pxy | Red line "This request expired on 2026-09-30 (UTC)", only Close |
| Close on one; Approve through `PUT /process/inbox/<id>` on the other | Both: "Has the Request Expired?" Yes, "Mark the Request Expired", "Principal Change Expired" to hr.mock.pxr. No NetSuite step ran |
| hr.mock.pxy's chart loaded while those two were pending | It deleted both rows; the runs' "Mark the Request Expired" then found no row and went on ([processes.md §7](core/processes.md#7-traps) trap 41) |
| Setup: PXY principal 57905, PXR member 57906 (Jae Choen Sim), through the model | |
| hr.mock.pxr: Is Principal on 57906, Save, reason, Send | "Caution: Creating New Assignment", then the dialog; "Sent for approval … If they have not approved it by 10/10/2026 (UTC), the request expires and you can send it again."; the row has `expires_on` 2026-10-10 |
| The same again | "Already waiting for approval … It expires after 10/10/2026 (UTC); then a new one can be sent." |
| `expires_on` set to 2026-09-30 by hand (`PUT /app_builder/model/…`), the same again | Not blocked: the reason dialog opened (cancelled), and the old row was deleted |
| That first request's window as hr.mock.pxy | "Please answer by 2026-10-10 (UTC)", Approve and Reject: the form and the process keep the values the row had when it was created |
| Reject | "Has the Request Expired?" No, "Is Approved?" No, "Mark the Request Rejected" (the row was already gone), "Principal Change Rejected" |
| Cleanup | 57905 and 57906 ended on 2026-10-03; the test's notices closed; request table empty |

**Approve after the change**, tested the same day at 07:20 in Thailand (UTC date
2026-10-04), at the owner's request:

| Step | Result |
|---|---|
| Setup through the model: PXY principal 58005, PXR member 58105, both from 2026-10-04 | |
| hr.mock.pxr: Is Principal on 58105, Save, reason, Send | No "Caution" this time (the assignment was from today); "Sent for approval … by 10/11/2026 (UTC)"; the row has `expires_on` 2026-10-11 |
| hr.mock.pxy opens the window | "Please answer by 2026-10-11 (UTC)", Approve and Reject |
| Approve | "Has the Request Expired?" No, "Is Approved?" Yes, both checks Yes; 58005 and 58105 ended on 2026-10-04; 58006 (PXY, principal 0) and 58007 (PXR, principal 1) start on 2026-10-04; row `applied`; "Principal Change Applied" to both HR groups 12 s after the answer. hr.mock.pxr's open chart showed "Approved: Jae Choen Sim is now principal in PXR." and deleted the row |
| hr.mock.pxr's chart, redrawing after that | First blank, with "Warning: No Team". A test artifact: a hr.mock.pxy chart still loading in a second tab had undone the switch back to hr.mock.pxr, so the redraw read PXR as hr.mock.pxy, who cannot see it (R27). After closing that tab and switching again, the chart showed 58007 as the principal |
| Cleanup | 58006 and 58007 ended on 2026-10-04; the notices closed; request table empty |

Not tested: the live "Expired:" message (it needs a late answer while the requester's chart
holds the row).

### 12.10 How long an approved change takes

From the approval answer to the row's `applied`, an approved change takes about 10 to 20 s
in the background. It ends two assignments and creates two new rows in NetSuite, and the
platform reads each written row back with every relation populated (R25). Only the first
run took longer:

| Run (date and time in Thailand) | Time |
|---|---|
| First test, 2026-10-03 (§12.5) | 55 s |
| Two retests, 2026-10-04 (§12.6) | about 13 s, 12 s |
| Approve after the expiry change, 2026-10-04 (§12.9) | 12 s |
| Test, 2026-10-05 09:13 | 16 s |
| Test, 2026-10-05 09:27 | 11 s |
| Test, 2026-10-15 13:03 | 20 s |

The last three are the `response time` of process_manager jobs `MslZTkOXVS`,
`oc0CGB1qok` and `_MF7hS0Yqx`. Where the time went in the slowest and the latest run, from
the appbuilder and process_manager logs:

| Step | 2026-10-03 (55 s) | 2026-10-15 (20 s) |
|---|---|---|
| End the first assignment | 15 s, 14 s of it reading the row back | 7 s, 3 s of it reading the row back |
| End the second assignment | 3 s | 3 s |
| Create the two new rows | about 34 s | about 5 s |
| Everything else (checks, reads before each write) | about 3 s | about 5 s |

The NetSuite steps are the same in every run, so the time depends mostly on how fast
NetSuite answers. That is inference; what the logs show is that in the first run the read-back
queries of the first end date waited about 13 s for NetSuite's answers. A run longer than
about 25 s also logs `Request timed out.` and `EOVERTIME` developer errors, although it
completes (PE22); the 2026-10-15 run finished about 5 s under that limit.

---

## 13. Global HR Update, the sibling web app

Moved here from global-hr-update.md on 2026-10-04. **Global HR Update** ("HR Update", repo
folder `../global-hr-update`, package `cruhr`) is a separate Express + Framework7 web app,
**not** an AppBuilder app. Staff use it to review and update their own HR record in
NetSuite. Changes that need approval go through AppBuilder, where this app's processes and
HR Generalist inbox handle them (§4). This section covers only the meeting points; the
app's own guide is `../global-hr-update/AGENTS.md` (read 2026-10-02, branch
`guy/enhancements`, `f60487e`).

**Do not read `../global-hr-update/back-end/config`** (live credentials) or
`../global-hr-update/back-end/data` (cached personal data) (AGENTS.md §2.0). Its `npm test`
calls live NetSuite, AppBuilder and Okta; `npm run test:unit` and `npm run lint` are the
safe gates.

### 13.1 The two workflows

1. **Staff update.** Staff sign in with Okta; the app finds their NetSuite employee record(s)
   by email and shows a form. On submit, optional fields are written straight to NetSuite;
   approval-required fields are written as an **`employee` row in AppBuilder** (local object
   `AB_GlobalHRUpdate_employee`: `netsuite_id`, `data` JSON with the requested change,
   `entity_id`, `is_approval_pending`).
2. **HR Generalist approval.** Creating or updating that `employee` row starts the AppBuilder
   processes **New Submission** / **Updated Submission** (§4): mark pending,
   then an **External** task whose URL is the HR Update app's `/approve/<netsuite_id>`. The
   HR Generalist opens it from the AppBuilder inbox; the page loads in an iframe, reads the
   pending change from AppBuilder and the current values from NetSuite, and on approve writes
   to NetSuite and calls AppBuilder `POST /process/external` to close the task. There is no
   reject path.

### 13.2 What it shares with AppBuilder

| AppBuilder piece | Used by HR Update for |
|---|---|
| `employee` (local, `AB_GlobalHRUpdate_employee`) | Pending change submissions, through the AppBuilder model REST API (`/app_builder/model/<object id>`) |
| `entity` (local, `AB_GlobalHRUpdate_entity`) | A local copy of some NetSuite **subsidiary** (NS Entity) columns: `entity_id` = NetSuite subsidiary id, `Name`. Filled by `back-end/syncEntities.js` (NetSuite → AppBuilder, direct MySQL) |
| `entity.User` (M:N to `SITE_USER`, table `AB_JOINMN_entity_USER_User`, keyed by **username**) | Which HR Generalists cover which entity. Written by `importHrGeneralists*.js` (direct MySQL) and by `POST /api/hr-generalists` (pushed by Celigo) |
| Role **HR Generalists** (`39ae03d7-…`) | Gate for `/admin/*`; `req.session.adminPermissions` = the entity ids the user covers |
| `POST /process/external` | Closing the External approval task |
| Inbox (`SITE_PROCESS_FORM`) | `back-end/resolveInbox.js` clears stale AppBuilder inbox items (direct MySQL, cron) |

The same `entity` table drives AppBuilder's own row-level security: the scope **Netsuite
Entity** of the HR Generalists role keeps only rows whose entity is in the query "entity
and employee" (entity rows whose `User` is the current user) (§11). So assigning an HR
Generalist to an entity in HR Update also decides what that person sees in the HR Teams
chart.

The local tables keep their `AB_GlobalHRUpdate_*` names, the app's earlier name (§1.1).

### 13.3 Local development notes from its guide

- Port 8000 by default; with `NODE_ENV=development` Okta is skipped and `?email=…` picks the
  user (staff impersonation). The approval External task in this tenant points at
  `https://localhost:23803/approve/...`.
- In other environments the session cookie is `sameSite: none; secure`, so the form can be
  iframed inside AppBuilder; that needs HTTPS.
- Progress is pushed with Server-Sent Events on `/events`; long requests answer 202 and
  stream results.
