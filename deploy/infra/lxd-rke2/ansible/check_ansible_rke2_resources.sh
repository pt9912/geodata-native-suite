#!/bin/bash
# Ansible + RKE2 Ressourcen-Check für LXD-VMs (mit Kubernetes-Checks vom Host)
# Nutzung: ./check_ansible_rke2_resources_lxd_final.sh <VM-Name> [SSH-Benutzer] [IP-Adresse]

set -uo pipefail

# Argumente
VM_NAME=$1
SSH_USER=${2:-"ubuntu"}  # Standard-Benutzer für cloud-init (Ubuntu-Images)
IP_ADDRESS=${3:-""}      # Optional: Manuelle IP-Adresse

# Parametrisierbare Defaults (können per Env überschrieben werden)
: "${ANSIBLE_LOG_PATH:=/var/log/ansible.log}"
: "${ANSIBLE_LOG_AUTOSETUP:=false}"              # true => Logdatei auf der VM anlegen
: "${PLAYBOOK_PATH:=}"                           # leer => auto-detect
: "${RKE2_UNIT:=rke2-server}"
: "${RKE2_LOG_SINCE:=1h}"                 # z.B. 30m, 2h, yesterday
: "${KUBECONFIG:=$HOME/.kube/config}"     # Host-Kubeconfig
: "${KUBE_CONTEXT:=}"                     # optionaler Kontextname
: "${INVENTORY_PATH:=}"   # optional: Pfad zum Inventory; leer => Auto-Detect

# Farbcodes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color




# Globale SSH-Optionen
SSH_OPTIONS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR -o BatchMode=yes"

# Wrapper für optionalen --context
KCTX_ARG=()
[ -n "$KUBE_CONTEXT" ] && KCTX_ARG=(--context "$KUBE_CONTEXT")

# Funktion zur Fehlerbehandlung für SSH-Befehle
ssh_exec() {
    local cmd=$1
    ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "$cmd" 2>/dev/null || echo ""
}

# 1. Prüfe, ob LXD läuft
check_lxd() {
    echo -e "${BLUE}=== 0. LXD-Status ===${NC}"
    if ! command -v lxc &> /dev/null; then
        echo -e "${RED}✗ FEHLER: LXD/lxc ist nicht installiert.${NC}"
        echo -e "${YELLOW}→ Installiere LXD mit: sudo snap install lxd${NC}"
        exit 1
    fi

    if snap list | grep -q lxd; then
        LXD_STATUS=$(snap services lxd | awk '/lxd\.daemon/ {print $3}' | tr '[:upper:]' '[:lower:]')
        if [[ "$LXD_STATUS" != "active" && "$LXD_STATUS" != "aktiv" ]]; then
            echo -e "${RED}✗ FEHLER: LXD-Daemon läuft nicht (Status: $LXD_STATUS).${NC}"
            echo -e "${YELLOW}→ Versuche, LXD zu starten: sudo snap start lxd${NC}"
            exit 1
        fi
    fi
    echo -e "${GREEN}✓ LXD-Daemon läuft.${NC}"
}

