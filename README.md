# geodata-native-suite (monorepo)

Vereint **Charts**, **Values** (base→platform→env), **RKE2-Deployment** und **DevContainer** in einem Repo.

## Struktur
- `.devcontainer/` – VS Code DevContainer (Docker-in-Docker, kubectl, helm, yq, jq)
- `charts/` – Helm-Charts (Ingress im Chart, cert-manager-ready)
- `values/` – Values-Layer für Apps & Infra (base → platform/{rke2,eks,aks} → env/{dev,stage,prod})
- `deploy/rke2/` – Makefile & TLS/Issuer für RKE2 auf Hetzner (ohne NS-Delegation)
- `services/` – Quellcode der Microservices (Search, Index, Fetch, NGINX Stream)

---

## Start
```bash
cp .env.example .env
#docker compose -f compose/docker-compose.yml up --build
docker compose -f compose/docker-compose.yml up -d nginxlog-exporter kafka-lag-exporter burrow burrow-exporter prometheus grafana
# Grafana: http://localhost:3000 (admin/admin)

# MinIO Demo-Bucket (optional)
bash scripts/minio-mc-allow.sh
```

## Quickstart Testdaten
```bash
cd tools/data-gen
# 1) Build Generator-Container (GDAL + Python)
docker build -t geodata-datagen .

# 2) 2GB COG erzeugen (1 Band, Float32) und lokal ablegen
mkdir -p ./out
docker run --rm -v $PWD/out:/out geodata-datagen   python /app/gen_geotiff.py --width 32768 --height 32768 --dtype float32 --cog --outfile /out/demo_2gb.tif

# 3) In MinIO hochladen
docker run --rm -v $PWD/out:/data geodata-datagen   python /app/upload_s3.py --endpoint http://minio:9000 --access-key minioadmin --secret-key minioadmin123   --bucket mybucket --prefix test --path /data

# 4) STAC-Items generieren und nach PostGIS einspielen
docker run --rm geodata-datagen   python /app/gen_grid_stac.py --bbox 6.0,49.0,8.0,51.0 --tiles 10,10 --from 2025-08-01 --to 2025-08-31  | docker run -i --rm geodata-datagen python /app/bulk_index_postgis.py --pg postgresql://app:apppw@postgres:5432/geodata

# 5) Kafka-Events simulieren
docker run --rm geodata-datagen   python /app/event_fuzzer.py --bootstrap redpanda:9092 --schema-url http://redpanda:8081 --count 1000
```


## Quickstart (RKE2/Hetzner)
```bash
# Devcontainer öffnen (optional)
cp deploy/rke2/.env.example deploy/rke2/.env
# .env anpassen: PARENT_ZONE=xxxx.de, BASE=geo.xxxx.de, HETZNER_API_TOKEN=...
cd deploy/rke2

#dev
make apps
make status-dev

#prod
make identity
make dns
make tls
make secrets
make apps
make status
```
---

## Values-Layering (Helm)
1. values/<app>/base/values.yaml – Basis-Konfiguration
2. values/<app>/platform/<platform>/values.yaml – Plattform-spezifische Anpassungen (z. B. rke2, eks, aks)
3. values/<app>/env/<env>/values.yaml – Umgebungs-spezifische Anpassungen (z. B. dev, stage, prod)

---

## Repository-Metadaten
- **Beschreibung:** Monorepo für GeoData Microservices (STAC Index/Search/Fetch, NGINX Streaming), Helm-Charts & RKE2-Deployment. Micronaut + GraalVM Native.
- **Topics:** geospatial, stac, micronaut, graalvm, native-image, kubernetes, helm, nginx, rke2, external-dns, external-secrets

---

## Services (Source-in-Repo)

### 1. search-service
- **Technologie:** Java Micronaut (GraalVM Native)
- **Endpunkte:**
  - GET /health – Gesundheitsstatus
  - GET /api/v1/search – STAC-Suche (Query-Parameter: bbox, datetime, collections, limit)
  - POST /api/v1/search – STAC-Suche mit Request-Body (JSON)
- **Beispiel-Request:**
- curl -X GET "http://<HOST>/api/v1/search?bbox=8.5,49.0,8.6,49.1&datetime=2023-01-01/2023-12-31&collections=sentinel-2"

- **Beispiel-Response:**
  { "type": "FeatureCollection", "features": [...] }

