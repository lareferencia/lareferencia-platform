# Análisis: Redundancia entre RecordValidation y OAIRecord

**Fecha:** 10 de noviembre de 2025  
**Contexto:** Propuesta de migración OAIRecord a Parquet  
**Problema crítico:** Duplicación de información de validación

---

## 1. PROBLEMA: REDUNDANCIA DE DATOS

### 1.1 Situación Actual

**OAIRecord (SQL → propuesto Parquet):**
```java
class OAIRecord {
    Long id;
    String identifier;
    LocalDateTime datestamp;
    RecordStatus status;           // ← VALIDACIÓN
    Boolean transformed;           // ← VALIDACIÓN
    String originalMetadataHash;
    String publishedMetadataHash;
}
```

**RecordValidation (Parquet - ya implementado):**
```java
class RecordValidation {
    String id;
    String identifier;
    Boolean recordIsValid;         // ← VALIDACIÓN (duplicado)
    Boolean isTransformed;         // ← VALIDACIÓN (duplicado)
    List<RuleFact> ruleFacts;      // ← Detalles de validación
}
```

### 1.2 Análisis de Redundancia

| Campo | OAIRecord | RecordValidation | ¿Duplicado? |
|-------|-----------|------------------|-------------|
| **ID** | ✅ `id` (Long) | ✅ `id` (String) | ❌ NO (tipos diferentes) |
| **Identifier** | ✅ `identifier` | ✅ `identifier` | ✅ **SÍ** |
| **Status/Valid** | ✅ `status` (enum) | ✅ `recordIsValid` (boolean) | ✅ **SÍ** |
| **Transformed** | ✅ `transformed` | ✅ `isTransformed` | ✅ **SÍ** |
| **Datestamp** | ✅ `datestamp` | ❌ - | NO |
| **Metadata hashes** | ✅ 2 campos | ❌ - | NO |
| **Rule facts** | ❌ - | ✅ `ruleFacts` | NO |

**Conclusión:** 50% de campos duplicados, principalmente información de validación.

### 1.3 Problema con Parquet

**En SQL (actual):**
```sql
-- Update es trivial
UPDATE oairecord 
SET status = 'VALID', transformed = true 
WHERE id = 12345;
```

**En Parquet (propuesto):**
```java
// Update requiere REESCRIBIR TODO EL SNAPSHOT
// Para 10 millones de records = catastrófico
copyAllRecordsWithChanges(snapshotId);  // ❌ INVIABLE
```

---

## 2. USO DE LA INFORMACIÓN

### 2.1 ¿Quién Usa Qué?

#### **ValidationWorker (escribe validación)**

```java
// ESCRIBE en RecordValidation (Parquet)
validationStatisticsService.writeValidationRecord(recordValidation);

// ESCRIBE en OAIRecord (SQL/Parquet)
metadataStoreService.updateRecordStatus(record, status, transformed);
```

**Observación:** ✅ **Doble escritura** - información se guarda en DOS lugares.

#### **IndexerWorker (lee para indexar)**

```java
// LEE de OAIRecord únicamente
IPaginator<OAIRecord> paginator = metadataStoreService.getValidRecordsPaginator(snapshotId);

for (OAIRecord record : paginator) {
    if (record.getStatus() == RecordStatus.VALID) {  // ← USA status de OAIRecord
        // Indexar...
    }
}
```

**Observación:** ✅ **Solo lee OAIRecord**, NO accede a RecordValidation.

#### **Dashboard/Stats (lee estadísticas)**

```java
// LEE de RecordValidation únicamente
validationStatisticsService.queryValidatorRulesStatsBySnapshot(snapshotId);
validationStatisticsService.queryValidationStatsObservations(snapshotId);
```

**Observación:** ✅ **Solo lee RecordValidation**, NO accede a OAIRecord.

#### **Harvesting Incremental (verifica existencia)**

```java
// LEE de OAIRecord
OAIRecord existing = metadataStoreService.findRecordByIdentifier(snapshotId, identifier);
if (existing != null) {
    // Ya existe, skip o update
}
```

