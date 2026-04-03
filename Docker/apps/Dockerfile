# --- Stage 1: Build ---
FROM maven:3.9.11-eclipse-temurin-17 AS builder
WORKDIR /build

# 1. Copiar apenas os POMs para cache de dependências
COPY pom.xml .
COPY lareferencia-core-lib/pom.xml lareferencia-core-lib/
COPY lareferencia-entity-lib/pom.xml lareferencia-entity-lib/
COPY lareferencia-indexing-filters-lib/pom.xml lareferencia-indexing-filters-lib/
COPY lareferencia-shell-entity-plugin/pom.xml lareferencia-shell-entity-plugin/
COPY lareferencia-shell/pom.xml lareferencia-shell/
COPY lareferencia-dark-lib/pom.xml lareferencia-dark-lib/
COPY lareferencia-lrharvester-app/pom.xml lareferencia-lrharvester-app/
COPY lareferencia-entity-rest/pom.xml lareferencia-entity-rest/
COPY lareferencia-dashboard-rest/pom.xml lareferencia-dashboard-rest/
COPY lareferencia-oclc-harvester/pom.xml lareferencia-oclc-harvester/

RUN --mount=type=cache,target=/root/.m2 mvn dependency:go-offline -B

# 2. Build - Forçamos o JAR a NÃO ser executável para permitir a extração de camadas
COPY . .
RUN --mount=type=cache,target=/root/.m2 mvn clean package -DskipTests -Dspring-boot.repackage.executable=false

# 3. Extração das camadas (Modern Spring Boot 3.x)
# Se a extração falhar, usamos o JAR inteiro como fallback no próximo estágio
ARG APP_MODULE
RUN \
    JAR_FILE=$(ls ${APP_MODULE}/target/${APP_MODULE}-*.jar | grep -v ".original" | head -n 1) && \
    java -Djarmode=tools -jar "${JAR_FILE}" extract --layers --launcher --destination extracted/ || \
    (mkdir -p extracted/application && cp "${JAR_FILE}" extracted/application/app.jar)

# --- Stage 2: Runtime ---
FROM bellsoft/liberica-openjre-alpine:17

RUN apk add --no-cache bash sed

WORKDIR /workspace
ARG APP_MODULE
ENV APP_MODULE=${APP_MODULE}

# 4. Copiar as camadas extraídas ou o JAR de fallback
# Usamos o comando 'cp' condicional caso as camadas não existam
COPY --from=builder /build/extracted/ /workspace/${APP_MODULE}/
COPY --from=builder /build/${APP_MODULE}/config /workspace/${APP_MODULE}/config

# Entrypoint
COPY Docker/apps/entrypoint.sh /usr/local/bin/lr-app-entrypoint.sh
RUN chmod +x /usr/local/bin/lr-app-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/lr-app-entrypoint.sh"]
