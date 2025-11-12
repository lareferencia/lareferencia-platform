# Plan de Refactoring: Reorganización de Paquetes - lareferencia-core-lib

**Fecha**: 12 de noviembre de 2025  
**Objetivo**: Eliminar el paquete `backend` y reorganizar todo bajo `core` con una estructura ultra-simple

---

## 1. ANÁLISIS DE LA ESTRUCTURA ACTUAL

### 1.1 Problemas Identificados

1. **Separación artificial**: `backend` vs `core` no tiene sentido semántico claro
2. **Mezcla de responsabilidades**: Domain models mezclados con diferentes tecnologías (JPA, Parquet)
3. **Validación fragmentada**: Lógica de validación en múltiples paquetes
4. **Workers dispersos**: Algunos en `backend.workers`, otros en `core.harvester.workers`
5. **Jerarquía profunda**: Múltiples niveles de subcarpetas dificultan navegación

---

## 2. PROPUESTA DE NUEVA ESTRUCTURA

### 2.1 Principios de Diseño

1. **Maximum Simplicity**: Jerarquía mínima, máximo 2 niveles de profundidad
2. **Functional Organization**: Dentro de cada capa técnica, organizar por funcionalidad (harvesting, validation, indexing)
3. **Clear Separation**: Solo 7 paquetes principales en el root
4. **No Structural Changes**: Solo mover clases, NO crear/eliminar/renombrar
5. **Preserve Interfaces**: Mantener todas las interfaces existentes con prefijo `I`

### 2.2 Nueva Estructura Propuesta

```
org.lareferencia.core/
│
├── domain/                           # 📦 MODELOS DE DOMINIO
│   ├── Network.java
│   ├── NetworkSnapshot.java
│   ├── NetworkSnapshotLog.java
│   ├── Validator.java
│   ├── Transformer.java
│   ├── SnapshotValidationStats.java
│   ├── RecordValidation.java
│   ├── RuleFact.java
│   └── ...
│
├── repository/                       # 📦 REPOSITORIOS
│   ├── jpa/
│   │   ├── NetworkRepository.java
│   │   ├── SnapshotRepository.java
│   │   ├── OAIRecordRepository.java
│   │   ├── ValidatorRepository.java
│   │   └── TransformerRepository.java
│   │
│   └── parquet/
│       ├── OAIRecord.java                          # Modelo Parquet
│       ├── RecordValidation.java                   # Modelo Parquet
│       ├── RuleFact.java                           # Modelo Parquet
│       ├── SnapshotValidationStats.java            # Modelo Parquet
│       ├── OAIRecordParquetRepository.java
│       ├── ValidationRecordManager.java
│       ├── SnapshotMetadataManager.java
│       └── ValidationStatParquetRepository.java
│
├── service/                          # 📦 SERVICIOS
│   ├── harvesting/
│   │   └── HarvestingService.java
│   │
│   ├── validation/
│   │   ├── IValidationStatisticsService.java      # Interfaz
│   │   ├── ValidationService.java
│   │   ├── TransformationService.java
│   │   └── ValidationStatisticsParquetService.java
│   │
│   ├── indexing/
│   │   └── IndexingService.java
│   │
│   └── management/
│       ├── SnapshotLogService.java
│       └── NetworkCleanupService.java
│
├── metadata/                         # 📦 METADATA
│   ├── IMetadataStore.java
│   ├── ISnapshotStore.java
│   ├── MetadataStoreFSImpl.java
│   ├── SnapshotStoreImpl.java
│   └── SnapshotMetadata.java
│
├── worker/                           # 📦 WORKERS
│   ├── BaseWorker.java
│   ├── WorkerContext.java
│   ├── IPaginator.java              # Interfaz
│   ├── OAIRecordParquetWorker.java
│   │
│   ├── harvesting/
│   │   ├── IHarvester.java          # Interfaz
│   │   ├── HarvestingWorker.java
│   │   └── OCLCHarvesterAdapter.java
│   │
│   ├── validation/
│   │   ├── IValidator.java          # Interfaz
│   │   ├── ITransformer.java        # Interfaz
│   │   ├── ValidationWorker.java
│   │   └── XPathRuleEvaluator.java
│   │
│   ├── indexing/
│   │   ├── IndexerWorker.java
│   │   └── SolrIndexer.java
│   │
│   └── management/
│       └── NetworkCleanWorker.java
│   │   ├── ITransformer.java
│   │   └── XPathRuleEvaluator.java
│   │
│   ├── indexing/
│   │   ├── IndexerWorker.java
│   │   └── SolrIndexer.java
│   │
│   └── management/
│       └── CleanupWorker.java
│
├── task/                             # 📦 TASK SCHEDULING
│   ├── TaskManager.java
│   ├── NetworkAction.java
│   └── NetworkActionManager.java
│
└── util/                             # 📦 UTILIDADES
    ├── PathUtils.java
    ├── DateHelper.java
    ├── XMLHelper.java
    ├── HashCalculator.java
    └── ParquetUtils.java
```

