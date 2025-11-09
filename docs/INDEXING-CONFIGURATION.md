# Configuración del Indexador Elasticsearch

Este documento describe las propiedades de configuración externalizadas para `JSONElasticEntityIndexerThreadedImpl`.

## Propiedades de Configuración

### Configuración de Elasticsearch

```properties
# Host del servidor Elasticsearch
elastic.host=localhost

# Puerto del servidor Elasticsearch
elastic.port=9200

# Usuario para autenticación
elastic.username=admin

# Contraseña para autenticación
elastic.password=admin

# Usar SSL para la conexión
elastic.useSSL=false

# Activar autenticación
elastic.authenticate=false
```

### Configuración de Threading

```properties
# Número de threads escritores para Elasticsearch (0 = auto-calcular: entre 2 y 6)
# Valor recomendado: 0 (auto) o entre 2-6 para ajuste fino
elastic.indexer.writer.threads=0

# Tamaño del buffer de documentos (default: 10000)
# Incrementar si procesas grandes volúmenes de datos
elastic.indexer.buffer.size=10000

# Tareas concurrentes máximas (0 = auto-calcular: threads * 2)
# Controla cuántas tareas de indexación pueden ejecutarse simultáneamente
elastic.indexer.max.concurrent.tasks=0

# Intervalo de monitoreo en segundos (default: 10)
# Frecuencia con la que se reportan estadísticas en los logs
elastic.indexer.monitoring.interval.seconds=10
```

### Configuración de Reintentos

```properties
# Número máximo de reintentos para operaciones fallidas (default: 10)
# Aumentar si tienes problemas de red intermitentes
elastic.indexer.max.retries=10
```

### Configuración del Circuit Breaker

El Circuit Breaker protege el sistema contra fallos en cascada cuando Elasticsearch no está disponible.

```properties
# Número de fallos consecutivos antes de abrir el circuit breaker (default: 10)
# Valor más bajo = más sensible a fallos
elastic.indexer.circuit.breaker.max.failures=10

# Tiempo de espera antes de reintentar después de abrir el circuit breaker (ms, default: 60000 = 1 minuto)
# Tiempo que el circuit breaker permanece abierto antes de intentar recuperarse
elastic.indexer.circuit.breaker.reset.timeout.ms=60000
```

**Comportamiento del Circuit Breaker:**
1. Tras `max.failures` fallos consecutivos, el circuit breaker se **abre**
2. Durante el estado OPEN, todas las operaciones fallan inmediatamente (fail-fast)
3. Después de `reset.timeout.ms`, el circuit breaker intenta **cerrarse** automáticamente
4. Una operación exitosa cierra el circuit breaker inmediatamente

### Configuración del Dead Letter Queue (DLQ)

El DLQ captura documentos que fallaron permanentemente para permitir su recuperación posterior.

```properties
# Capacidad del Dead Letter Queue (default: 10000)
# Número máximo de documentos fallidos que se pueden almacenar
elastic.indexer.dlq.capacity=10000

# Edad máxima de items en el DLQ en ms (default: 86400000 = 24 horas)
# Items más antiguos serán descartados durante el reprocesamiento
elastic.indexer.dlq.max.age.ms=86400000

# Número máximo de reintentos para items del DLQ (default: 3)
# Items que superan este número de reintentos serán descartados
elastic.indexer.dlq.max.retries=3
```

**Uso del DLQ:**

Los documentos se envían al DLQ cuando:
- El circuit breaker está abierto (Elasticsearch no disponible)
- Se excede el número máximo de reintentos (`max.retries`)

Para reprocesar documentos del DLQ:
```java
indexer.reprocessDeadLetterQueue(100); // Reprocesa hasta 100 documentos
indexer.reprocessDeadLetterQueue(0);   // Reprocesa todos los documentos
```

## Ejemplo de Configuración Completa

### Producción (Alta disponibilidad)

```properties
# Elasticsearch
elastic.host=es-cluster.example.com
elastic.port=9200
elastic.username=prod_user
elastic.password=secure_password
elastic.useSSL=true
elastic.authenticate=true

# Threading (alta concurrencia)
elastic.indexer.writer.threads=6
elastic.indexer.buffer.size=20000
elastic.indexer.max.concurrent.tasks=24
elastic.indexer.monitoring.interval.seconds=30

# Reintentos (agresivos para alta disponibilidad)
elastic.indexer.max.retries=15

# Circuit Breaker (más tolerante en producción)
elastic.indexer.circuit.breaker.max.failures=15
elastic.indexer.circuit.breaker.reset.timeout.ms=120000

# DLQ (mayor capacidad)
elastic.indexer.dlq.capacity=50000
elastic.indexer.dlq.max.age.ms=172800000  # 48 horas
elastic.indexer.dlq.max.retries=5
```

