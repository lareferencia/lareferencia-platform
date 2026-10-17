FROM solr:9.11.0

USER root

# Install gosu for secure privilege-dropping in entrypoint (solr:9.11.0 is Ubuntu Jammy based)
RUN apt-get update && \
    apt-get install -y --no-install-recommends gosu && \
    rm -rf /var/lib/apt/lists/*

# Copy local assets from Docker context (staged from module checkouts)
COPY Docker/solr/cores /opt/lr-solr-cores
COPY Docker/solr/jars /opt/lr-solr-jars
COPY Docker/solr/import /opt/lr-solr-import
COPY Docker/solr/entrypoint.sh /usr/local/bin/lr-solr-entrypoint.sh

# Ensure folders exist
RUN mkdir -p /opt/lr-solr-jars /opt/lr-solr-import /opt/lr-solr-vendor /var/solr/logs

# If ICU jars are available in the host, they should be in Docker/solr/vendor/ 
COPY Docker/solr/ven[d]or/icu4j-*.jar /opt/lr-solr-vendor/
COPY Docker/solr/ven[d]or/lucene-analysis-icu-*.jar /opt/lr-solr-vendor/

RUN chmod +x /usr/local/bin/lr-solr-entrypoint.sh

# Create log directory and ensure permissions
RUN mkdir -p /var/solr/logs && chown -R solr:solr /var/solr/logs

ENTRYPOINT ["/usr/local/bin/lr-solr-entrypoint.sh"]
