# Configuration Cleanup Proposal — `application.properties.d`

**Status:** proposed (on hold — configs deliberately untouched by decision on 2026-09-23) · **Last verified:** 2026-09-23

During the 2026-09-23 configuration audit ([`CONFIGURATION_PROPERTIES.md`](CONFIGURATION_PROPERTIES.md)),
several keys present in the versioned config fragments and templates were found to be
**not read by any code** ("dead keys"), plus one in-file comment that contradicts the code.
This document records the proposed cleanup so it can be reviewed and executed later.
**No configuration file has been modified** — this is a documentation-only record.

## Why the removals are safe

Spring Boot ignores unknown properties, so removing a key that no code reads has
**zero runtime effect** — the only change is readability of the config itself. Every
removal below was verified against the code on 2026-09-23 (per-key evidence in the
[summary table](#evidence-summary)). No live value changes; the only behavioral
alternative noted is optional (modern replacement loggers, see A3).

---

## A. Versioned fragments (zero runtime effect)

### A1. `lareferencia-lrharvester-app/config/application.properties.d/02-catalog.properties`

```diff
-# Timeout de conexión en segundos
-catalog.connection.timeout=30
```

### A2. `05-harvester.properties` — identical in the harvester and the shell

```diff
 scheduler.pool.size = 10
-taskexecutor.pool.size = 10
-
-#tiempo de limpieza de procesos terminados en milisegundos
-taskmanager.clean.interval = 60000
 taskmanager.concurrent.tasks = 4
 taskmanager.max_queuded.tasks = 32
-
-#reponame e instname
-reponame.fieldname=dc:source
-reponame.prefix=reponame:
-
-instname.fieldname=dc:source
-instname.prefix=instname:
```

Note: the misspelled `taskmanager.max_queuded.tasks` **stays** — it is the key the
code actually reads (`TaskManager` ~:117, default 32).

### A3. `lareferencia-lrharvester-app/config/application.properties.d/06-logging.properties`

Loggers for packages that no longer exist after the v5 refactor (they log nothing):

```diff
 logging.level.org.lareferencia=INFO
-logging.level.org.lareferencia.backend.taskmanager=INFO
 ...
-logging.level.org.lareferencia.backend.validation=DEBUG
 logging.level.org.lareferencia.backend.controllers.BackendController=DEBUG
```

Optional alternative (behavior-affecting — needs its own decision): replace the stale
loggers with the modern equivalents `logging.level.org.lareferencia.core.task=INFO`
and `logging.level.org.lareferencia.core.worker.validation=DEBUG`.

### A4. `08-workflow.properties` — correct the false in-file comment

```diff
-# Default: flowable
+# Default: legacy (the engine runs legacy when this property is unset or "legacy";
+# "flowable" enables Flowable — see docs/WORKFLOW_ACTIONS.md)
```

`TaskManagerConfig` runs the legacy engine when `workflow.engine` is `legacy` **or
unset**; `TransactionManagerConfig` enables Flowable only when the value is `flowable`.

### A5. `lareferencia-shell/config/application.properties.d/00-app.properties`

```diff
-# Application configuration directory path
-# Default: config
-config.dir.path=config
+# The config base directory is relocated with -Dapp.config.dir=...
+# (ConfigPathResolver, core-lib). There is no "config.dir.path" key.
```

---

## B. `lareferencia-lrharvester-app/config/application.properties.model` (versioned)

The template is **more stale than the live local file**. Proposed changes:

- `config.dir.path` block (lines ~22-24) → replaced by a comment pointing to the real
  mechanism: `app.config.dir` via `ConfigPathResolver` (see
  [`CONFIG_DIRECTORY.md`](CONFIG_DIRECTORY.md)).
- `dark.minter.url=http://minter.dark-pid.net/load` (section 6, v4 leftover) → removed;
  replaced by a comment stating that dARK is configured in
  `application.properties.d/07-dark.properties` (`dark.minter.base-url`, `dark.authority-id`, …).
- The whole `workflow.processes.*.lane` + `workflow.lanes[n]` block (lines ~121-155,
  never read by any code) → replaced by a comment: serial lanes are configured per
  worker bean with `serialLaneId` in `config/beans/*actions.xml` and enforced by the
  `TaskManager` queue map; the live keys are `workflow.max-queued-processes` plus the
  optional `workflow.max-queued-per-lane` (default 10) and `workflow.scheduler-pool-size`
  (default 5). See [`WORKFLOW_ACTIONS.md`](WORKFLOW_ACTIONS.md).

---

## C. Local gitignored files (optional, not committable)

Cosmetic-only hygiene (the keys are dead). These files are gitignored, so the change
cannot be committed — it only cleans the working copy:

- `lareferencia-lrharvester-app/config/application.properties`: remove `config.dir.path`
  and `dark.minter.url`.
- `lareferencia-shell/config/application.properties`: remove `solr.host` (read only by
  `lareferencia-entity-rest`, not by the shell) and the `workflow.processes.*.lane` /
  `workflow.lanes[n]` blocks.

The shell's own `application.properties.model` does not contain any of these keys
(it is already clean).

---

## D. Documentation sync (same change)

- [`CONFIGURATION_PROPERTIES.md`](CONFIGURATION_PROPERTIES.md): remove the table rows of
  the deleted keys and rewrite the *Maintenance notes* section to reflect that the
  cleanup was applied (with date).
- Check [`WORKFLOW_ACTIONS.md`](WORKFLOW_ACTIONS.md) and [`AUTHENTICATION.md`](AUTHENTICATION.md)
  for references to removed keys.

---

## E. `lareferencia-dashboard-rest` (added 2026-09-23 after documenting the module)

Discovered while extending [`CONFIGURATION_PROPERTIES.md`](CONFIGURATION_PROPERTIES.md) to the dashboard:

- `config/application.properties.model` carries a legacy `solr.host` + `elastic.*` block
  (host, port, username, password, useSSL, authenticate) that the live gitignored base no
  longer has. The dashboard's pom has no solr/elasticsearch/entity-lib dependency and no
  code reads these keys — dead in this module. Proposed: remove the block from the model
  (or move it behind a comment explaining it belongs to `entity-lib` deployments only).
- `99-docker.properties` repeats the same dead `solr.host` / `elastic.*` keys (with a
  "search backends (optional usage)" comment). Proposed: remove the block.
- Stale in-file comment in `00-server.properties` ("Access via http://localhost:8090") —
  the port is 8092. Proposed: correct the comment to 8092.
- Cosmetic only: the fragment file name `02-keycloack.properties` contains a typo
  ("keycloack"). Renaming is safe for the loader (files are scanned by directory) but is a
  versioned-file rename — do it together with a deployment note.

---

## Evidence summary

| Key / item | Defined in | Why it is dead (verified 2026-09-23) |
|---|---|---|
| `catalog.connection.timeout` | harvester `02-catalog` | `OAIRecordCatalogRepository` (~:67) reads `catalog.batch.size`; `CatalogDatabaseManager` (~:77) reads `catalog.sqlite.wal-mode`; nothing reads `catalog.connection.timeout` |
| `taskexecutor.pool.size` | both `05-harvester` | Only an integration test references it; not read in main code |
| `taskmanager.clean.interval` | both `05-harvester` | No such property in `TaskManager` |
| `reponame.*` / `instname.*` | both `05-harvester` | v4 legacy; the `reponame:`/`instname:` logic lives in the crosswalk/indexing XML (e.g. `lr-elastic-indexing.xml`) |
| `config.dir.path` | shell `00-app`, harvester `.model` + base | The real key is `app.config.dir` (`ConfigPathResolver`, `CONFIG_DIRECTORY.md`) |
| `dark.minter.url` | harvester `.model` + base | The real key is `dark.minter.base-url` (`DarkProperties`); the in-file value points at the v4 `/load` endpoint |
| `workflow.processes.*.lane`, `workflow.lanes[n]` | harvester `.model`, shell base | Zero code references (grep over `core-lib`, `lrharvester-app`, `shell` sources on 2026-09-23); lanes go via `serialLaneId` in beans XML |
| `solr.host` | shell base | Read by `lareferencia-entity-rest` (`LareferenciaEntityRestApplication` ~:73), not by the shell; shell indexers use `semantic.solr.url`/`frontend.solr.url` |
| `logging.level.…backend.taskmanager`, `…backend.validation` | harvester `06-logging` | Packages renamed in v5 (`core.task`, `core.worker.validation`); they log nothing |
| `# Default: flowable` comment | harvester `08-workflow` | Contradicts `TaskManagerConfig`: the real default is `legacy` |

---

## Decision record

- **2026-09-23:** proposal documented only — configuration files deliberately **not**
  modified (documentation-focused pass). No diff applied.

## How to execute later

1. Apply A2 to both `05-harvester.properties` files identically (harvester + shell).
2. Apply A1, A3, A4, A5 and the `.model` changes (B).
3. Decide on the local-only hygiene (C) separately from the committable changes.
4. Apply the documentation sync (D) in the same change so the reference stays true.
5. Re-run a startup afterwards and confirm the `[PropertiesLoader] Loaded: <filename>`
   lines and no behavioral change (all removed keys were dead).

Related: [`CONFIGURATION_PROPERTIES.md`](CONFIGURATION_PROPERTIES.md) ·
[`CONFIG_DIRECTORY.md`](CONFIG_DIRECTORY.md) · [`WORKFLOW_ACTIONS.md`](WORKFLOW_ACTIONS.md) ·
[`AUTHENTICATION.md`](AUTHENTICATION.md)