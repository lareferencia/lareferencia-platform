# Workflow: Actions, Scheduling and Engines

**Status:** current · **Last verified:** 2026-09-23

Operational reference for how network actions are defined, configured, scheduled and executed.
Decision records: [`WORKERS_TASKS_ACTIONS_ANALYSIS.md`](WORKERS_TASKS_ACTIONS_ANALYSIS.md) and
[`IMPLEMENTACION_CONFIGURACION_ACCIONES_2026-08-27.md`](IMPLEMENTACION_CONFIGURACION_ACCIONES_2026-08-27.md).

## Action definitions (beans)

Actions are declared as `NetworkAction` beans in XML under `config/beans/`, grouped by concern and
profile: `harvesting.actions.xml`, `validation.actions.xml`, `xoai.actions.xml`,
`index.elastic.actions.xml`, `index.frontend.actions.xml`, `index.thesis.actions.xml`,
`index.rcaap.actions.xml`, `cleaning.actions.xml`, `dark.actions.xml`, `entity.actions.xml`,
`network.actions.xml`, `project.actions.xml`, `historic.actions.xml`, plus localized variants
(`*.actions.en.xml`). Each action binds a **prototype** worker bean (e.g. `validationWorker`,
`darkStageWorker`, `entityExtractionWorker`).

Localized rule/label bundles: `actions.xml` + `actions.en.xml` (+ `actions.dc.xml`, `actions.dev.xml`,
`actions.rcaap.xml` for profile variants).

## Action catalog and per-network configuration (v5)

Defined in `lareferencia-core-lib` and persisted by migration
`lareferencia-shell/src/main/resources/db/migration/V5.0.0.8__Harvester_action_configuration.sql`
(the three tables were consolidated there; there is **no** `V5.0.0.9`/`V5.0.0.10` action migration —
`V5.0.0.9` is the dARK runtime configuration):

| Table | Entity | Purpose |
|---|---|---|
| `application_action` | `ApplicationAction` | Global action catalog (key, worker wiring) |
| `network_action` | `NetworkActionConfiguration` | Per-network config: `enabled`, `scheduleEnabled`, JSONB `configuration`, `updatedBy` |
| `application_worker_configuration` | — | Worker-level parameterization exposed in the Admin UI |

- Workers read options from `NetworkRunningContext.getBooleanActionOption(...)` — e.g. `HarvestingWorker`
  (`FORCE_FULL_HARVESTING`) and `ValidationWorker` (`DETAILED_DIAGNOSE`).
- Scheduled execution is guarded by `WorkflowService.setScheduledProcessGuard(BiConsumer<...>)` so the
  network-level schedule state is honored by both engines.

## Engines

```properties
workflow.engine=legacy   # legacy (TaskManager) | flowable
```

- **legacy** (default, `08-workflow.properties`): `TaskManager` launches workers;
  `launchWorkerWithResult(...)` returns a `WorkerLaunchResult`; `LegacyNetworkActionExecutor`
  runs all actions of a network.
- **flowable**: `WorkflowService` + delegates execute BPMN definitions in `config/processes/`
  (`harvesting`, `validation`, `frontend-indexing`, `xoai-indexing`, `network-processing`,
  `network-clean`, `network-delete` — `*.bpmn20.xml`).

Engine selection is wired with `@ConditionalOnProperty` (`TransactionManagerConfig`,
`INetworkActionExecutor`, `TaskManager`).

## Managing actions

- **API v5**: `GET/PUT /api/v5/networks/{networkId}/actions[/{key}]`, `/api/v5/application-actions`
  (with `/usage`, `/move`, `/refresh`), `/api/v5/worker-configurations`, and
  `POST /api/v5/networks/{id}/commands` (`{actionName, incremental}`).
- **Admin UI**: "Actions" page (application actions + worker parameters) and per-network schedule
  editor (manual/scheduled checkboxes + RJSF-generated configuration form).
- **Shell**: action commands and `config/beans/*actions.xml` definitions; configuration lives outside
  component scans in the shell (see dARK isolation notes in `dark.actions.xml` usage).