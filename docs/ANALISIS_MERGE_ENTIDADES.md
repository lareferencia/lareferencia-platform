# Análisis del Script de Merge de Entidades (process_dirty_entities)

## 📋 Descripción General

Este script SQL implementa un **proceso batch de consolidación** que toma las entidades marcadas como `dirty` y sincroniza sus datos desde las `source_entity` hacia las `entity` finales, además de reconstruir las relaciones.

---

## 🔍 Relación con la Arquitectura Transaccional

### Contexto en el Flujo de Carga

```
┌─────────────────────────────────────────────────────────────┐
│ PASO 1: Carga de Datos (Java - EntityDataService)           │
│  - parseAndPersistEntityRelationData()                      │
│  - Crea/actualiza SourceEntity, SourceRelation              │
│  - Marca Entity como dirty = TRUE                           │
│  - NO sincroniza field occurrences ni relaciones            │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ PASO 2: Merge (SQL - process_dirty_entities)                │
│  - Copia field occurrences de SourceEntity → Entity         │
│  - Reconstruye relaciones desde SourceRelation → Relation   │
│  - Marca Entity como dirty = FALSE                          │
└─────────────────────────────────────────────────────────────┘
```

### ¿Por Qué Existe Este Script?

El diseño actual tiene **dos fases separadas**:

1. **Fase de Carga (Java):** Rápida, transaccional
   - Valida y parsea XML
   - Crea/actualiza source_entity y source_relation
   - Crea/referencia entity final
   - **NO** copia field_occurrences a la entity
   - **NO** crea las relation finales

2. **Fase de Merge (SQL):** Batch, post-procesamiento
   - Consolida datos de múltiples source_entity en entity
   - Crea/actualiza relation finales
   - Marca entities como limpias (dirty=false)

---

## 🎯 Análisis Detallado del Script

### FASE 1: Preparación de Datos

#### 1.1. Crear Tabla Auxiliar de Mapeo

```sql
CREATE TABLE aux_entity_map (
    entity_id UUID NOT NULL,    -- Entity final
    source_id UUID              -- Source Entity que apunta a ella
);

INSERT INTO aux_entity_map (entity_id, source_id)
SELECT e.uuid, se.uuid
FROM entity e
JOIN source_entity se ON se.final_entity_id = e.uuid
WHERE e.dirty = TRUE;
```

**Propósito:**
- Mapear qué source_entities apuntan a cada entity dirty
- Una entity puede tener **múltiples** source_entities (duplicados)
- Ejemplo:
  ```
  Entity: abc-123 (dirty=true)
    ← SourceEntity: source-1 (provenance: repo1/record1)
    ← SourceEntity: source-2 (provenance: repo2/record2)  // mismo autor
    ← SourceEntity: source-3 (provenance: repo1/record1)  // actualización
  ```

**Optimización:**
- Crea índices en `entity_id` y `source_id`
- Permite JOINs eficientes posteriores

---

### FASE 2: Field Occurrences

#### 2.1. Consolidar Field Occurrences

```sql
CREATE TEMP TABLE tmp_entity_fieldoccrs AS
SELECT DISTINCT aem.entity_id, sef.fieldoccr_id
FROM aux_entity_map aem
JOIN source_entity_fieldoccr sef ON sef.entity_id = aem.source_id
WHERE aem.source_id IS NOT NULL;
```

**Lógica:**
- Recolecta TODOS los field_occurrences de TODAS las source_entities
- `DISTINCT` elimina duplicados (mismo fieldoccr en múltiples sources)
- Ejemplo:
  ```
  SourceEntity source-1:
    - fieldoccr: "name:John Doe"
    - fieldoccr: "email:john@example.com"
  
  SourceEntity source-2:
    - fieldoccr: "name:John Doe"        // duplicado
    - fieldoccr: "orcid:0000-0001-..."  // nuevo
  
  Resultado en Entity abc-123:
    - fieldoccr: "name:John Doe"        // una sola vez
    - fieldoccr: "email:john@example.com"
    - fieldoccr: "orcid:0000-0001-..."
  ```

#### 2.2. Eliminar Field Occurrences Antiguos