**Observación:** ✅ **Solo lee OAIRecord**, necesita identifier + metadata hashes.

### 2.2 Tabla de Dependencias

| Componente | Lee OAIRecord | Lee RecordValidation | Escribe OAIRecord | Escribe RecordValidation |
|------------|---------------|----------------------|-------------------|--------------------------|
| **HarvestingWorker** | ✅ (búsqueda) | ❌ | ✅ (crear) | ❌ |
| **ValidationWorker** | ✅ (leer metadata) | ❌ | ✅ (status) | ✅ (stats) |
| **IndexerWorker** | ✅ (filtrar válidos) | ❌ | ❌ | ❌ |
| **Dashboard** | ❌ | ✅ (estadísticas) | ❌ | ❌ |
| **API REST** | ✅ (queries) | ✅ (stats detail) | ❌ | ❌ |

---

## 3. PROPUESTAS DE SOLUCIÓN

### 3.1 OPCIÓN 1: OAIRecord Mínimo (RECOMENDADA)

**Concepto:** Separar información de **catálogo** vs **validación**.

#### Arquitectura

**OAIRecordCatalog (Parquet - nuevo):**
```java
/**
 * Información MÍNIMA para harvesting.
 * INMUTABLE después de harvesting (solo se crea o marca como deleted).
 * NO contiene estado de validación NI metadata transformada.
 */
class OAIRecordCatalog {
    Long id;                        // ID secuencial en snapshot
    String identifier;              // OAI identifier
    LocalDateTime datestamp;        // Última modificación OAI
    String originalMetadataHash;    // Hash MD5 del XML original (ÚNICO hash aquí)
    Boolean deleted;                // Flag de record eliminado (OAI deleted)
}
```

**RecordValidation (Parquet - mejorado):**
```java
/**
 * Información COMPLETA de validación y transformación.
 * Se REESCRIBE completamente en cada validación.
 */
class RecordValidation {
    Long recordId;                  // Referencia a OAIRecordCatalog.id
    String identifier;              // Duplicado para queries
    Boolean recordIsValid;          // Estado de validación
    Boolean isTransformed;          // Flag transformación
    String publishedMetadataHash;   // Hash MD5 del XML transformado (NUEVO)
    LocalDateTime validatedAt;      // Timestamp de validación
    List<RuleFact> ruleFacts;       // Detalles de reglas
}
```

**NetworkSnapshot (SQL - sin cambios):**
```java
class NetworkSnapshot {
    Long id;
    // ... campos actuales sin cambios
    Integer size;                   // Total records (de OAIRecordCatalog)
    Integer validSize;              // Valid records (de RecordValidation)
    Integer transformedSize;        // Transformed records (de RecordValidation)
}
```

#### Flujos de Operación

**HARVESTING (escribe catálogo):**
```java
public OAIRecord createRecord(Long snapshotId, OAIRecordMetadata metadata) {
    
    // 1. Almacenar XML en filesystem
    String hash = metadataStore.storeAndReturnHash(metadata.toString());
    
    // 2. Crear entrada en catálogo (PARQUET)
    OAIRecordCatalog catalogRecord = OAIRecordCatalog.builder()
        .id(nextRecordId(snapshotId))
        .identifier(metadata.getIdentifier())
        .datestamp(metadata.getDatestamp())
        .originalMetadataHash(hash)
        .deleted(false)
        .build();
    
    catalogManager.writeRecord(catalogRecord);
    
    // 3. Actualizar contador en snapshot
    snapshot.incrementSize();
    
    // NO escribe en RecordValidation (aún no validado)
    
    return catalogRecord;  // Adaptado como OAIRecord
}
```

