# Configuración del Indexador Elasticsearch/OpenSearch

**Status:** current · **Last verified:** 2026-09-23

Este documento describe las propiedades de configuración externalizadas para `JSONElasticEntityIndexerThreadedImpl` (`lareferencia-entity-lib`). Para la descripción de la arquitectura de indexación actual (pool fijo de threads, semáforo de backpressure, transacciones read-only `REQUIRES_NEW` y circuit breaker), ver [`ENTITY_INDEXING_ARCHITECTURE.md`](ENTITY_INDEXING_ARCHITECTURE.md).

> **Corrección 2026-09-23:** la versión anterior de este documento describía el pipeline *buffer → distribuidor → writers* (eliminado en el commit `1b894e7`) y sus propiedades `elastic.indexer.writer.threads`, `elastic.indexer.buffer.size`, `elastic.indexer.monitoring.interval.seconds` y el bloque DLQ (`elastic.indexer.dlq.*`, `reprocessDeadLetterQueue`). Ninguna de esas propiedades se lee en el código actual (no hay `@Value` asociado) y fueron retiradas de este documento. El análisis del pipeline eliminado está en [`archive/ANALISIS_INDEXACION_MULTITHREAD.md`](archive/ANALISIS_INDEXACION_MULTITHREAD.md).

## Propiedades de configuración

### Conexión a Elasticsearch

```properties
# Host del servidor Elasticsearch/OpenSearch
elastic.host=localhost

# Puerto del servidor
elastic.port=9200

# Usuario y contraseña para autenticación
elastic.username=admin
elastic.password=admin

# Usar SSL para la conexión
elastic.useSSL=false

# Activar autenticación
elastic.authenticate=false
```

### Indexación

```properties
# Tareas concurrentes máximas (0 = auto-calcular: threads * 2)
# Controla cuántas tareas de indexación pueden ejecutarse simultáneamente
elastic.indexer.max.concurrent.tasks=0

# Número máximo de reintentos para operaciones fallidas (default: 10)
# Aumentar si hay problemas de red intermitentes
elastic.indexer.max.retries=10
```

El pool de threads del indexador es fijo (`availableProcessors`); no es configurable por propiedades. El backpressure se controla con un `Semaphore` y la concurrencia efectiva con `max.concurrent.tasks`.

### Circuit Breaker

El circuit breaker protege el sistema contra fallos en cascada cuando Elasticsearch no está disponible.

```properties
# Número de fallos consecutivos antes de abrir el circuit breaker (default: 10)
elastic.indexer.circuit.breaker.max.failures=10

# Tiempo de espera antes de reintentar después de abrir el circuit breaker (ms, default: 60000)
elastic.indexer.circuit.breaker.reset.timeout.ms=60000
```

**Comportamiento:**

1. Tras `max.failures` fallos consecutivos, el circuit breaker se **abre**
2. Durante el estado OPEN, las operaciones fallan inmediatamente (fail-fast)
3. Después de `reset.timeout.ms`, el circuit breaker permite un intento de **recuperación** (half-open)
4. Una operación exitosa cierra el circuit breaker inmediatamente

## Ejemplo de configuración

```properties
# Producción
elastic.host=es-cluster.example.com
elastic.port=9200
elastic.username=prod_user
elastic.password=secure_password
elastic.useSSL=true
elastic.authenticate=true
elastic.indexer.max.concurrent.tasks=24
elastic.indexer.max.retries=15
elastic.indexer.circuit.breaker.max.failures=15
elastic.indexer.circuit.breaker.reset.timeout.ms=120000

# Desarrollo
elastic.host=localhost
elastic.port=9200
elastic.username=admin
elastic.password=admin
elastic.useSSL=false
elastic.authenticate=false
```

## Monitoreo

Cada ciclo de indexación imprime un bloque `=== INDEXING STATUS REPORT ===` en el log con los contadores de documentos producidos/leídos/indexados/fallidos, el estado del circuit breaker y las estadísticas de reintentos.

Alertas en el log:

1. **Documentos fallidos permanentes**: `Documents failed permanently: 42`
2. **Circuit breaker abierto**: `[CIRCUIT BREAKER] OPENED after 10 consecutive failures...`

## Mejores prácticas

1. **Max concurrent tasks**: el valor auto (`0`) usa `threads * 2` (threads = `availableProcessors`); ajustar solo si el cluster de Elasticsearch muestra presión
2. **Circuit breaker**: en producción, usar valores altos (`max.failures` ≥ 10) para evitar falsos positivos con reinicios breves de Elasticsearch
3. **Max retries**: balancear entre resiliencia y latencia (10 recomendado)
4. **SSL**: si el endpoint usa HTTPS, activar `elastic.useSSL` (y `elastic.authenticate` si aplica)

## Solución de problemas

### Circuit breaker se abre frecuentemente
- Aumentar `elastic.indexer.circuit.breaker.max.failures`
- Aumentar `elastic.indexer.max.retries`
- Verificar salud del cluster Elasticsearch y timeouts de red

### Bajo throughput
- Aumentar `elastic.indexer.max.concurrent.tasks`
- Verificar capacidad del cluster (shards, merging) y latencia de red

### Alto uso de memoria
- El pool es fijo (`availableProcessors`); si hay presión de memoria, reducir workers concurrentes del proceso (no hay buffer configurable en el indexador)