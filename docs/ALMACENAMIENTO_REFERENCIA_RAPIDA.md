# Referencia Rápida: Almacenamiento de Datos en LA Referencia v5.0

## 🎯 Quick Reference Sheet

### Dónde se guarda cada cosa

| Qué | Dónde | Cómo | Acceso | Ejemplo |
|-----|-------|------|--------|---------|
| **Metadata Snapshot** | PostgreSQL | `NetworkSnapshot` entity | `ISnapshotStore` | `snapshotStore.createSnapshot(network)` |
| **Metadata Records (XML)** | Filesystem | XML comprimido con GZIP | `IMetadataStore` | `metadataStore.getMetadata(snapshot, hash)` |
| **Records OAI** | Parquet | Binario comprimido | `OAIRecordParquetRepository` | `repo.getIterator(metadata)` |
| **Validación Stats** | JSON (FS) | `validation-stats.json` | `ValidationStatParquetRepository` | `repo.getSnapshotValidationStats(metadata)` |
| **Validación Records** | Parquet | Records con RuleFacts anidados | `ValidationRecordManager` | `manager.readNext()` |
| **Índice Ligero** | Parquet | `validation_index.parquet` | `ValidationRecordManager` | `manager.loadLightweightIndex(status)` |
| **Logs** | Texto | Plain text append | `SnapshotLogService` | `service.addEntry(snapshotId, msg)` |

---

## � Metadata - Estructura Dual-Layer

### Capa 1: PostgreSQL (Metadata Estructural Únicamente)
```sql
-- Tabla network_snapshot (referencias a archivos Parquet)
CREATE TABLE network_snapshot (
    id BIGINT PRIMARY KEY,
    network_id BIGINT NOT NULL,
    size INT,                          -- Total records (denormalizado de catálogo Parquet)
    valid_size INT,                    -- Valid records (denormalizado de stats JSON)
    status VARCHAR(50),                -- HARVESTING_IN_PROGRESS, etc.
    start_time TIMESTAMP,              -- Harvest start
    end_time TIMESTAMP,                -- Harvest end
    ...
);

-- NOTA: El catálogo OAI NO está en BD
-- Los registros OAI se guardan en Parquet:
-- {basePath}/{NETWORK}/snapshots/snapshot_{ID}/catalog/oai_records_batch_*.parquet
```

### Capa 2: Filesystem (Metadata Detallada + Catálogo OAI)

#### 2.1 Metadata XML Comprimido
```
{basePath}/{NETWORK}/metadata/{L1}/{L2}/{L3}/{HASH}.xml.gz

Ejemplo:
/data/lareferencia/IBICT/metadata/A/B/C/ABCDEF123456789.xml.gz
/data/lareferencia/LA_REFERENCIA/metadata/X/Y/Z/XYZABC987654321.xml.gz
```

**Características**:
- ✅ **Deduplicación**: Mismo XML = mismo hash
- ✅ **Particionamiento**: 3 niveles (4,096 particiones)
- ✅ **Búsqueda O(1)**: Hash-based, sin scanning
- ✅ **Compresión**: 70-80% ahorro con GZIP
- ✅ **Isolation**: Separado por network

#### 2.2 Catálogo OAI (Parquet - Inmutable)
```
{basePath}/{NETWORK}/snapshots/snapshot_{ID}/catalog/oai_records_batch_*.parquet

Estructura:
- id: String - Hash MD5 del identifier (PK)
- identifier: String - Identificador OAI único
- datestamp: Timestamp - Fecha de última modificación
- original_metadata_hash: String - Hash MD5 del XML original cosechado
- deleted: Boolean - Flag de eliminación
```

**Características**:
- ✅ **Inmutable**: Se escribe UNA SOLA VEZ, nunca se actualiza
- ✅ **Sin estado de validación**: Solo datos del harvesting
- ✅ **Batching**: Auto-flush cada 10,000 records
- ✅ **Compresión SNAPPY**: ~8 bytes/record
- ✅ **Lectura lazy**: Streaming sin cargar todo en memoria