```sql
DELETE FROM entity_fieldoccr
WHERE entity_id IN (SELECT DISTINCT entity_id FROM aux_entity_map);
```

**Por Qué:**
- Las entities dirty pueden haber tenido field_occurrences previos
- Necesitamos **reemplazar** completamente los datos
- Es una operación de **full refresh**

#### 2.3. Insertar Nuevos Field Occurrences

```sql
INSERT INTO entity_fieldoccr (entity_id, fieldoccr_id)
SELECT entity_id, fieldoccr_id FROM tmp_entity_fieldoccrs;
```

**Resultado:**
- Entity ahora tiene TODOS los field_occurrences de TODAS sus source_entities
- Consolidación completa de datos

---

### FASE 3: Relaciones

#### 3.1. Crear Tabla Temporal de Relaciones

```sql
CREATE TABLE tmp_new_relations (
    from_entity_id UUID,           -- Entity final (desde)
    relation_type_id int8,         -- Tipo de relación
    to_entity_id UUID,             -- Entity final (hacia)
    source_from_entity_id UUID,    -- SourceEntity original (desde)
    source_to_entity_id UUID,      -- SourceEntity original (hacia)
    dirty BOOLEAN
);

ALTER TABLE tmp_new_relations 
ADD CONSTRAINT unique_tmp_new_relations 
UNIQUE (from_entity_id, relation_type_id, to_entity_id);
```

**Diseño:**
- Constraint UNIQUE previene duplicados
- Mantiene referencia a source para copiar field_occurrences después

#### 3.2. Construir Relaciones Finales

```sql
INSERT INTO tmp_new_relations (...)
SELECT 
    se1.final_entity_id as from_entity_id,    -- Entity final FROM
    sr.relation_type_id,
    se2.final_entity_id as to_entity_id,      -- Entity final TO
    sr.from_entity_id as source_from_entity_id,
    sr.to_entity_id as source_to_entity_id,
    true as dirty
FROM source_relation sr
JOIN source_entity se1 ON sr.from_entity_id = se1.uuid
JOIN source_entity se2 ON sr.to_entity_id = se2.uuid
WHERE (EXISTS (...) OR EXISTS (...))  -- Al menos una entity involucrada es dirty
AND se1.deleted = FALSE 
AND se2.deleted = FALSE
AND se1.final_entity_id IS NOT NULL 
AND se2.final_entity_id IS NOT NULL
ON CONFLICT (...) DO NOTHING;
```

**Lógica Compleja:**

1. **Mapeo de Source a Final:**
   ```
   SourceRelation:
     from: source-entity-1  →  [final_entity_id]  →  Entity A
     to:   source-entity-2  →  [final_entity_id]  →  Entity B
   
   Relation Final:
     from: Entity A
     to:   Entity B
   ```

2. **Condiciones de Filtro:**
   - ✅ Al menos UNA de las entities involucradas debe ser dirty
   - ✅ Ambas source_entities NO deben estar deleted
   - ✅ Ambas source_entities deben tener final_entity_id (no nulos)

3. **Deduplicación Automática:**
   - Si múltiples source_relations apuntan a la misma relation final → solo se crea UNA
   - Ejemplo:
     ```
     SourceRelation 1: source-person-1 → authored → source-paper-1
     SourceRelation 2: source-person-2 → authored → source-paper-1
     
     Si source-person-1 y source-person-2 son duplicados 
     (mismo final_entity_id = Entity-Person-ABC)
     
     Resultado:
       Relation: Entity-Person-ABC → authored → Entity-Paper-XYZ  (UNA sola)
     ```

#### 3.3. Eliminar Relaciones Antiguas

```sql
DELETE FROM relation r
WHERE EXISTS (
    SELECT 1 FROM aux_entity_map aem
    WHERE aem.entity_id = r.from_entity_id OR aem.entity_id = r.to_entity_id
);
```

**Estrategia:**
- Eliminar TODAS las relaciones que involucren entities dirty
- Tanto si la entity es origen (from) o destino (to)
- Es un **full refresh** de relaciones

#### 3.4. Insertar Nuevas Relaciones

