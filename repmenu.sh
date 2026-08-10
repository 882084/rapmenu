#!/bin/bash
#
# repmenu.sh - Rapmenu
#
# Interaktives Whiptail-Menue fuer Proxmox VE:
# - Replikations-Verwaltung (HA-Jobs, sequenzieller Sync, ZFS-Tuning)
# - Cron-Jobs (Backup LXC/VM, PVE-Systemwartung) - auswaehlbar per Checkliste
# - System-Repair (Config-Dateien bearbeiten mit Auto-Backup, gaengige Fixes)
#
# Repo: https://github.com/882084/rapmenu
# Install: bash -c "$(wget -qLO - https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"

set -uo pipefail

VERSION="1.1.0"
SCRIPT_DIR="/usr/local/bin"
CONFIG_DIR="/etc/repmenu"
LOG_DIR="/var/log/repmenu"
BACKUP_DIR="/var/backups/repmenu"
CRON_FILE="/etc/cron.d/repmenu"
CRON_JOBS_FILE="/etc/cron.d/repmenu-jobs"
CRON_JOBS_HELPERS="/usr/local/bin/repmenu-jobs"
CRON_JOBS_CONF="$CONFIG_DIR/cronjobs.conf"
ZPOOL_NAME="ZFS2TB"   # Anpassen, falls dein Pool anders heisst
EDITOR_BIN="${EDITOR:-nano}"

mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$CONFIG_DIR" "$CRON_JOBS_HELPERS"

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
# CRON-JOBS (Backup LXC/VM + PVE-Systemwartung)
# ================================================================
#
# Jeder Job hat eine eindeutige ID, einen Anzeigenamen, eine Kategorie
# und wird bei Auswahl entweder direkt als Cron-Zeile eingetragen oder
# ruft ein kleines Helper-Skript unter $CRON_JOBS_HELPERS auf.

get_backup_storage() {
    # Liest gespeicherten Storage-Namen oder fragt einmalig danach
    if [ -f "$CRON_JOBS_CONF" ] && grep -q "^BACKUP_STORAGE=" "$CRON_JOBS_CONF"; then
        grep "^BACKUP_STORAGE=" "$CRON_JOBS_CONF" | cut -d= -f2
        return
    fi

    local AVAILABLE
    AVAILABLE=$(pvesm status 2>/dev/null | awk 'NR>1{print $1}')
    local STORAGE
    STORAGE=$(whiptail --title "Backup-Storage" --menu "Auf welchen Storage sollen Backups geschrieben werden?" 20 70 10 \
        $(echo "$AVAILABLE" | awk '{print $1, "-"}') 3>&1 1>&2 2>&3)
    [ -z "$STORAGE" ] && return 1

    echo "BACKUP_STORAGE=$STORAGE" >> "$CRON_JOBS_CONF"
    echo "$STORAGE"
}

write_helper_script() {
    # $1 = Dateiname, $2 = Inhalt (heredoc-String)
    local NAME="$1"
    local CONTENT="$2"
    echo "$CONTENT" > "$CRON_JOBS_HELPERS/$NAME"
    chmod +x "$CRON_JOBS_HELPERS/$NAME"
}

# ---------- Job-Definitionen ----------
# Format je Job: ID|Kategorie|Anzeigename|Beschreibung

CRON_JOB_DEFS=(
"backup-all-daily|Backup|Taegliches Vollbackup (LXC+VM)|vzdump --all, Snapshot-Modus, 02:00 Uhr"
"backup-vm-only-daily|Backup|Nur VMs sichern|vzdump nur fuer qm-VMs, 02:30 Uhr"
"backup-lxc-only-daily|Backup|Nur LXC-Container sichern|vzdump nur fuer pct-Container, 03:00 Uhr"
"backup-cleanup-weekly|Backup|Alte Backups aufraeumen|Loescht vzdump-Dateien aelter als 30 Tage, sonntags 04:00"
"backup-verify-weekly|Backup|Backup-Integritaet pruefen|Prueft Archiv-Integritaet aller Backups, sonntags 05:00"
"snapshot-cleanup-daily|Snapshots|Automatische Snapshots aufraeumen|Loescht Snapshots mit Praefix 'auto-' aelter als X Tage, schont manuelle Snapshots, taeglich 05:30"
"zfs-scrub-monthly|Wartung|ZFS Scrub|Erster Sonntag im Monat, 02:00 Uhr"
"apt-check-weekly|Wartung|APT Update-Check|Nur pruefen, nicht installieren, montags 06:00"
"smart-check-daily|Wartung|SMART Festplatten-Check|Taeglich 06:00, mailt bei Fehlern"
"kernel-reboot-check-daily|Wartung|Kernel-Reboot-Check|Prueft ob Reboot noetig ist, taeglich 07:00"
"journal-vacuum-weekly|Wartung|Log-Aufraeumen (journald)|Begrenzt journald-Logs auf 500MB, sonntags 03:00"
"acme-renew-daily|Wartung|SSL-Zertifikat-Erneuerung|ACME-Renew-Sicherheitsnetz, taeglich 03:00"
"pve-config-backup-daily|Konfiguration|Proxmox-Konfiguration sichern|Sichert /etc/pve/*.cfg + Netzwerk-Config als Archiv, taeglich 01:00"
"disk-space-alert-daily|Konfiguration|Speicherplatz-Warnung|Loggt Warnung wenn ein Mount ueber 90% voll ist, taeglich 08:00"
"template-update-weekly|Konfiguration|Container-Templates aktualisieren|pveam update, montags 05:00"
)

get_job_field() {
    # $1 = Job-Definition-Zeile, $2 = Feld-Index (1=ID,2=Kategorie,3=Name,4=Beschreibung)
    echo "$1" | awk -F'|' -v f="$2" '{print $f}'
}

is_job_enabled() {
    local JOBID="$1"
    [ -f "$CRON_JOBS_FILE" ] && grep -q "# repmenu-job:$JOBID" "$CRON_JOBS_FILE"
}

install_cron_job() {
    local JOBID="$1"
    local STORAGE

    case "$JOBID" in
        backup-all-daily)
            STORAGE=$(get_backup_storage) || return 1
            echo "0 2 * * * root vzdump --all --mode snapshot --compress zstd --storage $STORAGE >> $LOG_DIR/backup-all.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        backup-vm-only-daily)
            STORAGE=$(get_backup_storage) || return 1
            write_helper_script "backup-vm-only.sh" "#!/bin/bash