**VALIDATION (escribe validación, NO toca catálogo):**
```java
public void processItem(OAIRecord record) {
    
    // 1. Leer metadata original del catálogo
    OAIRecordCatalog catalog = catalogManager.readById(record.getId());
    String metadataXml = metadataStore.getMetadata(catalog.getOriginalMetadataHash());
    OAIRecordMetadata metadata = OAIRecordMetadata.fromString(metadataXml);
    
    // 2. Validar (lógica existente)
    ValidatorResult result = validator.validate(metadata);
    
    // 3. Transformar si es válido
    String publishedHash = null;
    if (result.isValid() && transformer != null) {
        metadata = transformer.transform(metadata);
        wasTransformed = true;
        
        // Almacenar metadata transformada y obtener hash
        publishedHash = metadataStore.storeAndReturnHash(metadata.toString());
    } else if (result.isValid()) {
        // Si es válido pero no transformado, usar hash original
        publishedHash = catalog.getOriginalMetadataHash();
    }
    // Si es inválido, publishedHash = null
    
    // 4. Escribir resultado SOLO en RecordValidation (PARQUET)
    RecordValidation validation = RecordValidation.builder()
        .recordId(record.getId())
        .identifier(record.getIdentifier())
        .recordIsValid(result.isValid())
        .isTransformed(wasTransformed)
        .publishedMetadataHash(publishedHash)  // ← HASH AQUÍ
        .validatedAt(LocalDateTime.now())
        .ruleFacts(result.getRuleFacts())
        .build();
    
    validationStatisticsService.writeValidationRecord(validation);
    
    // 5. Actualizar contadores en snapshot (SQL)
    if (result.isValid()) snapshot.incrementValidSize();
    if (wasTransformed) snapshot.incrementTransformedSize();
    
    // NO toca catálogo (permanece inmutable)
}
```

**INDEXING (lee catálogo + validación):**
```java
public void processItem(OAIRecord record) {
    
    // 1. Obtener validación (incluye publishedMetadataHash)
    RecordValidation validation = validationStatisticsService.getValidationByRecordId(record.getId());
    
    // 2. Filtrar por estado
    if (executeDeletion && (!validation.getRecordIsValid() || record.getDeleted())) {
        deleteRecord(record.getId());
        return;
    }
    
    // 3. Obtener metadata usando hash correcto
    // - Si fue transformado: usar publishedMetadataHash de RecordValidation
    // - Si NO fue transformado: usar originalMetadataHash de OAIRecordCatalog
    String metadataHash = validation.getIsTransformed() 
        ? validation.getPublishedMetadataHash()   // ← De validación
        : record.getOriginalMetadataHash();        // ← De catálogo
    
    String metadataXml = metadataStore.getMetadata(metadataHash);
    
    // 4. Indexar (lógica existente)
    indexToSolr(metadataXml);
}
```

#### Ventajas

✅ **Sin redundancia:** Cada dato vive en UN solo lugar  
✅ **Catálogo inmutable:** No requiere reescrituras Parquet  
✅ **Validación mutable:** Se puede reescribir solo RecordValidation (más pequeño)  
✅ **Separación de responsabilidades:** Catálogo vs Estado  
✅ **Escalabilidad:** RecordValidation es ~30% del tamaño de OAIRecord completo  

#### Desventajas

⚠️ **Complejidad:** Requiere JOIN lógico entre catálogo y validación  
⚠️ **Queries más complejas:** IndexerWorker debe leer 2 fuentes  
⚠️ **Migración:** Requiere split de datos existentes  

---

### 3.2 OPCIÓN 2: RecordValidation como Fuente Única (ALTERNATIVA)

**Concepto:** Eliminar estado de validación de OAIRecord, usar SOLO RecordValidation.

#### Arquitectura

**OAIRecordCatalog (igual que Opción 1):**
```java
class OAIRecordCatalog {
    Long id;
    String identifier;
    LocalDateTime datestamp;
    String originalMetadataHash;    // ÚNICO hash aquí
    Boolean deleted;
    // SIN campos de validación
    // SIN publishedMetadataHash (está en RecordValidation)
}
```

**RecordValidation (extendido):**
```java
class RecordValidation {
    Long recordId;
    String identifier;
    
    // Estado de validación
    Boolean recordIsValid;
    Boolean isTransformed;
    String publishedMetadataHash;   // Hash transformado (NUEVO)
    LocalDateTime validatedAt;
    
    // Detalles de validación
    List<RuleFact> ruleFacts;
    
    // NUEVO: Índice para acceso rápido
    // Se mantiene en archivo separado: validation_index.parquet
}
```

