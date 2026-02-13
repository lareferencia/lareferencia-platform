# Implementación del SemanticIndexerWorker

## Resumen

Este documento describe la implementación del `SemanticIndexerWorker`, un nuevo worker de indexación que extiende las capacidades del sistema LA Referencia para soportar búsqueda semántica mediante vectores densos (Dense Vectors) en Apache Solr.

## Contexto y Motivación

### Búsqueda Semántica con VuFind

VuFind soporta búsqueda semántica utilizando la funcionalidad de Dense Vectors de Solr, que permite realizar búsquedas k-NN (k-Nearest Neighbors) basadas en similitud vectorial. Esta capacidad permite encontrar documentos semánticamente similares aunque no compartan las mismas palabras clave.

### Arquitectura de Vectores en Solr

- **Tipo de campo**: `DenseVectorField` de Solr
- **Dimensiones**: 768 (estándar para modelos de embeddings como BERT, Sentence Transformers)
- **Función de similitud**: `dot_product` (producto punto)
- **Query de búsqueda**: `{!knn f=vector topK=10}[vector_values]`

## Trabajo Realizado

### 1. Análisis del IndexerWorker Original

Se analizó el archivo `IndexerWorker.java` ubicado en:
```
lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/indexing/IndexerWorker.java
```

**Características principales identificadas:**
- Worker de tipo batch que procesa registros OAI-PMH
- Genera documentos Solr mediante transformación XSLT
- Utiliza `HttpSolrClient` para comunicación con Solr
- Soporta parámetros configurables vía Spring beans
- Manejo de estados de registros (`VALID`, `TRANSFORMED`, `DELETED`)

### 2. Creación del SemanticIndexerWorker

Se creó una copia independiente del `IndexerWorker` con las siguientes modificaciones:

**Ubicación:**
```
lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/indexing/SemanticIndexerWorker.java
```

**Cambios de identidad:**
- Nombre de clase: `SemanticIndexerWorker`
- Nombre de componente Spring: `"semanticIndexerWorker"`
- Logger: `SemanticIndexerWorker.class`

### 3. Integración con API de Embeddings

Se implementó la comunicación con un servicio externo de generación de embeddings:

#### Nuevos Imports Añadidos

```java
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.net.URI;
import java.time.Duration;
import java.util.Arrays;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.JsonNode;
```

#### Nuevos Parámetros Configurables

| Parámetro | Tipo | Default | Descripción |
|-----------|------|---------|-------------|
| `embeddingApiUrl` | String | - | URL del servicio de embeddings |
| `sourceFieldForEmbedding` | String | `"dc.title.*"` | Campo de metadatos fuente para extraer texto |
| `vectorFieldName` | String | `"semantic_vector"` | Nombre del campo vector en Solr |
| `embeddingApiTimeoutSeconds` | int | `30` | Timeout para llamadas a la API |
| `skipOnEmbeddingFailure` | boolean | `true` | Continuar si falla la generación de embedding |

#### Nuevos Atributos de Clase

```java
private String embeddingApiUrl;
private String sourceFieldForEmbedding = "dc.title.*";
private String vectorFieldName = "semantic_vector";
private int embeddingApiTimeoutSeconds = 30;
private boolean skipOnEmbeddingFailure = true;

private HttpClient httpClient;
private ObjectMapper objectMapper;
```

#### Inicialización en `preRun()`

```java
// Initialize HTTP client for embedding API
this.httpClient = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(embeddingApiTimeoutSeconds))
    .build();
this.objectMapper = new ObjectMapper();
```

### 4. Métodos de Generación de Embeddings

#### `extractTextForEmbedding(OAIRecordMetadata metadata)`

Extrae el texto del campo de metadatos configurado:

```java
private String extractTextForEmbedding(OAIRecordMetadata metadata) {
    List<String> values = metadata.getFieldOcurrences(sourceFieldForEmbedding);
    if (values == null || values.isEmpty()) {
        return null;
    }
    return String.join(" ", values);
}
```

#### `generateEmbedding(String text)`

Llama a la API externa para generar el vector de embedding:

```java
private float[] generateEmbedding(String text) throws Exception {
    // Build JSON request
    String jsonBody = objectMapper.writeValueAsString(
        java.util.Collections.singletonMap("text", text)
    );
    
    HttpRequest request = HttpRequest.newBuilder()
        .uri(URI.create(embeddingApiUrl))
        .header("Content-Type", "application/json")
        .timeout(Duration.ofSeconds(embeddingApiTimeoutSeconds))
        .POST(HttpRequest.BodyPublishers.ofString(jsonBody))
        .build();
    
    HttpResponse<String> response = httpClient.send(request, 
        HttpResponse.BodyHandlers.ofString());
    
    if (response.statusCode() != 200) {
        throw new RuntimeException("Embedding API error: " + response.statusCode());
    }
    
    // Parse response
    JsonNode root = objectMapper.readTree(response.body());
    JsonNode embeddingNode = root.get("embedding");
    
    float[] embedding = new float[embeddingNode.size()];
    for (int i = 0; i < embeddingNode.size(); i++) {
        embedding[i] = (float) embeddingNode.get(i).asDouble();
    }
    
    return embedding;
}
```