### API: IMetadataStore
```java
// Guardar metadata y obtener hash
String storeAndReturnHash(SnapshotMetadata snapshotMetadata, String xmlContent);

// Recuperar metadata por hash
String getMetadata(SnapshotMetadata snapshotMetadata, String hash);

// Limpieza
Boolean cleanAndOptimizeStore();
```

### Flujo de Integración

**Harvesting (Catálogo OAI + Metadata XML)**:
```
Harvester
   ↓
1. xmlMetadata = harvester.fetchMetadata(identifier)
   ↓
2. metadataHash = metadataStore.storeAndReturnHash(snapshot, xmlMetadata)
   → FS: /data/lareferencia/.../metadata/{L1}/{L2}/{L3}/{HASH}.xml.gz
   
3. oaiRecord = OAIRecord.create(identifier, datestamp, metadataHash, deleted)
   → Construye record del catálogo OAI
   
4. oaiRecordRepository.saveRecord(snapshotId, oaiRecord)
   → Parquet: snapshot_{ID}/catalog/oai_records_batch_*.parquet (buffered)
   
5. oaiRecordRepository.finalizeSnapshot(snapshotId)
   → Flush final de catálogo (cierra archivos Parquet)
```

**Lectura/Validación**:
```
Validator
   ↓
1. oaiRecord = oaiRecordRepository.getIterator(snapshotMetadata)
   → Parquet: Lee catalogo desde oai_records_batch_*.parquet (streaming)
   
2. xmlContent = metadataStore.getMetadata(snapshot, oaiRecord.getOriginalMetadataHash())
   → FS: /data/lareferencia/.../metadata/{L1}/{L2}/{L3}/{HASH}.xml.gz
   
3. validationResult = validator.validate(xmlContent)
   → Procesa validación
```

---

## �📂 Estructura de Directorios

```
---

## 📂 Estructura de Directorios

### 🗂️ Organización General

Todo el almacenamiento sigue una estructura unificada basada en el `basePath` y el network acronym:

```
{basePath}/
└── {NETWORK}/                        ← Sanitizado (espacios→_, mayúsculas)
    ├── metadata/                     ← Metadata XML (IMetadataStore)
    │   └── {L1}/{L2}/{L3}/          ← Particionamiento de 3 niveles
    │       └── {HASH}.xml.gz        ← Archivo comprimido
    └── snapshots/                    ← Records OAI + Validación + Logs
        └── snapshot_{ID}/
            ├── catalog/              ← OAI Records (Parquet)
            ├── validation/           ← Validación (Parquet)
            └── snapshot.log          ← Logs (Texto)
```

### 📝 Metadata XML (Comprimida con GZIP)

**Ubicación**: `{basePath}/{NETWORK}/metadata/{L1}/{L2}/{L3}/{HASH}.xml.gz`

**Particionamiento**: 
- 3 niveles basados en los primeros 3 caracteres del hash
- Total de particiones posibles: 16³ = 4,096
- Ejemplo: Hash `ABCDEF123...` → Partición `A/B/C/`

**Ejemplo real**:
```
/data/lareferencia/IBICT/metadata/
├── A/
│   ├── B/
│   │   ├── C/
│   │   │   ├── ABCDEF123456789ABC.xml.gz
│   │   │   └── ABCABC987654321XYZ.xml.gz
│   │   └── D/
│   │       └── ABDABC111222333XYZ.xml.gz
│   └── X/
│       └── Y/
│           └── Z/
│               └── AXYZZZ999888777ABC.xml.gz
├── F/
│   └── 0/
│       └── 0/
│           └── F00ABC123456789DEF.xml.gz
└── ... (más particiones)
```

**Características**:
- ✅ Deduplicación: Mismo contenido XML = mismo hash = un solo archivo
- ✅ Búsqueda O(1): Lookup directo por hash sin scanning
- ✅ Compresión GZIP: ~70-80% reducción de espacio
- ✅ Network isolation: Cada red en su directorio

### 📊 Records OAI (Parquet)

**Ubicación**: `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/catalog/oai_records_batch_*.parquet`

**Estructura de batches**:
- Auto-flush cada 10,000 records (configurable)
- Archivos secuenciales: `batch_1.parquet`, `batch_2.parquet`, ...
- Compresión SNAPPY

**Ejemplo real**:
```
/data/lareferencia/IBICT/snapshots/snapshot_101/catalog/
├── oai_records_batch_1.parquet       (10,000 records, ~8 MB)
├── oai_records_batch_2.parquet       (10,000 records, ~8 MB)
└── oai_records_batch_3.parquet       (5,234 records, ~4 MB)

