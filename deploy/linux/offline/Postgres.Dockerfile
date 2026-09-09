ARG POSTGRES_RUNTIME_BASE_IMAGE=eclipse-temurin:21.0.11_10-jre

FROM ${POSTGRES_RUNTIME_BASE_IMAGE}

RUN apt-get update \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    postgresql \
    postgresql-client \
  && rm -rf /var/lib/apt/lists/* /var/lib/postgresql/*

COPY deploy/linux/offline/postgres-entrypoint.sh /usr/local/bin/postgres-entrypoint

ENV PGDATA=/var/lib/postgresql/data
VOLUME ["/var/lib/postgresql/data"]
EXPOSE 5432
ENTRYPOINT ["/usr/local/bin/postgres-entrypoint"]
CMD ["postgres"]