VMIDS=\$(qm list | awk 'NR>1{print \$1}')
[ -n \"\$VMIDS\" ] && vzdump \$VMIDS --mode snapshot --compress zstd --storage $STORAGE"
            echo "30 2 * * * root $CRON_JOBS_HELPERS/backup-vm-only.sh >> $LOG_DIR/backup-vm.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        backup-lxc-only-daily)
            STORAGE=$(get_backup_storage) || return 1
            write_helper_script "backup-lxc-only.sh" "#!/bin/bash
CTIDS=\$(pct list | awk 'NR>1{print \$1}')
[ -n \"\$CTIDS\" ] && vzdump \$CTIDS --mode snapshot --compress zstd --storage $STORAGE"
            echo "0 3 * * * root $CRON_JOBS_HELPERS/backup-lxc-only.sh >> $LOG_DIR/backup-lxc.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        backup-cleanup-weekly)
            local DAYS
            DAYS=$(whiptail --title "Aufbewahrung" --inputbox "Backups aelter als wie viele Tage loeschen?" 10 60 "30" 3>&1 1>&2 2>&3)
            [ -z "$DAYS" ] && DAYS=30
            write_helper_script "backup-cleanup.sh" "#!/bin/bash
find /var/lib/vz/dump -name 'vzdump-*' -type f -mtime +$DAYS -delete
echo \"\$(date): Backups aelter als $DAYS Tage geloescht\""
            echo "0 4 * * 0 root $CRON_JOBS_HELPERS/backup-cleanup.sh >> $LOG_DIR/backup-cleanup.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        backup-verify-weekly)
            write_helper_script "backup-verify.sh" "#!/bin/bash
for F in /var/lib/vz/dump/vzdump-*.tar.zst /var/lib/vz/dump/vzdump-*.vma.zst; do
    [ -f \"\$F\" ] || continue
    if [[ \"\$F\" == *.tar.zst ]]; then
        zstd -t \"\$F\" 2>&1 && echo \"OK: \$F\" || echo \"FEHLER: \$F ist beschaedigt!\"
    else
        zstd -t \"\$F\" 2>&1 && echo \"OK: \$F\" || echo \"FEHLER: \$F ist beschaedigt!\"
    fi
done"
            echo "0 5 * * 0 root $CRON_JOBS_HELPERS/backup-verify.sh >> $LOG_DIR/backup-verify.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        zfs-scrub-monthly)
            echo "0 2 1-7 * 0 root /sbin/zpool scrub $ZPOOL_NAME # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        apt-check-weekly)
            write_helper_script "apt-check.sh" "#!/bin/bash
apt-get update -qq
UPGRADABLE=\$(apt list --upgradable 2>/dev/null | grep -v '^Listing')
if [ -n \"\$UPGRADABLE\" ]; then
    echo \"Updates verfuegbar:\"
    echo \"\$UPGRADABLE\"
fi"
            echo "0 6 * * 1 root $CRON_JOBS_HELPERS/apt-check.sh >> $LOG_DIR/apt-check.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        smart-check-daily)
            write_helper_script "smart-check.sh" "#!/bin/bash
for DISK in \$(lsblk -d -n -o NAME | grep -E '^sd|^nvme'); do
    HEALTH=\$(smartctl -H /dev/\$DISK 2>/dev/null | grep -i 'result\\|status')
    echo \"/dev/\$DISK: \$HEALTH\"
    if echo \"\$HEALTH\" | grep -qi 'failed\\|failing'; then
        echo \"WARNUNG: /dev/\$DISK meldet Fehler!\"
    fi
done"
            echo "0 6 * * * root $CRON_JOBS_HELPERS/smart-check.sh >> $LOG_DIR/smart-check.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        kernel-reboot-check-daily)
            write_helper_script "kernel-reboot-check.sh" "#!/bin/bash
RUNNING=\$(uname -r)
INSTALLED=\$(dpkg -l | grep 'proxmox-kernel-.*-pve' | awk '{print \$3}' | sort -V | tail -1)
if [ \"\$RUNNING\" != \"\$INSTALLED\" ]; then
    echo \"Reboot noetig: laufender Kernel \$RUNNING, installiert ist \$INSTALLED\"
else
    echo \"Kein Reboot noetig (Kernel \$RUNNING aktuell)\"
fi"
            echo "0 7 * * * root $CRON_JOBS_HELPERS/kernel-reboot-check.sh >> $LOG_DIR/kernel-check.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        journal-vacuum-weekly)
            echo "0 3 * * 0 root journalctl --vacuum-size=500M # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        acme-renew-daily)
            echo "0 3 * * * root pvenode acme cert renew 2>&1 | logger -t acme-renew # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        snapshot-cleanup-daily)
            local PREFIX DAYS2
            PREFIX=$(whiptail --title "Snapshot-Praefix" --inputbox "Nur Snapshots mit diesem Praefix werden geloescht (schuetzt manuell erstellte Snapshots ohne diesen Praefix):" 10 70 "auto-" 3>&1 1>&2 2>&3)
            [ -z "$PREFIX" ] && PREFIX="auto-"
            DAYS2=$(whiptail --title "Snapshot-Alter" --inputbox "Snapshots aelter als wie viele Tage loeschen?" 10 60 "7" 3>&1 1>&2 2>&3)
            [ -z "$DAYS2" ] && DAYS2=7
            write_helper_script "snapshot-cleanup.sh" "#!/bin/bash
MAX_AGE_DAYS=$DAYS2
PREFIX='$PREFIX'
for TYPE in qm pct; do
    for VMID in \$(\$TYPE list 2>/dev/null | awk 'NR>1{print \$1}'); do
        for SNAP in \$(\$TYPE listsnapshot \$VMID 2>/dev/null | grep -v current | awk '{print \$2}' | grep -v '^\$'); do
            case \"\$SNAP\" in
                \"\$PREFIX\"*) ;;
                *) continue ;;
            esac
            SNAP_TIME=\$(\$TYPE config \$VMID --snapshot \"\$SNAP\" 2>/dev/null | grep snaptime | awk '{print \$2}')
            [ -z \"\$SNAP_TIME\" ] && continue
            AGE=\$(( (\$(date +%s) - SNAP_TIME) / 86400 ))
            if [ \"\$AGE\" -gt \"\$MAX_AGE_DAYS\" ]; then
                echo \"Loesche Snapshot '\$SNAP' von \$TYPE \$VMID (\${AGE} Tage alt)\"
                \$TYPE delsnapshot \$VMID \"\$SNAP\"
            fi
        done
    done
done"
            echo "30 5 * * * root $CRON_JOBS_HELPERS/snapshot-cleanup.sh >> $LOG_DIR/snapshot-cleanup.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        pve-config-backup-daily)
            write_helper_script "pve-config-backup.sh" "#!/bin/bash
DEST=/var/backups/repmenu/pve-config
mkdir -p \"\$DEST\"
TS=\$(date '+%Y%m%d_%H%M%S')
tar -czf \"\$DEST/pve-config_\${TS}.tar.gz\" /etc/pve/*.cfg /etc/network/interfaces /etc/hosts /etc/pve/storage.cfg /etc/pve/datacenter.cfg 2>/dev/null
find \"\$DEST\" -name 'pve-config_*.tar.gz' -mtime +14 -delete
echo \"Config-Backup erstellt: \$DEST/pve-config_\${TS}.tar.gz\""
            echo "0 1 * * * root $CRON_JOBS_HELPERS/pve-config-backup.sh >> $LOG_DIR/pve-config-backup.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        disk-space-alert-daily)
            write_helper_script "disk-space-alert.sh" "#!/bin/bash
df -hP | awk 'NR>1 {gsub(\"%\",\"\",\$5); if (\$5+0 > 90) print \"WARNUNG: \" \$6 \" ist zu \" \$5 \"% voll (\" \$1 \")\"}'"
            echo "0 8 * * * root $CRON_JOBS_HELPERS/disk-space-alert.sh >> $LOG_DIR/disk-space-alert.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        template-update-weekly)
            echo "0 5 * * 1 root pveam update >> $LOG_DIR/template-update.log 2>&1 # repmenu-job:$JOBID" >> "$CRON_JOBS_FILE"
            ;;
        *)
            return 1
            ;;
    esac
    log_action "Cron-Job aktiviert: $JOBID"
}

remove_cron_job() {
    local JOBID="$1"
    if [ -f "$CRON_JOBS_FILE" ]; then
        sed -i "/# repmenu-job:$JOBID$/d" "$CRON_JOBS_FILE"
        log_action "Cron-Job deaktiviert: $JOBID"
    fi
}

cron_category_checklist() {
    local CAT_FILTER="$1"
    local TITLE="$2"

    touch "$CRON_JOBS_FILE"

    local ITEMS=()
    local IDS_IN_CATEGORY=()
    for DEF in "${CRON_JOB_DEFS[@]}"; do
        local ID CAT NAME DESC STATE
        ID=$(get_job_field "$DEF" 1)
        CAT=$(get_job_field "$DEF" 2)
        [ "$CAT" != "$CAT_FILTER" ] && continue
        NAME=$(get_job_field "$DEF" 3)
        DESC=$(get_job_field "$DEF" 4)
        IDS_IN_CATEGORY+=("$ID")
        if is_job_enabled "$ID"; then
            STATE="ON"
        else
            STATE="OFF"
        fi
        ITEMS+=("$ID" "$NAME - $DESC" "$STATE")
    done

    if [ ${#ITEMS[@]} -eq 0 ]; then
        pause "Keine Jobs in dieser Kategorie definiert."
        return
    fi

    SELECTED=$(whiptail --title "$TITLE" --checklist \
        "Leertaste zum An-/Abwaehlen, Enter zum Bestaetigen." \
        30 100 15 "${ITEMS[@]}" 3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && return

    # Nur die repmenu-job Zeilen DIESER Kategorie entfernen, andere Kategorien bleiben unberuehrt
    if [ -f "$CRON_JOBS_FILE" ]; then
        for ID in "${IDS_IN_CATEGORY[@]}"; do
            sed -i "/# repmenu-job:$ID$/d" "$CRON_JOBS_FILE"
        done
    fi

    eval "SELECTED_ARR=($SELECTED)"

    for ID in "${IDS_IN_CATEGORY[@]}"; do
        for CHOSEN in "${SELECTED_ARR[@]:-}"; do
            if [ "$CHOSEN" == "$ID" ]; then
                install_cron_job "$ID"
                break
            fi
        done
    done

    pause "Jobs in Kategorie \"$TITLE\" aktualisiert.\n\nDatei: $CRON_JOBS_FILE\nHelper-Skripte: $CRON_JOBS_HELPERS\nLogs: $LOG_DIR"
}

cron_jobs_menu() {
    while true; do
        CHOICE=$(whiptail --title "Cron-Jobs" --menu "Kategorie waehlen:" 20 78 6 \
            "1" "Backup (LXC/VM sichern)" \
            "2" "Snapshot-Verwaltung" \
            "3" "System-Wartung" \
            "4" "Konfiguration & Sonstiges" \
            "5" "Zurueck" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) cron_category_checklist "Backup" "Backup-Jobs (LXC/VM)" ;;
            2) cron_category_checklist "Snapshots" "Snapshot-Verwaltung" ;;
            3) cron_category_checklist "Wartung" "System-Wartung" ;;
            4) cron_category_checklist "Konfiguration" "Konfiguration & Sonstiges" ;;
            5|"") break ;;
        esac
    done
}

view_cron_jobs_status() {
    if [ ! -f "$CRON_JOBS_FILE" ] || [ ! -s "$CRON_JOBS_FILE" ]; then
        pause "Aktuell sind keine Cron-Jobs ueber Rapmenu aktiviert."
        return
    fi
    run_and_show "cat '$CRON_JOBS_FILE'" "Aktive Cron-Jobs (Rohformat)"
}

# ================================================================
# APT-REPOSITORIES (Paketquellen) verwalten
# ================================================================
#
# Erlaubt An-/Abschalten von Repo-Zeilen per Menue, ohne manuell
# in Dateien rumzueditieren. Deckt sowohl klassisches sources.list-
# Format als auch das neuere deb822 (.sources) Format ab.

APT_REPO_PATHS_DEFAULT=(
    "/etc/apt/sources.list"
)

find_repo_files() {
    # Alle relevanten Repo-Dateien auflisten
    local FILES=()
    [ -f /etc/apt/sources.list ] && FILES+=("/etc/apt/sources.list")
    if [ -d /etc/apt/sources.list.d ]; then
        while IFS= read -r F; do
            FILES+=("$F")
        done < <(find /etc/apt/sources.list.d -maxdepth 1 -type f \( -name "*.list" -o -name "*.sources" \) 2>/dev/null | sort)
    fi
    printf '%s\n' "${FILES[@]}"
}

repo_list_all() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        while IFS= read -r F; do
            echo "=== $F ==="
            cat -n "$F"
            echo ""
        done < <(find_repo_files)
    } > "$TMPFILE"
    whiptail --title "Alle Paketquellen" --scrolltext --textbox "$TMPFILE" 30 100
    rm -f "$TMPFILE"
}

repo_toggle_matching() {
    # $1 = grep-Pattern (z.B. "enterprise.proxmox.com")
    # $2 = Anzeigename fuer Dialoge
    local PATTERN="$1"
    local LABEL="$2"

    local MATCHED_FILES
    MATCHED_FILES=$(grep -rl "$PATTERN" /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null)

    if [ -z "$MATCHED_FILES" ]; then
        pause "Keine Zeilen mit \"$PATTERN\" gefunden.\n\n$LABEL scheint auf diesem System nicht konfiguriert zu sein."
        return
    fi

    # Pruefen ob aktuell aktiv (mind. eine unkommentierte Treffer-Zeile) oder komplett deaktiviert
    local ACTIVE=0
    while IFS= read -r F; do
        if grep -E "^[^#]*$PATTERN" "$F" &>/dev/null; then
            ACTIVE=1
        fi
    done <<< "$MATCHED_FILES"

    local ACTION_TEXT
    if [ "$ACTIVE" -eq 1 ]; then
        ACTION_TEXT="deaktivieren (auskommentieren)"
    else
        ACTION_TEXT="aktivieren (einkommentieren)"
    fi

    if ! confirm "$LABEL $ACTION_TEXT?\n\nBetroffene Dateien:\n$MATCHED_FILES"; then
        return
    fi

    while IFS= read -r F; do
        backup_file "$F" > /dev/null
        if [ "$ACTIVE" -eq 1 ]; then
            # Auskommentieren: nur Zeilen, die aktuell NICHT bereits mit # beginnen
            sed -i -E "/^[^#].*$PATTERN/ s/^/#/" "$F"
        else
            # Einkommentieren: fuehrendes # vor Treffer-Zeilen entfernen
            sed -i -E "/^#.*$PATTERN/ s/^#//" "$F"
        fi
    done <<< "$MATCHED_FILES"

    log_action "$LABEL ${ACTION_TEXT%% *} (Dateien: $(echo $MATCHED_FILES | tr '\n' ' '))"
    pause "$LABEL wurde ${ACTION_TEXT%% *}.\n\nBetroffene Dateien wurden vorher gesichert."
}

repo_toggle_enterprise() {
    repo_toggle_matching "enterprise\.proxmox\.com" "PVE Enterprise-Repository"
}

repo_toggle_no_subscription() {
    repo_toggle_matching "pve-no-subscription" "PVE No-Subscription-Repository"
}

repo_toggle_ceph() {
    repo_toggle_matching "enterprise\.proxmox\.com/debian/ceph" "Ceph Enterprise-Repository"
}

repo_toggle_lines_menu() {
    # Datei auswaehlen
    local FILES=()
    while IFS= read -r F; do
        FILES+=("$F" "")
    done < <(find_repo_files)

    if [ ${#FILES[@]} -eq 0 ]; then
        pause "Keine Repository-Dateien gefunden."
        return
    fi

    local TARGET
    TARGET=$(whiptail --title "Datei waehlen" --menu "In welcher Datei Zeilen an-/abschalten?" 20 90 10 "${FILES[@]}" 3>&1 1>&2 2>&3)
    [ -z "${TARGET:-}" ] && return

    if [ ! -f "$TARGET" ]; then
        pause "Datei nicht gefunden: $TARGET"
        return
    fi

    # Zeilen einlesen, nur nicht-leere beruecksichtigen
    local LINES=()
    local ITEMS=()
    local IDX=0
    while IFS= read -r LINE; do
        # leere Zeilen ueberspringen
        if [ -z "$(echo "$LINE" | tr -d '[:space:]')" ]; then
            continue
        fi
        IDX=$((IDX+1))
        LINES[$IDX]="$LINE"
        local DISPLAY="${LINE#\#}"
        DISPLAY="${DISPLAY:0:75}"
        local STATE="ON"
        [[ "$LINE" == \#* ]] && STATE="OFF"
        ITEMS+=("$IDX" "$DISPLAY" "$STATE")
    done < "$TARGET"

    if [ ${#ITEMS[@]} -eq 0 ]; then
        pause "Keine Zeilen zum Bearbeiten in $TARGET gefunden."
        return
    fi

    SELECTED=$(whiptail --title "Zeilen in $(basename "$TARGET")" --checklist \
        "Leertaste = an/aus, Enter = uebernehmen.\nAngehakt = aktiv (nicht auskommentiert)." \
        30 100 15 "${ITEMS[@]}" 3>&1 1>&2 2>&3)

    [ $? -ne 0 ] && return

    eval "SELECTED_ARR=($SELECTED)"

    backup_file "$TARGET" > /dev/null

    local TMPFILE
    TMPFILE=$(mktemp)
    IDX=0
    while IFS= read -r LINE; do
        if [ -z "$(echo "$LINE" | tr -d '[:space:]')" ]; then
            echo "$LINE" >> "$TMPFILE"
            continue
        fi
        IDX=$((IDX+1))
        local SHOULD_BE_ON=0
        for SEL in "${SELECTED_ARR[@]:-}"; do
            [ "$SEL" == "$IDX" ] && SHOULD_BE_ON=1
        done

        local BARE="${LINE#\#}"
        if [ "$SHOULD_BE_ON" -eq 1 ]; then
            echo "$BARE" >> "$TMPFILE"
        else
            echo "#$BARE" >> "$TMPFILE"
        fi
    done < "$TARGET"

    mv "$TMPFILE" "$TARGET"
    log_action "Repo-Zeilen umgeschaltet in $TARGET"
    pause "Aenderungen gespeichert: $TARGET\n\nBackup wurde vorher angelegt."
}

repo_update_check() {
    run_and_show "apt-get update" "apt-get update - Ergebnis"
}

apt_repo_menu() {
    while true; do
        CHOICE=$(whiptail --title "Paketquellen (APT)" --menu "Was moechtest du tun?" 22 78 8 \
            "1" "Alle Paketquellen anzeigen" \
            "2" "PVE Enterprise-Repo an/aus" \
            "3" "PVE No-Subscription-Repo an/aus" \
            "4" "Ceph Enterprise-Repo an/aus" \
            "5" "Einzelne Zeilen an/abschalten (Checkliste)" \
            "6" "Datei im Editor bearbeiten (fortgeschritten)" \
            "7" "apt-get update ausfuehren" \
            "8" "Zurueck" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) repo_list_all ;;
            2) repo_toggle_enterprise ;;
            3) repo_toggle_no_subscription ;;
            4) repo_toggle_ceph ;;
            5) repo_toggle_lines_menu ;;
            6)
                local FILES=()
                while IFS= read -r F; do FILES+=("$F" ""); done < <(find_repo_files)
                TARGET=$(whiptail --title "Datei waehlen" --menu "Welche Datei im Editor oeffnen?" 20 90 10 "${FILES[@]}" 3>&1 1>&2 2>&3)
                [ -n "${TARGET:-}" ] && edit_file_safely "$TARGET"
                ;;
            7) repo_update_check ;;
            8|"") break ;;
        esac
    done
}

# ================================================================
# NETZWERKFREIGABEN (NFS/CIFS) an LXC-Container anbinden
# ================================================================
#
# Proxmox-LXC-Container koennen NFS/CIFS meist nicht direkt selbst
# mounten (Kernel-Modul-Einschraenkung, v.a. bei unprivilegierten
# Containern). Der saubere Weg: der PVE-HOST mountet die Freigabe,
# der Container bekommt sie per Bind-Mount (pct set -mpX) durchgereicht.
#
# Auto-Reconnect: fstab-Eintraege nutzen systemd x-systemd.automount,
# zusaetzlich ein optionaler Cron-Check als Sicherheitsnetz.

SHARES_MARKER_PREFIX="# repmenu-share:"
CREDENTIALS_DIR="/etc/repmenu/credentials"
mkdir -p "$CREDENTIALS_DIR"
chmod 700 "$CREDENTIALS_DIR"

share_ask_name() {
    whiptail --title "Name der Freigabe" --inputbox "Kurzer, eindeutiger Name fuer diese Freigabe (nur Buchstaben/Zahlen/Bindestrich, z.B. 'nas-media'):" 10 70 3>&1 1>&2 2>&3
}

share_find_free_mp_slot() {
    # $1 = CTID -> gibt naechste freie mpX-Nummer zurueck (0-9)
    local CTID="$1"
    for N in 0 1 2 3 4 5 6 7 8 9; do
        if ! pct config "$CTID" 2>/dev/null | grep -q "^mp${N}:"; then
            echo "$N"
            return
        fi
    done
    echo ""
}

share_offer_lxc_bind() {
    local NAME="$1"
    local HOST_MOUNTPOINT="$2"

    if ! confirm "Freigabe \"$NAME\" jetzt zusaetzlich per Bind-Mount in einen LXC-Container einbinden?"; then
        return
    fi

    local CT_LIST
    CT_LIST=$(pct list 2>/dev/null | awk 'NR>1{print $1, $3}')
    if [ -z "$CT_LIST" ]; then
        pause "Keine LXC-Container gefunden."
        return
    fi

    local CT_ITEMS=()
    while read -r ID HNAME; do
        CT_ITEMS+=("$ID" "$HNAME")
    done <<< "$CT_LIST"

    local CTID
    CTID=$(whiptail --title "Container waehlen" --menu "In welchen Container einbinden?" 20 70 10 "${CT_ITEMS[@]}" 3>&1 1>&2 2>&3)
    [ -z "${CTID:-}" ] && return

    local SLOT
    SLOT=$(share_find_free_mp_slot "$CTID")
    if [ -z "$SLOT" ]; then
        pause "Keine freien Mountpoint-Slots (mp0-mp9) mehr fuer Container $CTID."
        return
    fi

    local CT_PATH
    CT_PATH=$(whiptail --title "Pfad im Container" --inputbox "Unter welchem Pfad soll die Freigabe im Container erscheinen?" 10 70 "/mnt/$NAME" 3>&1 1>&2 2>&3)
    [ -z "$CT_PATH" ] && return

    if confirm "Bind-Mount einrichten?\n\nHost:      $HOST_MOUNTPOINT\nContainer: $CTID (Slot mp$SLOT)\nZiel-Pfad: $CT_PATH\n\nHinweis: Container muss dafuer neu gestartet werden (oder mind. mp neu geladen werden)."; then
        run_and_show "pct set $CTID -mp$SLOT $HOST_MOUNTPOINT,mp=$CT_PATH" "Bind-Mount eingerichtet"
        log_action "Bind-Mount: $HOST_MOUNTPOINT -> CT $CTID:$CT_PATH (mp$SLOT)"
        if confirm "Container $CTID jetzt neustarten, damit der Mount aktiv wird?"; then
            run_and_show "pct reboot $CTID" "Container neugestartet"
        fi
    fi
}

share_add_nfs() {
    local NAME SERVER EXPORT_PATH MOUNTPOINT NFSVERS

    NAME=$(share_ask_name)
    [ -z "$NAME" ] && return

    SERVER=$(whiptail --title "NFS-Server" --inputbox "IP-Adresse oder Hostname des NFS-Servers:" 10 70 3>&1 1>&2 2>&3)
    [ -z "$SERVER" ] && return

    EXPORT_PATH=$(whiptail --title "Export-Pfad" --inputbox "Freigegebener Pfad auf dem Server (z.B. /volume1/data):" 10 70 3>&1 1>&2 2>&3)
    [ -z "$EXPORT_PATH" ] && return

    MOUNTPOINT=$(whiptail --title "Mountpoint auf dem PVE-Host" --inputbox "Wohin soll auf DIESEM Proxmox-Host gemountet werden?" 10 70 "/mnt/pve/$NAME" 3>&1 1>&2 2>&3)
    [ -z "$MOUNTPOINT" ] && return

    NFSVERS=$(whiptail --title "NFS-Version" --menu "Welche NFS-Version verwenden?" 15 60 3 \
        "4" "NFSv4 (Standard, empfohlen)" \
        "3" "NFSv3 (aeltere NAS-Systeme)" \
        "auto" "Automatisch aushandeln" \
        3>&1 1>&2 2>&3)
    [ -z "$NFSVERS" ] && NFSVERS="4"

    mkdir -p "$MOUNTPOINT"

    local OPTS="_netdev,x-systemd.automount,x-systemd.mount-timeout=10,x-systemd.idle-timeout=1min,retry=3"
    if [ "$NFSVERS" != "auto" ]; then
        OPTS="nfsvers=$NFSVERS,$OPTS"
    fi

    local FSTAB_LINE="$SERVER:$EXPORT_PATH $MOUNTPOINT nfs $OPTS 0 0 ${SHARES_MARKER_PREFIX}${NAME}"

    backup_file /etc/fstab > /dev/null
    echo "$FSTAB_LINE" >> /etc/fstab

    systemctl daemon-reload
    run_and_show "mount '$MOUNTPOINT' && ls -la '$MOUNTPOINT' && echo '--- Mount erfolgreich ---' || echo '--- FEHLER beim Mounten, bitte fstab pruefen ---'" "NFS-Freigabe einbinden - Ergebnis"

    log_action "NFS-Freigabe hinzugefuegt: $NAME ($SERVER:$EXPORT_PATH -> $MOUNTPOINT)"

    share_offer_lxc_bind "$NAME" "$MOUNTPOINT"
}

share_add_cifs() {
    local NAME SERVER SHARE_NAME DOMAIN USERNAME PASSWORD MOUNTPOINT

    NAME=$(share_ask_name)
    [ -z "$NAME" ] && return

    SERVER=$(whiptail --title "CIFS/SMB-Server" --inputbox "IP-Adresse oder Hostname des Servers:" 10 70 3>&1 1>&2 2>&3)
    [ -z "$SERVER" ] && return

    SHARE_NAME=$(whiptail --title "Freigabename" --inputbox "Name der Freigabe (ohne Slashes, z.B. 'media' fuer \\\\server\\media):" 10 70 3>&1 1>&2 2>&3)
    [ -z "$SHARE_NAME" ] && return

    DOMAIN=$(whiptail --title "Domain (optional)" --inputbox "Windows-Domain oder Arbeitsgruppe (leer lassen falls nicht benoetigt):" 10 70 3>&1 1>&2 2>&3)

    USERNAME=$(whiptail --title "Benutzername" --inputbox "Benutzername fuer die Freigabe:" 10 70 3>&1 1>&2 2>&3)
    [ -z "$USERNAME" ] && return

    PASSWORD=$(whiptail --title "Passwort" --passwordbox "Passwort fuer $USERNAME:" 10 70 3>&1 1>&2 2>&3)
    [ -z "$PASSWORD" ] && return

    MOUNTPOINT=$(whiptail --title "Mountpoint auf dem PVE-Host" --inputbox "Wohin soll auf DIESEM Proxmox-Host gemountet werden?" 10 70 "/mnt/pve/$NAME" 3>&1 1>&2 2>&3)
    [ -z "$MOUNTPOINT" ] && return

    mkdir -p "$MOUNTPOINT"

    # Credentials-Datei sicher anlegen (nicht im Klartext in fstab)
    local CRED_FILE="$CREDENTIALS_DIR/${NAME}.cred"
    {
        echo "username=$USERNAME"
        echo "password=$PASSWORD"
        [ -n "$DOMAIN" ] && echo "domain=$DOMAIN"
    } > "$CRED_FILE"
    chmod 600 "$CRED_FILE"

    local OPTS="credentials=$CRED_FILE,iocharset=utf8,_netdev,x-systemd.automount,x-systemd.mount-timeout=10,x-systemd.idle-timeout=1min,uid=0,gid=0,file_mode=0770,dir_mode=0770"
    local FSTAB_LINE="//$SERVER/$SHARE_NAME $MOUNTPOINT cifs $OPTS 0 0 ${SHARES_MARKER_PREFIX}${NAME}"

    backup_file /etc/fstab > /dev/null
    echo "$FSTAB_LINE" >> /etc/fstab

    systemctl daemon-reload
    run_and_show "mount '$MOUNTPOINT' && ls -la '$MOUNTPOINT' && echo '--- Mount erfolgreich ---' || echo '--- FEHLER beim Mounten, bitte Zugangsdaten/fstab pruefen ---'" "CIFS-Freigabe einbinden - Ergebnis"

    log_action "CIFS-Freigabe hinzugefuegt: $NAME (//$SERVER/$SHARE_NAME -> $MOUNTPOINT)"

    share_offer_lxc_bind "$NAME" "$MOUNTPOINT"
}

share_list() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "=== Von Rapmenu verwaltete Freigaben (aus /etc/fstab) ==="
        echo ""
        grep "$SHARES_MARKER_PREFIX" /etc/fstab 2>/dev/null || echo "Keine Freigaben gefunden."
        echo ""
        echo "=== Aktueller Mount-Status ==="
        for LINE in $(grep "$SHARES_MARKER_PREFIX" /etc/fstab 2>/dev/null | awk '{print $2}'); do
            if mountpoint -q "$LINE" 2>/dev/null; then
                echo "OK       $LINE (gemountet)"
            else
                echo "NICHT AKTIV  $LINE (nicht gemountet - evtl. Lazy-Automount, wird bei Zugriff aktiv)"
            fi
        done
    } > "$TMPFILE"
    whiptail --title "Netzwerkfreigaben - Uebersicht" --scrolltext --textbox "$TMPFILE" 30 100
    rm -f "$TMPFILE"
}

share_remove() {
    local SHARES
    SHARES=$(grep "$SHARES_MARKER_PREFIX" /etc/fstab 2>/dev/null | sed -E "s/.*${SHARES_MARKER_PREFIX}//")
    if [ -z "$SHARES" ]; then
        pause "Keine von Rapmenu verwalteten Freigaben gefunden."
        return
    fi

    local ITEMS=()
    while IFS= read -r S; do
        ITEMS+=("$S" "")
    done <<< "$SHARES"

    local NAME
    NAME=$(whiptail --title "Freigabe entfernen" --menu "Welche Freigabe entfernen?" 20 70 10 "${ITEMS[@]}" 3>&1 1>&2 2>&3)
    [ -z "${NAME:-}" ] && return

    local MOUNTPOINT
    MOUNTPOINT=$(grep "${SHARES_MARKER_PREFIX}${NAME}$" /etc/fstab | awk '{print $2}')

    if confirm "Freigabe \"$NAME\" wirklich entfernen?\n\nMountpoint: $MOUNTPOINT\n\n(Aushaengen + fstab-Eintrag + Zugangsdaten werden entfernt. Bind-Mounts in Containern muessen manuell mit 'pct set <ID> -delete mpX' entfernt werden.)"; then
        umount "$MOUNTPOINT" 2>/dev/null
        backup_file /etc/fstab > /dev/null
        sed -i "\|${SHARES_MARKER_PREFIX}${NAME}$|d" /etc/fstab
        rm -f "$CREDENTIALS_DIR/${NAME}.cred"
        systemctl daemon-reload
        log_action "Freigabe entfernt: $NAME"
        pause "Freigabe \"$NAME\" entfernt."
    fi
}

share_check_reconnect() {
    if confirm "Reconnect-Check jetzt manuell ausfuehren?\n\nVersucht alle konfigurierten Freigaben zu mounten, falls sie nicht aktiv sind."; then
        run_and_show "for MP in \$(grep '$SHARES_MARKER_PREFIX' /etc/fstab | awk '{print \$2}'); do if ! mountpoint -q \"\$MP\"; then echo \"Versuche Reconnect: \$MP\"; mount \"\$MP\" && echo \"OK: \$MP\" || echo \"FEHLER: \$MP\"; else echo \"Bereits aktiv: \$MP\"; fi; done" "Reconnect-Check - Ergebnis"
    fi
}

share_setup_autoreconnect_cron() {
    if confirm "Automatischen Reconnect-Check per Cron einrichten?\n\nPrueft alle 5 Minuten, ob Freigaben aktiv sind, und mountet sie bei Bedarf neu (Sicherheitsnetz zusaetzlich zu systemd-automount)."; then
        write_helper_script "share-reconnect-check.sh" "#!/bin/bash
for MP in \$(grep '$SHARES_MARKER_PREFIX' /etc/fstab 2>/dev/null | awk '{print \$2}'); do
    if ! mountpoint -q \"\$MP\" 2>/dev/null; then
        echo \"\$(date): Reconnect-Versuch fuer \$MP\"
        mount \"\$MP\" 2>&1
    fi
done"
        local CRON_LINE="*/5 * * * * root $CRON_JOBS_HELPERS/share-reconnect-check.sh >> $LOG_DIR/share-reconnect.log 2>&1 # repmenu-job:share-reconnect-check"
        touch "$CRON_JOBS_FILE"
        sed -i "/# repmenu-job:share-reconnect-check$/d" "$CRON_JOBS_FILE"
        echo "$CRON_LINE" >> "$CRON_JOBS_FILE"
        log_action "Auto-Reconnect-Cron fuer Freigaben eingerichtet"
        pause "Auto-Reconnect-Check eingerichtet (alle 5 Minuten).\n\nLog: $LOG_DIR/share-reconnect.log"
    fi
}

shares_menu() {
    while true; do
        CHOICE=$(whiptail --title "Netzwerkfreigaben (NFS/CIFS)" --menu "Was moechtest du tun?" 22 78 8 \
            "1" "Neue NFS-Freigabe verbinden" \
            "2" "Neue CIFS/SMB-Freigabe verbinden" \
            "3" "Freigaben anzeigen (Status)" \
            "4" "Freigabe entfernen" \
            "5" "Reconnect jetzt manuell ausfuehren" \
            "6" "Automatischen Reconnect-Check einrichten (Cron)" \
            "7" "Zurueck" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) share_add_nfs ;;
            2) share_add_cifs ;;
            3) share_list ;;
            4) share_remove ;;
            5) share_check_reconnect ;;
            6) share_setup_autoreconnect_cron ;;
            7|"") break ;;
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

