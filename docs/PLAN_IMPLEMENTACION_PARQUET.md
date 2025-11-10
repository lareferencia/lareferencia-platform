# PLAN DE IMPLEMENTACIÓN: Migración OAIRecord a Parquet

**Versión**: 1.0  
**Fecha**: 10 de noviembre de 2025  
**Objetivo**: Migrar almacenamiento de OAIRecord de SQL (PostgreSQL) a Parquet con separación de catálogo y estado de validación

---

## ÍNDICE

1. [Contexto y Arquitectura](#contexto-y-arquitectura)
2. [Componentes a Implementar](#componentes-a-implementar)
3. [Fase 1: Entidades y Schemas Parquet](#fase-1-entidades-y-schemas-parquet)
4. [Fase 2: Managers Parquet](#fase-2-managers-parquet)
5. [Fase 3: Service Layer](#fase-3-service-layer)
6. [Fase 4: Actualización de Workers](#fase-4-actualización-de-workers)
7. [Fase 5: Migración de Datos](#fase-5-migración-de-datos)
8. [Fase 6: Testing y Validación](#fase-6-testing-y-validación)
9. [Checklist de Verificación](#checklist-de-verificación)

---

## CONTEXTO Y ARQUITECTURA

### Problema Actual

El sistema LRHarvester almacena registros OAI en PostgreSQL con dos problemas:
1. **Performance**: 10M+ registros por snapshot generan queries lentas
2. **Redundancia**: Estado de validación duplicado entre `OAIRecord` (SQL) y `RecordValidation` (Parquet)

### Solución Propuesta

**Separar datos inmutables de datos mutables:**

```
┌─────────────────────────────────────────────────────────────┐
│                    ARQUITECTURA FINAL                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  ┌──────────────────┐      ┌──────────────────┐            │
│  │  NetworkSnapshot │      │  IMetadataStore  │            │
│  │      (SQL)       │      │  (Filesystem)    │            │
│  │  - id, stats     │      │  - XML files     │            │
│  └──────────────────┘      └──────────────────┘            │
│           ▲                         ▲                       │
│           │                         │                       │
│           │                         │                       │
│  ┌────────┴──────────────┬──────────┴──────────┐           │
│  │                       │                      │           │
│  │  OAIRecordCatalog     │  RecordValidation   │           │
│  │    (PARQUET)          │    (PARQUET)        │           │
│  │  ┌─────────────────┐  │  ┌───────────────┐ │           │
│  │  │ INMUTABLE       │  │  │ REESCRIBIBLE  │ │           │
│  │  │ - id            │  │  │ - recordId    │ │           │
│  │  │ - identifier    │  │  │ - identifier  │ │           │
│  │  │ - datestamp     │  │  │ - isValid     │ │           │
│  │  │ - originalHash  │  │  │ - transformed │ │           │
│  │  │ - deleted       │  │  │ - publishedH. │ │           │
│  │  └─────────────────┘  │  │ - validatedAt │ │           │
│  │                       │  │ - ruleFacts   │ │           │
│  └───────────────────────┘  └───────────────┘ │           │
│                                      │                      │
│                          ┌───────────┴─────────┐           │
│                          │  ValidationIndex    │           │
│                          │    (PARQUET)        │           │
│                          │  ┌───────────────┐  │           │
│                          │  │ IN-MEMORY     │  │           │
│                          │  │ - recordId    │  │           │
│                          │  │ - identifier  │  │           │
│                          │  │ - isValid     │  │           │
│                          │  │ - transformed │  │           │
│                          │  │ - publishedH. │  │           │
│                          │  └───────────────┘  │           │
│                          └─────────────────────┘           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Principios Clave

1. **Inmutabilidad del Catálogo**: `OAIRecordCatalog` se escribe una vez durante harvesting, nunca se actualiza
2. **Validación Separada**: `RecordValidation` se reescribe completamente en cada validación
3. **Índice Ligero**: `ValidationIndex` cargado en memoria (~350 MB para 10M records) para queries rápidas
4. **Hash Separation**: 
   - `originalMetadataHash` → solo en `OAIRecordCatalog`
   - `publishedMetadataHash` → solo en `RecordValidation` y `ValidationIndex`

---

## COMPONENTES A IMPLEMENTAR

### Nuevos Componentes

| Componente | Tipo | Ubicación | Propósito |
|------------|------|-----------|-----------|
| `OAIRecordCatalog` | Domain Entity | `org.lareferencia.backend.domain.parquet` | Catálogo inmutable de registros |
| `ValidationIndex` | Domain Entity | `org.lareferencia.backend.domain.parquet` | Índice ligero para queries |
| `OAIRecordCatalogManager` | Repository | `org.lareferencia.backend.repositories.parquet` | CRUD Parquet para catálogo |
| `ValidationIndexManager` | Repository | `org.lareferencia.backend.repositories.parquet` | CRUD Parquet para índice |
| `ParquetMetadataRecordStoreService` | Service | `org.lareferencia.core.metadata` | Implementación Parquet de `IMetadataRecordStoreService` |

### Componentes a Modificar

| Componente | Tipo | Cambio |
|------------|------|--------|
| `RecordValidation` | Domain Entity | Agregar `recordId`, `publishedMetadataHash`, `validatedAt` |
| `ValidationRecordManager` | Repository | Soporte para referencias a `recordId` |
| `HarvestingWorker` | Worker | Escribir a `OAIRecordCatalog` en lugar de SQL |
| `ValidationWorker` | Worker | Escribir validación con `publishedMetadataHash` |
| `IndexerWorker` | Worker | Leer desde `ValidationIndex` en memoria |

---

## CONVENCIONES DE CÓDIGO

### Rutas Parquet

```java
// Base path configurado en application.properties
private static final String BASE_PATH_PROPERTY = "backend.parquet.basePath";

// Estructura de directorios
// /data/parquet/
//   └── snapshot_{snapshotId}/
//       ├── catalog/
//       │   ├── records_batch_0001.parquet
//       │   ├── records_batch_0002.parquet
//       │   └── ...
//       ├── validation/
//       │   ├── validation_batch_0001.parquet
//       │   ├── validation_batch_0002.parquet
//       │   └── ...
//       └── index/
//           └── validation_index.parquet  (archivo único)
```

### Configuración Hadoop

```java
Configuration hadoopConf = new Configuration();
hadoopConf.set("parquet.compression", "SNAPPY");
hadoopConf.set("parquet.block.size", "134217728"); // 128 MB
hadoopConf.set("parquet.page.size", "1048576");    // 1 MB
hadoopConf.set("parquet.enable.dictionary", "true");
```

### Naming Conventions

- **Clases de dominio Parquet**: sufijo sin `Entity` (ej: `OAIRecordCatalog`)
- **Managers Parquet**: sufijo `Manager` (ej: `OAIRecordCatalogManager`)
- **Factory methods**: `forReading(...)`, `forWriting(...)`
- **AutoCloseable**: Todos los managers implementan `AutoCloseable`

---

## FASE 1: ENTIDADES Y SCHEMAS PARQUET

**Duración**: 1-2 semanas  
**Dependencias**: Ninguna  
**Objetivo**: Crear las clases de dominio Parquet y sus schemas

### 1.1 OAIRecordCatalog Entity

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/domain/parquet/OAIRecordCatalog.java`

**Instrucciones para el agente IA:**

1. Crear nueva clase en el paquete `org.lareferencia.backend.domain.parquet`
2. La clase debe ser un POJO simple con Lombok
3. NO debe tener anotaciones JPA (no es entidad SQL)
4. Debe ser inmutable después de creación (usar `@Builder` con `toBuilder = false`)

**Código completo:**

```java
package org.lareferencia.backend.domain.parquet;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;
import java.time.LocalDateTime;

/**
 * Catálogo INMUTABLE de registros OAI cosechados.
 * 
 * Almacenado en Parquet, organizado por snapshot.
 * Se escribe UNA SOLA VEZ durante harvesting, nunca se actualiza.
 * 
 * NO contiene estado de validación (eso está en RecordValidation).
 * Solo contiene hash de metadata ORIGINAL (publishedMetadataHash está en RecordValidation).
 * 
 * Estructura de archivos:
 * /data/parquet/snapshot_{id}/catalog/records_batch_*.parquet
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class OAIRecordCatalog implements Serializable {
    
    private static final long serialVersionUID = 1L;
    
    /**
     * ID secuencial único dentro del snapshot.
     * Se genera durante harvesting (auto-increment).
     */
    private Long id;
    
    /**
     * Identificador OAI único del registro.
     * Formato típico: oai:repositorio:handle
     */
    private String identifier;
    
    /**
     * Fecha de última modificación del registro según OAI-PMH.
     */
    private LocalDateTime datestamp;
    
    /**
     * Hash MD5 del XML original cosechado.
     * Permite recuperar el XML desde IMetadataStore.
     * 
     * Este es el ÚNICO hash almacenado en el catálogo.
     * El hash de metadata transformada está en RecordValidation.
     */
    private String originalMetadataHash;
    
    /**
     * Flag que indica si el registro fue eliminado en el repositorio origen.
     * Se setea durante harvesting incremental si viene con <status>deleted</status>.
     */
    private Boolean deleted;
    
    /**
     * Snapshot al que pertenece este registro.
     * Se usa para organizar directorios en Parquet.
     * NO se almacena en Parquet (implícito por la ruta del archivo).
     */
    @Builder.Default
    private transient Long snapshotId = null;
}
```

**Validaciones que debe hacer el agente:**
- ✅ Clase en paquete correcto
- ✅ Sin anotaciones JPA (`@Entity`, `@Table`, etc.)
- ✅ Con Lombok (`@Data`, `@Builder`, `@NoArgsConstructor`, `@AllArgsConstructor`)
- ✅ Implementa `Serializable`
- ✅ Campo `snapshotId` marcado como `transient`
- ✅ Javadoc completo en clase y campos críticos

---

### 1.2 ValidationIndex Entity

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/domain/parquet/ValidationIndex.java`

**Instrucciones para el agente IA:**

1. Crear nueva clase en el paquete `org.lareferencia.backend.domain.parquet`
2. Esta clase es un **índice ligero** que se carga completo en memoria
3. Debe contener SOLO los campos necesarios para filtrado rápido
4. Tamaño objetivo: ~35 bytes/record comprimido

**Código completo:**

```java
package org.lareferencia.backend.domain.parquet;

import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

import java.io.Serializable;

/**
 * Índice LIGERO de validación para queries rápidas.
 * 
 * Se carga COMPLETO en memoria al inicio de IndexerWorker.
 * Permite filtrar registros sin leer RecordValidation completo.
 * 
 * Tamaño estimado:
 * - record_id: 8 bytes
 * - identifier: ~30 bytes (avg)
 * - is_valid: 1 byte
 * - is_transformed: 1 byte
 * - published_metadata_hash: 32 bytes (nullable)
 * Total: ~72 bytes sin comprimir, ~35 bytes con SNAPPY
 * 
 * 10M records = ~350 MB en memoria (aceptable)
 * 
 * Estructura de archivos:
 * /data/parquet/snapshot_{id}/index/validation_index.parquet (archivo ÚNICO)
 */
@Data
@Builder
@NoArgsConstructor
@AllArgsConstructor
public class ValidationIndex implements Serializable {
    
    private static final long serialVersionUID = 1L;
    
    /**
     * Referencia al ID en OAIRecordCatalog.
     */
    private Long recordId;
    
    /**
     * Identificador OAI (denormalizado para búsquedas).
     */
    private String identifier;
    
    /**
     * Flag de validación exitosa.
     * true = registro válido según reglas de validación
     * false = registro inválido
     */
    private Boolean isValid;
    
    /**
     * Flag de transformación aplicada.
     * true = metadata fue transformada (publishedMetadataHash ≠ originalMetadataHash)
     * false = metadata NO transformada (publishedMetadataHash = originalMetadataHash)
     */
    private Boolean isTransformed;
    
    /**
     * Hash MD5 del XML a indexar.
     * 
     * - Si isTransformed = true: hash del XML transformado
     * - Si isTransformed = false && isValid = true: hash del XML original
     * - Si isValid = false: null
     * 
     * Este campo permite a IndexerWorker obtener el hash correcto
     * sin tener que leer RecordValidation completo ni OAIRecordCatalog.
     */
    private String publishedMetadataHash;
}
```

**Validaciones que debe hacer el agente:**
- ✅ Clase en paquete correcto
- ✅ Sin anotaciones JPA
- ✅ Con Lombok
- ✅ Implementa `Serializable`
- ✅ Solo 5 campos (mantener ligero)
- ✅ Javadoc explicando propósito de in-memory loading

---

### 1.3 Modificar RecordValidation

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/domain/parquet/RecordValidation.java`

**Instrucciones para el agente IA:**

1. **NO crear archivo nuevo** - el archivo ya existe
2. Agregar 3 campos nuevos: `recordId`, `publishedMetadataHash`, `validatedAt`
3. Mantener todos los campos existentes
4. Actualizar Javadoc de la clase

**Cambios a aplicar:**

```java
// AGREGAR estos campos a la clase RecordValidation existente:

/**
 * Referencia al ID en OAIRecordCatalog.
 * Permite vincular validación con catálogo sin duplicar todos los datos.
 * 
 * NUEVO campo para soportar arquitectura separada.
 */
private Long recordId;

/**
 * Hash MD5 del XML a indexar (resultado de validación/transformación).
 * 
 * - Si isTransformed = true: hash del XML transformado
 * - Si isTransformed = false && recordIsValid = true: copia del originalMetadataHash
 * - Si recordIsValid = false: null
 * 
 * NUEVO campo que antes estaba en OAIRecord.publishedMetadataHash.
 * Ahora está aquí porque es RESULTADO de validación, no dato de catálogo.
 */
private String publishedMetadataHash;

/**
 * Timestamp de cuándo se ejecutó la validación.
 * Permite auditoría y troubleshooting.
 * 
 * NUEVO campo para tracking temporal.
 */
private LocalDateTime validatedAt;
```

**Actualizar Javadoc de clase:**

```java
/**
 * Información COMPLETA de validación y transformación.
 * 
 * Se REESCRIBE completamente en cada ejecución de ValidationWorker.
 * Contiene estado mutable que cambia con cada validación.
 * 
 * CAMBIOS vs versión anterior:
 * - Agregado recordId: referencia a OAIRecordCatalog
 * - Agregado publishedMetadataHash: hash del XML transformado
 * - Agregado validatedAt: timestamp de validación
 * 
 * Estructura de archivos:
 * /data/parquet/snapshot_{id}/validation/validation_batch_*.parquet
 */
```

**Validaciones que debe hacer el agente:**
- ✅ Archivo existe (no crear nuevo)
- ✅ Agregados 3 campos: `recordId`, `publishedMetadataHash`, `validatedAt`
- ✅ Campos existentes sin cambios: `id`, `identifier`, `recordIsValid`, `isTransformed`, `ruleFacts`
- ✅ Javadoc actualizado en clase y nuevos campos
- ✅ Imports correctos: `java.time.LocalDateTime`

---

### 1.4 Parquet Schemas

**Ubicación**: Dentro de cada Manager (se implementará en Fase 2)

**Instrucciones para el agente IA:**

Los schemas Parquet NO se definen en las entidades, sino en los Managers.
Por ahora, solo documentar aquí la especificación para referencia futura.

**Schema OAIRecordCatalog:**

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

**Schema ValidationIndex:**

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
        .named("published_metadata_hash")
    
    .named("ValidationIndex");
```

**Schema RecordValidation (modificado):**

```java
// AGREGAR estos campos al schema existente en ValidationRecordManager:

.required(PrimitiveType.PrimitiveTypeName.INT64)
    .named("record_id")  // NUEVO

.optional(PrimitiveType.PrimitiveTypeName.BINARY)
    .as(LogicalTypeAnnotation.stringType())
    .named("published_metadata_hash")  // NUEVO

.required(PrimitiveType.PrimitiveTypeName.INT64)
    .as(LogicalTypeAnnotation.timestampType(true, TimeUnit.MILLIS))
    .named("validated_at")  // NUEVO
```

---

### 1.5 Checklist Fase 1

**Antes de continuar a Fase 2, verificar:**

- [ ] `OAIRecordCatalog.java` creado en `org.lareferencia.backend.domain.parquet`
- [ ] `ValidationIndex.java` creado en `org.lareferencia.backend.domain.parquet`
- [ ] `RecordValidation.java` modificado con 3 campos nuevos
- [ ] Todos los campos tienen Javadoc
- [ ] Todas las clases compilan sin errores
- [ ] No hay dependencias de JPA en clases Parquet
- [ ] Imports correctos (Lombok, Serializable, LocalDateTime)

**Comandos de verificación:**

```bash
# Compilar módulo
cd lareferencia-core-lib
mvn clean compile

# Verificar que no hay errores de compilación
echo $?  # debe ser 0

# Buscar clases creadas
find src/main/java -name "OAIRecordCatalog.java"
find src/main/java -name "ValidationIndex.java"

# Verificar modificación de RecordValidation
grep -n "recordId" src/main/java/org/lareferencia/backend/domain/parquet/RecordValidation.java
grep -n "publishedMetadataHash" src/main/java/org/lareferencia/backend/domain/parquet/RecordValidation.java
grep -n "validatedAt" src/main/java/org/lareferencia/backend/domain/parquet/RecordValidation.java
```

---

## FASE 2: MANAGERS PARQUET

**Duración**: 2-3 semanas  
**Dependencias**: Fase 1 completada  
**Objetivo**: Implementar managers para lectura/escritura de archivos Parquet

### 2.1 OAIRecordCatalogManager

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/repositories/parquet/OAIRecordCatalogManager.java`

**Patrón de referencia**: `ValidationRecordManager` (ya existe en el proyecto)

**Instrucciones para el agente IA:**

1. Crear clase que sigue el **mismo patrón** que `ValidationRecordManager`
2. Implementar `AutoCloseable` para manejo de recursos
3. Factory methods: `forReading()` y `forWriting()`
4. Escritura con buffering (flush cada 10,000 records)
5. Lectura con lazy iteration (NO cargar todo en memoria)

**Estructura del Manager** (código resumido - el agente debe expandir siguiendo el patrón de ValidationRecordManager):

```java
package org.lareferencia.backend.repositories.parquet;

@Log4j2
public class OAIRecordCatalogManager implements AutoCloseable, Iterable<OAIRecordCatalog> {
    
    private static final int BUFFER_SIZE = 10000;
    private static final String CATALOG_SUBDIR = "catalog";
    private static final String FILE_PREFIX = "records_batch_";
    
    // Schema Parquet
    private static final MessageType CATALOG_SCHEMA = Types.buildMessage()
        .required(PrimitiveType.PrimitiveTypeName.INT64).named("id")
        .required(PrimitiveType.PrimitiveTypeName.BINARY)
            .as(LogicalTypeAnnotation.stringType()).named("identifier")
        .required(PrimitiveType.PrimitiveTypeName.INT64)
            .as(LogicalTypeAnnotation.timestampType(true, TimeUnit.MILLIS)).named("datestamp")
        .required(PrimitiveType.PrimitiveTypeName.BINARY)
            .as(LogicalTypeAnnotation.stringType()).named("original_metadata_hash")
        .required(PrimitiveType.PrimitiveTypeName.BOOLEAN).named("deleted")
        .named("OAIRecordCatalog");
    
    // Factory methods
    public static OAIRecordCatalogManager forWriting(String basePath, Long snapshotId, Configuration hadoopConf) throws IOException;
    public static OAIRecordCatalogManager forReading(String basePath, Long snapshotId, Configuration hadoopConf) throws IOException;
    
    // Operaciones
    public synchronized void writeRecord(OAIRecordCatalog record) throws IOException;
    public synchronized void flush() throws IOException;
    public Iterator<OAIRecordCatalog> iterator();  // Lazy iteration
    
    // AutoCloseable
    public void close() throws IOException;
}
```

**IMPORTANTE**: El agente debe copiar la implementación completa de `ValidationRecordManager` y adaptarla para `OAIRecordCatalog`:
- Cambiar tipos de `RecordValidation` a `OAIRecordCatalog`
- Cambiar schema Parquet
- Cambiar subdirectorio de "validation" a "catalog"
- Mantener TODA la lógica de buffering, lazy iteration, y manejo de múltiples archivos

**Archivos auxiliares requeridos:**
- `CatalogParquetWriter.java` - Writer específico para OAIRecordCatalog
- `CatalogParquetReader.java` - Reader específico para OAIRecordCatalog

(El agente debe crear estos siguiendo el patrón de `ValidationRecordParquetWriter` y `ValidationRecordParquetReader`)

**Validaciones:**
- ✅ Manager completo con factory methods
- ✅ Implementa `AutoCloseable` e `Iterable<OAIRecordCatalog>`
- ✅ Buffer de 10,000 records
- ✅ Lazy iteration sin cargar todo en memoria
- ✅ Writer y Reader auxiliares creados
- ✅ Compila sin errores

---

### 2.2 ValidationIndexManager

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/repositories/parquet/ValidationIndexManager.java`

**Característica especial**: Este manager trabaja con UN SOLO ARCHIVO (no múltiples batches como los otros)

**Instrucciones para el agente IA:**

1. A diferencia de otros managers, el índice se escribe en **un solo archivo**
2. Se regenera COMPLETO después de cada validación
3. Debe tener método `loadIndex()` que carga TODO el archivo en memoria (Map<Long, ValidationIndex>)
4. Tamaño pequeño (~350 MB para 10M records) hace viable carga completa

**Estructura del Manager:**

```java
package org.lareferencia.backend.repositories.parquet;

@Log4j2
public class ValidationIndexManager implements AutoCloseable {
    
    private static final String INDEX_SUBDIR = "index";
    private static final String INDEX_FILENAME = "validation_index.parquet";
    
    // Schema Parquet
    private static final MessageType INDEX_SCHEMA = Types.buildMessage()
        .required(PrimitiveType.PrimitiveTypeName.INT64).named("record_id")
        .required(PrimitiveType.PrimitiveTypeName.BINARY)
            .as(LogicalTypeAnnotation.stringType()).named("identifier")
        .required(PrimitiveType.PrimitiveTypeName.BOOLEAN).named("is_valid")
        .required(PrimitiveType.PrimitiveTypeName.BOOLEAN).named("is_transformed")
        .optional(PrimitiveType.PrimitiveTypeName.BINARY)
            .as(LogicalTypeAnnotation.stringType()).named("published_metadata_hash")
        .named("ValidationIndex");
    
    /**
     * Regenerar índice completo desde RecordValidation.
     * Se llama al final de ValidationWorker.postRun().
     */
    public void rebuildIndex(Long snapshotId) throws IOException {
        List<ValidationIndex> indexEntries = new ArrayList<>();
        
        // Leer todos los RecordValidation
        try (ValidationRecordManager reader = ValidationRecordManager.forReading(basePath, snapshotId, hadoopConf)) {
            for (RecordValidation validation : reader) {
                ValidationIndex entry = ValidationIndex.builder()
                    .recordId(validation.getRecordId())
                    .identifier(validation.getIdentifier())
                    .isValid(validation.getRecordIsValid())
                    .isTransformed(validation.getIsTransformed())
                    .publishedMetadataHash(validation.getPublishedMetadataHash())
                    .build();
                indexEntries.add(entry);
            }
        }
        
        // Escribir índice en un solo archivo
        writeIndex(snapshotId, indexEntries);
        log.info("Rebuilt validation index with {} entries", indexEntries.size());
    }
    
    /**
     * Cargar índice COMPLETO en memoria.
     * Retorna Map para lookup O(1) por recordId.
     * 
     * Usado por IndexerWorker al inicio.
     */
    public Map<Long, ValidationIndex> loadIndex(Long snapshotId) throws IOException {
        Map<Long, ValidationIndex> index = new HashMap<>();
        Path indexPath = getIndexPath(snapshotId);
        
        try (ParquetReader<ValidationIndex> reader = new IndexParquetReader(indexPath, hadoopConf)) {
            ValidationIndex entry;
            while ((entry = reader.read()) != null) {
                index.put(entry.getRecordId(), entry);
            }
        }
        
        log.info("Loaded validation index with {} entries (~{} MB)", 
                 index.size(), 
                 (index.size() * 72) / (1024 * 1024));
        
        return index;
    }
    
    /**
     * Escribir índice a disco.
     */
    private void writeIndex(Long snapshotId, List<ValidationIndex> entries) throws IOException {
        Path indexPath = getIndexPath(snapshotId);
        
        try (ParquetWriter<ValidationIndex> writer = new IndexParquetWriter(indexPath, INDEX_SCHEMA, CompressionCodecName.SNAPPY, hadoopConf)) {
            for (ValidationIndex entry : entries) {
                writer.write(entry);
            }
        }
    }
    
    private Path getIndexPath(Long snapshotId) {
        String path = String.format("%s/snapshot_%d/%s/%s", basePath, snapshotId, INDEX_SUBDIR, INDEX_FILENAME);
        return new Path(path);
    }
}
```

**Archivos auxiliares requeridos:**
- `IndexParquetWriter.java` - Writer específico para ValidationIndex
- `IndexParquetReader.java` - Reader específico para ValidationIndex

**Validaciones:**
- ✅ Manager con métodos `rebuildIndex()` y `loadIndex()`
- ✅ Escribe en UN SOLO archivo (no batches)
- ✅ `loadIndex()` retorna `Map<Long, ValidationIndex>` para lookup O(1)
- ✅ Writer y Reader auxiliares creados
- ✅ Compila sin errores

---

### 2.3 Modificar ValidationRecordManager

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/repositories/parquet/ValidationRecordManager.java`

**Instrucciones para el agente IA:**

1. **NO reescribir** la clase completa
2. Solo modificar el **schema Parquet** para agregar 3 campos nuevos
3. Modificar Writer/Reader para serializar/deserializar los nuevos campos

**Cambios en el Schema:**

```java
// AGREGAR estos campos al schema existente VALIDATION_SCHEMA:

.required(PrimitiveType.PrimitiveTypeName.INT64)
    .named("record_id")  // NUEVO - después de identifier

.optional(PrimitiveType.PrimitiveTypeName.BINARY)
    .as(LogicalTypeAnnotation.stringType())
    .named("published_metadata_hash")  // NUEVO - después de is_transformed

.required(PrimitiveType.PrimitiveTypeName.INT64)
    .as(LogicalTypeAnnotation.timestampType(true, TimeUnit.MILLIS))
    .named("validated_at")  // NUEVO - después de published_metadata_hash
```

**Cambios en ValidationRecordParquetWriter:**

Agregar serialización de los 3 campos nuevos en el método `write()`:

```java
// Después de escribir identifier:
recordConsumer.startField("record_id", 1);
recordConsumer.addLong(record.getRecordId());
recordConsumer.endField("record_id", 1);

// Después de escribir is_transformed:
if (record.getPublishedMetadataHash() != null) {
    recordConsumer.startField("published_metadata_hash", 4);
    recordConsumer.addBinary(Binary.fromString(record.getPublishedMetadataHash()));
    recordConsumer.endField("published_metadata_hash", 4);
}

recordConsumer.startField("validated_at", 5);
recordConsumer.addLong(Timestamp.valueOf(record.getValidatedAt()).getTime());
recordConsumer.endField("validated_at", 5);
```

**Cambios en ValidationRecordParquetReader:**

Agregar deserialización de los 3 campos nuevos en el `RecordMaterializer`:

```java
case 1: // record_id
    return new PrimitiveConverter() {
        @Override
        public void addLong(long value) {
            builder.recordId(value);
        }
    };

case 4: // published_metadata_hash
    return new PrimitiveConverter() {
        @Override
        public void addBinary(Binary value) {
            builder.publishedMetadataHash(value.toStringUsingUTF8());
        }
    };

case 5: // validated_at
    return new PrimitiveConverter() {
        @Override
        public void addLong(long value) {
            builder.validatedAt(new Timestamp(value).toLocalDateTime());
        }
    };
```

**Validaciones:**
- ✅ Schema actualizado con 3 campos
- ✅ Writer serializa los 3 campos nuevos
- ✅ Reader deserializa los 3 campos nuevos
- ✅ Índices de campos correctos (respetar orden)
- ✅ Compila sin errores
- ✅ NO se rompe compatibilidad con archivos existentes (campos opcionales donde corresponda)

---

### 2.4 Checklist Fase 2

**Antes de continuar a Fase 3, verificar:**

- [ ] `OAIRecordCatalogManager.java` creado con factory methods
- [ ] `CatalogParquetWriter.java` y `CatalogParquetReader.java` creados
- [ ] `ValidationIndexManager.java` creado con `rebuildIndex()` y `loadIndex()`
- [ ] `IndexParquetWriter.java` y `IndexParquetReader.java` creados
- [ ] `ValidationRecordManager.java` modificado (schema + writer + reader)
- [ ] Todos los managers implementan `AutoCloseable`
- [ ] Todos compilan sin errores
- [ ] Tests unitarios básicos (opcional pero recomendado)

**Comandos de verificación:**

```bash
# Compilar módulo
cd lareferencia-core-lib
mvn clean compile

# Verificar managers creados
find src/main/java -name "*CatalogManager.java"
find src/main/java -name "ValidationIndexManager.java"

# Verificar writers/readers
find src/main/java -name "CatalogParquet*.java"
find src/main/java -name "IndexParquet*.java"

# Test básico de escritura/lectura (crear archivo temporal)
# (Opcional - el agente puede crear un test simple)
```

---

## FASE 3: SERVICE LAYER

**Duración**: 2 semanas  
**Dependencias**: Fase 2 completada  
**Objetivo**: Implementar la capa de servicio que abstrae el acceso a Parquet

### 3.1 ParquetMetadataRecordStoreService

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/core/metadata/ParquetMetadataRecordStoreService.java`

**Propósito**: Implementación Parquet de `IMetadataRecordStoreService` que reemplaza `MetadataRecordStoreServiceImpl` (SQL)

**Instrucciones para el agente IA:**

1. Crear nueva clase que implementa `IMetadataRecordStoreService`
2. Usar `@Service` y `@Primary` para que Spring la use en lugar de la implementación SQL
3. Inyectar dependencias: `NetworkSnapshotRepository` (SQL - se mantiene), configuración de rutas
4. Implementar TODOS los métodos de la interfaz usando los Managers Parquet

**Código completo:**

```java
package org.lareferencia.core.metadata;

import lombok.extern.log4j.Log4j2;
import org.apache.hadoop.conf.Configuration;
import org.lareferencia.backend.domain.NetworkSnapshot;
import org.lareferencia.backend.domain.RecordStatus;
import org.lareferencia.backend.domain.parquet.OAIRecordCatalog;
import org.lareferencia.backend.domain.parquet.ValidationIndex;
import org.lareferencia.backend.repositories.NetworkSnapshotRepository;
import org.lareferencia.backend.repositories.parquet.OAIRecordCatalogManager;
import org.lareferencia.backend.repositories.parquet.ValidationIndexManager;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Primary;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.io.IOException;
import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;

/**
 * Implementación Parquet de IMetadataRecordStoreService.
 * 
 * REEMPLAZA a MetadataRecordStoreServiceImpl (SQL).
 * 
 * Arquitectura:
 * - NetworkSnapshot: SQL (se mantiene)
 * - OAIRecordCatalog: Parquet (catálogo inmutable)
 * - RecordValidation: Parquet (estado de validación)
 * - ValidationIndex: Parquet en memoria (queries rápidas)
 * 
 * Configuración requerida en application.properties:
 * backend.parquet.basePath=/data/parquet
 */
@Service
@Primary
@Log4j2
public class ParquetMetadataRecordStoreService implements IMetadataRecordStoreService {
    
    private final NetworkSnapshotRepository snapshotRepository;
    private final String parquetBasePath;
    private final Configuration hadoopConf;
    
    public ParquetMetadataRecordStoreService(
            NetworkSnapshotRepository snapshotRepository,
            @Value("${backend.parquet.basePath:/data/parquet}") String parquetBasePath) {
        
        this.snapshotRepository = snapshotRepository;
        this.parquetBasePath = parquetBasePath;
        this.hadoopConf = createHadoopConfiguration();
        
        log.info("Initialized ParquetMetadataRecordStoreService with basePath: {}", parquetBasePath);
    }
    
    /**
     * Configuración Hadoop optimizada para Parquet.
     */
    private Configuration createHadoopConfiguration() {
        Configuration conf = new Configuration();
        conf.set("parquet.compression", "SNAPPY");
        conf.set("parquet.block.size", "134217728"); // 128 MB
        conf.set("parquet.page.size", "1048576");    // 1 MB
        conf.set("parquet.enable.dictionary", "true");
        return conf;
    }
    
    /**
     * Crear un nuevo registro en el catálogo.
     * Se llama desde HarvestingWorker durante cosecha.
     */
    @Override
    @Transactional
    public OAIRecord createRecord(Long snapshotId, String identifier, LocalDateTime datestamp, 
                                   String metadataHash, Boolean deleted) throws Exception {
        
        NetworkSnapshot snapshot = snapshotRepository.findById(snapshotId)
            .orElseThrow(() -> new IllegalArgumentException("Snapshot not found: " + snapshotId));
        
        // Generar ID secuencial
        Long recordId = snapshot.getSize() + 1;
        
        // Crear entrada en catálogo Parquet
        OAIRecordCatalog catalog = OAIRecordCatalog.builder()
            .id(recordId)
            .identifier(identifier)
            .datestamp(datestamp)
            .originalMetadataHash(metadataHash)
            .deleted(deleted)
            .build();
        
        // Escribir a Parquet (usando manager en modo append)
        try (OAIRecordCatalogManager manager = OAIRecordCatalogManager.forWriting(
                parquetBasePath, snapshotId, hadoopConf)) {
            manager.writeRecord(catalog);
        } catch (IOException e) {
            log.error("Error writing catalog record", e);
            throw new Exception("Failed to create catalog record", e);
        }
        
        // Actualizar contador en snapshot (SQL)
        snapshot.incrementSize();
        snapshotRepository.save(snapshot);
        
        // Retornar adaptador OAIRecord (para compatibilidad con interfaz)
        return adaptCatalogToOAIRecord(catalog, snapshot);
    }
    
    /**
     * Actualizar estado de validación de un registro.
     * 
     * IMPORTANTE: Este método NO toca el catálogo (inmutable).
     * Solo actualiza contadores en NetworkSnapshot (SQL).
     * La validación real se escribe desde ValidationWorker directamente a RecordValidation (Parquet).
     */
    @Override
    @Transactional
    public void updateRecordStatus(Long recordId, RecordStatus newStatus, Boolean transformed) throws Exception {
        
        // NOTA: recordId incluye snapshotId en su estructura
        // Extraer snapshotId (implementación depende de cómo se codifica el ID)
        Long snapshotId = extractSnapshotIdFromRecordId(recordId);
        
        NetworkSnapshot snapshot = snapshotRepository.findById(snapshotId)
            .orElseThrow(() -> new IllegalArgumentException("Snapshot not found: " + snapshotId));
        
        // Actualizar contadores en snapshot según el estado
        if (newStatus == RecordStatus.VALID) {
            snapshot.incrementValidSize();
        }
        
        if (transformed != null && transformed) {
            snapshot.incrementTransformedSize();
        }
        
        snapshotRepository.save(snapshot);
        
        log.debug("Updated snapshot counters for record {}: status={}, transformed={}", 
                  recordId, newStatus, transformed);
    }
    
    /**
     * Obtener un paginator de registros válidos para indexación.
     * 
     * Usa ValidationIndex cargado en memoria para filtrado rápido.
     */
    @Override
    public IPaginator<OAIRecord> getValidRecordsPaginator(Long snapshotId, int pageSize) throws Exception {
        
        NetworkSnapshot snapshot = snapshotRepository.findById(snapshotId)
            .orElseThrow(() -> new IllegalArgumentException("Snapshot not found: " + snapshotId));
        
        return new ParquetValidRecordsPaginator(
            parquetBasePath,
            snapshotId,
            snapshot,
            pageSize,
            hadoopConf
        );
    }
    
    /**
     * Copiar registros no eliminados de un snapshot a otro.
     * Usado en harvesting incremental.
     */
    @Override
    @Transactional
    public void copyNotDeletedRecordsFromSnapshot(Long sourceSnapshotId, Long targetSnapshotId) throws Exception {
        
        log.info("Copying non-deleted records from snapshot {} to {}", sourceSnapshotId, targetSnapshotId);
        
        int copiedCount = 0;
        
        try (OAIRecordCatalogManager source = OAIRecordCatalogManager.forReading(
                parquetBasePath, sourceSnapshotId, hadoopConf);
             OAIRecordCatalogManager target = OAIRecordCatalogManager.forWriting(
                parquetBasePath, targetSnapshotId, hadoopConf)) {
            
            for (OAIRecordCatalog record : source) {
                if (!record.getDeleted()) {
                    // Crear copia con nuevo ID
                    OAIRecordCatalog copy = OAIRecordCatalog.builder()
                        .id(++copiedCount)  // Nuevo ID secuencial
                        .identifier(record.getIdentifier())
                        .datestamp(record.getDatestamp())
                        .originalMetadataHash(record.getOriginalMetadataHash())
                        .deleted(false)
                        .build();
                    
                    target.writeRecord(copy);
                }
            }
            
        } catch (IOException e) {
            log.error("Error copying records between snapshots", e);
            throw new Exception("Failed to copy records", e);
        }
        
        log.info("Copied {} non-deleted records", copiedCount);
    }
    
    /**
     * Obtener un registro por ID.
     */
    @Override
    public Optional<OAIRecord> getRecordById(Long recordId) throws Exception {
        
        Long snapshotId = extractSnapshotIdFromRecordId(recordId);
        
        try (OAIRecordCatalogManager manager = OAIRecordCatalogManager.forReading(
                parquetBasePath, snapshotId, hadoopConf)) {
            
            // Buscar registro por ID (iteración - podría optimizarse con índice)
            for (OAIRecordCatalog catalog : manager) {
                if (catalog.getId().equals(recordId)) {
                    NetworkSnapshot snapshot = snapshotRepository.findById(snapshotId).orElse(null);
                    return Optional.of(adaptCatalogToOAIRecord(catalog, snapshot));
                }
            }
            
        } catch (IOException e) {
            log.error("Error reading catalog record", e);
            throw new Exception("Failed to get record", e);
        }
        
        return Optional.empty();
    }
    
    /**
     * Obtener catálogo por ID (método específico de Parquet, no en interfaz).
     */
    public Optional<OAIRecordCatalog> getCatalogById(Long snapshotId, Long recordId) throws IOException {
        
        try (OAIRecordCatalogManager manager = OAIRecordCatalogManager.forReading(
                parquetBasePath, snapshotId, hadoopConf)) {
            
            for (OAIRecordCatalog catalog : manager) {
                if (catalog.getId().equals(recordId)) {
                    return Optional.of(catalog);
                }
            }
        }
        
        return Optional.empty();
    }
    
    /**
     * Adaptar OAIRecordCatalog a OAIRecord para compatibilidad con interfaz.
     * 
     * NOTA: Los campos de validación (status, transformed) NO están disponibles
     * en el catálogo. Si se necesitan, deben obtenerse desde ValidationIndex.
     */
    private OAIRecord adaptCatalogToOAIRecord(OAIRecordCatalog catalog, NetworkSnapshot snapshot) {
        OAIRecord record = new OAIRecord();
        record.setId(catalog.getId());
        record.setIdentifier(catalog.getIdentifier());
        record.setDatestamp(catalog.getDatestamp());
        record.setOriginalMetadataHash(catalog.getOriginalMetadataHash());
        record.setDeleted(catalog.getDeleted());
        record.setSnapshot(snapshot);
        
        // Campos de validación NO disponibles en catálogo
        // Si IndexerWorker los necesita, debe usar ValidationIndex
        record.setStatus(null);  // Se obtiene de ValidationIndex
        record.setTransformed(null);  // Se obtiene de ValidationIndex
        
        return record;
    }
    
    /**
     * Extraer snapshotId del recordId compuesto.
     * 
     * TODO: Implementar lógica según cómo se codifica el ID.
     * Opciones:
     * 1. recordId = snapshotId * 1000000000 + localId
     * 2. Mantener mapa en memoria
     * 3. Buscar en todos los snapshots (lento)
     */
    private Long extractSnapshotIdFromRecordId(Long recordId) {
        // Implementación simplificada - ajustar según necesidad
        // Por ahora asumimos que el recordId contiene el snapshotId de alguna forma
        throw new UnsupportedOperationException("extractSnapshotIdFromRecordId not implemented");
    }
}
```

**Validaciones:**
- ✅ Implementa `IMetadataRecordStoreService`
- ✅ Anotado con `@Service` y `@Primary`
- ✅ Inyecta `NetworkSnapshotRepository` y `parquetBasePath`
- ✅ Usa managers Parquet para todas las operaciones
- ✅ Mantiene NetworkSnapshot en SQL
- ✅ Compila sin errores

---

### 3.2 ParquetValidRecordsPaginator

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/core/metadata/ParquetValidRecordsPaginator.java`

**Propósito**: Implementación de `IPaginator<OAIRecord>` que filtra registros válidos usando ValidationIndex en memoria

**Instrucciones para el agente IA:**

1. Implementar `IPaginator<OAIRecord>`
2. Cargar `ValidationIndex` en memoria al inicio
3. Iterar sobre `OAIRecordCatalog` filtrando por validez
4. Combinar datos de catálogo + validación para construir OAIRecord completo

**Código completo:**

```java
package org.lareferencia.core.metadata;

import lombok.extern.log4j.Log4j2;
import org.apache.hadoop.conf.Configuration;
import org.lareferencia.backend.domain.NetworkSnapshot;
import org.lareferencia.backend.domain.OAIRecord;
import org.lareferencia.backend.domain.RecordStatus;
import org.lareferencia.backend.domain.parquet.OAIRecordCatalog;
import org.lareferencia.backend.domain.parquet.ValidationIndex;
import org.lareferencia.backend.repositories.parquet.OAIRecordCatalogManager;
import org.lareferencia.backend.repositories.parquet.ValidationIndexManager;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/**
 * Paginator que combina OAIRecordCatalog + ValidationIndex.
 * 
 * Estrategia:
 * 1. Cargar ValidationIndex completo en memoria (~350 MB para 10M records)
 * 2. Iterar OAIRecordCatalog con lazy loading
 * 3. Filtrar registros válidos usando el índice
 * 4. Retornar páginas de tamaño configurado
 * 
 * Performance:
 * - Carga inicial: ~10 seg para cargar índice
 * - Iteración: ~1 min para 10M records (lectura secuencial Parquet)
 * - Filtrado: O(1) usando índice en memoria
 */
@Log4j2
public class ParquetValidRecordsPaginator implements IPaginator<OAIRecord> {
    
    private final String basePath;
    private final Long snapshotId;
    private final NetworkSnapshot snapshot;
    private final int pageSize;
    private final Configuration hadoopConf;
    
    private Map<Long, ValidationIndex> validationIndex;
    private Iterator<OAIRecordCatalog> catalogIterator;
    private OAIRecordCatalogManager catalogManager;
    
    private Long currentRecordId;
    
    public ParquetValidRecordsPaginator(
            String basePath,
            Long snapshotId,
            NetworkSnapshot snapshot,
            int pageSize,
            Configuration hadoopConf) throws IOException {
        
        this.basePath = basePath;
        this.snapshotId = snapshotId;
        this.snapshot = snapshot;
        this.pageSize = pageSize;
        this.hadoopConf = hadoopConf;
        this.currentRecordId = 0L;
        
        initialize();
    }
    
    /**
     * Inicializar: cargar índice en memoria y abrir catálogo.
     */
    private void initialize() throws IOException {
        
        log.info("Initializing ParquetValidRecordsPaginator for snapshot {}", snapshotId);
        
        // 1. Cargar índice de validación en memoria
        ValidationIndexManager indexManager = new ValidationIndexManager(basePath, hadoopConf);
        this.validationIndex = indexManager.loadIndex(snapshotId);
        
        log.info("Loaded validation index with {} entries", validationIndex.size());
        
        // 2. Abrir catálogo para lectura lazy
        this.catalogManager = OAIRecordCatalogManager.forReading(basePath, snapshotId, hadoopConf);
        this.catalogIterator = catalogManager.iterator();
    }
    
    /**
     * Obtener siguiente página de registros válidos.
     */
    @Override
    public List<OAIRecord> nextPage() {
        
        List<OAIRecord> page = new ArrayList<>(pageSize);
        
        while (catalogIterator.hasNext() && page.size() < pageSize) {
            OAIRecordCatalog catalog = catalogIterator.next();
            
            // Filtrar por validez usando índice
            ValidationIndex validation = validationIndex.get(catalog.getId());
            
            if (validation != null && validation.getIsValid() && !catalog.getDeleted()) {
                // Combinar catálogo + validación
                OAIRecord record = buildOAIRecord(catalog, validation);
                page.add(record);
                currentRecordId = catalog.getId();
            }
        }
        
        return page;
    }
    
    /**
     * Construir OAIRecord combinando catálogo + validación.
     */
    private OAIRecord buildOAIRecord(OAIRecordCatalog catalog, ValidationIndex validation) {
        
        OAIRecord record = new OAIRecord();
        
        // Datos del catálogo
        record.setId(catalog.getId());
        record.setIdentifier(catalog.getIdentifier());
        record.setDatestamp(catalog.getDatestamp());
        record.setOriginalMetadataHash(catalog.getOriginalMetadataHash());
        record.setDeleted(catalog.getDeleted());
        record.setSnapshot(snapshot);
        
        // Datos de validación
        record.setStatus(validation.getIsValid() ? RecordStatus.VALID : RecordStatus.INVALID);
        record.setTransformed(validation.getIsTransformed());
        
        // Hash publicado (para indexación)
        record.setPublishedMetadataHash(validation.getPublishedMetadataHash());
        
        return record;
    }
    
    @Override
    public boolean hasNext() {
        return catalogIterator.hasNext();
    }
    
    @Override
    public Long getCurrentRecordId() {
        return currentRecordId;
    }
    
    @Override
    public void close() throws IOException {
        if (catalogManager != null) {
            catalogManager.close();
            log.info("Closed ParquetValidRecordsPaginator");
        }
    }
}
```

**Validaciones:**
- ✅ Implementa `IPaginator<OAIRecord>`
- ✅ Carga `ValidationIndex` en memoria
- ✅ Usa lazy iteration sobre catálogo
- ✅ Filtra por validez O(1) usando índice
- ✅ Combina datos de catálogo + validación
- ✅ Implementa `AutoCloseable` para cerrar recursos
- ✅ Compila sin errores

---

### 3.3 Configuración Spring

**Ubicación**: `lareferencia-core-lib/src/main/resources/application.properties`

**Instrucciones para el agente IA:**

Agregar configuración de ruta base para Parquet:

```properties
# Parquet Storage Configuration
backend.parquet.basePath=/data/parquet

# Opcional: habilitar/deshabilitar Parquet
backend.parquet.enabled=true
```

**Ubicación alternativa**: Si el proyecto usa `application.yml`:

```yaml
backend:
  parquet:
    basePath: /data/parquet
    enabled: true
```

---

### 3.4 Checklist Fase 3

**Antes de continuar a Fase 4, verificar:**

- [ ] `ParquetMetadataRecordStoreService.java` creado e implementa `IMetadataRecordStoreService`
- [ ] `ParquetValidRecordsPaginator.java` creado e implementa `IPaginator<OAIRecord>`
- [ ] Configuración `backend.parquet.basePath` agregada
- [ ] Service anotado con `@Primary` para que Spring lo use
- [ ] Compila sin errores
- [ ] Inyección de dependencias funciona (NetworkSnapshotRepository)
- [ ] Test de integración básico (opcional)

**Comandos de verificación:**

```bash
# Compilar módulo
cd lareferencia-core-lib
mvn clean compile

# Verificar service creado
find src/main/java -name "ParquetMetadataRecordStoreService.java"
find src/main/java -name "ParquetValidRecordsPaginator.java"

# Verificar configuración
grep "parquet.basePath" src/main/resources/application.properties
# O para YAML:
grep "parquet:" src/main/resources/application.yml

# Test de Spring context (asegurar que el service se carga)
mvn test -Dtest=ApplicationContextTest  # Si existe
```

---

## FASE 4: ACTUALIZACIÓN DE WORKERS

**Duración**: 2 semanas  
**Dependencias**: Fase 3 completada  
**Objetivo**: Adaptar workers para usar arquitectura Parquet

### 4.1 HarvestingWorker

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/workers/harvesting/HarvestingWorker.java`

**Cambios requeridos**: Escribir a `OAIRecordCatalog` en lugar de OAIRecord SQL

**Instrucciones para el agente IA:**

1. **NO reescribir** el worker completo
2. Solo modificar el método `processItem()` donde se guarda el registro
3. Cambiar de `metadataStoreService.createRecord()` a uso directo de `OAIRecordCatalogManager`

**Cambio en el método processItem():**

```java
@Override
public void processItem(String identifier) {
    
    // ... código existente de harvesting OAI-PMH ...
    
    // ANTES (SQL):
    // OAIRecord record = metadataStoreService.createRecord(
    //     snapshotId, identifier, datestamp, metadataHash, deleted);
    
    // DESPUÉS (Parquet):
    Long recordId = catalogManager.getTotalRecordsWritten() + 1;
    
    OAIRecordCatalog catalog = OAIRecordCatalog.builder()
        .id(recordId)
        .identifier(identifier)
        .datestamp(datestamp)
        .originalMetadataHash(metadataHash)
        .deleted(deleted)
        .build();
    
    try {
        catalogManager.writeRecord(catalog);
        
        // Actualizar contador en snapshot
        snapshot.incrementSize();
        
    } catch (IOException e) {
        log.error("Error writing catalog record for {}", identifier, e);
        throw new RuntimeException("Failed to write catalog record", e);
    }
}
```

**Cambio en preRun():**

```java
@Override
public void preRun() {
    
    // ... código existente ...
    
    // NUEVO: Abrir catalog manager para escritura
    try {
        this.catalogManager = OAIRecordCatalogManager.forWriting(
            parquetBasePath, 
            snapshotId, 
            hadoopConf
        );
    } catch (IOException e) {
        log.error("Error opening catalog manager", e);
        throw new RuntimeException("Failed to initialize catalog manager", e);
    }
}
```

**Cambio en postRun():**

```java
@Override
public void postRun() {
    
    // ... código existente ...
    
    // NUEVO: Cerrar catalog manager y hacer flush final
    if (catalogManager != null) {
        try {
            catalogManager.close();  // Hace flush automático
            log.info("Harvesting completed. Total records: {}", 
                     catalogManager.getTotalRecordsWritten());
        } catch (IOException e) {
            log.error("Error closing catalog manager", e);
        }
    }
}
```

**Agregar campo a la clase:**

```java
private OAIRecordCatalogManager catalogManager;
private String parquetBasePath;  // Inyectar desde configuración
private Configuration hadoopConf;  // Inyectar desde configuración
```

**Validaciones:**
- ✅ `catalogManager` abierto en `preRun()`
- ✅ Escritura en `processItem()` usando `catalogManager.writeRecord()`
- ✅ Cierre con flush en `postRun()`
- ✅ Actualización de contadores en `NetworkSnapshot`
- ✅ Compila sin errores
- ✅ No rompe harvesting existente

---

### 4.2 ValidationWorker

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/workers/validator/ValidationWorker.java`

**Cambios requeridos**: 
1. Escribir `RecordValidation` con campos nuevos (`recordId`, `publishedMetadataHash`, `validatedAt`)
2. Regenerar `ValidationIndex` en `postRun()`

**Instrucciones para el agente IA:**

1. Modificar `processItem()` para agregar los 3 campos nuevos a `RecordValidation`
2. Agregar llamada a `ValidationIndexManager.rebuildIndex()` en `postRun()`

**Cambio en processItem():**

```java
@Override
public void processItem(OAIRecord record) {
    
    // 1. Leer metadata original del catálogo
    OAIRecordCatalog catalog = catalogManager.readById(record.getId());
    String metadataXml = metadataStore.getMetadata(catalog.getOriginalMetadataHash());
    OAIRecordMetadata metadata = OAIRecordMetadata.fromString(metadataXml);
    
    // 2. Validar (código existente)
    ValidatorResult result = validator.validate(metadata);
    
    // 3. Transformar si es válido
    String publishedHash = null;
    boolean wasTransformed = false;
    
    if (result.isValid() && transformer != null) {
        metadata = transformer.transform(metadata);
        wasTransformed = true;
        
        // Almacenar metadata transformada y obtener hash
        publishedHash = metadataStore.storeAndReturnHash(metadata.toString());
        
    } else if (result.isValid()) {
        // Válido pero no transformado: usar hash original
        publishedHash = catalog.getOriginalMetadataHash();
    }
    // Si inválido: publishedHash = null
    
    // 4. Escribir validación (CON CAMPOS NUEVOS)
    RecordValidation validation = RecordValidation.builder()
        .id(String.valueOf(record.getId()))  // Mantener compatibilidad
        .recordId(record.getId())           // NUEVO
        .identifier(record.getIdentifier())
        .recordIsValid(result.isValid())
        .isTransformed(wasTransformed)
        .publishedMetadataHash(publishedHash)  // NUEVO
        .validatedAt(LocalDateTime.now())      // NUEVO
        .ruleFacts(result.getRuleFacts())
        .build();
    
    validationStatisticsService.writeValidationRecord(validation);
    
    // 5. Actualizar contadores en snapshot (SQL)
    if (result.isValid()) {
        snapshot.incrementValidSize();
    }
    if (wasTransformed) {
        snapshot.incrementTransformedSize();
    }
}
```

**Cambio en postRun():**

```java
@Override
public void postRun() {
    
    // ... código existente ...
    
    // NUEVO: Regenerar índice de validación
    try {
        log.info("Rebuilding validation index for snapshot {}", snapshotId);
        
        ValidationIndexManager indexManager = new ValidationIndexManager(
            parquetBasePath, 
            hadoopConf
        );
        
        indexManager.rebuildIndex(snapshotId);
        
        log.info("Validation index rebuilt successfully");
        
    } catch (IOException e) {
        log.error("Error rebuilding validation index", e);
        throw new RuntimeException("Failed to rebuild validation index", e);
    }
}
```

**Agregar campo a la clase:**

```java
private String parquetBasePath;  // Inyectar desde configuración
private Configuration hadoopConf;  // Inyectar desde configuración
```

**Validaciones:**
- ✅ `RecordValidation` escrito con 3 campos nuevos
- ✅ `publishedMetadataHash` calculado correctamente (transformado o original)
- ✅ `ValidationIndex` regenerado en `postRun()`
- ✅ Lógica de transformación sin cambios
- ✅ Compila sin errores
- ✅ No rompe validación existente

---

### 4.3 IndexerWorker

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/workers/indexer/IndexerWorker.java`

**Cambios requeridos**:
1. Cargar `ValidationIndex` en memoria en `preRun()`
2. Usar hash de `ValidationIndex` para obtener metadata a indexar

**Instrucciones para el agente IA:**

1. Modificar `preRun()` para cargar índice en memoria
2. Modificar `processItem()` para usar hash del índice
3. Simplificar lógica de obtención de metadata

**Cambio en preRun():**

```java
@Override
public void preRun() {
    
    // ... código existente ...
    
    // NUEVO: Cargar índice de validación en memoria
    try {
        log.info("Loading validation index for snapshot {}", snapshotId);
        
        ValidationIndexManager indexManager = new ValidationIndexManager(
            parquetBasePath, 
            hadoopConf
        );
        
        this.validationIndex = indexManager.loadIndex(snapshotId);
        
        log.info("Loaded validation index with {} entries (~{} MB)", 
                 validationIndex.size(),
                 (validationIndex.size() * 72) / (1024 * 1024));
        
    } catch (IOException e) {
        log.error("Error loading validation index", e);
        throw new RuntimeException("Failed to load validation index", e);
    }
    
    // MODIFICAR: Crear paginator con índice
    IPaginator<OAIRecord> paginator = new ParquetValidRecordsPaginator(
        parquetBasePath,
        snapshotId,
        snapshot,
        pageSize,
        hadoopConf
    );
    
    this.setPaginator(paginator);
}
```

**Cambio en processItem():**

```java
@Override
public void processItem(OAIRecord record) {
    
    // 1. Obtener validación desde índice en memoria
    ValidationIndex validation = validationIndex.get(record.getId());
    
    if (validation == null) {
        log.warn("No validation found for record {}", record.getId());
        return;
    }
    
    // 2. Filtrar por delete (si ejecuteDeletion)
    if (executeDeletion && (!validation.getIsValid() || record.getDeleted())) {
        deleteRecord(record.getId());
        return;
    }
    
    // 3. Obtener metadata usando hash del índice
    // SIMPLIFICADO: ya no hay lógica condicional transformado/original
    // El ValidationIndex SIEMPRE tiene el hash correcto
    String metadataHash = validation.getPublishedMetadataHash();
    
    if (metadataHash == null) {
        log.warn("No published metadata hash for record {}", record.getId());
        return;
    }
    
    String metadataXml = metadataStore.getMetadata(metadataHash);
    
    // 4. Indexar (código existente sin cambios)
    indexToSolr(metadataXml);
}
```

**Agregar campo a la clase:**

```java
private Map<Long, ValidationIndex> validationIndex;
private String parquetBasePath;  // Inyectar desde configuración
private Configuration hadoopConf;  // Inyectar desde configuración
```

**Validaciones:**
- ✅ `ValidationIndex` cargado en `preRun()`
- ✅ Lookup O(1) en `validationIndex` Map
- ✅ Lógica simplificada: siempre usar `publishedMetadataHash` del índice
- ✅ Filtrado por validez funciona
- ✅ Compila sin errores
- ✅ No rompe indexación existente

---

### 4.4 Configuración de Workers

**Instrucciones para el agente IA:**

Todos los workers necesitan inyección de `parquetBasePath` y `hadoopConf`. Opciones:

**Opción 1: Inyectar en constructor**

```java
@Autowired
public HarvestingWorker(
    @Value("${backend.parquet.basePath}") String parquetBasePath,
    // ... otras dependencias ...
) {
    this.parquetBasePath = parquetBasePath;
    this.hadoopConf = createHadoopConfiguration();
}
```

**Opción 2: Crear bean de configuración**

```java
@Configuration
public class ParquetConfiguration {
    
    @Bean
    public Configuration hadoopConfiguration() {
        Configuration conf = new Configuration();
        conf.set("parquet.compression", "SNAPPY");
        conf.set("parquet.block.size", "134217728");
        conf.set("parquet.page.size", "1048576");
        conf.set("parquet.enable.dictionary", "true");
        return conf;
    }
}
```

Luego inyectar:

```java
@Autowired
private Configuration hadoopConf;
```

---

### 4.5 Checklist Fase 4

**Antes de continuar a Fase 5, verificar:**

- [ ] `HarvestingWorker` modificado para escribir a `OAIRecordCatalogManager`
- [ ] `ValidationWorker` modificado para escribir `RecordValidation` con campos nuevos
- [ ] `ValidationWorker.postRun()` regenera `ValidationIndex`
- [ ] `IndexerWorker` modificado para usar `ValidationIndex` en memoria
- [ ] Inyección de `parquetBasePath` y `hadoopConf` en todos los workers
- [ ] Todos los workers compilan sin errores
- [ ] Test de harvesting funciona
- [ ] Test de validación funciona
- [ ] Test de indexación funciona

**Comandos de verificación:**

```bash
# Compilar módulo
cd lareferencia-core-lib
mvn clean compile

# Verificar modificaciones en workers
grep -n "OAIRecordCatalogManager" src/main/java/org/lareferencia/backend/workers/harvesting/HarvestingWorker.java
grep -n "publishedMetadataHash" src/main/java/org/lareferencia/backend/workers/validator/ValidationWorker.java
grep -n "ValidationIndex" src/main/java/org/lareferencia/backend/workers/indexer/IndexerWorker.java

# Test integración workers (si existe)
mvn test -Dtest=WorkerIntegrationTest
```

---

## FASE 5: MIGRACIÓN DE DATOS

**Duración**: 1-2 semanas  
**Dependencias**: Fase 4 completada  
**Objetivo**: Migrar datos existentes de SQL a Parquet

### 5.1 Script de Migración

**Ubicación**: `lareferencia-core-lib/src/main/java/org/lareferencia/backend/util/SqlToParquetMigration.java`

**Propósito**: Migrar OAIRecord existentes desde PostgreSQL a Parquet

**Instrucciones para el agente IA:**

1. Crear clase con método `main()` ejecutable
2. Leer todos los snapshots desde SQL
3. Para cada snapshot, migrar OAIRecord → OAIRecordCatalog + RecordValidation
4. Generar ValidationIndex
5. Verificar integridad

**Código completo:**

```java
package org.lareferencia.backend.util;

import lombok.extern.log4j.Log4j2;
import org.apache.hadoop.conf.Configuration;
import org.lareferencia.backend.domain.NetworkSnapshot;
import org.lareferencia.backend.domain.OAIRecord;
import org.lareferencia.backend.domain.RecordStatus;
import org.lareferencia.backend.domain.parquet.OAIRecordCatalog;
import org.lareferencia.backend.domain.parquet.RecordValidation;
import org.lareferencia.backend.repositories.NetworkSnapshotRepository;
import org.lareferencia.backend.repositories.OAIRecordRepository;
import org.lareferencia.backend.repositories.parquet.OAIRecordCatalogManager;
import org.lareferencia.backend.repositories.parquet.ValidationIndexManager;
import org.lareferencia.backend.repositories.parquet.ValidationRecordManager;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;

import java.io.IOException;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

/**
 * Script de migración SQL → Parquet.
 * 
 * Migra:
 * 1. OAIRecord (SQL) → OAIRecordCatalog (Parquet)
 * 2. OAIRecord (SQL) → RecordValidation (Parquet)
 * 3. Genera ValidationIndex
 * 
 * Ejecución:
 * mvn spring-boot:run -Dspring-boot.run.arguments="--migrate.snapshot.id=123"
 * 
 * O para todos los snapshots:
 * mvn spring-boot:run -Dspring-boot.run.arguments="--migrate.all=true"
 */
@SpringBootApplication
@Log4j2
public class SqlToParquetMigration implements CommandLineRunner {
    
    @Autowired
    private NetworkSnapshotRepository snapshotRepository;
    
    @Autowired
    private OAIRecordRepository recordRepository;
    
    @Value("${backend.parquet.basePath:/data/parquet}")
    private String parquetBasePath;
    
    @Value("${migrate.snapshot.id:#{null}}")
    private Long snapshotIdToMigrate;
    
    @Value("${migrate.all:false}")
    private boolean migrateAll;
    
    private Configuration hadoopConf;
    
    public static void main(String[] args) {
        SpringApplication.run(SqlToParquetMigration.class, args);
    }
    
    @Override
    public void run(String... args) throws Exception {
        
        log.info("=== SQL to Parquet Migration ===");
        log.info("Parquet base path: {}", parquetBasePath);
        
        // Crear configuración Hadoop
        hadoopConf = createHadoopConfiguration();
        
        if (migrateAll) {
            log.info("Migrating ALL snapshots");
            migrateAllSnapshots();
        } else if (snapshotIdToMigrate != null) {
            log.info("Migrating snapshot {}", snapshotIdToMigrate);
            migrateSnapshot(snapshotIdToMigrate);
        } else {
            log.error("No snapshot specified. Use --migrate.snapshot.id=X or --migrate.all=true");
            System.exit(1);
        }
        
        log.info("=== Migration completed ===");
    }
    
    /**
     * Migrar todos los snapshots.
     */
    private void migrateAllSnapshots() throws Exception {
        
        List<NetworkSnapshot> snapshots = snapshotRepository.findAll();
        log.info("Found {} snapshots to migrate", snapshots.size());
        
        int success = 0;
        int failed = 0;
        
        for (NetworkSnapshot snapshot : snapshots) {
            try {
                migrateSnapshot(snapshot.getId());
                success++;
            } catch (Exception e) {
                log.error("Failed to migrate snapshot {}", snapshot.getId(), e);
                failed++;
            }
        }
        
        log.info("Migration summary: {} succeeded, {} failed", success, failed);
    }
    
    /**
     * Migrar un snapshot específico.
     */
    private void migrateSnapshot(Long snapshotId) throws Exception {
        
        log.info("Starting migration for snapshot {}", snapshotId);
        
        NetworkSnapshot snapshot = snapshotRepository.findById(snapshotId)
            .orElseThrow(() -> new IllegalArgumentException("Snapshot not found: " + snapshotId));
        
        // Estadísticas
        long totalRecords = 0;
        long catalogRecords = 0;
        long validationRecords = 0;
        
        // 1. Migrar a OAIRecordCatalog
        log.info("Migrating to OAIRecordCatalog...");
        
        try (OAIRecordCatalogManager catalogManager = OAIRecordCatalogManager.forWriting(
                parquetBasePath, snapshotId, hadoopConf)) {
            
            // Leer registros en páginas (evitar OOM)
            int pageSize = 1000;
            int pageNumber = 0;
            Page<OAIRecord> page;
            
            do {
                page = recordRepository.findBySnapshotId(
                    snapshotId, 
                    PageRequest.of(pageNumber, pageSize)
                );
                
                for (OAIRecord record : page.getContent()) {
                    
                    // Crear catálogo
                    OAIRecordCatalog catalog = OAIRecordCatalog.builder()
                        .id(record.getId())
                        .identifier(record.getIdentifier())
                        .datestamp(record.getDatestamp())
                        .originalMetadataHash(record.getOriginalMetadataHash())
                        .deleted(record.getDeleted())
                        .build();
                    
                    catalogManager.writeRecord(catalog);
                    catalogRecords++;
                    totalRecords++;
                }
                
                pageNumber++;
                
                if (pageNumber % 10 == 0) {
                    log.info("Processed {} pages, {} records", pageNumber, totalRecords);
                }
                
            } while (page.hasNext());
        }
        
        log.info("Catalog migration completed: {} records", catalogRecords);
        
        // 2. Migrar a RecordValidation
        log.info("Migrating to RecordValidation...");
        
        try (ValidationRecordManager validationManager = ValidationRecordManager.forWriting(
                parquetBasePath, snapshotId, hadoopConf)) {
            
            int pageNumber = 0;
            Page<OAIRecord> page;
            
            do {
                page = recordRepository.findBySnapshotId(
                    snapshotId, 
                    PageRequest.of(pageNumber, pageSize)
                );
                
                for (OAIRecord record : page.getContent()) {
                    
                    // Determinar publishedMetadataHash
                    String publishedHash = null;
                    if (record.getStatus() == RecordStatus.VALID) {
                        publishedHash = record.getTransformed() != null && record.getTransformed()
                            ? record.getPublishedMetadataHash()
                            : record.getOriginalMetadataHash();
                    }
                    
                    // Crear validación
                    RecordValidation validation = RecordValidation.builder()
                        .id(String.valueOf(record.getId()))
                        .recordId(record.getId())
                        .identifier(record.getIdentifier())
                        .recordIsValid(record.getStatus() == RecordStatus.VALID)
                        .isTransformed(record.getTransformed() != null && record.getTransformed())
                        .publishedMetadataHash(publishedHash)
                        .validatedAt(LocalDateTime.now())  // Usar fecha de migración
                        .ruleFacts(new ArrayList<>())  // No hay facts en migración
                        .build();
                    
                    validationManager.writeRecord(validation);
                    validationRecords++;
                }
                
                pageNumber++;
                
            } while (page.hasNext());
        }
        
        log.info("Validation migration completed: {} records", validationRecords);
        
        // 3. Generar ValidationIndex
        log.info("Generating ValidationIndex...");
        
        ValidationIndexManager indexManager = new ValidationIndexManager(parquetBasePath, hadoopConf);
        indexManager.rebuildIndex(snapshotId);
        
        log.info("ValidationIndex generated");
        
        // 4. Verificación
        log.info("Verifying migration...");
        verify(snapshotId, totalRecords);
        
        log.info("Migration completed successfully for snapshot {}", snapshotId);
    }
    
    /**
     * Verificar integridad de datos migrados.
     */
    private void verify(Long snapshotId, long expectedRecords) throws IOException {
        
        // Contar registros en catálogo
        long catalogCount = 0;
        try (OAIRecordCatalogManager manager = OAIRecordCatalogManager.forReading(
                parquetBasePath, snapshotId, hadoopConf)) {
            for (OAIRecordCatalog catalog : manager) {
                catalogCount++;
            }
        }
        
        // Contar registros en validación
        long validationCount = 0;
        try (ValidationRecordManager manager = ValidationRecordManager.forReading(
                parquetBasePath, snapshotId, hadoopConf)) {
            for (RecordValidation validation : manager) {
                validationCount++;
            }
        }
        
        // Verificar índice
        ValidationIndexManager indexManager = new ValidationIndexManager(parquetBasePath, hadoopConf);
        long indexCount = indexManager.loadIndex(snapshotId).size();
        
        log.info("Verification results:");
        log.info("  Expected: {}", expectedRecords);
        log.info("  Catalog: {}", catalogCount);
        log.info("  Validation: {}", validationCount);
        log.info("  Index: {}", indexCount);
        
        if (catalogCount != expectedRecords || validationCount != expectedRecords || indexCount != expectedRecords) {
            throw new IllegalStateException("Record count mismatch! Migration may be incomplete.");
        }
        
        log.info("Verification PASSED");
    }
    
    private Configuration createHadoopConfiguration() {
        Configuration conf = new Configuration();
        conf.set("parquet.compression", "SNAPPY");
        conf.set("parquet.block.size", "134217728");
        conf.set("parquet.page.size", "1048576");
        conf.set("parquet.enable.dictionary", "true");
        return conf;
    }
}
```

**Validaciones:**
- ✅ Lee desde SQL en páginas (evita OOM)
- ✅ Escribe a Parquet en batches
- ✅ Genera ValidationIndex
- ✅ Verifica integridad
- ✅ Logging completo
- ✅ Manejo de errores

---

### 5.2 Proceso de Migración

**Instrucciones para el agente IA:**

Ejecutar migración en este orden:

**Paso 1: Backup de base de datos**

```bash
# Backup PostgreSQL
pg_dump -h localhost -U postgres -d lareferencia > backup_before_migration.sql
```

**Paso 2: Migración de un snapshot de prueba**

```bash
# Migrar snapshot pequeño primero
mvn spring-boot:run -Dspring-boot.run.arguments="--migrate.snapshot.id=1"

# Verificar archivos generados
ls -lh /data/parquet/snapshot_1/
```

**Paso 3: Verificación**

```bash
# Ejecutar test de harvesting + validación + indexación
# con snapshot migrado
```

**Paso 4: Migración completa**

```bash
# Migrar todos los snapshots
mvn spring-boot:run -Dspring-boot.run.arguments="--migrate.all=true"
```

**Paso 5: Activar Parquet en producción**

```properties
# application.properties
backend.parquet.enabled=true
```

---

### 5.3 Checklist Fase 5

- [ ] Script de migración creado y compila
- [ ] Backup de base de datos realizado
- [ ] Migración de snapshot de prueba exitosa
- [ ] Verificación de integridad exitosa
- [ ] Tests con datos migrados exitosos
- [ ] Migración completa realizada
- [ ] Parquet activado en producción

---

## FASE 6: TESTING Y VALIDACIÓN

**Duración**: 1 semana  
**Dependencias**: Fase 5 completada  
**Objetivo**: Validar que todo funciona correctamente

### 6.1 Tests Unitarios

**Crear tests para cada componente:**

**OAIRecordCatalogManagerTest.java:**

```java
@Test
public void testWriteAndRead() throws IOException {
    try (OAIRecordCatalogManager writer = OAIRecordCatalogManager.forWriting(
            testBasePath, 1L, hadoopConf)) {
        
        OAIRecordCatalog record = OAIRecordCatalog.builder()
            .id(1L)
            .identifier("oai:test:1")
            .datestamp(LocalDateTime.now())
            .originalMetadataHash("hash123")
            .deleted(false)
            .build();
        
        writer.writeRecord(record);
    }
    
    try (OAIRecordCatalogManager reader = OAIRecordCatalogManager.forReading(
            testBasePath, 1L, hadoopConf)) {
        
        List<OAIRecordCatalog> records = new ArrayList<>();
        reader.forEach(records::add);
        
        assertEquals(1, records.size());
        assertEquals("oai:test:1", records.get(0).getIdentifier());
    }
}
```

**ValidationIndexManagerTest.java:**

```java
@Test
public void testRebuildAndLoad() throws IOException {
    // Escribir RecordValidation
    // ...
    
    // Rebuild index
    ValidationIndexManager manager = new ValidationIndexManager(testBasePath, hadoopConf);
    manager.rebuildIndex(1L);
    
    // Load index
    Map<Long, ValidationIndex> index = manager.loadIndex(1L);
    
    assertFalse(index.isEmpty());
    assertTrue(index.containsKey(1L));
}
```

---

### 6.2 Tests de Integración

**WorkerIntegrationTest.java:**

```java
@SpringBootTest
public class WorkerIntegrationTest {
    
    @Test
    public void testHarvestingWorker() {
        // Ejecutar harvesting
        // Verificar que se creó OAIRecordCatalog
    }
    
    @Test
    public void testValidationWorker() {
        // Ejecutar validación
        // Verificar que se creó RecordValidation
        // Verificar que se generó ValidationIndex
    }
    
    @Test
    public void testIndexerWorker() {
        // Ejecutar indexación
        // Verificar que se indexó a Solr correctamente
    }
}
```

---

### 6.3 Tests de Performance

**PerformanceTest.java:**

```java
@Test
public void testCatalogWritePerformance() {
    long start = System.currentTimeMillis();
    
    try (OAIRecordCatalogManager manager = OAIRecordCatalogManager.forWriting(
            testBasePath, 1L, hadoopConf)) {
        
        for (int i = 0; i < 100000; i++) {
            OAIRecordCatalog record = createTestRecord(i);
            manager.writeRecord(record);
        }
    }
    
    long duration = System.currentTimeMillis() - start;
    
    log.info("Wrote 100K records in {} ms ({} records/sec)", 
             duration, (100000 * 1000) / duration);
    
    // Objetivo: > 5000 records/sec
    assertTrue(duration < 20000, "Should write 100K records in < 20 seconds");
}
```

---

### 6.4 Checklist Final

**Antes de desplegar a producción:**

- [ ] Todos los tests unitarios pasan
- [ ] Todos los tests de integración pasan
- [ ] Tests de performance cumplen objetivos (> 5K records/sec escritura)
- [ ] Harvesting funciona correctamente
- [ ] Validación funciona correctamente
- [ ] Indexación funciona correctamente
- [ ] ValidationIndex se carga en < 15 segundos
- [ ] Memoria usada por índice < 500 MB
- [ ] No hay memory leaks
- [ ] Logs no muestran errores
- [ ] Documentación actualizada
- [ ] Migración de producción planificada

---

## CHECKLIST DE VERIFICACIÓN COMPLETO

### Pre-implementación

- [ ] Análisis de arquitectura revisado y aprobado
- [ ] Equipo capacitado en Parquet y patrón de separación catálogo/validación
- [ ] Ambiente de desarrollo configurado
- [ ] Acceso a servidor de pruebas
- [ ] Backup de base de datos disponible

### Fase 1: Entidades (1-2 semanas)

- [ ] `OAIRecordCatalog.java` creado sin anotaciones JPA
- [ ] `ValidationIndex.java` creado ligero (~35 bytes/record)
- [ ] `RecordValidation.java` modificado con 3 campos nuevos
- [ ] Todas las entidades compilan
- [ ] Javadoc completo en todas las clases

### Fase 2: Managers (2-3 semanas)

- [ ] `OAIRecordCatalogManager.java` completo con factory methods
- [ ] `CatalogParquetWriter.java` y `CatalogParquetReader.java` creados
- [ ] `ValidationIndexManager.java` con `rebuildIndex()` y `loadIndex()`
- [ ] `IndexParquetWriter.java` y `IndexParquetReader.java` creados
- [ ] `ValidationRecordManager` modificado con 3 campos nuevos
- [ ] Todos los managers implementan `AutoCloseable`
- [ ] Tests unitarios de escritura/lectura pasan
- [ ] Buffering funciona (flush cada 10K records)
- [ ] Lazy iteration funciona (no carga todo en memoria)

### Fase 3: Service Layer (2 semanas)

- [ ] `ParquetMetadataRecordStoreService` implementa `IMetadataRecordStoreService`
- [ ] Service anotado con `@Primary`
- [ ] `ParquetValidRecordsPaginator` implementa `IPaginator<OAIRecord>`
- [ ] Configuración `backend.parquet.basePath` agregada
- [ ] Inyección de dependencias funciona
- [ ] Service compila sin errores
- [ ] Spring context se carga correctamente

### Fase 4: Workers (2 semanas)

- [ ] `HarvestingWorker` escribe a `OAIRecordCatalogManager`
- [ ] `ValidationWorker` escribe `RecordValidation` con campos nuevos
- [ ] `ValidationWorker.postRun()` regenera `ValidationIndex`
- [ ] `IndexerWorker` usa `ValidationIndex` en memoria
- [ ] Configuración inyectada en todos los workers
- [ ] Harvesting funciona end-to-end
- [ ] Validación funciona end-to-end
- [ ] Indexación funciona end-to-end

### Fase 5: Migración (1-2 semanas)

- [ ] Script `SqlToParquetMigration` creado
- [ ] Backup de base de datos realizado
- [ ] Migración de snapshot de prueba exitosa
- [ ] Verificación de integridad exitosa (counts match)
- [ ] ValidationIndex generado correctamente
- [ ] Tests con datos migrados pasan
- [ ] Performance de migración aceptable (> 1K records/sec)
- [ ] Migración completa realizada
- [ ] Archivos Parquet generados en ubicación correcta

### Fase 6: Testing (1 semana)

- [ ] Tests unitarios de managers pasan
- [ ] Tests de integración de workers pasan
- [ ] Tests de performance cumplen objetivos:
  - [ ] Escritura catálogo: > 5K records/sec
  - [ ] Lectura catálogo: > 10K records/sec
  - [ ] Carga ValidationIndex: < 15 segundos
  - [ ] Memoria ValidationIndex: < 500 MB para 10M records
- [ ] No hay memory leaks (verificado con profiler)
- [ ] No hay errores en logs durante 1 hora de operación
- [ ] Harvesting completo exitoso
- [ ] Validación completa exitosa
- [ ] Indexación completa exitosa

### Producción

- [ ] Configuración de producción revisada
- [ ] Monitoreo configurado (métricas de Parquet)
- [ ] Alertas configuradas (errores de escritura/lectura)
- [ ] Plan de rollback documentado
- [ ] Equipo de soporte capacitado
- [ ] Despliegue en horario de baja demanda
- [ ] Verificación post-despliegue:
  - [ ] Harvesting funciona
  - [ ] Validación funciona
  - [ ] Indexación funciona
  - [ ] Performance cumple SLAs
  - [ ] No hay errores en logs
  - [ ] Uso de disco según esperado
  - [ ] Uso de memoria según esperado

---

## TROUBLESHOOTING

### Problema: OutOfMemoryError al cargar ValidationIndex

**Causa**: ValidationIndex muy grande (> 1 GB)

**Solución**:

```java
// Aumentar heap de JVM
java -Xmx2G -jar lareferencia-indexer.jar

// O reducir carga parcial del índice (solo recordIds necesarios)
```

### Problema: IOException "Too many open files"

**Causa**: Límite de file descriptors del SO

**Solución**:

```bash
# Aumentar límite en Linux
ulimit -n 65536

# Verificar
ulimit -n
```

### Problema: Escritura Parquet muy lenta

**Causa**: Configuración de buffering inadecuada

**Solución**:

```java
// Aumentar buffer size
private static final int BUFFER_SIZE = 50000;  // En lugar de 10000

// O ajustar block size
conf.set("parquet.block.size", "268435456");  // 256 MB
```

### Problema: Registros duplicados después de migración

**Causa**: Migración ejecutada múltiples veces sin limpiar

**Solución**:

```bash
# Limpiar directorio Parquet antes de re-migrar
rm -rf /data/parquet/snapshot_*

# Re-ejecutar migración
mvn spring-boot:run -Dspring-boot.run.arguments="--migrate.all=true"
```

### Problema: ValidationIndex no se encuentra

**Causa**: `rebuildIndex()` no ejecutado después de validación

**Solución**:

```java
// Verificar que ValidationWorker.postRun() llama a rebuildIndex()
@Override
public void postRun() {
    // ...
    indexManager.rebuildIndex(snapshotId);  // ← DEBE estar
}
```

### Problema: Metadata hash no encontrado en IMetadataStore

**Causa**: `publishedMetadataHash` apunta a hash inexistente

**Solución**:

```java
// Verificar que ValidationWorker almacena metadata transformada
if (wasTransformed) {
    publishedHash = metadataStore.storeAndReturnHash(transformedXml);  // ← DEBE almacenar
}
```

### Problema: Performance de indexación degradada

**Causa**: ValidationIndex no cargado en memoria, lectura desde disco en cada record

**Solución**:

```java
// Verificar que IndexerWorker.preRun() carga índice
this.validationIndex = indexManager.loadIndex(snapshotId);  // ← Una sola vez

// NO hacer esto en processItem():
// validationIndex = indexManager.loadIndex(snapshotId);  // ✗ INCORRECTO
```

---

## MÉTRICAS DE ÉXITO

### Performance Esperada

| Operación | Baseline (SQL) | Target (Parquet) | Mejora |
|-----------|---------------|------------------|---------|
| Escritura harvesting | 2K records/sec | 6K records/sec | 3x |
| Lectura para validación | 1.5K records/sec | 8K records/sec | 5x |
| Escritura validación | 1K records/sec | 5K records/sec | 5x |
| Carga índice (10M records) | N/A (query SQL) | < 15 seg | N/A |
| Filtrado para indexación | 500 records/sec | 8K records/sec | 16x |

### Almacenamiento Esperado

| Componente | 10M records | Compresión |
|------------|-------------|------------|
| OAIRecordCatalog | ~400 MB | SNAPPY |
| RecordValidation | ~2 GB | SNAPPY |
| ValidationIndex | ~350 MB | SNAPPY |
| **Total Parquet** | **~2.75 GB** | - |
| SQL (antes) | ~15 GB | - |
| **Ahorro** | **~82%** | - |

### Memoria Esperada

| Componente | Heap usado | Notas |
|------------|-----------|-------|
| ValidationIndex (10M) | ~350 MB | Cargado completo |
| Catalog iteration | ~50 MB | Lazy loading |
| Validation writing | ~100 MB | Buffer 10K records |
| **Total worker** | **~500 MB** | Peak durante indexación |

---

## CONTACTOS Y RECURSOS

### Documentación de Referencia

- **Análisis completo**: `docs/ANALISIS_REDUNDANCIA_VALIDACION.md`
- **Análisis OAIRecord**: `docs/ANALISIS_OAIRECORD_PARQUET.md`
- **Apache Parquet**: https://parquet.apache.org/docs/
- **Hadoop Configuration**: https://hadoop.apache.org/docs/stable/

### Código de Referencia

- **ValidationRecordManager**: Patrón a seguir para todos los managers
- **MetadataRecordStoreServiceImpl**: Service layer a reemplazar
- **Workers existentes**: Estructura de preRun/processItem/postRun

### Equipo

- **Arquitecto**: [Nombre]
- **Desarrollador lead**: [Nombre]
- **QA**: [Nombre]
- **DevOps**: [Nombre]

---

## NOTAS FINALES PARA EL AGENTE IA

### Principios a Seguir

1. **No inventar**: Seguir EXACTAMENTE los patrones existentes (`ValidationRecordManager`)
2. **Immutabilidad**: `OAIRecordCatalog` NUNCA se actualiza, solo se crea
3. **Separación**: Catálogo (inmutable) vs Validación (mutable)
4. **Performance**: Lazy iteration, buffering, compresión
5. **Verificación**: Siempre verificar counts después de escribir

### Cuando Pedir Ayuda

- Si un patrón existente no está claro
- Si hay conflicto entre interfaces existentes y nueva arquitectura
- Si performance no cumple targets
- Si migración falla con errores de integridad

### Comandos Útiles Durante Implementación

```bash
# Compilar sin tests
mvn clean compile -DskipTests

# Compilar solo un módulo
cd lareferencia-core-lib && mvn clean install

# Ver tamaño de archivos Parquet
du -sh /data/parquet/snapshot_*/

# Contar registros en Parquet
parquet-tools rowcount /data/parquet/snapshot_1/catalog/records_batch_0001.parquet

# Ver schema Parquet
parquet-tools schema /data/parquet/snapshot_1/catalog/records_batch_0001.parquet

# Ver primeros registros
parquet-tools head /data/parquet/snapshot_1/catalog/records_batch_0001.parquet
```

---

**FIN DEL PLAN DE IMPLEMENTACIÓN**

**Versión**: 1.0  
**Última actualización**: 10 de noviembre de 2025  
**Estado**: Listo para ejecución

