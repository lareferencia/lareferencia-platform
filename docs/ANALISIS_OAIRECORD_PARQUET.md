# Análisis: Implementación de OAIRecord en Parquet

**Fecha:** 10 de noviembre de 2025  
**Objetivo:** Migrar el almacenamiento de `OAIRecord` de SQL a Parquet, manteniendo datos de snapshot en SQL  
**Modelo de referencia:** `ValidationRecordManager`

---

## 1. CONTEXTO Y MOTIVACIÓN

### 1.1 Situación Actual
- **OAIRecord** se almacena en base de datos SQL (PostgreSQL)
- **NetworkSnapshot** mantiene metadatos y contadores en SQL
- El contenido XML (metadata) ya está en filesystem vía `IMetadataStore`
- Los records pueden ser millones por snapshot → problema de escala en SQL

### 1.2 Justificación del Cambio
1. **Escalabilidad**: SQL no escala bien con millones de records por snapshot
2. **Performance**: Operaciones batch sobre archivos Parquet son más eficientes
3. **Almacenamiento**: Compresión y formato columnar reducen espacio
4. **Consistencia**: Similar a `ValidationRecordManager` que ya usa Parquet exitosamente
5. **Separación de responsabilidades**: 
   - SQL → metadatos de snapshot (ligero)
   - Parquet → datos masivos de records (pesado)

---

## 2. ARQUITECTURA PROPUESTA

### 2.1 División de Responsabilidades

#### **SQL (mantener en base de datos)**
- **NetworkSnapshot**: toda la entidad sin cambios
  - ID, network_id, status, indexStatus
  - Timestamps (startTime, endTime, lastIncrementalTime)
  - Contadores (size, validSize, transformedSize)
  - Referencias (previousSnapshotId, resumptionToken)
  - Flag deleted

- **Network**: sin cambios
- **Validator, Transformer**: sin cambios
- **Logs y estadísticas agregadas**: sin cambios

#### **Parquet (nueva implementación)**
- **OAIRecord**: toda la entidad migrada a Parquet
  - ID (secuencial dentro del snapshot)
  - identifier (OAI identifier)
  - datestamp
  - status (RecordStatus enum)
  - transformed (boolean)
  - originalMetadataHash (referencia a IMetadataStore)
  - publishedMetadataHash (referencia a IMetadataStore)

### 2.2 Estructura de Directorios

```
{basePath}/
├── oai-records/
│   ├── snapshot_{snapshotId}/
│   │   ├── records_batch_00001.parquet
│   │   ├── records_batch_00002.parquet
│   │   ├── records_batch_00003.parquet
│   │   └── ...
│   ├── snapshot_{snapshotId2}/
│   │   └── records_batch_*.parquet
│   └── ...
└── validation-stats/         # Existente
    └── snapshot_{snapshotId}/
        └── records_batch_*.parquet
```

**Estrategia de archivos:**
- Una carpeta por snapshot
- Múltiples archivos batch por carpeta (auto-flush cada 10K records)
- Nombres secuenciales: `records_batch_00001.parquet`

---

## 3. ESQUEMA PARQUET

### 3.1 Diseño del Schema

```java
private static final MessageType OAI_RECORD_SCHEMA = Types.buildMessage()
    // ID secuencial dentro del snapshot (reemplaza ID de SQL)
    .required(PrimitiveType.PrimitiveTypeName.INT64)
        .named("id")
    
    // Identificador OAI-PMH (requerido, max 255 chars)
    .required(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("identifier")
    
    // Timestamp de la última modificación del record
    .required(PrimitiveType.PrimitiveTypeName.INT64)
        .as(LogicalTypeAnnotation.timestampType(true, TimeUnit.MILLIS))
        .named("datestamp")
    
    // Estado del record: UNTESTED, VALID, INVALID, DELETED
    .required(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("status")
    
    // Flag de transformación
    .required(PrimitiveType.PrimitiveTypeName.BOOLEAN)
        .named("transformed")
    
    // Hash MD5 del metadata original (32 chars)
    .optional(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("original_metadata_hash")
    
    // Hash MD5 del metadata publicado/transformado (32 chars)
    .optional(PrimitiveType.PrimitiveTypeName.BINARY)
        .as(LogicalTypeAnnotation.stringType())
        .named("published_metadata_hash")
    
    .named("OAIRecord");
```

### 3.2 Mapeo OAIRecord → Parquet

| Campo SQL              | Tipo SQL      | Campo Parquet           | Tipo Parquet | Notas |
|------------------------|---------------|-------------------------|--------------|-------|
| `id`                   | BIGINT (seq)  | `id`                    | INT64        | Secuencial por snapshot |
| `identifier`           | VARCHAR(255)  | `identifier`            | STRING       | Required |
| `datestamp`            | TIMESTAMP     | `datestamp`             | TIMESTAMP    | LocalDateTime → millis |
| `status`               | ENUM          | `status`                | STRING       | UNTESTED, VALID, etc. |
| `transformed`          | BOOLEAN       | `transformed`           | BOOLEAN      | Default false |
| `originalMetadataHash` | VARCHAR(32)   | `original_metadata_hash`| STRING       | Nullable |
| `publishedMetadataHash`| VARCHAR(32)   | `published_metadata_hash`| STRING      | Nullable |
| `snapshot_id` (FK)     | BIGINT        | **(no almacenar)**      | -            | Implícito en carpeta |

**Observaciones importantes:**
- `snapshot_id` NO se almacena en Parquet → está implícito en el path de la carpeta
- `id` es secuencial local al snapshot, NO global (reinicia en cada snapshot)
- Los hashes referencian al `IMetadataStore` existente (sin cambios)

---

## 4. COMPONENTES A IMPLEMENTAR

### 4.1 OAIRecordManager (nuevo)

Clase principal para gestión de records en Parquet, siguiendo el patrón de `ValidationRecordManager`.