# ================================================================
# UNTERMENUE: Backup & Wartung, Logs
# ================================================================

backup_wartung_menu() {
    while true; do
        CHOICE=$(whiptail --title "Cron-Jobs" --menu "Was moechtest du tun?" 18 78 4 \
            "1" "Jobs nach Kategorie auswaehlen" \
            "2" "Aktive Jobs anzeigen (alle Kategorien)" \
            "3" "Zurueck" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) cron_jobs_menu ;;
            2) view_cron_jobs_status ;;
            3|"") break ;;
        esac
    done
}

# ================================================================
# BEREINIGUNG (Fehlinstallationen, verwaiste Dateien/Pakete)
# ================================================================

cleanup_detect_docker_on_host() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "=== Docker-Pakete (dpkg) ==="
        dpkg -l 2>/dev/null | grep -iE 'docker|containerd' || echo "Keine Docker/Containerd-Pakete installiert."
        echo ""
        echo "=== Docker-Dienst ==="
        systemctl status docker --no-pager 2>&1 | head -5 || echo "Kein docker.service gefunden."
        echo ""
        echo "=== Docker-Datenverzeichnisse ==="
        for D in /var/lib/docker /var/lib/containerd /etc/docker; do
            if [ -d "$D" ]; then
                SIZE=$(du -sh "$D" 2>/dev/null | cut -f1)
                echo "$D existiert (Groesse: $SIZE)"
            else
                echo "$D existiert nicht"
            fi
        done
    } > "$TMPFILE"
    whiptail --title "Docker auf PVE-Host - Erkennung" --scrolltext --textbox "$TMPFILE" 30 100
    rm -f "$TMPFILE"
}

