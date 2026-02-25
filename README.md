# LA Referencia Platform

LA Referencia is a comprehensive platform for harvesting, processing, and indexing scholarly metadata from institutional and thematic repositories across Latin America. The platform provides advanced entity management, metadata validation, and search capabilities through SOLR/Elasticsearch and Vufind integraton.

## 🚀 Current Status

### Latest Stable Release: **v4.2.6**
The stable version 4.2.6 is tagged and ready for production use. This version provides:
- Full support for OAI-PMH harvesting
- Entity-based metadata processing
- Elasticsearch and Solr indexing
- PostgreSQL-based metadata storage
- Comprehensive validation and transformation pipelines

### Development Branch: **main** (v5.0 - Work in Progress)

The main branch is actively being developed for version 5.0, which includes significant architectural improvements and modernization:

#### 🔧 Major Upgrades
- **Spring Boot 3.5**: Migration from Spring Boot 2.x to 3.5
- **Jakarta EE**: Transition from javax to jakarta namespace
- **Dependency Updates**: All core dependencies updated to latest stable versions

#### 🗑️ Deprecated Features
- **Spring Data Solr**: Removed due to official discontinuation by Spring team
- **Solr Entity Indexing**: Elasticsearch is now the primary indexing engine
- **IBICT and RCAAP Contrib Modules**: API modules for Solr-based entity services are no longer supported
  - Code remains in repository but is excluded from compilation
  - Existing deployments should migrate to Elasticsearch-based APIs

#### ✨ New Features & Improvements

**Harvesting Statistics Storage**
- Migration from database to **SQLite files** for better performance and manageability
- Improved analytics capabilities with SQL compatibility while maintaining file-based isolation
- Reduced central database load and improved query performance with indexes

**Snapshot Logging System Refactoring**
- **New file-based snapshot logging**: Logs now stored as text files alongside Parquet data instead of database tables
- **Location**: `{basePath}/{NETWORK}/snapshots/snapshot_{id}/snapshot.log`
- **Format**: Plain text with timestamps `[2025-11-12 12:45:30.123] message`
- **Benefits**: 
  - No database dependency for logs
  - Easy to read and audit with standard text editors
  - Automatic directory creation and error handling
  - Thread-safe append operations
  - Consistent with filesystem-based storage architecture
- **API Compatibility**: Fully backward compatible - no changes needed for existing code using `addEntry()` and `deleteSnapshotLog()`

**Metadata Storage Optimization**
- **Gradual migration** from PostgreSQL to filesystem-based storage
- Better scalability for large metadata collections
- Improved backup and recovery processes

#### Storage Architecture Redesign (v5.0)

The platform introduces a hybrid **filesystem + database** storage strategy that dramatically improves performance and scalability:

| Component | Storage | Format | Purpose |
|-----------|---------|--------|---------|
| **Metadata XML** | Filesystem | GZIP compressed | Original harvested XML records |
| **OAI Records Catalog** | SQLite (DB) | `catalog.db` | Harvested metadata index with MD5 hashes |
| **Validation Records** | SQLite (DB) | `validation.db` | Validation results and rule violations |
| **Validation Statistics** | JSON (FS) | Text aggregates | Pre-computed validation metrics |
| **Snapshot Logs** | Text (FS) | Plain text with timestamps | Audit trail and debugging |
| **Snapshot Metadata** | PostgreSQL | Relational | Structural snapshot info |
| **Network Configuration** | PostgreSQL | Relational | Networks and repositories |
| **Entity Data** | PostgreSQL | Relational | Publications, Persons, Organizations |

**Key Benefits:**

- ✅ **Unified Storage**: Structured data in SQLite files for querying, with raw XML in filesystem
- ✅ **WAL Concurrency**: Write-Ahead Logging enables simultaneous reading and writing
- ✅ **Dynamic Validation**: Rule columns created on-the-fly based on validator configuration (no schema constraints)
- ✅ **~30-50% deduplication**: Identical XML metadata stored once (filesystem hashing)
- ✅ **Ultra-fast statistics**: <1ms queries via pre-computed JSON and indexed DB lookups
- ✅ **Thread-safe**: Connection pooling per database file
- ✅ **No transaction overhead**: Filesystem isolation avoids central DB locks
- ✅ **Filesystem isolation**: Each network in separate directory (`{basePath}/{NETWORK}/`)