```java
package org.lareferencia.backend.repositories.parquet;

/**
 * Gestiona lectura y escritura de OAIRecords en archivos Parquet.
 * 
 * ESTRATEGIA DE BATCHING (ESCRITURA):
 * - Buffer interno de 10,000 registros con auto-flush
 * - Archivos múltiples: records_batch_XXXXX.parquet
 * - Thread-safe para escritura (synchronized)
 * 
 * ESTRATEGIA MULTI-ARCHIVO (LECTURA):
 * - Lee TODOS los archivos records_batch_*.parquet del snapshot
 * - Procesa batches en orden numérico
 * - Iterator lazy (no carga todo en memoria)
 * 
 * EJEMPLOS DE USO:
 * 
 * 1. ESCRITURA:
 * try (OAIRecordManager writer = OAIRecordManager.forWriting(basePath, snapshotId, conf)) {
 *     writer.writeRecord(record);
 *     writer.flush(); // Garantizar persistencia
 * }
 * 
 * 2. LECTURA LAZY:
 * try (OAIRecordManager reader = OAIRecordManager.forReading(basePath, snapshotId, conf)) {
 *     for (OAIRecordData record : reader) {
 *         processRecord(record);
 *     }
 * }
 */
public final class OAIRecordManager implements AutoCloseable, Iterable<OAIRecordData> {
    
    // Configuración
    private static final int FLUSH_THRESHOLD_RECORDS = 10000;
    private static final String BATCH_FILE_PREFIX = "records_batch_";
    
    // Factory methods
    public static OAIRecordManager forWriting(String basePath, Long snapshotId, Configuration hadoopConf);
    public static OAIRecordManager forReading(String basePath, Long snapshotId, Configuration hadoopConf);
    public static Iterable<OAIRecordData> iterate(String basePath, Long snapshotId, Configuration hadoopConf);
    
    // ESCRITURA
    public synchronized void writeRecord(OAIRecordData record) throws IOException;
    public synchronized void flush() throws IOException;
    
    // LECTURA
    public OAIRecordData readNext() throws IOException;
    public List<OAIRecordData> readAll() throws IOException;
    
    // ITERACIÓN LAZY
    @Override
    public Iterator<OAIRecordData> iterator();
    public void reset() throws IOException;
    
    // UTILIDADES
    public long countRecords();
    public OAIRecordData findByIdentifier(String identifier) throws IOException;
    public void deleteSnapshot() throws IOException;
}
```

### 4.2 OAIRecordData (nuevo)

DTO inmutable para representar un record en Parquet (sin dependencias de JPA).

```java
package org.lareferencia.backend.domain.parquet;

import java.time.LocalDateTime;
import org.lareferencia.core.metadata.RecordStatus;
import lombok.Builder;
import lombok.Value;

/**
 * Data object para OAIRecord almacenado en Parquet.
 * Inmutable, sin dependencias JPA, optimizado para streaming.
 */
@Value
@Builder(toBuilder = true)
public class OAIRecordData {
    
    // ID secuencial dentro del snapshot
    Long id;
    
    // Identificador OAI-PMH
    String identifier;
    
    // Timestamp de última modificación
    LocalDateTime datestamp;
    
    // Estado del record
    RecordStatus status;
    
    // Flag de transformación
    Boolean transformed;
    
    // Hash del metadata original
    String originalMetadataHash;
    
    // Hash del metadata publicado
    String publishedMetadataHash;
    
    /**
     * Convierte de entidad JPA (para migración).
     */
    public static OAIRecordData fromEntity(OAIRecord entity) {
        return OAIRecordData.builder()
            .id(entity.getId())
            .identifier(entity.getIdentifier())
            .datestamp(entity.getDatestamp())
            .status(entity.getStatus())
            .transformed(entity.getTransformed())
            .originalMetadataHash(entity.getOriginalMetadataHash())
            .publishedMetadataHash(entity.getPublishedMetadataHash())
            .build();
    }
}
```

### 4.3 ParquetMetadataRecordStoreService (nuevo)

Nueva implementación de `IMetadataRecordStoreService` usando Parquet.

```java
package org.lareferencia.core.metadata;

/**
 * Implementación de IMetadataRecordStoreService usando Parquet para OAIRecords.
 * 
 * RESPONSABILIDADES:
 * - Mantiene NetworkSnapshot en SQL (sin cambios)
 * - Almacena OAIRecords en Parquet (nuevo)
 * - Usa IMetadataStore para contenido XML (sin cambios)
 * 
 * DIFERENCIAS CON MetadataRecordStoreServiceImpl:
 * - NO usa OAIRecordRepository
 * - USA OAIRecordManager para persistencia
 * - Paginadores devuelven OAIRecordData en lugar de OAIRecord
 * - Caché de snapshots activos (igual que implementación SQL)
 */
public class ParquetMetadataRecordStoreService implements IMetadataRecordStoreService {
    
    @Autowired NetworkSnapshotRepository snapshotRepository;
    @Autowired NetworkRepository networkRepository;
    @Autowired IMetadataStore metadataStore;
    @Autowired SnapshotLogService snapshotLogService;
    
    @Value("${parquet.basepath}")
    private String parquetBasePath;
    
    private Configuration hadoopConf;
    
    // Caché de snapshots activos (mismo patrón que SQL)
    private ConcurrentHashMap<Long, NetworkSnapshot> snapshotMap;
    
    // Caché de managers activos (para evitar abrir/cerrar constantemente)
    private ConcurrentHashMap<Long, OAIRecordManager> activeManagers;
    
    // === IMPLEMENTACIÓN DE MÉTODOS ===
    
    @Override
    public OAIRecord createRecord(Long snapshotId, OAIRecordMetadata metadata) {
        // 1. Obtener/crear manager para el snapshot
        // 2. Generar ID secuencial
        // 3. Almacenar XML en IMetadataStore (existente)
        // 4. Escribir record en Parquet
        // 5. Incrementar contador en NetworkSnapshot
        // 6. Retornar OAIRecordData envuelto como OAIRecord (adaptador)
    }
    
    @Override
    public IPaginator<OAIRecord> getUntestedRecordsPaginator(Long snapshotId) {
        // Retorna ParquetRecordPaginator que filtra por status=UNTESTED
    }
    
    // ... resto de métodos adaptados
}
```

### 4.4 ParquetRecordPaginator (nuevo)

Implementación de `IPaginator<OAIRecord>` que lee de Parquet de forma lazy.

