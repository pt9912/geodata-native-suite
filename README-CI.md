# CI: Build & Push Images

Diese Pipeline baut **alle Service-Images** und pushed sie nach GHCR (`ghcr.io/<owner>/geodata-native-suite/<service>`).

## Tags
- `:<branch>` – pro Branch (z. B. `geodata-2`)
- `:sha-<abcdefg>` – Commit-spezifisch
- `:latest` – nur auf `main`

## Voraussetzungen
- GitHub Repository → Settings → Packages: erlaubt (default ok)
- Kein zusätzliches Secret nötig (nutzt `GITHUB_TOKEN`)

## Services
- `search-service` – 2 Images: `.../search-service` (JVM), `.../search-service-native` (GraalVM)
- `index-service`  – Python FastAPI
- `fetch-service`  – Python FastAPI
- `fetch-worker`   – Celery Worker
- `nginx-stream`   – NGINX Offloading

## Charts/Values
Deploye mit Helm und referenziere Branch-Tag (z. B. `:geodata-2`) oder Release-Tag.