Total: 25,234 records en 3 archivos (20 MB)
```

### ✅ Validación (Dual-Layer: JSON Stats + Parquet Records con Facts Anidados)

**Ubicación Base**: `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/validation/`

La validación usa una **arquitectura eficiente de 2 capas** que elimina la explosión de filas:

#### Layer 1: Estadísticas Agregadas (JSON)
**Archivo**: `validation-stats.json`

Contiene estadísticas precomputadas guardadas **UNA SOLA VEZ**:
```json
{
  "totalRecords": 25234,
  "validRecords": 20100,
  "invalidRecords": 5134,
  "transformedRecords": 18500,
  "ruleStats": {
    "1": { "validCount": 25000, "invalidCount": 234 },
    "2": { "validCount": 24500, "invalidCount": 734 }
  },
  "facets": {
    "record_is_valid": { "true": 20100, "false": 5134 }
  }
}
```

**Ventajas**:
- ✅ Consultas ultra-rápidas (<1ms)
- ✅ Formato legible para debugging
- ✅ No requiere PostgreSQL ni cálculos complejos

#### Layer 2: Records de Validación con Rule Facts Anidados (Parquet)
**Archivos**: `records_batch_*.parquet`

**Estructura**: 1 fila por RECORD con RuleFacts anidados dentro

**Schema Parquet** (estructura anidada):
```
RecordValidation:
├── identifier: String (required)
├── record_id: String (required, PK)
├── datestamp: Timestamp (optional)
├── record_is_valid: Boolean (required)
├── is_transformed: Boolean (required)
├── published_metadata_hash: String (optional)
└── rule_facts_list: List (optional, nested)
    └── fact: Struct (repeated)
        ├── rule_id: Int (required)
        ├── is_valid: Boolean (required)
        ├── valid_occurrences: List<String> (optional)
        └── invalid_occurrences: List<String> (optional)
```

**Ejemplo de record**:
```json
{
  "record_id": "abc123",
  "identifier": "oai:example.org/123",
  "record_is_valid": true,
  "is_transformed": false,
  "rule_facts_list": [
    {
      "rule_id": 1,
      "is_valid": true,
      "valid_occurrences": ["value1", "value2"]
    },
    {
      "rule_id": 2,
      "is_valid": false,
      "invalid_occurrences": ["bad_value"]
    }
  ]
}
```

**Archivos batch**:
```
records_batch_1.parquet  (10,000 records con facts anidados, ~5 MB)
records_batch_2.parquet  (10,000 records con facts anidados, ~5 MB)
records_batch_3.parquet  (5,234 records con facts anidados, ~2.5 MB)

