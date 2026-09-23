# Arquitectura Transaccional - Sistema de Carga de Entidades
**Status:** historical (decision record / analysis; see notes) · **Last verified:** 2026-09-23

> **Nota 2026-09-23:** la sección "Configuración Recomendada" (`batch_size=20`, etc.) es una recomendación de diseño: esos valores no están aplicados en ningún `application.properties` del repositorio.

## 📋 Descripción General

Este documento describe cómo funcionan las transacciones en el proceso de carga de entidades después del refactoring del 7 de noviembre de 2025.

---

## 🏗️ Arquitectura en Capas

```
┌─────────────────────────────────────────────────────────────────┐
│                    CAPA DE COMANDO (Shell)                       │
│                  Sin transacción - Orquestación                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CAPA DE SERVICIO                              │
│              @Transactional(REQUIRED) - TX Única                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 CAPA DE LÓGICA DE NEGOCIO                        │
│           @Transactional(MANDATORY) - Usa TX padre               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                  CAPA DE STORES/CACHES                           │
│           @Transactional(MANDATORY) - Usa TX padre               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 CAPA DE REPOSITORIOS JPA                         │
│                  Operaciones CRUD básicas                        │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔄 Flujo Completo de Transacción

### Nivel 1: Comando Shell (`EntityDataCommands`)

```java
// SIN @Transactional
public void load_xml_file(File file, Boolean dryRun) {
    InputStream input = new FileInputStream(file);
    Document doc = dBuilder.parse(input);
    
    // ┌─────────────────────────────────┐
    // │  INICIA TRANSACCIÓN AQUÍ (TX1)  │
    // └─────────────────────────────────┘
    EntityLoadingStats stats = erService.parseAndPersistEntityRelationDataFromXMLDocument(doc, dryRun);
    // ┌─────────────────────────────────┐
    // │    COMMIT AUTOMÁTICO AQUÍ       │
    // └─────────────────────────────────┘
}
```

**Responsabilidades:**
- 📄 Lectura de archivos XML del sistema de archivos
- 🔄 Iteración sobre múltiples archivos
- 📊 Reporte de estadísticas y errores
- ⚠️ Manejo de excepciones a nivel de archivo

**Estado Transaccional:** `NO TRANSACTIONAL`

---

### Nivel 2: Servicio Principal (`EntityDataService`)

#### 2.1. Método de Entry Point

```java
@Transactional(propagation = Propagation.REQUIRED)
public EntityLoadingStats parseAndPersistEntityRelationDataFromXMLDocument(
    Document document, Boolean dryRun) {
    
    // ┌────────────────────────────────────────┐
    // │ SI NO HAY TX: Crea nueva transacción   │
    // │ SI HAY TX: Usa la existente            │
    // │ EN ESTE CASO: Siempre crea TX1         │
    // └────────────────────────────────────────┘
    
    // Paso 1: Parse XML (SIN transacción - no accede a BD)
    XMLEntityRelationData erData = parseEntityRelationDataFromXmlDocumentNonTransactional(document);
    
    // Paso 2: Persistir (DENTRO de TX1)
    return persistEntityRelationData(erData, dryRun);
    
    // ┌────────────────────────────────────────┐
    // │ COMMIT automático si todo OK           │
    // │ ROLLBACK automático si hay Exception   │
    // └────────────────────────────────────────┘
}
```

**Propagation.REQUIRED:**
- ✅ Si **no existe** transacción → **Crea una nueva** (TX1)
- ✅ Si **existe** transacción → **La usa**
- 🎯 En nuestro caso: Siempre crea TX1 porque se llama sin transacción

---

#### 2.2. Método de Parseo XML

```java
// SIN @Transactional
public XMLEntityRelationData parseEntityRelationDataFromXmlDocumentNonTransactional(
    Document document) {
    
    // ┌────────────────────────────────────────┐
    // │ NO accede a base de datos              │
    // │ Solo parsea XML usando JAXB            │
    // │ NO necesita transacción                │
    // └────────────────────────────────────────┘
    
    JAXBContext context = JAXBContext.newInstance(erData.getClass());
    Unmarshaller unmarshaller = context.createUnmarshaller();
    erData = (XMLEntityRelationData) unmarshaller.unmarshal(document);
    erData.isConsistent(); // validación
    
    return erData;
}
```

**Estado Transaccional:** `NO TRANSACTIONAL`

**Razón:** No accede a la base de datos, solo operaciones en memoria

---

#### 2.3. Método de Persistencia Principal

```java
@Transactional(propagation = Propagation.MANDATORY)
public EntityLoadingStats persistEntityRelationData(
    XMLEntityRelationData data, Boolean dryRun) {
    
    // ┌────────────────────────────────────────┐
    // │ MANDATORY: REQUIERE transacción activa │
    // │ Si no hay TX: Lanza IllegalTransactionStateException │
    // │ En nuestro caso: Usa TX1 del método padre │
    // └────────────────────────────────────────┘
    
    // Todas las operaciones usan TX1
    // ...
}
```

**Propagation.MANDATORY:**
- ✅ **Requiere** que exista una transacción activa
- ❌ Si no hay transacción → Lanza `IllegalTransactionStateException`
- 🎯 Garantiza que siempre se ejecuta dentro de una transacción

---

### Nivel 3: Lógica de Persistencia Detallada

```java
@Transactional(propagation = Propagation.MANDATORY)
public EntityLoadingStats persistEntityRelationData(...) {
    
    // ════════════════════════════════════════════════════════
    // TODAS las operaciones siguientes usan TX1
    // ════════════════════════════════════════════════════════
    
    // ┌─── PASO 1: PROVENANCE ────────────────────────────┐
    // │ provenanceStore.loadOrCreate()                     │
    // │   @Transactional(MANDATORY) → Usa TX1             │
    // │   repository.save(provenance) → En TX1            │
    // └────────────────────────────────────────────────────┘
    Provenance provenance = provenanceStore.loadOrCreate(source, record);
    
    // ┌─── PASO 2: LOGICAL DELETE ────────────────────────┐
    // │ sourceEntityRepository.logicalDeleteByProvenanceId │
    // │   @Modifying query ejecutada en TX1               │
    // └────────────────────────────────────────────────────┘
    if (isUpdate) {
        sourceEntityRepository.logicalDeleteByProvenanceId(provenance.getId());
    }
    
    // ┌─── PASO 3: LOOP DE ENTIDADES ─────────────────────┐
    for (XMLEntityInstance xmlEntity : data.getEntities()) {
        
        // 3.1 Field Occurrences
        // ┌────────────────────────────────────────────────┐
        // │ addFieldOccurrenceFromXMLFieldInstance()       │
        // │   → fieldOcurrenceCachedStore.loadOrCreate()   │
        // │      → put() @Transactional(MANDATORY)         │
        // │         → repository.save() en TX1             │
        // └────────────────────────────────────────────────┘
        addFieldOccurrenceFromXMLFieldInstance(...);
        
        // 3.2 Semantic Identifiers
        // ┌────────────────────────────────────────────────┐
        // │ semanticIdentifierCachedStore.loadOrCreate()   │
        // │   → put() @Transactional(MANDATORY)            │
        // │      → repository.save() en TX1                │
        // └────────────────────────────────────────────────┘
        sourceEntity.addSemanticIdentifier(
            semanticIdentifierCachedStore.loadOrCreate(semanticId)
        );
        
        // 3.3 Find or Create Entity
        // ┌────────────────────────────────────────────────┐
        // │ findOrCreateFinalEntity()                      │
        // │   @Transactional(MANDATORY) → Usa TX1          │
        // │   entityRepository.save() en TX1               │
        // └────────────────────────────────────────────────┘
        FindOrCreateEntityResult result = findOrCreateFinalEntity(sourceEntity);
        
        // 3.4 Save Source Entity
        // ┌────────────────────────────────────────────────┐
        // │ sourceEntityRepository.save()                  │
        // │   Agrega a contexto de persistencia de TX1     │
        // │   NO hace flush inmediato                      │
        // └────────────────────────────────────────────────┘
        sourceEntityRepository.save(sourceEntity);
    }
    // └────────────────────────────────────────────────────┘
    
    // ┌─── PASO 4: LOOP DE RELACIONES ────────────────────┐
    for (XMLRelationInstance xmlRelation : data.getRelations()) {
        // Similar al loop de entidades
        sourceRelationRepository.save(sourceRelation);
    }
    // └────────────────────────────────────────────────────┘
    
    // ┌─── PASO 5: UPDATE PROVENANCE ─────────────────────┐
    // │ provenanceStore.setLastUpdate()                    │
    // │   @Transactional(MANDATORY) → Usa TX1             │
    // │   @Modifying query ejecutada en TX1               │
    // └────────────────────────────────────────────────────┘
    provenanceStore.setLastUpdate(provenance, lastUpdate);
    
    return stats;
    
    // ════════════════════════════════════════════════════════
    // AL SALIR DE ESTE MÉTODO:
    //   - Vuelve al método padre (parseAndPersist...)
    //   - TX1 sigue activa
    // ════════════════════════════════════════════════════════
}
```

---

### Nivel 4: Stores y Caches

#### 4.1. ProvenanceStore

```java
@Transactional(propagation = Propagation.MANDATORY)
public Provenance loadOrCreate(String source, String record) {
    
    // ┌────────────────────────────────────────┐
    // │ Usa TX1 del caller                     │
    // └────────────────────────────────────────┘
    
    Provenance createdProvenance = new Provenance(source, record);
    Optional<Provenance> optProvenance = repository.findById(createdProvenance.getId());
    
    if (optProvenance.isPresent())
        return optProvenance.get();
    else {
        // ┌────────────────────────────────────┐
        // │ save() agrega al contexto de TX1   │
        // │ NO hace flush inmediato            │
        // └────────────────────────────────────┘
        repository.save(createdProvenance);
        return createdProvenance;
    }
}

