#!/usr/bin/env bash
set -euo pipefail
echo ">> postCreate: verifying tools"
kubectl version --client=true --output=yaml || true
helm version || true
yq --version || true
jq --version || true
docker version || true
echo ">> postCreate: done"