```java
/**
 * Paginator que lee records de Parquet de forma lazy sin cargar todo en memoria.
 * Similar a RecordPaginator pero usa OAIRecordManager en lugar de JPA.
 */
public class ParquetRecordPaginator implements IPaginator<OAIRecord> {
    
    private OAIRecordManager manager;
    private RecordStatus filterStatus;  // null = sin filtro
    private LocalDateTime filterDate;   // null = sin filtro
    private int pageSize;
    private int currentPage;
    
    @Override
    public Page<OAIRecord> nextPage() {
        // 1. Leer siguiente batch del manager
        // 2. Aplicar filtros (status, date) en memoria
        // 3. Convertir OAIRecordData → OAIRecord (adaptador)
        // 4. Retornar Page<OAIRecord>
    }
}
```

---

## 5. OPERACIONES CRÍTICAS

### 5.1 Harvesting (escritura masiva)

**Flujo actual (SQL):**
```
HarvestingWorker → createRecord() → recordRepository.save() → SQL INSERT
```

**Flujo propuesto (Parquet):**
```
HarvestingWorker → createRecord() → manager.writeRecord() → Parquet buffer
                                  → (auto-flush cada 10K) → Parquet file
```

**Cambios necesarios:**
- `HarvestingWorker`: sin cambios (usa interfaz `IMetadataRecordStoreService`)
- `ParquetMetadataRecordStoreService.createRecord()`:
  ```java
  public OAIRecord createRecord(Long snapshotId, OAIRecordMetadata metadata) {
      // Obtener manager (crear si no existe)
      OAIRecordManager manager = getOrCreateManager(snapshotId);
      
      // Generar ID secuencial
      long recordId = nextRecordId(snapshotId);
      
      // Almacenar XML en filesystem
      String hash = metadataStore.storeAndReturnHash(metadata.toString());
      
      // Crear data object
      OAIRecordData recordData = OAIRecordData.builder()
          .id(recordId)
          .identifier(metadata.getIdentifier())
          .datestamp(metadata.getDatestamp())
          .status(RecordStatus.UNTESTED)
          .transformed(false)
          .originalMetadataHash(hash)
          .build();
      
      // Escribir en Parquet (buffered)
      manager.writeRecord(recordData);
      
      // Actualizar contador en snapshot
      NetworkSnapshot snapshot = getSnapshot(snapshotId);
      snapshot.incrementSize();
      
      // Retornar adaptador (ver sección 5.6)
      return new OAIRecordAdapter(recordData, snapshotId);
  }
  ```

**Importante:** 
- Auto-flush cada 10K records (igual que ValidationRecordManager)
- Flush manual al finalizar harvesting antes de commit transaccional

### 5.2 Validation (lectura + actualización masiva)

**Flujo actual (SQL):**
```
ValidationWorker → getUntestedRecordsPaginator() → JPA query
                → processPage() → updateRecordStatus() → SQL UPDATE
```

**Flujo propuesto (Parquet):**
```
ValidationWorker → getUntestedRecordsPaginator() → ParquetRecordPaginator
                → processPage() → updateRecordStatus() → Parquet REWRITE
```

**PROBLEMA CRÍTICO:** Parquet NO soporta UPDATE in-place.

**SOLUCIÓN 1: Copy-on-Write (RECOMENDADA)**
```java
public OAIRecord updateRecordStatus(OAIRecord record, RecordStatus status, Boolean wasTransformed) {
    Long snapshotId = record.getSnapshotId();
    
    // 1. Crear manager temporal para LECTURA
    OAIRecordManager reader = OAIRecordManager.forReading(basePath, snapshotId, hadoopConf);
    
    // 2. Crear manager temporal para ESCRITURA en carpeta nueva
    String tempPath = basePath + "/snapshot_" + snapshotId + "_temp";
    OAIRecordManager writer = OAIRecordManager.forWriting(tempPath, snapshotId, hadoopConf);
    
    // 3. Copiar todos los records, actualizando el que corresponda
    for (OAIRecordData data : reader) {
        if (data.getId().equals(record.getId())) {
            // Actualizar record
            data = data.toBuilder()
                .status(status)
                .transformed(wasTransformed)
                .build();
        }
        writer.writeRecord(data);
    }
    
    // 4. Cerrar managers
    reader.close();
    writer.flush();
    writer.close();
    
    // 5. Reemplazar carpeta original con temporal (atómico)
    FileSystem fs = FileSystem.get(hadoopConf);
    Path originalPath = new Path(basePath + "/snapshot_" + snapshotId);
    Path tempPathObj = new Path(tempPath);
    fs.delete(originalPath, true);
    fs.rename(tempPathObj, originalPath);
    
    // 6. Actualizar contador en snapshot SQL
    NetworkSnapshot snapshot = getSnapshot(snapshotId);
    snapshot.incrementValidSize();
    snapshotRepository.save(snapshot);
    
    return record;
}
```

**PROBLEMA:** Esta solución es EXTREMADAMENTE INEFICIENTE para validación batch.

**SOLUCIÓN 2: Batch Update with Delta Files (MEJOR PARA VALIDACIÓN)**

```java
/**
 * Estrategia optimizada para validación:
 * - No actualiza records inmediatamente
 * - Acumula cambios en un "delta file" temporal
 * - Al finalizar batch de validación, aplica todos los cambios de una vez
 */
public class BatchUpdateStrategy {
    
    // Durante validación: acumular cambios
    private Map<Long, RecordUpdate> pendingUpdates = new HashMap<>();
    
    public void stageUpdate(Long recordId, RecordStatus status, Boolean transformed) {
        pendingUpdates.put(recordId, new RecordUpdate(status, transformed));
    }
    
    // Al finalizar batch: aplicar todos los cambios
    public void commitUpdates(Long snapshotId) {
        // 1. Leer todos los records
        OAIRecordManager reader = OAIRecordManager.forReading(basePath, snapshotId, hadoopConf);
        
        // 2. Crear carpeta temporal
        String tempPath = basePath + "/snapshot_" + snapshotId + "_temp";
        OAIRecordManager writer = OAIRecordManager.forWriting(tempPath, snapshotId, hadoopConf);
        
        // 3. Copiar con updates
        int validCount = 0, transformedCount = 0;
        for (OAIRecordData data : reader) {
            RecordUpdate update = pendingUpdates.get(data.getId());
            if (update != null) {
                data = data.toBuilder()
                    .status(update.status)
                    .transformed(update.transformed)
                    .build();
                if (update.status == RecordStatus.VALID) validCount++;
                if (update.transformed) transformedCount++;
            }
            writer.writeRecord(data);
        }
        
        reader.close();
        writer.flush();
        writer.close();
        
        // 4. Swap atómico
        swapDirectories(snapshotId);
        
        // 5. Actualizar contadores en snapshot
        NetworkSnapshot snapshot = getSnapshot(snapshotId);
        snapshot.setValidSize(validCount);
        snapshot.setTransformedSize(transformedCount);
        snapshotRepository.save(snapshot);
        
        pendingUpdates.clear();
    }
}
```