```sql
INSERT INTO relation (relation_type_id, from_entity_id, to_entity_id, dirty)
SELECT tnr.relation_type_id, tnr.from_entity_id, tnr.to_entity_id, true
FROM tmp_new_relations tnr
ON CONFLICT (...) DO NOTHING;
```

---

### FASE 4: Field Occurrences de Relaciones

#### 4.1. Eliminar Field Occurrences de Relaciones Dirty

```sql
DELETE FROM relation_fieldoccr rfo
WHERE EXISTS (
    SELECT 1 FROM relation r
    WHERE r.dirty = TRUE
      AND rfo.relation_type_id = r.relation_type_id
      AND rfo.from_entity_id = r.from_entity_id
      AND rfo.to_entity_id = r.to_entity_id
);
```

#### 4.2. Copiar Field Occurrences desde Source Relations

```sql
INSERT INTO relation_fieldoccr (from_entity_id, relation_type_id, to_entity_id, fieldoccr_id)
SELECT
    tnr.from_entity_id,
    tnr.relation_type_id,
    tnr.to_entity_id,
    sro.fieldoccr_id
FROM tmp_new_relations tnr
JOIN source_relation_fieldoccr sro ON sro.relation_type_id = tnr.relation_type_id
                                AND sro.from_entity_id = tnr.source_from_entity_id
                                AND sro.to_entity_id = tnr.source_to_entity_id
ON CONFLICT (...) DO NOTHING;
```

**Mapeo:**
```
SourceRelation (source-person-1 → authored → source-paper-1):
  - fieldoccr: "role:first author"
  - fieldoccr: "contribution:50%"

Relation Final (Entity-Person-ABC → authored → Entity-Paper-XYZ):
  - fieldoccr: "role:first author"
  - fieldoccr: "contribution:50%"
```

---

### FASE 5: Limpieza

#### 5.1. Marcar Entities como Limpias

```sql
UPDATE entity
SET dirty = FALSE
WHERE uuid IN (SELECT DISTINCT entity_id FROM aux_entity_map);
```

#### 5.2. Marcar Relaciones como Limpias

```sql
UPDATE relation
SET dirty = FALSE
WHERE dirty = TRUE;
```

---

## 🔍 Análisis Crítico

### ✅ Ventajas del Diseño Actual

1. **Separación de Responsabilidades**
   - Java: Validación, deduplicación, creación de source data
   - SQL: Consolidación batch, optimizada para grandes volúmenes

2. **Transacciones Rápidas en Java**
   - No tiene que esperar el merge completo
   - Puede procesar múltiples archivos rápidamente
   - Cada archivo es independiente

3. **Optimización de Merge**
   - Se ejecuta en batch para múltiples entities
   - Usa SQL set-based operations (muy eficiente)
   - Puede ejecutarse asíncronamente

4. **Manejo de Duplicados**
   - El merge consolida automáticamente datos de múltiples sources
   - DISTINCT y ON CONFLICT previenen duplicados

### ⚠️ Desventajas y Problemas

#### 1. **Estado Inconsistente Temporal**

```
PROBLEMA: Entre la carga (Java) y el merge (SQL), los datos están inconsistentes

Entity ABC:
  - dirty = TRUE
  - field_occurrences = [] ← VACÍO! (no sincronizado aún)
  - relations = [] ← VACÍAS!

Si alguien consulta la entity ANTES del merge → obtiene datos incompletos
```

**Impacto:**
- ❌ Queries pueden retornar entities sin datos
- ❌ Índices de búsqueda pueden tener información desactualizada
- ❌ Reports pueden mostrar conteos incorrectos

#### 2. **Flag `dirty` No Se Usa para Filtrar Queries**

Busqué en el código y no vi que las queries filtren por `dirty = FALSE`:

```java
// EntityRepository.java
Entity findEntityWithSemanticIdentifiers(List<Long> semanticIds);
// ← NO filtra por dirty!

List<Entity> findByProvenanceSourceAndRecordId(String sourceId, String recordId);
// ← NO filtra por dirty!
```

**Consecuencia:**
- Las entities dirty (sin field_occurrences) pueden ser retornadas en búsquedas
- Los usuarios pueden ver entities "vacías" o incompletas

#### 3. **No Hay Sincronización Automática**

El script SQL **NO se ejecuta automáticamente** después de la carga:

