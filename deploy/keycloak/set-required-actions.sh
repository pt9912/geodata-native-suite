#!/usr/bin/env bash
set -euo pipefail
if [[ -f ".env" ]]; then set -a; source .env; set +a; fi
: "${KEYCLOAK_URL:?Missing KEYCLOAK_URL}"
: "${REALM:?Missing REALM}"
: "${ADMIN_USER:?Missing ADMIN_USER}"
: "${ADMIN_PASSWORD:?Missing ADMIN_PASSWORD}"
: "${KEYCLOAK_VERSION:=25.0.0}"
KCADM="docker run --rm --network host -v \"$PWD/.kcadm\":/root/.keycloak quay.io/keycloak/keycloak:${KEYCLOAK_VERSION} kcadm.sh"
login() { eval $KCADM config credentials --server \"$KEYCLOAK_URL\" --realm master --user \"$ADMIN_USER\" --password \"$ADMIN_PASSWORD\" >/dev/null; }

login

: "${REQUIRED_ACTIONS:=VERIFY_EMAIL,UPDATE_PASSWORD,CONFIGURE_TOTP}"
IFS=',;' read -ra ACTS <<< "$REQUIRED_ACTIONS"
# Enable built-in actions
for a in "${ACTS[@]}"; do
  a="$(echo "$a" | xargs)"; [[ -z "$a" ]] && continue
  echo ">> Enabling required action: $a"
  eval $KCADM update "authentication/required-actions/$a" -r "$REALM" -s enabled=true >/dev/null || true
done

# Set as default actions for new users
REALM_PATCH=$(jq -n --argjson arr "$(printf '%s\n' "${ACTS[@]}" | jq -R . | jq -s .)" '{defaultRequiredActions:$arr}')
eval $KCADM update realms/"$REALM" -f <(echo "$REALM_PATCH") >/dev/null || true

echo "OK: required actions set."