cleanup_remove_docker_on_host() {
    if ! dpkg -l 2>/dev/null | grep -qiE 'docker|containerd' && [ ! -d /var/lib/docker ]; then
        pause "Keine Docker-Installation auf diesem Host gefunden. Nichts zu entfernen."
        return
    fi

    if ! whiptail --title "ACHTUNG - Docker vom PVE-Host entfernen" --yesno "Docker sollte NIEMALS direkt auf dem Proxmox-Host laufen - es gehoert immer in eine VM oder einen LXC-Container.\n\nDiese Aktion wird:\n- Alle Docker/Containerd-Pakete purgen\n- /var/lib/docker, /var/lib/containerd, /etc/docker loeschen\n- Verwaiste Abhaengigkeiten entfernen\n\nALLE Docker-Container/Images/Volumes auf diesem Host gehen dabei verloren!\n\nWirklich fortfahren?" 20 78; then
        return
    fi

    if ! whiptail --title "Letzte Bestaetigung" --yesno "Bist du dir WIRKLICH sicher?\n\nDies ist nicht rueckgaengig zu machen." 10 60; then
        return
    fi

    run_and_show "apt-get purge -y docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose podman-docker 2>/dev/null; \
        apt-get autoremove -y; \
        rm -rf /var/lib/docker /var/lib/containerd /etc/docker; \
        groupdel docker 2>/dev/null; \
        echo '--- Docker-Entfernung abgeschlossen ---'" "Docker entfernen - Ergebnis"

    log_action "Docker auf PVE-Host entfernt (versehentliche Host-Installation korrigiert)"
}