@Transactional(propagation = Propagation.MANDATORY)
public void setLastUpdate(Provenance provenance, LocalDateTime lastUpdate) {
    
    // ┌────────────────────────────────────────┐
    // │ @Modifying query en TX1                │
    // └────────────────────────────────────────┘
    repository.setLastUpdate(provenance.getId(), lastUpdate);
}
```

**Características:**
- ✅ Eliminado `synchronized` (no más bloqueos Java)
- ✅ Usa `save()` en lugar de `saveAndFlush()`
- ✅ Ambos métodos con `MANDATORY`

---

#### 4.2. ConcurrentCachedStore (Base para Semantic IDs y Field Occurrences)

```java
public C get(K key) {
    // ┌────────────────────────────────────────┐
    // │ Operación de lectura                   │
    // │ Puede ejecutar fuera de transacción    │
    // │ Si está en TX, usa esa transacción     │
    // └────────────────────────────────────────┘
    
    return cache.get(key, k -> {
        Optional<C> optObj = repository.findById(key);
        if (optObj.isPresent())
            return Hibernate.unproxy(optObj.get());
        else
            return null;
    });
}

@Transactional(readOnly = false, propagation = Propagation.MANDATORY)
public void put(K key, C obj) {
    
    // ┌────────────────────────────────────────┐
    // │ MANDATORY: Usa TX1 del caller          │
    // └────────────────────────────────────────┘
    
    if (cache.getIfPresent(key) == null) {
        if (!readOnly) {
            // ┌────────────────────────────────┐
            // │ save() agrega al contexto TX1  │
            // │ NO flush inmediato             │
            // └────────────────────────────────┘
            repository.save(obj);
            obj.markAsStored();
        }
        cache.put(key, obj);
    }
}
```

**Cambios Clave:**
- ❌ **Eliminado:** `REQUIRES_NEW` (ya no crea transacción nueva)
- ❌ **Eliminado:** `SERIALIZABLE` (ya no conflicto de aislamiento)
- ❌ **Eliminado:** `synchronized`
- ❌ **Eliminado:** `saveAndFlush()` → Ahora usa `save()`
- ✅ **Agregado:** `MANDATORY` (usa TX del caller)

---

#### 4.3. FieldOcurrenceCachedStore

```java
// SIN @Transactional
public FieldOccurrence loadOrCreate(FieldType type, IFieldValueInstance field) {
    
    // ┌────────────────────────────────────────┐
    // │ Crea el objeto en memoria              │
    // └────────────────────────────────────────┘
    FieldOccurrence createdFieldOccr = type.buildFieldOccurrence();
    
    // Configurar valores...
    createdFieldOccr.updateId();
    
    // ┌────────────────────────────────────────┐
    // │ Buscar en cache (puede leer de BD)     │
    // └────────────────────────────────────────┘
    FieldOccurrence existingFieldOccr = this.get(createdFieldOccr.getId());
    
    if (existingFieldOccr == null) {
        // ┌────────────────────────────────────┐
        // │ put() @Transactional(MANDATORY)    │
        // │   → Usa TX1 del caller             │
        // │   → save() en TX1                  │
        // └────────────────────────────────────┘
        this.put(createdFieldOccr.getId(), createdFieldOccr);
        return createdFieldOccr;
    } else {
        return existingFieldOccr;
    }
}
```

**Cambios Críticos:**
- ❌ **Eliminado:** `@Transactional(REQUIRES_NEW)` en loadOrCreate
- ❌ **Eliminado:** Gestión manual de transacciones (`PlatformTransactionManager`)
- ❌ **Eliminado:** `transactionManager.commit()` / `rollback()`
- ❌ **Eliminado:** `synchronized`
- ✅ Ahora todo corre en TX1 del caller

---

#### 4.4. SemanticIdentifierCachedStore

```java
// SIN @Transactional
public SemanticIdentifier loadOrCreate(String semanticIdentifier) {
    
    SemanticIdentifier created = new SemanticIdentifier(semanticIdentifier);
    SemanticIdentifier existing = this.get(created.getId());
    
    if (existing == null) {
        // ┌────────────────────────────────────┐
        // │ put() heredado de ConcurrentCachedStore │
        // │   @Transactional(MANDATORY)        │
        // │   Usa TX1                          │
        // └────────────────────────────────────┘
        this.put(created.getId(), created);
        return created;
    } else {
        return existing;
    }
}
```

**Hereda** el comportamiento de `ConcurrentCachedStore.put()`

---

#### 4.5. findOrCreateFinalEntity

```java
@Transactional(propagation = Propagation.MANDATORY)
public FindOrCreateEntityResult findOrCreateFinalEntity(SourceEntity sourceEntity) {
    
    // ┌────────────────────────────────────────┐
    // │ Usa TX1 del caller                     │
    // └────────────────────────────────────────┘
    
    // Buscar entidad existente
    Entity entity = entityRepository.findEntityWithSemanticIdentifiers(semanticIds);
    
    if (entity == null) {
        entity = new Entity(sourceEntity.getEntityType());
        entityAlreadyExists = false;
    }
    
    entity.setDirty(true);
    entity.addSemanticIdentifiers(semanticIdentifiers);
    
    // ┌────────────────────────────────────────┐
    // │ save() agrega al contexto de TX1       │
    // │ NO flush inmediato                     │
    // └────────────────────────────────────────┘
    entityRepository.save(entity);
    
    return new FindOrCreateEntityResult(entity, entityAlreadyExists);
}
```

**Cambios:**
- ❌ **Eliminado:** `synchronized`
- ❌ **Eliminado:** `saveAndFlush()` → Ahora `save()`
- ✅ **Agregado:** `@Transactional(MANDATORY)`

---

## 📊 Diagrama de Secuencia Temporal

```
Tiempo  │  Componente              │  Acción                          │  TX
───────────────────────────────────────────────────────────────────────────────
   0    │  EntityDataCommands      │  load_xml_file()                 │  -
   1    │  EntityDataService       │  parseAndPersist...()            │  ┌─ TX1 START
   2    │  EntityDataService       │  parseXmlNonTransactional()      │  │
   3    │  EntityDataService       │  persistEntityRelationData()     │  │  TX1
   4    │  ProvenanceStore         │  loadOrCreate()                  │  │  TX1
   5    │  ProvenanceRepository    │  save(provenance)                │  │  TX1 (en memoria)
   6    │  SourceEntityRepository  │  logicalDelete()                 │  │  TX1 (en memoria)
   7    │  FieldOcurrenceStore     │  loadOrCreate()                  │  │  TX1
   8    │  ConcurrentCachedStore   │  put()                           │  │  TX1
   9    │  FieldOccurrenceRepo     │  save(fieldOccurrence)           │  │  TX1 (en memoria)
  10    │  SemanticIdStore         │  loadOrCreate()                  │  │  TX1
  11    │  ConcurrentCachedStore   │  put()                           │  │  TX1
  12    │  SemanticIdRepo          │  save(semanticId)                │  │  TX1 (en memoria)
  13    │  EntityDataService       │  findOrCreateFinalEntity()       │  │  TX1
  14    │  EntityRepository        │  save(entity)                    │  │  TX1 (en memoria)
  15    │  SourceEntityRepository  │  save(sourceEntity)              │  │  TX1 (en memoria)
  ... (repetir 7-15 para cada entidad)
  50    │  SourceRelationRepo      │  save(sourceRelation)            │  │  TX1 (en memoria)
  ... (repetir para cada relación)
  100   │  ProvenanceStore         │  setLastUpdate()                 │  │  TX1 (en memoria)
  101   │  EntityDataService       │  return stats                    │  │  TX1
  102   │  Spring Transaction      │  FLUSH todas las operaciones     │  │  TX1 FLUSH
  103   │  Spring Transaction      │  COMMIT                          │  └─ TX1 COMMIT
  104   │  EntityDataCommands      │  return success                  │  -
