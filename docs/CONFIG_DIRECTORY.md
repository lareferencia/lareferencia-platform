# Configuración Flexible del Directorio Base

## Resumen

La aplicación permite configurar el directorio base de configuración mediante la propiedad de sistema `app.config.dir`. Por defecto, usa el directorio `config` relativo al directorio de trabajo actual.

## Uso

### Línea de Comandos

```bash
# Uso por defecto (directorio ./config)
java -jar lareferencia-shell.jar

# Path relativo personalizado
java -Dapp.config.dir=../shared-config -jar lareferencia-shell.jar

# Path absoluto
java -Dapp.config.dir=/etc/lrharvester/config -jar lareferencia-shell.jar

# Ejemplo Docker
java -Dapp.config.dir=/app/config -jar lareferencia-shell.jar
```

### Verificación

Al iniciar la aplicación, verás en los logs:
```
[ConfigPathResolver] Using config directory: /path/to/config
```

## Estructura del Directorio de Configuración

El directorio de configuración debe contener:

```
${app.config.dir}/
├── application.properties.d/     # Archivos .properties que se cargan automáticamente
│   ├── 01-dbconnection.properties
│   ├── 02-harvester.properties
│   └── ...
├── beans/
│   ├── mdformats.xml            # Configuración de formatos de metadata
│   ├── fingerprint.xml          # Configuración de fingerprinting
│   └── actions.xml              # Acciones (solo lrharvester-app)
├── processes/                    # Definiciones de procesos Flowable BPMN
│   └── *.bpmn20.xml
├── i18n/                         # Mensajes de internacionalización
│   ├── messages.properties
│   └── messages_es.properties
├── users.properties              # Usuarios para autenticación (lrharvester-app)
└── custom-context.xml            # Beans Spring personalizados
```

## Implementación Técnica

### ConfigPathResolver

Clase utilitaria en `lareferencia-core-lib`:

```java
import org.lareferencia.core.util.ConfigPathResolver;

// Obtener el directorio base
String configDir = ConfigPathResolver.getConfigDir();

// Resolver un path relativo al directorio de configuración
String path = ConfigPathResolver.resolve("beans/mdformats.xml");

// Obtener como Path
Path path = ConfigPathResolver.resolvePath("application.properties.d");
```

### Propiedades

| Propiedad | Descripción | Valor por defecto |
|-----------|-------------|-------------------|
| `app.config.dir` | Directorio base de configuración | `config` |
| `security.users.file` | Archivo de usuarios (relativo o absoluto) | `config/users.properties` |

## Casos de Uso

### Desarrollo Local

```bash
# Usar configuración local (directorio por defecto)
java -jar lareferencia-shell.jar
```

### Múltiples Instancias

```bash
# Instancia 1
java -Dapp.config.dir=/opt/lrharvester/instance1/config -jar app.jar

# Instancia 2
java -Dapp.config.dir=/opt/lrharvester/instance2/config -jar app.jar
```

### Docker

```dockerfile
FROM eclipse-temurin:21-jre

WORKDIR /app
COPY target/lareferencia-*.jar app.jar
COPY config /app/config

ENTRYPOINT ["java", "-Dapp.config.dir=/app/config", "-jar", "app.jar"]
```

### Docker Compose con Volume

```yaml
services:
  lrharvester:
    image: lrharvester:latest
    environment:
      - JAVA_OPTS=-Dapp.config.dir=/config
    volumes:
      - ./my-config:/config:ro
```

### Kubernetes ConfigMap

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: lrharvester
spec:
  containers:
  - name: app
    image: lrharvester:latest
    env:
    - name: JAVA_OPTS
      value: "-Dapp.config.dir=/config"
    volumeMounts:
    - name: config-volume
      mountPath: /config
  volumes:
  - name: config-volume
    configMap:
      name: lrharvester-config
```

## Compatibilidad

Esta característica es compatible con:
- `lareferencia-shell`
- `lareferencia-lrharvester-app`

## Notas Importantes

1. **El directorio debe existir** - La aplicación no crea el directorio automáticamente
2. **Permisos** - El usuario que ejecuta la aplicación debe tener permisos de lectura
3. **Paths relativos** - Se resuelven relativos al directorio de trabajo (CWD)
4. **Prioridad** - La propiedad de sistema tiene prioridad sobre cualquier otro valor
