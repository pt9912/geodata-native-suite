# GeoData Microservices – Architektur & Anforderungen (Micronaut + GraalVM Native)

## 1. Einleitung

### 1.1 Zweck und Motivation
Das Projekt entwickelt ein **skalierbares Microservice-System** für standardisierten Zugriff auf heterogene Geodatenquellen (Copernicus, NASA, DWD).  

**Aktuelle Probleme:**
- Vielfalt an Provider-APIs (S3, REST, FTP) und Datenformaten (GeoTIFF, NetCDF)
- Performance-Probleme durch Live-Abfragen (>2s Latenz)
- Synchrone CPU-intensive Verarbeitung blockiert API
- Monolithische Architektur begrenzt Skalierung

**Lösungsansatz mit Drei-Services-Architektur:**
1. **index-service**: Vorindexierung der Metadaten in PostGIS/STAC  
2. **search-service**: Schnelle Metadatensuche (STAC-/search, Textsuche, CRS)  
3. **fetch-service**: Verarbeitung und Auslieferung der Daten; Offloading großer Downloads an **NGINX**  

**Datenfluss:**  
Provider → index-service → PostGIS/STAC → search-service → fetch-service → S3/MinIO Cache + **NGINX Streaming** → Client  
(Fallback: fetch-service → Provider bei veralteten Daten)

### 1.2 Zielgruppe und Nutzen
| Zielgruppe          | Hauptnutzen                          | Technische Implikation          |
|---------------------|---------------------------------------|----------------------------------|
| Datenwissenschaftler | Einheitliche Suchschnittstelle       | **STAC-/search**, STAC-API       |
| GIS-Experten        | Standardisierte Verarbeitung         | GDAL-Integration, Worker-Pools  |
| Externe Kunden      | Performance bei großen Datenmengen   | **NGINX Offloading**, Chunked Streaming |
| DevOps-Team         | Skalierbare Deployment-Optionen      | Kubernetes, Docker Compose      |
| Management          | Kostentransparenz                    | Monitoring, Rate-Limiting       |

### 1.3 Architekturprinzipien
1. Trennung der Verantwortlichkeiten in drei Services  
2. Performance durch Vorindexierung und asynchrone Verarbeitung  
3. Skalierbarkeit durch horizontale/vertikale Trennung  
4. Provider-Abstraktion via STAC-Standard und Adapter  
5. **Schnellstartende, ressourceneffiziente Services** via Micronaut + GraalVM Native für Latenz-kritische Pfade
6. **NGINX Offloading** (Range/Resume, Slice-Cache) für Downloads >1GB  
7. **Konfigurierbare S3-Allowlist** + **internes Relay** (Presigned URLs bleiben serverseitig)

---

## 2. Funktionale Anforderungen

### 2.1 Metadaten-Suche (search-service)
| ID   | Anforderung                                        | Priorität |
|------|-----------------------------------------------------|-----------|
| F-01 | BBox + Zeitbereich-Suche (GET `/search/search`)     | Hoch      |
| F-02 | **STAC-konforme Filter** (POST `/stac/search`)      | Hoch      |
| F-03 | **Textsuche `q`** über `id`, `collection`, `props`  | Mittel    |
| F-04 | **CRS-Reprojektion** (`crs=EPSG:<srid>`) für Filter | Hoch      |
| F-05 | Caching mit Redis (TTL: 1h)                         | Mittel    |
| F-06 | Paginierung (limit/offset, `links.next` optional)   | Mittel    |

### 2.2 Geodaten-Zugriff (fetch-service)
| ID   | Anforderung                                         | Priorität |
|------|------------------------------------------------------|-----------|
| F-10 | Synchroner Download via **NGINX** (`X-Accel-Redirect`) | Hoch    |
| F-11 | Asynchrones Clipping/Reprojection via Job-Queue      | Hoch      |
| F-12 | Chunked Streaming (>1GB)                              | Hoch      |
| F-13 | Granulares Caching mit parametrisierten Keys          | Hoch      |
| F-14 | Formatkonvertierung (GeoTIFF→NetCDF/COG)              | Mittel    |
| F-15 | **S3-Allowlist** (konfigurierbar)                     | Hoch      |
| F-16 | **Presigned-URL Relay** (NGINX `/internal/relay`, Signaturen verborgen) | Hoch |

