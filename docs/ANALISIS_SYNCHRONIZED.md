# Análisis de Métodos `synchronized` en el Código
**Status:** historical (decision record / analysis; see notes) · **Last verified:** 2026-09-23

> **Actualización 2026-09-23:** las secciones §2 (`SemanticIdentifierCachedStore`) y §3 (`mergeEntityRelationData`) fueron **resueltas** en el código: el `synchronized` se eliminó de `SemanticIdentifierCachedStore` y el método vacío fue reemplazado por `EntityDataService.mergeDirtyEntitiesAndRelations()`. El resto del inventario sigue vigente como referencia.

## 📋 Resumen Ejecutivo

Después del refactoring transaccional, quedan **algunos métodos `synchronized`** en el código. Este documento analiza si tienen sentido y si deberían mantenerse o eliminarse.

---

## 🔍 Métodos `synchronized` Encontrados

### 1. **EntityLoadingStats** - ✅ **CORRECTOS - MANTENER**

#### Ubicación
`org.lareferencia.core.entity.services.EntityLoadingStats`

#### Métodos Afectados
```java
public synchronized void incrementSourceEntitiesLoaded()
public synchronized void incrementEntitiesCreated()
public synchronized void incrementEntitiesDuplicated()
public synchronized void incrementSourceRelationsLoaded()
public synchronized void incrementRelationsCreated()
public synchronized void incrementEntitiesLoaded()
public synchronized void addLoadTime(int loadTime)
public synchronized int getTotalEntitiesLoaded()
public synchronized int getTotalLoadTime()
public synchronized double getAverageLoadTime()
```

#### ¿Tienen Sentido?

**✅ SÍ - ABSOLUTAMENTE NECESARIOS**

#### Razón

1. **Objeto Compartido entre Hilos**
   - `EntityLoadingStats` es un objeto **compartido** que se pasa entre múltiples componentes
   - Se actualiza desde diferentes partes del código durante la carga

2. **Operaciones NO Atómicas**
   ```java
   this.sourceEntitiesLoaded++;  // NO es atómico en Java
   totalLoadTime += loadTime;    // NO es atómico en Java
   ```
   
   - El operador `++` es en realidad 3 operaciones:
     - LEER valor
     - INCREMENTAR
     - ESCRIBIR valor
   - Sin `synchronized`, dos hilos pueden leer el mismo valor y sobrescribirse

3. **Problema Sin `synchronized`**
   ```
   Thread 1: lee sourceEntitiesLoaded = 100
   Thread 2: lee sourceEntitiesLoaded = 100
   Thread 1: incrementa a 101, escribe
   Thread 2: incrementa a 101, escribe  ← PERDIÓ UN INCREMENTO!
   Resultado: sourceEntitiesLoaded = 101 (debería ser 102)
   ```

4. **Uso en Entorno Multihilo**
   - Aunque ahora solo hay un hilo de carga por archivo
   - El monitor (`EntityLoadingMonitorService`) puede acceder a estas stats concurrentemente
   - Puede haber carga de múltiples archivos en paralelo en el futuro

#### Alternativas Evaluadas

**Opción A: AtomicLong** (mejor opción si se quiere mejorar)
```java
private AtomicLong sourceEntitiesLoaded = new AtomicLong(0);

public void incrementSourceEntitiesLoaded() {
    this.sourceEntitiesLoaded.incrementAndGet();
}
```
- ✅ Mejor rendimiento que `synchronized`
- ✅ Lock-free
- ⚠️ Requiere cambiar el código

**Opción B: Mantener `synchronized`** (opción actual)
- ✅ Correcto y seguro
- ✅ Simple
- ⚠️ Menor rendimiento que AtomicLong (no significativo aquí)

#### Conclusión
**MANTENER `synchronized`** - Son correctos y necesarios para thread-safety.

---

