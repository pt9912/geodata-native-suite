# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- PostGIS/SpatiaLite Query-Layer für `search-service` (ST_Intersects, Zeitfilter) – *in Arbeit*
- Volltextsuche (GIN/TSVECTOR) – *geplant*
- OTel OTLP Exporter aktivieren (Tracing/Metrics) – *geplant*
- Strikte Avro-Schema-Validierung gegen Schema Registry – *geplant*

### Changed
- Helm Values: Plattform-spezifische Defaults (RKE2/EKS/AKS) weiter harmonisieren – *geplant*

### Fixed
- **search-service**: BOM auf `io.micronaut:micronaut-core-bom:${micronautVersion}` umgestellt.
- **search-service**: Micronaut auf 4.9.10 angehoben (Gradle `micronaut { version }`).
- **search-service**: Build-Abhängigkeiten stabilisiert (Micronaut BOM eingebunden).
- **search-service-native**: GraalVM BASE_IMAGE robust gemacht (Default + Workflow-Probe).
- **CI**: Diagnose-Step „Workflow file line count“ gehärtet (continue-on-error, kein Abbruch mehr).
- **index-service**: boto3/botocore Pins (1.34.131) für Kompatibilität mit aioboto3 gesetzt.
- **fetch-service**: Abhängigkeitskonflikt boto3/aioboto3/botocore behoben, Pin auf botocore=1.34.131 (boto3=1.34.131).
- NGINX Cache-Invalidierung für re-verarbeitete Ergebnisse – *geplant*

---

## [geodata-3-patch-v1] - 2025-08-24
### Added
- **search-service (Java/Micronaut)**: STAC `/api/v1/search` (POST) mit Filterobjekt (`bbox`, `datetime`, `collections`, `intersects`, `q`), **BBox-Reprojektion** `EPSG:3857 → EPSG:4326`.
- **index-service (FastAPI + Celery + APScheduler)**: S3 **Prefix-Listing** (inkl. *Requester-Pays*), minimale **STAC-Ableitung**, **Kafka-Events** (Stub, JSON → Confluent-Kafka optional), **Retry & DLQ** via Redis, periodische Läufe via Cron.
- **fetch-service (FastAPI)**: Wahlweise **Presigned-URL** *oder* **X-Accel-Redirect** (NGINX Offloading), **Bucket-Whitelist** via YAML-Config.
- **nginx-stream**: internes Ziel `/internal/s3/...` für X-Accel-Redirect + Slice-Cache.
- **deploy/rke2**: Beispiel-Override `dev-tags-geodata-3.yaml` (Image-Tag = Branch `geodata-3`).

### Notes
- ENV: `REQUEST_PAYER=requester` (Requester-Pays), `FETCH_MODE=presigned|accel`, `ALLOWED_BUCKETS_FILE`, `INDEX_CONFIG`, `KAFKA_BOOTSTRAP_SERVERS`.
- Die eigentlichen DB-Queries (PostGIS/SpatiaLite) für `search-service` sind noch Stub und folgen in einem separaten Patch.

---

## [ci-upgrade-v1] - 2025-08-24
### Added
- **GitHub Actions**: Matrix-Build & Push nach **GHCR** für alle Services:
  - `search-service-jvm` (JVM Fat-Jar)
  - `search-service-native` (GraalVM Native)
  - `index-service` (Python)
  - `fetch-service` (Python)
  - `fetch-worker` (Celery)
  - `nginx-stream` (NGINX)
- Lokales Helper-Script `scripts/ci/build_matrix.sh`.

### Changed
- `services/search-service` erhält **Dockerfile.jvm** und **Dockerfile.native** (getrennte Pfade).

---

## [monorepo-v2-with-services] - 2025-08-24
### Added
- **Monorepo** erweitert um Service-Quellcode:
  - `services/search-service` (Java/Micronaut)
  - `services/index-service` (FastAPI)
  - `services/fetch-service` (FastAPI + Celery)
  - `services/nginx-stream` (NGINX)

---

## [license-apache-2.0] - 2025-08-24
### Added
- **Apache-2.0** als Projektslizenz (LICENSE + NOTICE im Root und in jedem Helm-Chart).
- Helm `Chart.yaml` mit `annotations.licenses: Apache-2.0` ergänzt.