### 2.3 Provider-Integration
| ID   | Anforderung                                  | Priorität |
|------|-----------------------------------------------|-----------|
| F-20 | Sentinel-2 (S3) Integration                   | Hoch      |
| F-21 | NASA Earthdata (EDL Token Handling)           | Hoch      |
| F-22 | DWD Open Data (FTP/HTTP)                      | Mittel    |
| F-23 | STAC-Adapter für nicht-konforme Provider      | Hoch      |
| F-24 | Token-Refresh-Mechanismus für NASA EDL        | Hoch      |
| F-25 | **Requester-Pays** Unterstützung (AWS)        | Mittel    |
| F-26 | **Auto-Region-Detect** für AWS Buckets        | Mittel    |

### 2.4 Datenindexierung (index-service)
| ID   | Anforderung                                          | Priorität |
|------|-------------------------------------------------------|-----------|
| F-40 | Inkrementelle Indexierung mit Delta-Erkennung         | Hoch      |
| F-41 | PostGIS-Partitioning (Collection/Datum)               | Hoch      |
| F-42 | Fehlerresistente Indexierung (Retries, DLQ)           | Hoch      |
| F-43 | Manueller Indexierungs-Trigger                        | Niedrig   |
| F-44 | **Light vs Heavy Profile** (SpatiaLite vs PostGIS)    | Hoch      |

### 2.5 API-Definitionen
- **OpenAPI/Swagger**: REST-Spezifikation für search-service und fetch-service  
- **AsyncAPI**: Events für Job-Status (z. B. Clipping abgeschlossen, Fehler)  
- **Versionierung**: `/api/v1/...`  
- **STAC**: `/stac/search` (POST), `/search/search` (GET), kompatible Filterfelder

### 2.6 Events & Schema Registry
| ID   | Anforderung                                                                 | Priorität |
|------|------------------------------------------------------------------------------|-----------|
| F-60 | Nutzung von Kafka-kompatibler Infrastruktur (z. B. Redpanda, Confluent, Apicurio) | Hoch |
| F-61 | Avro-Schema für STAC-Events (`stac.item.indexed/updated/deleted`)            | Hoch |
| F-62 | JSON Schema für Fetch-Job-Status                                            | Hoch |
| F-63 | AsyncAPI 3.0 als zentrale Event-Spezifikation (mit `$ref` auf Schemas)       | Hoch |
| F-64 | Backward-kompatible Schema-Evolution (`BACKWARD_TRANSITIVE`)                 | Hoch |
| F-65 | Schema-Validierung in CI/CD (PR-Checks gegen Registry)                       | Mittel |
| F-66 | Nutzung von Kafka Headers für Trace-/Span-IDs (statt im Payload)             | Mittel |

---

## 3. Nicht-funktionale Anforderungen

### 3.1 Performance
| ID   | Metrik                                       | Zielwert          |
|------|----------------------------------------------|-------------------|
| NF-01 | Cache-Hit-Rate (Index)                       | ≥80%              |
| NF-02 | Latenz bei Cache-Hit (search-service)        | <200ms (p95)      |
| NF-02b| **Kaltstart search-service (Native)**        | **<100ms**        |
| NF-03 | Max. Fallback-Requests pro Provider          | ≤5 gleichzeitig   |
| NF-04 | 10GB Download-Durchsatz (NGINX Slice Cache)  | ≥10MB/s           |

