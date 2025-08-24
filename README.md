
# geodata-native-suite (monorepo)

Vereint **Charts**, **Values** (base→platform→env), **RKE2-Deployment** und **DevContainer** in einem Repo.

## Struktur
- `.devcontainer/` – VS Code DevContainer (Docker-from-Docker, kubectl, helm, yq, jq)
- `charts/` – Helm-Charts (Ingress im Chart, cert-manager-ready)
- `values/` – Values-Layer für Apps & Infra (base → platform/{rke2,eks,aks} → env/{dev,stage,prod})
- `deploy/rke2/` – Makefile & TLS/Issuer für RKE2 auf Hetzner (ohne NS-Delegation)

## Quickstart (RKE2/Hetzner)
```bash
# Devcontainer öffnen (optional)
cp deploy/rke2/.env.example deploy/rke2/.env
# .env anpassen: PARENT_ZONE=dburkard.de, BASE=geo.dburkard.de, HETZNER_API_TOKEN=...

cd deploy/rke2
make identity
make dns
make tls
make secrets
make apps
make status
```

## Values-Layering (Helm)
1. `values/<app>/base/values.yaml`
2. `values/<app>/platform/<platform>/values.yaml`
3. `values/<app>/env/<env>/values.yaml`

---

## Repository-Metadaten (Empfehlung)
- **Beschreibung:** Monorepo für GeoData Microservices (STAC Index/Search/Fetch, NGINX Streaming), Helm-Charts & RKE2-Deployment. Micronaut + GraalVM Native.
- **Topics:** `geospatial`, `stac`, `micronaut`, `graalvm`, `native-image`, `kubernetes`, `helm`, `nginx`, `rke2`, `external-dns`, `external-secrets`