```java
// EntityDataCommands.java - load_data()
erService.mergeEntityRelationData();  // ← Este método está VACÍO!
```

**Problema:**
- El merge debe ejecutarse **manualmente**
- Si no se ejecuta, las entities quedan dirty indefinidamente
- No hay garantía de cuándo se ejecutará

#### 4. **Full Refresh en Lugar de Incremental**

```sql
-- Elimina TODO y reinserta TODO
DELETE FROM entity_fieldoccr WHERE entity_id IN (...);
INSERT INTO entity_fieldoccr SELECT ...;

DELETE FROM relation WHERE ...;
INSERT INTO relation SELECT ...;
```

**Problemas:**
- ⚠️ Si el merge falla a mitad de camino → pérdida de datos
- ⚠️ No es transaccional con la carga de Java
- ⚠️ Puede ser lento para grandes volúmenes

#### 5. **Triggers Desactivados Según Comentario**

```sql
-- "con triggers desactivados"
```

**Preguntas:**
- ¿Hay triggers que deberían ejecutarse?
- ¿Se desactivan para rendimiento?
- ¿Hay efectos secundarios de desactivarlos?

---

## 🎯 Comparación con Arquitectura Transaccional Actual

### Lo Que Hace el Código Java (Refactorizado)

```java
@Transactional(propagation = Propagation.MANDATORY)
public EntityLoadingStats persistEntityRelationData(...) {
    
    // 1. Provenance
    provenance = provenanceStore.loadOrCreate(...);
    
    // 2. Source Entities
    for (XMLEntityInstance xmlEntity : data.getEntities()) {
        SourceEntity sourceEntity = new SourceEntity(entityType, provenance);
        
        // 2.1. Field Occurrences en SOURCE entity
        addFieldOccurrenceFromXMLFieldInstance(...);
        
        // 2.2. Semantic Identifiers
        sourceEntity.addSemanticIdentifier(...);
        
        // 2.3. Find or Create FINAL Entity (marca como dirty)
        FindOrCreateEntityResult result = findOrCreateFinalEntity(sourceEntity);
        entity.setDirty(true);  // ← MARCA COMO DIRTY
        
        // 2.4. Link source → final
        sourceEntity.setFinalEntity(result.entity);
        
        // 2.5. Save source entity (con field_occurrences)
        sourceEntityRepository.save(sourceEntity);
        
        // ❌ NO copia field_occurrences a entity final
        // ❌ NO crea relation final
    }
    
    // 3. Source Relations
    for (XMLRelationInstance xmlRelation : data.getRelations()) {
        SourceRelation sourceRelation = ...;
        sourceRelationRepository.save(sourceRelation);
        
        // ❌ NO crea relation final
    }
    
    // 4. Update provenance
    provenanceStore.setLastUpdate(...);
    
    return stats;
}
```

### Lo Que Hace el Script SQL (Merge)

```sql
-- Copia field_occurrences: source_entity_fieldoccr → entity_fieldoccr
-- Crea relations: source_relation → relation
-- Copia field_occurrences: source_relation_fieldoccr → relation_fieldoccr
-- Marca entities y relations como dirty=false
```

---

## 📊 Flujo Completo de Datos