Total: 25,234 records en 3 archivos (~12.5 MB)
```

**Ventajas de la estructura anidada**:
- ✅ Reducción ~88% de espacio vs fact table separada
- ✅ Paginación correcta: 20 filas = 20 records completos
- ✅ Consultas eficientes con proyección de columnas Parquet
- ✅ Lectura lazy: Solo lee rule_facts cuando se necesita
- ✅ Compresión SNAPPY + dictionary encoding

**Índice ligero adicional**:
**Archivo**: `validation_index.parquet`

Contiene solo campos esenciales (sin rule_facts) para queries rápidas:
- `record_id`, `identifier`, `datestamp`
- `record_is_valid`, `is_transformed`
- `published_metadata_hash`

**Uso**: Filtrado rápido sin leer rule facts completos (~35 bytes/record)

### 📋 Logs (Texto Plano)

**Ubicación**: `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/snapshot.log`

**Formato**:
```
[2025-11-12 10:30:15.123] HARVEST STARTED - network=IBICT
[2025-11-12 10:30:20.456] Record harvested: oai:example.org/123
[2025-11-12 10:35:45.789] HARVEST COMPLETED - 25,234 records
[2025-11-12 10:36:00.012] VALIDATION STARTED
[2025-11-12 10:40:30.567] VALIDATION COMPLETED - 15,234 valid
```

**Características**:
- Append-only (nunca se sobrescribe)
- Timestamp con milisegundos
- Paginado en lectura (API REST)

### 🌲 Árbol Completo - Ejemplo con 2 Snapshots

```
/data/lareferencia/
├── IBICT/                                         ← Network
│   ├── metadata/                                  ← Metadata XML
│   │   ├── A/
│   │   │   └── B/
│   │   │       └── C/
│   │   │           ├── ABCDEF123456789ABC.xml.gz  (500 bytes)
│   │   │           └── ABCABC987654321XYZ.xml.gz  (480 bytes)
│   │   ├── F/
│   │   │   └── 0/
│   │   │       └── 0/
│   │   │           └── F00ABC123456789DEF.xml.gz  (510 bytes)
│   │   └── ... (más particiones con ~25,000 archivos)
│   │
│   └── snapshots/                                 ← Snapshots
│       ├── snapshot_101/                          ← Snapshot 1
│       │   ├── metadata.json                      (Metadata de snapshot, ~2 KB)
│       │   ├── catalog/                           ← OAI Records
│       │   │   ├── oai_records_batch_1.parquet    (10,000 records, 8 MB)
│       │   │   ├── oai_records_batch_2.parquet    (10,000 records, 8 MB)
│       │   │   └── oai_records_batch_3.parquet    (5,234 records, 4 MB)
│       │   ├── validation/                        ← Validación (2 layers: JSON + Parquet anidado)
│       │   │   ├── validation-stats.json          (Estadísticas agregadas, ~5 KB)
│       │   │   ├── validation_index.parquet       (Índice ligero sin facts, ~900 KB)
│       │   │   ├── records_batch_1.parquet        (10,000 records con facts anidados, ~5 MB)
│       │   │   ├── records_batch_2.parquet        (10,000 records con facts anidados, ~5 MB)
│       │   │   └── records_batch_3.parquet        (5,234 records con facts anidados, ~2.5 MB)
│       │   └── snapshot.log                       (25,234 entries, 250 KB)
│       │
│       └── snapshot_102/                          ← Snapshot 2
│           ├── metadata.json                      (~2 KB)
│           ├── catalog/
│           │   ├── oai_records_batch_1.parquet    (10,000 records, 8 MB)
│           │   └── oai_records_batch_2.parquet    (8,500 records, 7 MB)
│           ├── validation/
│           │   ├── validation-stats.json          (~5 KB)
│           │   ├── validation_index.parquet       (~750 KB)
│           │   ├── records_batch_1.parquet        (10,000 con facts, ~5 MB)
│           │   └── records_batch_2.parquet        (8,500 con facts, ~4 MB)
│           └── snapshot.log                       (18,500 entries, 190 KB)
│
└── LA_REFERENCIA/                                 ← Otra Network
    ├── metadata/
    │   └── ... (similar estructura)
    └── snapshots/
        └── ... (similar estructura)
```
└── LA_REFERENCIA/                                 ← Otra Network
    ├── metadata/
    │   └── ... (similar estructura)
    └── snapshots/
        └── ... (similar estructura)
```

### 🔗 Relación entre Componentes

```
PostgreSQL (network_snapshot)
    ↓ id=101, network_id=5, size=25234
    │
    ├──→ Filesystem: /data/lareferencia/IBICT/snapshots/snapshot_101/
    │                ├── catalog/*.parquet (Catálogo OAI inmutable)
    │                ├── validation/*.parquet (Validación)
    │                └── snapshot.log
    │
Parquet Catálogo OAI (snapshot_101/catalog/oai_records_batch_*.parquet)
    ↓ record: identifier="oai:ex.org/123", original_metadata_hash="ABCDEF123..."
    │
    └──→ Filesystem: /data/lareferencia/IBICT/metadata/A/B/C/ABCDEF123456789ABC.xml.gz
         (XML comprimido - compartido entre snapshots con mismo contenido)
```

### 📏 Tamaños Estimados (25,000 records)

