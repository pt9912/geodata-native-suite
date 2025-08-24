
#!/usr/bin/env bash
set -euo pipefail
ORG="${1:-dburkard}"
SUITE="${2:-geodata-native-suite}"
TAG="${3:-v0.1.0}"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

echo ">> Building search-service (native image)"
docker build -t ghcr.io/$ORG/$SUITE/search-service:$TAG services/search-service

echo ">> Building index-service"
docker build -t ghcr.io/$ORG/$SUITE/index-service:$TAG services/index-service

echo ">> Building fetch-service (api)"
docker build -t ghcr.io/$ORG/$SUITE/fetch-service:$TAG services/fetch-service -f services/fetch-service/Dockerfile

echo ">> Building fetch-worker"
docker build -t ghcr.io/$ORG/$SUITE/fetch-worker:$TAG services/fetch-service -f services/fetch-service/Dockerfile.worker

echo ">> Building nginx-stream"
docker build -t ghcr.io/$ORG/$SUITE/nginx-stream:$TAG services/nginx-stream

echo ">> Done. Use 'docker push' to publish."
