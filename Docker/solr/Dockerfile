FROM solr:9.8

USER root

COPY Docker/solr/cores /opt/lr-solr-cores
COPY Docker/solr/jars /opt/lr-solr-jars
COPY Docker/solr/import /opt/lr-solr-import
COPY Docker/solr/entrypoint.sh /usr/local/bin/lr-solr-entrypoint.sh

RUN chmod +x /usr/local/bin/lr-solr-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/lr-solr-entrypoint.sh"]