| Componente | Ubicación | Tamaño | Notas |
|------------|-----------|--------|-------|
| **Metadata XML** | `{basePath}/{NETWORK}/metadata/` | ~10-12 MB | Comprimido GZIP, deduplicado |
| **Snapshot Metadata** | `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/metadata.json` | ~2 KB | JSON estructural |
| **OAI Records** | `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/catalog/` | ~20 MB | Parquet SNAPPY, 3 batches |
| **Validation Stats** | `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/validation/validation-stats.json` | ~5 KB | JSON agregado |
| **Validation Index** | `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/validation/validation_index.parquet` | ~900 KB | Índice ligero sin facts |
| **Validation Records** | `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/validation/records_*.parquet` | ~12.5 MB | Con RuleFacts anidados |
| **Logs** | `{basePath}/{NETWORK}/snapshots/snapshot_{ID}/snapshot.log` | ~250 KB | Texto plano |
| **PostgreSQL** | BD | ~1-2 MB | Metadata estructural |
| **TOTAL** | | **~45-48 MB** | Por snapshot completo |

**Proyección**:
- 100 snapshots = ~4.7 GB
- 1,000 snapshots = ~47 GB
- Deduplicación de metadata ahorra ~30-50% del espacio total

**Desglose por capas**:
- 26% Metadata XML (deduplicado entre snapshots)
- 42% OAI Records (Parquet catalog)
- 28% Validación (JSON stats + índice + records con facts anidados)
- 3% Logs
- 1% Metadata estructural (JSON + PostgreSQL)
- 1% Metadata estructural (JSON + PostgreSQL)

### 🔧 Sanitización de Network Acronym

El nombre del directorio de red se sanitiza automáticamente:

| Original | Sanitizado | Ejemplo Ruta |
|----------|------------|--------------|
| `br` | `BR` | `/data/lareferencia/BR/` |
| `LA Referencia` | `LA_REFERENCIA` | `/data/lareferencia/LA_REFERENCIA/` |
| `mx-unam` | `MX-UNAM` | `/data/lareferencia/MX-UNAM/` |
| `test@123` | `TEST_123` | `/data/lareferencia/TEST_123/` |

**Reglas**:
- Mayúsculas
- Solo permitidos: `A-Z`, `0-9`, `-`, `_`
- Todo lo demás → `_`

---

## 🔄 Ciclo de Vida

### 1️⃣ Harvesting
```
1. snapshotStore.createSnapshot(network)
   → BD: INSERT snapshot (status=HARVESTING_IN_PROGRESS)
   
2. oaiRecordRepository.initializeSnapshot(snapshotMetadata)
   → FS: mkdir catalog/
   
3. saveRecord() × N
   → FS: Append to buffer
   → Auto-flush: batch_1.parquet, batch_2.parquet, ...
   → BD: incrementSnapshotSize()
   
4. oaiRecordRepository.finalizeSnapshot(snapshotId)
   → FS: Flush final, close last batch
   
5. snapshotStore.updateSnapshotStatus(..., HARVESTING_FINISHED_VALID)
   → BD: UPDATE snapshot SET status=...
```

### 2️⃣ Validación
```
1. validationStatRepository.initializeSnapshot(snapshotMetadata)
   → FS: mkdir validation/
   → FS: Crear metadata inicial (SnapshotValidationStats vacío)
   
2. validationService.addObservation() × N
   → FS: saveRecordAndFacts() incremental
   → Auto-flush cada 10k records
   → Actualiza stats acumulativos en memoria
   
3. validationStatRepository.finalizeSnapshot(snapshotId)
   → FS: Flush final de buffers pendientes
   → FS: Escribir validation-stats.json (estadísticas finales)
   → Cierre de writers
   
4. snapshotStore.updateSnapshotStatus(..., VALIDATION_FINISHED_VALID)
   → BD: UPDATE snapshot SET status=...
```

**Archivos generados**:
- `validation-stats.json` (Layer 1: estadísticas agregadas)
- `validation_index.parquet` (Índice ligero sin rule_facts)
- `records_batch_*.parquet` (Layer 2: records con RuleFacts anidados)

---

## 📊 Campos en PostgreSQL