**Directory Structure** (per snapshot):

```text
{basePath}/{NETWORK}/snapshots/snapshot_{ID}/
├── metadata.json                          ← Snapshot metadata (structured)
├── catalog/
│   └── catalog.db                         ← OAI records index (SQLite)
├── validation/
│   ├── validation.db                      ← Validation results & stats (SQLite)
│   └── validation-stats.json              ← Aggregated statistics (<1ms lookup)
└── snapshot.log                           ← Text audit trail

{basePath}/{NETWORK}/metadata/
├── A/B/C/ABCDEF123456789.xml.gz          ← Partitioned by hash (3 levels)
├── A/B/D/ABDABC987654321.xml.gz
└── ... (4,096 partitions for scale)
```

**Validation Schema** (nested RuleFacts):

- 1 row per record (not per fact)
- RuleFacts stored as nested list within record
- Each RuleFact includes: rule_id, is_valid, valid/invalid occurrences
- Reduces storage from ~1.5GB (flat) to ~180MB (nested) for 100k records

For complete reference, see [ALMACENAMIENTO_REFERENCIA_RAPIDA.md](docs/ALMACENAMIENTO_REFERENCIA_RAPIDA.md).

**Entity Processing Enhancements**

- Simplified transactional model for entity loading and processing
- Multiple bug fixes in entity relationship management
- Optimized read-only transactions for better performance
- Improved lazy loading handling

**Elasticsearch Indexing**

- **New multi-threaded entity indexer** implementation
- Direct indexing architecture (removed buffer→distributor→writers pipeline)
- Natural backpressure using database as bottleneck
- Circuit breaker pattern for fail-fast behavior
- Configurable concurrency control with semaphores
- Automatic resource cleanup on completion
- Significant performance improvements for large-scale indexing

**Dynamic Schema Generation & I18n**

- **Dynamic Forms**: Validation and transformation rule forms are now generated dynamically from Java classes using custom annotations (`@ValidatorRuleMeta`, `@SchemaProperty`).
- **Internationalization (I18n)**: Full support for localized rule titles, descriptions, and help texts (English, Spanish, Portuguese).
- **Reduced Maintenance**: Eliminated static JSON schema files; frontend stays automatically synchronized with backend code.
- **Extensibility**: New rules are automatically exposed to the UI simply by implementing the interface and adding annotations.

**File-Based Authentication System**

- **Dual Authentication**: Supports both Form Login (web form) and HTTP Basic Auth for API access
- **File-Based Users**: User credentials stored in `config/users.properties` with BCrypt-encrypted passwords
- **Auto-Reload**: Automatic user file reload when a user is not found in cache (add users without restart)
- **Role-Based Access**: All endpoints require `ADMIN` role; configurable per-endpoint access control
- **Python CLI Tool**: Includes `add-user.py` script for easy user management via command line or interactive mode
- **Security**: 
  - BCrypt password hashing with `$2a$` prefix (Java-compatible)
  - In-memory user cache with copy-on-read to prevent credential corruption
  - Secure logout with session invalidation
- **Documentation**: Complete setup guide in [AUTENTICACION_FILE_BASED.md](docs/AUTENTICACION_FILE_BASED.md)

**Core Library Package Structure Refactoring (v5.0)**

- **Ultra-simplified organization**: Replaced complex `backend.*` + `core.*` split with clean 7-package structure
- **New structure** (`org.lareferencia.core.*`):

```text
├── domain/       - Domain models and entities
├── repository/   - Data access (JPA + Parquet)
├── service/      - Business logic (harvesting, validation, indexing, management)
├── metadata/     - Metadata storage abstraction
├── worker/       - Async processors (harvesting, validation, indexing, management)
├── task/         - Task scheduling and coordination
└── util/         - Shared utilities
```

