# LA Referencia Platform

LA Referencia is a comprehensive platform for harvesting, processing, and indexing scholarly metadata from institutional and thematic repositories across Latin America. The platform provides advanced entity management, metadata validation, and search capabilities through Elasticsearch.

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
- Migration from database to **Parquet files** for better performance and scalability
- Improved analytics capabilities with columnar storage format
- Reduced database load and improved query performance

**Metadata Storage Optimization**
- **Gradual migration** from PostgreSQL to filesystem-based storage
- Better scalability for large metadata collections
- Improved backup and recovery processes

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
- Validation statistics and reporting (Parquet storage in v5.0)

[View detailed documentation](lareferencia-core-lib/README.md)

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

[View detailed documentation](lareferencia-entity-lib/README.md)

#### **lareferencia-dark-lib**
DARK (descentrilized ARK) library for persistent identifier minting and management.

**Key Features:**
- Persistent identifier (PID) minting and registration
- OAI identifier to DARK identifier mapping
- Credential management for DARK services
- Worker integration for batch PID assignment

[View detailed documentation](lareferencia-dark-lib/README.md)

### Application Modules

#### **lareferencia-lrharvester-app**
Main web application for OAI-PMH metadata harvesting, validation, transformation, and publication.

**Key Features:**
- Web-based dashboard for network management
- National repository network configuration
- OAI-PMH harvesting (full and incremental)
- Metadata validation and transformation pipelines
- **NEW**: Statistics storage in Parquet format (v5.0)
- Entity extraction and relationship mapping
- Elasticsearch indexing
- Multi-language UI (Spanish/English)

**Access:** `http://localhost:8080/harvester`

[View detailed documentation](lareferencia-lrharvester-app/README.md)

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

[View detailed documentation](lareferencia-entity-rest/README.md)

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

[View detailed documentation](lareferencia-dashboard-rest/README.md)

### Infrastructure Modules

#### **lareferencia-indexing-filters-lib**
Field occurrence filtering library for controlling which metadata field values are indexed to search engines.

**Key Features:**
- Configurable field occurrence limits
- Filter by field name and occurrence count
- Integration with entity indexing pipeline
- Index size optimization

[View detailed documentation](lareferencia-indexing-filters-lib/README.md)

#### **lareferencia-oclc-harvester**
Modified version of OCLC Harvester2 library (2006 version) adapted for LA Referencia.

**Purpose:** Low-level OAI-PMH protocol support used internally by core-lib.

[View detailed documentation](lareferencia-oclc-harvester/README.md)

#### **lareferencia-shell**
Interactive command-line shell for administrative and maintenance operations.

**Key Features:**
- Spring Shell-based interactive CLI
- Administrative commands for platform maintenance
- Direct database access utilities
- Entity processing tools
- Non-interactive mode for scripting

[View detailed documentation](lareferencia-shell/README.md)

#### **lareferencia-shell-entity-plugin**
Entity-specific commands plugin for lareferencia-shell.

**Purpose:** Extends shell with entity management commands.

### Deprecated Modules (Not Compiled in v5.0)

#### ⚠️ **lareferencia-contrib-ibict**
IBICT-specific Solr extensions (DISCONTIUED)

**Status:** No longer compiled. Spring Data Solr discontinued. Migrate to `lareferencia-entity-rest`.

[View deprecation notice](lareferencia-contrib-ibict/README.md)

#### ⚠️ **lareferencia-contrib-rcaap**
RCAAP-specific Solr extensions (DISCONTINUED)

**Status:** No longer compiled. Spring Data Solr discontinued. Migrate to `lareferencia-entity-rest`.

[View deprecation notice](lareferencia-contrib-rcaap/README.md)


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


### Update All Submodules

```bash
git submodule update --remote --merge
```

### Checkout Specific Version

```bash
# Checkout stable version 4.2.6
git checkout 4.2.6
git submodule update --init --recursive
```

## 🔧 Configuration

Configuration files are located in each application module under `src/main/resources/` or in external configuration directories.

Key configuration files:
- `application.properties`: Main application configuration
- `application-*.properties`: Environment-specific configurations
- Entity indexing configurations in XML format

### Elasticsearch Configuration

For version 5.0, configure Elasticsearch settings in `application.properties`:

```properties
elastic.host=localhost
elastic.port=9200
elastic.indexer.max.concurrent.tasks=16
elastic.indexer.circuit.breaker.max.failures=10
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
6. **Configure Parquet Storage**: Set up filesystem storage for harvest statistics

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