### `network_snapshot`
```sql
id (BIGINT PRIMARY KEY)
network_id (BIGINT FK)
size (INT) -- Total records harvested
valid_size (INT) -- Records valid after validation
transformed_size (INT) -- Records transformed
status (ENUM) -- HARVESTING_IN_PROGRESS, HARVESTING_FINISHED_VALID, ...
index_status (ENUM) -- UNKNOWN, PENDING, INDEXED, ...
start_time (TIMESTAMP) -- Harvest start
end_time (TIMESTAMP) -- Harvest end
last_incremental_time (TIMESTAMP) -- Last OAI-PMH incremental
previous_snapshot_id (BIGINT FK) -- Link to previous snapshot
deleted (BOOLEAN) -- Logical delete flag
created_at (TIMESTAMP)
updated_at (TIMESTAMP)
```

**NOTA**: PostgreSQL solo almacena metadata estructural:
- **network_snapshot**: Información de snapshots (denormalizada de Parquet/FS)
- **network, source, harvesting_config**: Datos relacionales
- **NO contiene**: Catálogo OAI (está en Parquet), Metadata XML (está en FS), Validación stats (está en JSON)

Ver sección de Validación arriba para detalles de almacenamiento en Filesystem.

---

## 🔒 Thread Safety

### ✅ SEGURO
```java
// Cada thread obtiene NUEVA instancia
Iterator<OAIRecord> it1 = repository.getIterator(metadata);  // Thread 1
Iterator<OAIRecord> it2 = repository.getIterator(metadata);  // Thread 2
// ✅ Sin interferencia
```

### ❌ INSEGURO
```java
// Compartir iterator entre threads
Iterator<OAIRecord> shared = repository.getIterator(metadata);
Thread1: shared.hasNext(); // ⚠️ Race condition
Thread2: shared.hasNext(); // ⚠️ Race condition
```

### Métodos Sincronizados
```java
// PostgreSQL - Contadores de snapshot (synchronized)
snapshotStore.incrementSnapshotSize(snapshotId);        // synchronized
snapshotStore.incrementValidSize(snapshotId);           // synchronized

// Logs (synchronized)
snapshotLogService.addEntry(snapshotId, message);       // synchronized

// Validación - Actualización de stats en memoria (synchronized)
validationStatRepository.updateStoredStats(...);        // synchronized

// OAIRecord/Validation Writers - Auto sincronizados internamente
oaiRecordManager.writeRecord(record);                   // synchronized interno
validationRecordManager.writeRecord(record);            // synchronized interno
```

---

## 📝 API Quick Reference

### ISnapshotStore
```java
// Lifecycle
Long createSnapshot(Network network)
void saveSnapshot(Long snapshotId)
void deleteSnapshot(Long snapshotId)
void cleanSnapshotData(Long snapshotId)

// Metadata
SnapshotMetadata getSnapshotMetadata(Long snapshotId)

// Status
SnapshotStatus getSnapshotStatus(Long snapshotId)
void updateSnapshotStatus(Long snapshotId, SnapshotStatus status)

// Counters (synchronized)
void incrementSnapshotSize(Long snapshotId)
void incrementValidSize(Long snapshotId)
void incrementTransformedSize(Long snapshotId)
void updateSnapshotCounts(Long snapshotId, Integer size, Integer validSize, Integer transformedSize)
```

### OAIRecordParquetRepository
```java
// Write
void initializeSnapshot(SnapshotMetadata snapshotMetadata)
void saveRecord(Long snapshotId, OAIRecord record)
void flush(Long snapshotId)
void finalizeSnapshot(Long snapshotId)

// Read (Thread-safe - NEW instance each call)
Iterator<OAIRecord> getIterator(SnapshotMetadata snapshotMetadata)

// Management
void deleteSnapshot(Long snapshotId)
boolean hasActiveManager(Long snapshotId)
Map<String, Object> getManagerInfo(Long snapshotId)
```

### SnapshotLogService
```java
// Write
void addEntry(Long snapshotId, String message)
void deleteSnapshotLog(Long snapshotId)

// Read
LogQueryResult getLogEntries(Long snapshotId, int page, int size)
```

---

## 🚀 Patrones de Uso Comunes