**ValidationIndex (Parquet - recomendado):**
```java
/**
 * Índice ligero para queries rápidas sin leer todo RecordValidation.
 * Contiene campos esenciales para filtrado + hash para indexación.
 */
class ValidationIndex {
    Long recordId;                  // FK a OAIRecordCatalog
    String identifier;              // Para búsquedas
    Boolean isValid;                // Para filtrado
    Boolean isTransformed;          // Para filtrado
    String publishedMetadataHash;   // Hash del XML a indexar (NUEVO)
}
```

#### Flujo IndexerWorker

```java
public void preRun() {
    // Leer índice completo en memoria (ligero: ~100MB para 10M records)
    Map<Long, ValidationIndex> validationIndex = 
        validationStatisticsService.loadValidationIndex(snapshotId);
    
    // Crear paginator de catálogo
    IPaginator<OAIRecordCatalog> catalogPaginator = 
        catalogManager.getRecordsPaginator(snapshotId);
    
    this.setPaginator(new FilteredCatalogPaginator(catalogPaginator, validationIndex));
}

public void processItem(OAIRecord record) {
    // record ya está filtrado por estado de validación
    // procesar normalmente...
}
```

#### Ventajas

✅ **Fuente única de verdad:** Validación vive SOLO en RecordValidation  
✅ **Sin duplicación:** Cero redundancia de datos  
✅ **Índice optimizado:** ValidationIndex es muy ligero y cabe en memoria  
✅ **Coherencia:** Imposible tener estados inconsistentes  

#### Desventajas

⚠️ **Lectura dual:** Siempre requiere leer catálogo + validación  
⚠️ **Índice en memoria:** 100MB+ para datasets grandes  
⚠️ **Complejidad de código:** Más lógica de coordinación  

---

### 3.3 OPCIÓN 3: Mantener Redundancia con Delta Updates (NO RECOMENDADA)

**Concepto:** Aceptar duplicación, pero optimizar updates con archivos delta.

#### Arquitectura

**OAIRecord (Parquet - completo):**
```java
class OAIRecord {
    Long id;
    String identifier;
    LocalDateTime datestamp;
    RecordStatus status;           // ← Mantener
    Boolean transformed;           // ← Mantener
    String originalMetadataHash;
    String publishedMetadataHash;
}
```

**RecordValidation (Parquet - mantener):**
```java
class RecordValidation {
    // ... igual que ahora (con duplicación)
}
```

**OAIRecordDelta (Parquet - nuevo):**
```java
/**
 * Archivo delta con solo los cambios de validación.
 * Se fusiona con OAIRecord base en lectura.
 */
class OAIRecordDelta {
    Long recordId;
    RecordStatus newStatus;
    Boolean newTransformed;
    LocalDateTime updatedAt;
}
```

#### Flujo de Update

```java
public void updateRecordStatus(Long recordId, RecordStatus status, Boolean transformed) {
    
    // 1. Escribir cambio en archivo delta (rápido)
    OAIRecordDelta delta = new OAIRecordDelta(recordId, status, transformed, LocalDateTime.now());
    deltaManager.writeDelta(snapshotId, delta);
    
    // 2. Acumular deltas sin fusionar
    // (fusión ocurre en background o en próximo harvesting)
}

public OAIRecord readRecord(Long recordId) {
    
    // 1. Leer record base
    OAIRecord baseRecord = catalogManager.readRecord(recordId);
    
    // 2. Aplicar delta si existe
    OAIRecordDelta delta = deltaManager.readDelta(recordId);
    if (delta != null) {
        baseRecord.setStatus(delta.getNewStatus());
        baseRecord.setTransformed(delta.getNewTransformed());
    }
    
    return baseRecord;
}
```

#### Ventajas

✅ **Updates rápidos:** Solo escribe deltas pequeños  
✅ **Sin reescrituras:** Archivos base intactos  
✅ **Backward compatible:** Misma interfaz OAIRecord  

