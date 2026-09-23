# Documentation Archive

Historical documents moved here on **2026-09-23** during the documentation overhaul
(see [`../PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md`](../PROPUESTA_ACTUALIZACION_DOCUMENTACION_2026-09-23.md)).
They are kept as decision records / analysis snapshots and are **not** maintained.
Each file carries a banner explaining why it was archived and what replaced it.

| Document | Reason | Replaced by |
|---|---|---|
| `ANALISIS_INDEXACION_MULTITHREAD.md` | Describes the buffer→distributor→writers pipeline removed in commit `1b894e7` (2025-11-09) | `docs/ENTITY_INDEXING_ARCHITECTURE.md` |
| `ARQUITECTURA_CATALOGO_SQLITE.md` | Pre-incremental catalog schema; superseded by the incremental implementation (commit `7cf2a01`, 2026-09-04) | `docs/ISSUE_INCREMENTAL_RECORD_PROCESSING.md` |
| `ANALISIS_REDUNDANCIA_VALIDACION.md` | Its central claim ("no incremental state machine") was superseded on 2026-09-04 | `docs/ISSUE_INCREMENTAL_RECORD_PROCESSING.md` |
| `ANALISIS_OPTIMIZACION_TRANSACCIONAL_READONLY.md` | Proposal already implemented in code (read-only `REQUIRES_NEW` transactions) | `docs/REFACTORING_TRANSACCIONAL.md` |
| `HARVESTER_ADMIN_WEB_V5_TECHNICAL_PLAN.md` | Plan executed: React admin web + `/api/v5` merged to `main` (2026-08→09) | `docs/HARVESTER_ADMIN_WEB_V5_BACKLOG.md` |
| `changelog.md` | Unmaintained since 2024-01; changelog moved to GitHub Releases + tags | [GitHub Releases](https://github.com/lareferencia/lareferencia-platform/releases) |
| `PACKAGE_MIGRATION_GUIDE.md` | Content merged into `REFACTORING_PACKAGE_STRUCTURE.md` (package list verified against `core-lib`) on 2026-09-23 | `docs/REFACTORING_PACKAGE_STRUCTURE.md` |

Do not add new content here without a banner explaining the archiving reason.