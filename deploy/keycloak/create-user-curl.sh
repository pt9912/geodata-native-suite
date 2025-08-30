#!/usr/bin/env bash
set -euo pipefail
if [[ -f ".env" ]]; then set -a; source .env; set +a; fi
: "${KEYCLOAK_URL:?}"; : "${REALM:?}"; : "${ADMIN_USER:?}"; : "${ADMIN_PASSWORD:?}"
USERNAME=""; PASSWORD=""; EMAIL=""; FIRST=""; LAST="";
while getopts "u:p:e:f:l:h" opt; do case "$opt" in
  u) USERNAME="$OPTARG";; p) PASSWORD="$OPTARG";;
  e) EMAIL="$OPTARG";; f) FIRST="$OPTARG";; l) LAST="$OPTARG";;
  h|*) echo "Usage: $0 -u <username> -p <password> [-e <email>] [-f <first>] [-l <last>]"; exit 1;;
esac; done
[[ -z "$USERNAME" || -z "$PASSWORD" ]] && { echo "missing user/pass"; exit 1; }
TOKEN=$(curl -s -X POST "$KEYCLOAK_URL/realms/master/protocol/openid-connect/token" -H "Content-Type: application/x-www-form-urlencoded" -d "client_id=admin-cli" -d "username=$ADMIN_USER" -d "password=$ADMIN_PASSWORD" -d "grant_type=password" | jq -r .access_token)
[[ -z "$TOKEN" || "$TOKEN" == "null" ]] && { echo "token fail"; exit 1; }
EXISTS=$(curl -s -H "Authorization: Bearer $TOKEN" "$KEYCLOAK_URL/admin/realms/$REALM/users?username=$USERNAME")
if [[ "$(echo "$EXISTS" | jq 'length')" -eq 0 ]]; then
  jq -n --arg u "$USERNAME" --arg e "$EMAIL" --arg f "$FIRST" --arg l "$LAST" '{username:$u,enabled:true} + ( ($e|length)>0 ? {email:$e}:{} ) + ( ($f|length)>0 ? {firstName:$f}:{} ) + ( ($l|length)>0 ? {lastName:$l}:{} )' > /tmp/u.json
  curl -s -o /dev/null -w "%{http_code}\n" -X POST "$KEYCLOAK_URL/admin/realms/$REALM/users" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d @/tmp/u.json | grep -qE "20[0-9]" || { echo "create failed"; exit 1; }
fi
USER_ID=$(curl -s -H "Authorization: Bearer $TOKEN" "$KEYCLOAK_URL/admin/realms/$REALM/users?username=$USERNAME" | jq -r '.[0].id')
curl -s -o /dev/null -w "%{http_code}\n" -X PUT "$KEYCLOAK_URL/admin/realms/$REALM/users/$USER_ID/reset-password" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "{\"type\":\"password\",\"value\":\"$PASSWORD\",\"temporary\":false}" | grep -qE "20[0-9]" || { echo "pwd failed"; exit 1; }
echo "OK: $USERNAME (REST)"