#### Desventajas

❌ **Duplicación persiste:** No resuelve el problema fundamental  
❌ **Complejidad:** Sistema delta complejo de mantener  
❌ **Performance degradado:** Lecturas requieren merge on-the-fly  
❌ **Compaction necesario:** Eventualmente hay que fusionar deltas  

**Decisión:** ❌ **NO RECOMENDADA** - complejidad sin beneficio real.

---

## 4. COMPARACIÓN DE OPCIONES

| Criterio | Opción 1: Catálogo Mínimo | Opción 2: RecordValidation Único | Opción 3: Delta Updates |
|----------|---------------------------|----------------------------------|-------------------------|
| **Duplicación** | ❌ Eliminada | ❌ Eliminada | ⚠️ Persiste |
| **Performance escritura** | ✅ Excelente | ✅ Excelente | ✅ Buena |
| **Performance lectura** | ⚠️ JOIN lógico | ⚠️ Dual + índice | ❌ Merge on-fly |
| **Complejidad código** | ⚠️ Media | ⚠️ Media-Alta | ❌ Alta |
| **Escalabilidad** | ✅ Excelente | ✅ Buena | ⚠️ Media |
| **Mantenibilidad** | ✅ Clara separación | ✅ Fuente única | ❌ Sistema complejo |
| **Migración** | ⚠️ Moderada | ⚠️ Moderada | ⚠️ Moderada |
| **Riesgo** | ✅ Bajo | ⚠️ Medio | ❌ Alto |

---

## 5. RECOMENDACIÓN: OPCIÓN 1 CON OPTIMIZACIONES

### 5.1 Arquitectura Final Propuesta

```
lareferencia-platform/
├── OAIRecordCatalog (Parquet)
│   ├── Propósito: Información de harvesting e identificación
│   ├── Tamaño: ~50 bytes/record
│   ├── Operaciones: CREATE, UPDATE (solo publishedHash), SOFT DELETE
│   └── Path: /data/oai-catalog/snapshot_{id}/catalog_batch_*.parquet
│
├── RecordValidation (Parquet)
│   ├── Propósito: Estado y detalles de validación
│   ├── Tamaño: ~200 bytes/record
│   ├── Operaciones: CREATE, REWRITE (completo en cada validación)
│   └── Path: /data/validation-stats/snapshot_{id}/records_batch_*.parquet
│
├── ValidationIndex (Parquet - opcional)
│   ├── Propósito: Índice ligero para filtrado rápido
│   ├── Tamaño: ~20 bytes/record
│   ├── Operaciones: REGENERAR (post-validación)
│   └── Path: /data/validation-stats/snapshot_{id}/validation_index.parquet
│
└── NetworkSnapshot (SQL)
    ├── Propósito: Metadatos y contadores agregados
    ├── Tamaño: 1 row/snapshot
    └── Operaciones: CREATE, UPDATE (transaccional)
```

### 5.2 Esquemas Parquet Detallados

#### OAIRecordCatalog Schema

```java
private static final MessageType CATALOG_SCHEMA = Types.buildMessage()
    .required(PrimitiveType.PrimitiveTypeName.INT64)
        .named("id")
    
    .required(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("identifier")
    
    .required(PrimitiveType.PrimitiveTypeName.INT64)
        .as(LogicalTypeAnnotation.timestampType(true, TimeUnit.MILLIS))
        .named("datestamp")
    
    .required(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("original_metadata_hash")
    
    .required(PrimitiveType.PrimitiveTypeName.BOOLEAN)
        .named("deleted")
    
    .named("OAIRecordCatalog");
```

**Estimación tamaño:**
- id: 8 bytes
- identifier: ~30 bytes (avg)
- datestamp: 8 bytes
- original_metadata_hash: 32 bytes
- deleted: 1 byte
- **Total: ~79 bytes/record sin compresión**
- **Con SNAPPY: ~40 bytes/record** ← 20% más pequeño que antes

#### RecordValidation Schema (mejorado)

