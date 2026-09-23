> **[ARCHIVED 2026-09-23]** This document describes the multi-threaded indexing pipeline (buffer → distributor → writers) that was **removed** in commit `1b894e7` (2025-11-09). The current model is documented in [`../ENTITY_INDEXING_ARCHITECTURE.md`](../ENTITY_INDEXING_ARCHITECTURE.md). Kept for historical reference.

# Análisis del Modelo de Procesamiento de Indexación Multithreading - Elasticsearch

## 📋 Resumen Ejecutivo

El sistema de indexación de LA Referencia para **Elasticsearch** implementa un **modelo de procesamiento multithreading altamente sofisticado** con arquitectura **Producer-Consumer** optimizada específicamente para aprovechar las capacidades de indexación concurrente de Elasticsearch.

**Veredicto:** ✅ **SÍ es multithreading** - implementación profesional optimizada para Elasticsearch con control de concurrencia avanzado.

**Nota:** Este análisis se enfoca exclusivamente en la implementación de Elasticsearch. Se omiten las implementaciones de TDB1/TDB2 para RDF.

---

## 🏗️ Arquitectura Elasticsearch - Producer-Consumer con Múltiples Writers

### Diagrama de Flujo Completo

```
┌──────────────────────────────────────────────────────────────────────────┐
│ CAPA DE PRODUCCIÓN (Indexing Threads)                                    │
│                                                                           │
│  Thread 1 ──┐                                                            │
│  Thread 2 ──┤                                                            │
│  Thread 3 ──┼──> ExecutorService (CPU cores threads)                     │
│  Thread N ──┘      │                                                     │
│                    │                                                     │
│                    ▼                                                     │
│              [Semaphore]  ← Control: maxConcurrentTasks (2x cores)       │
│                    │                                                     │
│                    ▼                                                     │
│         BlockingQueue (documentBuffer)  ← 10,000 documentos              │
└──────────────────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ CAPA DE DISTRIBUCIÓN (Single Thread)                                     │
│                                                                           │
│          Distributor Thread (Round-Robin)                                │
│                 │                                                        │
│                 ├──> OutputQueue 1 (Elastic Writer 1)                    │
│                 ├──> OutputQueue 2 (Elastic Writer 2)                    │
│                 ├──> OutputQueue 3 (Elastic Writer 3)                    │
│                 ├──> OutputQueue 4 (Elastic Writer 4)                    │
│                 ├──> OutputQueue 5 (Elastic Writer 5)                    │
│                 └──> OutputQueue 6 (Elastic Writer 6)                    │
└──────────────────────────────────────────────────────────────────────────┘
                     │
                     ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ CAPA DE ESCRITURA (Elasticsearch Writers - 2 a 6 threads concurrentes)   │
│                                                                           │
│  Elastic Writer Thread 1  ──┐                                            │
│  Elastic Writer Thread 2  ──┤                                            │
│  Elastic Writer Thread 3  ──┼──> Elasticsearch Bulk API                  │
│  Elastic Writer Thread 4  ──┤     (Concurrent Indexing)                  │
│  Elastic Writer Thread 5  ──┤                                            │
│  Elastic Writer Thread 6  ──┘                                            │
│                                                                           │
│  Cada writer:                                                            │
│  - Acumula documentos en batch                                           │
│  - Bulk request cada N documentos o timeout                              │
│  - Retry con backoff exponencial                                         │
│  - Manejo de errores granular                                            │
└──────────────────────────────────────────────────────────────────────────┘
                     │
                     ▼
              Elasticsearch Cluster
```

### Características Clave de la Arquitectura

**1. Producers (Indexing Threads):**
- Número de threads = CPU cores disponibles
- Cada thread carga una entidad completa de BD
- Transacción independiente por entidad (REQUIRES_NEW)
- Preload de relaciones para evitar lazy loading

**2. Distributor (Thread Único):**
- Consume del buffer principal (documentBuffer)
- Distribuye documentos round-robin entre writers
- Balance de carga automático
- Maneja markers de flush y shutdown

**3. Elasticsearch Writers (2-6 Threads):**
- **Cálculo automático:** `Math.max(2, Math.min(indexingThreads, 6))`
- **Configurable:** `elastic.indexer.writer.threads` en properties
- Escritura concurrente aprovechando capacidad de Elasticsearch
- Bulk API para reducir overhead de red
- Cada writer es independiente con su propia conexión

---

## 🔍 JSONElasticEntityIndexerThreadedImpl - Implementación Detallada

### Configuración de Threading

**ExecutorServices:**
```java
private ExecutorService indexingExecutor;  // Pool de threads para indexación
private ExecutorService utilityExecutor;   // Thread único para monitoreo
```

**Parámetros de Configuración:**
```java
private int indexingThreads = Runtime.getRuntime().availableProcessors();
private int bufferSize = 10000;
private int maxConcurrentTasks = indexingThreads * 2;
private int elasticWriterThreads = Math.max(2, Math.min(indexingThreads, 6));
```

**Cálculo Automático de Writers:**
- **Mínimo:** 2 writers (garantiza concurrencia básica)
- **Máximo:** 6 writers (óptimo para clusters Elasticsearch)
- **Auto-ajuste:** Basado en CPU cores disponibles
- **Override:** Configurable vía `elastic.indexer.writer.threads` en properties

### Componentes de Sincronización

