
# Heavy but reliable: full GDAL with Python
FROM ubuntu:25.04

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin

# Python deps used by helpers
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    software-properties-common build-essential \
    python3-dev python3-full python3-venv pip python-is-python3 \
    libgdal-dev \
    libsqlite3-mod-spatialite sqlite3 \
    && rm -rf /var/lib/apt/lists/*


RUN python3 -m venv /opt/venv

RUN useradd -ms /bin/bash user1

RUN chown -R user1:user1 /opt/venv

WORKDIR /app

USER user1
RUN /opt/venv/bin/pip install --no-cache-dir boto3==1.40.17 confluent-kafka==2.11.1 python-dateutil==2.9.0.post0

RUN /opt/venv/bin/pip install  gdal==3.10.2
RUN /opt/venv/bin/pip install "numpy>1.0.0" wheel "setuptools>=67"
RUN /opt/venv/bin/pip install --no-cache --force-reinstall gdal[numpy]=="$(gdal-config --version).*"

RUN /opt/venv/bin/pip install attrs==25.3.0 orjson==3.11.2 httpx==0.28.1 cachetools==6.2.0 \
        Authlib==1.6.2 fastavro==1.12.0
RUN /opt/venv/bin/pip install psycopg==3.2.9


COPY gen_geotiff.py /app/
COPY gen_grid_stac.py /app/
COPY upload_s3.py /app/
COPY bulk_index_postgis.py /app/
COPY event_fuzzer.py /app/
COPY spatialite_check.py /app/
COPY bulk_index_spatialite.py /app/

COPY /schemas /schemas

COPY entrypoint.sh /app/
USER root

#RUN apt-get update && apt-get install -y expect

RUN chmod +x /app/entrypoint.sh
#RUN find / -name "*mod*spatialite*" && FALSE
#/usr/lib/x86_64-linux-gnu/mod_spatialite.so
USER user1


ENTRYPOINT ["/app/entrypoint.sh"]

