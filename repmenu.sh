#!/bin/bash
#
# repmenu.sh - Rapmenu
#
# Interaktives Whiptail-Menue fuer Proxmox VE:
# - Replikations-Verwaltung (HA-Jobs, sequenzieller Sync, ZFS-Tuning)
# - System-Repair (Config-Dateien bearbeiten mit Auto-Backup, gaengige Fixes)
#
# Repo: https://github.com/<USER>/repmenu
# Install: bash -c "$(wget -qLO - https://raw.githubusercontent.com/<USER>/repmenu/main/install.sh)"

set -uo pipefail

VERSION="1.0.0"
SCRIPT_DIR="/usr/local/bin"
CONFIG_DIR="/etc/repmenu"
LOG_DIR="/var/log/repmenu"
BACKUP_DIR="/var/backups/repmenu"
CRON_FILE="/etc/cron.d/repmenu"
ZPOOL_NAME="ZFS2TB"   # Anpassen, falls dein Pool anders heisst
EDITOR_BIN="${EDITOR:-nano}"

mkdir -p "$LOG_DIR" "$BACKUP_DIR"

# ---------- Hilfsfunktionen ----------

pause() {
    whiptail --title "Info" --msgbox "$1" 15 70
}

confirm() {
    whiptail --title "Bestaetigen" --yesno "$1" 10 70
}

run_and_show() {
    local CMD="$1"
    local TITLE="$2"
    local TMPFILE
    TMPFILE=$(mktemp)
    eval "$CMD" > "$TMPFILE" 2>&1
    whiptail --title "$TITLE" --scrolltext --textbox "$TMPFILE" 30 100
    rm -f "$TMPFILE"
}

backup_file() {
    # Legt Backup vor Bearbeitung an, gibt Backup-Pfad zurueck
    local SRC="$1"
    local TS
    TS=$(date '+%Y%m%d_%H%M%S')
    local DEST="$BACKUP_DIR/$(basename "$SRC").${TS}.bak"
    mkdir -p "$BACKUP_DIR"
    cp -a "$SRC" "$DEST" 2>/dev/null && echo "$DEST"
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | logger -t repmenu
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_DIR/actions.log"
}

# ================================================================
# REPLIKATION
# ================================================================

show_ha_status() {
    run_and_show "ha-manager status" "HA-Status"
}

show_replication_list() {
    run_and_show "pvesr list" "Replikations-Jobs (Uebersicht)"
}

check_missing_jobs() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "=== HA-Container ohne Replikations-Job ==="
        echo ""
        HA_CTS=$(ha-manager config 2>/dev/null | grep -oP '^ct:\K[0-9]+' || true)
        EXISTING=$(pvesr list 2>/dev/null | awk 'NR>1{print $1}' || true)
        FOUND=0
        for CTID in $HA_CTS; do
            if ! echo "$EXISTING" | grep -q "^${CTID}-"; then
                echo "CT $CTID -> KEIN Replikations-Job"
                FOUND=1
            fi
        done
        if [ "$FOUND" -eq 0 ]; then
            echo "Alle HA-Container haben einen Replikations-Job. Alles gut."
        fi
    } > "$TMPFILE"
    whiptail --title "Fehlende Jobs pruefen" --scrolltext --textbox "$TMPFILE" 25 90
    rm -f "$TMPFILE"
}

run_auto_ha_replication() {
    if [ ! -x "$SCRIPT_DIR/auto-ha-replication.sh" ]; then
        pause "Skript nicht gefunden:\n$SCRIPT_DIR/auto-ha-replication.sh"
        return
    fi
    if confirm "Automatisch fehlende Replikations-Jobs fuer alle HA-Container anlegen?"; then
        run_and_show "$SCRIPT_DIR/auto-ha-replication.sh" "Auto-HA-Replication - Ergebnis"
    fi
}

run_sequential_sync() {
    if [ ! -x "$SCRIPT_DIR/sequential-replication.sh" ]; then
        pause "Skript nicht gefunden:\n$SCRIPT_DIR/sequential-replication.sh"
        return
    fi
    if confirm "Alle Replikations-Jobs JETZT nacheinander synchronisieren?"; then
        run_and_show "$SCRIPT_DIR/sequential-replication.sh" "Sequenzieller Sync - Ergebnis"
    fi
}

