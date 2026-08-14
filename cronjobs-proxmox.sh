#!/bin/bash
# ==========================================================
# CronJobs-Proxmox - Einstiegspunkt
# ==========================================================
# Ein Menue fuer Proxmox VE, gedacht auch fuer Nutzer OHNE
# Linux- oder Proxmox-Erfahrung: alles per Pfeiltasten und
# Enter, keine Konsolenbefehle noetig.
#
# Dieses Skript laedt die Bibliothek und alle Menue-Module
# und startet dann das Hauptmenue.
#
# Repo: https://github.com/882084/rapmenu
# ==========================================================

set -uo pipefail

VERSION="3.0.0"

# Basisverzeichnis ermitteln: erst der Installationsort,
# sonst das Verzeichnis, in dem dieses Skript liegt
if [ -d /usr/local/share/cronjobs-proxmox/menus ]; then
    BASE_DIR="/usr/local/share/cronjobs-proxmox"
else
    BASE_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
fi
export BASE_DIR

# ── Startpruefungen ─────────────────────────────────────
if ! command -v whiptail &> /dev/null; then
    echo "Das Programm 'whiptail' fehlt."
    echo "Bitte einmalig installieren mit:  apt install whiptail"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Bitte als Administrator (root) starten:"
    echo "  sudo cronjobs-proxmox"
    exit 1
fi

# ── Module laden ────────────────────────────────────────
MODULE=(
    "lib/utils.sh"
    "cron/definitions.sh"
    "cron/install_jobs.sh"
    "health/checks.sh"
    "menus/logs_menu.sh"
    "menus/cron_menu.sh"
    "menus/repair_menu.sh"
    "menus/status_menu.sh"
    "menus/help_menu.sh"
    "menus/main_menu.sh"
)

for M in "${MODULE[@]}"; do
    if [ ! -f "$BASE_DIR/$M" ]; then
        echo "Fehlende Datei: $BASE_DIR/$M"
        echo "Die Installation scheint unvollstaendig zu sein."
        echo "Bitte neu installieren."
        exit 1
    fi
    # shellcheck disable=SC1090
    source "$BASE_DIR/$M"
done

if ! command -v pveversion &> /dev/null; then
    echo "Achtung: Dieses Werkzeug ist fuer Proxmox VE gedacht."
    echo "Auf diesem System wurde kein Proxmox gefunden."
    read -rp "Trotzdem fortfahren? [j/N] " A
    [[ "$A" =~ ^[Jj]$ ]] || exit 1
fi

# ── Los geht's ──────────────────────────────────────────
main_menu
clear
echo "CronJobs-Proxmox beendet."
echo "Erneut starten mit:  cronjobs-proxmox"
