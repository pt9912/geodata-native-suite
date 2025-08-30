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

: "${OTP_POLICY_ALG:=HmacSHA1}"
: "${OTP_POLICY_DIGITS:=6}"
: "${OTP_POLICY_PERIOD:=30}"
: "${OTP_POLICY_TYPE:=totp}"
: "${ENFORCE_TOTP:=true}"

echo ">> Setting OTP policy"
eval $KCADM update realms/"$REALM" \
  -s "otpPolicyAlgorithm=$OTP_POLICY_ALG" \
  -s "otpPolicyDigits=${OTP_POLICY_DIGITS}" \
  -s "otpPolicyPeriod=${OTP_POLICY_PERIOD}" \
  -s "otpPolicyType=${OTP_POLICY_TYPE}" >/dev/null

if [[ "$ENFORCE_TOTP" == "true" ]]; then
  echo ">> Enforcing CONFIGURE_TOTP as required action"
  eval $KCADM update "authentication/required-actions/CONFIGURE_TOTP" -r "$REALM" -s enabled=true -s defaultAction=true >/dev/null || true
fi

echo "OK: 2FA policy applied."