cleanup_orphaned_packages() {
    local TMPFILE
    TMPFILE=$(mktemp)
    apt-get autoremove --dry-run 2>/dev/null > "$TMPFILE"

    if ! grep -q "Remove" "$TMPFILE"; then
        pause "Keine verwaisten Pakete gefunden."
        rm -f "$TMPFILE"
        return
    fi

    whiptail --title "Verwaiste Pakete (Vorschau)" --scrolltext --textbox "$TMPFILE" 25 100
    rm -f "$TMPFILE"

    if confirm "Diese Pakete jetzt entfernen (apt-get autoremove --purge)?"; then
        run_and_show "apt-get autoremove --purge -y" "Verwaiste Pakete entfernen - Ergebnis"
        log_action "Verwaiste Pakete entfernt (apt autoremove --purge)"
    fi
}

cleanup_residual_configs() {
    local RESIDUAL
    RESIDUAL=$(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')

    if [ -z "$RESIDUAL" ]; then
        pause "Keine Pakete mit uebrig gebliebener Konfiguration gefunden."
        return
    fi

    if ! whiptail --title "Residual-Konfigurationen" --yesno "Folgende deinstallierten Pakete haben noch Konfigurationsreste:\n\n$RESIDUAL\n\nJetzt vollstaendig purgen?" 20 70; then
        return
    fi

    run_and_show "dpkg --purge $RESIDUAL" "Residual-Configs purgen - Ergebnis"
    log_action "Residual-Konfigurationen gepurged: $RESIDUAL"
}

cleanup_broken_symlinks() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "=== Defekte Symlinks unter /usr/local, /opt, /etc ==="
        find /usr/local /opt /etc -xtype l 2>/dev/null
        echo ""
        echo "(Leer = keine defekten Symlinks gefunden)"
    } > "$TMPFILE"
    whiptail --title "Defekte Symlinks" --scrolltext --textbox "$TMPFILE" 25 100

    if confirm "Sollen die oben gefundenen defekten Symlinks geloescht werden?\n(Nur relevant, falls die Liste nicht leer war)"; then
        run_and_show "find /usr/local /opt /etc -xtype l -delete -print 2>/dev/null; echo '--- Bereinigung abgeschlossen ---'" "Defekte Symlinks entfernen - Ergebnis"
        log_action "Defekte Symlinks unter /usr/local, /opt, /etc entfernt"
    fi
    rm -f "$TMPFILE"
}

