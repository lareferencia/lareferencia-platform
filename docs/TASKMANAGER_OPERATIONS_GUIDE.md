# Harvester TaskManager Operations Guide

Updated: 2026-10-03. Audience: administrators deploying and operating the Harvester with `workflow.engine=legacy`.

This guide covers deployment, database migration, runtime configuration, queue monitoring, and restoring previous settings. TaskManager coordinates workers inside one Harvester process. Its limits and monitoring panel are available to users with the `ADMIN` role on the Admin **Runtime** page.

Settings saved through Admin survive restarts. Pending tasks and execution history are held in memory and do not survive a restart. Coordinate the deployment when existing work has finished, or arrange to resubmit interrupted work afterward.

## Deploy the updated components

Deploy matching versions of core-lib, the Harvester application, the shell, and Admin. An older shell artifact will not contain the new migration; an older Admin bundle will not contain the configuration and queue panels.

Use this sequence:

1. Record the current configuration and identify any active or queued work.
2. Build the updated shell with its core-lib dependency and migration resources.
3. Point the shell at the same database used by the Harvester and inspect migration status.
4. Apply the pending migrations and confirm that version `5.0.0.15` succeeded.
5. Deploy or rebuild the updated Harvester and Admin.
6. Sign in as an administrator and open **Runtime**. Confirm that the configuration and capacity panels load.

The required migration is:

```text
lareferencia-shell/src/main/resources/db/migration/
V5.0.0.15__TaskManager_runtime_configuration.sql
```

It creates `taskmanager_configuration`, containing a single installation configuration row with ID `1`. The row stores worker concurrency, queue capacity, result retention, retained result count, shutdown wait, and the last editor and modification time. The migration creates the table without inserting a configuration row, preserving installation defaults until the first Admin save.

Apply the migration before starting the new Harvester. The shell migration commands are:

```text
database_info
database_migrate
database_info
```

`database_migrate` applies all pending migrations, so review the initial report. Do not use database clean or repair commands to perform this upgrade.

### Docker development deployment

For an existing Docker development installation, run these commands from the parent project directory:

```bash
./Docker/docker-dev.sh build shell
./Docker/docker-dev.sh lrshell database_info
./Docker/docker-dev.sh lrshell database_migrate
./Docker/docker-dev.sh lrshell database_info
./Docker/docker-dev.sh rebuild harvester
```

The Harvester rebuild also compiles the Admin and repository dashboard and restarts the Harvester. For a later change confined to Admin, use:

```bash
./Docker/docker-dev.sh rebuild frontend
```

These commands use the installation's existing Docker configuration and build profile. For a packaged or production deployment, follow the same ordering with its normal build and release procedure: updated shell, migration, then updated Harvester and Admin.

## Change runtime settings

Open **Admin → Runtime → Process configuration**. Enter the values and select **Save and apply**. Editing a field alone does not change execution limits. The form shows whether values come from installation properties or a saved configuration, together with the last editor and timestamp.

| Setting | Initial default | Allowed values | Effect |
|---|---:|---|---|
| Concurrent workers | 4 | Integer, at least 1 | Maximum global reservations for workers in this Harvester process. |
| Maximum queued workers | 32 | Integer, at least 0 | Maximum total pending workers across all contexts. |
| Result retention | 3600 seconds | Integer, at least 1 | Retention period for terminal execution records. |
| Maximum retained results | 1000 | Integer, at least 1 | Maximum number of terminal execution records retained. |
| Shutdown wait | 30 seconds | Integer, at least 0 | Time to wait for the worker executor after requesting shutdown. |

Installation properties may override these initial defaults. Before the first Admin save, the relevant keys are:

```properties
taskmanager.concurrent.tasks=4
taskmanager.max-queued-tasks=32
taskmanager.result-retention-seconds=3600
taskmanager.max-retained-results=1000
taskmanager.shutdown-timeout-seconds=30
```

The historical queue key `taskmanager.max_queuded.tasks` is accepted as an alias. When using properties, do not define it and `taskmanager.max-queued-tasks` with different values.

After an Admin save, the database configuration takes precedence over these five properties and is restored when the Harvester starts. Changing the property file alone will not replace the saved configuration. The scheduler pool and reconciliation interval remain startup settings outside this form:

```properties
scheduler.pool.size=10
taskmanager.reconcile.interval-ms=2000
```

The scheduler pool handles scheduling and cron callbacks; it does not set worker concurrency.

### What happens when limits change

Increasing concurrency immediately allows eligible pending workers to be dispatched. Context and lane exclusions still apply.

Reducing concurrency preserves existing reservations, including workers already dispatched and cancellation requests awaiting completion. Occupancy can temporarily exceed the new limit. No new reservation is made until enough existing reservations finish.

Reducing queue capacity preserves every admitted pending worker. New plans are rejected if the complete plan cannot fit under the new limits. A queue capacity of zero permits only work that can reserve immediate execution capacity while respecting context and lane exclusions.

Reducing result retention or retained result count can immediately remove older terminal records. It does not cancel active workers or delete their business data. Raising the limits afterward cannot restore records already purged.

## Read the capacity and queue panel

The panel refreshes every 10 seconds and shows the time of the last received execution snapshot. If refresh fails, it keeps the previous data and displays an outdated-data notice. Limits and executions are fetched separately, so they can briefly reflect different moments during a configuration update.

### Global occupancy

Two bars show **active workers / maximum concurrency** and **queued workers / maximum queue capacity**. Active occupancy includes reserved workers awaiting entry into execution and workers with cancellation requested. A slot is released only when the worker body and any tracked stop hook have finished.

For example, `3 / 4` active and `12 / 32` queued means three reservations and twelve pending workers. A label indicating occupancy above the new limit is expected after lowering a limit below current usage. The displayed count remains the actual count; it is not clipped to the new maximum.