### Pattern 1: Simple Harvesting
```java
Long snapshotId = snapshotStore.createSnapshot(network);
SnapshotMetadata metadata = snapshotStore.getSnapshotMetadata(snapshotId);
oaiRecordRepository.initializeSnapshot(metadata);

for (OAIRecord record : harvestedRecords) {
    oaiRecordRepository.saveRecord(snapshotId, record);
    snapshotStore.incrementSnapshotSize(snapshotId);
}

oaiRecordRepository.finalizeSnapshot(snapshotId);
snapshotStore.updateSnapshotStatus(snapshotId, SnapshotStatus.HARVESTING_FINISHED_VALID);
```

### Pattern 2: Lectura Segura Multi-Thread
```java
SnapshotMetadata metadata = snapshotStore.getSnapshotMetadata(snapshotId);

// Múltiples threads
executor.submit(() -> {
    Iterator<OAIRecord> iterator = repository.getIterator(metadata);
    while (iterator.hasNext()) {
        OAIRecord record = iterator.next();
        process(record);
    }
});
```

### Pattern 3: Lectura de Logs Paginada
```java
LogQueryResult result = snapshotLogService.getLogEntries(snapshotId, 0, 10);
for (LogEntry entry : result.getEntries()) {
    System.out.println(entry.getTimestamp() + " " + entry.getMessage());
}
System.out.println("Page 1 of " + result.getTotalPages());
```

---

## ⚙️ Configuración (application.properties)

```properties
# Base path para almacenamiento (Metadata XML + Snapshots Parquet)
store.basepath=/data/lareferencia

# Records OAI - Batching
parquet.catalog.records-per-file=10000

# Validación - Batching (records con RuleFacts anidados)
parquet.validation.records-per-file=10000

# Validación - Detalle de occurrences dentro de facts (costoso en espacio)
validation.detailed.diagnose=false

# Parquet - Compresión
parquet.compression=SNAPPY

# Parquet - Page size (1 MB = 1048576)
parquet.page.size=1048576

# Parquet - Dictionary encoding
parquet.enable.dictionary=true

# Database - PostgreSQL (solo para metadata estructural)
spring.datasource.url=jdbc:postgresql://localhost:5432/lareferencia
spring.datasource.username=postgres
spring.datasource.password=password
```

---

## 📈 Estimaciones de Almacenamiento

**Por 25,000 records** (ver tabla detallada en sección "Tamaños Estimados" arriba):
- **Metadata XML**: ~10-12 MB (deduplicación entre snapshots)
- **Snapshot Metadata JSON**: ~2 KB
- **Parquet OAI Records**: ~20 MB (catalog/)
- **Validation Stats JSON**: ~5 KB
- **Validation Index**: ~900 KB (índice ligero)
- **Parquet Validation Records**: ~12.5 MB (con RuleFacts anidados)
- **Logs**: ~250 KB
- **PostgreSQL**: ~1-2 MB (metadata estructural)
- **TOTAL**: ~45-48 MB por snapshot completo

**Proyecciones**:
- 100 snapshots = ~4.7 GB
- 1,000 snapshots = ~47 GB
- 10,000 snapshots = ~470 GB

**Ventajas de la Nueva Arquitectura**:
- ✅ Reducción ~88% vs fact table tradicional
- ✅ Deduplicación de metadata XML ahorra 30-50%
- ✅ Sin bases de datos complejas para validación
- ✅ RuleFacts anidados en mismo archivo = mejor compresión
- ✅ Escalable a millones de records

---

## 🔍 Monitoreo y Debug

### Ver logs de un snapshot
```bash
curl "http://localhost:8080/rest/log/search/findBySnapshotId?snapshot_id=123&page=0&size=20"
```

### Ver información de manager activo
```java
if (repository.hasActiveManager(snapshotId)) {
    Map<String, Object> info = repository.getManagerInfo(snapshotId);
    System.out.println("Records: " + info.get("recordsWritten"));
    System.out.println("Batches: " + info.get("batchCount"));
}
```

### Ver metadata de snapshot
```java
SnapshotMetadata metadata = snapshotStore.getSnapshotMetadata(snapshotId);
System.out.println("Size: " + metadata.getSize());
System.out.println("Valid: " + metadata.getValidSize());
System.out.println("Status: " + snapshotStore.getSnapshotStatus(snapshotId));
```

