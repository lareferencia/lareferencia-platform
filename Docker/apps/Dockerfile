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
ARG LR_BUILD_PROFILE
RUN --mount=type=cache,target=/root/.m2 mvn clean package -DskipTests -Dspring-boot.repackage.executable=false -P${LR_BUILD_PROFILE:-lareferencia}

# 3. Extração das camadas (Modern Spring Boot 3.x)
ARG APP_MODULE
RUN \
    JAR_FILE=$(ls ${APP_MODULE}/target/${APP_MODULE}-*.jar | grep -v ".original" | head -n 1) && \
    java -Djarmode=tools -jar "${JAR_FILE}" extract --layers --launcher --destination extracted/ || \
    (mkdir -p extracted/application && cp "${JAR_FILE}" extracted/application/app.jar)

# --- Stage 2: Runtime ---
FROM bellsoft/liberica-openjre-debian:17

RUN apt-get update && apt-get install -y bash sed curl && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
ARG APP_MODULE
ENV APP_MODULE=${APP_MODULE}

# 4. Copiar as camadas extraídas ou o JAR de fallback
COPY --from=builder /build/extracted/ /workspace/${APP_MODULE}/

# 5. Copiar recursos externos (Configurações e Estáticos)
COPY --from=builder /build/${APP_MODULE}/ /tmp/module-files/
RUN mkdir -p /workspace/${APP_MODULE} && \
    if [ -d /tmp/module-files/config ]; then cp -r /tmp/module-files/config /workspace/${APP_MODULE}/; fi && \
    if [ -d /tmp/module-files/static ]; then cp -r /tmp/module-files/static /workspace/${APP_MODULE}/; fi && \
    if [ -d /tmp/module-files/static_en ]; then cp -r /tmp/module-files/static_en /workspace/${APP_MODULE}/; fi && \
    rm -rf /tmp/module-files

# Entrypoint
COPY Docker/apps/entrypoint.sh /usr/local/bin/lr-app-entrypoint.sh
RUN chmod +x /usr/local/bin/lr-app-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/lr-app-entrypoint.sh"]
