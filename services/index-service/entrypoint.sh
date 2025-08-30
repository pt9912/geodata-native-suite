#!/usr/bin/env sh
set -e
if [ "$1" = "api" ] || [ "$#" -eq 0 ]; then
  exec uvicorn app.main:app --host 0.0.0.0 --port 8000
else
  exec "$@"
fi
