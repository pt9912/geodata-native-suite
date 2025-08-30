
# Keycloak Provisioning v2 – Realm/Clients/Roles/2FA + User Import

Dieses Bundle erweitert v1 um **Realm-/Client-Bootstrap**, **Rollen/Groups**, **Required Actions** und **2FA (TOTP)**.

## Quickstart
```bash
unzip keycloak-user-provision-v2.zip && cd keycloak-user-provision-v2
cp .env.example .env  # anpassen (URL, Realm, SMTP, Redirects, etc.)

# 1) Realm anlegen & konfigurieren (SMTP, Login, Events)
./bootstrap-realm.sh

# 2) Rollen & Gruppen einrichten (+ Default-Rollen/-Gruppen)
./bootstrap-roles-groups.sh

# 3) Clients (UI, API, CLI) anlegen
./bootstrap-clients.sh

# 4) Required Actions aktivieren, 2FA-Policy setzen
./set-required-actions.sh
./enable-2fa.sh

# 5) Benutzer anlegen (einzeln oder CSV)
./create-user.sh -u alice -p 'Secret123!' -e alice@example.org -f Alice -l Example -r 'user,analyst'
./create-users-from-csv.sh users.csv
```

### Hinweise
- Die Skripte sind **idempotent**: Wiederholtes Ausführen aktualisiert Konfiguration/Passwörter/Rollen.
- `kcadm.sh` läuft **im Docker-Container** (offizielles Keycloak-Image). Kein lokales Java nötig.
- SMTP ist wichtig, wenn `REQUIRE_EMAIL_VERIFICATION=true` aktiv ist.
- Clients/Redirects/Web Origins musst du an deine Hosts anpassen.

### Dateien
- `bootstrap-realm.sh` – Realm erstellen, SMTP/Login/Event-Config
- `bootstrap-roles-groups.sh` – Realm-Rollen & Gruppen, Default-Zuweisungen
- `bootstrap-clients.sh` – UI/API/CLI Clients
- `set-required-actions.sh` – Aktiviert Required Actions, konfiguriert Defaults
- `enable-2fa.sh` – OTP-Policy setzen und TOTP als Pflicht erzwingen
- `create-user.sh`, `create-users-from-csv.sh`, `create-user-curl.sh` – wie in v1
- `users.csv` – Beispielimport

**Tipp:** Für `geodata-api` (confidential) werden **Service Accounts** aktiviert; so kannst du Server-2-Server Tokens holen.
