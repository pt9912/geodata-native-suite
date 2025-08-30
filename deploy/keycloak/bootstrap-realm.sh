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

# create realm if not exists
EXISTS=$(eval $KCADM get realms | jq -r '.[].realm' | grep -c -E "^${REALM}$" || true)
if [[ "$EXISTS" -eq 0 ]]; then
  echo ">> Creating realm '$REALM'"
  eval $KCADM create realms -s realm="$REALM" -s enabled=true >/dev/null
else
  echo ">> Realm '$REALM' exists"
fi

: "${REALM_DISPLAY_NAME:=}"
: "${ALLOW_USER_REGISTRATION:=false}"
: "${LOGIN_WITH_EMAIL:=true}"
: "${REQUIRE_EMAIL_VERIFICATION:=true}"

# set general settings
eval $KCADM update realms/"$REALM" \
  -s "displayName=${REALM_DISPLAY_NAME}" \
  -s "registrationAllowed=${ALLOW_USER_REGISTRATION}" \
  -s "loginWithEmailAllowed=${LOGIN_WITH_EMAIL}" \
  -s "verifyEmail=${REQUIRE_EMAIL_VERIFICATION}" \
  -s "eventsEnabled=true" \
  -s "eventsListeners=['jboss-logging']" >/dev/null

# SMTP config
: "${SMTP_HOST:=}"; : "${SMTP_PORT:=587}"; : "${SMTP_FROM:=}"; : "${SMTP_USER:=}"; : "${SMTP_PASSWORD:=}"; : "${SMTP_ENCRYPTION:=starttls}"
if [[ -n "${SMTP_HOST}" && -n "${SMTP_FROM}" ]]; then
  echo ">> Configuring SMTP"
  PROPS=(
    -s "smtpServer.host=${SMTP_HOST}"
    -s "smtpServer.port=${SMTP_PORT}"
    -s "smtpServer.from=${SMTP_FROM}"
    -s "smtpServer.auth=true"
    -s "smtpServer.user=${SMTP_USER}"
    -s "smtpServer.password=${SMTP_PASSWORD}"
  )
  case "${SMTP_ENCRYPTION}" in
    starttls) PROPS+=( -s "smtpServer.starttls=true" ) ;;
    ssl)      PROPS+=( -s "smtpServer.ssl=true" ) ;;
    none)     : ;;
    *)        PROPS+=( -s "smtpServer.starttls=true" ) ;;
  esac
  eval $KCADM update realms/"$REALM" "${PROPS[@]}" >/dev/null
fi

echo "OK: realm bootstrap complete."