### 2. **SemanticIdentifierCachedStore.loadOrCreate()** - ⚠️ **INNECESARIO - PUEDE ELIMINARSE**

#### Ubicación
`org.lareferencia.core.entity.services.SemanticIdentifierCachedStore`

#### Método Afectado
```java
public synchronized SemanticIdentifier loadOrCreate(String semanticIdentifier) {
    SemanticIdentifier created = new SemanticIdentifier(semanticIdentifier);
    
    SemanticIdentifier existing = this.get(created.getId());
    if (existing == null) {
        this.put(created.getId(), created);
        return created;
    } else {
        return existing;
    }
}
```

#### ¿Tiene Sentido?

**⚠️ INNECESARIO - El cache Caffeine ya es thread-safe**

#### Análisis

1. **Caffeine Cache es Thread-Safe**
   - `com.github.benmanes.caffeine.cache.Cache` es **totalmente thread-safe**
   - Documentación oficial: "All operations are thread-safe"
   - Usa ConcurrentHashMap internamente

2. **Operación `cache.get(key, mappingFunction)`**
   ```java
   cache.get(key, k -> {
       Optional<C> optObj = repository.findById(key);
       // ...
   });
   ```
   - Esta operación es **atómica**
   - Caffeine garantiza que el mappingFunction solo se ejecuta UNA vez
   - Si dos hilos piden la misma key, solo uno ejecuta el loader

3. **Operación `cache.put(key, value)`**
   - También es thread-safe
   - ConcurrentHashMap.put() es thread-safe

4. **Operación `cache.getIfPresent(key)`**
   - Thread-safe
   - Retorna null si no existe

#### El Problema del Patrón Check-Then-Act

Sin `synchronized`, el código tiene una condición de carrera:

```java
// Thread 1 y Thread 2 llaman con el mismo semanticIdentifier simultáneamente

Thread 1: existing = this.get(id);     // null
Thread 2: existing = this.get(id);     // null
Thread 1: if (existing == null) {      // true
Thread 2: if (existing == null) {      // true
Thread 1:     this.put(id, created);   // inserta
Thread 2:     this.put(id, created);   // inserta de nuevo ← DUPLICADO!
```

**PERO** este problema es **inofensivo** porque:

1. **put() está protegido internamente**
   ```java
   @Transactional(propagation = Propagation.MANDATORY)
   public void put(K key, C obj) {
       if (cache.getIfPresent(key) == null) {  // ← Segunda verificación
           repository.save(obj);
           cache.put(key, obj);
       }
   }
   ```
   - Hay una **segunda verificación** dentro de `put()`
   - Aunque dos hilos pasen el primer `if`, solo uno insertará

2. **Base de datos tiene constraint único**
   - La tabla de semantic_identifier tiene PRIMARY KEY en el ID
   - Si dos hilos intentan insertar, uno fallará con constraint violation
   - La transacción hará rollback automáticamente

3. **Caffeine.get() con loader es mejor**
   En lugar de:
   ```java
   public synchronized SemanticIdentifier loadOrCreate(String id) {
       SemanticIdentifier existing = this.get(id);
       if (existing == null) {
           this.put(id, created);
       }
       return existing;
   }
   ```
   
   Mejor usar:
   ```java
   public SemanticIdentifier loadOrCreate(String id) {
       SemanticIdentifier created = new SemanticIdentifier(id);
       return cache.get(created.getId(), key -> {
           // Este código se ejecuta ATÓMICAMENTE
           // Solo UNA vez, aunque múltiples hilos llamen
           this.put(key, created);
           return created;
       });
   }
   ```

#### Contexto Actual

**En la arquitectura actual:**
- ✅ Solo **un hilo** procesa un archivo XML a la vez
- ✅ Cada archivo se procesa en **una transacción**
- ✅ No hay concurrencia dentro de un archivo

**Por lo tanto:**
- El `synchronized` es **innecesario** en el contexto actual
- NO causa problemas de rendimiento significativos
- Pero tampoco aporta valor