### 2. index-service
- **Technologie:** Python FastAPI
- **Funktionen:** S3 Prefix-Listing, STAC-Katalog-Ableitung (in Arbeit)
- **Endpunkte (geplant):**
  - GET /api/v1/index – Liste aller indizierten STAC-Items
  - POST /api/v1/index – Neues STAC-Item hinzufügen

### 3. fetch-service
- **Technologie:** Python FastAPI + Celery Worker
- **Funktionen:** Clipping von Geo-Daten, Erstellung von Cloud-Optimized GeoTIFFs (COG) (in Arbeit)
- **Endpunkte (geplant):**
  - GET /api/v1/fetch – Datenabruf mit Clipping-Parametern
  - POST /api/v1/fetch – Asynchroner Fetch-Job

### 4. nginx-stream
- **Technologie:** NGINX
- **Funktionen:** Offloading-Proxy für Range/Slice-Requests, Caching von Geo-Daten

---

## API-Beschreibung
### Allgemeine Parameter
- bbox: [minLon,minLat,maxLon,maxLat]
- datetime: YYYY-MM-DD/YYYY-MM-DD oder YYYY-MM-DDThh:mm:ssZ/YYYY-MM-DDThh:mm:ssZ
- collections: Komma-separierte Liste von Collections (z. B. sentinel-2,landsat-8)

### Beispiel-API-Aufrufe
#### STAC-Suche

```bash
curl -X GET "http://<HOST>/api/v1/search?bbox=8.5,49.0,8.6,49.1&datetime=2023-01-01/2023-12-31&collections=sentinel-2"
```

#### STAC-Item abrufen
```bash
curl -X GET "http://<HOST>/api/v1/items/<item-id>"
```
#### Daten-Clipping anfordern
```bash
curl -X POST "http://<HOST>/api/v1/fetch" -H "Content-Type: application/json" -d '{
  "url": "s3://bucket/path/to/file.tif",
  "bbox": [8.5, 49.0, 8.6, 49.1],
  "output_format": "COG"
}'
```
---

## Build der Docker-Images
```bash
./scripts/build_images.sh <ORG> <REPO> <TAG>
# Beispiel: ./scripts/build_images.sh org geodata-native-suite v0.1.0
```
---

## Deployment
### RKE2/Hetzner
1. .env anpassen (siehe deploy/rke2/.env.example).
2. Makefile-Targets ausführen (siehe Quickstart).

### Kubernetes (Helm)
```bash
helm upgrade --install <release> charts/<app> --namespace <namespace> --values values/<app>/base/values.yaml --values values/<app>/platform/rke2/values.yaml --values values/<app>/env/prod/values.yaml --set image.tag=v0.1.0
```

---

## Entwicklung
### DevContainer
- VS Code mit Remote-Containers-Erweiterung öffnen.
- Alle Abhängigkeiten (Docker, kubectl, helm) sind vorinstalliert.

### Lokale Entwicklung
# Services lokal starten (Beispiel für search-service)
```
cd services/search-service
./gradlew run
```
---

## Deployment – lokal (k3d) & Hetzner (RKE2)

Diese Distribution bringt zwei Wege zum Testen und Betreiben der Helm-Charts:

### A) Lokal mit k3d (schnelle Iteration)
```bash
./apply.sh local up
./apply.sh charts sync
# -> http://localhost:8080
```
- Startet ein k3d-Cluster (1x Server, 2x Agent), mapped Ports 80/443 auf 8080/8443.
- Eignet sich für schnelles Tuning der Values, Liveness/Readiness, Ingress/Services.

### B) Hetzner mit RKE2 (realitätsnah)
```bash
export HCLOUD_TOKEN=...
./apply.sh hetzner up
./apply.sh kubeconfig print
./apply.sh charts sync <hetzner-context>
```
- Provisioniert Hetzner-Server mit Terraform und installiert RKE2 via Ansible.
- `kubeconfig-hetzner` wird lokal abgelegt; der `print`-Befehl zeigt den Export an.
- Charts werden im Namespace `geodata` deployed.

**Struktur**
- `apply.sh` – Orchestriert lokale & Hetzner-Cluster und Chart-Deployments
- `infra/local/` – k3d Quickstart
- `infra/hetzner/terraform/` – Hetzner-Netz & Nodes (Terraform)
- `infra/hetzner/ansible/` – RKE2 Playbooks/Rollen + `scripts/fetch-kubeconfig.sh`

> Optional: CSI (hcloud-csi), cert-manager und Cilium/Hubble können leicht ergänzt werden.
