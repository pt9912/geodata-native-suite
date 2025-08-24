#!/usr/bin/env bash
set -euo pipefail
REG="ghcr.io"
OWNER="${1:-$USER}"
NS="${OWNER}/geodata-native-suite"
TAG="${2:-dev}"

declare -A matrix=(
  ["search-service-jvm"]="services/search-service Dockerfile.jvm search-service"
  ["search-service-native"]="services/search-service Dockerfile.native search-service-native"
  ["index-service"]="services/index-service Dockerfile index-service"
  ["fetch-service"]="services/fetch-service Dockerfile fetch-service"
  ["fetch-worker"]="services/fetch-service Dockerfile.worker fetch-worker"
  ["nginx-stream"]="services/nginx-stream Dockerfile nginx-stream"
)

for key in "${!matrix[@]}"; do
  read -r ctx file image <<< "${matrix[$key]}"
  echo ">> Building ${image} from ${ctx}/${file}"
  docker build -t "${REG}/${NS}/${image}:${TAG}" -f "${ctx}/${file}" "${ctx}"
done

echo "Done. Push with: docker push --all-tags ${REG}/${NS}/<image>"
