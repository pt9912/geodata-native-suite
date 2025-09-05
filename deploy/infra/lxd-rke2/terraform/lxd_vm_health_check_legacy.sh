#!/bin/bash
# VM Health Check für LXD-VMs mit cloud-init (erweitert)
# Nutzung: ./lxd_vm_health_check_extended.sh <VM-Name> [SSH-Benutzer] [IP-Adresse]

set -euo pipefail

# Argumente
VM_NAME=$1
SSH_USER=${2:-"ubuntu"}  # Standard-Benutzer für cloud-init (Ubuntu-Images)
IP_ADDRESS=${3:-""}      # Optional: Manuelle IP-Adresse

# Farbcodes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 0. Prüfe, ob LXD läuft (Snap-Version, deutschsprachig)
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

# 0.1 Prüfe, ob der Benutzer in der `lxd`-Gruppe ist
check_lxd_group() {
    if ! groups | grep -q '\blxd\b'; then
        echo -e "${YELLOW}⚠ WARNUNG: Benutzer ist nicht in der 'lxd'-Gruppe. Versuche hinzuzufügen...${NC}"
        if ! sudo usermod -aG lxd $USER; then
            echo -e "${RED}✗ FEHLER: Konnte Benutzer nicht zur 'lxd'-Gruppe hinzufügen.${NC}"
            exit 1
        fi
        echo -e "${GREEN}✓ Benutzer zur 'lxd'-Gruppe hinzugefügt.${NC}"
        echo -e "${YELLOW}→ Bitte neu anmelden und das Skript erneut ausführen.${NC}"
        exit 0
    fi
    echo -e "${GREEN}✓ Benutzer ist in der 'lxd'-Gruppe.${NC}"
}

# 1. VM-Status prüfen (ohne --format)
check_vm_status() {
    echo -e "${BLUE}\n=== 1. VM-Status ===${NC}"
    if [ -z "$IP_ADDRESS" ]; then
        if ! lxc list | grep -q "$VM_NAME"; then
            echo -e "${RED}✗ FEHLER: VM '$VM_NAME' existiert nicht oder ist nicht erreichbar.${NC}"
            echo -e "${YELLOW}→ Mögliche Lösungen:"
            echo "  - VM mit 'lxc launch' erstellen."
            echo "  - IP-Adresse manuell angeben: $0 $VM_NAME $SSH_USER <IP-Adresse>${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}✓ Manuelle IP-Adresse wird verwendet: $IP_ADDRESS${NC}"
        return 0
    fi

    STATUS=$(lxc info "$VM_NAME" | grep "Status:" | awk '{print $2}' | tr '[:upper:]' '[:lower:]')
    if [[ "$STATUS" != "running" ]]; then
        echo -e "${RED}✗ FEHLER: VM '$VM_NAME' läuft nicht (Status: $STATUS).${NC}"
        echo -e "${YELLOW}→ Starte die VM mit: lxc start $VM_NAME${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ VM '$VM_NAME' läuft.${NC}"
}

