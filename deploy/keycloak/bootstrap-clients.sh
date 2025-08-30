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

# UI (public) client
: "${UI_CLIENT_ID:=geodata-ui}"
: "${UI_REDIRECTS:=http://localhost/*}"
: "${UI_WEB_ORIGINS:=+}"
if ! eval $KCADM get clients -r "$REALM" -q clientId="$UI_CLIENT_ID" | jq -e '.[0]' >/dev/null 2>&1; then
  echo ">> Creating client: $UI_CLIENT_ID (public)"
  eval $KCADM create clients -r "$REALM" \
    -s "clientId=$UI_CLIENT_ID" -s "publicClient=true" -s "standardFlowEnabled=true" \
    -s "redirectUris=['$UI_REDIRECTS']" -s "webOrigins=['$UI_WEB_ORIGINS']" >/dev/null
else
  echo ">> Updating client: $UI_CLIENT_ID"
  CID=$(eval $KCADM get clients -r "$REALM" -q clientId="$UI_CLIENT_ID" | jq -r '.[0].id')
  eval $KCADM update clients/$CID -r "$REALM" \
    -s "redirectUris=['$UI_REDIRECTS']" -s "webOrigins=['$UI_WEB_ORIGINS']" >/dev/null
fi

# API (confidential) client
: "${API_CLIENT_ID:=geodata-api}"
: "${API_BASE_URL:=}"
: "${API_ALLOWED_ORIGINS:=}"
if ! eval $KCADM get clients -r "$REALM" -q clientId="$API_CLIENT_ID" | jq -e '.[0]' >/dev/null 2>&1; then
  echo ">> Creating client: $API_CLIENT_ID (confidential) with service account"
  eval $KCADM create clients -r "$REALM" \
    -s "clientId=$API_CLIENT_ID" -s "publicClient=false" -s "serviceAccountsEnabled=true" \
    -s "standardFlowEnabled=false" -s "directAccessGrantsEnabled=true" \
    -s "baseUrl=$API_BASE_URL" >/dev/null
else
  echo ">> Ensuring service account + baseUrl: $API_CLIENT_ID"
  CID=$(eval $KCADM get clients -r "$REALM" -q clientId="$API_CLIENT_ID" | jq -r '.[0].id')
  eval $KCADM update clients/$CID -r "$REALM" \
    -s "serviceAccountsEnabled=true" -s "baseUrl=$API_BASE_URL" >/dev/null
fi

# CLI (public) client
: "${CLI_CLIENT_ID:=geodata-cli}"
: "${CLI_REDIRECTS:=http://localhost/*}"
if ! eval $KCADM get clients -r "$REALM" -q clientId="$CLI_CLIENT_ID" | jq -e '.[0]' >/dev/null 2>&1; then
  echo ">> Creating client: $CLI_CLIENT_ID (public)"
  eval $KCADM create clients -r "$REALM" \
    -s "clientId=$CLI_CLIENT_ID" -s "publicClient=true" -s "directAccessGrantsEnabled=true" \
    -s "redirectUris=['$CLI_REDIRECTS']" >/dev/null
fi

echo "OK: clients configured."
