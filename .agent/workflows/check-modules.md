---
description: Check all modules for updates and consistency
---

When performing a project-wide update or "sweep", verify consistency across active modules, paying attention to their dependencies and responsibilities.

## Core Libraries (High Impact)
Changes here propagate to ALL applications.

- [ ] **`lareferencia-core-lib`**: The Heart (Domain, Harvesting, Validation, Workers).
    - *Check:* If changing workers or domain objects, verify `lrharvester-app` and `shell` compatibility.
- [ ] **`lareferencia-entity-lib`**: Entities & Indexing.
    - *Check:* If changing indexing logic, verify `entity-rest` and `shell-entity-plugin`.
- [ ] **`lareferencia-indexing-filters-lib`**: Indexing filters.
- [ ] **`lareferencia-dark-lib`**: Persistent Identifiers (DARK).

## Applications (Runnables)
- [ ] **`lareferencia-lrharvester-app`** (Main Web UI):
    - *Check:* `config/application.properties` vs `.model`.
    - *Check:* UI functionality if Core/Entity libs changed.
- [ ] **`lareferencia-shell`** (CLI Admin):
    - *Check:* Commands execution if Core/Entity libs changed.
    - *Check:* `config/application.properties` vs `.model`.
- [ ] **`lareferencia-entity-rest`** (Public API):
    - *Check:* API contract (Swagger) if Entity lib changed.
    - *Check:* `config/application.properties` vs `.model`.
- [ ] **`lareferencia-dashboard-rest`** (Stats API):
    - *Check:* `config/application.properties` vs `.model`.

## Configuration Consistency Sweep
1. [ ] **Properties sync**: Ensure any new key in `application.properties` is added to `application.properties.model` in ALL apps.
2. [ ] **Deep config**: Check `application.properties.d/` for internal tuning changes.
3. [ ] **Dependency versions**: Check root `pom.xml` limits.

## Deprecated Layout
- Ignore `lareferencia-contrib-*` unless specifically asked.