```

---

## 🔑 Puntos Clave de la Arquitectura

### 1. **Una Sola Transacción por Archivo XML**

```
┌─────────────────────────────────────────────┐
│           TX1 (Transaction 1)                │
│  ┌─────────────────────────────────────┐    │
│  │  Parse XML                          │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │  Provenance (load/create)           │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │  FOR Entity 1                       │    │
│  │    - Field Occurrences              │    │
│  │    - Semantic IDs                   │    │
│  │    - Final Entity                   │    │
│  │    - Source Entity                  │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │  FOR Entity 2 ... N                 │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │  FOR Relation 1 ... M               │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │  Update Provenance LastUpdate       │    │
│  └─────────────────────────────────────┘    │
│                                              │
│  ┌─────────────────────────────────────┐    │
│  │  FLUSH (todas las operaciones)      │    │
│  └─────────────────────────────────────┘    │
│  ┌─────────────────────────────────────┐    │
│  │  COMMIT                              │    │
│  └─────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

### 2. **Propagación de Transacciones**

| Nivel | Método | Propagation | Comportamiento |
|-------|--------|-------------|----------------|
| 1 | `load_xml_file()` | - | No inicia transacción |
| 2 | `parseAndPersist...()` | **REQUIRED** | **Crea TX1** |
| 3 | `parseXmlNonTx()` | - | Sin transacción (no accede BD) |
| 3 | `persistEntityRelationData()` | **MANDATORY** | **Usa TX1** |
| 4 | `provenanceStore.loadOrCreate()` | **MANDATORY** | **Usa TX1** |
| 4 | `findOrCreateFinalEntity()` | **MANDATORY** | **Usa TX1** |
| 5 | `cachedStore.put()` | **MANDATORY** | **Usa TX1** |