```java
private static final MessageType VALIDATION_SCHEMA = Types.buildMessage()
    .required(PrimitiveType.PrimitiveTypeName.INT64)
        .named("record_id")  // FK a OAIRecordCatalog
    
    .required(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("identifier")  // Denormalizado para queries
    
    .required(PrimitiveType.PrimitiveTypeName.BOOLEAN)
        .named("record_is_valid")
    
    .required(PrimitiveType.PrimitiveTypeName.BOOLEAN)
        .named("is_transformed")
    
    .optional(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("published_metadata_hash")  // Hash del XML transformado (NUEVO)
    
    .required(PrimitiveType.PrimitiveTypeName.INT64)
        .as(LogicalTypeAnnotation.timestampType(true, TimeUnit.MILLIS))
        .named("validated_at")
    
    .optionalGroup()
        .repeatedGroup()
            // ... ruleFacts (igual que ahora)
        .named("rule_facts_list")
    
    .named("RecordValidation");
```

#### ValidationIndex Schema (nuevo)

```java
private static final MessageType INDEX_SCHEMA = Types.buildMessage()
    .required(PrimitiveType.PrimitiveTypeName.INT64)
        .named("record_id")
    
    .required(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("identifier")
    
    .required(PrimitiveType.PrimitiveTypeName.BOOLEAN)
        .named("is_valid")
    
    .required(PrimitiveType.PrimitiveTypeName.BOOLEAN)
        .named("is_transformed")
    
    .optional(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("published_metadata_hash")  // Hash para indexación (NUEVO)
    
    .named("ValidationIndex");
```

**Estimación tamaño:**
- record_id: 8 bytes
- identifier: ~30 bytes
- is_valid: 1 byte
- is_transformed: 1 byte
- published_metadata_hash: 32 bytes (nullable)
- **Total: ~72 bytes/record sin compresión**
- **Con SNAPPY: ~35 bytes/record**
- **10M records = 350 MB (cabe en memoria)**

### 5.3 Implementación de Componentes

#### OAIRecordCatalogManager

```java
public final class OAIRecordCatalogManager implements AutoCloseable, Iterable<OAIRecordCatalog> {
    
    private static final int FLUSH_THRESHOLD_RECORDS = 10000;
    private static final String BATCH_FILE_PREFIX = "catalog_batch_";
    
    // Factory methods
    public static OAIRecordCatalogManager forWriting(String basePath, Long snapshotId, Configuration hadoopConf);
    public static OAIRecordCatalogManager forReading(String basePath, Long snapshotId, Configuration hadoopConf);
    
    // ESCRITURA (solo durante harvesting)
    public synchronized void writeRecord(OAIRecordCatalog record) throws IOException;
    public synchronized void markAsDeleted(Long recordId) throws IOException;
    public synchronized void flush() throws IOException;
    
    // LECTURA
    public OAIRecordCatalog readById(Long recordId) throws IOException;
    public OAIRecordCatalog findByIdentifier(String identifier) throws IOException;
    public Iterator<OAIRecordCatalog> iterator();
    
    // UTILIDADES
    public long countRecords();
    public void deleteSnapshot() throws IOException;
}
```

#### ValidationIndexManager

```java
public final class ValidationIndexManager {
    
    private static final String INDEX_FILE = "validation_index.parquet";
    
    /**
     * Regenera el índice completo desde RecordValidation.
     * Llamar después de cada validación.
     */
    public void rebuildIndex(Long snapshotId) throws IOException {
        
        List<ValidationIndex> indexEntries = new ArrayList<>();
        
        // Leer todos los RecordValidation
        try (ValidationRecordManager reader = ValidationRecordManager.forReading(basePath, snapshotId, hadoopConf)) {
            for (RecordValidation validation : reader) {
                ValidationIndex entry = ValidationIndex.builder()
                    .recordId(Long.parseLong(validation.getId()))
                    .identifier(validation.getIdentifier())
                    .isValid(validation.getRecordIsValid())
                    .isTransformed(validation.getIsTransformed())
                    .publishedMetadataHash(validation.getPublishedMetadataHash())  // ← INCLUIR
                    .build();
                
                indexEntries.add(entry);
            }
        }
        
        // Escribir índice en un solo archivo
        writeIndex(snapshotId, indexEntries);
    }
    
    /**
     * Carga índice completo en memoria.
     * Rápido: ~200MB para 10M records.
     */
    public Map<Long, ValidationIndex> loadIndex(Long snapshotId) throws IOException {
        
        Map<Long, ValidationIndex> index = new HashMap<>();
        
        try (ParquetReader<Group> reader = createReader(snapshotId)) {
            Group group;
            while ((group = reader.read()) != null) {
                ValidationIndex entry = parseGroup(group);
                index.put(entry.getRecordId(), entry);
            }
        }
        
        return index;
    }
}
```