**1. Semaphore (Control de Backpressure):**
```java
private Semaphore concurrentTasksSemaphore = new Semaphore(maxConcurrentTasks);
```
- **Propósito:** Limitar tareas de indexación concurrentes
- **Límite:** 2x número de CPU cores
- **Efecto:** Evita saturación de memoria y BD

**2. Phaser (Sincronización de Fases):**
```java
private final Phaser activeIndexingPhaser = new Phaser(1);
```
- **Propósito:** Rastrear productores activos
- **Uso:** Sincronizar operación flush
- **Mecanismo:** Register/arriveAndDeregister por tarea

**3. BlockingQueues (Comunicación Thread-Safe):**
```java
private BlockingQueue<Object> documentBuffer = new LinkedBlockingQueue<>(10000);
private final List<BlockingQueue<Object>> outputQueues = new ArrayList<>();
```
- **Buffer principal:** 10,000 documentos JSON
- **Output queues:** Una por cada Elasticsearch writer
- **Thread-safe:** No requiere sincronización externa

---

## ⚙️ Flujo de Procesamiento Completo

### Fase 1: Producción de Documentos (Indexing Threads)

**Método Principal `index(Entity)`:**
```java
@Override
public void index(Entity entity) throws EntityIndexingException {
    // 1. Adquirir permiso del semáforo (BLOCKING si no hay slots)
    concurrentTasksSemaphore.acquire();
    
    // 2. Registrar en phaser
    activeIndexingPhaser.register();
    
    // 3. Capturar solo el ID (evitar lazy loading)
    final UUID entityId = entity.getId();
    
    // 4. Lanzar procesamiento asíncrono
    CompletableFuture.runAsync(() -> {
        try {
            processEntityAsync(entityId);
        } finally {
            concurrentTasksSemaphore.release();
            activeIndexingPhaser.arriveAndDeregister();
        }
    }, indexingExecutor);
    
    // 5. Retornar INMEDIATAMENTE (non-blocking)
}
```

**Procesamiento Asíncrono por Entidad:**
```java
private void processEntityAsync(UUID entityId) {
    // 1. Crear transacción INDEPENDIENTE
    DefaultTransactionDefinition def = new DefaultTransactionDefinition();
    def.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
    def.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
    TransactionStatus status = transactionManager.getTransaction(def);
    
    try {
        // 2. Recargar entidad desde BD (thread-safe)
        Entity freshEntity = entityDataService.getEntityById(entityId).get();
        
        // 3. Pre-cargar todas las relaciones (evitar lazy loading)
        Entity fullyLoadedEntity = preloadEntityData(freshEntity);
        
        // 4. Generar documento JSON
        JSONEntityElastic jsonDoc = buildJSONDocument(fullyLoadedEntity);
        
        // 5. Enviar a buffer
        documentBuffer.put(jsonDoc);
        documentsProduced.incrementAndGet();
        
        // 6. Commit transacción
        transactionManager.commit(status);
        
    } catch (Exception e) {
        transactionManager.rollback(status);
        throw e;
    }
}
```

### Fase 2: Distribución (Distributor Thread)

**Thread Distribuidor (Round-Robin):**
```java
private class Distributor implements Runnable {
    private int currentWriterIndex = 0;
    
    @Override
    public void run() {
        while (!shutdown) {
            try {
                Object item = documentBuffer.take(); // BLOCKING
                
                if (item == POISON_PILL) {
                    // Shutdown signal
                    propagatePoisonPills();
                    break;
                }
                
                if (item instanceof FlushMarker) {
                    // Flush signal
                    propagateFlushMarker((FlushMarker) item);
                    continue;
                }
                
                if (item instanceof JSONEntityElastic) {
                    // Distribuir round-robin
                    BlockingQueue<Object> targetQueue = 
                        outputQueues.get(currentWriterIndex);
                    targetQueue.put(item);
                    currentWriterIndex = (currentWriterIndex + 1) % outputQueues.size();
                    documentsConsumed.incrementAndGet();
                }
                
            } catch (InterruptedException e) {
                break;
            }
        }
    }
}
```

### Fase 3: Escritura a Elasticsearch (Writer Threads)

**Elasticsearch Writer (Bulk Indexing):**
```java
private class ElasticsearchWriter implements Runnable {
    private final BlockingQueue<Object> inputQueue;
    private final RestHighLevelClient client;
    private final List<JSONEntityElastic> batch = new ArrayList<>();
    private static final int BATCH_SIZE = 500;
    private static final long FLUSH_INTERVAL_MS = 5000;
    
    @Override
    public void run() {
        long lastFlushTime = System.currentTimeMillis();
        
        while (!shutdown || !inputQueue.isEmpty()) {
            try {
                Object item = inputQueue.poll(1, TimeUnit.SECONDS);
                
                if (item == POISON_PILL) break;
                
                if (item instanceof FlushMarker) {
                    flushBatch();
                    ((FlushMarker) item).latch.countDown();
                    continue;
                }
                
                if (item instanceof JSONEntityElastic) {
                    batch.add((JSONEntityElastic) item);
                    
                    // Flush si batch lleno o timeout
                    if (batch.size() >= BATCH_SIZE || 
                        System.currentTimeMillis() - lastFlushTime > FLUSH_INTERVAL_MS) {
                        flushBatch();
                        lastFlushTime = System.currentTimeMillis();
                    }
                }
                
            } catch (InterruptedException e) {
                break;
            }
        }
        
        // Flush final
        flushBatch();
    }
    
    private void flushBatch() {
        if (batch.isEmpty()) return;
        
        BulkRequest bulkRequest = new BulkRequest();
        for (JSONEntityElastic doc : batch) {
            IndexRequest indexRequest = new IndexRequest(indexName)
                .id(doc.getId())
                .source(jsonMapper.writeValueAsString(doc), XContentType.JSON);
            bulkRequest.add(indexRequest);
        }
        
        // Retry logic con backoff exponencial
        int retries = 0;
        while (retries < MAX_RETRIES) {
            try {
                BulkResponse response = client.bulk(bulkRequest, RequestOptions.DEFAULT);
                if (!response.hasFailures()) {
                    documentsIndexed.addAndGet(batch.size());
                    batch.clear();
                    break;
                }
                // Manejar failures parciales
                handlePartialFailures(response);
                break;
                
            } catch (IOException e) {
                retries++;
                long backoff = (long) Math.pow(2, retries) * 1000;
                Thread.sleep(Math.min(backoff, 30000));
            }
        }
    }
}
```