# 2. IP-Adresse ermitteln (für ältere LXD-Versionen)
get_ip_address() {
    if [ -z "$IP_ADDRESS" ]; then
        echo -e "${BLUE}\n=== 1. IP-Adresse ===${NC}"
        # Extrahiere die IP-Adresse aus allen Netzwerkinterfaces
        IP_ADDRESS=$(lxc list --format json 2>/dev/null | jq -r --arg name "$VM_NAME" '.[] | select(.name == $name) | .state.network | to_entries[] | .value.addresses[] | select(.family == "inet") | .address' | grep -Eo '10\.0\.[0-9]+\.[0-9]+')

        if [ -z "$IP_ADDRESS" ]; then
            echo -e "${YELLOW}⚠ WARNUNG: IP-Adresse konnte nicht automatisch ermittelt werden.${NC}"
            echo -e "${YELLOW}→ Versuche, die IP über DHCP-Leases zu ermitteln...${NC}"
            NETWORK_NAME=$(lxc network list | grep -v NAME | awk '{print $2}' | head -n 1)
            IP_ADDRESS=$(lxc network list-leases "$NETWORK_NAME" 2>/dev/null | grep "$VM_NAME" | awk '{print $3}' | grep -Eo '10\.0\.[0-9]+\.[0-9]+')
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


# 3. Netzwerkverbindung testen
test_network() {
    echo -e "${BLUE}\n=== 3. Netzwerktest ===${NC}"
    if ! ping -c 1 -W 2 "$IP_ADDRESS" &>/dev/null; then
        echo -e "${RED}✗ FEHLER: VM ist nicht über das Netzwerk erreichbar (Ping fehlgeschlagen).${NC}"
        echo -e "${YELLOW}→ Prüfe Firewall, Netzwerkinterface der VM und Routing.${NC}"
        return 1
    else
        echo -e "${GREEN}✓ VM ist über das Netzwerk erreichbar.${NC}"
        return 0
    fi
}

# 4. SSH-Verbindung testen
test_ssh() {
    echo -e "${BLUE}\n=== 4. SSH-Verbindung ===${NC}"
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 "${SSH_USER}@${IP_ADDRESS}" "echo 'SSH funktioniert'" &>/dev/null; then
        echo -e "${RED}✗ FEHLER: SSH-Verbindung fehlgeschlagen.${NC}"
        echo -e "${YELLOW}→ Prüfe:"
        echo "  - Wurde der SSH-Schlüssel von cloud-init korrekt injiziert?"
        echo "  - Läuft der SSH-Dienst in der VM? (systemctl status ssh)"
        echo "  - Ist der Benutzer '$SSH_USER' in der VM vorhanden?"
        echo "  - Firewall-Regeln auf Host und VM?"
        return 1
    else
        echo -e "${GREEN}✓ SSH-Verbindung erfolgreich.${NC}"
        return 0
    fi
}

# 5. Cloud-init-Logs prüfen
check_cloud_init_logs() {
    echo -e "${BLUE}\n=== 5. Cloud-init-Logs ===${NC}"
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "sudo cat /var/log/cloud-init-output.log" &>/dev/null; then
        echo -e "${RED}✗ FEHLER: Cloud-init-Logs nicht lesbar.${NC}"
        echo -e "${YELLOW}→ Prüfe manuell in der VM: sudo cat /var/log/cloud-init-output.log${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Cloud-init-Logs sind lesbar.${NC}"
        echo -e "${BLUE}--- Letzte 10 Zeilen der Cloud-init-Logs ---${NC}"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "sudo tail -n 10 /var/log/cloud-init-output.log"
        return 0
    fi
}

# 6. Dienste prüfen (SSH, NGINX)
check_services() {
    echo -e "${BLUE}\n=== 6. Dienstestatus ===${NC}"
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "systemctl is-active --quiet ssh" &>/dev/null; then
        echo -e "${GREEN}✓ SSH-Dienst läuft.${NC}"
    else
        echo -e "${RED}✗ FEHLER: SSH-Dienst läuft nicht.${NC}"
        echo -e "${YELLOW}→ Starte SSH in der VM: sudo systemctl start ssh${NC}"
    fi
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "systemctl is-active --quiet nginx" &>/dev/null; then
        echo -e "${GREEN}✓ NGINX-Dienst läuft.${NC}"
    else
        echo -e "${YELLOW}⚠ NGINX-Dienst läuft nicht (evtl. nicht installiert).${NC}"
    fi
}

# 7. Cloud-Init-Analyse
cloud_init_analyze() {
    echo -e "${BLUE}\n=== 7. Cloud-Init-Analyse ===${NC}"
    if ! ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "sudo cloud-init analyze show" &>/dev/null; then
        echo -e "${YELLOW}⚠ Cloud-Init-Analyse nicht verfügbar.${NC}"
        return 1
    else
        echo -e "${GREEN}✓ Cloud-Init-Analyse:${NC}"
        ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "sudo cloud-init analyze show"
        return 0
    fi
}

# 8. VM-Ressourcen prüfen (Speicher, CPU, Festplatte)
check_vm_resources() {
    echo -e "${BLUE}\n=== 8. VM-Ressourcen ===${NC}"

    # Speicher
    MEM_TOTAL=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "free -m | awk '/Mem:/ {print \$2}'")
    MEM_AVAIL=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "free -m | awk '/Mem:/ {print \$7}'")
    MEM_USAGE_PERCENT=$(( 100 - ($MEM_AVAIL * 100 / $MEM_TOTAL) ))

    if [ "$MEM_USAGE_PERCENT" -gt 90 ]; then
        echo -e "${RED}✗ KRITISCH: Speicherauslastung bei ${MEM_USAGE_PERCENT}%!${NC}"
        echo -e "${YELLOW}→ Lösungen:"
        echo "  - VM-Speicher erhöhen: lxc config set $VM_NAME limits.memory 4GiB"
        echo "  - Unnötige Dienste in der VM beenden."
    elif [ "$MEM_USAGE_PERCENT" -gt 75 ]; then
        echo -e "${YELLOW}⚠ WARNUNG: Speicherauslastung bei ${MEM_USAGE_PERCENT}%.${NC}"
    else
        echo -e "${GREEN}✓ Speicher: ${MEM_USAGE_PERCENT}% genutzt.${NC}"
    fi

    # CPU
    CPU_LOAD=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "uptime | awk -F'load average: ' '{print \$2}' | awk '{print \$1}' | cut -d. -f1")
    CPU_CORES=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "nproc")

    if [ "$CPU_LOAD" -gt "$((CPU_CORES * 2))" ]; then
        echo -e "${RED}✗ KRITISCH: Hohe CPU-Auslastung (Load: $CPU_LOAD, Kerne: $CPU_CORES)!${NC}"
        echo -e "${YELLOW}→ Lösungen:"
        echo "  - VM-CPUs erhöhen: lxc config set $VM_NAME limits.cpu 4"
        echo "  - CPU-intensive Prozesse in der VM beenden."
    else
        echo -e "${GREEN}✓ CPU: Load $CPU_LOAD (Kerne: $CPU_CORES).${NC}"
    fi

    # Festplatte
    DISK_USAGE=$(ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "df -h / | awk '/\// {print \$5}' | tr -d '%'")
    if [ "$DISK_USAGE" -gt 90 ]; then
        echo -e "${RED}✗ KRITISCH: Festplattenauslastung bei ${DISK_USAGE}%!${NC}"
        echo -e "${YELLOW}→ Lösungen:"
        echo "  - VM-Festplatte erweitern: lxc config device set $VM_NAME root size 20GiB"
        echo "  - Alte Logs oder temporäre Dateien in der VM bereinigen."
    elif [ "$DISK_USAGE" -gt 80 ]; then
        echo -e "${YELLOW}⚠ WARNUNG: Festplattenauslastung bei ${DISK_USAGE}%.${NC}"
    else
        echo -e "${GREEN}✓ Festplatte: ${DISK_USAGE}% genutzt.${NC}"
    fi
}