change_schedule() {
    JOBID=$(whiptail --title "Job-ID" --inputbox "Fuer welchen Job (z.B. 131-0) soll der Zeitplan geaendert werden?" 12 70 3>&1 1>&2 2>&3)
    [ -z "$JOBID" ] && return

    SCHEDULE=$(whiptail --title "Zeitplan" --menu "Neuen Zeitplan fuer Job $JOBID waehlen:" 18 70 6 \
        "*/15" "Alle 15 Minuten" \
        "*/30" "Alle 30 Minuten" \
        "hourly" "Jede volle Stunde" \
        "*/2:00" "Alle 2 Stunden" \
        "custom" "Eigenen Cron-Ausdruck eingeben" \
        3>&1 1>&2 2>&3)

    if [ "$SCHEDULE" == "custom" ]; then
        SCHEDULE=$(whiptail --title "Eigener Zeitplan" --inputbox "Proxmox-Cron-Syntax eingeben (z.B. '0 */2 * * *'):" 10 70 3>&1 1>&2 2>&3)
    fi
    [ -z "$SCHEDULE" ] && return

    run_and_show "pvesr set '$JOBID' --schedule '$SCHEDULE'" "Zeitplan aendern - Ergebnis"
}

zfs_tuning_menu() {
    while true; do
        CHOICE=$(whiptail --title "ZFS Tuning (Pool: $ZPOOL_NAME)" --menu "Was moechtest du einstellen?" 18 70 6 \
            "1" "Aktuelle Compression anzeigen" \
            "2" "Compression auf lz4 setzen" \
            "3" "Aktuelle Recordsize anzeigen" \
            "4" "Recordsize setzen" \
            "5" "ARC-Size anzeigen" \
            "6" "Zurueck" \
            3>&1 1>&2 2>&3)

        case "$CHOICE" in
            1) run_and_show "zfs get compression $ZPOOL_NAME" "Compression Status" ;;
            2)
                if confirm "Compression=lz4 fuer Pool $ZPOOL_NAME setzen?"; then
                    run_and_show "zfs set compression=lz4 $ZPOOL_NAME && zfs get compression $ZPOOL_NAME" "Compression gesetzt"
                fi
                ;;
            3) run_and_show "zfs get recordsize $ZPOOL_NAME" "Recordsize Status" ;;
            4)
                RS=$(whiptail --title "Recordsize" --menu "Neue Recordsize waehlen:" 16 60 4 \
                    "64K" "Fuer viele kleine Dateien" \
                    "128K" "ZFS-Standard" \
                    "1M" "Fuer grosse Dateien (Mediathek)" \
                    3>&1 1>&2 2>&3)
                [ -z "$RS" ] && continue
                run_and_show "zfs set recordsize=$RS $ZPOOL_NAME && zfs get recordsize $ZPOOL_NAME" "Recordsize gesetzt"
                ;;
            5) run_and_show "arc_summary | grep -A2 'ARC size'" "ARC Size" ;;
            6|"") break ;;
        esac
    done
}

migration_network_info() {
    run_and_show "grep -A5 migration /etc/pve/datacenter.cfg 2>/dev/null || echo 'Kein spezielles Migrations-Netzwerk konfiguriert.'" "Migrations-Netzwerk"
}

setup_cron() {
    if confirm "Cron-Jobs einrichten?\n\n- Alle 15 Min: fehlende HA-Replikation pruefen/anlegen\n- Stuendlich: alle Jobs sequenziell syncen"; then
        cat > "$CRON_FILE" << EOF
*/15 * * * * root $SCRIPT_DIR/auto-ha-replication.sh >> $LOG_DIR/auto-ha.log 2>&1
0 * * * * root $SCRIPT_DIR/sequential-replication.sh >> $LOG_DIR/sequential.log 2>&1
EOF
        pause "Cron-Jobs eingerichtet: $CRON_FILE"
    fi
}

disable_cron() {
    if [ -f "$CRON_FILE" ]; then
        if confirm "Cron-Automatisierung deaktivieren?"; then
            rm -f "$CRON_FILE"
            pause "Cron-Job entfernt: $CRON_FILE"
        fi
    else
        pause "Es ist aktuell kein Cron-Job eingerichtet."
    fi
}