- **Benefits**:
  - ✅ Intuitive navigation (max 2 package levels)
  - ✅ Functional organization by domain (harvesting, validation, indexing)
  - ✅ Reduced cognitive load for new developers
  - ✅ Easier to find related code (all harvesting code together, etc.)
  - ✅ Zero breaking changes to public APIs
- **Backward Compatibility**: All external APIs unchanged; migration is import-only for dependent projects
- **Migration Support**: Automated scripts and detailed migration guide provided in [PACKAGE_MIGRATION_GUIDE.md](docs/PACKAGE_MIGRATION_GUIDE.md)

## 📋 System Requirements

- **Java**: OpenJDK 17 or later
- **Maven**: 3.8.x or later
- **PostgreSQL**: 12.x or later
- **Elasticsearch**: 7.x or 8.x
- **Memory**: Minimum 4GB RAM (8GB recommended for production)

## 🏗️ Architecture

The platform is organized as a multi-module Maven project with the following main components:

### Core Modules

#### **lareferencia-core-lib**
Core library module providing fundamental domain models, metadata processing, validation, transformation, and OAI-PMH harvesting capabilities.

**Key Features:**
- OAI-PMH 2.0 protocol implementation for metadata harvesting
- Extensible validation and transformation rule engine
- Metadata processing framework (XML/JSON support)
- Worker framework for asynchronous job execution
- Validation statistics and reporting (SQLite storage in v5.0)

**Architecture (v5.0)**:
- **Simplified package structure**: Reorganized from `backend.*` to `core.*` with 7 core packages:
  - `domain/` - Domain models (entities, value objects)
  - `repository/` - Data access layer (JPA + SQLite + Parquet)
  - `service/` - Business logic (organized by functionality)
  - `metadata/` - Metadata storage abstraction
  - `worker/` - Asynchronous job processing (organized by functionality)
  - `task/` - Task scheduling and coordination
  - `util/` - Shared utilities
- **Ultra-simple navigation**: Maximum 2 levels of package depth
- **Functional organization**: Workers and services organized by domain (harvesting, validation, indexing, management)
- **Zero breaking changes**: All public APIs remain identical, only internal package organization changed

**Migration Guide for Dependent Projects:**
If your project depends on `lareferencia-core-lib`, imports have changed:
- ❌ Old: `org.lareferencia.backend.*`
- ✅ New: `org.lareferencia.core.*`

[See detailed migration guide](docs/PACKAGE_MIGRATION_GUIDE.md) with automated scripts.