### 3.2 Skalierbarkeit
| Komponente          | Skalierungsstrategie                                  |
|---------------------|--------------------------------------------------------|
| search-service (Native) | Horizontal, kleine Container (≤256Mi)              |
| fetch-service       | Vertikal + Worker-Pools                                |
| **NGINX-Streaming** | Horizontal, stateless, **Slice-Cache**, Zero-Copy     |
| PostGIS             | Read Replicas + Connection Pooling                     |
| S3/MinIO            | Multi-Part Uploads (5GB/Objekt)                        |

### 3.3 Sicherheit
| ID   | Anforderung                                                                 |
|------|-----------------------------------------------------------------------------|
| NF-30 | JWT Authentifizierung                                                      |
| NF-31 | Keycloak/SSO für interne und externe Clients                               |
| NF-32 | TLS 1.2+ Verschlüsselung                                                  |
| NF-33 | IAM Roles für S3-Zugriff                                                   |
| NF-34 | Secrets Management mit Vault/Kubernetes Secrets                             |
| NF-35 | Rate Limiting & Quotas für externe Kunden                                  |
| NF-36 | **NGINX**: Header-Sanitation, `X-Accel-Redirect` nur intern, **keine** Presigned-URLs nach außen |
| NF-37 | **Allowlist** erzwungen (konfigurierbar, fail-closed)                      |

### 3.4 Daten- und Event-Konsistenz
| ID   | Anforderung                                                                 |
|------|-----------------------------------------------------------------------------|
| NF-40 | Alle Events müssen Schema-Registry-validiert sein                          |
| NF-41 | Kompatibilitätsmodus: `BACKWARD_TRANSITIVE`                                |
| NF-42 | Fehlgeschlagene Event-Validierung → DLQ/Retry                              |
| NF-43 | Event-Provenance: Speicherung von `trace_id` und `provider` in Kafka-Headern |

### 3.5 Ressourcen-Effizienz (Native)
| ID   | Anforderung                                        | Zielwert        |
|------|-----------------------------------------------------|-----------------|
| NF-50| **RSS Memory search-service (Idle)**               | **≤128Mi**      |
| NF-51| **Container Image Size (Native Binary + Distroless)** | **≤150MB**   |

---

## 4. Monitoring & Observability

### 4.1 Monitoring
- **Prometheus**: Sammeln von System- und Applikationsmetriken  
- **Grafana Dashboards**: Visualisierung für Management/DevOps  
- **Alertmanager**: Provider-Ausfälle, Queue-Längen, Cache-Miss-Spitzen  
- **NGINX**: Access/Error Logs, `$upstream_cache_status`, Slice-Hit-Rate, 206-Ratio

### 4.2 Observability
- **OpenTelemetry Tracing** für alle Services (Micronaut-OTel für search-service)  
- **Metriken**:
  - Latenz pro Provider  
  - Cache-Hit-Rate pro Service & **NGINX Slice-Cache**
  - Queue-Längen (Clipping-Jobs)  
  - Durchsatz (MB/s) beim Download  
- **Trace-Propagation**: `traceparent` via HTTP, Kafka-Headers für Events

---

## 5. Technische Anforderungen

### 5.1 Core Stack
| Komponente       | Technologie                                      | Version/Profil         |
|------------------|---------------------------------------------------|------------------------|
| index-service    | Python/FastAPI                                    | Python 3.9             |
| search-service   | **Java/Micronaut (Native Image)**                 | **Micronaut 4.9.2, GraalVM 24.0.2 (JDK 21)** |
| fetch-service    | Python/Celery + Flask (Relay)                     | Python 3.9             |
| Datenbank (Heavy)| **PostGIS/TimescaleDB**                           | PostgreSQL 14          |
| Datenbank (Light)| **SpatiaLite (SQLite)** – *kleine Lösung/Edge*    | Aktuell                |
| Cache            | Redis Cluster                                     | 6                      |
| Storage          | MinIO/Amazon S3                                   | MinIO RELEASE.2025 / AWS S3 |