cleanup_old_tmp_files() {
    local TMPFILE
    TMPFILE=$(mktemp)
    find /tmp /var/tmp -type f -mtime +7 -size +10M 2>/dev/null -exec ls -lh {} \; > "$TMPFILE"

    if [ ! -s "$TMPFILE" ]; then
        pause "Keine alten/grossen Dateien (>10MB, aelter als 7 Tage) in /tmp oder /var/tmp gefunden."
        rm -f "$TMPFILE"
        return
    fi

    whiptail --title "Alte Dateien in /tmp, /var/tmp" --scrolltext --textbox "$TMPFILE" 25 120
    rm -f "$TMPFILE"

    if confirm "Diese Dateien jetzt loeschen?"; then
        run_and_show "find /tmp /var/tmp -type f -mtime +7 -size +10M -delete -print 2>/dev/null; echo '--- Fertig ---'" "Alte Temp-Dateien entfernen - Ergebnis"
        log_action "Alte Temp-Dateien in /tmp, /var/tmp entfernt"
    fi
}

cleanup_apt_cache() {
    run_and_show "du -sh /var/cache/apt/archives 2>/dev/null; apt-get clean; echo '--- APT-Cache geleert ---'; du -sh /var/cache/apt/archives 2>/dev/null" "APT-Cache leeren - Ergebnis"
    log_action "APT-Paketcache geleert"
}