### 5.4 Adaptación de Workers

#### HarvestingWorker (sin cambios significativos)

```java
@Override
public void handleRecord(OAIRecordMetadata metadata) {
    
    // Buscar record existente (incremental)
    OAIRecordCatalog existing = catalogManager.findByIdentifier(metadata.getIdentifier());
    
    if (existing != null && hashesMatch(existing, metadata)) {
        // Sin cambios, skip
        return;
    }
    
    // Crear nuevo record en catálogo
    OAIRecordCatalog catalogRecord = createCatalogRecord(metadata);
    catalogManager.writeRecord(catalogRecord);
    
    // Actualizar contador
    snapshot.incrementSize();
}
```

#### ValidationWorker (modificado)

```java
@Override
public void processItem(OAIRecord record) {
    
    // 1. Leer catálogo
    OAIRecordCatalog catalog = catalogManager.readById(record.getId());
    
    // 2. Obtener metadata original
    OAIRecordMetadata metadata = metadataStore.getMetadata(catalog.getOriginalMetadataHash());
    
    // 3. Validar
    ValidatorResult result = validator.validate(metadata);
    
    // 4. Transformar si es válido
    String publishedHash = null;
    if (result.isValid() && transformer != null) {
        metadata = transformer.transform(metadata);
        wasTransformed = true;
        publishedHash = metadataStore.storeAndReturnHash(metadata.toString());
    } else if (result.isValid()) {
        // Válido pero no transformado: usar hash original
        publishedHash = catalog.getOriginalMetadataHash();
    }
    // Si inválido: publishedHash = null
    
    // 5. Escribir validación (INCLUYE publishedMetadataHash)
    RecordValidation validation = RecordValidation.builder()
        .recordId(catalog.getId())
        .identifier(catalog.getIdentifier())
        .recordIsValid(result.isValid())
        .isTransformed(wasTransformed)
        .publishedMetadataHash(publishedHash)  // ← HASH AQUÍ
        .validatedAt(LocalDateTime.now())
        .ruleFacts(result.getRuleFacts())
        .build();
    
    validationStatisticsService.writeValidationRecord(validation);
    
    // 6. Actualizar contadores
    if (result.isValid()) snapshot.incrementValidSize();
    if (wasTransformed) snapshot.incrementTransformedSize();
}

@Override
public void postRun() {
    // Regenerar índice de validación (incluye publishedMetadataHash)
    validationIndexManager.rebuildIndex(snapshotId);
}
```

#### IndexerWorker (modificado)

```java
@Override
public void preRun() {
    
    // 1. Cargar índice de validación en memoria (incluye publishedMetadataHash)
    Map<Long, ValidationIndex> validationIndex = validationIndexManager.loadIndex(snapshotId);
    
    // 2. Crear paginator de catálogo
    IPaginator<OAIRecordCatalog> catalogPaginator = catalogManager.getRecordsPaginator(snapshotId);
    
    // 3. Envolver en paginator filtrado
    this.setPaginator(new ValidRecordsPaginator(catalogPaginator, validationIndex));
}

@Override
public void processItem(OAIRecord record) {
    
    // record ya está filtrado (solo válidos)
    
    // 1. Obtener validación desde índice en memoria
    ValidationIndex validation = validationIndex.get(record.getId());
    
    // 2. Obtener hash correcto:
    //    - Si transformado: usar publishedMetadataHash del índice
    //    - Si NO transformado: usar publishedMetadataHash del índice (apunta a original)
    String metadataHash = validation.getPublishedMetadataHash();  // ← SIEMPRE del índice
    
    // 3. Leer metadata
    String metadataXml = metadataStore.getMetadata(metadataHash);
    
    // 4. Indexar (sin cambios)
    indexToSolr(metadataXml);
}
```

