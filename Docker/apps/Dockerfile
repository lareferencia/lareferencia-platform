FROM maven:3.9.11-eclipse-temurin-17

ENV MAVEN_OPTS="-Dmaven.repo.local=/root/.m2/repository"

WORKDIR /workspace

COPY Docker/apps/entrypoint.sh /usr/local/bin/lr-app-entrypoint.sh
RUN chmod +x /usr/local/bin/lr-app-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/lr-app-entrypoint.sh"]
