LA Referencia Platform - Changelog
----------

4.2.2 / 2023-11-13
==================
- Incremental entity indexing by lastUpdate parameter:  
example: `lareferencia-shell >index-entities --config-file-full-path entity-indexing-config.xml --last-update 2023-10-10T00:00:00  --indexer-name entityIndexerElasticJSON`


4.2.1 / 2023-10-10
==================
- Added: Incremental refacting harvest for OAI-PMH
- Added: Incremental validation stats changes
- Added: Optimization task for oaimetadata table

**Migration Notes**:
- Run database migrations: `lareferencia-shell > database-migrate` 
- Run full harvesting and validation for all repositories
- Run optimization task from shell `lareferencia-shell > optimize-metadata-store`
- Put lareferencia-shell/optimize-metadata-store.sh  on weekly cron job

4.2.0 / 2023-08-1
==================
- Added: Bugfixing release
- Preferred occurrences for entities
- Indexing plugin for entities update
- Statistics and reports for entity extraction and indexing
- Simple dc entity model for entity extraction

**Migration Notes**:
- Run database migrations: `lareferencia-shell > database-migrate`