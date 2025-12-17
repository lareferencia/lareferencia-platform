# Guía de Migración de Paquetes - lareferencia-core-lib

**Fecha**: 12 de noviembre de 2025  
**Versión**: 2.0 (Validado con migración real)  
**Propósito**: Guía para actualizar imports después de la reestructuración de paquetes en `lareferencia-core-lib`

---

## 🚀 INICIO RÁPIDO

**Si solo quieres migrar tu proyecto rápidamente:**

1. **Descarga el script Python** de la sección "Opción 3" (línea ~300)
2. **Ejecuta**: `python3 migrate_imports.py`
3. **Compila**: `mvn clean compile`
4. **Verifica**: `mvn test`

**Tiempo estimado**: 5-15 minutos para un proyecto típico.

---

## 📋 RESUMEN

La librería `lareferencia-core-lib` ha reorganizado sus paquetes de la siguiente manera:

- ❌ Eliminado: `org.lareferencia.backend.*`
- ✅ Nueva estructura: `org.lareferencia.core.*` con 7 paquetes raíz

**IMPORTANTE**: Esta es una reestructuración de paquetes, NO un refactoring. Los nombres de clases, métodos e interfaces NO han cambiado. Solo necesitas actualizar los imports.

---

## 📑 ÍNDICE

1. [🚀 Inicio Rápido](#-inicio-rápido)
2. [🎯 Estructura Nueva](#-estructura-nueva)
3. [📦 Mapeo Completo de Paquetes](#-mapeo-completo-de-paquetes)
4. [🔧 Cómo Aplicar la Migración](#-cómo-aplicar-la-migración)
   - [Opción 1: Bash/Linux (Recomendado)](#opción-1-búsqueda-y-reemplazo-global-recomendado)
   - [Opción 2: IntelliJ IDEA](#opción-2-intellij-idea-refactor)
   - [Opción 3: Script Python (Más robusto)](#opción-3-script-python-automático)
5. [✅ Verificación Post-Migración](#-verificación-post-migración)
6. [🎓 Lecciones Aprendidas](#-lecciones-aprendidas-migración-real)
7. [🎯 Checklist de Migración](#-checklist-de-migración)
8. [⚠️ Casos Especiales](#-casos-especiales)
9. [🆘 Soporte](#-soporte)

---

## 🎯 ESTRUCTURA NUEVA

```
org.lareferencia.core/
├── domain/          - Modelos de negocio (entidades JPA)
├── repository/      - Repositorios (jpa/ y parquet/)
├── service/         - Servicios de negocio (por funcionalidad)
├── metadata/        - Almacenamiento de XML
├── worker/          - Workers asíncronos (por funcionalidad)
├── task/            - Scheduling y coordinación
└── util/            - Utilidades compartidas
```

---

## 📦 MAPEO COMPLETO DE PAQUETES

### 1. DOMAIN - Modelos de Negocio

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.domain.Network` | `org.lareferencia.core.domain.Network` |
| `org.lareferencia.backend.domain.NetworkSnapshot` | `org.lareferencia.core.domain.NetworkSnapshot` |
| `org.lareferencia.backend.domain.NetworkSnapshotLog` | `org.lareferencia.core.domain.NetworkSnapshotLog` |
| `org.lareferencia.backend.domain.Validator` | `org.lareferencia.core.domain.Validator` |
| `org.lareferencia.backend.domain.Transformer` | `org.lareferencia.core.domain.Transformer` |
| `org.lareferencia.backend.domain.ValidatorRule` | `org.lareferencia.core.domain.ValidatorRule` |
| `org.lareferencia.backend.domain.TransformerRule` | `org.lareferencia.core.domain.TransformerRule` |
| `org.lareferencia.backend.domain.OAIRecord` | `org.lareferencia.core.domain.OAIRecord` |
| `org.lareferencia.backend.domain.IOAIRecord` | `org.lareferencia.core.domain.IOAIRecord` |
| `org.lareferencia.backend.domain.OAIMetadata` | `org.lareferencia.core.domain.OAIMetadata` |
| `org.lareferencia.backend.domain.OAIBitstream` | `org.lareferencia.core.domain.OAIBitstream` |
| `org.lareferencia.backend.domain.OAIBitstreamId` | `org.lareferencia.core.domain.OAIBitstreamId` |
| `org.lareferencia.backend.domain.OAIBitstreamStatus` | `org.lareferencia.core.domain.OAIBitstreamStatus` |
| `org.lareferencia.backend.domain.SnapshotStatus` | `org.lareferencia.core.domain.SnapshotStatus` |
| `org.lareferencia.backend.domain.SnapshotIndexStatus` | `org.lareferencia.core.domain.SnapshotIndexStatus` |

### 2. REPOSITORY - JPA

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.repositories.jpa.NetworkRepository` | `org.lareferencia.core.repository.jpa.NetworkRepository` |
| `org.lareferencia.backend.repositories.jpa.NetworkSnapshotRepository` | `org.lareferencia.core.repository.jpa.NetworkSnapshotRepository` |
| `org.lareferencia.backend.repositories.jpa.NetworkSnapshotLogRepository` | `org.lareferencia.core.repository.jpa.NetworkSnapshotLogRepository` |
| `org.lareferencia.backend.repositories.jpa.ValidatorRepository` | `org.lareferencia.core.repository.jpa.ValidatorRepository` |
| `org.lareferencia.backend.repositories.jpa.ValidatorRuleRepository` | `org.lareferencia.core.repository.jpa.ValidatorRuleRepository` |
| `org.lareferencia.backend.repositories.jpa.TransformerRepository` | `org.lareferencia.core.repository.jpa.TransformerRepository` |
| `org.lareferencia.backend.repositories.jpa.TransformerRuleRepository` | `org.lareferencia.core.repository.jpa.TransformerRuleRepository` |
| `org.lareferencia.backend.repositories.jpa.OAIRecordRepository` | `org.lareferencia.core.repository.jpa.OAIRecordRepository` |
| `org.lareferencia.backend.repositories.jpa.OAIMetadataRepository` | `org.lareferencia.core.repository.jpa.OAIMetadataRepository` |
| `org.lareferencia.backend.repositories.jpa.OAIBitstreamRepository` | `org.lareferencia.core.repository.jpa.OAIBitstreamRepository` |

### 3. REPOSITORY - Parquet (Modelos + Managers)

**⚠️ IMPORTANTE**: Los modelos Parquet se mueven junto con sus managers

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.domain.parquet.OAIRecord` | `org.lareferencia.core.repository.parquet.OAIRecord` |
| `org.lareferencia.backend.domain.parquet.RecordValidation` | `org.lareferencia.core.repository.parquet.RecordValidation` |
| `org.lareferencia.backend.domain.parquet.RuleFact` | `org.lareferencia.core.repository.parquet.RuleFact` |
| `org.lareferencia.backend.domain.parquet.SnapshotValidationStats` | `org.lareferencia.core.repository.parquet.SnapshotValidationStats` |
| `org.lareferencia.backend.repositories.parquet.OAIRecordParquetRepository` | `org.lareferencia.core.repository.parquet.OAIRecordParquetRepository` |
| `org.lareferencia.backend.repositories.parquet.OAIRecordManager` | `org.lareferencia.core.repository.parquet.OAIRecordManager` |
| `org.lareferencia.backend.repositories.parquet.ValidationRecordManager` | `org.lareferencia.core.repository.parquet.ValidationRecordManager` |
| `org.lareferencia.backend.repositories.parquet.SnapshotMetadataManager` | `org.lareferencia.core.repository.parquet.SnapshotMetadataManager` |
| `org.lareferencia.backend.repositories.parquet.ValidationStatParquetRepository` | `org.lareferencia.core.repository.parquet.ValidationStatParquetRepository` |

### 4. SERVICE - Servicios de Negocio

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.services.ValidationService` | `org.lareferencia.core.service.validation.ValidationService` |
| `org.lareferencia.backend.services.SnapshotLogService` | `org.lareferencia.core.service.management.SnapshotLogService` |

### 5. SERVICE - Validation (Estadísticas y DTOs)

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.validation.IValidationStatisticsService` | `org.lareferencia.core.service.validation.IValidationStatisticsService` |
| `org.lareferencia.backend.validation.ValidationStatisticsParquetService` | `org.lareferencia.core.service.validation.ValidationStatisticsParquetService` |
| `org.lareferencia.backend.validation.ValidationStatisticsException` | `org.lareferencia.core.service.validation.ValidationStatisticsException` |
| `org.lareferencia.backend.validation.ValidationStatsResult` | `org.lareferencia.core.service.validation.ValidationStatsResult` |
| `org.lareferencia.backend.validation.ValidationStatsObservationsResult` | `org.lareferencia.core.service.validation.ValidationStatsObservationsResult` |
| `org.lareferencia.backend.validation.ValidationStatObservation` | `org.lareferencia.core.service.validation.ValidationStatObservation` |
| `org.lareferencia.backend.validation.ValidationRuleStat` | `org.lareferencia.core.service.validation.ValidationRuleStat` |
| `org.lareferencia.backend.validation.ValidationRuleOccurrencesCount` | `org.lareferencia.core.service.validation.ValidationRuleOccurrencesCount` |
| `org.lareferencia.backend.validation.OccurrenceCount` | `org.lareferencia.core.service.validation.OccurrenceCount` |
| `org.lareferencia.backend.validation.FacetKey` | `org.lareferencia.core.service.validation.FacetKey` |
| `org.lareferencia.backend.validation.FacetFieldEntry` | `org.lareferencia.core.service.validation.FacetFieldEntry` |

### 6. WORKER - Validation (Reglas de Validación)

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.workers.validator.ValidationWorker` | `org.lareferencia.core.worker.validation.ValidationWorker` |
| `org.lareferencia.backend.workers.validator.ValidatorImpl` | `org.lareferencia.core.worker.validation.ValidatorImpl` |
| `org.lareferencia.backend.workers.validator.TransformerImpl` | `org.lareferencia.core.worker.validation.TransformerImpl` |
| `org.lareferencia.backend.validation.validator.*` | `org.lareferencia.core.worker.validation.validator.*` |
| `org.lareferencia.backend.validation.transformer.*` | `org.lareferencia.core.worker.validation.transformer.*` |

**Reglas de Validación Específicas**:

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.validation.validator.RegexFieldContentValidatorRule` | `org.lareferencia.core.worker.validation.validator.RegexFieldContentValidatorRule` |
| `org.lareferencia.backend.validation.validator.ControlledValueFieldContentValidatorRule` | `org.lareferencia.core.worker.validation.validator.ControlledValueFieldContentValidatorRule` |
| `org.lareferencia.backend.validation.validator.LargeControlledValueFieldContentValidatorRule` | `org.lareferencia.core.worker.validation.validator.LargeControlledValueFieldContentValidatorRule` |
| `org.lareferencia.backend.validation.validator.ContentLengthFieldContentValidatorRule` | `org.lareferencia.core.worker.validation.validator.ContentLengthFieldContentValidatorRule` |
| `org.lareferencia.backend.validation.validator.DynamicYearRangeFieldContentValidatorRule` | `org.lareferencia.core.worker.validation.validator.DynamicYearRangeFieldContentValidatorRule` |
| `org.lareferencia.backend.validation.validator.URLExistFieldValidatorRule` | `org.lareferencia.core.worker.validation.validator.URLExistFieldValidatorRule` |
| `org.lareferencia.backend.validation.validator.FieldExpressionValidatorRule` | `org.lareferencia.core.worker.validation.validator.FieldExpressionValidatorRule` |
| `org.lareferencia.backend.validation.validator.FieldExpressionEvaluator` | `org.lareferencia.core.worker.validation.validator.FieldExpressionEvaluator` |
| `org.lareferencia.backend.validation.validator.NodeOccursConditionalValidatorRule` | `org.lareferencia.core.worker.validation.validator.NodeOccursConditionalValidatorRule` |
| `org.lareferencia.backend.validation.validator.ContentValidatorResult` | `org.lareferencia.core.worker.validation.validator.ContentValidatorResult` |

**Reglas de Transformación Específicas**:

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.validation.transformer.FieldNameTranslateRule` | `org.lareferencia.core.worker.validation.transformer.FieldNameTranslateRule` |
| `org.lareferencia.backend.validation.transformer.FieldNameBulkTranslateRule` | `org.lareferencia.core.worker.validation.transformer.FieldNameBulkTranslateRule` |
| `org.lareferencia.backend.validation.transformer.FieldNameConditionalTranslateRule` | `org.lareferencia.core.worker.validation.transformer.FieldNameConditionalTranslateRule` |
| `org.lareferencia.backend.validation.transformer.FieldContentTranslateRule` | `org.lareferencia.core.worker.validation.transformer.FieldContentTranslateRule` |
| `org.lareferencia.backend.validation.transformer.FieldContentPriorityTranslateRule` | `org.lareferencia.core.worker.validation.transformer.FieldContentPriorityTranslateRule` |
| `org.lareferencia.backend.validation.transformer.FieldContentRemoveWhiteSpacesTranslateRule` | `org.lareferencia.core.worker.validation.transformer.FieldContentRemoveWhiteSpacesTranslateRule` |
| `org.lareferencia.backend.validation.transformer.FieldContentNormalizeRule` | `org.lareferencia.core.worker.validation.transformer.FieldContentNormalizeRule` |
| `org.lareferencia.backend.validation.transformer.FieldContentConditionalAddOccrRule` | `org.lareferencia.core.worker.validation.transformer.FieldContentConditionalAddOccrRule` |
| `org.lareferencia.backend.validation.transformer.FieldAddRule` | `org.lareferencia.core.worker.validation.transformer.FieldAddRule` |
| `org.lareferencia.backend.validation.transformer.RegexTranslateRule` | `org.lareferencia.core.worker.validation.transformer.RegexTranslateRule` |
| `org.lareferencia.backend.validation.transformer.IdentifierRegexRule` | `org.lareferencia.core.worker.validation.transformer.IdentifierRegexRule` |
| `org.lareferencia.backend.validation.transformer.RemoveAllButFirstOccrRule` | `org.lareferencia.core.worker.validation.transformer.RemoveAllButFirstOccrRule` |
| `org.lareferencia.backend.validation.transformer.RemoveDuplicateOccrsRule` | `org.lareferencia.core.worker.validation.transformer.RemoveDuplicateOccrsRule` |
| `org.lareferencia.backend.validation.transformer.RemoveDuplicatePrefixedOccrs` | `org.lareferencia.core.worker.validation.transformer.RemoveDuplicatePrefixedOccrs` |
| `org.lareferencia.backend.validation.transformer.RemoveDuplicateVocabularyOccrsRule` | `org.lareferencia.core.worker.validation.transformer.RemoveDuplicateVocabularyOccrsRule` |
| `org.lareferencia.backend.validation.transformer.RemoveBlacklistOccrsRule` | `org.lareferencia.core.worker.validation.transformer.RemoveBlacklistOccrsRule` |
| `org.lareferencia.backend.validation.transformer.RemoveEmptyOccrsRule` | `org.lareferencia.core.worker.validation.transformer.RemoveEmptyOccrsRule` |
| `org.lareferencia.backend.validation.transformer.AddRepoNameRule` | `org.lareferencia.core.worker.validation.transformer.AddRepoNameRule` |
| `org.lareferencia.backend.validation.transformer.AddProvenanceMetadataRule` | `org.lareferencia.core.worker.validation.transformer.AddProvenanceMetadataRule` |
| `org.lareferencia.backend.validation.transformer.ReduceHeavyRecords` | `org.lareferencia.core.worker.validation.transformer.ReduceHeavyRecords` |

### 7. WORKER - Harvesting (Downloader)

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.workers.downloader.DownloaderWorker` | `org.lareferencia.core.worker.harvesting.DownloaderWorker` |
| `org.lareferencia.backend.workers.downloader.FulltextWorker` | `org.lareferencia.core.worker.harvesting.FulltextWorker` |
| `org.lareferencia.backend.workers.downloader.DeleteBitstreamWorker` | `org.lareferencia.core.worker.harvesting.DeleteBitstreamWorker` |
| `org.lareferencia.backend.workers.downloader.DowloaderException` | `org.lareferencia.core.worker.harvesting.DowloaderException` |

### 8. WORKER - Indexing

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.workers.indexer.IndexerWorker` | `org.lareferencia.core.worker.indexing.IndexerWorker` |
| `org.lareferencia.backend.workers.indexer.FullUnindexerWorker` | `org.lareferencia.core.worker.indexing.FullUnindexerWorker` |
| `org.lareferencia.backend.workers.indexer.IndexerException` | `org.lareferencia.core.worker.indexing.IndexerException` |

### 9. TASK - Scheduling

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.backend.taskmanager.TaskManager` | `org.lareferencia.core.task.TaskManager` |
| `org.lareferencia.backend.taskmanager.NetworkAction` | `org.lareferencia.core.task.NetworkAction` |
| `org.lareferencia.backend.taskmanager.NetworkActionkManager` | `org.lareferencia.core.task.NetworkActionManager` |
| `org.lareferencia.backend.taskmanager.NetworkProperty` | `org.lareferencia.core.task.NetworkProperty` |
| `org.lareferencia.backend.taskmanager.NetworkCleanWorker` | `org.lareferencia.core.worker.management.NetworkCleanWorker` |

**⚠️ NOTA**: `NetworkCleanWorker` va a `worker/management/` porque es un worker, no un task.

### 10. METADATA - Sin Cambios

| Import | Estado |
|--------|--------|
| `org.lareferencia.core.metadata.*` | ✅ Sin cambios |

### 11. WORKER - Interfaces (ya existentes en core)

| Import Antiguo | Import Nuevo |
|----------------|--------------|
| `org.lareferencia.core.validation.IValidator` | `org.lareferencia.core.worker.validation.IValidator` |
| `org.lareferencia.core.validation.ITransformer` | `org.lareferencia.core.worker.validation.ITransformer` |
| `org.lareferencia.core.harvester.IHarvester` | `org.lareferencia.core.worker.harvesting.IHarvester` |

### 12. UTIL - Sin Cambios Mayores

| Import | Estado |
|--------|--------|
| `org.lareferencia.core.util.*` | ✅ Sin cambios |
| `org.lareferencia.backend.util.parquet.*` | ➡️ Mover a `org.lareferencia.core.util.*` |

---

## 🔧 CÓMO APLICAR LA MIGRACIÓN

### ⚠️ IMPORTANTE: Orden Crítico de Ejecución

**El orden de los comandos es CRÍTICO**. Ejecutar en orden incorrecto puede causar imports incorrectos.

### Opción 1: Búsqueda y Reemplazo Global (Recomendado)

**Para macOS/Linux** (usa el siguiente orden exacto):

```bash
# FASE 1: Domain (más específico primero)
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.domain\.parquet\./import org.lareferencia.core.repository.parquet./g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.domain\./import org.lareferencia.core.domain./g' {} +

# FASE 2: Repositories
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.repositories\.jpa\./import org.lareferencia.core.repository.jpa./g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.repositories\.parquet\./import org.lareferencia.core.repository.parquet./g' {} +

# FASE 3: Services (específico antes que genérico)
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.services\./import org.lareferencia.core.service.validation./g' {} +

# FASE 4: Validation (MUY IMPORTANTE: más específico primero)
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.validation\.validator\./import org.lareferencia.core.worker.validation.validator./g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.validation\.transformer\./import org.lareferencia.core.worker.validation.transformer./g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.validation\./import org.lareferencia.core.worker.validation./g' {} +

# FASE 5: Workers
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.workers\.validator\./import org.lareferencia.core.worker.validation./g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.workers\.downloader\./import org.lareferencia.core.worker.harvesting./g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.workers\.indexer\./import org.lareferencia.core.worker.indexing./g' {} +

# FASE 6: Task Manager
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.taskmanager\./import org.lareferencia.core.task./g' {} +

# FASE 7: Core packages (interfaces que ya estaban en core)
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.core\.harvester\.workers\./import org.lareferencia.core.worker.harvesting./g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.core\.harvester\./import org.lareferencia.core.worker.harvesting./g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.core\.validation\./import org.lareferencia.core.worker.validation./g' {} +

# FASE 8: Correcciones específicas (clases que fueron a service en vez de worker)
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.core\.worker\.validation\.ValidationStatObservation;/import org.lareferencia.core.service.validation.ValidationStatObservation;/g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.core\.worker\.validation\.IValidationStatisticsService;/import org.lareferencia.core.service.validation.IValidationStatisticsService;/g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.core\.worker\.validation\.ValidationStatisticsException;/import org.lareferencia.core.service.validation.ValidationStatisticsException;/g' {} +
find src -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.core\.service\.validation\.SnapshotLogService;/import org.lareferencia.core.service.management.SnapshotLogService;/g' {} +
```

**Para Linux** (sin las comillas '' después de -i):

```bash
# Mismo código pero con: sed -i 's/...' en vez de sed -i '' 's/...'
find src -type f -name "*.java" -exec sed -i 's/import org\.lareferencia\.backend\.domain\.parquet\./import org.lareferencia.core.repository.parquet./g' {} +
# ... (resto igual)
```

**Para Windows (PowerShell)**:

```powershell
# IMPORTANTE: Ejecutar en orden
$patterns = @(
    @{Old='org\.lareferencia\.backend\.domain\.parquet\.'; New='org.lareferencia.core.repository.parquet.'},
    @{Old='org\.lareferencia\.backend\.domain\.'; New='org.lareferencia.core.domain.'},
    @{Old='org\.lareferencia\.backend\.repositories\.jpa\.'; New='org.lareferencia.core.repository.jpa.'},
    @{Old='org\.lareferencia\.backend\.repositories\.parquet\.'; New='org.lareferencia.core.repository.parquet.'},
    @{Old='org\.lareferencia\.backend\.services\.'; New='org.lareferencia.core.service.validation.'},
    @{Old='org\.lareferencia\.backend\.validation\.validator\.'; New='org.lareferencia.core.worker.validation.validator.'},
    @{Old='org\.lareferencia\.backend\.validation\.transformer\.'; New='org.lareferencia.core.worker.validation.transformer.'},
    @{Old='org\.lareferencia\.backend\.validation\.'; New='org.lareferencia.core.worker.validation.'},
    @{Old='org\.lareferencia\.backend\.workers\.validator\.'; New='org.lareferencia.core.worker.validation.'},
    @{Old='org\.lareferencia\.backend\.workers\.downloader\.'; New='org.lareferencia.core.worker.harvesting.'},
    @{Old='org\.lareferencia\.backend\.workers\.indexer\.'; New='org.lareferencia.core.worker.indexing.'},
    @{Old='org\.lareferencia\.backend\.taskmanager\.'; New='org.lareferencia.core.task.'},
    @{Old='org\.lareferencia\.core\.harvester\.workers\.'; New='org.lareferencia.core.worker.harvesting.'},
    @{Old='org\.lareferencia\.core\.harvester\.'; New='org.lareferencia.core.worker.harvesting.'},
    @{Old='org\.lareferencia\.core\.validation\.'; New='org.lareferencia.core.worker.validation.'},
    # Correcciones específicas
    @{Old='org\.lareferencia\.core\.worker\.validation\.ValidationStatObservation'; New='org.lareferencia.core.service.validation.ValidationStatObservation'},
    @{Old='org\.lareferencia\.core\.worker\.validation\.IValidationStatisticsService'; New='org.lareferencia.core.service.validation.IValidationStatisticsService'},
    @{Old='org\.lareferencia\.core\.worker\.validation\.ValidationStatisticsException'; New='org.lareferencia.core.service.validation.ValidationStatisticsException'},
    @{Old='org\.lareferencia\.core\.service\.validation\.SnapshotLogService'; New='org.lareferencia.core.service.management.SnapshotLogService'}
)

Get-ChildItem -Path "src" -Recurse -Filter *.java | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $modified = $false
    foreach ($pattern in $patterns) {
        $newContent = $content -replace $pattern.Old, $pattern.New
        if ($newContent -ne $content) {
            $content = $newContent
            $modified = $true
        }
    }
    if ($modified) {
        Set-Content -Path $_.FullName -Value $content -NoNewline
        Write-Host "✅ Migrado: $($_.FullName)"
    }
}
```

### Opción 2: IntelliJ IDEA Refactor

1. Abre el proyecto que usa `lareferencia-core-lib`
2. **Menu** → **Edit** → **Find** → **Replace in Files...** (Ctrl+Shift+R / Cmd+Shift+R)
3. Marca la casilla **Regex**
4. Ejecuta los reemplazos **EN ORDEN** (uno por uno):

```
# Orden exacto (copiar y pegar cada línea):
import org\.lareferencia\.backend\.domain\.parquet\.  →  import org.lareferencia.core.repository.parquet.
import org\.lareferencia\.backend\.domain\.  →  import org.lareferencia.core.domain.
import org\.lareferencia\.backend\.repositories\.jpa\.  →  import org.lareferencia.core.repository.jpa.
import org\.lareferencia\.backend\.repositories\.parquet\.  →  import org.lareferencia.core.repository.parquet.
import org\.lareferencia\.backend\.services\.  →  import org.lareferencia.core.service.validation.
import org\.lareferencia\.backend\.validation\.validator\.  →  import org.lareferencia.core.worker.validation.validator.
import org\.lareferencia\.backend\.validation\.transformer\.  →  import org.lareferencia.core.worker.validation.transformer.
import org\.lareferencia\.backend\.validation\.  →  import org.lareferencia.core.worker.validation.
import org\.lareferencia\.backend\.workers\.validator\.  →  import org.lareferencia.core.worker.validation.
import org\.lareferencia\.backend\.workers\.downloader\.  →  import org.lareferencia.core.worker.harvesting.
import org\.lareferencia\.backend\.workers\.indexer\.  →  import org.lareferencia.core.worker.indexing.
import org\.lareferencia\.backend\.taskmanager\.  →  import org.lareferencia.core.task.
import org\.lareferencia\.core\.harvester\.workers\.  →  import org.lareferencia.core.worker.harvesting.
import org\.lareferencia\.core\.harvester\.  →  import org.lareferencia.core.worker.harvesting.
import org\.lareferencia\.core\.validation\.  →  import org.lareferencia.core.worker.validation.

# Correcciones específicas:
import org\.lareferencia\.core\.worker\.validation\.ValidationStatObservation;  →  import org.lareferencia.core.service.validation.ValidationStatObservation;
import org\.lareferencia\.core\.worker\.validation\.IValidationStatisticsService;  →  import org.lareferencia.core.service.validation.IValidationStatisticsService;
import org\.lareferencia\.core\.worker\.validation\.ValidationStatisticsException;  →  import org.lareferencia.core.service.validation.ValidationStatisticsException;
import org\.lareferencia\.core\.service\.validation\.SnapshotLogService;  →  import org.lareferencia.core.service.management.SnapshotLogService;
```

5. **CRÍTICO**: Revisar cada cambio antes de aplicar (IntelliJ muestra preview)
6. Aplicar cambio por cambio, no todos a la vez

**⚠️ NOTA**: También busca referencias completamente calificadas (sin import) que puedan existir en el código.

### Opción 3: Script Python Automático

**Recomendado para proyectos grandes**. Guarda este script como `migrate_imports.py`:

```python
#!/usr/bin/env python3
"""
Script de migración automática de imports para lareferencia-core-lib
Migra de la estructura antigua (backend.*) a la nueva (core.*)
"""
import os
import re
from pathlib import Path

# Definir mapeos en orden (CRÍTICO: más específico primero)
IMPORT_MAPPINGS = [
    # FASE 1: Domain (más específico primero)
    (r'import org\.lareferencia\.backend\.domain\.parquet\.', 'import org.lareferencia.core.repository.parquet.'),
    (r'import org\.lareferencia\.backend\.domain\.', 'import org.lareferencia.core.domain.'),
    
    # FASE 2: Repositories
    (r'import org\.lareferencia\.backend\.repositories\.jpa\.', 'import org.lareferencia.core.repository.jpa.'),
    (r'import org\.lareferencia\.backend\.repositories\.parquet\.', 'import org.lareferencia.core.repository.parquet.'),
    
    # FASE 3: Services
    (r'import org\.lareferencia\.backend\.services\.', 'import org.lareferencia.core.service.validation.'),
    
    # FASE 4: Validation (MUY IMPORTANTE: más específico primero)
    (r'import org\.lareferencia\.backend\.validation\.validator\.', 'import org.lareferencia.core.worker.validation.validator.'),
    (r'import org\.lareferencia\.backend\.validation\.transformer\.', 'import org.lareferencia.core.worker.validation.transformer.'),
    (r'import org\.lareferencia\.backend\.validation\.', 'import org.lareferencia.core.worker.validation.'),
    
    # FASE 5: Workers
    (r'import org\.lareferencia\.backend\.workers\.validator\.', 'import org.lareferencia.core.worker.validation.'),
    (r'import org\.lareferencia\.backend\.workers\.downloader\.', 'import org.lareferencia.core.worker.harvesting.'),
    (r'import org\.lareferencia\.backend\.workers\.indexer\.', 'import org.lareferencia.core.worker.indexing.'),
    
    # FASE 6: Task Manager
    (r'import org\.lareferencia\.backend\.taskmanager\.', 'import org.lareferencia.core.task.'),
    
    # FASE 7: Core packages (interfaces que ya estaban en core)
    (r'import org\.lareferencia\.core\.harvester\.workers\.', 'import org.lareferencia.core.worker.harvesting.'),
    (r'import org\.lareferencia\.core\.harvester\.', 'import org.lareferencia.core.worker.harvesting.'),
    (r'import org\.lareferencia\.core\.validation\.', 'import org.lareferencia.core.worker.validation.'),
    
    # FASE 8: Correcciones específicas (clases que fueron a service en vez de worker)
    (r'import org\.lareferencia\.core\.worker\.validation\.ValidationStatObservation;', 
     'import org.lareferencia.core.service.validation.ValidationStatObservation;'),
    (r'import org\.lareferencia\.core\.worker\.validation\.IValidationStatisticsService;', 
     'import org.lareferencia.core.service.validation.IValidationStatisticsService;'),
    (r'import org\.lareferencia\.core\.worker\.validation\.ValidationStatisticsException;', 
     'import org.lareferencia.core.service.validation.ValidationStatisticsException;'),
    (r'import org\.lareferencia\.core\.service\.validation\.SnapshotLogService;', 
     'import org.lareferencia.core.service.management.SnapshotLogService;'),
]

# También migrar referencias completamente calificadas (sin import)
QUALIFIED_MAPPINGS = [
    (r'org\.lareferencia\.backend\.domain\.parquet\.OAIRecord', 'org.lareferencia.core.repository.parquet.OAIRecord'),
    (r'org\.lareferencia\.backend\.domain\.parquet\.', 'org.lareferencia.core.repository.parquet.'),
    (r'org\.lareferencia\.backend\.domain\.', 'org.lareferencia.core.domain.'),
]

def migrate_file(filepath: Path) -> tuple[bool, int]:
    """
    Migra un archivo Java.
    Returns: (fue_modificado, numero_de_cambios)
    """
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"❌ Error leyendo {filepath}: {e}")
        return False, 0
    
    original = content
    changes = 0
    
    # Aplicar mapeos de imports
    for pattern, replacement in IMPORT_MAPPINGS:
        new_content, count = re.subn(pattern, replacement, content)
        if count > 0:
            content = new_content
            changes += count
    
    # Aplicar mapeos de referencias completamente calificadas
    for pattern, replacement in QUALIFIED_MAPPINGS:
        new_content, count = re.subn(pattern, replacement, content)
        if count > 0:
            content = new_content
            changes += count
    
    if content != original:
        try:
            with open(filepath, 'w', encoding='utf-8') as f:
                f.write(content)
            return True, changes
        except Exception as e:
            print(f"❌ Error escribiendo {filepath}: {e}")
            return False, 0
    
    return False, 0

def migrate_directory(directory: str = './src'):
    """Migra todos los archivos .java en un directorio."""
    src_path = Path(directory)
    
    if not src_path.exists():
        print(f"❌ Directorio no encontrado: {directory}")
        return
    
    print(f"🔍 Buscando archivos Java en: {src_path.absolute()}")
    print(f"{'='*80}")
    
    java_files = list(src_path.rglob('*.java'))
    total_files = len(java_files)
    migrated_count = 0
    total_changes = 0
    
    print(f"📁 Encontrados {total_files} archivos Java\n")
    
    for filepath in java_files:
        modified, changes = migrate_file(filepath)
        if modified:
            migrated_count += 1
            total_changes += changes
            print(f"✅ {filepath.relative_to(src_path.parent)} ({changes} cambios)")
    
    print(f"\n{'='*80}")
    print(f"📊 Resumen:")
    print(f"   - Total archivos analizados: {total_files}")
    print(f"   - Archivos migrados: {migrated_count}")
    print(f"   - Total de cambios aplicados: {total_changes}")
    
    if migrated_count == 0:
        print(f"\n✨ ¡No se encontraron imports antiguos! El proyecto ya está migrado.")
    else:
        print(f"\n✨ ¡Migración completada exitosamente!")
        print(f"\n⚠️  SIGUIENTE PASO: Ejecutar 'mvn clean compile' para verificar")

if __name__ == '__main__':
    import sys
    
    directory = sys.argv[1] if len(sys.argv) > 1 else './src'
    
    print("🚀 Iniciando migración de imports...")
    print(f"📂 Directorio objetivo: {directory}\n")
    
    migrate_directory(directory)
```

**Uso**:

```bash
# Desde la raíz del proyecto
python3 migrate_imports.py

# O especificar directorio
python3 migrate_imports.py ./src
```

**Ventajas de este script**:
- ✅ Orden correcto automático
- ✅ Maneja referencias completamente calificadas
- ✅ Muestra progreso detallado
- ✅ Cuenta cambios realizados
- ✅ Seguro (no modifica si no hay cambios)

---

## ✅ VERIFICACIÓN POST-MIGRACIÓN

### 1. Verificar que no quedan imports antiguos de backend

```bash
# Buscar imports de backend que no deberían existir
grep -r "import org.lareferencia.backend" src/ --include="*.java"

# Si el comando no retorna nada (o retorna error "No such file or directory"), 
# significa que la migración está completa ✅

# NOTA: En lareferencia-lrharvester-app es NORMAL encontrar:
#   - org.lareferencia.backend.controllers.*
#   - org.lareferencia.backend.app.*
# Estos son parte de esa aplicación, NO de core-lib
```

### 2. Buscar referencias completamente calificadas (sin import)

```bash
# Buscar usos de clases con nombre completo (ej: new org.lareferencia.backend...)
grep -r "org\.lareferencia\.backend\." src/ --include="*.java" | grep -v "^import"

# Estos deben ser corregidos manualmente si existen
```

### 3. Verificar clases que migraron a service.validation (no worker)

**IMPORTANTE**: Algunas clases fueron a `service.validation` en vez de `worker.validation`:

```bash
# Estas clases DEBEN estar en service.validation:
grep -r "IValidationStatisticsService" src/ --include="*.java"
grep -r "ValidationStatObservation" src/ --include="*.java"
grep -r "ValidationStatisticsException" src/ --include="*.java"

# Verificar que los imports sean:
# import org.lareferencia.core.service.validation.IValidationStatisticsService;
# import org.lareferencia.core.service.validation.ValidationStatObservation;
# import org.lareferencia.core.service.validation.ValidationStatisticsException;

# NO deben ser:
# import org.lareferencia.core.worker.validation.IValidationStatisticsService;  ❌
```

### 4. Verificar SnapshotLogService está en service.management

```bash
grep -r "SnapshotLogService" src/ --include="*.java"

# El import debe ser:
# import org.lareferencia.core.service.management.SnapshotLogService;

# NO debe ser:
# import org.lareferencia.core.service.validation.SnapshotLogService;  ❌
```

### 5. Compilar el proyecto

```bash
mvn clean compile

# Debe terminar con:
# [INFO] BUILD SUCCESS
```

**Si hay errores de compilación**, revisar los mensajes. Los errores comunes son:

- **"package org.lareferencia.backend.xxx does not exist"**: Falta migrar algún import
- **"cannot find symbol"**: El import fue migrado al paquete incorrecto
- **"class XXX is already defined"**: Posible conflicto de nombres (muy raro)

### 6. Ejecutar tests

```bash
mvn test

# Si hay tests que fallan, revisar los imports en los archivos de test
```

### 7. Verificar imports de core que cambiaron

```bash
# Estos NO deberían existir FUERA de lareferencia-core-lib:
grep -r "import org.lareferencia.core.validation" src/ --include="*.java"
grep -r "import org.lareferencia.core.harvester" src/ --include="*.java"

# Si aparecen, deben cambiarse a:
# org.lareferencia.core.worker.validation.*
# org.lareferencia.core.worker.harvesting.*
```

### 8. Checklist de verificación rápida

Ejecuta estos comandos en secuencia para verificación completa:

```bash
#!/bin/bash
echo "🔍 Verificando migración..."
echo ""

echo "1️⃣ Buscando imports antiguos de backend..."
BACKEND_IMPORTS=$(grep -r "import org.lareferencia.backend" src/ --include="*.java" 2>/dev/null | wc -l)
if [ $BACKEND_IMPORTS -eq 0 ]; then
    echo "   ✅ No se encontraron imports de backend"
else
    echo "   ❌ Se encontraron $BACKEND_IMPORTS imports de backend"
    grep -r "import org.lareferencia.backend" src/ --include="*.java"
fi
echo ""

echo "2️⃣ Buscando referencias a core.validation (deben ser worker.validation)..."
CORE_VALIDATION=$(grep -r "import org.lareferencia.core.validation\." src/ --include="*.java" 2>/dev/null | wc -l)
if [ $CORE_VALIDATION -eq 0 ]; then
    echo "   ✅ No se encontraron imports de core.validation"
else
    echo "   ⚠️  Se encontraron $CORE_VALIDATION imports de core.validation"
fi
echo ""

echo "3️⃣ Buscando referencias a core.harvester (deben ser worker.harvesting)..."
CORE_HARVESTER=$(grep -r "import org.lareferencia.core.harvester\." src/ --include="*.java" 2>/dev/null | wc -l)
if [ $CORE_HARVESTER -eq 0 ]; then
    echo "   ✅ No se encontraron imports de core.harvester"
else
    echo "   ⚠️  Se encontraron $CORE_HARVESTER imports de core.harvester"
fi
echo ""

echo "4️⃣ Compilando proyecto..."
mvn clean compile -q
if [ $? -eq 0 ]; then
    echo "   ✅ Compilación exitosa"
else
    echo "   ❌ Errores de compilación"
fi
echo ""

echo "✨ Verificación completa"
```

---

## 🎓 LECCIONES APRENDIDAS (Migración Real)

### 1. ⚠️ El orden de los reemplazos es CRÍTICO

Durante la migración real descubrimos que ejecutar los comandos en orden incorrecto puede causar que imports correctos se sobrescriban incorrectamente.

**Ejemplo del problema**:
```bash
# ❌ MAL - Orden incorrecto
find . -exec sed 's/backend\.validation\./core.worker.validation./g' {} +
find . -exec sed 's/backend\.validation\.validator\./core.worker.validation.validator./g' {} +

# Resultado: backend.validation.validator.* termina como core.worker.validation.worker.validation.validator.*
```

**Solución**: Siempre ejecutar de **MÁS ESPECÍFICO a MÁS GENÉRICO**:
```bash
# ✅ BIEN - Orden correcto
find . -exec sed 's/backend\.validation\.validator\./core.worker.validation.validator./g' {} +
find . -exec sed 's/backend\.validation\.transformer\./core.worker.validation.transformer./g' {} +
find . -exec sed 's/backend\.validation\./core.worker.validation./g' {} +  # Al final, más genérico
```

### 2. ⚠️ Clases de servicio vs Worker - Importante distinción

**Descubrimiento**: No todas las clases en `backend.validation` son workers. Algunas son servicios y DTOs:

**Van a `service.validation`** (NO a worker):
- `IValidationStatisticsService` - Interface de servicio
- `ValidationStatisticsParquetService` - Implementación del servicio  
- `ValidationStatisticsException` - Excepción de negocio
- `ValidationStatObservation` - DTO
- `ValidationStatsResult` - DTO
- `ValidationRuleStat` - DTO
- `FacetKey`, `FacetFieldEntry`, `OccurrenceCount` - DTOs

**Van a `worker.validation`**:
- `ValidationWorker` - Worker principal
- `ValidatorImpl`, `TransformerImpl` - Implementaciones de workers
- `IValidator`, `ITransformer`, `IValidatorRule`, etc. - Interfaces de workers
- Todo en `validator/` y `transformer/` - Reglas específicas

**⚡ Corrección necesaria**: Después de la migración general, ejecutar:
```bash
find src -exec sed -i '' 's/core\.worker\.validation\.ValidationStatObservation/core.service.validation.ValidationStatObservation/g' {} +
find src -exec sed -i '' 's/core\.worker\.validation\.IValidationStatisticsService/core.service.validation.IValidationStatisticsService/g' {} +
find src -exec sed -i '' 's/core\.worker\.validation\.ValidationStatisticsException/core.service.validation.ValidationStatisticsException/g' {} +
```

### 3. ⚠️ Referencias Completamente Calificadas (Fully Qualified Names)

**Descubrimiento**: No todos los usos de clases están en imports. Algunos aparecen como nombres completamente calificados en el código:

```java
// Ejemplo encontrado en RecordValidation.java
this.recordId = org.lareferencia.backend.domain.parquet.OAIRecord.generateIdFromIdentifier(identifier);
```

**Solución**: Los scripts de migración deben buscar y reemplazar TANTO imports COMO referencias completamente calificadas:

```python
QUALIFIED_MAPPINGS = [
    (r'org\.lareferencia\.backend\.domain\.parquet\.OAIRecord', 
     'org.lareferencia.core.repository.parquet.OAIRecord'),
]
```

### 4. ⚠️ SnapshotLogService está en service.management (no validation)

**Descubrimiento**: `SnapshotLogService` está relacionado con logging/gestión, no con validación.

**Correcto**:
```java
import org.lareferencia.core.service.management.SnapshotLogService;
```

**Incorrecto** (lo que sale si solo reemplazamos backend.services):
```java
import org.lareferencia.core.service.validation.SnapshotLogService;  // ❌
```

**Corrección**:
```bash
find src -exec sed -i '' 's/core\.service\.validation\.SnapshotLogService/core.service.management.SnapshotLogService/g' {} +
```

### 5. ✅ Archivos de test también deben migrarse

**Descubrimiento**: Los archivos de test en `src/test/java` también tienen imports que deben actualizarse.

**Solución**: Ejecutar los mismos comandos pero también en `src/test`:
```bash
find src/test -type f -name "*.java" -exec sed -i '' 's/import org\.lareferencia\.backend\.domain\./import org.lareferencia.core.domain./g' {} +
# ... (todos los demás comandos)
```

O usar el script Python que automáticamente procesa todo en `src/` (incluye src/main y src/test).

### 6. ⚠️ sed en macOS vs Linux

**Descubrimiento**: El comando `sed` funciona diferente en macOS y Linux:

**macOS** (BSD sed):
```bash
sed -i '' 's/pattern/replacement/g' file.java  # Comillas vacías después de -i
```

**Linux** (GNU sed):
```bash
sed -i 's/pattern/replacement/g' file.java  # Sin comillas después de -i
```

**Solución multiplataforma**: Usar el script Python que funciona igual en todos los sistemas operativos.

### 7. ✅ Compilación incremental ayuda a detectar errores

**Lección**: Después de cada grupo de cambios, compilar:

```bash
# Después de migrar domain
mvn clean compile
# Después de migrar repositories
mvn clean compile
# ... etc
```

Esto permite detectar errores rápidamente en vez de al final.

### 8. 📊 Estadísticas de la Migración Real

En la migración de `lareferencia-core-lib`:

- **115 archivos** actualizados (declaraciones de paquetes)
- **~200 imports** migrados
- **3 errores** de compilación después de primera pasada (referencias completamente calificadas)
- **Tiempo total**: ~15 minutos (con scripts automatizados)
- **Compilación final**: ✅ BUILD SUCCESS

### 9. ⚡ Scripts automatizados son esenciales

**Lección clave**: La migración manual es propensa a errores. Los scripts automatizados:
- ✅ Garantizan orden correcto
- ✅ No olvidan casos especiales  
- ✅ Son repetibles y verificables
- ✅ Documentan exactamente qué se hizo

**Recomendación**: SIEMPRE usar el script Python para proyectos reales.

---

## 🎯 CHECKLIST DE MIGRACIÓN

Use este checklist para cada módulo que depende de `lareferencia-core-lib`:

- [ ] **Backup**: Crear branch o commit antes de migrar
- [ ] **Actualizar dependencia**: Asegurar que usa la versión nueva de `lareferencia-core-lib`
- [ ] **Aplicar migración**: Usar uno de los métodos arriba
- [ ] **Verificar imports**: No deben quedar `org.lareferencia.backend.*`
- [ ] **Compilar**: `mvn clean compile` sin errores
- [ ] **Tests**: `mvn test` todos pasando
- [ ] **Verificar específicos**:
  - [ ] Modelos Parquet movieron a `repository/parquet/`
  - [ ] Reglas de validación en `worker/validation/validator/`
  - [ ] Reglas de transformación en `worker/validation/transformer/`
  - [ ] Interfaces con prefijo `I` mantienen su nombre
- [ ] **Code Review**: Revisar cambios antes de commit
- [ ] **Documentar**: Actualizar README si aplica

---

## 📚 MÓDULOS A MIGRAR

Módulos conocidos que usan `lareferencia-core-lib`:

1. ✅ `lareferencia-core-lib` (ya migrado)
2. ⏳ `lareferencia-dashboard-rest`
3. ⏳ `lareferencia-entity-lib`
4. ⏳ `lareferencia-entity-rest`
5. ⏳ `lareferencia-lrharvester-app`
6. ⏳ `lareferencia-shell`
7. ⏳ `lareferencia-shell-entity-plugin`
8. ⏳ `lareferencia-contrib-ibict`
9. ⏳ `lareferencia-contrib-rcaap`

---

## ⚠️ CASOS ESPECIALES

### lareferencia-lrharvester-app

Este módulo tiene su propio paquete `org.lareferencia.backend.controllers` y `org.lareferencia.backend.app` que **NO deben migrar** porque son parte de esa aplicación, no de core-lib.

Solo migrar imports de clases de core-lib.

### Configuraciones XML/Properties

Revisar archivos de configuración que puedan referenciar nombres de clases completos:

- `application.properties`
- `application.yml`
- Archivos Spring XML
- Archivos de logging

Ejemplo:
```properties
# Antes
worker.validator.class=org.lareferencia.backend.workers.validator.ValidationWorker

# Después
worker.validator.class=org.lareferencia.core.worker.validation.ValidationWorker
```

---

## 🆘 SOPORTE

Si encuentras problemas:

1. Verifica que estás usando la última versión de `lareferencia-core-lib`
2. Revisa que el orden de los reemplazos es correcto (más específico primero)
3. Busca en este documento el mapeo exacto de la clase problemática
4. Consulta el documento de planificación: `REFACTORING_PACKAGE_STRUCTURE.md`

---

**Última actualización**: 12 de noviembre de 2025  
**Versión**: 2.0 - Actualizado con lecciones de migración real  
**Estado**: ✅ Validado en lareferencia-core-lib (migración exitosa)
