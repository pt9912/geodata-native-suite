#!/usr/bin/env bash
set -euo pipefail
if [[ -f ".env" ]]; then set -a; source .env; set +a; fi
: "${KEYCLOAK_URL:?}"; : "${REALM:?}"; : "${ADMIN_USER:?}"; : "${ADMIN_PASSWORD:?}"
: "${KEYCLOAK_VERSION:=25.0.0}"
KCADM="docker run --rm --network host -v \"$PWD/.kcadm\":/root/.keycloak quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} kcadm.sh"
usage(){ echo "Usage: $0 -u <username> -p <password> [-e <email>] [-f <first>] [-l <last>] [-r <roles>]"; exit 1; }
USERNAME=""; PASSWORD=""; EMAIL=""; FIRST=""; LAST=""; ROLES=""
while getopts "u:p:e:f:l:r:h" opt; do
  case "$opt" in
    u) USERNAME="$OPTARG";; p) PASSWORD="$OPTARG";;
    e) EMAIL="$OPTARG";; f) FIRST="$OPTARG";; l) LAST="$OPTARG";;
    r) ROLES="$OPTARG";; h|*) usage;;
  esac
done
[[ -z "$USERNAME" || -z "$PASSWORD" ]] && usage
eval $KCADM config credentials --server "$KEYCLOAK_URL" --realm master --user "$ADMIN_USER" --password "$ADMIN_PASSWORD" >/dev/null
EXISTS=$((eval $KCADM get users -r "$REALM" -q username="$USERNAME" --fields username | grep -c "\"username\"" ) || true)
if [[ "$EXISTS" -eq 0 ]]; then
  eval $KCADM create users -r "$REALM" -s "username=$USERNAME" -s enabled=true ${EMAIL:+-s email="$EMAIL"} ${FIRST:+-s firstName="$FIRST"} ${LAST:+-s lastName="$LAST"} >/dev/null
fi
eval $KCADM set-password -r "$REALM" --username "$USERNAME" --new-password "$PASSWORD" --temporary=false >/dev/null
if [[ -n "$ROLES" ]]; then
  IFS=',;' read -ra ARR <<< "$ROLES"
  for role in "${ARR[@]}"; do role="$(echo "$role"|xargs)"; [[ -z "$role" ]] && continue; eval $KCADM add-roles -r "$REALM" --uusername "$USERNAME" --rolename "$role" >/dev/null || true; done
fi
echo "OK: $USERNAME"