### 3. **Timing de Flush**

```
Operación                           │  Estado en BD
────────────────────────────────────┼──────────────────────
save(provenance)                    │  En memoria (TX1)
save(fieldOccurrence1)              │  En memoria (TX1)
save(semanticId1)                   │  En memoria (TX1)
save(entity1)                       │  En memoria (TX1)
save(sourceEntity1)                 │  En memoria (TX1)
save(fieldOccurrence2)              │  En memoria (TX1)
...                                 │  En memoria (TX1)
save(sourceRelation1)               │  En memoria (TX1)
setLastUpdate(provenance)           │  En memoria (TX1)
────────────────────────────────────┼──────────────────────
return from persistEntityRelation   │  En memoria (TX1)
return from parseAndPersist         │  En memoria (TX1)
────────────────────────────────────┼──────────────────────
[Spring Transaction Manager]        │
  → entityManager.flush()           │  ┌─ FLUSH TO DB
  → connection.commit()             │  └─ COMMIT
────────────────────────────────────┼──────────────────────
return to EntityDataCommands        │  ✅ Persistido en BD
```

**Ventajas:**
- ✅ **Operación atómica**: Todo o nada
- ✅ **Mejor rendimiento**: Batch de inserts/updates
- ✅ **Consistencia**: No se ven datos parciales