---

## 🎯 Características Avanzadas Elasticsearch

### 1. Preload de Datos (Evitar N+1 y Lazy Loading)

```java
private Entity preloadEntityData(Entity entity) {
    // Cargar tipo de entidad
    EntityType type = entityModelCache.getObjectById(
        EntityType.class, entity.getEntityTypeId());
    
    EntityIndexingConfig config = configsByEntityType.get(type.getName());
    
    // Pre-cargar field occurrences si necesario
    List<FieldIndexingConfig> fields = config.getFields();
    if (fields != null && !fields.isEmpty()) {
        entity.loadOcurrences(
            entityModelCache.getNamesByIdMap(FieldType.class));
    }
    
    // Pre-cargar TODAS las relaciones
    for (RelationIndexingConfig relConfig : config.getRelationMappings()) {
        Set<Relation> relations = entityDataService
            .getRelationsWithThisEntityAsMember(
                entity.getId(), 
                relConfig.getName(), 
                relConfig.isFromMember());
        
        // Forzar carga de entidades relacionadas
        for (Relation rel : relations) {
            Entity relatedEntity = rel.getRelatedEntity(entity.getId());
            if (relatedEntity != null) {
                relatedEntity.getId(); // Trigger load
            }
        }
    }
    
    return entity;
}
```

**Beneficios:**
- Elimina lazy loading exceptions en threads paralelos
- Reduce número de queries a BD (batch loading)
- Una transacción independiente carga TODO lo necesario

### 2. Construcción de Documento JSON

```java
private JSONEntityElastic buildJSONDocument(Entity entity) {
    JSONEntityElastic doc = new JSONEntityElastic();
    doc.setId(entity.getId().toString());
    
    EntityType type = entityModelCache.getObjectById(
        EntityType.class, entity.getEntityTypeId());
    EntityIndexingConfig config = configsByEntityType.get(type.getName());
    
    // Mapear campos
    for (FieldIndexingConfig fieldConfig : config.getFields()) {
        String fieldName = fieldConfig.getName();
        Collection<FieldOccurrence> occurrences = 
            entity.getFieldOccurrencesByFieldName(fieldName);
        
        if (fieldConfig.isMultivalued()) {
            doc.addField(fieldConfig.getTargetField(), 
                         occurrences.stream()
                             .map(FieldOccurrence::getValue)
                             .collect(Collectors.toList()));
        } else if (!occurrences.isEmpty()) {
            doc.addField(fieldConfig.getTargetField(), 
                         occurrences.iterator().next().getValue());
        }
    }
    
    // Mapear relaciones como nested objects
    for (RelationIndexingConfig relConfig : config.getRelationMappings()) {
        Set<Relation> relations = entityDataService
            .getRelationsWithThisEntityAsMember(...);
        
        List<Map<String, Object>> nestedDocs = new ArrayList<>();
        for (Relation rel : relations) {
            Map<String, Object> nestedDoc = new HashMap<>();
            Entity relatedEntity = rel.getRelatedEntity(entity.getId());
            
            // Agregar campos de la entidad relacionada
            nestedDoc.put("id", relatedEntity.getId().toString());
            nestedDoc.put("type", relatedEntity.getEntityType().getName());
            
            // Agregar campos de la relación
            for (FieldIndexingConfig relField : relConfig.getFields()) {
                // ... mapear campos
            }
            
            nestedDocs.add(nestedDoc);
        }
        
        doc.addField(relConfig.getTargetField(), nestedDocs);
    }
    
    return doc;
}
```

### 3. Bulk Indexing Optimization

**Estrategia de Batching:**
- **Tamaño de batch:** 500 documentos (configurable)
- **Timeout:** 5 segundos (flush automático)
- **Triggers:** Batch lleno O timeout alcanzado

**Ventajas:**
- Reduce número de requests HTTP a Elasticsearch
- Aprovecha bulk API para mejor throughput
- Balancea latencia vs throughput

### 4. Retry Logic con Backoff Exponencial

```java
int retries = 0;
while (retries < MAX_RETRIES) {
    try {
        BulkResponse response = client.bulk(bulkRequest, RequestOptions.DEFAULT);
        if (!response.hasFailures()) {
            break; // Success
        }
        handlePartialFailures(response);
        break;
    } catch (IOException e) {
        retries++;
        long backoff = (long) Math.pow(2, retries) * 1000; // Exponencial
        Thread.sleep(Math.min(backoff, 30000)); // Max 30s
    }
}
```