cleanup_check_unused_lxc_disks() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "=== ZFS-Datasets ohne zugehoerigen LXC/VM (evtl. Reste alter/geloeschter Gaeste) ==="
        echo ""
        EXISTING_IDS=$(pct list 2>/dev/null | awk 'NR>1{print $1}'; qm list 2>/dev/null | awk 'NR>1{print $1}')
        for DS in $(zfs list -H -o name 2>/dev/null | grep -E 'subvol-|vm-'); do
            ID=$(echo "$DS" | grep -oP '(?:subvol|vm)-\K[0-9]+')
            if [ -n "$ID" ] && ! echo "$EXISTING_IDS" | grep -qx "$ID"; then
                SIZE=$(zfs list -H -o used "$DS" 2>/dev/null)
                echo "$DS (ID $ID nicht mehr vorhanden, Groesse: $SIZE)"
            fi
        done
        echo ""
        echo "(Leer = keine verwaisten Datasets gefunden. VORSICHT vor dem Loeschen: manuell pruefen, nicht blind entfernen!)"
    } > "$TMPFILE"
    whiptail --title "Verwaiste ZFS-Datasets (VM/LXC-Reste)" --scrolltext --textbox "$TMPFILE" 25 100
    rm -f "$TMPFILE"
}

cleanup_menu() {
    while true; do
        CHOICE=$(whiptail --title "Bereinigung" --menu "Was moechtest du pruefen/bereinigen?" 22 82 10 \
            "1" "Docker auf PVE-Host pruefen (falls versehentlich installiert)" \
            "2" "Docker auf PVE-Host entfernen" \
            "3" "Verwaiste Pakete entfernen (apt autoremove)" \
            "4" "Residual-Konfigurationen purgen" \
            "5" "Defekte Symlinks finden/entfernen" \
            "6" "Alte/grosse Dateien in /tmp aufraeumen" \
            "7" "APT-Paketcache leeren" \
            "8" "Verwaiste ZFS-Datasets pruefen (alte VM/LXC-Reste)" \
            "9" "Zurueck" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) cleanup_detect_docker_on_host ;;
            2) cleanup_remove_docker_on_host ;;
            3) cleanup_orphaned_packages ;;
            4) cleanup_residual_configs ;;
            5) cleanup_broken_symlinks ;;
            6) cleanup_old_tmp_files ;;
            7) cleanup_apt_cache ;;
            8) cleanup_check_unused_lxc_disks ;;
            9|"") break ;;
        esac
    done
}