### Ver estadísticas de validación
```java
// Leer desde JSON (ultra-rápido <1ms)
SnapshotValidationStats stats = validationStatRepository.getSnapshotValidationStats(metadata);

System.out.println("Total Records: " + stats.getTotalRecords());
System.out.println("Valid Records: " + stats.getValidRecords());
System.out.println("Invalid Records: " + stats.getInvalidRecords());
System.out.println("Transformed: " + stats.getTransformedRecords());

// Ver stats por regla
RuleStats rule5 = stats.getRuleStats(5L);
System.out.println("Rule 5 - Valid: " + rule5.getValidCount());
System.out.println("Rule 5 - Invalid: " + rule5.getInvalidCount());

// Ver facets
Map<String, Long> validFacet = stats.getFacet("record_is_valid");
System.out.println("Valid: " + validFacet.get("true"));
System.out.println("Invalid: " + validFacet.get("false"));
```

### Consultar occurrences de una regla
```java
// Obtener occurrences detalladas de regla #5
Map<String, Map<String, Integer>> occurrences = 
    validationStatRepository.calculateRuleOccurrences(snapshotId, 5, null);

Map<String, Integer> validOccurrences = occurrences.get("valid");
Map<String, Integer> invalidOccurrences = occurrences.get("invalid");

System.out.println("Valid occurrences:");
validOccurrences.forEach((value, count) -> 
    System.out.println("  " + value + ": " + count)
);
```

---

## ⚠️ Posibles Problemas

### Problema: Metadata No Encontrada
**Síntoma**: `MetadataRecordStoreException: Metadata not found for hash`
**Causa**: 
- Archivo XML comprimido fue eliminado del FS
- Hash incorrecto en BD
- Partición equivocada

**Solución**:
```bash
# Verificar si existe el archivo
ls -la /data/metadata/NETWORK/metadata/A/B/C/ABCDEF123456789.xml.gz

# Recalcular hash
String newHash = metadataStore.storeAndReturnHash(snapshot, xmlContent);

# Actualizar referencia en BD
UPDATE oai_record SET metadata_hash = 'newHash' WHERE id = ?
```

### Problema: Disco Lleno (Metadata)
**Síntoma**: IOException durante storeAndReturnHash
**Causa**: Partición del FS sin espacio
**Solución**:
```bash
# Ver uso
df -h /data/metadata

# Comprimir archivos antiguos (si aplica)
find /data/metadata -mtime +30 -name "*.xml.gz" -exec gzip -9 {} \;

# O borrar snapshots antiguos
snapshotStore.deleteSnapshot(oldSnapshotId);
```

### Problema: Hash Duplicado Incorrecto
**Síntoma**: Dos records diferentes con mismo hash
**Causa**: 
- Datos corruptos
- Colisión (muy raro con SHA-256)

**Solución**:
```java
// Recalcular y verificar
String xml1 = metadataStore.getMetadata(snap, hash);
String xml2 = metadataStore.getMetadata(snap, hash);

if (!xml1.equals(xml2)) {
    logger.error("Hash collision detected!");
    // Regenerar uno de los hashes
}
```

### Problema: Memory Leak en Lectura
**Síntoma**: Memoria RAM crece leyendo metadata
**Causa**: Buffer no liberado, String muy grande
**Solución**:
```java
// ✅ BUENO - Stream pequeños chunks
try (InputStream is = new FileInputStream(file);
     GZIPInputStream gzis = new GZIPInputStream(is)) {
    byte[] buffer = new byte[8192];
    int bytesRead;
    while ((bytesRead = gzis.read(buffer)) > 0) {
        process(buffer, bytesRead);
    }
}

// ❌ MALO - Carga todo a memoria
String xml = readCompressed(file); // Si es muy grande
```

---

## 📚 Documentos Relacionados

- `docs/ALMACENAMIENTO_DATOS.md` - Documentación completa
- `docs/ALMACENAMIENTO_EJEMPLOS.md` - Ejemplos de código
- `docs/PACKAGE_MIGRATION_GUIDE.md` - Guía de paquetes

---

**Última actualización**: 12 de noviembre de 2025