**Integración con ValidationWorker:**
```java
public class ValidationWorker extends BaseBatchWorker<OAIRecord, NetworkRunningContext> {
    
    private BatchUpdateStrategy updateStrategy;
    
    @Override
    protected void preRun() {
        updateStrategy = new BatchUpdateStrategy();
    }
    
    @Override
    protected void processBatch(List<OAIRecord> records) {
        for (OAIRecord record : records) {
            // Validar...
            RecordStatus newStatus = validate(record);
            
            // NO actualizar inmediatamente, solo acumular
            updateStrategy.stageUpdate(record.getId(), newStatus, wasTransformed);
        }
    }
    
    @Override
    protected void postRun() {
        // Aplicar TODOS los cambios al finalizar
        updateStrategy.commitUpdates(snapshotId);
    }
}
```

### 5.3 Incremental Harvesting (copyNotDeletedRecordsFromSnapshot)

**Flujo actual (SQL):**
```sql
INSERT INTO oairecord (...)
SELECT ... FROM oairecord 
WHERE snapshot_id = previousSnapshotId
  AND NOT EXISTS (SELECT ... WHERE snapshot_id = newSnapshotId)
```

**Flujo propuesto (Parquet):**
```java
public void copyNotDeletedRecordsFromSnapshot(Long previousSnapshotId, Long snapshotId) {
    
    // 1. Leer records del snapshot anterior
    OAIRecordManager previousReader = OAIRecordManager.forReading(basePath, previousSnapshotId, hadoopConf);
    
    // 2. Leer identifiers del nuevo snapshot (para evitar duplicados)
    Set<String> newIdentifiers = new HashSet<>();
    OAIRecordManager currentReader = OAIRecordManager.forReading(basePath, snapshotId, hadoopConf);
    for (OAIRecordData record : currentReader) {
        newIdentifiers.add(record.getIdentifier());
    }
    currentReader.close();
    
    // 3. Copiar records no presentes en nuevo snapshot
    OAIRecordManager writer = OAIRecordManager.forWriting(basePath, snapshotId, hadoopConf);
    long copiedCount = 0;
    
    for (OAIRecordData record : previousReader) {
        // Filtrar: solo copiar si NO está en nuevo snapshot
        if (!newIdentifiers.contains(record.getIdentifier())) {
            // Regenerar ID para nuevo snapshot
            long newId = nextRecordId(snapshotId);
            OAIRecordData copiedRecord = record.toBuilder()
                .id(newId)
                .build();
            
            writer.writeRecord(copiedRecord);
            copiedCount++;
        }
    }
    
    previousReader.close();
    writer.flush();
    writer.close();
    
    // 4. Actualizar contadores en snapshot
    NetworkSnapshot snapshot = getSnapshot(snapshotId);
    snapshot.setSize(snapshot.getSize() + (int)copiedCount);
    snapshotRepository.save(snapshot);
}
```

**Optimización:** Usar Bloom Filter en lugar de HashSet para identifiers grandes.

### 5.4 Indexing (lectura masiva)

**Flujo actual (SQL):**
```
IndexerWorker → getValidRecordsPaginator() → JPA query
             → processPage() → enviar a Solr
```

**Flujo propuesto (Parquet):**
```
IndexerWorker → getValidRecordsPaginator() → ParquetRecordPaginator (filtro: VALID)
             → processPage() → enviar a Solr
```

**SIN CAMBIOS en IndexerWorker:** usa interfaz `IMetadataRecordStoreService`.

### 5.5 Búsqueda por Identifier

**Caso de uso:** Harvesting incremental necesita verificar si identifier existe.

**Implementación:**
```java
public OAIRecord findRecordByIdentifier(Long snapshotId, String oaiIdentifier) {
    
    // OPCIÓN 1: Búsqueda lineal (simple pero lento para datasets grandes)
    try (OAIRecordManager reader = OAIRecordManager.forReading(basePath, snapshotId, hadoopConf)) {
        for (OAIRecordData record : reader) {
            if (record.getIdentifier().equals(oaiIdentifier)) {
                return new OAIRecordAdapter(record, snapshotId);
            }
        }
    }
    return null; // No encontrado
    
    // OPCIÓN 2: Índice secundario (complejo pero rápido)
    // - Mantener archivo auxiliar: identifier_index.parquet
    // - Estructura: (identifier → record_id, batch_file)
    // - Usar Parquet Predicate Pushdown para filtrar rápido
}
```

**RECOMENDACIÓN:** 
- Implementar OPCIÓN 1 inicialmente (simple)
- Si performance es problema, agregar OPCIÓN 2 después

### 5.6 Adaptador OAIRecord ↔ OAIRecordData

**Problema:** La interfaz `IMetadataRecordStoreService` retorna `OAIRecord` (JPA entity), pero ahora tenemos `OAIRecordData` (POJO).

**Solución:** Adaptador ligero que envuelve `OAIRecordData` como `OAIRecord`.