view_logs() {
    if ls "$LOG_DIR"/*.log &> /dev/null; then
        run_and_show "tail -n 100 $LOG_DIR/*.log 2>/dev/null" "Letzte Log-Eintraege"
    else
        pause "Noch keine Logs vorhanden."
    fi
}

replication_menu() {
    while true; do
        CHOICE=$(whiptail --title "Replikation" --menu "Was moechtest du tun?" 24 78 11 \
            "1" "HA-Status anzeigen" \
            "2" "Alle Replikations-Jobs anzeigen" \
            "3" "Fehlende Jobs pruefen" \
            "4" "Fehlende Jobs automatisch anlegen" \
            "5" "Jetzt sequenziell synchronisieren" \
            "6" "Zeitplan eines Jobs aendern" \
            "7" "ZFS Tuning" \
            "8" "Migrations-Netzwerk anzeigen" \
            "9" "Cron-Automatisierung einrichten" \
            "10" "Cron-Automatisierung deaktivieren" \
            "11" "Logs ansehen" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) show_ha_status ;;
            2) show_replication_list ;;
            3) check_missing_jobs ;;
            4) run_auto_ha_replication ;;
            5) run_sequential_sync ;;
            6) change_schedule ;;
            7) zfs_tuning_menu ;;
            8) migration_network_info ;;
            9) setup_cron ;;
            10) disable_cron ;;
            11) view_logs ;;
        esac
    done
}

# ================================================================
# SYSTEM REPAIR
# ================================================================

COMMON_CONFIGS=(
    "/etc/pve/datacenter.cfg"           "Cluster-weite Datacenter-Optionen"
    "/etc/pve/storage.cfg"              "Storage-Definitionen"
    "/etc/network/interfaces"           "Netzwerk-Konfiguration"
    "/etc/hosts"                        "Hostname-Aufloesung"
    "/etc/resolv.conf"                  "DNS-Server"
    "/etc/pve/replication.cfg"          "Replikations-Jobs (Rohformat)"
    "/etc/apt/sources.list"             "APT-Paketquellen"
    "/etc/fstab"                        "Mount-Punkte"
    "/etc/crontab"                      "System-Crontab"
    "custom"                            "Eigenen Pfad eingeben..."
)

edit_file_safely() {
    local FILE="$1"

    if [ ! -f "$FILE" ]; then
        if confirm "Datei $FILE existiert nicht. Neu anlegen?"; then
            touch "$FILE" 2>&1 || { pause "Konnte Datei nicht anlegen (Berechtigung?)."; return; }
        else
            return
        fi
    fi

    if [ ! -w "$FILE" ]; then
        pause "Keine Schreibrechte auf $FILE."
        return
    fi

    local BACKUP
    BACKUP=$(backup_file "$FILE")
    if [ -n "$BACKUP" ]; then
        log_action "Backup erstellt: $BACKUP (vor Bearbeitung von $FILE)"
    fi

    # Editor im Vordergrund oeffnen (whiptail muss dafuer kurz pausieren)
    "$EDITOR_BIN" "$FILE"

    if confirm "Aenderungen an $FILE wurden gespeichert.\n\nDiff zum Backup anzeigen?"; then
        if [ -n "$BACKUP" ]; then
            run_and_show "diff -u '$BACKUP' '$FILE' || true" "Diff: Backup vs. aktuelle Version"
        fi
    fi

    log_action "Datei bearbeitet: $FILE"
}

edit_common_config() {
    local MENU_ITEMS=()
    local i=0
    local -A PATH_MAP
    while [ $i -lt ${#COMMON_CONFIGS[@]} ]; do
        local KEY="$((i/2 + 1))"
        PATH_MAP["$KEY"]="${COMMON_CONFIGS[$i]}"
        MENU_ITEMS+=("$KEY" "${COMMON_CONFIGS[$i]} - ${COMMON_CONFIGS[$((i+1))]}")
        i=$((i+2))
    done

    CHOICE=$(whiptail --title "Config-Datei bearbeiten" --menu "Welche Datei bearbeiten?\n(Automatisches Backup vor jeder Aenderung)" 24 90 10 "${MENU_ITEMS[@]}" 3>&1 1>&2 2>&3)
    [ -z "${CHOICE:-}" ] && return

    local TARGET="${PATH_MAP[$CHOICE]}"
    if [ "$TARGET" == "custom" ]; then
        TARGET=$(whiptail --title "Eigener Pfad" --inputbox "Vollstaendigen Pfad zur Datei eingeben:" 10 70 3>&1 1>&2 2>&3)
        [ -z "$TARGET" ] && return
    fi

    edit_file_safely "$TARGET"
}

browse_and_edit() {
    local DIR="/etc"
    while true; do
        local ITEMS=()
        ITEMS+=(".." "Nach oben")
        while IFS= read -r ENTRY; do
            if [ -d "$DIR/$ENTRY" ]; then
                ITEMS+=("$ENTRY/" "Verzeichnis")
            else
                ITEMS+=("$ENTRY" "Datei")
            fi
        done < <(ls -1 "$DIR" 2>/dev/null)

        SEL=$(whiptail --title "Dateibrowser: $DIR" --menu "Auswaehlen:" 26 90 15 "${ITEMS[@]}" 3>&1 1>&2 2>&3)
        [ -z "${SEL:-}" ] && return

        if [ "$SEL" == ".." ]; then
            DIR=$(dirname "$DIR")
        elif [[ "$SEL" == */ ]]; then
            DIR="$DIR/${SEL%/}"
        else
            if confirm "Datei bearbeiten:\n$DIR/$SEL ?"; then
                edit_file_safely "$DIR/$SEL"
            fi
        fi
    done
}