**Backoff:**
- Retry 1: 2 segundos
- Retry 2: 4 segundos
- Retry 3: 8 segundos
- ...
- Retry 10: 30 segundos (cap)

---

---

## 📊 Mecanismos de Control de Concurrencia en Elasticsearch

### 1. Semaphore - Backpressure Control

**Configuración:**
```java
private Semaphore concurrentTasksSemaphore = new Semaphore(maxConcurrentTasks);
// maxConcurrentTasks = indexingThreads * 2
```

**Comportamiento:**
- Limita el número de tareas de indexación concurrentes ejecutándose simultáneamente
- Si no hay permisos disponibles, `acquire()` bloquea el thread hasta que se libere uno
- Evita saturación de base de datos PostgreSQL y memoria JVM
- Ejemplo con 8 cores: permite max 16 tareas concurrentes

**Flujo de Ejecución:**
```
Thread 1 → acquire() ✓ (permit 1/16) → load entity → create JSON → release()
Thread 2 → acquire() ✓ (permit 2/16) → load entity → create JSON → release()
...
Thread 17 → acquire() ⏸ BLOCKED (no permits) → esperando...
Thread 1 → release() → Thread 17 unblocked ✓ → continúa
```

**Beneficio en PostgreSQL:**
- Previene connection pool exhaustion
- Evita timeouts por saturación de transacciones concurrentes
- Controla memoria usada por entidades cargadas en paralelo

### 2. Phaser - Sincronización de Fases

**Propósito:**
- Rastrear cuántos productores (indexing threads) están activos
- Sincronizar operación `flush()` para garantizar que todos los documentos se procesen

**Operaciones Clave:**
```java
// Al iniciar indexación de una entidad
activeIndexingPhaser.register();  // Incrementa contador de tareas activas

// Al terminar procesamiento
activeIndexingPhaser.arriveAndDeregister();  // Decrementa contador

// En flush() - esperar a que TODOS los producers terminen
activeIndexingPhaser.arriveAndAwaitAdvance();
```

**Flujo de Flush:**
```
1. User llama indexer.flush()
2. Phaser espera: 5 tareas activas → espera...
3. Tarea 1 termina → 4 activas → espera...
4. Tarea 2 termina → 3 activas → espera...
5. Tarea 5 termina → 0 activas → CONTINÚA
6. Envía FlushMarker a writers
7. Espera confirmación de todos los writers
8. Retorna (flush completo)
```

### 3. BlockingQueue - Comunicación Thread-Safe

**Colas Utilizadas:**
```java
private BlockingQueue<Object> documentBuffer = new LinkedBlockingQueue<>(10000);
private List<BlockingQueue<Object>> outputQueues; // Una por cada Elasticsearch writer (2-6)
```

**Ventajas del Modelo Producer-Consumer:**
- **Thread-safe automático:** No requiere `synchronized` manual
- **Blocking operations:** `put()` bloquea si cola llena, `take()` bloquea si vacía
- **Desacoplamiento:** Productores y consumidores operan a velocidades independientes
- **Buffer intermedio:** Absorbe picos de velocidad entre BD y Elasticsearch

**Ejemplo de Flujo:**
```
Producer Thread 1 → documentBuffer.put(doc1) → Buffer: [doc1]
Producer Thread 2 → documentBuffer.put(doc2) → Buffer: [doc1, doc2]
Distributor Thread → documentBuffer.take() → obtiene doc1 → Buffer: [doc2]
Distributor → outputQueues[0].put(doc1) → Writer 0 recibe doc1
Distributor → documentBuffer.take() → obtiene doc2 → Buffer: []
Distributor → outputQueues[1].put(doc2) → Writer 1 recibe doc2
```

**Capacidad y Comportamiento:**
- **Buffer principal:** 10,000 documentos JSON
- **Output queues:** Ilimitadas (LinkedBlockingQueue sin capacidad)
- **Backpressure:** Si buffer lleno, producers bloquean en `put()`

---

## 📊 Métricas y Monitoreo

### Contadores Atómicos (Thread-Safe)

```java
private final AtomicLong documentsProduced = new AtomicLong(0);
private final AtomicLong documentsConsumed = new AtomicLong(0);
private final AtomicLong documentsIndexed = new AtomicLong(0);
```

**¿Por qué AtomicLong?**
- Operaciones thread-safe sin `synchronized`
- Método `incrementAndGet()` es atómico
- Mejor performance que sincronización explícita
- Lectura consistente desde múltiples threads

### Estadísticas Reportadas

**Elasticsearch Indexing Stats:**
- **Documentos producidos:** Total de documentos JSON creados
- **Documentos consumidos:** Total procesados por distributor
- **Documentos indexados:** Total enviados a Elasticsearch (confirmados)
- **Buffer usage:** `documentBuffer.size() / 10000 * 100%`
- **Active tasks:** Tareas de indexación en progreso
- **Memory usage:** Heap JVM utilizado/disponible
- **Bulk operations:** Número de bulk requests enviados
- **Bulk failures:** Documentos que fallaron en indexación

### Logging de Progreso