---

## 3. JUSTIFICACIÓN DE LA ESTRUCTURA

### 3.1 Solo 7 Paquetes Raíz

La estructura se reduce a exactamente **7 paquetes raíz**, cada uno con una responsabilidad clara:

| Paquete | Responsabilidad | Contenido |
|---------|----------------|-----------|
| `domain/` | Modelos de negocio | Entidades JPA actuales (Network, Validator, etc.) |
| `repository/` | Acceso a datos | `jpa/` (Spring Data) + `parquet/` (Managers) |
| `service/` | Lógica de negocio | Por funcionalidad: harvesting, validation, indexing, management |
| `metadata/` | Almacenamiento XML | Interfaces + implementación filesystem |
| `worker/` | Procesamiento asíncrono | BaseWorker + por funcionalidad |
| `task/` | Scheduling | TaskManager + coordinación |
| `util/` | Utilidades | Helpers compartidos |

### 3.2 Organización Funcional Interna

Tanto `service/` como `worker/` se organizan internamente por **funcionalidad**:

- **`harvesting/`** - Todo lo relacionado con cosecha OAI-PMH
- **`validation/`** - Todo lo relacionado con validación y transformación
- **`indexing/`** - Todo lo relacionado con indexación en Solr
- **`management/`** - Gestión de snapshots y limpieza

### 3.3 Ventajas

**Extrema Simplicidad**:
- ✅ Solo 7 carpetas en el root
- ✅ Máximo 2 niveles de profundidad (ej: `service/validation/ValidationService.java`)
- ✅ Navegación mental inmediata

**Sin Sobre-ingeniería**:
- ❌ No hay subcarpetas `entity/`, `model/`, `adapter/`, `contract/`
- ❌ No hay interfaces abstractas innecesarias tipo Port/Adapter
- ❌ No hay capa de "aplicación" con DTOs

**Funcionalidad Visible**:
- Si buscas harvesting: `service/harvesting/` y `worker/harvesting/`
- Si buscas validation: `service/validation/` y `worker/validation/`
- Todo relacionado con una funcionalidad está junto

**Pragmática**:
- Los modelos JPA van directo en `domain/` (sin carpeta `entity/`)
- Los repositorios van directo en `repository/jpa/` o `repository/parquet/`
- Spring Data ya provee las abstracciones necesarias

---

## 4. MAPEO DE MIGRACIÓN

### 4.1 Tabla de Correspondencias