---

## 🛡️ Manejo de Errores y Rollback

### Escenario 1: Error de Validación

```java
persistEntityRelationData() {
    // ...
    for (XMLEntityInstance xmlEntity : data.getEntities()) {
        // ...
        if (!isAtLeastOneMinimalViableSemanticIdentifier) {
            // ┌────────────────────────────────────────┐
            // │ Lanza EntitiyRelationXMLLoadingException │
            // │ Spring intercepta la excepción          │
            // │ Marca TX1 para rollback                 │
            // │ NO se hace flush                        │
            // │ ROLLBACK completo                       │
            // └────────────────────────────────────────┘
            throw new EntitiyRelationXMLLoadingException("...");
        }
    }
}
```

**Resultado:**
- ❌ **Ningún dato se persiste** (rollback completo)
- ✅ Base de datos queda consistente
- ✅ Excepción propagada al caller

---

### Escenario 2: Error de Constraint de BD

```java
persistEntityRelationData() {
    // ...
    sourceEntityRepository.save(sourceEntity);
    // Supongamos que sourceEntity viola un constraint único
}

// Al momento del FLUSH:
// ┌────────────────────────────────────────┐
// │ entityManager.flush()                  │
// │   → Hibernate ejecuta SQL              │
// │   → BD lanza ConstraintViolationException │
// │   → Hibernate convierte a DataIntegrityViolationException │
// │   → Spring intercepta                  │
// │   → Marca TX1 para rollback           │
// │   → ROLLBACK completo                 │
// └────────────────────────────────────────┘
```

