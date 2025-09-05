#!/usr/bin/env bash
set -euo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
command -v packer >/dev/null || { echo "Packer nicht gefunden"; exit 1; }

packer init .
packer validate .
packer build . | tee build.log

echo "Hinweis: ImageName=... aus der Ausgabe in terraform/terraform.tfvars eintragen."
