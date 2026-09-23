# Entity Indexing Architecture (Elasticsearch/OpenSearch)

**Status:** current · **Last verified:** 2026-09-23

This document describes **how entity indexing works today**. It replaces the archived
[`archive/ANALISIS_INDEXACION_MULTITHREAD.md`](archive/ANALISIS_INDEXACION_MULTITHREAD.md), which described the former
buffer → distributor → writers pipeline (removed in commit `1b894e7`, 2025-11-09).

## Overview

- Implementation: `org.lareferencia.core.entity.indexing.elastic.JSONElasticEntityIndexerThreadedImpl` (`lareferencia-entity-lib`)
- Client: `opensearch-rest-high-level-client` 2.5.0 (REST API compatible with Elasticsearch 7.x; the compose stack bundles Elasticsearch 7.12.0)
- Triggered by the shell command `index-entities` (`EntityIndexingCommands`), by network indexing actions, or from the Admin UI
- RDF/VIVO triple-store indexing is provided separately by `EntityIndexerTDB1ThreadedImpl` / `EntityIndexerTDB2ThreadedImpl` (Jena)

## Execution Model

```
index(Entity) ──► capture UUID ──► enqueue async task
                                        │
              fixed pool (availableProcessors threads)
                                        │
            Semaphore(maxConcurrentTasks) ── backpressure
                                        │
        processEntityInTransaction(uuid)   (read-only REQUIRES_NEW tx)
                                        │
            index document ──► Phaser arrival / deregistration
```

- A fixed thread pool is created with `Runtime.getRuntime().availableProcessors()` threads.
- Backpressure is a `Semaphore` limiting concurrent in-flight tasks (`threads * 2` when auto).
- A `Phaser` tracks active indexing tasks; `AtomicLong` counters track produced / indexed / failed documents.
- `index(Entity)` only captures the entity UUID and enqueues an asynchronous task; the interface
  (`IEntityIndexer`) is unchanged.

## Per-Document Transaction

Each document is processed inside its own transaction:

- `processEntityInTransaction(UUID)` — propagation `REQUIRES_NEW`, isolation `READ_COMMITTED`,
  `readOnly = true`, timeout 30 s; entity data is loaded inside the transaction for lazy-loading safety.
- The transaction is closed with `rollback()` in a `finally` block — for read-only transactions this is
  equivalent to commit and avoids flushing.

## Configuration (all properties verified in code)

| Property | Default | Purpose |
|---|---|---|
| `elastic.host` | `localhost` | Endpoint host |
| `elastic.port` | `9200` | Endpoint port |
| `elastic.username` / `elastic.password` | `admin` / `admin` | Credentials (if `elastic.authenticate`) |
| `elastic.useSSL` | `false` | HTTPS |
| `elastic.authenticate` | `false` | Enable credentials |
| `elastic.indexer.max.retries` | `10` | Per-document retry attempts |
| `elastic.indexer.circuit.breaker.max.failures` | `10` | Failures before the breaker opens (fail-fast) |
| `elastic.indexer.circuit.breaker.reset.timeout.ms` | `60000` | Half-open reset window |
| `elastic.indexer.max.concurrent.tasks` | `0` (auto) | Semaphore permits (0 = `threads * 2`) |

Threading and buffering are **automatic** — there are no `writer.threads` or `buffer.size` properties
(an earlier design proposed them and a dead-letter queue; that design was never implemented, see
`archive/ANALISIS_INDEXACION_MULTITHREAD.md`).

Status reporting is emitted in logs as `=== INDEXING STATUS REPORT ===` blocks (no buffer/DLQ metrics).

## Operational Notes

- The Solr-based entity indexer (`EntityIndexerSolrImpl`) is disabled (`.java.disabled`) since the
  Spring Data Solr removal; see `lareferencia-entity-lib/src/main/java/org/lareferencia/core/entity/indexing/solr/README_SOLR_MIGRATION.md`.
- Indexers are exposed as `IEntityIndexer` beans (e.g. `entityIndexerElastic`, prototype scope) and can
  be listed with the shell command `list-indexers`.
- Soft-deleted entities are excluded from indexing; use `remove_deleted_entities_from_index` for cleanup —
  see [`ENTITY_DELETED_INDEXING.md`](ENTITY_DELETED_INDEXING.md).