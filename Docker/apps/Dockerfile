# --- Stage 1: Build ---
FROM eclipse-temurin:17-jre AS builder
WORKDIR /build

# Copy the pre-compiled JAR directly from the host's build context
ARG APP_MODULE
COPY ${APP_MODULE}/target/${APP_MODULE}-*.jar /tmp/app.jar

# Extração das camadas (Modern Spring Boot 3.x)
RUN \
    java -Djarmode=tools -jar /tmp/app.jar extract --layers --launcher --destination /build/extracted/ || \
    (mkdir -p /build/extracted/application && cp /tmp/app.jar /build/extracted/application/app.jar)

# --- Stage 2: Runtime ---
FROM eclipse-temurin:17-jre

# Minimal tools and gosu
RUN apt-get update && apt-get install -y bash sed curl gosu && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd -r lareferencia && useradd -r -g lareferencia -s /bin/bash -m lareferencia

WORKDIR /workspace
ARG APP_MODULE
ENV APP_MODULE=${APP_MODULE}

# 4. Copiar as camadas extraídas ou o JAR de fallback
COPY --from=builder /build/extracted/ /workspace/${APP_MODULE}/

# 5. Copiar apenas recursos externos necessários do contexto de build
COPY ${APP_MODULE}/confi[g]/ /workspace/${APP_MODULE}/config/
COPY ${APP_MODULE}/stati[c]/ /workspace/${APP_MODULE}/static/
COPY ${APP_MODULE}/static_e[n]/ /workspace/${APP_MODULE}/static_en/

# Ensure application files are owned by lareferencia
RUN chown -R lareferencia:lareferencia /workspace

# Entrypoint
COPY Docker/apps/entrypoint.sh /usr/local/bin/lr-app-entrypoint.sh
RUN chmod +x /usr/local/bin/lr-app-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/lr-app-entrypoint.sh"]