```java
logger.info("[ELASTIC INDEXING STATUS] " +
    "Buffer: {}/{} ({}%). " +
    "Active Tasks: {}. " +
    "Slots: {}/{}. " +
    "Docs: Produced:{}, Consumed:{}, Indexed:{} ({}%). " +
    "Bulk Ops: {} (Failures: {}). " +
    "Memory: {}MB/{}MB",
    bufferSize, bufferCapacity, bufferPercentage,
    activeTasks,
    availableSlots, maxSlots,
    produced, consumed, indexed, indexedPercentage,
    bulkOps, bulkFailures,
    usedMemory, maxMemory);
```

---

## ⚡ Optimizaciones de Performance

### 1. Transacciones Independientes (REQUIRES_NEW)

**Configuración:**
```java
DefaultTransactionDefinition def = new DefaultTransactionDefinition();
def.setPropagationBehavior(TransactionDefinition.PROPAGATION_REQUIRES_NEW);
def.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
def.setTimeout(300); // 5 minutos
```

**Ventajas:**
- Cada thread tiene su propia transacción PostgreSQL
- No hay bloqueos entre threads
- Rollback de un thread no afecta otros
- Permite verdadero procesamiento paralelo

### 2. Preload de Relaciones

**Estrategia:**
- Cargar TODAS las relaciones en la transacción inicial
- Evitar lazy loading en procesamiento posterior
- Trigger de Hibernate para forzar carga

**Resultado:**
- Elimina N+1 queries
- Una transacción carga todo lo necesario
- No hay acceso a BD en fase de construcción de JSON

### 3. Bulk API de Elasticsearch

**Ventajas:**
```
Operación individual: 500 docs × 1 request/doc = 500 HTTP requests
Bulk API:           500 docs × 1 bulk request = 1 HTTP request
Reducción:          99.8% menos overhead de red
```

**Configuración Óptima:**
- Batch size: 500 documentos
- Timeout: 5 segundos
- Flush si batch lleno O timeout alcanzado

### 4. Múltiples Elasticsearch Writers (2-6)

**Cálculo Automático:**
```java
int writers = Math.max(2, Math.min(indexingThreads, 6));
```

**Ejemplo con diferentes CPUs:**
- **2 cores:** 2 writers (mínimo garantizado)
- **4 cores:** 4 writers
- **8 cores:** 6 writers (cap máximo)
- **16 cores:** 6 writers (cap máximo)

**¿Por qué cap en 6?**
- Elasticsearch cluster típico: 3-5 nodos
- Más de 6 conexiones concurrentes no mejora throughput
- Evita saturación de conexiones HTTP
- Balance óptimo entre concurrencia y overhead

---

activeIndexingPhaser.arriveAndAwaitAdvance(); // Esperar todos
```

---

## 🚨 Manejo de Errores en Elasticsearch Indexing

### 1. Producers (Indexing Threads)

**Estrategia: Isolate Failures**
```java
try {
    // Procesar entidad con transacción independiente
    Entity fullyLoadedEntity = preloadEntityData(freshEntity);
    JSONEntityElastic jsonDoc = buildJSONDocument(fullyLoadedEntity);
    documentBuffer.put(jsonDoc);
    transactionManager.commit(status);
    
} catch (Exception e) {
    transactionManager.rollback(status);
    logger.error("Error processing entity {}: {}", entityId, e.getMessage(), e);
    // NO propaga - failure de una entidad NO detiene otras
    
} finally {
    // SIEMPRE liberar recursos
    concurrentTasksSemaphore.release();
    activeIndexingPhaser.arriveAndDeregister();
}
```

**Beneficios:**
- Error en entity X no afecta entity Y
- Transacciones independientes permiten rollback aislado
- Semaphore y Phaser se liberan correctamente
- Log detallado para debugging

### 2. Distributor Thread

**Estrategia: Resilient Distribution**
```java
try {
    Object item = documentBuffer.take(); // BLOCKING
    
    if (item == POISON_PILL) {
        propagatePoisonPills(); // Shutdown graceful
        break;
    }
    
    if (item instanceof FlushMarker) {
        propagateFlushMarker((FlushMarker) item);
        continue;
    }
    
    // Distribuir round-robin
    BlockingQueue<Object> targetQueue = outputQueues.get(currentWriterIndex);
    targetQueue.put(item);
    
} catch (InterruptedException e) {
    logger.warn("Distributor interrupted", e);
    Thread.currentThread().interrupt();
    break;
    
} catch (Exception e) {
    logger.error("Unexpected error in distributor", e);
    // Continúa procesando - no detiene pipeline
}
```

### 3. Elasticsearch Writers

**Estrategia: Retry con Backoff Exponencial**
```java
private void flushBatch() {
    if (batch.isEmpty()) return;
    
    BulkRequest bulkRequest = buildBulkRequest(batch);
    int retries = 0;
    
    while (retries < MAX_RETRIES) {
        try {
            BulkResponse response = client.bulk(bulkRequest, RequestOptions.DEFAULT);
            
            if (!response.hasFailures()) {
                // SUCCESS
                documentsIndexed.addAndGet(batch.size());
                batch.clear();
                return;
            }
            
            // Partial failures
            handlePartialFailures(response);
            return;
            
        } catch (IOException e) {
            retries++;
            logger.warn("Bulk indexing failed (attempt {}/{}): {}", 
                       retries, MAX_RETRIES, e.getMessage());
            
            if (retries >= MAX_RETRIES) {
                logger.error("Max retries reached. {} documents lost", batch.size());
                batch.clear(); // Evitar loop infinito
                return;
            }
            
            // Backoff exponencial: 2^retries segundos (max 30s)
            long backoffMs = (long) Math.pow(2, retries) * 1000;
            long sleepTime = Math.min(backoffMs, 30000);
            
            try {
                Thread.sleep(sleepTime);
            } catch (InterruptedException ie) {
                Thread.currentThread().interrupt();
                return;
            }
        }
    }
}