#### Conclusión

**PUEDE ELIMINARSE** - Es innecesario porque:
1. Caffeine cache es thread-safe
2. Solo hay un hilo procesando por transacción
3. La segunda verificación en `put()` protege contra duplicados
4. Constraints de BD previenen duplicados en persistencia

**PERO** puede mantenerse sin problemas si:
- Se planea procesar archivos en paralelo en el futuro
- Se prefiere ser conservador con thread-safety

---

### 3. **EntityDataService.mergeEntityRelationData()** - ❌ **INÚTIL - ELIMINAR**

#### Ubicación
`org.lareferencia.core.entity.services.EntityDataService`

#### Método Afectado
```java
@Transactional
public synchronized void mergeEntityRelationData() {
    //entityRepository.mergeEntiyRelationData();
    // TODO: delete this method
}
```

#### ¿Tiene Sentido?

**❌ NO - MÉTODO VACÍO MARCADO PARA ELIMINACIÓN**

#### Análisis

1. **El método NO hace nada**
   - La única línea está comentada
   - Tiene un TODO: delete this method

2. **Uso Actual**
   ```java
   // EntityDataCommands.java
   erService.mergeEntityRelationData();
   ```
   - Se llama después de procesar archivos
   - Pero no ejecuta ninguna lógica

3. **Historia del Método**
   - Probablemente hacía algún merge o consolidación antes
   - Ya no es necesario en la arquitectura actual
   - Se dejó como placeholder pero nunca se eliminó

#### Conclusión

**ELIMINAR** - Es un método vacío que debería haberse eliminado hace tiempo.

---

### 4. **EntityModelCache.initialize()** - ✅ **CORRECTO - MANTENER**

#### Ubicación
`org.lareferencia.core.entity.services.EntityModelCache`

#### Código
```java
synchronized (initLock) {
    // Inicialización del cache
}
```

#### ¿Tiene Sentido?

**✅ SÍ - PATRÓN LAZY INITIALIZATION THREAD-SAFE**

#### Razón

1. **Double-Checked Locking Pattern**
   - Patrón estándar para inicialización lazy thread-safe
   - El lock garantiza que solo un hilo inicialice el cache

2. **Uso de Object Lock**
   - Usa un objeto dedicado `initLock` (mejor práctica)
   - No bloquea toda la instancia

#### Conclusión

**MANTENER** - Es el patrón correcto para lazy initialization thread-safe.

---

### 5. **EntityIndexerTDB2ThreadedImpl** - ✅ **CORRECTOS - MANTENER**

#### Ubicación
`org.lareferencia.core.entity.indexing.vivo.EntityIndexerTDB2ThreadedImpl`

#### Código
```java
synchronized (flushLock) { ... }
synchronized (tdbWriteLock) { ... }
synchronized (writeLock) { ... }
```

#### ¿Tienen Sentido?

**✅ SÍ - NECESARIOS PARA COORDINACIÓN DE HILOS**

#### Razón

1. **Componente Explícitamente Multihilo**
   - El nombre dice "Threaded" - diseñado para concurrencia
   - Múltiples hilos de indexación

2. **Coordinación de Escrituras**
   - TDB2 (Apache Jena) requiere sincronización para escrituras
   - Los locks coordinan acceso concurrente

3. **Locks Dedicados**
   - Usa objetos lock específicos (buena práctica)
   - `flushLock`, `tdbWriteLock`, `writeLock` - cada uno con propósito

#### Conclusión

**MANTENER** - Son necesarios para coordinar hilos de indexación.

---

## 📊 Resumen de Recomendaciones

