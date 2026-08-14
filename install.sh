#!/bin/bash
# ==========================================================
# CronJobs-Proxmox - Installation
# ==========================================================
# In einer Zeile installieren:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"
# ==========================================================

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/882084/rapmenu/main"
BASE_DIR="/usr/local/share/cronjobs-proxmox"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/cronjobs-proxmox"
LOG_DIR="/var/log/cronjobs-proxmox"
BACKUP_DIR="/var/backups/cronjobs-proxmox"
HELPER_DIR="/usr/local/bin/cronjobs-proxmox-skripte"

GRUEN='\033[0;32m'; GELB='\033[1;33m'; BLAU='\033[0;34m'; ROT='\033[0;31m'; NC='\033[0m'
info()   { echo -e "${BLAU}[info]${NC} $*"; }
ok()     { echo -e "${GRUEN}[ok]${NC} $*"; }
warn()   { echo -e "${GELB}[hinweis]${NC} $*"; }
fehler() { echo -e "${ROT}[fehler]${NC} $*"; exit 1; }

# Alle Dateien des Werkzeugs
DATEIEN=(
    "cronjobs-proxmox.sh"
    "version.txt"
    "lib/utils.sh"
    "cron/definitions.sh"
    "cron/install_jobs.sh"
    "health/checks.sh"
    "menus/main_menu.sh"
    "menus/status_menu.sh"
    "menus/cron_menu.sh"
    "menus/repair_menu.sh"
    "menus/logs_menu.sh"
    "menus/help_menu.sh"
)

[ "$EUID" -ne 0 ] && fehler "Bitte als Administrator (root) ausfuehren."

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

# ── Abhaengigkeiten ─────────────────────────────────────
info "Pruefe benoetigte Programme ..."
if ! command -v whiptail &> /dev/null; then
    info "whiptail fehlt, wird installiert ..."
    apt-get update -qq && apt-get install -y whiptail -qq
    ok "whiptail installiert"
else
    ok "whiptail vorhanden"
fi

if ! command -v smartctl &> /dev/null; then
    warn "smartmontools fehlt - ohne das Programm kann der Zustand"
    warn "der Festplatten nicht geprueft werden."
    read -rp "Jetzt mitinstallieren? [J/n] " A
    if [[ ! "$A" =~ ^[Nn]$ ]]; then
        apt-get install -y smartmontools -qq && ok "smartmontools installiert"
    fi
fi

DOWNLOADER=""
for CMD in wget curl; do
    command -v "$CMD" &> /dev/null && { DOWNLOADER="$CMD"; break; }
done

hole() {
    if [ "$DOWNLOADER" == "wget" ]; then wget -qO "$2" "$1"; else curl -fsSL "$1" -o "$2"; fi
}

# ── Verzeichnisse ───────────────────────────────────────
mkdir -p "$BASE_DIR"/{lib,cron,health,menus} "$CONFIG_DIR" "$LOG_DIR" "$BACKUP_DIR" "$HELPER_DIR"
ok "Verzeichnisse angelegt"

# ── Dateien installieren ────────────────────────────────
QUELLE="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
LOKAL=0
[ -f "$QUELLE/cronjobs-proxmox.sh" ] && [ -d "$QUELLE/menus" ] && LOKAL=1

if [ "$LOKAL" -eq 1 ]; then
    info "Installiere aus dem lokalen Verzeichnis ..."
else
    info "Lade Dateien herunter ..."
    [ -z "$DOWNLOADER" ] && fehler "Weder wget noch curl gefunden. Bitte eines davon installieren."
fi

for DATEI in "${DATEIEN[@]}"; do
    ZIEL="$BASE_DIR/$DATEI"
    mkdir -p "$(dirname "$ZIEL")"
    if [ "$LOKAL" -eq 1 ]; then
        cp -f "$QUELLE/$DATEI" "$ZIEL"
    else
        hole "$REPO_RAW/$DATEI" "$ZIEL" || fehler "Konnte $DATEI nicht laden."
    fi
    case "$DATEI" in *.sh) chmod +x "$ZIEL" ;; esac
done
ok "${#DATEIEN[@]} Dateien installiert nach $BASE_DIR"

# Deinstallations-Skript
if [ "$LOKAL" -eq 1 ] && [ -f "$QUELLE/uninstall.sh" ]; then
    cp -f "$QUELLE/uninstall.sh" "$BIN_DIR/uninstall-cronjobs-proxmox.sh"
else
    hole "$REPO_RAW/uninstall.sh" "$BIN_DIR/uninstall-cronjobs-proxmox.sh" || true
fi
chmod +x "$BIN_DIR/uninstall-cronjobs-proxmox.sh" 2>/dev/null || true

# ── Startbefehl ─────────────────────────────────────────
ln -sf "$BASE_DIR/cronjobs-proxmox.sh" "$BIN_DIR/cronjobs-proxmox"
ok "Startbefehl angelegt: cronjobs-proxmox"

# ── Reste aelterer Versionen ────────────────────────────
for ALT in repmenu.sh auto-ha-replication.sh sequential-replication.sh cronjobs-proxmox.sh; do
    if [ -f "$BIN_DIR/$ALT" ] && [ ! -L "$BIN_DIR/$ALT" ]; then
        rm -f "$BIN_DIR/$ALT"
        ok "Aeltere Datei entfernt: $BIN_DIR/$ALT"
    fi
done
sed -i '/alias repmenu=/d' /root/.bashrc 2>/dev/null || true

if [ -d /etc/repmenu ] || [ -f /etc/cron.d/repmenu-jobs ]; then
    warn "Es wurde eine Installation der Vorgaengerversion (Rapmenu) gefunden."
    warn "Deren Cron-Jobs laufen weiter, bis du sie entfernst:"
    warn "  /etc/cron.d/repmenu-jobs"
fi

cat > "$CONFIG_DIR/installation.txt" << EOF
# CronJobs-Proxmox - Installationsinformationen
BASE_DIR=$BASE_DIR
CONFIG_DIR=$CONFIG_DIR
LOG_DIR=$LOG_DIR
BACKUP_DIR=$BACKUP_DIR
HELPER_DIR=$HELPER_DIR
CRON_FILE=/etc/cron.d/cronjobs-proxmox
VERSION=$(cat "$BASE_DIR/version.txt" 2>/dev/null || echo unbekannt)
INSTALLIERT_AM=$(date '+%d.%m.%Y %H:%M:%S')
EOF

echo ""
echo "=================================================="
ok "Installation abgeschlossen."
echo "=================================================="
echo ""
echo "  Menue starten mit:"
echo ""
echo "      cronjobs-proxmox"
echo ""
echo "  Der erste Bildschirm zeigt dir den Zustand deines"
echo "  Servers und was du als naechstes tun solltest."
echo ""

if [ -t 0 ]; then
    read -rp "Menue jetzt starten? [J/n] " START
    if [[ ! "$START" =~ ^[Nn]$ ]]; then
        exec "$BASE_DIR/cronjobs-proxmox.sh"
    fi
fi