private void handlePartialFailures(BulkResponse response) {
    List<JSONEntityElastic> failedDocs = new ArrayList<>();
    
    for (BulkItemResponse itemResponse : response.getItems()) {
        if (itemResponse.isFailed()) {
            BulkItemResponse.Failure failure = itemResponse.getFailure();
            logger.error("Document {} failed: {}", 
                        itemResponse.getId(), 
                        failure.getMessage());
            
            // Guardar para retry selectivo
            failedDocs.add(batch.get(itemResponse.getItemId()));
        }
    }
    
    // Actualizar contadores
    int successful = batch.size() - failedDocs.size();
    documentsIndexed.addAndGet(successful);
    
    // Retry solo los que fallaron
    batch.clear();
    batch.addAll(failedDocs);
}
```

**Backoff Progresivo:**
- Retry 1: 2 segundos
- Retry 2: 4 segundos
- Retry 3: 8 segundos
- Retry 4: 16 segundos
- Retry 5+: 30 segundos (cap)

### 4. Graceful Shutdown

```java
@Override
public void close() {
    logger.info("Initiating graceful shutdown...");
    shutdown = true;
    
    // 1. Detener aceptación de nuevas tareas
    indexingExecutor.shutdown();
    
    // 2. Esperar a que producers terminen
    try {
        if (!indexingExecutor.awaitTermination(60, TimeUnit.SECONDS)) {
            logger.warn("Indexing executor did not terminate in time. Forcing shutdown...");
            indexingExecutor.shutdownNow();
        }
    } catch (InterruptedException e) {
        indexingExecutor.shutdownNow();
        Thread.currentThread().interrupt();
    }
    
    // 3. Enviar POISON_PILL para terminar pipeline
    try {
        documentBuffer.put(POISON_PILL);
    } catch (InterruptedException e) {
        Thread.currentThread().interrupt();
    }
    
    // 4. Esperar distributor y writers
    if (distributorThread != null) {
        distributorThread.join(30000); // 30 segundos timeout
    }
    
    for (Thread writerThread : writerThreads) {
        writerThread.join(30000);
    }
    
    // 5. Cerrar cliente Elasticsearch
    try {
        elasticClient.close();
    } catch (IOException e) {
        logger.error("Error closing Elasticsearch client", e);
    }
    
    logger.info("Shutdown complete. Final stats: " +
                "Produced:{}, Indexed:{}", 
                documentsProduced.get(), 
                documentsIndexed.get());
}
```

---

## 📈 Escalabilidad y Tunning

### Configuración Auto-Ajustable

**Detección Automática de Recursos:**
```java
// Threads de indexación = CPU cores disponibles
int indexingThreads = Runtime.getRuntime().availableProcessors();

// Max tareas concurrentes = 2x threads (backpressure control)
int maxConcurrentTasks = indexingThreads * 2;

// Elasticsearch writers = 2-6 (óptimo para clusters típicos)
int elasticWriterThreads = Math.max(2, Math.min(indexingThreads, 6));
```

**Override Manual (application.properties):**
```properties
# Indexing threads (default: auto)
indexer.threads=16

# Elasticsearch writers (default: auto 2-6)
elastic.indexer.writer.threads=4

# Buffer size (default: 10000)
indexer.buffer.size=20000

# Bulk batch size (default: 500)
elastic.bulk.batch.size=1000

# Bulk flush interval ms (default: 5000)
elastic.bulk.flush.interval=3000
```

### Adaptación por Workload

**Máquinas Pequeñas (4 cores):**
```
Indexing Threads:      4
Max Concurrent Tasks:  8
Document Buffer:       10,000
Elasticsearch Writers: 2 (mínimo)
Bulk Batch Size:       500
Throughput Estimado:   ~500-1000 docs/seg
```

**Máquinas Medianas (8 cores):**
```
Indexing Threads:      8
Max Concurrent Tasks:  16
Document Buffer:       10,000
Elasticsearch Writers: 6 (óptimo)
Bulk Batch Size:       500
Throughput Estimado:   ~2000-4000 docs/seg
```

**Máquinas Grandes (32 cores):**
```
Indexing Threads:      32
Max Concurrent Tasks:  64
Document Buffer:       20,000 (ajustado)
Elasticsearch Writers: 6 (cap)
Bulk Batch Size:       1000 (ajustado)
Throughput Estimado:   ~8000-15000 docs/seg
```

### Tunning por Bottleneck

**Bottleneck: PostgreSQL (Connection Pool)**
```properties
# Aumentar connection pool
spring.datasource.hikari.maximum-pool-size=40

# Reducir concurrent tasks para no saturar BD
indexer.max.concurrent.tasks=20
```

**Bottleneck: Elasticsearch (Network/Cluster)**
```properties
# Aumentar bulk batch size (menos requests)
elastic.bulk.batch.size=1000

# Aumentar writers si cluster es grande
elastic.indexer.writer.threads=8

# Ajustar timeout de bulk requests
elastic.bulk.timeout.seconds=60
```

**Bottleneck: Memoria JVM**
```properties
# Reducir buffer size
indexer.buffer.size=5000