```
┌─────────────────────────────────────────────────────────────┐
│ XML File                                                     │
│  - Entity: Person (John Doe)                                │
│  - Entity: Paper (Title ABC)                                │
│  - Relation: Person authored Paper                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Java: persistEntityRelationData()                           │
│                                                              │
│  Provenance: repo1/record1                                  │
│                                                              │
│  SourceEntity 1:                                            │
│    - type: Person                                           │
│    - provenance: repo1/record1                              │
│    - final_entity_id: Entity-ABC (dirty=true)               │
│    - field_occurrences: [name:"John Doe", orcid:"..."]      │
│                                                              │
│  SourceEntity 2:                                            │
│    - type: Paper                                            │
│    - provenance: repo1/record1                              │
│    - final_entity_id: Entity-XYZ (dirty=true)               │
│    - field_occurrences: [title:"Title ABC"]                 │
│                                                              │
│  SourceRelation:                                            │
│    - from: SourceEntity 1                                   │
│    - to: SourceEntity 2                                     │
│    - type: authored                                         │
│    - field_occurrences: [role:"first author"]               │
│                                                              │
│  Entity-ABC:                                                │
│    - type: Person                                           │
│    - dirty: TRUE                                            │
│    - field_occurrences: [] ← VACÍO!                         │
│                                                              │
│  Entity-XYZ:                                                │
│    - type: Paper                                            │
│    - dirty: TRUE                                            │
│    - field_occurrences: [] ← VACÍO!                         │
│                                                              │
│  NO HAY Relation entre Entity-ABC y Entity-XYZ              │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ SQL: process_dirty_entities()                               │
│                                                              │
│  1. Copia field_occurrences:                                │
│     SourceEntity 1 → Entity-ABC                             │
│       [name:"John Doe", orcid:"..."]                        │
│                                                              │
│     SourceEntity 2 → Entity-XYZ                             │
│       [title:"Title ABC"]                                   │
│                                                              │
│  2. Crea Relation:                                          │
│     from: Entity-ABC                                        │
│     to: Entity-XYZ                                          │
│     type: authored                                          │
│                                                              │
│  3. Copia field_occurrences de relation:                    │
│     SourceRelation → Relation                               │
│       [role:"first author"]                                 │
│                                                              │
│  4. Marca como limpio:                                      │
│     Entity-ABC.dirty = FALSE                                │
│     Entity-XYZ.dirty = FALSE                                │
│     Relation.dirty = FALSE                                  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Estado Final (Consistente)                                  │
│                                                              │
│  Entity-ABC:                                                │
│    - type: Person                                           │
│    - dirty: FALSE                                           │
│    - field_occurrences: [name:"John Doe", orcid:"..."]      │
│                                                              │
│  Entity-XYZ:                                                │
│    - type: Paper                                            │
│    - dirty: FALSE                                           │
│    - field_occurrences: [title:"Title ABC"]                 │
│                                                              │
│  Relation:                                                  │
│    - from: Entity-ABC                                       │
│    - to: Entity-XYZ                                         │
│    - type: authored                                         │
│    - dirty: FALSE                                           │
│    - field_occurrences: [role:"first author"]               │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚨 Problemas Identificados

### 1. **Ventana de Inconsistencia**

```
Tiempo │ Estado
───────┼────────────────────────────────────────────────────
  T0   │ (estado inicial)
  T1   │ Carga Java: Entity creada, dirty=true, SIN datos
  T2   │ ← VENTANA DE INCONSISTENCIA ←
  T3   │ ← Queries pueden retornar entities vacías ←
  T4   │ ← Índices pueden estar desactualizados ←
  T5   │ Merge SQL: Entity populated, dirty=false
  T6   │ (estado consistente)
```

### 2. **Método `mergeEntityRelationData()` Vacío**

```java
// EntityDataService.java
@Transactional
public synchronized void mergeEntityRelationData() {
    //entityRepository.mergeEntiyRelationData();
    // TODO: delete this method
}

// EntityDataCommands.java
erService.mergeEntityRelationData();  // ← NO HACE NADA!
```

**Consecuencia:**
- El merge NO se ejecuta automáticamente
- Las entities quedan dirty indefinidamente
- Alguien debe ejecutar el script SQL manualmente

### 3. **Falta de Atomicidad entre Java y SQL**

```
Java Transaction:
  ┌─────────────────────┐
  │ Create SourceEntity │
  │ Create Entity       │
  │ SET dirty = TRUE    │
  └─────────────────────┘
           ↓ COMMIT
           
  ⚠️ GAP SIN TRANSACCIÓN ⚠️
           
SQL Procedure:
  ┌─────────────────────┐
  │ Copy field_occrs    │
  │ Create relations    │
  │ SET dirty = FALSE   │
  └─────────────────────┘
```

Si el proceso SQL falla → datos quedan en estado intermedio

---

## 💡 Recomendaciones

### Opción A: Ejecutar Merge Dentro de la Transacción Java ⭐ **MEJOR**

```java
@Transactional(propagation = Propagation.MANDATORY)
public EntityLoadingStats persistEntityRelationData(...) {
    // ... código actual ...
    
    // Al final, antes de return:
    if (!dryRun) {
        // Ejecutar merge inmediatamente
        processDirtyEntitiesForProvenance(provenance.getId());
    }
    
    return stats;
}

