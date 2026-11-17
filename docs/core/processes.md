# Processes (BPMN)

How builder-designed BPMN processes are stored, started, executed, paused for people, and
resumed. The feature spans five repos:

| Repo | Role |
|---|---|
| `developer/appbuilder/AppBuilder/core` (`ABProcessCore.js`, `process/`) | Process and element definitions, graph helpers, data lookup |
| `developer/appbuilder/AppBuilder` (`platform/ABProcess.js`, `platform/process/`) | Server execution: instances, `do()` for every task |
| `developer/process_manager` | The engine service: triggers, timers, inbox/user forms, run/reset |
| `developer/appbuilder` | Fires lifecycle triggers after record writes |
| `developer/plugins/ABDesigner` + `developer/ab_platform_web` | Process editor (bpmn-js) and the user inbox / form popups |

Verified on 2026-10-02 against class_core `2ecde31`, platform_service `544b83a`,
process_manager `0790f1e`. Paths below are relative to the repo root; `core/tasks/` means
class_core's `process/tasks/` and `server/tasks/` means platform_service's
`platform/process/tasks/` (in a service: `AppBuilder/core/process/tasks/` and
`AppBuilder/platform/process/tasks/`). "Inferred" = reasoned
from code, not run.

---

## 1. Data model

### 1.1 Process definition

A process is one `appbuilder_definition` row of type `process`
(`ABProcessCore.toObj()`, `class_core/ABProcessCore.js:78-109`):

- `id`, `name`, translations;
- **`xmlDefinition`**: the BPMN 2.0 XML (drives "what runs next");
- `elementIDs`: ids of the element definition rows;
- **`connections`**: `{<flowDiagramID>: {id, type: "bpmn:SequenceFlow"|"bpmn:MessageFlow",
  from: <diagramID>, to: <diagramID>}}` (drives "what ran before" for data lookups, and
  gateway branches).

The graph is stored twice (XML and `connections`) and the two are used for different
things (trap 13). Each element is its own definition row
`{id, name, type, json:{id, name, type, processID, diagramID, laneDiagramID, key, ...settings}}`.

| Identifier | Meaning | Used for |
|---|---|---|
| `id` | definition row uuid | `elementIDs`, data keys of most tasks, API `taskID` |
| `diagramID` | BPMN element id in the XML (`StartEvent_1`, `Task_0zvsnjm`) | runtime state `context.taskState[diagramID]`, `startTaskID`, `errorTasks` |
| flow diagram id | id of a sequence flow | `connections` keys, gateway `conditions` keys |
| `laneDiagramID` | enclosing participant/lane | finding assignees |
| `key` | element class key (e.g. `Email`) | `ABProcessTaskManager.newTask` |
| `triggerKey` | signal a start event listens for | starting instances |

**Participants and lanes** (`process.participant`, `process.lane`) pick users by role,
account, or a user field (`useRole/role`, `useAccount/account`, `useField/userField`). They
have no runtime state.

### 1.2 Instance storage (tenant DB, system objects)

| Table | Holds |
|---|---|
| `SITE_PROCESS_INSTANCE` | `uuid`, `processID`, `definition` (FK to the frozen snapshot), `context`, `errorTasks`, `log` (TEXT), `status`, `triggeredBy` (FK SITE_USER.username), `instanceKey` (UNIQUE), `jobID` |
| `SITE_PROCESS_DEFINITION` | `uuid`, `hash` (UNIQUE), `definition` JSON: the XML converted with xml-js and hashed with object-hash, reused when identical. Each instance runs against its own snapshot |
| `SITE_PROCESS_FORM` | Inbox items: `status` (pending/processed), `ui` (form.io JSON), `data`, `response`, `responder`, `name`, `process` (**instance uuid**), `definition` (**ABProcess id**), `scopeQuery`; recipients in `AB_JOINMN_ProcessForm_ROLE_roles` / `_USER_users` |
| `SITE_PENDING_TRIGGER` | appbuilder's retry queue for failed `process_manager.trigger` calls |

Status values defined: `created, error, running, waiting, completed`. Code sets only
`created`, `completed`, `error`, and `running` (on reset); `waiting` is never set.

### 1.3 Context and process data

- `context = {input: <trigger data>, taskState: {}}`; the trigger sets
  `taskState[<diagramID>] = {status:"completed", triggered:true, data}` and `startTaskID`.
- `instanceNew` calls `initState` on every element (`{initialized:true,
  status:"initialized", ...}`); lifecycle-trigger input is shrunk with `populateMin`.
- Per-task state examples: Email `to/from/subject/message`; Approval/External
  `userFormID`, `userFormResponse`, `responder`; Gateway `chosenPath`; InsertRecord `data`;
  Query `[taskParam]`; Api `rawResponse`; GetResetPasswordUrl `url`.
- **Reading earlier outputs:** design time `processDataFields(curr)` lists
  `{key, label, field, object}` from every **upstream** element (reached by walking
  backwards through `connections`, not only the direct parent); run time
  `processData(curr, [instance, key])` asks each upstream element (one answer: value;
  several: array).

**Data key formats are inconsistent** (trap 14):

