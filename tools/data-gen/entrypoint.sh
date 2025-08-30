#!/bin/bash
set -euo pipefail

# Virtual Environment aktivieren
source /opt/venv/bin/activate

# Falls keine Argumente übergeben wurden, Standardbefehl ausführen
if [ $# -eq 0 ]; then
    python -V && gdal-config --version
else
    # Ansonsten die übergebenen Argumente ausführen
    exec "$@"
fi