# 2. IP-Adresse der VM ermitteln (mit JSON und allen Interfaces)
get_ip_address() {
    if [ -z "$IP_ADDRESS" ]; then
        echo -e "${BLUE}\n=== 1. IP-Adresse ===${NC}"
        IP_ADDRESS=$(lxc list --format json 2>/dev/null \
            | jq -r --arg name "$VM_NAME" '.[] | select(.name == $name) | .state.network
              | to_entries[] | .value.addresses[] | select(.family == "inet") | .address' \
            | grep -Eo '10\.0\.[0-9]+\.[0-9]+')

        if [ -z "$IP_ADDRESS" ]; then
            echo -e "${YELLOW}⚠ WARNUNG: IP-Adresse konnte nicht automatisch ermittelt werden.${NC}"
            echo -e "${YELLOW}→ Versuche, die IP über DHCP-Leases zu ermitteln...${NC}"
            NETWORK_NAME=$(lxc network list | awk 'NR>3 && $1!="+" {print $2}' | head -n 1)
            IP_ADDRESS=$(lxc network list-leases "$NETWORK_NAME" 2>/dev/null \
                | awk -v vm="$VM_NAME" '$0 ~ vm {print $3}' \
                | grep -Eo '10\.0\.[0-9]+\.[0-9]+')
        fi

        if [ -z "$IP_ADDRESS" ]; then
            echo -e "${RED}✗ FEHLER: IP-Adresse der VM '$VM_NAME' konnte nicht ermittelt werden.${NC}"
            echo -e "${YELLOW}→ IP-Adresse manuell angeben: $0 $VM_NAME $SSH_USER <IP-Adresse>${NC}"
            exit 1
        else
            echo -e "${GREEN}✓ IP-Adresse: $IP_ADDRESS${NC}"
            export IP_ADDRESS
        fi
    fi
}

# 3. Netzwerkverbindung testen (Port 22 statt Ping)
test_network() {
    echo -e "${BLUE}\n=== 2. Netzwerktest ===${NC}"
    if ! timeout 2 bash -c "echo > /dev/tcp/$IP_ADDRESS/22" 2>/dev/null; then
        echo -e "${RED}✗ FEHLER: VM ist nicht über das Netzwerk erreichbar (Port 22 nicht offen).${NC}"
        echo -e "${YELLOW}→ Prüfe:"
        echo "  - Firewall-Regeln auf Host und VM."
        echo "  - Netzwerkinterface der VM (lxc exec $VM_NAME -- ip a)."
        echo "  - Routing-Tabelle (ip route)."
        echo "  - SSH-Dienst in der VM (systemctl status ssh)."
        exit 1
    else
        echo -e "${GREEN}✓ VM ist über das Netzwerk erreichbar (Port 22 offen).${NC}"
    fi
}

# 4. SSH-Verbindung testen
test_ssh() {
    echo -e "${BLUE}\n=== 3. SSH-Verbindung ===${NC}"
    if ! ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "echo 'SSH funktioniert'" &>/dev/null; then
        echo -e "${RED}✗ FEHLER: SSH-Verbindung fehlgeschlagen.${NC}"
        echo -e "${YELLOW}→ Prüfe:"
        echo "  - Wurde der SSH-Schlüssel von cloud-init korrekt injiziert?"
        echo "  - Läuft der SSH-Dienst in der VM? (systemctl status ssh)"
        echo "  - Ist der Benutzer '$SSH_USER' in der VM vorhanden?"
        echo "  - Firewall-Regeln auf Host und VM?"
        exit 1
    else
        echo -e "${GREEN}✓ SSH-Verbindung erfolgreich.${NC}"
    fi
}

# 5. VM-Ressourcen prüfen (Speicher, CPU, Festplatte)
check_vm_resources() {
    echo -e "${BLUE}\n=== 4. VM-Ressourcen ===${NC}"
    # Speicher
    MEM_TOTAL=$(ssh_exec "free -m | awk '/Mem:/ {print \$2}'")
    MEM_AVAIL=$(ssh_exec "free -m | awk '/Mem:/ {print \$7}'")
    if [[ -z "$MEM_TOTAL" || -z "$MEM_AVAIL" ]]; then
        echo -e "${YELLOW}⚠ WARNUNG: Speicherinformationen konnten nicht abgerufen werden.${NC}"
    else
        MEM_USAGE_PERCENT=$(( 100 - ($MEM_AVAIL * 100 / $MEM_TOTAL) ))
        if [ "$MEM_USAGE_PERCENT" -gt 90 ]; then
            echo -e "${RED}✗ KRITISCH: Speicherauslastung bei ${MEM_USAGE_PERCENT}%!${NC}"
            echo -e "${YELLOW}→ Lösungen:"
            echo "  - VM-Speicher erhöhen: lxc config set $VM_NAME limits.memory 4GiB"
            echo "  - Unnötige Dienste in der VM beenden."
            echo "  - RKE2 Resource Limits für Pods anpassen.${NC}"
        elif [ "$MEM_USAGE_PERCENT" -gt 75 ]; then
            echo -e "${YELLOW}⚠ WARNUNG: Speicherauslastung bei ${MEM_USAGE_PERCENT}%.${NC}"
        else
            echo -e "${GREEN}✓ Speicher: ${MEM_USAGE_PERCENT}% genutzt.${NC}"
        fi
    fi

    # CPU
    CPU_LOAD=$(ssh_exec "uptime | awk -F'load average: ' '{print \$2}' | awk '{print \$1}' | cut -d. -f1")
    CPU_CORES=$(ssh_exec "nproc")
    if [[ -z "$CPU_LOAD" || -z "$CPU_CORES" ]]; then
        echo -e "${YELLOW}⚠ WARNUNG: CPU-Informationen konnten nicht abgerufen werden.${NC}"
    else
        if [ "$CPU_LOAD" -gt "$((CPU_CORES * 2))" ]; then
            echo -e "${RED}✗ KRITISCH: Hohe CPU-Auslastung (Load: $CPU_LOAD, Kerne: $CPU_CORES)!${NC}"
            echo -e "${YELLOW}→ Lösungen:"
            echo "  - VM-CPUs erhöhen: lxc config set $VM_NAME limits.cpu 4"
            echo "  - Pod-Resource-Limits für CPU anpassen.${NC}"
        else
            echo -e "${GREEN}✓ CPU: Load $CPU_LOAD (Kerne: $CPU_CORES).${NC}"
        fi
    fi

    # Festplatte
    DISK_USAGE=$(ssh_exec "df -h / | awk '/\// {print \$5}' | tr -d '%'")
    if [[ -z "$DISK_USAGE" ]]; then
        echo -e "${YELLOW}⚠ WARNUNG: Festplatteninformationen konnten nicht abgerufen werden.${NC}"
    else
        if [ "$DISK_USAGE" -gt 90 ]; then
            echo -e "${RED}✗ KRITISCH: Festplattenauslastung bei ${DISK_USAGE}%!${NC}"
            echo -e "${YELLOW}→ Lösungen:"
            echo "  - VM-Festplatte erweitern: lxc config device set $VM_NAME root size 20GiB"
            echo "  - Alte Container/Pods bereinigen: rke2 kubectl delete pod <pod-name>${NC}"
        elif [ "$DISK_USAGE" -gt 80 ]; then
            echo -e "${YELLOW}⚠ WARNUNG: Festplattenauslastung bei ${DISK_USAGE}%.${NC}"
        else
            echo -e "${GREEN}✓ Festplatte: ${DISK_USAGE}% genutzt.${NC}"
        fi
    fi
}

# 6. RKE2-Status prüfen
check_rke2_status() {
    echo -e "${BLUE}\n=== 5. RKE2-Status ===${NC}"
    if ! ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "systemctl is-active --quiet ${RKE2_UNIT}" 2>/dev/null; then
        echo -e "${RED}✗ FEHLER: RKE2-Dienst läuft nicht! (Unit: ${RKE2_UNIT})${NC}"
        echo -e "${YELLOW}→ Starte RKE2: sudo systemctl start ${RKE2_UNIT}${NC}"
    else
        echo -e "${GREEN}✓ RKE2-Dienst läuft.${NC}"
    fi
}

# 7. Kubernetes-Pods auf Speicherprobleme prüfen (vom Host aus)
check_k8s_pods() {
    echo -e "${BLUE}\n=== 6. Kubernetes-Pods (Host) ===${NC}"

    # 0) Kubeconfig prüfen
    if [ ! -r "$KUBECONFIG" ]; then
        echo -e "${RED}✗ FEHLER: Kubeconfig nicht lesbar: ${KUBECONFIG}${NC}"
        echo -e "${YELLOW}↳ Setze \$KUBECONFIG oder lege ~/.kube/config an (gcloud/aws/az/minikube/kind/k3s).${NC}"
        return 10
    fi

    # 1) Kontext/API prüfen
    if ! kubectl --kubeconfig "$KUBECONFIG" "${KCTX_ARG[@]}" config current-context >/dev/null 2>&1; then
        echo -e "${RED}✗ FEHLER: Kein aktueller kubectl-Context konfiguriert.${NC}"
        return 11
    fi
    if ! kubectl --kubeconfig "$KUBECONFIG" "${KCTX_ARG[@]}" cluster-info >/dev/null 2>&1; then
        echo -e "${RED}✗ FEHLER: API-Server nicht erreichbar (Context/Netz/VPN?).${NC}"
        return 12
    fi

    # 2) OOMKilled-Pods prüfen
    echo -e "${BLUE}--- OOMKilled-Pods prüfen ---${NC}"
    OOM_PODS="$(kubectl --kubeconfig "$KUBECONFIG" "${KCTX_ARG[@]}" get pods --all-namespaces \
        -o jsonpath='{.items[?(@.status.containerStatuses[?(@.lastState.terminated.reason=="OOMKilled")])].metadata.name}' 2>/dev/null || true)"
    if [ -n "$OOM_PODS" ]; then
        echo -e "${RED}✗ KRITISCH: Pods mit OOMKilled gefunden: ${OOM_PODS}${NC}"
        echo -e "${YELLOW}→ Maßnahmen: Limits/Requests erhöhen, RAM bereitstellen.${NC}"
    else
        echo -e "${GREEN}✓ Keine OOMKilled-Pods.${NC}"
    fi

    # 3) Pending-Pods prüfen
    echo -e "${BLUE}--- Pending-Pods prüfen ---${NC}"
    PENDING_PODS="$(kubectl --kubeconfig "$KUBECONFIG" "${KCTX_ARG[@]}" get pods --all-namespaces \
        --field-selector=status.phase=Pending -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)"
    if [ -n "$PENDING_PODS" ]; then
        echo -e "${RED}✗ KRITISCH: Pending-Pods gefunden: ${PENDING_PODS}${NC}"
        echo -e "${YELLOW}→ Hinweise: 'kubectl describe pod <pod>'; Scheduler/Node-Ressourcen/Taints prüfen.${NC}"
    else
        echo -e "${GREEN}✓ Keine Pending-Pods.${NC}"
    fi

    # 4) Top-Speichernutzer prüfen
    echo -e "${BLUE}--- Top-Speichernutzer prüfen ---${NC}"
    tmp_err="$(mktemp)"
    top_out="$(kubectl --kubeconfig "$KUBECONFIG" "${KCTX_ARG[@]}" top pods --all-namespaces --sort-by=memory --no-headers 2> "$tmp_err" || true)"
    status=$?
    if [ $status -ne 0 ]; then
        echo -e "${RED}✗ FEHLER: 'kubectl top' fehlgeschlagen (Exit $status).${NC}"
        if [ -s "$tmp_err" ]; then
            echo -e "${RED}↳ Details:${NC}"; cat "$tmp_err" >&2
        fi
        rm -f "$tmp_err"
        return 13
    fi
    count="$(printf '%s\n' "$top_out" | wc -l | tr -d ' ')"
    if [ "$count" -eq 0 ]; then
        echo -e "${YELLOW}⚠ WARNUNG: Keine Pod-Metriken verfügbar (metrics-server?).${NC}"
        echo -e "${YELLOW}↳ Prüfe: 'kubectl get apiservices | grep metrics.k8s.io' und Logs des metrics-server.${NC}"
    else
        printf '%s\n' "$top_out" | head -n 5
    fi
    rm -f "$tmp_err"

    # 5) (optional) Node-Übersicht
    node_out="$(kubectl --kubeconfig "$KUBECONFIG" "${KCTX_ARG[@]}" top nodes --no-headers 2>/dev/null || true)"
    if [ -n "$node_out" ]; then
        echo -e "${BLUE}--- Node-Übersicht ---${NC}"
        printf '%s\n' "$node_out"
    fi
}

# 8. RKE2-Logs prüfen (nur relevante Fehler)
check_rke2_logs() {
    echo -e "${BLUE}\n=== 7. RKE2-Logs (letzte Fehler) ===${NC}"
    # --since einschränken, um Rauschen zu reduzieren
    RKE2_ERRORS=$(ssh_exec "sudo journalctl -u ${RKE2_UNIT} --since '${RKE2_LOG_SINCE}' --no-pager | grep -Ei '(fatal|error|panic)' | grep -v 'websocket: close 1006'")
    if [ -n "$RKE2_ERRORS" ]; then
        echo -e "${RED}✗ FEHLER in den RKE2-Logs gefunden:${NC}"
        echo "$RKE2_ERRORS"
    else
        echo -e "${GREEN}✓ Keine relevanten Fehler in den letzten RKE2-Logs.${NC}"
    fi
}

# 9. Ansible-Logs prüfen
check_ansible_logs() {
    local ansible_log_path="$1"
    echo -e "${BLUE}\n=== 8. Ansible-Logs ===${NC}"

    if ! ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "test -f '$ansible_log_path'"; then
        if [ "${ANSIBLE_LOG_AUTOSETUP}" = "true" ]; then
            # Verzeichnis + Datei (mit sudo) anlegen und dem SSH_USER schreiben lassen
            ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "sudo install -d -m 775 \$(dirname '$ansible_log_path') && sudo install -o ${SSH_USER} -g ${SSH_USER} -m 664 /dev/null '$ansible_log_path'" 2>/dev/null \
              && echo -e "${GREEN}✓ Ansible-Log-Datei angelegt: ${ansible_log_path}${NC}" \
              || echo -e "${YELLOW}⚠ WARNUNG: Konnte Log-Datei nicht anlegen: ${ansible_log_path}${NC}"
        else
            echo -e "${YELLOW}⚠ WARNUNG: Ansible-Log-Datei '${ansible_log_path}' nicht gefunden.${NC}"
            echo -e "${YELLOW}↳ Aktivieren: In ansible.cfg unter [defaults] log_path = ${ansible_log_path}${NC}"
            return
        fi
    fi

    # Fehlerindikatoren komprimiert
    ANSIBLE_ERRORS=$(ssh_exec "sudo grep -E '(^fatal:|UNREACHABLE!| failed=[1-9])' '$ansible_log_path' | tail -n 10")
    if [ -n "$ANSIBLE_ERRORS" ]; then
        echo -e "${RED}✗ KRITISCH: Ansible-Fehler gefunden:${NC}"
        echo "$ANSIBLE_ERRORS"
        echo -e "${YELLOW}→ Maßnahmen:"
        echo "  - Syntaxcheck: ansible-playbook --syntax-check <playbook.yml>"
        echo "  - Debug: ansible-playbook -vvv <playbook.yml>"
        echo "  - Connectivity/Berechtigungen prüfen.${NC}"
    else
        echo -e "${GREEN}✓ Keine eindeutigen Ansible-Fehler in den Logs gefunden.${NC}"
    fi

    # Letzte Änderungen
    ANSIBLE_CHANGED=$(ssh_exec "sudo grep -i 'changed=true' '$ansible_log_path' | tail -n 5")
    [ -n "$ANSIBLE_CHANGED" ] && { echo -e "${BLUE}--- Letzte geänderten Aufgaben ---${NC}"; echo "$ANSIBLE_CHANGED"; }
}

# 10. Ansible-Playbook-Syntax prüfen (Host oder VM) – mit Auto-Discovery
# Konfigurierbar:
#   PLAYBOOK_LOCATION=host|vm   (Default: host)
#   PLAYBOOK_PATH=/pfad/zum/playbook.yml  (leer => Auto-Detect)
: "${PLAYBOOK_LOCATION:=host}"

check_ansible_playbook() {
    echo -e "${BLUE}\n=== 9. Ansible-Playbook-Syntax ===${NC}"

    local where="$PLAYBOOK_LOCATION"
    local pb="${PLAYBOOK_PATH:-}"

    if [ "$where" = "host" ]; then
        # ---- Host-Modus ----
        [ -z "$pb" ] && pb="$PWD/site.yml"
        echo -e "${BLUE}Host: $(hostname -f)  Datei: ${pb}${NC}"

        if ! command -v ansible-playbook >/dev/null 2>&1; then
            echo -e "${YELLOW}⚠ WARNUNG: ansible-playbook ist lokal nicht installiert.${NC}"
            return
        fi
        if [ ! -f "$pb" ]; then
            echo -e "${YELLOW}⚠ WARNUNG: Playbook auf dem Host nicht gefunden: ${pb}${NC}"
            echo -e "${YELLOW}↳ Setze \$PLAYBOOK_PATH oder gib einen existierenden Pfad an.${NC}"
            return
        fi

        # Inventory ermitteln: 1) ENV  2) ./inventory.yml  3) ./inventories/**/hosts.yml|yml
        inv="${INVENTORY_PATH:-}"
        if [ -z "$inv" ]; then
            if [ -f "$PWD/inventory.yml" ]; then inv="$PWD/inventory.yml"
            elif [ -f "$PWD/inventory.yaml" ]; then inv="$PWD/inventory.yaml"
            else
                inv="$(find "$PWD" -maxdepth 3 -type f \( -name hosts.yml -o -name hosts.yaml -o -name inventory.yml -o -name inventory.yaml \) | head -n1)"
            fi
        fi

        if [ -n "$inv" ] && [ -f "$inv" ]; then
            echo -e "${BLUE}Inventory: ${inv}${NC}"
            # Sanity: Gruppen vorhanden?
            if ! ansible-inventory -i "$inv" --list >/dev/null 2>&1; then
                echo -e "${YELLOW}⚠ WARNUNG: Inventory lässt sich nicht parsen: ${inv}${NC}"
            fi
            if ! out="$(ansible-playbook -i "$inv" --syntax-check "$pb" 2>&1)"; then
                echo -e "${RED}✗ FEHLER: Playbook-Syntaxfehler (Host: ${pb})${NC}"
                printf '%s\n' "$out"
                return 1
            fi
        else
            echo -e "${YELLOW}⚠ WARNUNG: Kein Inventory übergeben (INVENTORY_PATH leer, Auto-Detect fand nichts).${NC}"
            echo -e "${YELLOW}↳ Führe Syntaxcheck ohne -i aus – das führt oft zu 'hostvars is undefined'.${NC}"
            if ! out="$(ansible-playbook --syntax-check "$pb" 2>&1)"; then
                echo -e "${RED}✗ FEHLER: Playbook-Syntaxfehler (Host: ${pb})${NC}"
                printf '%s\n' "$out"
                return 1
            fi
        fi

        echo -e "${GREEN}✓ Playbook-Syntax ist korrekt (Host: ${pb}).${NC}"
        return
    fi

    # ---- VM-Modus ----
    local rhost ruser
    ruser="$SSH_USER"
    rhost="$(ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" 'hostname -f 2>/dev/null || hostname' || echo '?')"
    echo -e "${BLUE}Remote: ${ruser}@${IP_ADDRESS} (${rhost})${NC}"

    # ansible-playbook vorhanden?
    if ! ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "command -v ansible-playbook >/dev/null 2>&1"; then
        echo -e "${YELLOW}⚠ WARNUNG: ansible-playbook ist auf der VM nicht installiert.${NC}"
        echo -e "${YELLOW}↳ Installiere z. B.: sudo apt-get update && sudo apt-get install -y ansible${NC}"
        return
    fi

    # Playbook finden: erst Kandidaten, dann find-Suche
    if [ -z "$pb" ]; then
        # 1) typische Kandidaten
        for cand in \
            "~/ansible/playbook.yml" \
            "./playbook.yml" \
            "./site.yml" \
            "/home/${SSH_USER}/ansible/site.yml" \
            "/home/${SSH_USER}/ansible/playbook.yml" \
            "/srv/ansible/site.yml" \
            "/srv/ansible/playbook.yml" \
            "/etc/ansible/site.yml" \
            "/etc/ansible/playbook.yml" \
            "/opt/ansible/site.yml" \
            "/opt/ansible/playbook.yml"
        do
            if ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "test -f '$cand'"; then
                pb="$cand"; break
            fi
        done
        # 2) heuristische Suche, falls noch leer
        if [ -z "$pb" ]; then
            pb="$(ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" \
                "find /home/${SSH_USER} /srv /etc /opt -maxdepth 4 -type f -name '*.yml' -o -name '*.yaml' 2>/dev/null \
                 | grep -E '/(site|playbook)\\.ya?ml$' | head -n1" 2>/dev/null)"
        fi
    fi

    echo -e "${BLUE}Remote-Datei: ${pb:-<keine gefunden>}${NC}"
    if [ -z "$pb" ] || ! ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "test -f '$pb'"; then
        echo -e "${YELLOW}⚠ WARNUNG: Kein Playbook in der VM gefunden. Setze \$PLAYBOOK_PATH explizit.${NC}"
        return
    fi

    # Sichtbarkeit & Realpfad
    ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "ls -lah '$pb'; realpath '$pb' 2>/dev/null || readlink -f '$pb' 2>/dev/null || true" >/dev/null

    # Syntaxcheck
    if ! out="$(ssh $SSH_OPTIONS "${SSH_USER}@${IP_ADDRESS}" "ansible-playbook --syntax-check '$pb' 2>&1")"; then
        echo -e "${RED}✗ FEHLER: Playbook-Syntaxfehler (VM: ${pb})${NC}"
        printf '%s\n' "$out"
        return 1
    fi
    echo -e "${GREEN}✓ Playbook-Syntax ist korrekt (VM: ${pb}).${NC}"
}



# Hauptprogramm
FAIL=0
check_lxd         || FAIL=1
get_ip_address    || FAIL=1
test_network      || FAIL=1
test_ssh          || FAIL=1
check_vm_resources || true              # Info-only
check_rke2_status || FAIL=1
check_k8s_pods    || FAIL=1
check_rke2_logs   || true               # Info-only
check_ansible_logs "$ANSIBLE_LOG_PATH" || true
check_ansible_playbook || FAIL=1

echo -e "${BLUE}\n=== Zusammenfassung ===${NC}"
echo -e "${GREEN}✓ Alle Checks abgeschlossen.${NC}"
echo -e "${YELLOW}→ Bei Problemen: Siehe obige Lösungsvorschläge.${NC}"

exit $FAIL