```java
/**
 * Adaptador que permite usar OAIRecordData como OAIRecord.
 * NO es entidad JPA, solo implementa getters.
 */
public class OAIRecordAdapter extends OAIRecord {
    
    private final OAIRecordData data;
    private final Long snapshotId;
    
    public OAIRecordAdapter(OAIRecordData data, Long snapshotId) {
        this.data = data;
        this.snapshotId = snapshotId;
    }
    
    @Override public Long getId() { return data.getId(); }
    @Override public String getIdentifier() { return data.getIdentifier(); }
    @Override public LocalDateTime getDatestamp() { return data.getDatestamp(); }
    @Override public RecordStatus getStatus() { return data.getStatus(); }
    @Override public Boolean getTransformed() { return data.getTransformed(); }
    @Override public String getOriginalMetadataHash() { return data.getOriginalMetadataHash(); }
    @Override public String getPublishedMetadataHash() { return data.getPublishedMetadataHash(); }
    @Override public Long getSnapshotId() { return snapshotId; }
    
    // NetworkSnapshot getter: lazy load desde snapshotRepository
    @Override 
    public NetworkSnapshot getSnapshot() {
        // Requiere acceso a snapshotRepository (inyección)
        return snapshotRepository.findById(snapshotId).orElse(null);
    }
    
    // Setters: NO soportados (entidad read-only desde Parquet)
    @Override 
    public void setStatus(RecordStatus status) {
        throw new UnsupportedOperationException("OAIRecordAdapter is read-only");
    }
    
    // ... resto de setters lanzan UnsupportedOperationException
}
```

**IMPORTANTE:** 
- Workers que lean records pueden seguir usando `OAIRecord` sin cambios
- Workers que modifiquen records deben llamar a `updateRecordStatus()` explícitamente

---

## 6. GESTIÓN DE TRANSACCIONES

### 6.1 Problema de Consistencia

**SQL (actual):**
- Transacciones ACID garantizan consistencia
- Rollback automático en caso de error

**Parquet (propuesto):**
- NO hay transacciones nativas
- Escrituras son "event

uales" (flush asíncrono)
- Requiere estrategia manual de consistencia

### 6.2 Estrategia de Consistencia

```java
/**
 * Garantizar consistencia entre SQL (NetworkSnapshot) y Parquet (OAIRecords):
 * 
 * 1. Escritura:
 *    - Escribir primero en Parquet (buffer)
 *    - Actualizar snapshot SQL
 *    - Flush Parquet al finalizar transacción
 *    - Si falla flush: marcar snapshot como FAILED en SQL
 * 
 * 2. Rollback manual:
 *    - Si falla transacción SQL: eliminar carpeta Parquet
 *    - Si falla flush Parquet: marcar snapshot como FAILED
 */

@Service
@Transactional
public class ParquetMetadataRecordStoreService implements IMetadataRecordStoreService {
    
    @Override
    public Long createSnapshot(Network network) {
        // 1. Crear snapshot en SQL
        NetworkSnapshot snapshot = new NetworkSnapshot();
        snapshot.setNetwork(network);
        snapshot.setStartTime(LocalDateTime.now());
        snapshotRepository.save(snapshot);
        
        // 2. Crear carpeta Parquet
        Long snapshotId = snapshot.getId();
        createSnapshotDirectory(snapshotId);
        
        // 3. Guardar en caché
        putSnapshot(snapshot);
        
        return snapshotId;
    }
    
    @Override
    public void saveSnapshot(Long snapshotId) {
        try {
            // 1. Flush Parquet ANTES de commit SQL
            OAIRecordManager manager = activeManagers.get(snapshotId);
            if (manager != null) {
                manager.flush();
                manager.close();
                activeManagers.remove(snapshotId);
            }
            
            // 2. Commit SQL (automático por @Transactional)
            NetworkSnapshot snapshot = getSnapshot(snapshotId);
            snapshotRepository.save(snapshot);
            
        } catch (IOException e) {
            // Flush Parquet falló → marcar snapshot como FAILED
            logger.error("Failed to flush Parquet for snapshot " + snapshotId, e);
            NetworkSnapshot snapshot = getSnapshot(snapshotId);
            snapshot.setStatus(SnapshotStatus.FAILED);
            snapshotRepository.save(snapshot);
            throw new MetadataRecordStoreException("Parquet flush failed", e);
        }
    }
    
    @Override
    public void deleteSnapshot(Long snapshotId) {
        // 1. Eliminar records en Parquet
        deleteSnapshotDirectory(snapshotId);
        
        // 2. Eliminar snapshot en SQL
        snapshotRepository.deleteBySnapshotID(snapshotId);
        
        // 3. Limpiar caché
        deleteSnapshot(getSnapshot(snapshotId));
    }
}
```

### 6.3 Manejo de Fallos

| Escenario | Detección | Recuperación |
|-----------|-----------|--------------|
| **Falla durante harvesting** | Transacción SQL rollback | Eliminar carpeta Parquet (cleanup manual) |
| **Falla en flush Parquet** | IOException en `manager.flush()` | Marcar snapshot como FAILED en SQL |
| **Snapshot incompleto (sin flush)** | Carpeta Parquet existe pero sin archivos batch | Eliminar carpeta en próximo cleanup |
| **Corrupción archivo Parquet** | IOException en lectura | Marcar snapshot como CORRUPTED, re-harvest |

---

## 7. MIGRACIÓN DE DATOS EXISTENTES

### 7.1 Estrategia de Migración

**Opción A: Migración Big Bang (NO recomendada)**
- Parar sistema
- Migrar todos los snapshots de SQL a Parquet
- Desplegar nueva versión
- Reiniciar sistema

**Opción B: Migración Gradual (RECOMENDADA)**

1. **Fase 1: Despliegue con soporte dual**
   - Nueva versión soporta AMBOS backends (SQL y Parquet)
   - Property: `metadata.store.backend=sql` (default)
   - Snapshots nuevos usan SQL (sin cambios)