# 9. Netzwerkkonfiguration prüfen
check_network_config() {
    echo -e "${BLUE}\n=== 9. Netzwerkkonfiguration ===${NC}"
    echo -e "${BLUE}--- Netzwerkinterfaces ---${NC}"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "ip a"

    echo -e "${BLUE}\n--- Routing-Tabelle ---${NC}"
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null "${SSH_USER}@${IP_ADDRESS}" "ip route"
}

# 10. Konsolenlog (Fallback)
check_console_log() {
    echo -e "${BLUE}\n=== 10. VM-Konsolenlog (Fallback) ===${NC}"
    echo -e "${YELLOW}→ Konsolenlog (letzte 20 Zeilen):${NC}"
    lxc console "$VM_NAME" --type=vga 2>/dev/null | tail -n 20 || \
        echo -e "${YELLOW}→ Konsole konnte nicht gelesen werden.${NC}"
}

# 11. Zusammenfassung
summary() {
    echo -e "${BLUE}\n=== 11. Zusammenfassung ===${NC}"
    echo -e "${GREEN}Alle Tests abgeschlossen.${NC}"
    echo -e "${YELLOW}→ Bei Fehlern: Siehe obige Hinweise zur Fehlerbehebung.${NC}"
}

# Hauptprogramm
check_lxd
check_lxd_group
check_vm_status
if get_ip_address; then
    if test_network; then
        if test_ssh; then
            check_cloud_init_logs
            check_services
            cloud_init_analyze
            check_vm_resources
            check_network_config
        else
            check_console_log
        fi
    else
        check_console_log
    fi
else
    check_console_log
fi
summary
