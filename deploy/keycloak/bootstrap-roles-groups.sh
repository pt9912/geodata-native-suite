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

# roles
: "${EXTRA_ROLES:=}"
if [[ -n "${EXTRA_ROLES}" ]]; then
  IFS=',;' read -ra ROLES <<< "$EXTRA_ROLES"
  for role in "${ROLES[@]}"; do
    role="$(echo "$role" | xargs)"; [[ -z "$role" ]] && continue
    if ! eval $KCADM get roles -r "$REALM" | jq -r '.[].name' | grep -q -E "^${role}$"; then
      echo ">> Creating realm role: $role"
      eval $KCADM create roles -r "$REALM" -s "name=$role" >/dev/null
    fi
  done
fi

# default roles
: "${DEFAULT_ROLES:=}"
if [[ -n "${DEFAULT_ROLES}" ]]; then
  IFS=',;' read -ra DRS <<< "$DEFAULT_ROLES"
  for role in "${DRS[@]}"; do
    role="$(echo "$role" | xargs)"; [[ -z "$role" ]] && continue
    echo ">> Adding default realm role: $role"
    eval $KCADM add-roles -r "$REALM" --target-realm-default-roles --rolename "$role" >/dev/null || true
  done
fi

# groups
: "${GROUPS:=}"
if [[ -n "${GROUPS}" ]]; then
  IFS=',;' read -ra GPS <<< "$GROUPS"
  for g in "${GPS[@]}"; do
    g="$(echo "$g" | xargs)"; [[ -z "$g" ]] && continue
    if [[ $(eval $KCADM get groups -r "$REALM" | jq -r '.[].name' | grep -c -E "^${g}$" || true) -eq 0 ]]; then
      echo ">> Creating group: $g"
      eval $KCADM create groups -r "$REALM" -s "name=$g" >/dev/null
    fi
  done
fi

# default groups
: "${DEFAULT_GROUPS:=}"
if [[ -n "${DEFAULT_GROUPS}" ]]; then
  IFS=',;' read -ra DGS <<< "$DEFAULT_GROUPS"
  for g in "${DGS[@]}"; do
    g="$(echo "$g" | xargs)"; [[ -z "$g" ]] && continue
    echo ">> Marking default group: $g"
    GID=$(eval $KCADM get groups -r "$REALM" | jq -r ".[] | select(.name==\"$g\").id")
    [[ -n "$GID" && "$GID" != "null" ]] && eval $KCADM update "realms/$REALM/default-groups/$GID" -n >/dev/null || true
  done
fi

echo "OK: roles/groups configured."