| Actual | Nuevo | Acción |
|--------|-------|--------|
| **DOMAIN** | | |
| `backend.domain.Network` | `core.domain.Network` | Mover |
| `backend.domain.NetworkSnapshot` | `core.domain.NetworkSnapshot` | Mover |
| `backend.domain.NetworkSnapshotLog` | `core.domain.NetworkSnapshotLog` | Mover |
| `backend.domain.Validator` | `core.domain.Validator` | Mover |
| `backend.domain.Transformer` | `core.domain.Transformer` | Mover |
| `backend.domain.OAIRecord` (JPA) | `core.domain.OAIRecord` | Mover |
| `backend.domain.parquet.OAIRecord` | `core.repository.parquet.OAIRecord` | Mover (mantener en parquet) |
| `backend.domain.parquet.SnapshotValidationStats` | `core.repository.parquet.SnapshotValidationStats` | Mover (mantener en parquet) |
| `backend.domain.parquet.RecordValidation` | `core.repository.parquet.RecordValidation` | Mover (mantener en parquet) |
| `backend.domain.parquet.RuleFact` | `core.repository.parquet.RuleFact` | Mover (mantener en parquet) |
| **REPOSITORY** | | |
| `backend.repositories.jpa.NetworkRepository` | `core.repository.jpa.NetworkRepository` | Mover |
| `backend.repositories.jpa.SnapshotRepository` | `core.repository.jpa.SnapshotRepository` | Mover |
| `backend.repositories.jpa.OAIRecordRepository` | `core.repository.jpa.OAIRecordRepository` | Mover |
| `backend.repositories.jpa.ValidatorRepository` | `core.repository.jpa.ValidatorRepository` | Mover |
| `backend.repositories.jpa.TransformerRepository` | `core.repository.jpa.TransformerRepository` | Mover |
| `backend.repositories.parquet.OAIRecordParquetRepository` | `core.repository.parquet.OAIRecordParquetRepository` | Mover |
| `backend.repositories.parquet.ValidationRecordManager` | `core.repository.parquet.ValidationRecordManager` | Mover |
| `backend.repositories.parquet.SnapshotMetadataManager` | `core.repository.parquet.SnapshotMetadataManager` | Mover |
| `backend.repositories.parquet.ValidationStatParquetRepository` | `core.repository.parquet.ValidationStatParquetRepository` | Mover |
| **SERVICE** | | |
| `backend.services.ValidationService` | `core.service.validation.ValidationService` | Mover |
| `backend.services.SnapshotLogService` | `core.service.management.SnapshotLogService` | Mover |
| `backend.validation.IValidationStatisticsService` | `core.service.validation.IValidationStatisticsService` | Mover |
| `backend.validation.ValidationStatisticsParquetService` | `core.service.validation.ValidationStatisticsParquetService` | Mover |
| **WORKER** | | |
| `backend.workers.validator.ValidationWorker` | `core.worker.validation.ValidationWorker` | Mover |
| `backend.workers.indexer.IndexerWorker` | `core.worker.indexing.IndexerWorker` | Mover |
| `backend.workers.downloader.*` | `core.worker.harvesting.*` | Mover |
| `core.harvester.workers.HarvestingWorker` | `core.worker.harvesting.HarvestingWorker` | Mover |
| `core.worker.BaseWorker` | `core.worker.BaseWorker` | Sin cambios (ya está en root de worker) |
| `core.worker.WorkerContext` | `core.worker.WorkerContext` | Sin cambios |
| `core.worker.IPaginator` | `core.worker.IPaginator` | Sin cambios |
| `core.worker.OAIRecordParquetWorker` | `core.worker.OAIRecordParquetWorker` | Sin cambios |
| **TASK** | | |
| `backend.taskmanager.TaskManager` | `core.task.TaskManager` | Mover |
| `backend.taskmanager.NetworkAction` | `core.task.NetworkAction` | Mover |
| `backend.taskmanager.NetworkActionManager` | `core.task.NetworkActionManager` | Mover |
| `backend.taskmanager.NetworkCleanWorker` | `core.worker.management.NetworkCleanWorker` | Mover (es un worker, no task) |
| **METADATA** | | |
| `core.metadata.IMetadataStore` | `core.metadata.IMetadataStore` | Sin cambios |
| `core.metadata.ISnapshotStore` | `core.metadata.ISnapshotStore` | Sin cambios |
| `core.metadata.MetadataStoreFSImpl` | `core.metadata.MetadataStoreFSImpl` | Sin cambios |
| `core.metadata.SnapshotStoreImpl` | `core.metadata.SnapshotStoreImpl` | Sin cambios |
| `core.metadata.SnapshotMetadata` | `core.metadata.SnapshotMetadata` | Sin cambios |
| **VALIDATION ENGINE** | | |
| `core.validation.IValidator` | `core.worker.validation.IValidator` | Mover |
| `core.validation.ITransformer` | `core.worker.validation.ITransformer` | Mover |
| `core.validation.ValidationEngine` | `core.worker.validation.ValidationEngine` | Mover (si existe) |
| `core.validation.XPathRuleEvaluator` | `core.worker.validation.XPathRuleEvaluator` | Mover (si existe) |
| **HARVESTING** | | |
| `core.harvester.IHarvester` | `core.worker.harvesting.IHarvester` | Mover |
| `core.harvester.OCLCHarvesterAdapter` | `core.worker.harvesting.OCLCHarvesterAdapter` | Mover |
| `core.harvester.*` | `core.worker.harvesting.*` | Mover todo |
| **INDEXING** | | |
| `core.indexing.SolrIndexer` | `core.worker.indexing.SolrIndexer` | Mover (si existe) |
| **UTIL** | | |
| `core.util.*` | `core.util.*` | Sin cambios |
| `backend.util.parquet.*` | `core.util.*` | Mover |