| Componente | Método/Lock | Necesario | Recomendación |
|------------|-------------|-----------|---------------|
| **EntityLoadingStats** | Todos los métodos | ✅ Sí | **MANTENER** (o mejorar con AtomicLong) |
| **SemanticIdentifierCachedStore** | loadOrCreate() | ⚠️ No | **PUEDE ELIMINARSE** (pero inofensivo) |
| **EntityDataService** | mergeEntityRelationData() | ❌ No | **ELIMINAR MÉTODO COMPLETO** |
| **EntityModelCache** | initLock | ✅ Sí | **MANTENER** |
| **EntityIndexerTDB2ThreadedImpl** | Varios locks | ✅ Sí | **MANTENER** |

---

## 🎯 Análisis de Impacto por Contexto

### Contexto Actual: Procesamiento de UN Archivo a la Vez

En la arquitectura actual:
```
load_xml_file(file1) [Hilo A]
  └─> parseAndPersist() [TX1]
       └─> persistEntityRelationData()
            └─> semanticIdStore.loadOrCreate() [synchronized]
                └─> Ejecuta en Hilo A
```

**Análisis:**
- ✅ No hay concurrencia real en `loadOrCreate()`
- ✅ El `synchronized` no hace nada útil
- ✅ PERO tampoco causa problemas

### Contexto Futuro: Procesamiento Paralelo de Archivos

Si en el futuro se implementa carga paralela:
```
load_xml_file(file1) [Hilo A] ─┐
                                ├─> semanticIdStore.loadOrCreate("orcid:123")
load_xml_file(file2) [Hilo B] ─┘
```

**Análisis:**
- ⚠️ El `synchronized` protegería contra race conditions
- ✅ Caffeine cache ya es thread-safe, pero...
- ⚠️ El patrón check-then-act podría crear duplicados
- ✅ La segunda verificación en `put()` y constraints de BD protegen

**Conclusión:** Aunque ayuda, no es estrictamente necesario.

---

## 💡 Recomendaciones Detalladas

### Acción Inmediata (Prioridad Alta)

1. **Eliminar `mergeEntityRelationData()`**
   ```java
   // ELIMINAR este método completamente
   @Transactional
   public synchronized void mergeEntityRelationData() {
       //entityRepository.mergeEntiyRelationData();
       // TODO: delete this method
   }
   ```
   
   Y su llamada en `EntityDataCommands.java`:
   ```java
   // ELIMINAR estas líneas
   logger.info("Merging entity-relation data...");
   erService.mergeEntityRelationData();
   ```

### Acción Opcional (Mejora de Rendimiento)

2. **Mejorar `EntityLoadingStats` con AtomicLong**
   
   Cambiar de:
   ```java
   Long sourceEntitiesLoaded = 0L;
   
   public synchronized void incrementSourceEntitiesLoaded() {
       this.sourceEntitiesLoaded++;
   }
   ```
   
   A:
   ```java
   private final AtomicLong sourceEntitiesLoaded = new AtomicLong(0);
   
   public void incrementSourceEntitiesLoaded() {
       this.sourceEntitiesLoaded.incrementAndGet();
   }
   
   public Long getSourceEntitiesLoaded() {
       return this.sourceEntitiesLoaded.get();
   }
   ```
   
   **Beneficios:**
   - ✅ Mejor rendimiento (lock-free)
   - ✅ Más escalable para alta concurrencia
   - ✅ Menos contención de locks

### Acción Opcional (Simplificación)

3. **Eliminar `synchronized` de `SemanticIdentifierCachedStore.loadOrCreate()`**
   
   Es seguro eliminarlo porque:
   - Caffeine cache es thread-safe
   - Solo un hilo por transacción en arquitectura actual
   - Segunda verificación en `put()` protege contra duplicados
   
   **PERO** puede mantenerse como "defensive programming" sin problemas.

### Mantener Sin Cambios

4. **EntityModelCache.initLock** - Correcto
5. **EntityIndexerTDB2ThreadedImpl locks** - Necesarios

---

## 🔍 Prueba de Thread-Safety

### Test Conceptual para SemanticIdentifierCachedStore