**Resultado:**
- ❌ **Ningún dato se persiste** (rollback completo)
- ✅ Base de datos queda consistente
- ✅ Excepción propagada con stack trace completo

---

### Escenario 3: Éxito Completo

```java
persistEntityRelationData() {
    // Todas las operaciones exitosas
    return stats;
}

// Al salir del método parseAndPersist:
// ┌────────────────────────────────────────┐
// │ entityManager.flush()                  │
// │   → Hibernate ejecuta todos los SQL    │
// │   → Inserts, Updates en orden correcto │
// │   → Todo exitoso                       │
// │ connection.commit()                    │
// │   → BD confirma cambios                │
// │   → TX1 completada                     │
// └────────────────────────────────────────┘
```

**Resultado:**
- ✅ **Todos los datos persistidos**
- ✅ Base de datos consistente
- ✅ Stats retornados al caller

---

## 🔍 Comparación: Antes vs Después

### Antes del Refactoring

```
load_xml_file() [NO TX]
  └─> parseAndPersist() [TX1 - REQUIRED]
       ├─> parseXml() [TX2 - REQUIRES_NEW, READ_UNCOMMITTED] ❌
       │    └─> (solo parsea XML)
       └─> persist() [TX3 - REQUIRES_NEW, READ_UNCOMMITTED] ❌
            ├─> provenance.loadOrCreate() [NO TX + synchronized] ❌
            │    └─> saveAndFlush() ❌
            ├─> logicalDelete() [usa TX3]
            ├─> FOR cada entidad:
            │    ├─> fieldStore.loadOrCreate() [TX4 - REQUIRES_NEW] ❌
            │    │    ├─> Manual TX5 ❌❌❌
            │    │    └─> put() [TX6 - REQUIRES_NEW, SERIALIZABLE] ❌❌
            │    │         └─> saveAndFlush() ❌
            │    ├─> semanticStore.loadOrCreate() [NO TX]
            │    │    └─> put() [TX7 - REQUIRES_NEW, SERIALIZABLE] ❌❌
            │    │         └─> saveAndFlush() ❌
            │    ├─> findOrCreate() [NO TX + synchronized] ❌
            │    │    └─> saveAndFlush() ❌
            │    └─> saveAndFlush(sourceEntity) ❌
            └─> provenance.setLastUpdate() [NO TX] ❌

Problemas:
❌ 6-7 transacciones por archivo
❌ Conflictos de aislamiento (SERIALIZABLE vs READ_UNCOMMITTED)
❌ Gestión manual de transacciones
❌ synchronized + transacciones = deadlocks
❌ Múltiples flush (uno por entidad)
❌ Rollback-only silencioso
```

