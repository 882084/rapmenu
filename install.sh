#!/bin/bash
#
# install.sh - Installation von CronJobs-Proxmox
#
# In einer Zeile installieren:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/882084/rapmenu/main"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/cronjobs-proxmox"
LOG_DIR="/var/log/cronjobs-proxmox"
BACKUP_DIR="/var/backups/cronjobs-proxmox"
HELPER_DIR="/usr/local/bin/cronjobs-proxmox-skripte"
HAUPTSKRIPT="cronjobs-proxmox.sh"

GRUEN='\033[0;32m'
GELB='\033[1;33m'
BLAU='\033[0;34m'
ROT='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${BLAU}[info]${NC} $*"; }
ok()    { echo -e "${GRUEN}[ok]${NC} $*"; }
warn()  { echo -e "${GELB}[hinweis]${NC} $*"; }
fehler() { echo -e "${ROT}[fehler]${NC} $*"; exit 1; }

if [ "$EUID" -ne 0 ]; then
    fehler "Bitte als Administrator (root) ausfuehren."
fi

echo ""
echo "=================================================="
echo "   CronJobs-Proxmox  -  Installation"
echo "=================================================="
echo ""

if ! command -v pveversion &> /dev/null; then
    warn "Auf diesem System wurde kein Proxmox VE gefunden."
    read -rp "Trotzdem installieren? [j/N] " A
    [[ "$A" =~ ^[Jj]$ ]] || exit 1
fi

info "Pruefe benoetigte Programme ..."
if ! command -v whiptail &> /dev/null; then
    info "whiptail fehlt, wird installiert ..."
    apt-get update -qq && apt-get install -y whiptail -qq
    ok "whiptail installiert"
else
    ok "whiptail vorhanden"
fi

if ! command -v smartctl &> /dev/null; then
    warn "smartmontools fehlt (wird fuer die Festplatten-Pruefung gebraucht)"
    read -rp "Jetzt mitinstallieren? [J/n] " A
    if [[ ! "$A" =~ ^[Nn]$ ]]; then
        apt-get install -y smartmontools -qq && ok "smartmontools installiert"
    fi
fi

DOWNLOADER=""
for CMD in wget curl; do
    command -v "$CMD" &> /dev/null && { DOWNLOADER="$CMD"; break; }
done
[ -z "$DOWNLOADER" ] && fehler "Weder wget noch curl gefunden. Bitte eines davon installieren."

hole() {
    if [ "$DOWNLOADER" == "wget" ]; then
        wget -qO "$2" "$1"
    else
        curl -fsSL "$1" -o "$2"
    fi
}

mkdir -p "$INSTALL_DIR" "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR" "$HELPER_DIR"
ok "Verzeichnisse angelegt"

info "Lade Dateien herunter ..."
QUELLE_LOKAL="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"

for DATEI in "$HAUPTSKRIPT" "uninstall.sh"; do
    if [ -f "$QUELLE_LOKAL/$DATEI" ]; then
        cp -f "$QUELLE_LOKAL/$DATEI" "$INSTALL_DIR/$DATEI"
        ok "kopiert: $INSTALL_DIR/$DATEI"
    else
        hole "$REPO_RAW/$DATEI" "$INSTALL_DIR/$DATEI"
        ok "geladen:  $INSTALL_DIR/$DATEI"
    fi
    chmod +x "$INSTALL_DIR/$DATEI"
done

# Kurzer Startbefehl ohne .sh
ln -sf "$INSTALL_DIR/$HAUPTSKRIPT" "$INSTALL_DIR/cronjobs-proxmox"
ok "Startbefehl angelegt: cronjobs-proxmox"

# Alte Version (Rapmenu) sauber ablegen, falls vorhanden
if [ -f "$INSTALL_DIR/repmenu.sh" ]; then
    warn "Eine aeltere Version (repmenu) wurde gefunden."
    read -rp "Alte Version jetzt entfernen? [J/n] " A
    if [[ ! "$A" =~ ^[Nn]$ ]]; then
        rm -f "$INSTALL_DIR/repmenu.sh" "$INSTALL_DIR/auto-ha-replication.sh" "$INSTALL_DIR/sequential-replication.sh"
        sed -i '/alias repmenu=/d' /root/.bashrc 2>/dev/null || true
        ok "Alte Version entfernt (Cron-Jobs und Backups blieben erhalten)"
    fi
fi

cat > "$CONFIG_DIR/installation.txt" << EOF
# CronJobs-Proxmox - Installationsinformationen
# Wird bei der Deinstallation gelesen, bitte nicht bearbeiten.
INSTALL_DIR=$INSTALL_DIR
CONFIG_DIR=$CONFIG_DIR
LOG_DIR=$LOG_DIR
BACKUP_DIR=$BACKUP_DIR
HELPER_DIR=$HELPER_DIR
CRON_FILE=/etc/cron.d/cronjobs-proxmox
INSTALLIERT_AM=$(date '+%d.%m.%Y %H:%M:%S')
EOF
ok "Installationsinformationen gespeichert"

echo ""
echo "=================================================="
ok "Installation abgeschlossen."
echo "=================================================="
echo ""
echo "  Menue starten mit:"
echo ""
echo "      cronjobs-proxmox"
echo ""
echo "  Erster Schritt: im Menue den Punkt 'Hilfe' oeffnen -"
echo "  dort steht in wenigen Zeilen, was du zuerst aktivieren"
echo "  solltest."
echo ""
warn "Der Reparatur-Bereich veraendert echte Systemeinstellungen."
warn "Vor jeder Aenderung wird automatisch eine Kopie angelegt."
echo ""

if [ -t 0 ]; then
    read -rp "Menue jetzt starten? [J/n] " START
    if [[ ! "$START" =~ ^[Nn]$ ]]; then
        exec "$INSTALL_DIR/$HAUPTSKRIPT"
    fi
fi
