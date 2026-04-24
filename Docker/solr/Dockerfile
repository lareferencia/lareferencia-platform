FROM solr:9.8.0

USER root

# Install wget
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

# Copy local assets from Docker context (synced by docker.sh)
COPY Docker/solr/cores /opt/lr-solr-cores
COPY Docker/solr/jars /opt/lr-solr-jars
COPY Docker/solr/import /opt/lr-solr-import
COPY Docker/solr/entrypoint.sh /usr/local/bin/lr-solr-entrypoint.sh

# Ensure folders exist
RUN mkdir -p /opt/lr-solr-jars /opt/lr-solr-import /opt/lr-solr-vendor

# Download VuFind specific jars from official master branch
RUN wget -O /opt/lr-solr-jars/MarcImporter.jar https://raw.githubusercontent.com/vufind-org/vufind/master/solr/vufind/jars/MarcImporter.jar && \
    wget -O /opt/lr-solr-jars/browse-handler.jar https://raw.githubusercontent.com/vufind-org/vufind/master/solr/vufind/jars/browse-handler.jar && \
    wget -O /opt/lr-solr-jars/sqlite-jdbc-3.39.3.0.jar https://raw.githubusercontent.com/vufind-org/vufind/master/solr/vufind/jars/sqlite-jdbc-3.39.3.0.jar

# If ICU jars are available in the host, they should be in Docker/solr/vendor/ 
# Using wildcards directly in COPY is valid. 
# We copy them into a temporary folder first to avoid build failure if they don't exist
COPY Docker/solr/ven[d]or/icu4j-*.jar /opt/lr-solr-vendor/
COPY Docker/solr/ven[d]or/lucene-analysis-icu-*.jar /opt/lr-solr-vendor/

RUN chmod +x /usr/local/bin/lr-solr-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/lr-solr-entrypoint.sh"]