### Después del Refactoring

```
load_xml_file() [NO TX]
  └─> parseAndPersist() [TX1 - REQUIRED] ✅
       ├─> parseXmlNonTx() [NO TX] ✅
       │    └─> (solo parsea XML)
       └─> persist() [MANDATORY - usa TX1] ✅
            ├─> provenance.loadOrCreate() [MANDATORY - usa TX1] ✅
            │    └─> save() ✅
            ├─> logicalDelete() [usa TX1] ✅
            ├─> FOR cada entidad:
            │    ├─> fieldStore.loadOrCreate() [NO TX - usa TX1] ✅
            │    │    └─> put() [MANDATORY - usa TX1] ✅
            │    │         └─> save() ✅
            │    ├─> semanticStore.loadOrCreate() [NO TX - usa TX1] ✅
            │    │    └─> put() [MANDATORY - usa TX1] ✅
            │    │         └─> save() ✅
            │    ├─> findOrCreate() [MANDATORY - usa TX1] ✅
            │    │    └─> save() ✅
            │    └─> save(sourceEntity) ✅
            └─> provenance.setLastUpdate() [MANDATORY - usa TX1] ✅
       
       [Spring Transaction Manager]
         └─> flush() + commit() ✅

Beneficios:
✅ 1 sola transacción por archivo
✅ Un solo nivel de aislamiento
✅ Solo gestión declarativa
✅ Sin synchronized
✅ Flush único al final
✅ Errores claros y predecibles
```

---

## 📈 Ventajas de la Nueva Arquitectura

### Rendimiento
1. **Menos overhead transaccional**: 1 TX vs 6-7 TX
2. **Batch de escrituras**: Flush único vs múltiples flush
3. **Sin suspend/resume de transacciones**: Todo en misma TX
4. **Mejor uso de batch JDBC**: Hibernate puede agrupar INSERTs

### Confiabilidad
1. **Comportamiento ACID garantizado**: Todo o nada
2. **No más rollback-only silencioso**: Errores claros
3. **Stack traces completos**: Debugging más fácil
4. **Consistencia de datos**: No hay estados parciales

### Mantenibilidad
1. **Código más simple**: Una sola estrategia transaccional
2. **Fácil de entender**: Flujo lineal
3. **Sin gestión manual**: Solo anotaciones declarativas
4. **Sin bloqueos Java**: Solo bloqueos de BD