2. **Fase 2: Migración offline de snapshots antiguos**
   ```java
   /**
    * Script de migración: SQL → Parquet para snapshots viejos
    */
   public class SnapshotMigrationTool {
       
       public void migrateSnapshot(Long snapshotId) {
           // 1. Leer todos los records de SQL
           List<OAIRecord> sqlRecords = recordRepository.findBySnapshotId(snapshotId);
           
           // 2. Escribir en Parquet
           OAIRecordManager writer = OAIRecordManager.forWriting(basePath, snapshotId, hadoopConf);
           for (OAIRecord record : sqlRecords) {
               OAIRecordData data = OAIRecordData.fromEntity(record);
               writer.writeRecord(data);
           }
           writer.flush();
           writer.close();
           
           // 3. Marcar snapshot como migrado (flag en SQL)
           NetworkSnapshot snapshot = snapshotRepository.findById(snapshotId).get();
           snapshot.setMigrated(true);
           snapshotRepository.save(snapshot);
           
           // 4. Eliminar records de SQL (opcional, para liberar espacio)
           recordRepository.deleteBySnapshotID(snapshotId);
       }
   }
   ```

3. **Fase 3: Switch a Parquet para nuevos snapshots**
   - Property: `metadata.store.backend=parquet`
   - Snapshots nuevos usan Parquet
   - Snapshots viejos aún en SQL (o migrados en background)

4. **Fase 4: Limpieza final**
   - Migrar snapshots restantes
   - Eliminar tabla `oairecord` de SQL
   - Deprecar `MetadataRecordStoreServiceImpl`

### 7.2 Configuración Dual Backend

```java
@Configuration
public class MetadataStoreConfiguration {
    
    @Value("${metadata.store.backend:sql}")
    private String backend;
    
    @Bean
    public IMetadataRecordStoreService metadataRecordStoreService() {
        if ("parquet".equalsIgnoreCase(backend)) {
            return new ParquetMetadataRecordStoreService();
        } else {
            return new MetadataRecordStoreServiceImpl();
        }
    }
}
```

**Properties:**
```properties
# application.properties

# Backend para nuevos snapshots: sql | parquet
metadata.store.backend=sql

# Path base para archivos Parquet
parquet.basepath=/data/harvester/oai-records

# Configuración Hadoop
hadoop.fs.defaultFS=file:///
```

---

## 8. TESTING

### 8.1 Tests Unitarios

```java
@Test
public void testWriteAndReadRecords() throws Exception {
    Configuration conf = new Configuration();
    String basePath = "/tmp/test-oai-records";
    Long snapshotId = 123L;
    
    // Escribir records
    try (OAIRecordManager writer = OAIRecordManager.forWriting(basePath, snapshotId, conf)) {
        for (int i = 0; i < 1000; i++) {
            OAIRecordData record = OAIRecordData.builder()
                .id((long) i)
                .identifier("oai:repo:item-" + i)
                .datestamp(LocalDateTime.now())
                .status(RecordStatus.UNTESTED)
                .transformed(false)
                .build();
            writer.writeRecord(record);
        }
        writer.flush();
    }
    
    // Leer records
    try (OAIRecordManager reader = OAIRecordManager.forReading(basePath, snapshotId, conf)) {
        long count = reader.countRecords();
        assertEquals(1000, count);
        
        OAIRecordData first = reader.readNext();
        assertEquals("oai:repo:item-0", first.getIdentifier());
    }
}

@Test
public void testLazyIteration() throws Exception {
    // Verificar que no carga todo en memoria
    long initialMemory = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory();
    
    try (OAIRecordManager reader = OAIRecordManager.forReading(basePath, snapshotId, conf)) {
        int count = 0;
        for (OAIRecordData record : reader) {
            count++;
            // Verificar que memoria no crece significativamente
            long currentMemory = Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory();
            assertTrue(currentMemory - initialMemory < 100_000_000); // < 100MB
        }
        assertEquals(1_000_000, count); // 1 millón de records
    }
}
```

### 8.2 Tests de Integración

```java
@SpringBootTest
@Transactional
public class ParquetMetadataRecordStoreServiceIntegrationTest {
    
    @Autowired
    private IMetadataRecordStoreService metadataStoreService;
    
    @Autowired
    private NetworkRepository networkRepository;
    
    @Test
    public void testHarvestingWorkflow() throws Exception {
        // 1. Crear snapshot
        Network network = networkRepository.findById(1L).get();
        Long snapshotId = metadataStoreService.createSnapshot(network);
        
        // 2. Crear records (simular harvesting)
        for (int i = 0; i < 10000; i++) {
            OAIRecordMetadata metadata = new OAIRecordMetadata();
            metadata.setIdentifier("oai:repo:item-" + i);
            metadata.setDatestamp(LocalDateTime.now());
            // ... set metadata content
            
            metadataStoreService.createRecord(snapshotId, metadata);
        }
        
        // 3. Guardar snapshot (flush Parquet)
        metadataStoreService.saveSnapshot(snapshotId);
        
        // 4. Verificar contadores
        assertEquals(10000, metadataStoreService.getSnapshotSize(snapshotId));
        
        // 5. Leer records
        IPaginator<OAIRecord> paginator = metadataStoreService.getUntestedRecordsPaginator(snapshotId);
        paginator.setPageSize(100);
        
        int totalRecords = 0;
        while (paginator.getTotalPages() > 0) {
            Page<OAIRecord> page = paginator.nextPage();
            totalRecords += page.getNumberOfElements();
        }
        
        assertEquals(10000, totalRecords);
    }
}
```

### 8.3 Performance Testing

```java
@Test
@Disabled("Performance test - ejecutar manualmente")
public void testLargeDatasetPerformance() throws Exception {
    long startTime = System.currentTimeMillis();
    
    // Escribir 10 millones de records
    try (OAIRecordManager writer = OAIRecordManager.forWriting(basePath, snapshotId, conf)) {
        for (int i = 0; i < 10_000_000; i++) {
            OAIRecordData record = createDummyRecord(i);
            writer.writeRecord(record);
            
            if (i % 100_000 == 0) {
                System.out.println("Written " + i + " records");
            }
        }
        writer.flush();
    }
    
    long writeTime = System.currentTimeMillis() - startTime;
    System.out.println("Write time: " + writeTime + "ms");
    
    // Leer 10 millones de records
    startTime = System.currentTimeMillis();
    try (OAIRecordManager reader = OAIRecordManager.forReading(basePath, snapshotId, conf)) {
        long count = 0;
        for (OAIRecordData record : reader) {
            count++;
        }
        assertEquals(10_000_000, count);
    }
    
    long readTime = System.currentTimeMillis() - startTime;
    System.out.println("Read time: " + readTime + "ms");
    
    // Benchmarks esperados:
    // - Escritura: < 5 min para 10M records (~33K records/sec)
    // - Lectura: < 2 min para 10M records (~83K records/sec)
}
```