[View detailed documentation](https://github.com/lareferencia/lareferencia-core-lib)

#### **lareferencia-entity-lib**
Entity management, relationship processing, and multi-engine indexing library for scholarly metadata.

**Key Features:**
- Entity-centric data model (Publications, Persons, Organizations, Projects)
- Bidirectional relationship management
- **NEW**: Multi-threaded Elasticsearch indexer (v5.0)
- Triple store indexing (VIVO-compatible RDF)
- Semantic identifier support (DOI, ORCID, ROR, etc.)
- Provenance tracking at field level
- High-performance LRU caching

**Architecture Highlight (v5.0):**
- Direct database-to-Elasticsearch pipeline
- Configurable concurrency with semaphore backpressure
- Circuit breaker pattern for fault tolerance
- Automatic resource cleanup
- Real-time indexing statistics

[View detailed documentation](https://github.com/lareferencia/lareferencia-entity-lib)

#### **lareferencia-dark-lib**
DARK (descentrilized ARK) library for persistent identifier minting and management.

**Key Features:**
- Persistent identifier (PID) minting and registration
- OAI identifier to DARK identifier mapping
- Credential management for DARK services
- Worker integration for batch PID assignment

[View detailed documentation](https://github.com/lareferencia/lareferencia-dark-lib)

### Application Modules

#### **lareferencia-lrharvester-app**
Main web application for OAI-PMH metadata harvesting, validation, transformation, and publication.

**Key Features:**
- Web-based dashboard for network management
- National repository network configuration
- OAI-PMH harvesting (full and incremental)
- Metadata validation and transformation pipelines
- **NEW**: Statistics storage in SQLite format (v5.0)
- Entity extraction and relationship mapping
- Elasticsearch indexing
- Multi-language UI (Spanish/English)

**Access:** `http://localhost:8080/harvester`

[View detailed documentation](https://github.com/lareferencia/lareferencia-lrharvester-app)

#### **lareferencia-entity-rest**
RESTful API for accessing and searching scholarly entities indexed by LA Referencia.

**Key Features:**
- Full-text entity search across all types
- Semantic identifier resolution (DOI, ORCID, ROR)
- Relationship navigation (author, affiliation, funding, citations)
- Faceted search by type, country, institution
- OpenAPI/Swagger documentation

**Access:** `http://localhost:8081/entity-api`  
**Swagger UI:** `http://localhost:8081/entity-api/swagger-ui.html`

[View detailed documentation](https://github.com/lareferencia/lareferencia-entity-rest)

#### **lareferencia-dashboard-rest**
RESTful API providing monitoring, statistics, and administrative data for dashboards and reporting.

**Key Features:**
- Network statistics and growth metrics
- Repository status monitoring
- Harvest event tracking and logs
- Validation statistics and quality indicators
- OA Broker event management

**Access:** `http://localhost:8082/dashboard-api`  
**Swagger UI:** `http://localhost:8082/dashboard-api/swagger-ui.html`

[View detailed documentation](https://github.com/lareferencia/lareferencia-dashboard-rest)

### Infrastructure Modules

#### **lareferencia-indexing-filters-lib**
Field occurrence filtering library for controlling which metadata field values are indexed to search engines.

**Key Features:**
- Configurable field occurrence limits
- Filter by field name and occurrence count
- Integration with entity indexing pipeline
- Index size optimization

[View detailed documentation](https://github.com/lareferencia/lareferencia-indexing-filters-lib)

#### **lareferencia-oclc-harvester**
Modified version of OCLC Harvester2 library (2006 version) adapted for LA Referencia.

**Purpose:** Low-level OAI-PMH protocol support used internally by core-lib.

[View detailed documentation](https://github.com/lareferencia/lareferencia-oclc-harvester)

#### **lareferencia-shell**
Interactive command-line shell for administrative and maintenance operations.

**Key Features:**
- Spring Shell-based interactive CLI
- Administrative commands for platform maintenance
- Direct database access utilities
- Entity processing tools
- Non-interactive mode for scripting

[View detailed documentation](https://github.com/lareferencia/lareferencia-shell)

#### **lareferencia-shell-entity-plugin**
Entity-specific commands plugin for lareferencia-shell.

**Purpose:** Extends shell with entity management commands.

### Deprecated Modules (Not Compiled in v5.0)

#### ⚠️ **lareferencia-contrib-ibict**
IBICT-specific Solr extensions (DISCONTIUED)

**Status:** No longer compiled. Spring Data Solr discontinued. Migrate to `lareferencia-entity-rest`.

[View deprecation notice](https://github.com/lareferencia/lareferencia-contrib-ibict)

#### ⚠️ **lareferencia-contrib-rcaap**
RCAAP-specific Solr extensions (DISCONTINUED)

**Status:** No longer compiled. Spring Data Solr discontinued. Migrate to `lareferencia-entity-rest`.

[View deprecation notice](https://github.com/lareferencia/lareferencia-contrib-rcaap)


## 🚀 Quick Start

### Building the Platform

```bash
# Clone the repository with submodules
git clone --recursive https://github.com/lareferencia/lareferencia-platform.git
cd lareferencia-platform

# Build all modules general implementation
./build.sh lareferencia

# Or build specific contribution (e.g., ibict)
./build.sh ibict
```

## 📦 Git Submodules

This project uses Git submodules for modular development. All submodules are tracked separately and can be developed independently.

### Unified CLI: `githelper`

The repository includes a single integrated CLI in the project root: `./githelper`.

```bash
# Show parent/submodule status
./githelper status

# Switch parent branch and move each submodule only if that branch exists there
./githelper switch v5-semantic-indexing

# Pull parent branch and then submodules:
# - same parent branch if it exists in the submodule
# - otherwise the submodule current branch
./githelper pull

# Create the parent branch name in specific modules
./githelper branch create --modules lareferencia-core-lib,lareferencia-shell

# Convert submodule URLs from SSH to HTTPS (for users without SSH access)
./githelper url rewrite --to https
```

### Checkout Specific Tagged Version (release workflow)

```bash
# Checkout stable version 4.2.6
git checkout 4.2.6
git submodule update --init --recursive
```

## 🔧 Configuration

### Configuration Directory Structure

The platform uses a **flexible configuration system** based on a configurable base directory. Each application module (`lareferencia-lrharvester-app`, `lareferencia-shell`, `lareferencia-dashboard-rest`, `lareferencia-entity-rest`) has its own `config/` directory.

**Standard Configuration Directory Structure:**

```
config/
├── application.properties          # Local/Private (gitignored)
├── application.properties.model    # Template/Reference (versioned)
├── application.properties.d/       # Deep/Modular configuration (versioned)
│   ├── 01-database.properties
│   ├── 02-storage.properties
│   ├── 03-elasticsearch.properties
│   └── ...
├── beans/
│   ├── mdformats.xml              # Metadata format definitions
│   └── fingerprint.xml            # Fingerprint configuration
├── processes/                      # Flowable BPMN process definitions
│   └── *.bpmn20.xml
├── i18n/                          # Internationalization files
│   ├── messages.properties
│   └── messages_es.properties
└── users.properties               # File-based authentication (lrharvester-app)
```

### The Golden Rule

- **`application.properties`**: Local/Private configuration (gitignored, not versioned)
- **`application.properties.model`**: Template with all available properties and documentation (versioned)
- **`application.properties.d/*.properties`**: Modular configuration fragments loaded automatically (versioned)

**Action Required**: When adding a new configuration property to `.properties`, you **MUST** also add it to `.properties.model` with documentation.

### Deep Configuration (`application.properties.d/`)

The `.d` directory contains modular, granular configuration files that are automatically loaded by Spring Boot. This allows:

- **Separation of concerns**: Database, storage, indexing configs in separate files
- **Incremental loading**: Files loaded in alphanumeric order (01-, 02-, etc.)
- **Version control friendly**: Each module can be tracked independently
- **Environment overrides**: Local `application.properties` can override any `.d` setting

### Configuration Directory Resolution

You can customize the configuration base directory using the `app.config.dir` system property:

```bash
# Default: uses ./config directory
java -jar lareferencia-shell.jar

# Custom relative path
java -Dapp.config.dir=../shared-config -jar lareferencia-shell.jar

# Absolute path
java -Dapp.config.dir=/etc/lrharvester/config -jar lareferencia-shell.jar

# Docker example
java -Dapp.config.dir=/app/config -jar harvester.jar
```

**See**: [CONFIG_DIRECTORY.md](docs/CONFIG_DIRECTORY.md) for deployment examples (Docker, Kubernetes).

### Elasticsearch Configuration (v5.0)

Configure Elasticsearch in `application.properties` or `application.properties.d/03-elasticsearch.properties`:

```properties
elastic.host=localhost
elastic.port=9200
elastic.indexer.max.concurrent.tasks=16
elastic.indexer.circuit.breaker.max.failures=10
```

### SQLite Storage Configuration (v5.0)

Storage base path for SQLite databases (catalog, validation):

```properties
store.basepath=/tmp/data/
catalog.sqlite.wal-mode=true
```

## 🧪 Testing

```bash
# Run all tests
mvn test

# Run tests for specific module
cd lareferencia-entity-lib
mvn test
```

## 📝 Migration Guide: v4.2.6 → v5.0

### Required Actions

1. **Update Java**: Migrate to Java 17+
2. **Update Spring Boot**: Configuration changes for Spring Boot 3.x
3. **Migrate from javax to jakarta**: Update all imports
4. **Remove Solr Dependencies**: Migrate to Elasticsearch for entity indexing
5. **Update Database Schema**: New schema for optimized entity storage
6. **Configure Storage**: Set up filesystem and SQLite storage for harvest statistics

### Breaking Changes

- Solr entity indexing APIs removed
- IBICT/RCAAP contrib modules no longer compiled
- Configuration property names updated for Spring Boot 3.x
- Entity indexer implementation completely rewritten

## 🤝 Contributing

Contributions to LA Referencia are welcome! Whether you're fixing bugs, improving documentation, or proposing new features, your help is appreciated.

### How to Contribute

1. **Fork the repository** and create a feature branch
   ```bash
   git checkout -b feature/amazing-feature
   ```

2. **Make your changes** following the project's coding standards
   - Write clear, documented code
   - Add tests for new functionality
   - Ensure all existing tests pass

3. **Commit your changes** with descriptive messages
   ```bash
   git commit -m 'Add amazing feature: description of what it does'
   ```

4. **Push to your branch**
   ```bash
   git push origin feature/amazing-feature
   ```

5. **Open a Pull Request** against the main branch
   - Describe your changes clearly
   - Reference any related issues
   - Include test results

### Coding Standards

- **Java**: Follow standard Java conventions
- **Spring Boot**: Use Spring best practices and annotations
- **Tests**: Write unit and integration tests for new code
- **Documentation**: Update README files and JavaDoc comments
- **License**: All contributions must be compatible with AGPL-3.0

### Before Submitting

- [ ] Code compiles without errors
- [ ] All tests pass (`mvn test`)
- [ ] New code has appropriate test coverage
- [ ] Documentation is updated
- [ ] Commit messages are clear and descriptive

### Code of Conduct

Please be respectful and constructive in all interactions with the community.

## 📄 License

This project is licensed under the **GNU Affero General Public License v3.0 (AGPL-3.0)**.

The AGPL-3.0 is a free, copyleft license for software and other kinds of works, specifically designed to ensure cooperation with the community in the case of network server software.

**Key License Points:**
- **Freedom to use**: You can use this software for any purpose
- **Freedom to study and modify**: Source code is available and can be modified
- **Freedom to share**: You can distribute copies of the software
- **Copyleft**: Modified versions must also be released under AGPL-3.0
- **Network use provision**: Users who interact with the software over a network must be able to receive the source code

For the complete license text, see the [LICENSE.txt](LICENSE.txt) file in the repository root.

**Important:** If you deploy this software on a network server where users interact with it remotely, you must make the complete source code (including any modifications) available to those users.

## 📧 Support and Contact

For technical support, questions, bug reports, or contributions, please contact the LA Referencia technical team:

**Email**: [soporte@lareferencia.redclara.net](mailto:soporte@lareferencia.redclara.net)

### What to Include in Support Requests

When requesting support, please include:
- **Platform version**: Specify if you're using v4.2.6 (stable) or v5.0 (development)
- **Module affected**: Which component is experiencing issues
- **Error logs**: Relevant log excerpts showing the problem
- **Configuration**: Relevant configuration snippets (remove sensitive data)
- **Steps to reproduce**: Clear description of how to reproduce the issue

### Community

- **Website**: [https://www.lareferencia.info](https://www.lareferencia.info)
- **GitHub**: [https://github.com/lareferencia](https://github.com/lareferencia)

## 🔗 Links

- **Website**: [https://www.lareferencia.info](https://www.lareferencia.info)
- **Issue Tracker**: [GitHub Issues](https://github.com/lareferencia/lareferencia-platform/issues)
- **Source Code**: [GitHub Repository](https://github.com/lareferencia/lareferencia-platform)

---

**Note**: For production deployments, always use tagged releases (v4.2.6). The main branch contains ongoing development for v5.0 and may include unstable features.

**License**: GNU Affero General Public License v3.0 (AGPL-3.0)  
**Contact**: soporte@lareferencia.redclara.net