#### `injectVectorField(String solrXml, float[] vector)`

Inyecta el campo vector en el documento XML de Solr:

```java
private String injectVectorField(String solrXml, float[] vector) {
    // Convert float array to string representation
    StringBuilder vectorStr = new StringBuilder("[");
    for (int i = 0; i < vector.length; i++) {
        if (i > 0) vectorStr.append(",");
        vectorStr.append(vector[i]);
    }
    vectorStr.append("]");
    
    // Create the field element
    String fieldElement = "<field name=\"" + vectorFieldName + "\">" 
        + vectorStr.toString() + "</field>";
    
    // Insert before </doc>
    int docEndIndex = solrXml.lastIndexOf("</doc>");
    if (docEndIndex != -1) {
        return solrXml.substring(0, docEndIndex) 
            + fieldElement + "\n" 
            + solrXml.substring(docEndIndex);
    }
    
    return solrXml;
}
```

### 5. Modificación del Flujo de Procesamiento

En el método `processRecord()`, se integró la generación de embeddings:

```java
// After XSLT transformation and before sending to Solr:
if (embeddingApiUrl != null && !embeddingApiUrl.isEmpty()) {
    try {
        String textForEmbedding = extractTextForEmbedding(metadata);
        if (textForEmbedding != null && !textForEmbedding.isEmpty()) {
            float[] embedding = generateEmbedding(textForEmbedding);
            solrDoc = injectVectorField(solrDoc, embedding);
            logger.debug("Generated embedding for record: " + record.getId());
        } else {
            logger.warn("No text found for embedding in record: " + record.getId());
        }
    } catch (Exception e) {
        if (skipOnEmbeddingFailure) {
            logger.warn("Failed to generate embedding for record " 
                + record.getId() + ": " + e.getMessage());
        } else {
            throw new RuntimeException("Embedding generation failed", e);
        }
    }
}
```

### 6. Configuración de Spring Beans

Se creó el archivo de configuración:
```
lareferencia-lrharvester-app/config/beans/index.frontend.semantic.xml
```

#### Contenido del archivo:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<beans xmlns="http://www.springframework.org/schema/beans"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.springframework.org/schema/beans
        http://www.springframework.org/schema/beans/spring-beans.xsd">

    <!-- Semantic Indexing Network Action -->
    <bean id="semanticIndexingNetworkAction" 
          class="org.lareferencia.core.worker.NetworkRunWorkerAction" 
          scope="prototype">
        <property name="name" value="SEMANTIC_INDEX_FRONTEND"/>
        <property name="workerBeanName" value="semanticIndexerWorker"/>
    </bean>

    <!-- Semantic Indexer Worker -->
    <bean id="semanticIndexerWorker" 
          class="org.lareferencia.core.worker.indexing.SemanticIndexerWorker" 
          scope="prototype">
        <property name="solrURL" value="${frontend.solr.url}"/>
        <property name="xsltFileName" value="${frontend.indexing.xslt}"/>
        <property name="networkAcronymField" value="${frontend.indexing.network_acronym}"/>
        <property name="embeddingApiUrl" value="${embedding.api.url}"/>
        <property name="sourceFieldForEmbedding" value="dc.title.*"/>
        <property name="vectorFieldName" value="semantic_vector"/>
        <property name="embeddingApiTimeoutSeconds" value="30"/>
        <property name="skipOnEmbeddingFailure" value="true"/>
    </bean>

    <!-- Semantic Delete Action (reuses standard delete worker) -->
    <bean id="semanticDeleteAction" 
          class="org.lareferencia.core.worker.NetworkRunWorkerAction" 
          scope="prototype">
        <property name="name" value="SEMANTIC_DELETE_FRONTEND"/>
        <property name="workerBeanName" value="semanticDeleteWorker"/>
    </bean>

    <!-- Semantic Delete Worker -->
    <bean id="semanticDeleteWorker" 
          class="org.lareferencia.core.worker.indexing.SolrDeleteByQueryWorker" 
          scope="prototype">
        <property name="solrURL" value="${frontend.solr.url}"/>
        <property name="networkAcronymField" value="${frontend.indexing.network_acronym}"/>
    </bean>

