
FROM postgis/postgis:14-3.3
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl && rm -rf /var/lib/apt/lists/*
COPY initdb/ /docker-entrypoint-initdb.d/
# Basic archive settings via config fragment
RUN echo "wal_level=replica" >> /usr/share/postgresql/postgresql.conf.sample &&     echo "archive_mode=on" >> /usr/share/postgresql/postgresql.conf.sample &&     echo "archive_timeout=60s" >> /usr/share/postgresql/postgresql.conf.sample &&     echo "max_wal_senders=3" >> /usr/share/postgresql/postgresql.conf.sample &&     echo "archive_command='/bin/sh -c "wal-g wal-push %p"'" >> /usr/share/postgresql/postgresql.conf.sample