private void processDirtyEntitiesForProvenance(Long provenanceId) {
    // Versión Java del merge, solo para entities de esta provenance
    // O llamada a stored procedure SQL
}
```

**Ventajas:**
- ✅ Atómico - todo en una transacción
- ✅ Sin ventana de inconsistencia
- ✅ Entities siempre consistentes

**Desventajas:**
- ⚠️ Transacción más larga
- ⚠️ Más lógica en Java

### Opción B: Sincronizar Automáticamente Post-Commit

```java
@TransactionalEventListener(phase = TransactionPhase.AFTER_COMMIT)
public void onEntityLoadingCommit(EntityLoadingEvent event) {
    // Ejecutar merge asíncronamente
    mergeDirtyEntitiesAsync();
}
```

**Ventajas:**
- ✅ Transacción Java rápida
- ✅ Merge en background

**Desventajas:**
- ⚠️ Ventana de inconsistencia (aunque pequeña)
- ⚠️ Complejidad adicional

### Opción C: Filtrar Entities Dirty en Queries

```java
// EntityRepository.java
@Query("SELECT e FROM Entity e WHERE e.dirty = FALSE AND ...")
Entity findEntityWithSemanticIdentifiers(List<Long> semanticIds);
```

**Ventajas:**
- ✅ Queries nunca retornan datos inconsistentes

**Desventajas:**
- ⚠️ Entities dirty no son encontrables
- ⚠️ Debe combinarse con merge automático

### Opción D: Implementar el Merge en Java (Eliminar SQL)

Cambiar la lógica para que Java haga TODO:

```java
@Transactional(propagation = Propagation.MANDATORY)
public EntityLoadingStats persistEntityRelationData(...) {
    // ... crear source entities ...
    
    // Copiar field_occurrences a entity final INMEDIATAMENTE
    for (FieldOccurrence fo : sourceEntity.getFieldOccurrences()) {
        entity.addFieldOccurrence(fo);
    }
    entityRepository.save(entity);
    entity.setDirty(false);  // ← Ya está sincronizada
    
    // Crear relation final INMEDIATAMENTE
    Relation relation = new Relation(entity1, entity2, relationType);
    relationRepository.save(relation);
    
    return stats;
}
```

**Ventajas:**
- ✅ Completamente atómico
- ✅ Sin ventana de inconsistencia
- ✅ Sin necesidad de script SQL
- ✅ Consistente con arquitectura transaccional

**Desventajas:**
- ⚠️ Requiere refactoring importante
- ⚠️ Transacción más larga
- ⚠️ Lógica de deduplicación más compleja en Java

---

## 🎯 Conclusión

### El Script SQL es **Correcto y Eficiente** PERO...

**✅ Fortalezas:**
1. Optimizado para operaciones set-based
2. Maneja bien la consolidación de duplicados
3. Deduplicación automática
4. Operaciones batch eficientes

**❌ Debilidades:**
1. **Desacoplado** de la transacción Java
2. **No se ejecuta automáticamente** (método vacío)
3. Crea **ventana de inconsistencia**
4. **No hay filtrado** de entities dirty en queries
5. **No es atómico** con la carga

### Inconsistencia con Arquitectura Transaccional

La arquitectura transaccional que acabamos de refactorizar enfatiza:
- ✅ Una transacción por operación
- ✅ Atomicidad completa
- ✅ Sin estados intermedios

Pero el merge introduce:
- ❌ Dos fases desacopladas
- ❌ Estado intermedio (dirty)
- ❌ Sincronización manual requerida

### Recomendación Final

**Corto plazo:**
1. Implementar el merge en `mergeEntityRelationData()` para que se ejecute automáticamente
2. Agregar filtros `dirty = FALSE` en queries críticas

**Largo plazo:**
3. Considerar mover la lógica de merge a Java para eliminar la ventana de inconsistencia
4. O al menos ejecutar el merge dentro de la misma transacción

---

**Fecha de análisis:** 7 de noviembre de 2025  
**Contexto:** Post-refactoring de arquitectura transaccional
