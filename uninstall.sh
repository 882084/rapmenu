#!/bin/bash
#
# uninstall.sh - Rapmenu Uninstaller
#
# Kann direkt aufgerufen werden ODER ueber das Menue selbst
# (Menuepunkt "Deinstallieren"). Entfernt Skripte, Cron-Job und Alias.
# Backups und bestehende pvesr-Jobs bleiben standardmaessig erhalten.

set -uo pipefail

CONFIG_DIR="/etc/repmenu"
INSTALL_DIR="/usr/local/bin"
LOG_DIR="/var/log/repmenu"
BACKUP_DIR="/var/backups/repmenu"
CRON_FILE="/etc/cron.d/repmenu"
CRON_JOBS_FILE="/etc/cron.d/repmenu-jobs"
CRON_JOBS_HELPERS="/usr/local/bin/repmenu-jobs"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "$*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

if [ "$EUID" -ne 0 ]; then
    error "Bitte als root ausfuehren."
    exit 1
fi

ASSUME_YES=0
if [ "${1:-}" == "--yes" ]; then
    ASSUME_YES=1
fi

confirm() {
    if [ "$ASSUME_YES" -eq 1 ]; then
        return 0
    fi
    read -rp "$1 [j/N] " REPLY
    [[ "$REPLY" =~ ^[Jj]$ ]]
}

echo ""
echo "======================================================"
echo "   Rapmenu - Deinstallation"
echo "======================================================"
echo ""

if ! confirm "Wirklich deinstallieren? Skripte und Cron-Jobs werden entfernt."; then
    info "Abgebrochen."
    exit 0
fi

if [ -f "$CRON_FILE" ]; then
    rm -f "$CRON_FILE"
    ok "Cron-Job entfernt: $CRON_FILE"
else
    info "Kein Cron-Job gefunden (ok)."
fi

if [ -f "$CRON_JOBS_FILE" ]; then
    if confirm "Backup/Wartungs-Cron-Jobs ($CRON_JOBS_FILE) ebenfalls entfernen?"; then
        rm -f "$CRON_JOBS_FILE"
        ok "Entfernt: $CRON_JOBS_FILE"
    else
        info "Backup/Wartungs-Cron-Jobs bleiben aktiv: $CRON_JOBS_FILE"
    fi
fi

if [ -d "$CRON_JOBS_HELPERS" ]; then
    if confirm "Helper-Skripte fuer Cron-Jobs ($CRON_JOBS_HELPERS) ebenfalls entfernen?"; then
        rm -rf "$CRON_JOBS_HELPERS"
        ok "Entfernt: $CRON_JOBS_HELPERS"
    fi
fi

SCRIPTS=(
    "repmenu.sh"
    "auto-ha-replication.sh"
    "sequential-replication.sh"
)

for SCRIPT in "${SCRIPTS[@]}"; do
    if [ -f "$INSTALL_DIR/$SCRIPT" ]; then
        rm -f "$INSTALL_DIR/$SCRIPT"
        ok "Entfernt: $INSTALL_DIR/$SCRIPT"
    fi
done

if grep -q "alias repmenu=" /root/.bashrc 2>/dev/null; then
    sed -i "/alias repmenu=/d" /root/.bashrc
    ok "Alias aus /root/.bashrc entfernt"
fi

if [ -d "$LOG_DIR" ]; then
    if confirm "Auch Logs unter $LOG_DIR loeschen?"; then
        rm -rf "$LOG_DIR"
        ok "Logs geloescht: $LOG_DIR"
    else
        info "Logs bleiben erhalten: $LOG_DIR"
    fi
fi

if [ -d "$BACKUP_DIR" ]; then
    warn "Config-Backups liegen unter: $BACKUP_DIR"
    if confirm "Backups WIRKLICH loeschen? (Empfehlung: NEIN, falls du Configs bearbeitet hast)"; then
        rm -rf "$BACKUP_DIR"
        ok "Backups geloescht: $BACKUP_DIR"
    else
        info "Backups bleiben erhalten: $BACKUP_DIR"
    fi
fi

if [ -d "$CONFIG_DIR" ]; then
    rm -rf "$CONFIG_DIR"
    ok "Konfigurationsverzeichnis entfernt: $CONFIG_DIR"
fi

echo ""
warn "Hinweis: Bereits angelegte pvesr-Replikations-Jobs bleiben BESTEHEN"
warn "(sie sind Teil deiner Proxmox-Konfiguration, nicht des Tools):"
echo "         pvesr list"
echo "         pvesr delete <JobID>"
echo ""

ok "Deinstallation abgeschlossen."

SELF_PATH="$(readlink -f "$0")"
if [ "$SELF_PATH" == "$INSTALL_DIR/uninstall.sh" ]; then
    rm -f "$SELF_PATH"
fi