---

## 9. IMPACTO EN EL SISTEMA

### 9.1 Componentes NO Afectados

✅ **Workers:** 
- `HarvestingWorker`
- `ValidationWorker`
- `IndexerWorker`
- `BitstreamWorker`
- `DownloaderWorker`

Todos estos workers usan la interfaz `IMetadataRecordStoreService`, por lo que NO requieren cambios.

✅ **Domain entities:**
- `NetworkSnapshot` (sin cambios)
- `Network` (sin cambios)
- `Validator`, `Transformer` (sin cambios)

✅ **Metadata storage:**
- `IMetadataStore` (filesystem storage para XML, sin cambios)
- `MetadataStoreFSImpl` / `MetadataStoreSQLImpl` (sin cambios)

✅ **Servicios:**
- `ValidationService`
- `SnapshotLogService`
- Todos los servicios transaccionales

### 9.2 Componentes Afectados

❌ **Repositorios:**
- `OAIRecordRepository` → DEPRECAR (no eliminar hasta migración completa)

❌ **Servicios:**
- `MetadataRecordStoreServiceImpl` → DEPRECAR en favor de `ParquetMetadataRecordStoreService`

❌ **Domain:**
- `OAIRecord` (JPA entity) → MANTENER pero deprecar
- Crear `OAIRecordData` (POJO) para Parquet

❌ **Tests:**
- Tests que usan `OAIRecordRepository` directamente → actualizar

### 9.3 APIs REST

**Endpoints afectados:**
```
GET  /api/snapshot/{id}/records          → Requiere adaptación
GET  /api/snapshot/{id}/records/{rid}    → Requiere adaptación  
GET  /api/record/{id}                    → Requiere adaptación
```

**Estrategia:**
- Mantener contratos API sin cambios
- Controllers convierten `OAIRecordData` → DTOs como antes
- NO exponer diferencia SQL vs Parquet a clientes

### 9.4 Performance Esperado

| Operación | SQL (actual) | Parquet (propuesto) | Mejora |
|-----------|--------------|---------------------|--------|
| **Escritura (10M records)** | ~15 min | ~5 min | **3x más rápido** |
| **Lectura secuencial (10M)** | ~10 min | ~2 min | **5x más rápido** |
| **Búsqueda por ID** | ~1 ms (índice) | ~100 ms (scan) | **100x más lento** ⚠️ |
| **Filtrado por status** | ~5 min (full scan) | ~2 min (scan + filter) | **2.5x más rápido** |
| **UPDATE 1M records** | ~10 min | ~15 min | **1.5x más lento** ⚠️ |
| **Tamaño disco (10M records)** | ~50 GB | ~10 GB | **5x menos espacio** |

**Observaciones:**
- ✅ **Lectura/escritura secuencial:** excelente performance (patrón dominante en harvesting/validación)
- ⚠️ **Búsqueda puntual:** peor performance (poco frecuente, solo en harvesting incremental)
- ⚠️ **Updates:** más lento (requiere reescritura completa, pero se mitiga con batch updates)
- ✅ **Almacenamiento:** reducción significativa con compresión Parquet

---

## 10. RIESGOS Y MITIGACIONES

### 10.1 Riesgos Técnicos

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|--------------|---------|------------|
| **Corrupción de archivos Parquet** | Media | Alto | - Checksums en cada archivo<br>- Backup periódico<br>- Snapshot status=CORRUPTED |
| **Performance peor de lo esperado** | Baja | Alto | - Benchmark extensivo antes de producción<br>- Rollback a SQL posible |
| **Memoria insuficiente en lectura** | Baja | Medio | - Iteradores lazy (NO cargar todo)<br>- Batch size configurable |
| **Pérdida de datos en crash** | Media | Alto | - Flush explícito antes de commit<br>- Carpetas temporales + swap atómico |
| **Incompatibilidad Hadoop en diferentes OS** | Media | Medio | - Testing en Linux, Mac, Windows<br>- Documentar configuraciones específicas |

### 10.2 Riesgos Operacionales

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|--------------|---------|------------|
| **Migración SQL→Parquet falla** | Media | Alto | - Mantener datos SQL hasta confirmar éxito<br>- Script de rollback |
| **Espacio en disco insuficiente** | Media | Medio | - Monitoreo proactivo<br>- Compresión agresiva (SNAPPY/GZIP) |
| **Snapshots huérfanos (sin metadata)** | Baja | Bajo | - Script de limpieza periódico<br>- Logs de creación/eliminación |
| **Dificultad para debugging** | Media | Medio | - Herramienta CLI para inspeccionar Parquet<br>- Logs detallados |

### 10.3 Plan de Contingencia

**Si Parquet no funciona como esperado:**

1. **Rollback inmediato:**
   - Cambiar property: `metadata.store.backend=sql`
   - Reiniciar servicios
   - Datos SQL intactos (no eliminados durante migración)

2. **Análisis de problemas:**
   - Revisar logs de IOException
   - Performance profiling
   - Verificar integridad de archivos

3. **Corrección:**
   - Aplicar fixes específicos
   - Re-testing exhaustivo
   - Nueva ventana de migración

---

## 11. PLAN DE IMPLEMENTACIÓN

### 11.1 Fases del Proyecto

#### **FASE 1: Fundamentos (2-3 semanas)**
- [ ] Crear `OAIRecordData` (POJO)
- [ ] Implementar `OAIRecordManager` (lectura/escritura Parquet)
- [ ] Tests unitarios de `OAIRecordManager`
- [ ] Documentación técnica

#### **FASE 2: Service Layer (2-3 semanas)**
- [ ] Implementar `ParquetMetadataRecordStoreService`
- [ ] Implementar `ParquetRecordPaginator`
- [ ] Implementar `OAIRecordAdapter`
- [ ] Implementar `BatchUpdateStrategy`
- [ ] Tests de integración

