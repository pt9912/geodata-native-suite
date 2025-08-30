# Stage 1: Build (Debian)
FROM python:3.11-slim AS builder
WORKDIR /app
ENV PYTHONUNBUFFERED=1

# Installiere Build-Tools für confluent-kafka
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    gcc \
    g++ \
    python3-dev \
    librdkafka-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt ./
RUN pip install --user --upgrade pip && \
    pip install --user --no-cache-dir -r requirements.txt && \
    pip install --user mypy

    
# Stage 2: Runtime (Debian)
FROM python:3.11-slim
WORKDIR /app
ENV PYTHONUNBUFFERED=1

# Installiere Runtime-Abhängigkeiten für confluent-kafka
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    librdkafka1 \
    && rm -rf /var/lib/apt/lists/*

# Kopiere Python-Pakete in ein systemweites Verzeichnis (z. B. /usr/local)
RUN mkdir -p /usr/local/confluent_kafka
COPY --from=builder /root/.local /usr/local
ENV PATH=/usr/local/bin:$PATH

# Metadata-Labels
LABEL maintainer="dietmar.burkard@burkard.org" \
      version="1.0" \
      description="STAC Index-Service für Sentinel-Daten (Debian)"

# Security: Systemuser erstellen
RUN useradd -m appuser
WORKDIR /app
RUN chown -R appuser:appuser /app /usr/local/confluent_kafka
USER appuser

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s \
    CMD curl -f http://localhost:8000/health || exit 1

# Kopiere den App-Code
COPY --chown=appuser:appuser app/ ./app/
COPY --chown=appuser:appuser config/ ./config/
COPY --chown=appuser:appuser entrypoint.sh ./

#RUN mypy ./app/

RUN chmod +x /app/entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/app/entrypoint.sh"]