logs_menu() {
    while true; do
        CHOICE=$(whiptail --title "Logs & Verlauf" --menu "Welches Log ansehen?" 18 78 4 \
            "1" "Rapmenu-Aktionen (System Repair, Repo-Aenderungen)" \
            "2" "Replikations-Logs (auto-ha / sequential)" \
            "3" "Backup/Wartungs-Cron-Logs" \
            "4" "Zurueck" \
            3>&1 1>&2 2>&3)
        [ $? -ne 0 ] && break
        case "$CHOICE" in
            1) run_and_show "tail -n 100 $LOG_DIR/actions.log 2>/dev/null || echo 'Noch keine Aktionen protokolliert.'" "Rapmenu Aktions-Log" ;;
            2) view_logs ;;
            3) run_and_show "tail -n 50 $LOG_DIR/backup-*.log $LOG_DIR/smart-check.log $LOG_DIR/apt-check.log $LOG_DIR/kernel-check.log 2>/dev/null || echo 'Noch keine Cron-Logs vorhanden.'" "Backup/Wartungs-Logs" ;;
            4|"") break ;;
        esac
    done
}

main_menu() {
    while true; do
        CHOICE=$(whiptail --title "Rapmenu v$VERSION" --menu "Hauptmenue - Kategorie waehlen:" 24 78 8 \
            "1" "Replikation" \
            "2" "Cron-Jobs" \
            "3" "Netzwerkfreigaben (NFS/CIFS)" \
            "4" "Paketquellen (APT-Repositories)" \
            "5" "System Repair" \
            "6" "Bereinigung (Fehlinstallationen, Muell)" \
            "7" "Logs & Verlauf" \
            "8" "Deinstallieren" \
            "0" "Beenden" \
            3>&1 1>&2 2>&3)

        EXIT=$?
        if [ $EXIT -ne 0 ]; then
            break
        fi

        case "$CHOICE" in
            1) replication_menu ;;
            2) backup_wartung_menu ;;
            3) shares_menu ;;
            4) apt_repo_menu ;;
            5) system_repair_menu ;;
            6) cleanup_menu ;;
            7) logs_menu ;;
            8) uninstall_tool ;;
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