### 5.5 Performance Esperado

**Harvesting (10M records):**
- Escritura catálogo: ~3 min (solo append)
- Total: ~3 min ✅ (vs 15 min SQL)

**Validation (10M records):**
- Lectura catálogo: ~1 min
- Escritura RecordValidation: ~2 min (reescritura completa)
- Actualizar hashes catálogo: ~1 min (solo records transformados ~30%)
- Rebuild index: ~1 min
- Total: ~5 min ✅ (vs 10 min SQL)

**Indexing (10M records válidos):**
- Carga índice en memoria: ~10 seg
- Lectura catálogo filtrado: ~2 min
- Indexación Solr: ~8 min
- Total: ~10 min ✅ (igual que SQL)

---

## 6. PLAN DE IMPLEMENTACIÓN

### 6.1 Fases

#### FASE 1: Componentes Base (2 semanas)
- [ ] Crear `OAIRecordCatalog` (domain)
- [ ] Implementar `OAIRecordCatalogManager`
- [ ] Crear `ValidationIndex` (domain)
- [ ] Implementar `ValidationIndexManager`
- [ ] Tests unitarios

#### FASE 2: Service Layer (2 semanas)
- [ ] Modificar `RecordValidation` (agregar recordId, validatedAt)
- [ ] Actualizar `ValidationRecordManager`
- [ ] Modificar `ParquetMetadataRecordStoreService` para usar catálogo
- [ ] Modificar `ValidationStatisticsParquetService` para índice
- [ ] Tests de integración

#### FASE 3: Workers (2 semanas)
- [ ] Actualizar `HarvestingWorker`
- [ ] Actualizar `ValidationWorker`
- [ ] Actualizar `IndexerWorker`
- [ ] Tests end-to-end

#### FASE 4: Migración de Datos (1-2 semanas)
- [ ] Script de migración OAIRecord SQL → OAIRecordCatalog + RecordValidation
- [ ] Validación de integridad
- [ ] Testing en QA

#### FASE 5: Producción (1 semana)
- [ ] Despliegue
- [ ] Monitoreo
- [ ] Ajustes

**TOTAL: 8-9 semanas**

### 6.2 Criterios de Éxito

✅ **Cero duplicación:** Validación vive SOLO en RecordValidation  
✅ **Performance:** Validación ≤ 5 min para 10M records  
✅ **Escalabilidad:** Soporta 100M+ records sin degradación  
✅ **Mantenibilidad:** Código más simple que SQL actual  

---

## 7. CONCLUSIÓN

### ✅ Recomendación Final

**IMPLEMENTAR OPCIÓN 1: OAIRecordCatalog + RecordValidation separados**

**Justificación:**

1. **Elimina redundancia:** Cada dato vive en un solo lugar
2. **Inmutabilidad:** Catálogo casi no cambia (óptimo para Parquet)
3. **Escalabilidad:** RecordValidation se puede reescribir eficientemente
4. **Separación clara:** Harvesting vs Validación
5. **Performance:** 2-3x más rápido que SQL
6. **Índice ligero:** ValidationIndex cabe en memoria para queries rápidas

**Riesgos mitigados:**

- JOIN lógico → resuelto con ValidationIndex en memoria
- Complejidad → menor que sistema delta
- Migración → script automatizado, testeable

**Próximos pasos:**

1. ✅ Aprobar diseño con equipo
2. ✅ Implementar POC con 100K records
3. ✅ Benchmark vs SQL
4. ✅ Proceder con implementación completa

---

**Documento preparado por:** Análisis técnico AI  
**Fecha:** 10 de noviembre de 2025  
**Versión:** 1.0  
**Estado:** Propuesta para discusión