### 4.2 Notas Importantes

**Modelos Parquet**:
- Los modelos que están en `backend.domain.parquet.*` se mantienen como modelos de Parquet
- Se mueven a `repository/parquet/` junto con sus managers
- No se crean ni eliminan clases, solo se reubican

**Sin Renombres**:
- ❌ NO renombrar clases (ej: `SnapshotLogService` sigue siendo `SnapshotLogService`)
- ❌ NO agregar sufijos (ej: no cambiar `Network` a `NetworkEntity`)
- ❌ NO eliminar clases
- ✅ Solo MOVER clases existentes

**Interfaces con Prefijo I**:
- ✅ Todas las interfaces existentes mantienen su prefijo `I`
- ✅ Ejemplos: `IMetadataStore`, `ISnapshotStore`, `IValidator`, `ITransformer`, `IHarvester`, `IPaginator`
- ✅ `IValidationStatisticsService` se mantiene como está

---

## 5. PLAN DE EJECUCIÓN

### 5.1 Fases de Migración

#### FASE 1: Preparación
**Duración**: 1 día

1. Crear estructura de directorios vacía
2. Documentar imports actuales
3. Preparar scripts de migración

#### FASE 2: Migración de Domain
**Duración**: 2 días

1. Mover todas las clases de `backend.domain` a `core.domain/`
2. Incluir los modelos que están en `backend.domain.parquet/`
3. Actualizar imports

#### FASE 3: Migración de Repository
**Duración**: 2-3 días

1. Mover `backend.repositories.jpa/` a `core.repository.jpa/`
2. Mover `backend.repositories.parquet/` a `core.repository.parquet/`
3. Actualizar imports y verificar inyección de dependencias

#### FASE 4: Migración de Service
**Duración**: 2-3 días

1. Crear subcarpetas por funcionalidad: `harvesting/`, `validation/`, `indexing/`, `management/`
2. Mover servicios de `backend.services/` y `backend.validation/`
3. Consolidar servicios duplicados
4. Actualizar imports

#### FASE 5: Migración de Worker
**Duración**: 2-3 días

1. Mover `BaseWorker` y framework al root de `worker/`
2. Crear subcarpetas: `harvesting/`, `validation/`, `indexing/`, `management/`
3. Mover workers de `backend.workers/` y `core.harvester.workers/`
4. Mover interfaces (`IValidator`, `ITransformer`, `IHarvester`) a sus workers respectivos

#### FASE 6: Migración de Task
**Duración**: 1 día

1. Mover `backend.taskmanager/` a `core.task/`
2. Mover `NetworkCleanWorker` a `worker/management/CleanupWorker`

#### FASE 7: Limpieza Final
**Duración**: 2 días

1. Eliminar paquete `backend/` completamente
2. Consolidar utilidades en `util/`
3. Ejecutar todos los tests
4. Verificar que no quedan imports del paquete `backend`
5. Code review completo

### 5.2 Duración Total

**12-15 días de trabajo** (2-3 semanas calendario)

---

## 6. ESTRATEGIA DE TESTING

### 6.1 Validación Continua

- Ejecutar tests unitarios después de cada fase
- Ejecutar tests de integración al final de cada fase mayor
- Verificar que la aplicación arranca sin errores

### 6.2 Criterios de Éxito