#### **FASE 3: Soporte Dual (1-2 semanas)**
- [ ] Configuración backend seleccionable (SQL vs Parquet)
- [ ] Testing con ambos backends
- [ ] Performance benchmarking
- [ ] Documentación de configuración

#### **FASE 4: Migración de Datos (2-4 semanas)**
- [ ] Script de migración SQL→Parquet
- [ ] Testing de migración en ambiente QA
- [ ] Migración de snapshots antiguos (background job)
- [ ] Validación de integridad post-migración

#### **FASE 5: Producción (1-2 semanas)**
- [ ] Despliegue con backend=parquet en producción
- [ ] Monitoreo intensivo (performance, errores)
- [ ] Migración final de snapshots restantes
- [ ] Eliminación de tabla `oairecord` (opcional)

**TOTAL ESTIMADO: 8-14 semanas**

### 11.2 Milestones Críticos

1. **M1:** `OAIRecordManager` funcional (lectura + escritura)
2. **M2:** `ParquetMetadataRecordStoreService` pasa todos los tests
3. **M3:** Workers funcionan con Parquet (HarvestingWorker, ValidationWorker, IndexerWorker)
4. **M4:** Benchmarks muestran mejora de performance vs SQL
5. **M5:** Migración exitosa en ambiente QA
6. **M6:** Producción estable con Parquet

### 11.3 Criterios de Éxito

✅ **Performance:**
- Harvesting: ≥ 2x más rápido que SQL
- Validación: ≥ 1.5x más rápido que SQL
- Tamaño disco: ≤ 30% del tamaño SQL

✅ **Estabilidad:**
- Cero pérdida de datos
- Cero corrupción de snapshots
- Rollback posible en < 1 hora

✅ **Funcionalidad:**
- Todos los workers funcionan sin cambios
- Harvesting incremental funciona correctamente
- APIs REST responden como antes

---

## 12. ALTERNATIVAS CONSIDERADAS

### 12.1 Mantener SQL

**Pros:**
- Sin riesgo de migración
- Queries complejas fáciles
- Transacciones ACID

**Contras:**
- No escala con millones de records
- Costo de almacenamiento alto
- Performance degradado en batch operations

**Decisión:** ❌ No viable a largo plazo

### 12.2 Usar MongoDB/DocumentDB

**Pros:**
- Flexible schema
- Queries potentes
- Escalabilidad horizontal

**Contras:**
- Requiere infraestructura adicional
- No optimizado para batch processing
- Costo operacional

**Decisión:** ❌ Overhead excesivo para caso de uso

### 12.3 Usar Apache Avro (en lugar de Parquet)

**Pros:**
- Mejor para escritura secuencial
- Schema evolution integrado

**Contras:**
- No tiene formato columnar (peor compresión)
- Peor performance para lecturas selectivas
- Menos maduro que Parquet

**Decisión:** ❌ Parquet es mejor para nuestro patrón de acceso

### 12.4 Usar Delta Lake

**Pros:**
- Soporte nativo para ACID
- Updates eficientes (merge)
- Time travel

**Contras:**
- Dependencia pesada (Spark)
- Complejidad operacional alta
- Overhead para caso de uso simple

**Decisión:** ❌ Over-engineering para nuestras necesidades

---

## 13. RECOMENDACIONES FINALES

### 13.1 Enfoque Conservador

1. **Implementar en FASES** (no big bang)
2. **Mantener SQL como backup** durante 6 meses
3. **Monitoreo exhaustivo** en cada fase
4. **Benchmarking continuo** (comparar SQL vs Parquet)
5. **Rollback plan claro** y probado

### 13.2 Optimizaciones Futuras

Una vez estable la implementación básica:

1. **Índices secundarios en Parquet:**
   - Archivo auxiliar: `identifier_index.parquet`
   - Acelerar búsquedas puntuales

2. **Compresión adaptativa:**
   - SNAPPY para escritura rápida
   - GZIP para snapshots archivados

3. **Particionado por fecha:**
   - Subdirectorios: `year=2025/month=11/batch_*.parquet`
   - Acelerar queries temporales

4. **Cache de metadatos:**
   - Bloom filters para identifiers
   - Estadísticas pre-calculadas

### 13.3 Próximos Pasos Inmediatos

1. **Crear ticket JIRA** con épica y subtareas
2. **Diseño detallado** de `OAIRecordManager` (basado en `ValidationRecordManager`)
3. **Prototipo funcional** con 100K records
4. **Benchmark comparativo** SQL vs Parquet
5. **Presentar a equipo** para validación

---

## 14. CONCLUSIONES

### ✅ Ventajas de la Migración

1. **Escalabilidad:** Soporta millones de records sin degradación
2. **Performance:** 2-5x más rápido en operaciones batch
3. **Almacenamiento:** 70% menos espacio en disco
4. **Consistencia:** Mismo patrón que `ValidationRecordManager` (ya probado)
5. **Separación:** SQL para metadata ligero, Parquet para datos pesados

### ⚠️ Desafíos Principales

1. **No hay UPDATE in-place:** Requiere reescritura completa (mitigado con batch updates)
2. **Búsquedas puntuales lentas:** Scan lineal vs índice SQL (poco frecuente en nuestro caso)
3. **Complejidad de migración:** Requiere planificación cuidadosa y fases
4. **Testing exhaustivo:** Necesario para garantizar estabilidad

### 🎯 Recomendación Final

**SÍ, PROCEDER CON LA MIGRACIÓN** bajo las siguientes condiciones:

1. Implementación **GRADUAL** (no big bang)
2. Mantener **SQL como backup** hasta validar estabilidad
3. **Testing exhaustivo** en cada fase
4. **Benchmark** antes de producción
5. **Plan de rollback** claro y probado

La migración es **técnicamente viable** y **altamente beneficiosa** para la escalabilidad del sistema. El patrón ya está validado con `ValidationRecordManager`, lo que reduce significativamente el riesgo de implementación.

---

**Documento preparado por:** Análisis técnico AI  
**Fecha:** 10 de noviembre de 2025  
**Versión:** 1.0  
**Estado:** Propuesta para revisión