restore_backup() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        pause "Keine Backups vorhanden unter $BACKUP_DIR"
        return
    fi

    local ITEMS=()
    while IFS= read -r BKP; do
        ITEMS+=("$BKP" "")
    done < <(ls -1t "$BACKUP_DIR")

    SEL=$(whiptail --title "Backup wiederherstellen" --menu "Welches Backup zurueckspielen?" 24 100 15 "${ITEMS[@]}" 3>&1 1>&2 2>&3)
    [ -z "${SEL:-}" ] && return

    # Original-Dateiname aus Backup-Namen ableiten (vor der letzten .TIMESTAMP.bak)
    local ORIG_NAME
    ORIG_NAME=$(echo "$SEL" | sed -E 's/\.[0-9]{8}_[0-9]{6}\.bak$//')

    TARGET_PATH=$(whiptail --title "Ziel-Pfad" --inputbox "Wohin soll das Backup zurueckgespielt werden?\n(Vorschlag basierend auf Dateiname)" 12 80 "/etc/$ORIG_NAME" 3>&1 1>&2 2>&3)
    [ -z "$TARGET_PATH" ] && return

    if confirm "Backup $SEL nach $TARGET_PATH wiederherstellen?\n\nAktuelle Datei wird vorher ebenfalls gesichert."; then
        [ -f "$TARGET_PATH" ] && backup_file "$TARGET_PATH" > /dev/null
        cp -a "$BACKUP_DIR/$SEL" "$TARGET_PATH"
        log_action "Backup wiederhergestellt: $BACKUP_DIR/$SEL -> $TARGET_PATH"
        pause "Wiederhergestellt: $TARGET_PATH"
    fi
}

list_backups() {
    run_and_show "ls -lht '$BACKUP_DIR' 2>/dev/null || echo 'Keine Backups vorhanden.'" "Vorhandene Backups"
}

# ---------- Gaengige Reparatur-Aktionen ----------

repair_apt() {
    if confirm "APT reparieren?\n\nFuehrt aus:\n- dpkg --configure -a\n- apt-get install -f\n- apt-get clean\n- apt-get update"; then
        run_and_show "dpkg --configure -a; apt-get install -f -y; apt-get clean; apt-get update" "APT Reparatur - Ergebnis"
        log_action "APT-Reparatur ausgefuehrt"
    fi
}

repair_network() {
    if confirm "Netzwerk neu laden?\n\nFuehrt aus: ifreload -a (bzw. systemctl restart networking)\n\nACHTUNG: Kann bei Fehlkonfiguration die Verbindung trennen!"; then
        if command -v ifreload &> /dev/null; then
            run_and_show "ifreload -a" "Netzwerk neu geladen"
        else
            run_and_show "systemctl restart networking" "Netzwerk-Service neugestartet"
        fi
        log_action "Netzwerk-Reload ausgefuehrt"
    fi
}

repair_initramfs() {
    if confirm "Initramfs neu bauen?\n\nFuehrt aus: update-initramfs -u -k all\n\nDauert einige Minuten."; then
        run_and_show "update-initramfs -u -k all" "Initramfs Rebuild - Ergebnis"
        log_action "Initramfs neu gebaut"
    fi
}

repair_locale() {
    if confirm "Locales neu generieren?\n\nFuehrt aus: locale-gen && update-locale"; then
        run_and_show "locale-gen && update-locale" "Locale Reparatur - Ergebnis"
        log_action "Locale-Reparatur ausgefuehrt"
    fi
}

check_zfs_pool() {
    run_and_show "zpool status" "ZFS Pool Status"
}

scrub_zfs_pool() {
    if confirm "ZFS Scrub fuer Pool $ZPOOL_NAME jetzt starten?\n\n(Laeuft im Hintergrund weiter, Fortschritt via 'zpool status' pruefbar)"; then
        run_and_show "zpool scrub $ZPOOL_NAME && echo 'Scrub gestartet - Fortschritt mit zpool status pruefen'" "ZFS Scrub gestartet"
        log_action "ZFS Scrub gestartet fuer $ZPOOL_NAME"
    fi
}

check_disk_space() {
    run_and_show "df -h; echo ''; echo '--- Groesste Verzeichnisse unter /var ---'; du -h --max-depth=2 /var 2>/dev/null | sort -rh | head -20" "Speicherplatz-Uebersicht"
}