</beans>
```

### 7. Integración en actions.xml

Se añadieron importaciones comentadas en `actions.xml`:

```xml
<!-- Semantic Indexer Configuration (uncomment to enable) -->
<!--import resource="index.frontend.semantic.xml" /-->
```

Y referencias a las acciones:
```xml
<!--ref bean="semanticIndexingNetworkAction" /-->
<!--ref bean="semanticDeleteAction" /-->
```

## API de Embeddings

### Contrato de la API

**Request:**
```http
POST /embed HTTP/1.1
Content-Type: application/json

{
    "text": "Título del documento a vectorizar"
}
```

**Response:**
```json
{
    "embedding": [0.123, -0.456, 0.789, ...]  // 768 floats
}
```

### Ejemplo de Implementación (Python/FastAPI)

```python
from fastapi import FastAPI
from sentence_transformers import SentenceTransformer
from pydantic import BaseModel

app = FastAPI()
model = SentenceTransformer('paraphrase-multilingual-MiniLM-L12-v2')

class EmbeddingRequest(BaseModel):
    text: str

@app.post("/embed")
def generate_embedding(request: EmbeddingRequest):
    embedding = model.encode(request.text)
    return {"embedding": embedding.tolist()}
```

## Configuración de Solr

### Schema del Campo Vector

En el esquema de Solr (`schema.xml` o `managed-schema`):

```xml
<fieldType name="knn_vector" 
           class="solr.DenseVectorField" 
           vectorDimension="768" 
           similarityFunction="dot_product"/>

<field name="semantic_vector" 
       type="knn_vector" 
       indexed="true" 
       stored="true"/>
```

## Guía de Despliegue

### 1. Configurar Application Properties

Añadir en el archivo de propiedades de la aplicación:

```properties
# Embedding API Configuration
embedding.api.url=http://localhost:8000/embed
```

### 2. Activar el Indexador Semántico

Descomentar las líneas en `actions.xml`:

```xml
<import resource="index.frontend.semantic.xml" />
```

Y en la lista de acciones:
```xml
<ref bean="semanticIndexingNetworkAction" />
<ref bean="semanticDeleteAction" />
```

### 3. Desplegar Servicio de Embeddings

Iniciar el servicio de embeddings en la URL configurada.

### 4. Configurar Solr

Asegurar que el campo `semantic_vector` esté definido en el esquema del core de Solr.

### 5. Ejecutar Indexación

La acción `SEMANTIC_INDEX_FRONTEND` estará disponible para ser programada o ejecutada manualmente.

## Consultas de Búsqueda Semántica

### Ejemplo en VuFind

```php
$query = '{!knn f=semantic_vector topK=10}' . json_encode($queryVector);
```

### Ejemplo Directo en Solr

```
http://localhost:8983/solr/biblio/select?q={!knn f=semantic_vector topK=10}[0.1,0.2,...]
```

## Consideraciones de Rendimiento

1. **Timeout de API**: El timeout de 30 segundos es configurable. Ajustar según la latencia del servicio de embeddings.

2. **Modo de fallo**: Por defecto, `skipOnEmbeddingFailure=true` permite continuar la indexación si falla la generación de un embedding individual.

3. **Batch Processing**: El worker procesa registros en batches, lo cual es eficiente para la comunicación con Solr pero las llamadas a la API de embeddings son individuales.

4. **Campos de origen**: Por defecto se usa `dc.title.*` pero puede configurarse cualquier campo de metadatos disponible.

## Archivos Modificados/Creados

| Archivo | Operación | Descripción |
|---------|-----------|-------------|
| `lareferencia-core-lib/src/main/java/org/lareferencia/core/worker/indexing/SemanticIndexerWorker.java` | Creado | Nueva clase del worker semántico |
| `lareferencia-lrharvester-app/config/beans/index.frontend.semantic.xml` | Creado | Configuración Spring del indexador |
| `lareferencia-lrharvester-app/config/beans/actions.xml` | Modificado | Añadidas importaciones comentadas |

## Trabajo Futuro

1. **Batch de embeddings**: Implementar llamadas batch a la API de embeddings para mejorar rendimiento.

2. **Cache de embeddings**: Considerar cachear embeddings para evitar regeneración.

3. **Campos adicionales**: Soportar concatenación de múltiples campos (título + resumen).

4. **Modelos configurables**: Permitir especificar el modelo de embedding a usar.

5. **Métricas**: Añadir métricas de tiempo de generación de embeddings y tasa de éxito.

---

*Documento generado: Febrero 2026*
*Versión: 1.0*