### Desarrollo (Recursos limitados)

```properties
# Elasticsearch
elastic.host=localhost
elastic.port=9200
elastic.username=admin
elastic.password=admin
elastic.useSSL=false
elastic.authenticate=false

# Threading (baja concurrencia)
elastic.indexer.writer.threads=2
elastic.indexer.buffer.size=5000
elastic.indexer.max.concurrent.tasks=4
elastic.indexer.monitoring.interval.seconds=5

# Reintentos (menos agresivos)
elastic.indexer.max.retries=5

# Circuit Breaker (más sensible en desarrollo)
elastic.indexer.circuit.breaker.max.failures=5
elastic.indexer.circuit.breaker.reset.timeout.ms=30000

# DLQ (menor capacidad)
elastic.indexer.dlq.capacity=5000
elastic.indexer.dlq.max.age.ms=43200000  # 12 horas
elastic.indexer.dlq.max.retries=2
```

## Monitoreo

El indexador reporta estadísticas cada `monitoring.interval.seconds`:

```
[STATUS] Buffer: 245/10000 (2.45%). Active Tasks: 3. Slots: 8/24. 
Documents: P:1500, C:1450, I:1420, F:5. 
DLQ: 12/10000 (Sent:15, Reprocessed:3). 
Circuit Breaker: CLOSED (failures: 2/10)
```

**Leyenda:**
- **Buffer**: Documentos en el buffer principal / capacidad
- **Active Tasks**: Tareas de indexación activas
- **Slots**: Slots concurrentes usados / total
- **P**: Documents Produced (producidos)
- **C**: Documents Consumed (consumidos)
- **I**: Documents Indexed (indexados exitosamente)
- **F**: Documents Failed (fallidos permanentemente)
- **DLQ**: Tamaño actual / capacidad (Enviados total, Reprocesados total)
- **Circuit Breaker**: Estado (fallos consecutivos / máximo)

## Alertas Automáticas

El sistema genera automáticamente alertas en los logs:

1. **Buffer lleno (>80%)**: `Buffer usage is high: 87.5%`
2. **Documentos fallidos**: `Documents failed permanently: 42`
3. **DLQ llenándose (>80%)**: `Dead Letter Queue is filling up: 8500/10000 (85.0%). Consider processing DLQ.`
4. **Circuit Breaker abierto**: `[CIRCUIT BREAKER] OPENED after 10 consecutive failures. Elasticsearch operations will be rejected for 60000ms`

## Mejores Prácticas

1. **Buffer Size**: Ajustar según memoria disponible (cada documento ~1-5KB)
2. **Writer Threads**: No exceder el número de nodos Elasticsearch * 2
3. **Circuit Breaker**: En producción, usar valores altos para evitar falsos positivos
4. **DLQ**: Monitorear periódicamente y reprocesar durante ventanas de bajo tráfico
5. **Max Retries**: Balancear entre resiliencia y latencia (10-15 recomendado)

## Solución de Problemas

### DLQ se llena constantemente
- Aumentar `elastic.indexer.dlq.capacity`
- Reducir `elastic.indexer.dlq.max.age.ms` para descartar items antiguos más rápido
- Programar reprocesamiento periódico del DLQ
- Investigar causa raíz de fallos en Elasticsearch

### Circuit Breaker se abre frecuentemente
- Aumentar `elastic.indexer.circuit.breaker.max.failures`
- Aumentar `elastic.indexer.max.retries`
- Verificar salud del cluster Elasticsearch
- Revisar configuración de red/timeouts

### Alto uso de memoria
- Reducir `elastic.indexer.buffer.size`
- Reducir `elastic.indexer.dlq.capacity`
- Reducir `elastic.indexer.max.concurrent.tasks`
- Reducir `elastic.indexer.writer.threads`

### Baja throughput
- Aumentar `elastic.indexer.writer.threads` (máximo 6)
- Aumentar `elastic.indexer.buffer.size`
- Aumentar `elastic.indexer.max.concurrent.tasks`
- Verificar capacidad del cluster Elasticsearch