# Reducir concurrent tasks
indexer.max.concurrent.tasks=10

# Flush más frecuente
elastic.bulk.flush.interval=2000
```

**Bottleneck: CPU**
```properties
# Reducir indexing threads
indexer.threads=4

# Reducir concurrent tasks
indexer.max.concurrent.tasks=8
```

---
- 32 indexing threads
- 64 concurrent tasks max
- 6 Elasticsearch writers

### Configuración Externa

```properties
# application.properties
elastic.indexer.writer.threads=4  # Override auto-calculation
```

---

## 🎯 Conclusiones

### ✅ Fortalezas de la Arquitectura Elasticsearch

1. **Arquitectura Robusta y Eficiente:**
   - **Producer-Consumer pattern:** Separación clara entre carga de BD y escritura a Elasticsearch
   - **Pipeline de 3 capas:** Producción → Distribución → Escritura
   - **Desacoplamiento:** Cada capa opera a su propia velocidad sin bloquear otras
   - **Escalabilidad horizontal:** Auto-ajuste basado en CPU cores disponibles

2. **Control de Concurrencia Sofisticado:**
   - **Semaphore:** Backpressure control para evitar saturación de PostgreSQL
   - **Phaser:** Sincronización de fases para flush garantizado
   - **BlockingQueues:** Comunicación thread-safe sin sincronización manual
   - **AtomicLong:** Contadores thread-safe de alta performance

3. **Optimizaciones de Performance:**
   - **Preload de relaciones:** Elimina N+1 queries, una transacción carga TODO
   - **Transacciones independientes (REQUIRES_NEW):** No hay bloqueos entre threads, rollback aislado
   - **Bulk API de Elasticsearch:** 99.8% reducción de overhead de red (500 docs en 1 request)
   - **Round-robin distribution:** Distribución balanceada entre 2-6 Elasticsearch writers

4. **Observabilidad y Monitoreo:**
   - **Logging detallado:** Estado de buffers, tasks activas, throughput, memoria
   - **Métricas atómicas:** Documentos producidos/consumidos/indexados
   - **Bulk operation tracking:** Failures, retries, tiempos de respuesta
   - **Memory monitoring:** Alertas proactivas de uso de heap JVM

5. **Resiliencia y Manejo de Errores:**
   - **Isolation de fallos:** Error en entity X no afecta entity Y
   - **Retry con backoff exponencial:** Hasta 10 reintentos con delays progresivos
   - **Partial failure handling:** Reintenta solo los documentos que fallaron en bulk
   - **Graceful shutdown:** Cierre ordenado con flush completo de buffers

6. **Elasticidad y Auto-Tunning:**
   - **Auto-detección de recursos:** Threads = CPU cores, writers = 2-6 automático
   - **Configuración externa:** Override via application.properties
   - **Adaptación por workload:** 500-15000 docs/seg según hardware
   - **Múltiples puntos de tunning:** Buffer size, bulk batch, flush interval, etc.

### ⚠️ Consideraciones de Implementación

1. **Complejidad Arquitectónica:**
   - Código con múltiples niveles de threading y sincronización
   - Debugging requiere entender Producer-Consumer pattern
   - Curva de aprendizaje moderada-alta para nuevos desarrolladores
   - Recomendación: Documentación exhaustiva y logging detallado

2. **Consumo de Memoria:**
   - **Preload de entidades:** Puede consumir mucha memoria con entidades grandes/complejas
   - **Buffers en memoria:** documentBuffer (10k), outputQueues (6), cada uno con objetos JSON
   - **Concurrent tasks:** Hasta 2x CPU cores en memoria simultáneamente
   - **Mitigación:** Semaphore limita max concurrent, monitoring de heap JVM

3. **Dependencia de Configuración:**
   - **Muchos parámetros de tunning:** threads, buffer size, bulk size, flush interval, writers, etc.
   - **Valores óptimos varían:** Dependen de hardware, tamaño de entidades, Elasticsearch cluster
   - **Trial and error:** Requiere testing de carga para encontrar valores óptimos
   - **Recomendación:** Empezar con valores default auto-calculados, ajustar solo si hay bottlenecks

4. **Coordinación con PostgreSQL:**
   - **Connection pool:** Debe configurarse para soportar max concurrent tasks
   - **Lock contention:** Transacciones REQUIRES_NEW reducen pero no eliminan locks
   - **Recomendación:** Hikari pool size ≥ max concurrent tasks + 10%

5. **Coordinación con Elasticsearch:**
   - **Cluster size:** Writers óptimos dependen de número de nodos ES
   - **Network bandwidth:** Bulk size grande requiere buena conectividad
   - **Index refresh rate:** Puede causar latencia si es muy bajo
   - **Recomendación:** 2-6 writers es óptimo para clusters típicos de 3-5 nodos

### 🎓 Recomendaciones para Producción

**1. Monitoreo y Alertas:**
```properties
# Implementar métricas Prometheus
management.metrics.export.prometheus.enabled=true