### Lanes

A lane is an exclusion group identified by a nonnegative number. At most one worker reservation can occupy the same lane, even across different contexts. Lane `0` is a regular lane. A negative lane disables lane exclusion for that worker.

Each observed lane displays occupancy `0 / 1` or `1 / 1`, the reserved worker and source, its state, and the number of pending workers assigned to that lane. Pending workers may be waiting for their context order or global capacity rather than for the lane itself.

Free lanes remain visible while recent execution records identify them. This is an inventory of observed lanes, not every lane configured in the installation. Workers without lane exclusion are summarized separately.

### Queues by source and context

A context is the execution identity supplied by a worker. Each context admits at most one active reservation and preserves FIFO order for its pending steps. Contexts may have the same source acronym; their distinct context IDs remain visible. Manual dARK operations can use a context different from the source's normal harvesting context.

The list sorts contexts by pending count and shows their active worker, the first three pending steps, and an expansion button for additional steps. No individual maximum is shown because queue capacity is global; there is no separate per-context limit.

| Waiting reason | Interpretation |
|---|---|
| `CONTEXT_ORDER` | An earlier step in the same context must run first. |
| `CONTEXT_BUSY` | Another worker holds that context's reservation. |
| `LANE_BUSY` | The head worker's lane is reserved elsewhere. |
| `GLOBAL_CAPACITY` | No global worker slot is available. |
| `EXECUTOR_UNAVAILABLE` | A reserved worker awaits a retry of its transfer to the executor. |

## Interpret execution outcomes

| State | Meaning |
|---|---|
| `QUEUED` | Admitted and pending. |
| `DISPATCHED` | Holds a reservation; its body has not started. |
| `RUNNING` | Its body is executing. |
| `CANCEL_REQUESTED` | Cancellation was requested; its reservation remains occupied. |
| `COMPLETED` | Its body finished without a propagated or reported execution failure. |
| `FAILED` | Its body threw an error or reported an execution failure. |
| `CANCELLED` | Entry was prevented, or the cancelled execution and its tracked stop hook finished. |

`COMPLETED` does not certify every business effect. Inspect the action's results and logs when assessing harvesting, validation, indexing, or dARK publication. A failed step does not automatically cancel all subsequent steps in its context.

An accepted action response means admission, not completion. Each execution has an `executionId`; steps admitted together share a `groupId`. Admission of a plan is complete or rejected; it is not partially admitted because the queue filled halfway through submission.

Cron prepares fresh worker instances on each firing. A firing is skipped while a cron plan for that context remains live. Removing a schedule does not cancel a plan already admitted.

## Restore previous settings

Before changing settings, record all five current values. To undo the change, enter those values in the Runtime form and select **Save and apply** again. This restores both the effective limits and their persisted values.

Restoring a smaller limit preserves current work and can temporarily show occupancy above that limit. Restoring retention settings cannot recover records already removed. A restart alone does not undo a saved configuration.

Reverting an application release is a separate deployment operation. This guide does not provide a down migration. Coordinate release rollback with the installation's normal process and retain the configuration table unless a reviewed schema rollback requires otherwise.

## Troubleshooting and operational checks

| Symptom | Check or action |
|---|---|
| Configuration or queue panel fails to load | Confirm the new Harvester and Admin are deployed, the required table exists, the engine is legacy, and the user has the ADMIN role. |
| Migration `5.0.0.15` is absent from shell output | Confirm the shell artifact was rebuilt with the SQL resource, and that its migration location and database connection are correct. |
| Action admission returns `TASK_QUEUE_FULL` | Inspect pending count, global limits, and the head waiting reasons. Retry later or adjust capacity deliberately. |
| A lane remains occupied after cancellation | Inspect the worker and its logs. Cancellation is cooperative; an execution that has not exited retains its reservation. |
| Values return after restart despite property edits | A saved database configuration has priority. Change the values through Admin. |
| A free lane disappears from the panel | Its identifying execution records may have expired or been removed by retention limits. |
| No queued work remains after restart | Queues are in memory. Resubmit the required work through the normal action entry points. |

Administrative API endpoints are `GET` and `PUT /api/v5/runtime/configuration`, plus `GET /api/v5/runtime/executions`. They require the ADMIN role. The configuration PUT requires all five fields: `concurrentTasks`, `maxQueuedTasks`, `resultRetentionSeconds`, `maxRetainedResults`, and `shutdownTimeoutSeconds`.

Invalid settings return HTTP 422 with `TASKMANAGER_CONFIGURATION_INVALID`. A non-legacy engine returns HTTP 409 with `TASKMANAGER_CONFIGURATION_UNAVAILABLE`. An update during shutdown can return HTTP 503 with `TASKMANAGER_SHUTDOWN`. Database persistence precedes runtime application; if shutdown intervenes after the commit, the saved values are restored on the next start.

Coordination and configuration application are local to one JVM. This implementation does not provide distributed lane exclusion or broadcast settings changes to other Harvester processes sharing the database. The shutdown wait limits the executor wait; a custom stop hook that blocks can delay the shutdown request itself.

### Validation status

Java compilation and Admin TypeScript checking passed during implementation. Database migration, the deployed UI, persistence across a real restart, and behavior under real workload remain unverified in the installation. No deployment or database operation was performed while writing this guide.

After deployment, record the outcome of these checks:

- Migration `5.0.0.15` succeeds against the intended database.
- The Runtime panels load for an administrator.
- Saving settings changes the displayed limits and records the editor and time.
- Lowering a limit preserves admitted work and displays excess occupancy correctly.
- Queue order, lane ownership, and cancellation states match observed executions.
- A planned restart restores saved settings; outstanding work is handled explicitly.