check_pve_services() {
    run_and_show "systemctl status pve-cluster pvedaemon pveproxy pvestatd --no-pager" "Proxmox-Kern-Dienste Status"
}

restart_pve_services() {
    if confirm "Proxmox-Kerndienste neustarten?\n\n(pve-cluster, pvedaemon, pveproxy, pvestatd)\n\nKann kurze GUI-Unterbrechung verursachen."; then
        run_and_show "systemctl restart pve-cluster pvedaemon pveproxy pvestatd && sleep 2 && systemctl status pve-cluster pvedaemon pveproxy pvestatd --no-pager" "PVE-Dienste Neustart - Ergebnis"
        log_action "PVE-Kerndienste neugestartet"
    fi
}

quick_fixes_menu() {
    while true; do
        CHOICE=$(whiptail --title "Schnelle Reparaturen" --menu "Was soll repariert/geprueft werden?" 22 78 10 \
            "1" "APT reparieren (dpkg/apt-get -f)" \
            "2" "Netzwerk neu laden" \
            "3" "Initramfs neu bauen" \
            "4" "Locales neu generieren" \
            "5" "ZFS Pool Status pruefen" \
            "6" "ZFS Scrub starten" \
            "7" "Speicherplatz-Uebersicht" \
            "8" "PVE-Dienste Status pruefen" \
            "9" "PVE-Dienste neustarten" \
            "10" "Zurueck" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) repair_apt ;;
            2) repair_network ;;
            3) repair_initramfs ;;
            4) repair_locale ;;
            5) check_zfs_pool ;;
            6) scrub_zfs_pool ;;
            7) check_disk_space ;;
            8) check_pve_services ;;
            9) restart_pve_services ;;
            10|"") break ;;
        esac
    done
}

system_repair_menu() {
    while true; do
        CHOICE=$(whiptail --title "System Repair" --menu "Was moechtest du tun?" 22 78 8 \
            "1" "Config-Datei bearbeiten (aus Liste)" \
            "2" "Dateibrowser (beliebige Datei bearbeiten)" \
            "3" "Backup wiederherstellen" \
            "4" "Vorhandene Backups anzeigen" \
            "5" "Schnelle Reparaturen (APT/Netzwerk/ZFS/...)" \
            "6" "Zurueck" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) edit_common_config ;;
            2) browse_and_edit ;;
            3) restore_backup ;;
            4) list_backups ;;
            5) quick_fixes_menu ;;
            6|"") break ;;
        esac
    done
}

# ================================================================
# DEINSTALLATION
# ================================================================

uninstall_tool() {
    if whiptail --title "Deinstallieren" --yesno "Rapmenu wirklich deinstallieren?\n\nEntfernt: Skripte, Cron-Job, Alias.\nBackups und bestehende pvesr-Jobs bleiben erhalten." 14 74; then
        whiptail --title "Deinstalliere..." --infobox "Bitte warten..." 8 50
        if [ -x "$SCRIPT_DIR/uninstall.sh" ]; then
            "$SCRIPT_DIR/uninstall.sh" --yes > /tmp/repmenu-uninstall.log 2>&1
            whiptail --title "Deinstalliert" --textbox /tmp/repmenu-uninstall.log 20 80
        else
            pause "uninstall.sh nicht gefunden. Manuelle Entfernung noetig."
        fi
        clear
        echo "Rapmenu wurde deinstalliert."
        exit 0
    fi
}

# ================================================================
# HAUPTMENUE
# ================================================================

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "Rapmenu v$VERSION" --menu "Hauptmenue:" 20 74 6 \
            "1" "Replikation verwalten" \
            "2" "System Repair" \
            "3" "Logs ansehen (Rapmenu-Aktionen)" \
            "4" "Deinstallieren" \
            "0" "Beenden" \
            3>&1 1>&2 2>&3)

        EXIT=$?
        if [ $EXIT -ne 0 ]; then
            break
        fi

        case "$CHOICE" in
            1) replication_menu ;;
            2) system_repair_menu ;;
            3) run_and_show "tail -n 100 $LOG_DIR/actions.log 2>/dev/null || echo 'Noch keine Aktionen protokolliert.'" "Rapmenu Aktions-Log" ;;
            4) uninstall_tool ;;
            0) break ;;
        esac
    done
}

# ---------- Start ----------

if ! command -v whiptail &> /dev/null; then
    echo "whiptail nicht gefunden. Installiere mit: apt install whiptail"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Bitte als root ausfuehren (sudo repmenu.sh)"
    exit 1
fi

main_menu
clear
echo "Beendet."
