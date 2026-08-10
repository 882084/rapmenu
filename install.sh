#!/bin/bash
#
# install.sh - Rapmenu Installer
#
# One-line install:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"
#
# Laedt alle benoetigten Dateien herunter und installiert sie nach /usr/local/bin
# sowie einen Alias 'repmenu' zum bequemen Start.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/882084/rapmenu/main"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/repmenu"
LOG_DIR="/var/log/repmenu"
BACKUP_DIR="/var/backups/repmenu"
ALIAS_LINE="alias repmenu='/usr/local/bin/repmenu.sh'"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    error "Bitte als root ausfuehren. Beispiel: sudo bash -c \"\$(wget -qLO - $REPO_RAW/install.sh)\""
fi

if ! command -v pvesr &> /dev/null; then
    error "Dieses Tool ist fuer Proxmox VE gedacht (pvesr nicht gefunden). Abbruch."
fi

echo ""
echo "======================================================"
echo "   Rapmenu - Installation"
echo "======================================================"
echo ""

info "Pruefe Abhaengigkeiten..."
if ! command -v whiptail &> /dev/null; then
    info "whiptail nicht gefunden, installiere..."
    apt-get update -qq && apt-get install -y whiptail -qq
    ok "whiptail installiert"
else
    ok "whiptail bereits vorhanden"
fi

for CMD in wget curl; do
    if command -v "$CMD" &> /dev/null; then
        DOWNLOADER="$CMD"
        break
    fi
done

if [ -z "${DOWNLOADER:-}" ]; then
    error "Weder wget noch curl gefunden. Bitte eines davon installieren."
fi

fetch() {
    local URL="$1"
    local DEST="$2"
    if [ "$DOWNLOADER" == "wget" ]; then
        wget -qO "$DEST" "$URL"
    else
        curl -fsSL "$URL" -o "$DEST"
    fi
}

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR"
ok "Verzeichnisse angelegt: $CONFIG_DIR, $LOG_DIR, $BACKUP_DIR"

info "Lade Skripte herunter..."

FILES=(
    "repmenu.sh"
    "auto-ha-replication.sh"
    "sequential-replication.sh"
    "uninstall.sh"
)

for FILE in "${FILES[@]}"; do
    BASENAME=$(basename "$FILE")
    fetch "$REPO_RAW/$FILE" "$INSTALL_DIR/$BASENAME"
    chmod +x "$INSTALL_DIR/$BASENAME"
    ok "Installiert: $INSTALL_DIR/$BASENAME"
done

cat > "$CONFIG_DIR/manifest.txt" << EOF
# Rapmenu - Installations-Manifest
# Wird vom Uninstaller genutzt, nicht manuell bearbeiten
INSTALL_DIR=$INSTALL_DIR
CONFIG_DIR=$CONFIG_DIR
LOG_DIR=$LOG_DIR
BACKUP_DIR=$BACKUP_DIR
CRON_FILE=/etc/cron.d/repmenu
INSTALLED_ON=$(date '+%Y-%m-%d %H:%M:%S')
FILES=${FILES[*]}
EOF
ok "Manifest gespeichert: $CONFIG_DIR/manifest.txt"

if ! grep -q "alias repmenu=" /root/.bashrc 2>/dev/null; then
    echo "$ALIAS_LINE" >> /root/.bashrc
    ok "Alias 'repmenu' zu /root/.bashrc hinzugefuegt"
else
    ok "Alias 'repmenu' bereits vorhanden"
fi

echo ""
echo "======================================================"
ok "Installation abgeschlossen!"
echo "======================================================"
echo ""
echo "  Menue starten mit:   repmenu.sh"
echo "  oder (nach Neustart der Shell / 'source ~/.bashrc'):"
echo "                       repmenu"
echo ""
echo "  Deinstallation:      Menue -> 'Deinstallieren'"
echo "  oder direkt:         $INSTALL_DIR/uninstall.sh"
echo ""
warn "Hinweis: Rapmenu enthaelt ein System-Repair-Modul mit dem du"
warn "Systemdateien direkt bearbeiten kannst. Vor jeder Aenderung wird"
warn "automatisch ein Backup nach $BACKUP_DIR angelegt - trotzdem gilt:"
warn "mit root-Rechten an Systemdateien arbeiten ist immer mit Vorsicht"
warn "zu geniessen."
echo ""

if [ -t 0 ]; then
    read -rp "Menue jetzt starten? [J/n] " START_NOW
    if [[ ! "$START_NOW" =~ ^[Nn]$ ]]; then
        exec "$INSTALL_DIR/repmenu.sh"
    fi
fi
