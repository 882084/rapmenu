#!/bin/bash
#
# uninstall.sh - Deinstallation von CronJobs-Proxmox
#
# Aufruf direkt oder ueber den Menuepunkt "Deinstallieren".
# Sicherungen der VMs/Container und Proxmox-Einstellungen
# bleiben in jedem Fall unberuehrt.

set -uo pipefail

BASE_DIR="/usr/local/share/cronjobs-proxmox"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/cronjobs-proxmox"
LOG_DIR="/var/log/cronjobs-proxmox"
BACKUP_DIR="/var/backups/cronjobs-proxmox"
HELPER_DIR="/usr/local/bin/cronjobs-proxmox-skripte"
CRON_FILE="/etc/cron.d/cronjobs-proxmox"

GRUEN='\033[0;32m'
GELB='\033[1;33m'
ROT='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GRUEN}[ok]${NC} $*"; }
warn() { echo -e "${GELB}[hinweis]${NC} $*"; }
info() { echo -e "$*"; }

if [ "$EUID" -ne 0 ]; then
    echo -e "${ROT}Bitte als Administrator (root) ausfuehren.${NC}"
    exit 1
fi

JA=0
[ "${1:-}" == "--yes" ] && JA=1

frage() {
    [ "$JA" -eq 1 ] && return 0
    read -rp "$1 [j/N] " A
    [[ "$A" =~ ^[Jj]$ ]]
}

echo ""
echo "=================================================="
echo "   CronJobs-Proxmox  -  Deinstallation"
echo "=================================================="
echo ""

if ! frage "Wirklich deinstallieren?"; then
    info "Abgebrochen."
    exit 0
fi

# --- Cron-Jobs ---
if [ -f "$CRON_FILE" ]; then
    ANZ=$(grep -c "# job:" "$CRON_FILE" 2>/dev/null || echo 0)
    warn "Es sind aktuell $ANZ automatische Aufgaben eingerichtet."
    if frage "Diese automatischen Aufgaben ebenfalls entfernen?"; then
        rm -f "$CRON_FILE"
        ok "Automatische Aufgaben entfernt"
    else
        warn "Die Aufgaben laufen weiter, obwohl das Menue entfernt wird."
        warn "Datei: $CRON_FILE"
        BEHALTE_SKRIPTE=1
    fi
fi

# --- Helfer-Skripte ---
if [ -d "$HELPER_DIR" ]; then
    if [ "${BEHALTE_SKRIPTE:-0}" -eq 1 ]; then
        warn "Die Skripte bleiben erhalten, da noch Aufgaben aktiv sind: $HELPER_DIR"
    elif frage "Die Job-Skripte ($HELPER_DIR) entfernen?"; then
        rm -rf "$HELPER_DIR"
        ok "Job-Skripte entfernt"
    fi
fi

# --- Programmdateien ---
if [ -d "$BASE_DIR" ]; then
    rm -rf "$BASE_DIR"
    ok "Programmdateien entfernt: $BASE_DIR"
fi
for F in cronjobs-proxmox cronjobs-proxmox.sh uninstall-cronjobs-proxmox.sh; do
    if [ -e "$BIN_DIR/$F" ]; then
        rm -f "$BIN_DIR/$F"
        ok "Entfernt: $BIN_DIR/$F"
    fi
done

# --- Reste der alten Version ---
for F in repmenu.sh auto-ha-replication.sh sequential-replication.sh; do
    [ -f "$BIN_DIR/$F" ] && { rm -f "$BIN_DIR/$F"; ok "Alte Datei entfernt: $F"; }
done
sed -i '/alias repmenu=/d' /root/.bashrc 2>/dev/null || true

# --- Protokolle ---
if [ -d "$LOG_DIR" ]; then
    if frage "Auch die Protokolle unter $LOG_DIR loeschen?"; then
        rm -rf "$LOG_DIR"
        ok "Protokolle geloescht"
    else
        info "Protokolle bleiben erhalten: $LOG_DIR"
    fi
fi

# --- Sicherungskopien ---
if [ -d "$BACKUP_DIR" ]; then
    warn "Unter $BACKUP_DIR liegen Sicherungskopien deiner"
    warn "Konfigurationsdateien (z.B. Netzwerk-Einstellungen)."
    if frage "Diese Sicherungskopien wirklich loeschen? (Empfehlung: nein)"; then
        rm -rf "$BACKUP_DIR"
        ok "Sicherungskopien geloescht"
    else
        info "Sicherungskopien bleiben erhalten: $BACKUP_DIR"
    fi
fi

# --- Einstellungen ---
if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    ok "Einstellungen entfernt: $CONFIG_DIR"
fi

echo ""
info "Unberuehrt geblieben sind:"
info "  - alle Sicherungen deiner VMs und Container"
info "  - saemtliche Proxmox-Einstellungen"
info "  - alle VMs und Container selbst"
echo ""
ok "Deinstallation abgeschlossen."

SELBST="$(readlink -f "$0")"
[ "$SELBST" == "$BIN_DIR/uninstall-cronjobs-proxmox.sh" ] && rm -f "$SELBST"
exit 0
