#!/usr/bin/env bash
set -euo pipefail
CSV="${1:-users.csv}"; [[ ! -f "$CSV" ]] && { echo "missing $CSV"; exit 1; }
tail -n +1 "$CSV" | while IFS=, read -r USERNAME EMAIL FIRST LAST PASSWORD ROLES; do
  [[ -z "${USERNAME:-}" ]] && continue
  [[ "$USERNAME" =~ ^# ]] && continue
  if [[ "$USERNAME" == "username" && "$EMAIL" == "email" ]]; then continue; fi
  ./create-user.sh -u "$USERNAME" -p "$PASSWORD" -e "$EMAIL" -f "$FIRST" -l "$LAST" -r "$ROLES"
done