### Concurrencia
1. **Menos riesgo de deadlocks**: Sin synchronized
2. **Transacciones más cortas**: Mejor throughput
3. **Nivel de aislamiento consistente**: Sin conflictos

---

## 🎯 Principios Aplicados

1. ✅ **Single Transaction per Unit of Work**: Una transacción por archivo XML
2. ✅ **Declarative Transaction Management**: Solo @Transactional
3. ✅ **Mandatory for DB Operations**: Métodos que acceden BD requieren TX
4. ✅ **Deferred Flush Pattern**: Flush al final de TX
5. ✅ **Fail-Fast**: Errores claros y tempranos
6. ✅ **ACID Compliance**: Atomicidad garantizada

---

## 🔧 Configuración Recomendada

### application.properties

```properties
# Nivel de aislamiento por defecto (READ_COMMITTED)
# No es necesario especificar - Spring usa el default del driver

# Show SQL para debugging
spring.jpa.show-sql=false
spring.jpa.properties.hibernate.format_sql=true

# Habilitar estadísticas Hibernate (solo para debug)
spring.jpa.properties.hibernate.generate_statistics=false

# Batch size para mejor rendimiento
spring.jpa.properties.hibernate.jdbc.batch_size=20
spring.jpa.properties.hibernate.order_inserts=true
spring.jpa.properties.hibernate.order_updates=true

# Logging
logging.level.org.lareferencia.core.entity=DEBUG
logging.level.org.springframework.transaction=INFO
logging.level.org.hibernate.SQL=DEBUG
logging.level.org.hibernate.type.descriptor.sql.BasicBinder=TRACE
```

---

## 📝 Notas para Desarrolladores

### ¿Cuándo crear una nueva transacción?

**NUNCA** en métodos que son parte del flujo de carga de entidades.

**Solo usar REQUIRES_NEW si:**
- La operación debe completarse independientemente del resultado de la TX padre
- Ejemplo: Log de auditoría que debe persistir aunque falle la operación principal

### ¿Cuándo usar MANDATORY?

**SIEMPRE** en métodos que:
- Ejecutan operaciones de base de datos
- Son parte de una operación más grande
- Deben garantizar que están en una transacción

### ¿Cuándo NO usar @Transactional?

- Métodos que **solo** procesan datos en memoria (ej: parseXML)
- Métodos que **solo** leen configuración
- Métodos de utilidad que no acceden a BD

### ¿Usar save() o saveAndFlush()?

**Siempre usar `save()`** excepto si:
- Necesitas el ID autogenerado inmediatamente
- Necesitas forzar validación de constraints antes de continuar
- Estás fuera de una transacción (muy raro)

---

## 🧪 Testing de Transacciones

### Test Unitario

```java
@Test
@Transactional  // TX de test (diferente a TX de producción)
public void test_entity_loading() {
    // La TX del test hace rollback automático
    // No contamina la BD
    Document doc = getXmlDocument("test.xml");
    EntityLoadingStats stats = dataService.parseAndPersist...(doc, false);
    
    assertThat(stats).isNotNull();
    // Al terminar el test: ROLLBACK automático
}
```

### Verificar Logging

```bash
# Debe mostrar:
# 1. Un solo "Creating new transaction"
# 2. Múltiples "Participating in existing transaction"
# 3. Un solo "Committing JPA transaction"
```

---

## 🔗 Referencias

- Spring Transaction Management: [docs.spring.io/transaction](https://docs.spring.io/spring-framework/docs/current/reference/html/data-access.html#transaction)
- Hibernate Flush Modes: [Hibernate User Guide](https://docs.jboss.org/hibernate/orm/current/userguide/html_single/Hibernate_User_Guide.html#flushing)
- JPA Transaction Propagation: [Baeldung Guide](https://www.baeldung.com/spring-transactional-propagation-isolation)

---

**Documento creado el:** 7 de noviembre de 2025  
**Autor:** Sistema de carga de entidades refactorizado  
**Versión:** 1.0