| Element | Key |
|---|---|
| TriggerLifecycle | `<diagramID>.<fieldID>`, `<diagramID>.uuid`, optional `.format` |
| Approval / External | `<diagramID>.userFormResponse` / `<id>.userFormResponse` |
| Form | the raw form.io component `key` |
| Query | `<id>.<taskParam>` |
| InsertRecord | `<id>.[PK]` |
| Calculate | `<id>.value` |
| Api | `<id>.rawResponse` |
| GetResetPasswordUrl | `<id>.url` |
| SubProcess | `<id>.uuid`, `<id>.<fieldID>`, `<id>.subProcess` |

---

## 2. Element inventory

Exactly **21 element classes**, registered by `defaults().key` in
`class_core/process/ABProcessTaskManager.js`. There is **no plugin path** for new elements.

| # | key | BPMN shape | What it does at runtime |
|---|---|---|---|
| 1 | `Trigger` | StartEvent + Signal | Starts an instance for `triggerKey`. No designer panel; nothing sends plain signal keys, so it never fires (inferred) |
| 2 | `TriggerLifecycle` | StartEvent + `ab:SignalLifecycle` | `triggerKey = <objectID>.<added|updated|deleted>`; exposes every field of the record + `uuid`; born completed |
| 3 | `TimerStartEvent` | StartEvent + `ab:SignalTriggerTimer` | `triggerKey = timer.<elementID>`; cron schedule from `repeatEvery` (daily/weekly/monthly), `repeatTime`, `repeatDaily`, `repeatWeekly`, `repeatMonthly`, `isEnabled` (§3.9) |
| 4 | `End` | EndEvent + Terminate | Marks completed; does **not** stop other branches |
| 5 | `GatewayExclusive` | ExclusiveGateway | Tests each outgoing flow's filter (`conditions[flowID].filterValue`) in order, takes the first match; no default branch; no match rejects `"no valid path found"` |
| 6 | `Email` | SendTask | Resolves to/from (next participant, role/user/user field, custom), renders `message` as EJS (`{%= %}` values from completed Query and GetResetPasswordUrl tasks, keyed by task name), calls `notification_email.email`. **Currently broken** by the notification_email config bug ([services.md §6](services.md#6-notification_email)) |
| 7 | `TaskService` | ServiceTask | Placeholder: `do()` always rejects |
| 8 | `SubProcess` | SubProcess | Loops over a list (`parameterId`), running a nested engine over its own XML per item |
| 9 | `TaskUser` | UserTask | Placeholder: `do()` always rejects |
| 10 | `TaskServiceQuery` | (switched from ServiceTask) | Runs an ABQL chain (`object`, `find`, `first`, `set_pluck`, `set_save`, `row_pluck`, `row_save`, `update`, `value_save`; see [domain-model.md §8](domain-model.md#8-process-query-language-ql)). `find` runs as `_system_` with **no scopes**; `update` goes through `appbuilder.model-update` with `fromProcessManager:true` (prevents trigger loops) |
| 11 | `InsertRecord` | (switched) | Inserts into `objectID` with per-field `set` modes (1 custom, 2 start record, 3 previous step, 4 formula via `eval`, 5 repeat item, 6 query-task keys); optional repeat per linked record. Writes directly through `model().create()` (no broadcast, no triggers) |
| 12 | `Calculate` | (switched) | `formulaText` with `{label}` placeholders; computed lazily, sanitized, `eval` |
| 13 | `Api` | (switched) | axios call with `<%= Secret: NAME %>` (per-definition secret store) and `<%= key %>` substitution; stores `rawResponse` |
| 14 | `GetResetPasswordUrl` | (switched) | `user_manager.user-password-reset-url` for an email data key; stores `url` |
| 15-18 | `AccountingBatchProcessing`, `AccountingFPClose`, `AccountingFPYearClose`, `AccountingJEArchive` | (switched) | Run the stored procedures `BALANCE_PROCESS`, `CLOSE_FP_PROCESS`, `CLOSE_FY_YEAR_PROCESS`, `JEARCHIVE_PROCESS` (created only in `appbuilder-admin`, see [database.md §4](database.md#4-accounting-stored-procedures-04-08)) |
| 19 | `Approval` | (switched from UserTask) | Creates an inbox form (`process_manager.userform.create`) for the lane or picked roles/users, returns false (waits); later passes poll `userform.status` and complete when processed |
| 20 | `External` | (switched) | Like Approval, plus an EJS `url` to an external system (`task=<form uuid>` appended) |
| 21 | `Form` | (switched) | Pushes `ab.task.userform` to the **current request user's** socket and waits for `userform.update` |

The designer palette offers start event, end event, exclusive gateway, task and
participant; "switch to" buttons turn a generic Service Task into types 10-18 and a User
Task into 19-21.

**Not implemented** (verified by file listing): parallel/inclusive gateway classes,
"update record" task (use a Query task with an `update` step), CSV export or NetSuite
tasks, intermediate/boundary events, notification channels other than email.

---

## 3. Engine runtime (process_manager)

### 3.1 Startup

`AB.controller("process_manager")` with `waitForDB = true`. `afterStartup` calls
`tenant_manager.config.list` and sends `process_manager.initialize_timer` per tenant as a
`_system_` request. Tenant factories load lazily. Only setting: `PROCESS_MANAGER_ENABLE`.
Uses node-cron 3.0.3.

### 3.2 Handlers (`developer/process_manager/handlers/`)

| Key | Params | Behavior |
|---|---|---|
| `trigger` | `key`, `data`, `requestID`, `rowLogID` | For each process, find the start event with that `triggerKey`; `instanceKey = <requestID>.<trigger.id>`; run inside `req.retry`; reply with the count **after the runs finish** |
| `run` | `instanceID` (string/array) | Load instance(s) and `run()` |
| `reset` | `instanceID`, `taskID` | `instanceReset(pi, taskID)` then run |
| `initialize_timer` | none | Start cron jobs for enabled timers in this tenant |
| `timer-start` / `timer-stop` / `timer-status` | `uuid` | (Re)start, stop, report `{isRunning}` |
| `userform.create` | `name, process, definition, ui, data`, opt. `scopeQuery, roles, users` | Create a SITE_PROCESS_FORM row, reply, broadcast `ab.inbox.create` |
| `userform.status` | `formID` | Return the form row |
| `userform.update` | `processID, taskID, instanceID, values` | `task.enterInputs()` then `process.run()` (not awaited) |
| `inbox.find` | `users`, `roles` | Pending forms for those users/roles, filtered by `scopeQuery` |
| `inbox.meta` | `ids` | Group process ids by application |
| `inbox-update` | `user, uuid, response` | Mark the form processed, reply, then `run` |
| `external` | `user, uuid, response` | Same, plus broadcast `ab.inbox.update` |

Key naming mixes dots (`inbox.find`, `userform.*`) and dashes (`inbox-update`,
`timer-*`). Keys are wire contracts: never rename them.

### 3.3 Starting an instance

`trigger()` builds the context and calls `instanceNew` (`platform_service/platform/ABProcess.js:158-224`):
`initState` on all elements, prune input, get or create the definition snapshot, insert the
instance (`status:"created"`, `log:["created"]`, `triggeredBy = req.username()` which is
`_system_` without a user, `instanceKey ?? "UUID()"`), then `run()`. `ER_DUP_ENTRY` on
`instanceKey` counts as "already triggered" and returns success.

### 3.4 Walking the graph (`run()`, `ABProcess.js:273-405`)

1. Skip instances in `error` or `completed`.
2. `pendingTasks()` walks from `startTaskID`: a task that is not completed/errored is
   pending; otherwise follow `nextTasks()` (base: **all** outgoing flows in the instance's
   XML snapshot; gateway: only the chosen flow).
3. Nothing pending: close as `completed`.
4. Run every pending task's `do()` **in parallel**; a truthy result means done, then
   `reset()` its next tasks (loops can run again); `false` means waiting.
5. Progress made: `run()` again; otherwise save the instance.

Consequences (inferred): several outgoing flows act as an implicit parallel split; there is
**no join** (a merge target runs when the first branch arrives and can run twice); `End`
does not terminate other branches.

### 3.5 Resuming waiting tasks

There is **no sweeper**. A waiting task resumes only when something calls `run`:
`inbox-update` (Approval), `external` (External), `userform.update` (Form), or `reset`.
Timers only start new instances.

### 3.6 Errors, retries, idempotency

- A task rejection sets the task to `error` and the instance to `error` with
  `errorTasks[diagramID]`, except `"no valid path found"` and a `null` from `nextTasks()`,
  which leave the instance `created` (traps 8, 9). Configuration errors go through
  `errorConfig` (`notify.builder` + reject).
- `req.retry` (connection/deadlock/timeout codes, up to 10 tries) wraps the **whole**
  trigger+run and reset+run, so a retry repeats every side effect (inferred).
- Duplicate starts are prevented only by the UNIQUE `instanceKey`. No row locking:
  concurrent `run()` calls on one instance can lose updates (inferred).
- Element objects belong to the tenant factory and are shared by all instances; several
  tasks keep per-run data on `this` (`_req`, `results`, `instance`), so concurrent runs can
  see each other's values (inferred).

### 3.7 Tenancy

One factory per tenant (ABBootstrap); timers keyed `TIMER_POOLS[tenantID][elementID]`
(`process_manager/utils/active_timer.js`). A failed factory build sticks until restart
([server-platform.md trap 1](server-platform.md#9-traps)).

### 3.8 Timers

The cron expression is `"<sec> <min> <hour> <day> <month> <weekday> <year>"` with seconds
`*` (`core/tasks/ABProcessTriggerTimerCore.js:137-166`). node-cron 3.0.3 ignores the 7th
field and checks every second, so a timer can fire **every second of its minute** (trap 4).
Each fire sends `process_manager.trigger {key, data:{}}` with **no `requestID`**. Timers
are set up only at startup for tenants known then; the browser calls timer-start/stop after
saving a timer.

Seen on 2026-10-02 with a daily timer whose one task inserts a row (process_manager's clock
is UTC). Saving the timer element calls `PUT /process/timer/<id>/start`, and process_manager
logs `::: START CRON job [<cron>]`; disabling it calls `.../stop`. A `repeatTime: "12:47"`
passed to the element's constructor was stored as "19:47" from a browser at UTC+7 (trap 6);
setting `element.repeatTime = "12:49"` directly and saving gave `* 49 12 * * * *`. At 12:49
UTC the job fired 59 times (trap 4): one instance, keyed `"UUID()"`, ran to `completed`, and
the other 58 were refused with `Process already triggered for undefined` (trap 5). Because
that one row blocks every later timer-started run in the tenant, it was deleted through the
ProcessInstance model and the timer was disabled. To build a timer element from the console
(§6.1), take its class from `AB.processElementNewForModelDefinition({type: "bpmn:StartEvent",
businessObject: {eventDefinitions: [{$type: "ab:SignalTriggerTimer"}]}}, process)`.

---

### 3.9 Where "what runs next" comes from (seen 2026-10-02)

`ABProcessElementCore.nextTasks()` reads the element's `bpmn2:outgoing` children from the
instance's own copy of the BPMN XML (`instance.hashDiagramObjects[diagramID]`,
`developer/appbuilder/AppBuilder/core/process/tasks/ABProcessElementCore.js:236-262`). The
process definition's `connections` map is not used for this. A diagram whose elements
lack `<bpmn2:outgoing>` (for example XML written by hand, or a Start with no line out)
stops at the first element with `Configuration Error: Did not find any outgoing flows`,
and the run is still saved as `completed` (known issue PE12). Instances keep the XML they
started with, so fixing the diagram helps only new runs. Verified in code and at runtime
(§3.10).

### 3.10 A run seen end to end (2026-10-02)

Two small processes in a test app, watched in the logs and the database:

- **Row added → InsertRecord → End.** Creating a row made appbuilder call
  `process_manager.trigger` ("triggered 1 task", 194 ms). The instance in
  `SITE_PROCESS_INSTANCE` logged `created`, then "Insert a new row to Object: [...]", then
  "End Event Reached", and ended `completed`. The new row took one value from the trigger
  row (InsertRecord value mode `"2"`) and one fixed value (mode `"1"`). The InsertRecord
  write started no further process (§4).
- **Row updated → Approval → gateway → InsertRecord → End.** The Approval had `who: "1"`,
  `toUsers.useAccount: "1"` with admin's uuid as the account, and Form.io buttons with
  `event: "approve"` and `"reject"`. Updating a row created a `pending`
  `SITE_PROCESS_FORM` row, which `GET /config/inbox` returned. Answering it with
  `PUT /process/inbox/<form uuid>` and `{response: "approve"}` (what the inbox UI sends)
  marked it `processed`; the gateway, which tested the approval's `userFormResponse`, logged
  "chosen path towards Yes", and the new row appeared. The first try stopped at the start
  because the hand-written XML had no `<bpmn2:outgoing>` tags (§3.9).

## 4. Lifecycle triggers from data changes

Only appbuilder fires them, after `cb()` (fire-and-forget), from `model-post`
(`<objectID>.added`), `model-update` (`.updated`, skipped when `fromProcessManager`) and
`model-delete` (`.deleted`). Payload: `key`, `data` (row re-read with populate; delete sends
the old row), `requestID` (new uuid), `rowLogID`. Delivery goes through a circuit breaker
(3 s timeout) with a `SITE_PENDING_TRIGGER` retry queue; because `trigger` replies only
after the runs finish, slow processes trip the timeout and are retried, deduplicated by
`instanceKey` (inferred).

Writes that **never** fire triggers: InsertRecord tasks, ABQL updates, other services'
writes (e.g. user_manager), stored procedures.

---

## 5. Inbox and user forms

- **Approval / External:** `userform.create` saves a pending SITE_PROCESS_FORM row and, unless
  it has a `scopeQuery`, broadcasts **`ab.inbox.create`** to rooms `<tenant>-<user>` and
  `<tenant>-<roleUUID>`.
- **Browser:** loads `GET /config/inbox` (inbox.find + inbox.meta), joins rooms with
  `POST /process/inbox/register` (socket only), listens for `ab.inbox.create`,
  `ab.inbox.update`, `ab.task.userform`
  (`developer/ab_platform_web/ui/portal_work_inbox.js`).
- **Answering:** `PUT /process/inbox/:ID {response}` reaches `inbox-update`, which saves and
  runs; Approval then sees the form processed and completes. External systems answer with
  `POST /process/external {task:{id}, data}`.
- **How the inbox draws a form** (`platform_web/webix_custom_components/formioPreview.js`):
  `new Form(el, task.ui)` from formiojs 4.18 with no options, then
  `submission = {data: task.data}`. The data is the copy the task stored when it created
  the form; it does not change later. **Only top-level buttons** with `action: "event"` get
  a click handler (`formComponents.components.forEach`), so an Approve or Reject button
  inside a panel or fieldset does nothing. Form.io's JavaScript runs in the inbox (nothing
  in platform_web sets `noeval`; seen 2026-10-04, §7.2): a `customConditional` can show or
  hide a line or a button from the form data, and a `content` component's `html` fills in
  `{{ <expression> }}`. A component with `hidden: true` is not drawn but keeps its value in
  the form data, so a condition can read a value nobody sees; a button hidden by its
  condition is not drawn at all.
- A lifecycle trigger gives later steps every field of the row, keyed
  `<diagramID>.<field id>`, plus `<diagramID>.uuid`
  (`ABProcessTriggerLifecycleCore.processDataFields()`). `created_at` and `updated_at`
  are not fields, so forms and gateways cannot read them; store a date in a field when a
  step needs one.
- **Form tasks:** `ab.task.userform` opens a popup
  (`developer/ab_platform_web/ui/portal_work_task_user_form.js`), which posts
  `POST /process/userform/:processID/:taskID {instanceID, values}` (`userform.update`).
  The portal has one such window and rebuilds it for each push, so a second Form replaces
  one that is still open. Its X hides the window without posting. The task
  (`ABProcessTaskUserForm.do()`, platform_service) pushes to the user's socket room only
  when the process reaches it, and a Form has no inbox entry, so a Form closed with the X
  is not shown again and its run waits until the task is reset (§3.5). With no user on
  the request (`req._user`), `do()` skips the Form and the run goes on without its values.
  A Form task writes no line to the instance `log`, neither when it is pushed nor when it
  is answered (seen 2026-10-31).

api_sails routes: `GET /process/inbox`, `POST /process/inbox/register`,
`PUT /process/inbox/:ID`, `POST /process/inbox/meta`, `POST /process/external`,
`PUT /process/reset/:taskID`, `POST /process/userform/:processID/:taskID` (logged-in user);
`PUT /process/timer/:ID/start|stop`, `GET /process/timer/:ID` (builder); `GET /config/inbox`.

---

## 6. Designer side

- **bpmn-js `^9.0.3`** `BpmnModeler` with a custom renderer, palette, replace menu and an
  `ab` moddle extension (`SignalLifecycle`, `SignalTriggerTimer`)
  (`developer/plugins/ABDesigner/src/rootPages/Designer/ui_work_process_workspace_model.js`).
- New shapes call `elementNewForModelDefinition()`, matched by event-definition type or
  BPMN type; untyped shapes get a `highlight-undefined-task` marker. Connections are
  upserted on `bpmnElement.added` / `element.changed` and removed on `shape.remove`.
- One property panel per element type under `.../Designer/properties/process/`; form
  designers use form.io (`formiojs ^4.18.0`).
- **Saving:** `saveXML`, `modelUpdate`, `process.save()`: each element saves as its own
  definition row (`POST /definition/create` or `PUT /definition/:id`, builder-only), then
  the process row.
- **Monitor tab:** lists instances and offers Reset for errored ones
  (`PUT /process/reset/<task.id>`; see trap 3).

### 6.1 Building or changing a process from the browser console

What the designer does can also be done from the console with the browser factory
([frontend.md §11](frontend.md#11-building-definitions-from-the-browser-console)). Done this
way for test processes on 2026-10-02 and 2026-10-04, and for "Principal Change Approval" and
the rework of "Updated Assignments" (NetSuite HR Update) on 2026-10-03.

- **A new process, in this order** (trap 38): `const p = AB.processNew({name, label,
  xmlDefinition: ""}); await p.save();`, so the elements get a `processID`; then, per
  element, `new Cls({...values, label}, p, AB)` and `await e.save()`, each one before another
  element refers to its id; then the XML, `p._connections`, `await p.save()` and
  `await app.processInsert(p)`. Take an element class from an existing element
  (`p.elements().find((e) => e.key == "InsertRecord").constructor`) or from
  `AB.processElementNewForModelDefinition()` (§3.8 shows it for a timer).
- **The XML must carry `<bpmn2:incoming>` / `<bpmn2:outgoing>` children on every element**
  (§3.9), and `_connections` must hold one `{id, type, from, to}` per sequence flow, because
  gateways follow `_connections` (trap 39): keep both in step. For the ABDesigner modeler to
  draw the lines, the XML also needs a `bpmndi:BPMNEdge` per flow; a diagram with only
  `BPMNShape`s opens with its shapes and labels but no lines.
- **Query task values:** `qlObj` is the chain `object → find → first → row_pluck → row_save`
  as nested `next` objects, each with `objectID`. A find rule on trigger data uses
  `rule: "context_equals", value: "StartEvent_1.<field id>"`; one on the trigger row itself
  uses `key: "this_object"` with `value: "StartEvent_1.uuid"`. Name a saved value after the
  plucked field's id when a gateway must test it (trap 36).
- **InsertRecord `fieldValues`** are keyed by the **target** field id: `{set: "2", value:
  <trigger field id>}` copies from the trigger row (the two objects may differ), and
  `{set: "1", value: "ab-current-date"}` gives a date field today's (server) date.
- **Changing an existing process:** parse `p.xmlDefinition` with `DOMParser`, change the
  `<bpmn2:*>` nodes, their `incoming`/`outgoing` children and the matching
  `BPMNShape`/`BPMNEdge`, serialize it back, update `p._connections`, call `el.destroy()` for
  each element you drop (it deletes the definition and removes it from the process), then
  `await p.save()`. Afterwards check that every flow in the XML is in `connections` and the
  other way round.

---

## 7. Traps

Verified in code unless marked inferred.

1. **An Api task stalls the run:** its `do()` returns `undefined` and `run()` only moves on
   for truthy results, so later tasks wait until something else calls `run` (inferred).
2. **SubProcess runs one wave per item:** `doTasks()` returns `undefined`, so its loop runs
   once (regression from platform_service `213ceac`, 2025-02-25; inferred).
3. **Monitor Reset skips the failed task:** the designer sends the element `id`, but
   `instanceReset` matches it as a `diagramID`, so nothing resets and the errored task is
   walked past (inferred).
4. **Timers fire up to 60 times in their minute** (seconds field is `*`). Seen 2026-10-02:
   59 `TRIGGER CRON job` lines in one minute (§3.8).
5. **Timer-started instances collide:** with no `requestID` the `instanceKey` is the literal
   string `"UUID()"`, and `SITE_PROCESS_INSTANCE` has a UNIQUE index on `instanceKey`
   **alone**, for every process in the tenant. Seen 2026-10-02: the first fire created one
   instance keyed `"UUID()"`; the other 58 fires logged `Process already triggered for
   undefined`. Inferred from the index: once one such row exists, **no timer-started run of
   any process in that tenant can be created again**. Check with
   `SELECT COUNT(*) FROM SITE_PROCESS_INSTANCE WHERE instanceKey='UUID()'`.
6. **Timer time of day drifts by the browser's UTC offset on every save.**
   `ABProcessTriggerTimerCore.fromValues()` treats the stored `repeatTime` as UTC and turns
   it into local time, but `toObj()` stores that local string back unchanged (only a `Date`
   is converted). Seen 2026-10-02 from a browser at UTC+7: "12:47" was saved as "19:47"
   and the server started `* 47 19 * * * *`. 12-hour locales also lose PM (inferred).
7. The core default `repeatMonthly: "last"` is not a valid node-cron day; one bad monthly
   timer throws inside `initialize_timer` and stops that tenant's remaining timers
   (inferred).
8. Exclusive gateway: no default branch, and "no path" leaves the instance `created` (a
   later run closes it as completed).
9. A task with no outgoing flow ends up `error` but the instance is not marked error.
10. No join semantics; 11. "Terminate" End does not terminate (inferred).
12. Diagrams with several pools likely break the engine (xml-js turns repeated
    `bpmn2:process` into an array; inferred, unverified).
13. **In-flight instances mix snapshot and live definitions:** "what runs next" comes from
    the snapshot, but task settings, gateway branches and data lookups use the current
    definition.
14. Data keys mix `diagramID`, `id` and raw form keys (§1.3).
15. Shared element objects across concurrent instances; `InsertRecord.results` grows for
    the factory's lifetime (inferred).
16. Participant `users()` ignores field-based users.
17. Email reports almost every send error as "server refusing to connect" (wrong
    `indexOf` check).
18. `this.log(message)` passes a string where an instance is expected (TypeError when a
    form row is missing).
19. Two promise executors `return` a rejection instead of calling `reject`, so they never
    settle (AccountingFPYearClose, External; inferred).
20. An Approval with no `formBuilder` throws in `processDataFields`, breaking downstream
    lookups (inferred).
21. External's URL template calls `myState()` on participants/lanes, which lack it
    (inferred).
22. **Form tasks depend on the request user:** skipped for timer/`_system_` runs, sent to
    whoever's request is running, and a closed popup leaves the instance waiting forever
    (inferred). The HR Teams widget hides some of these popups on purpose
    ([netsuite-hr-update.md §5](../netsuite-hr-update.md#5-run-history-in-this-stack-2026-10-02)).
23. Server-side code execution: InsertRecord formula mode `eval`s strings built from record
    values; Email messages and External URLs are EJS templates (inferred risk).
24. Accounting SQL is built by string interpolation, and the procedures exist only in
    `appbuilder-admin`.
25. **Authorization gaps:** inbox answers, form submits, external callbacks and resets need
    only a logged-in user; nothing checks the user is an assignee or the form is pending
    (inferred).
26. Answered approvals stay in other assignees' inboxes until reload (`inbox-update`
    broadcasts nothing).
27. Thin handler error handling: `userform.update` has none and does not await `run`;
    `userform.create` can call `cb` twice.
28. `context`, `log`, `errorTasks`, `ui`, `data` are TEXT (about 64 KB) while
    `_prevState` chains grow (inferred).
29. **An unknown element `key` breaks the whole tenant** in that service until restart
    (throws during the factory build; inferred).
30. **Seeded processes run in every tenant** on each new SITE_USER ("New User Default
    Roles", "TestSendMail"); TestSendMail stores a literal email where a data key belongs,
    so it errors every time (inferred).

Seen at runtime on 2026-10-03 (NetSuite HR Update,
[netsuite-hr-update.md §8](../netsuite-hr-update.md#8-a-cross-entity-principal-move-end-to-end-2026-10-03)):

31. **A one-element list from an earlier task arrives as a bare value.**
    `ABProcessCore.processData()` (class_core) collects answers with lodash `_concat`,
    which spreads an array result, then returns `values.length > 1 ? values : values[0]`.
    So `["2715"]` comes back as `"2715"`, and `[]` as `null`. A query rule `context_in` or
    `context_not_in` becomes `in` or `not_in` (`ABQLFind.conditionReduce()`), and
    `ABModel` compiles `in` with a value that is not an array to `1=0`
    (`platform/ABModel.js:1555-1584`), so the query returns nothing. Any task that reads a
    list from an earlier task can hit this when the list has exactly one entry (B25).
32. **`set_pluck` on a connect field loads every relation of the linked rows.**
    `ABQLSetPluck` re-reads the rows with that field populated, then reads the linked rows
    with `populate: true`. On a NetSuite object that is one SuiteQL read per relation:
    plucking 155 subsidiary ids read all their team assignments, teams, employees and
    responsibilities (PE15).
33. **Email tasks whose From or To is the current or next participant crash in a process
    without lanes.** `resolveAddresses()` pushes `this.myLane()` (`undefined`), and
    `laneUserEmails()` calls `.users` on it: `TypeError: Cannot read properties of
    undefined (reading 'users')`. The designer warning "can not resolve the lane
    participant" predicts it. The run is saved as `error` even when every earlier task
    worked (PE13).
34. **Process context keeps whole rows.** A query task that reads `SITE_USER` stores each
    user with every column in `SITE_PROCESS_INSTANCE.context`, including `password` and
    `salt` when the user has a local password (seen for admin in a 2026-09-14 run, S34).
35. **Process queries ignore scopes.** Query, InsertRecord and pluck steps call the model
    directly (`ABQLFind` → `model().findAll(cond, null, req)`), and only appbuilder's
    model-get handler adds scopes; NetSuite credentials come from the object, not the user.
    So a run reads every row, whoever triggered it. Seen 2026-10-03: a run started by
    `hr.mock.pxr` (scoped to PXR) read the PXY subsidiary's name. Only the browser-side
    checks are limited by the user's scope (known-issues D6).
36. **A gateway can test a query task's output only when the saved parameter is named
    after the field's id.** The gateway loads the fields that earlier tasks offer and
    matches each rule by field id; `getFieldVal()` (`class_core/FilterComplexCore.js`)
    then looks for a process key that ends in `.<field id>`. Trigger data is keyed
    `StartEvent_1.<field id>` and an approval answer brings its own pseudo-field, so both
    work. A query task's value is keyed `<task id>.<parameter>`, so a rule built on it in
    the designer reads nothing (a boolean then reads as unchecked, a text as empty).
    Workaround, used in "Principal Change Approval": name the `row_save` parameter
    after the plucked field's id. Proven on 2026-10-04 (§7.1): with ordinary names a
    gateway chose No for an item that was done and named, with field-id names Yes.
    A Calculate task offers an unsaved fake field with no id, and its value is keyed
    `<task id>.value`, so the same lookup probably cannot find it either (read from code,
    not tested; PE21).
37. **No element deletes a record.** The query language offers find, first, pluck, save
    and update, and there is no delete task, so a process can only mark a row; something
    else has to delete it (PE20).
38. **Element ids exist only after `save()`.** When building a process from the console,
    save the process first (its elements take their `processID` from it), then save each
    element before another element refers to its id, for example in an approval's
    `toUsers.userFields` (`"<task id>.<parameter>"`). An element built before that refers to
    `undefined.<parameter>`, the dead source still visible in old definitions.
39. **Gateways choose the next task through the stored `connections`, other elements
    through the XML.** `ABProcessGatewayExclusive.nextTasks()` follows
    `process.connectionsOutgoing()`, built from the definition's `connections`, while a
    normal task follows its `<bpmn2:outgoing>` flows in the XML. When a flow is moved by
    hand, change both, or the gateway and the diagram disagree.
40. **An Approval that resolves to nobody is still created, and its run waits forever.**
    `ABProcessTaskUserApproval._requestNewForm()` (platform_service
    `platform/process/tasks/`) sends whatever its role, account and user-field settings
    give, even an empty list, and `process_manager.userform.create`
    (`handlers/userform-create.js`) creates the form with no users and no roles. It warns
    (`notify.builder`, "no matching users for provided settings") only when names were
    given and none matched; an empty list passes silently. Nobody sees the form, so nobody
    answers it, and the instance stays at that task. On 2026-10-04 this tenant held 19 such
    pending forms ("Notify of an Edited Assignment", 2026-09-13 to 09-15). When recipients
    come from data, check the list before the Approval; the gateway offers no "is empty"
    for user fields ([domain-model.md §7.2](domain-model.md#72-operators-offered-per-field-type-filtercomplexcorefieldstoqb-824-1014))
    and reads a query result only by field id (trap 36). Seen as PE23.
41. **An `update` step that finds no row does nothing and does not fail.**
    `ABQLRowUpdate.do()` (platform_service `platform/ql/`) logs
    `no data provided to ABQLRowUpdate` to the console and passes on, so a run whose
    record was deleted meanwhile carries on to its next task (seen 2026-10-04, §7.2 and
    [netsuite-hr-update.md §12.9](../netsuite-hr-update.md#129-expiry-after-7-days-since-2026-10-04)).
42. **Gateway date rules compare calendar days in process_manager's time zone.**
    `FilterComplexCore.dateValid()` evaluates `less_current`, `greater_current`,
    `less_or_equal_current` and `greater_or_equal_current` with `setHours(0, 0, 0, 0)` on
    both sides, in the server's local time (UTC in this stack), so the day changes at 07:00
    in Thailand (compare W23). Seen 2026-10-04 at 06:00 in Thailand: a date equal to the
    UTC day counted as today. **An empty date matches neither `less_current` nor
    `greater_or_equal_current`**, without an error, so a gateway with only those two
    branches stops with `no valid path found` and the run stays `created` (trap 8); give one
    branch an `is_empty` rule too (§7.2).

### 7.1 Proof for trap 36 (PE21), 2026-10-04

Two test processes that differ **only** in the names of the saved values, both built from
the console (§6.1) and both started by one new row of a test object. Each reads one item,
"Gear" (its `Done` checked, its `Name` filled), and tests it in two gateways:

| Step | A (ordinary names) | B (field id names) |
|---|---|---|
| Query "Read Gear Done": item where Name = "Gear" → first → pluck `Done` → save as | `GearDone` | `282bbf7b-…` (the id of `Done`) |
| Query "Read Gear Name": same → pluck `Name` → save as | `GearName` | `4ebab2b3-…` (the id of `Name`) |
| Value saved in the run (`SITE_PROCESS_INSTANCE.context.taskState`) | `GearDone: 1`, `GearName: "Gear"` | `1`, `"Gear"` |
| Gateway "Is Gear Done?" (Yes: `Done` checked, No: unchecked) | **No** | Yes |
| Gateway "Does Gear Have a Name?" (Yes: `Name` is not empty, No: is empty) | **No** | Yes |

Run A saved both values, yet its gateways could not see them: a boolean read as unchecked
and a text as empty. Run B, with the same data, chose Yes twice. The conditions are what
the designer builds: its gateway editor lists the fields the earlier tasks offer (the
plucked field, by id), so a process made entirely in ABDesigner fails like A (inferred from
`ABDesigner/src/rootPages/Designer/properties/process/ABProcessGatewayExclusive.js:68-73`).
The two processes are kept in the local tenant's test app (Claude Sandbox, "Sandbox Gateway
Test A" and "B"), so the check can be repeated: add any row to its Sandbox Task object and
read the two newest runs' logs.

### 7.2 Expiry checks in an approval, tested in the sandbox (2026-10-04)

Built from the console (§6.1) in the local test app before the same design went into
"Principal Change Approval"
([netsuite-hr-update.md §12.9](../netsuite-hr-update.md#129-expiry-after-7-days-since-2026-10-04)):
an object with a date field `expires_on`, and a process trigger → Approval → "Has the
Request Expired?" (`less_current` / `greater_or_equal_current` on the trigger's date) → "Is
Approved?" → a status update. The Approval's form shows a red line and a Close button when
the date has passed, Approve and Reject before (Form.io `customConditional`, §5). Run on
2026-10-04 between 05:50 and 06:05 in Thailand, when the UTC date was still 2026-10-03:

| `expires_on` | The window showed | Answer | Path |
|---|---|---|---|
| 2026-10-02 | Red line, only Close | Close, in the inbox | Expired: Yes |
| 2026-10-10 | Approve, Reject | Approve (API) | No, then "Is Approved?" Yes |
| 2026-10-03 (the UTC day; already 2026-10-04 in Thailand) | Approve, Reject | Approve (API) | No, then Yes: the window (browser) and the gateway (server) agree on the UTC day |
| 2026-10-01 | (not opened) | Approve (API) | Yes: the server's check holds whatever the window showed |
| 2026-10-01, row deleted before the answer | | Close (API) | Yes; the update step found no row, logged `no data provided to ABQLRowUpdate`, and the run completed (trap 41) |
| empty | | Approve (API) | `no valid path found`, run left `created` (trap 42) |
| 2026-10-09, date shown as `{{ }}` text, its field hidden | "Expires on 2026-10-09 (UTC)", Approve, Reject | Reject (API) | No, then "Is Approved?" No (`not_equal approve`) |
| 2026-09-30, same form | The date line, red line, only Close | Close (API) | Yes |

Dates: a date written as `"YYYY-MM-DD"` is stored as given. The browser model returns it as
local midnight (`2026-10-01T17:00:00.000Z` for 2026-10-02 at UTC+7); the trigger data and
the form data carry UTC midnight (`2026-10-02T00:00:00.000Z`). Code that needs the day has
to read each shape the right way: take the first 10 characters of a UTC-midnight value, and
the local date of a local-midnight one.