- ✅ Todos los tests existentes pasan
- ✅ No hay imports de `org.lareferencia.backend.*`
- ✅ Compilación exitosa sin warnings
- ✅ La aplicación arranca correctamente
- ✅ Todos los workers funcionan

---

## 7. RIESGOS Y MITIGACIÓN

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|--------------|---------|------------|
| Breaking changes | Media | Alto | Suite completa de tests |
| Configuración Spring rota | Baja | Alto | Verificar component scanning |
| Merge conflicts | Alta | Medio | Branch dedicado + comunicación |

### 7.1 Plan de Rollback

1. Branch dedicado: `refactor/simple-package-structure`
2. Commits atómicos por fase
3. Tags en cada fase completada
4. Rollback a tag anterior si algo falla

---

## 8. BENEFICIOS ESPERADOS

### 8.1 Técnicos

- **Simplicidad extrema**: Solo 7 carpetas root, fácil navegación
- **Mantenibilidad**: Todo relacionado con una funcionalidad está junto
- **Testabilidad**: Estructura clara facilita testing
- **Pragmatismo**: Sin abstracciones innecesarias

### 8.2 De Negocio

- **Onboarding rápido**: Estructura autoexplicativa
- **Menos bugs**: Menos complejidad = menos errores
- **Desarrollo ágil**: Cambios más rápidos

---

## 9. CHECKLIST DE VALIDACIÓN

### Estructura
- [ ] Existen exactamente 7 carpetas en `org.lareferencia.core/`
- [ ] No existe el paquete `org.lareferencia.backend`
- [ ] Ningún paquete tiene más de 2 niveles de profundidad

### Código
- [ ] No hay imports de `org.lareferencia.backend.*`
- [ ] Todos los tests pasan
- [ ] No hay warnings de compilación
- [ ] Component scanning de Spring funciona

### Funcional
- [ ] Harvesting funciona
- [ ] Validación funciona
- [ ] Indexación funciona
- [ ] Dashboard muestra datos
- [ ] Workers se ejecutan correctamente

---

## 10. CONVENCIONES

### 10.1 Nomenclatura

**Reglas Estrictas**:
- ❌ NO renombrar clases (mantener nombres originales)
- ❌ NO agregar sufijos (`Entity`, `Parquet`, `Impl`, etc.)
- ❌ NO eliminar clases
- ❌ NO crear clases nuevas
- ✅ SOLO mover clases existentes a nuevos paquetes

**Interfaces**:
- ✅ Todas las interfaces mantienen prefijo `I`
- ✅ Ejemplos: `IMetadataStore`, `ISnapshotStore`, `IHarvester`, `IValidator`, `ITransformer`, `IPaginator`, `IValidationStatisticsService`

### 10.2 Filosofía

**Reestructuración, NO Refactoring**:
- Este es un movimiento de paquetes, no una reescritura
- NO cambiar nombres de clases, métodos o variables
- NO cambiar firmas de métodos
- NO consolidar clases duplicadas (mover ambas)
- Solo actualizar imports

**Pragmatismo**:
- Usar las abstracciones que Spring ya provee
- Mantener todas las interfaces existentes
- No crear nuevas abstracciones

**Funcionalidad Primero**:
- Organizar por funcionalidad (harvesting, validation, indexing)
- No por tipo técnico (controllers, services, repositories)
- Excepción: Los 7 paquetes raíz son transversales

---

## 11. CONCLUSIÓN

Este plan propone la estructura **más simple posible** que mantiene separación de responsabilidades:

✅ **7 paquetes raíz**: domain, repository, service, metadata, worker, task, util  
✅ **Máximo 2 niveles**: ej. `service/validation/ValidationService.java`  
✅ **Organización funcional**: harvesting, validation, indexing dentro de cada capa  
✅ **Solo movimientos**: NO renombrar, crear o eliminar clases  
✅ **Preservar interfaces**: Todas las interfaces con prefijo `I` se mantienen  

**Duración**: 2-3 semanas  
**Riesgo**: Bajo (solo cambios de imports)  
**Beneficio**: Alto (simplicidad y mantenibilidad)

---

**Versión**: 4.0 (Reestructuración sin renombres)  
**Estado**: Propuesta para revisión