> **Hinweis:** Search-Service bevorzugt **Native** mit PostGIS; SpatiaLite wird im **JVM-Profil** betrieben (JNI/Extensions).

### 5.2 Deployment-Beispiele

**Docker Compose (On-Premise, Auszug):**
```yaml
services:
  postgis:
    image: postgis/postgis:14
    environment:
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - postgis_data:/var/lib/postgresql/data
  redis:
    image: redis:6
    command: redis-server --cluster-enabled yes
  nginx:
    image: nginx:1.27-alpine
    volumes:
      - nginx_cache:/var/cache/nginx
      - nginx_logs:/var/log/nginx
```

**Kubernetes (Cloud, search-service Native):**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search-service
spec:
  replicas: 4
  template:
    spec:
      containers:
      - name: search
        image: registry/search-service:native-v1
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "256Mi"
        ports:
          - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /health/readiness
            port: 8080
          periodSeconds: 5
          failureThreshold: 3
```

**Container-Build (Search, Native):**
```Dockerfile
# Build: GraalVM 24.0.2 (JDK 21) + Micronaut Native
FROM ghcr.io/graalvm/native-image:ol9-java21-24.0.2 AS build
WORKDIR /work
COPY . .
RUN ./gradlew -x test nativeCompile

FROM gcr.io/distroless/base-nossl:nonroot
WORKDIR /app
COPY --from=build /work/build/native/nativeCompile/search-service /app/search-service
USER nonroot
EXPOSE 8080
ENTRYPOINT ["/app/search-service"]
```

---

## 6. CI/CD Pipeline & DevOps

- **Build Pipeline**: GitHub Actions / GitLab CI  
  - Linting, Tests (JVM-Tests für search-service; Native-Tests selektiv)  
  - **Micronaut AOT + GraalVM Native Build** (für `search-service`)  
  - Docker Build & Push (distroless base), SBOM/Signierung (cosign)  
  - Security Scans (Trivy, Snyk)  
- **Deployment Pipeline**:  
  - Helm Charts für Kubernetes (separate Values für Heavy/Light DB-Profile)  
  - Docker Compose für On-Premise/Edge  
- **Native-Build Hinweise**:  
  - Reflection-Konfiguration minimieren (Micronaut reduziert das automatisch), ggf. `reflect-config.json` für JDBC/Driver hinzufügen  
  - OTel-Instrumentierung über Micronaut-Module (native-fähig)  
- **Deployment-Strategien**:  
  - Blue/Green für kritische Services  
  - Canary Releases für fetch-service  
  - Rollout-Strategie für Native-Images: kleine Replica-Units, schnelles Scale-out

---

## 7. Datenfluss-Diagramme

### 7.1 Standard-Ablauf
1. Client → search-service: Suche (BBox/CRS/Text)  
2. search-service → PostGIS/SpatiaLite: STAC Query  
3. DB → search-service: Ergebnisse  
4. Client → fetch-service: Download (Dataset-ID)  
5. fetch-service → S3: Cache Check & **Presigned-URL-Erzeugung**  
   - **Internes Relay**: fetch-service → NGINX `/internal/relay` (Signaturen bleiben verborgen)  
6. **NGINX streamt** die Daten an den Client (Range/Resume, Slice-Cache)  

### 7.2 Asynchrone Verarbeitung
1. Client → fetch-service: Clipping Job anfordern  
2. fetch-service → Queue: Job einreihen  
3. fetch-service → Client: Job-ID zurück (202 Accepted)  
4. Worker → S3: Ergebnis speichern  
5. Client → fetch-service: Job-Status abfragen  
6. fetch-service → S3/NGINX: Ergebnis-URL liefern  
7. **NGINX** liefert das Ergebnis über internes Relay/Cache aus  

---

## 8. Abnahmekriterien & Tests

### 8.1 Funktionstests
| ID   | Testfall                                                |
|------|---------------------------------------------------------|
| FT-01 | BBox-Suche mit 10.000 Datensätzen (<200ms)             |
| FT-01b| **Kaltstart search-service (Native) <100ms**           |
| FT-02 | 10GB GeoTIFF Download (Chunked Transfer via NGINX)     |
| FT-03 | Asynchrones Clipping (Job-ID Rückgabe)                 |
| FT-04 | Provider-Fallback bei veraltetem Index (max. 5 Requests)|
| FT-05 | **STAC `/stac/search` POST** mit `bbox/intersects`     |
| FT-06 | **CRS-Reprojektion** (EPSG:3857 → 4326) korrekt        |
| FT-07 | **Allowlist** blockiert nicht freigegebene Buckets (403)|

### 8.2 Lasttests
| ID   | Szenario                                      | Zielwert          |
|------|-----------------------------------------------|-------------------|
| PT-01 | 100 parallele Suchanfragen                    | <1s p95           |
| PT-02 | 10 gleichzeitige 5GB-Downloads                | ≥10MB/s           |
| PT-03 | 50 Clipping-Jobs                              | <5min p90         |
| PT-04 | NGINX Slice-Cache: ≥70% Hit-Rate bei Re-Downloads | Zielwert       |

### 8.3 Testdaten & Reproduzierbarkeit
- **Synthetic Datasets**: Generierte 10GB GeoTIFFs mit GDAL/Rasterio  
- **Replay-Tests**: Provider-Abfragen gespeichert und reproduzierbar  
- **Konfig-Test**: Allowlist/Region-Detect/Requester-Pays systematisch prüfen

---

## 9. Archivierung & Retention

- **S3 Lifecycle Policies**: automatische Archivierung nach Glacier nach 90 Tagen  
- **On-Premise**: Tiered Storage (NVMe Cache → HDD → Tape)  
- **Retention Policies**: konfigurierbar pro Collection / Provider  
- **Kostenoptimierung**: Monitoring von Speicherkosten pro Tier  

---

## 10. Offene Punkte & Risiken
| ID   | Risiko                                                | Lösungsidee                          |
|------|-------------------------------------------------------|--------------------------------------|
| R-01 | PostGIS-Skalierung bei >1 Mrd. Datensätzen            | TimescaleDB/Partitioning             |
| R-02 | Cache-Explosion durch Parameter-Kombis                | TTL-Staffelung + manuelle Bereinigung|
| R-03 | Fallback-Sturm auf Provider                           | Circuit Breaker (5 Requests)         |
| R-04 | On-Premise Limits bei >10TB                           | Hybrid Cloud Storage                 |
| R-05 | **Native-Build-Zeit/CI-Runtime**                      | Caching von GraalVM/Gradle, Artefakt-Reuse |
| R-06 | **Reflection/Driver-Probleme im Native**              | Micronaut-Data/JDBC geprüfte Treiber |
| R-07 | **NGINX Cache-Invalidierung** bei Reprocessing        | Key-Design + Event-basierte PURGE    |
| R-08 | **S3-Signaturen**/Uhrzeitdrift                        | NTP strickt; kurze TTL; 401 → Re-Sign|
| R-09 | **SpatiaLite nur „kleine Lösung“**                    | JVM-Profil; Heavy = PostGIS (Native) |

---

## 11. Zusammenfassung
Die Architektur definiert drei Kern-Services (index, search, fetch) und ergänzt diese durch **NGINX** als Streaming-Front mit internem Relay.  
Der search-service unterstützt **STAC-/search (POST)**, **Textsuche** und **CRS-Reprojektion**; **SpatiaLite** dient als *kleine Lösung* (JVM), **PostGIS** als Heavy-Variante (Native).  
S3-Zugriffe sind über **Allowlist** abgesichert, Presigned-URLs bleiben intern.  
Nicht-funktionale Anforderungen (Performance, Sicherheit, Observability, CI/CD) und Tests sind konkretisiert; Risiken (Skalierung, Native, Cache-Invalidierung) sind adressiert.