```java
@Test
public void test_concurrent_loadOrCreate() throws InterruptedException {
    // Simular 100 hilos intentando crear el mismo semantic ID
    ExecutorService executor = Executors.newFixedThreadPool(100);
    CountDownLatch latch = new CountDownLatch(100);
    
    String semanticId = "orcid:0000-0001-2345-6789";
    Set<SemanticIdentifier> results = ConcurrentHashMap.newKeySet();
    
    for (int i = 0; i < 100; i++) {
        executor.submit(() -> {
            SemanticIdentifier result = store.loadOrCreate(semanticId);
            results.add(result);
            latch.countDown();
        });
    }
    
    latch.await();
    executor.shutdown();
    
    // TODOS los hilos deberían obtener la MISMA instancia
    assertEquals(1, results.size());
    
    // Solo debería haber UNA entrada en la BD
    long count = semanticIdRepository.count();
    assertEquals(1, count);
}
```

**Resultado Esperado:**
- ✅ Con `synchronized`: Pasa ✓
- ✅ Sin `synchronized` + Caffeine: Pasa ✓ (cache es thread-safe)
- ⚠️ Sin `synchronized` + sin segunda verificación en put(): Puede fallar

---

## 📚 Principios de Thread-Safety Aplicados

### 1. ✅ Evitar `synchronized` sobre Métodos Transaccionales
- ❌ ANTES: `synchronized` + `@Transactional` = riesgo de deadlock
- ✅ AHORA: Eliminado en métodos transaccionales de negocio

### 2. ✅ Usar `synchronized` Solo para Datos en Memoria
- ✅ `EntityLoadingStats`: Variables en memoria (counters)
- ❌ `ProvenanceStore`: Operaciones de BD (ELIMINADO)

### 3. ✅ Preferir Estructuras Thread-Safe
- ✅ Caffeine Cache: Thread-safe por diseño
- ✅ ConcurrentHashMap: Thread-safe
- ⚠️ Long++: NO es thread-safe (necesita synchronized o AtomicLong)

### 4. ✅ Evitar Check-Then-Act sin Protección
- ❌ MALO:
  ```java
  if (cache.get(key) == null) {  // Check
      cache.put(key, value);      // Act
  }
  ```
- ✅ BUENO:
  ```java
  cache.get(key, k -> {
      // Función loader es atómica
      return createValue(k);
  });
  ```

---

## 🎯 Conclusión Final

### Métodos `synchronized` que TIENEN SENTIDO:

1. ✅ **EntityLoadingStats.increment*()** - Necesarios para thread-safety de contadores
2. ✅ **EntityModelCache.initLock** - Patrón correcto para lazy init
3. ✅ **EntityIndexerTDB2ThreadedImpl locks** - Necesarios para coordinación multihilo

### Métodos `synchronized` INNECESARIOS:

1. ⚠️ **SemanticIdentifierCachedStore.loadOrCreate()** - Caffeine ya es thread-safe, puede eliminarse
2. ❌ **EntityDataService.mergeEntityRelationData()** - Método vacío, debe eliminarse

### Impacto del Refactoring Transaccional:

El refactoring **eliminó correctamente** los `synchronized` problemáticos:
- ❌ ProvenanceStore.loadOrCreate() - ELIMINADO ✓
- ❌ FieldOcurrenceCachedStore.loadOrCreate() - ELIMINADO ✓
- ❌ EntityDataService.findOrCreateFinalEntity() - ELIMINADO ✓
- ❌ ConcurrentCachedStore.put() - ELIMINADO ✓

Estos eran los que causaban problemas porque:
- Se combinaban con `@Transactional`
- Ejecutaban operaciones de base de datos
- Causaban deadlocks potenciales

Los que quedaron son **inofensivos** o **necesarios** y no causan problemas.

---

**Análisis realizado el:** 7 de noviembre de 2025  
**Autor:** Revisión post-refactoring transaccional