# Alertas recomendadas:
- Buffer usage > 80% (backpressure alto)
- Active tasks near max (saturación)
- Memory usage > 85% (riesgo OOM)
- Bulk failures > 5% (problemas con ES)
- Indexing lag > 10 min (throughput bajo)
```

**2. Testing de Carga:**
```java
// Test scenarios
1. 10,000 entidades simples (1-5 relaciones) → baseline performance
2. 1,000 entidades complejas (50+ relaciones) → memory stress test
3. 100,000 entidades medianas (10-20 relaciones) → throughput test
4. Concurrent indexing + búsquedas → stress test completo
```

**3. Configuración Inicial Conservadora:**
```properties
# Empezar conservador, escalar según necesidad
indexer.threads=auto  # CPU cores
indexer.max.concurrent.tasks=auto  # 2x threads
elastic.indexer.writer.threads=auto  # 2-6
indexer.buffer.size=10000
elastic.bulk.batch.size=500
elastic.bulk.flush.interval=5000
```

**4. Tunning por Bottleneck Observado:**
- **BD lenta:** Aumentar connection pool, reducir concurrent tasks
- **Elasticsearch lento:** Aumentar bulk batch, aumentar writers (si cluster grande)
- **Memoria alta:** Reducir buffer size, reducir concurrent tasks
- **CPU alto:** Reducir indexing threads

### 📊 Integración con Flujo de Datos Completo

```
┌─────────────────────────────────────────────────────────────┐
│ FASE 1: CARGA (EntityDataService)                           │
│ - Single threaded                                           │
│ - Una TX por archivo XML                                    │
│ - Inserta en source_entity, source_relation                 │
│ - Marca dirty=true                                          │
│                                                              │
│ Comando: load_data --file=...                              │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ FASE 2: MERGE (SQL Function)                                │
│ - Batch processing (PostgreSQL)                             │
│ - Consolida source_entity → entity                          │
│ - Consolida source_relation → relation                      │
│ - Marca dirty=false                                         │
│                                                              │
│ Comando: merge_dirty_entities                               │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ FASE 3: INDEXACIÓN (JSONElasticEntityIndexerThreadedImpl)   │
│ - Multithreaded (CPU cores)                                 │
│ - Transacciones independientes (REQUIRES_NEW)               │
│ - Pipeline Producer-Consumer                                │
│ - Bulk indexing a Elasticsearch                             │
│                                                              │
│ Automático: Al guardar/actualizar entities                  │
│ Manual: reindex_all                                         │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ RESULTADO: Elasticsearch Cluster                            │
│ - Documentos JSON indexados                                 │
│ - Búsqueda full-text disponible                             │
│ - Nested objects (relaciones) navegables                    │
└─────────────────────────────────────────────────────────────┘
```

**Consistencia Arquitectónica:**
- **Carga:** Transaccional única (MANDATORY), single-threaded, dirty=true
- **Merge:** Batch SQL, consolida fuentes, dirty=false
- **Indexación:** Multithreaded (REQUIRES_NEW), paralelo, Elasticsearch

**Complementariedad:**
- Carga e indexación operan en fases separadas (no hay conflictos)
- Merge intermedio garantiza consolidación antes de indexar
- Cada fase optimizada para su workload específico

---

## 📚 Referencias Técnicas

**Patrones de Concurrencia:**
- Producer-Consumer Pattern: https://en.wikipedia.org/wiki/Producer%E2%80%93consumer_problem
- Pipeline Architecture: https://www.enterpriseintegrationpatterns.com/patterns/messaging/PipesAndFilters.html
- Phaser (Java Concurrency): https://docs.oracle.com/javase/8/docs/api/java/util/concurrent/Phaser.html
- Semaphore: https://docs.oracle.com/javase/8/docs/api/java/util/concurrent/Semaphore.html

**Elasticsearch Best Practices:**
- Bulk API: https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html
- Indexing Performance: https://www.elastic.co/guide/en/elasticsearch/reference/current/tune-for-indexing-speed.html
- Java High Level REST Client: https://www.elastic.co/guide/en/elasticsearch/client/java-rest/current/java-rest-high.html

**Spring Framework:**
- Transaction Management: https://docs.spring.io/spring-framework/docs/current/reference/html/data-access.html#transaction
- Transaction Propagation: https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/transaction/annotation/Propagation.html
- ExecutorService: https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/scheduling/concurrent/ThreadPoolTaskExecutor.html

---

## 🏁 Resumen Ejecutivo

El modelo de indexación multithreading para Elasticsearch implementa una arquitectura **Producer-Consumer de 3 capas** (Producción → Distribución → Escritura) con las siguientes características clave:

✅ **Escalabilidad automática:** Auto-ajuste basado en CPU cores (threads) y cluster Elasticsearch (2-6 writers)  
✅ **Performance óptima:** Bulk API reduce 99.8% overhead de red, preload elimina N+1 queries  
✅ **Resiliencia:** Retry exponencial, partial failure handling, isolation de errores entre threads  
✅ **Control de flujo:** Semaphore evita saturación BD, BlockingQueues balancean velocidades  
✅ **Observabilidad:** Logging detallado, métricas atómicas, monitoreo de memoria y buffers  
✅ **Sincronización:** Phaser garantiza flush completo, POISON_PILL para shutdown graceful  

**Throughput estimado:** 500-15,000 docs/seg según hardware (4-32 cores)  
**Configuración recomendada:** Empezar con auto-detect, ajustar solo si hay bottlenecks observados  
**Integración:** Complementa flujo carga (single-thread) → merge (batch SQL) → indexación (multithread)

**Fecha de análisis:** 8 de enero de 2025  
**Autor:** Análisis técnico del sistema de indexación Elasticsearch  
**Enfoque:** Implementación multithreading para indexación en Elasticsearch  
**Contexto:** Post-refactoring de arquitectura transaccional
