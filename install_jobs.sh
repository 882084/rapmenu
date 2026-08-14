#!/bin/bash
# ==========================================================
# CronJobs-Proxmox - Einrichten der einzelnen Aufgaben
# ==========================================================
# Legt je Aufgabe das Helfer-Skript unter $HELPER_DIR an und
# traegt die passende Zeile in $CRON_FILE ein.
# ==========================================================

# ================================================================
# INSTALLATION DER EINZELNEN CRON-JOBS
# ================================================================

install_cron_job() {
    local JOBID="$1" STORAGE DAYS PREFIX

    case "$JOBID" in

    # ---------- Sicherung ----------
    sicherung-alle-taeglich)
        STORAGE=$(get_backup_storage) || return 1
        write_helper "backup-alle-vms-und-container.sh" <<EOS
#!/bin/bash
# Sichert alle VMs und Container
echo "\$(date '+%d.%m.%Y %H:%M') - Starte Sicherung aller Systeme"
vzdump --all --mode snapshot --compress zstd --storage $STORAGE
echo "\$(date '+%d.%m.%Y %H:%M') - Sicherung beendet"
EOS
        add_cron_line "0 2 * * * root $HELPER_DIR/backup-alle-vms-und-container.sh >> $LOG_DIR/sicherung-alle.log 2>&1" "$JOBID"
        ;;

    sicherung-nur-vms-taeglich)
        STORAGE=$(get_backup_storage) || return 1
        write_helper "backup-nur-vms.sh" <<EOS
#!/bin/bash
# Sichert nur virtuelle Maschinen (keine Container)
VMIDS=\$(qm list 2>/dev/null | awk 'NR>1{print \$1}')
if [ -z "\$VMIDS" ]; then
    echo "\$(date '+%d.%m.%Y %H:%M') - Keine VMs vorhanden, nichts zu sichern"
    exit 0
fi
echo "\$(date '+%d.%m.%Y %H:%M') - Sichere VMs: \$VMIDS"
vzdump \$VMIDS --mode snapshot --compress zstd --storage $STORAGE
EOS
        add_cron_line "30 2 * * * root $HELPER_DIR/backup-nur-vms.sh >> $LOG_DIR/sicherung-vms.log 2>&1" "$JOBID"
        ;;

    sicherung-nur-container-taeglich)
        STORAGE=$(get_backup_storage) || return 1
        write_helper "backup-nur-container.sh" <<EOS
#!/bin/bash
# Sichert nur LXC-Container (keine VMs)
CTIDS=\$(pct list 2>/dev/null | awk 'NR>1{print \$1}')
if [ -z "\$CTIDS" ]; then
    echo "\$(date '+%d.%m.%Y %H:%M') - Keine Container vorhanden, nichts zu sichern"
    exit 0
fi
echo "\$(date '+%d.%m.%Y %H:%M') - Sichere Container: \$CTIDS"
vzdump \$CTIDS --mode snapshot --compress zstd --storage $STORAGE
EOS
        add_cron_line "0 3 * * * root $HELPER_DIR/backup-nur-container.sh >> $LOG_DIR/sicherung-container.log 2>&1" "$JOBID"
        ;;

    sicherung-alte-loeschen-woechentlich)
        DAYS=$(eingabe_dialog "Aufbewahrungsdauer" \
            "Wie viele Tage sollen Sicherungen aufbewahrt werden?\n\nAeltere Sicherungen werden dann automatisch geloescht.\nEmpfehlung: 30 Tage." "30")
        [ -z "${DAYS:-}" ] && DAYS=30
        write_helper "backup-alte-loeschen.sh" <<EOS
#!/bin/bash
# Loescht Sicherungsdateien aelter als $DAYS Tage
TAGE=$DAYS
GEFUNDEN=0
for VERZ in /var/lib/vz/dump \$(pvesm status 2>/dev/null | awk 'NR>1 && \$2 ~ /dir|nfs|cifs/ {print \$1}' | while read -r S; do pvesm path "\$S:" 2>/dev/null; done); do
    [ -d "\$VERZ" ] || continue
    while IFS= read -r F; do
        echo "Loesche: \$F"
        rm -f "\$F" "\$F.notes" "\$F.log"
        GEFUNDEN=1
    done < <(find "\$VERZ" -maxdepth 2 -name 'vzdump-*' -type f -mtime +\$TAGE 2>/dev/null)
done
[ "\$GEFUNDEN" -eq 0 ] && echo "\$(date '+%d.%m.%Y %H:%M') - Keine Sicherungen aelter als \$TAGE Tage gefunden"
EOS
        add_cron_line "0 4 * * 0 root $HELPER_DIR/backup-alte-loeschen.sh >> $LOG_DIR/sicherung-aufraeumen.log 2>&1" "$JOBID"
        ;;

    sicherung-pruefen-woechentlich)
        write_helper "backup-integritaet-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft, ob die Sicherungsdateien fehlerfrei lesbar sind
echo "$(date '+%d.%m.%Y %H:%M') - Pruefe Sicherungsdateien"
ANZ=0; FEHLER=0
for F in /var/lib/vz/dump/vzdump-*.zst /var/lib/vz/dump/vzdump-*.gz /var/lib/vz/dump/vzdump-*.lzo; do
    [ -f "$F" ] || continue
    ANZ=$((ANZ+1))
    case "$F" in
        *.zst) PRUEF="zstd -t" ;;
        *.gz)  PRUEF="gzip -t" ;;
        *.lzo) PRUEF="lzop -t" ;;
    esac
    if $PRUEF "$F" >/dev/null 2>&1; then
        echo "  OK      $(basename "$F")"
    else
        echo "  DEFEKT  $(basename "$F")  <-- diese Sicherung ist unbrauchbar!"
        FEHLER=$((FEHLER+1))
    fi
done
echo "Ergebnis: $ANZ Dateien geprueft, $FEHLER defekt"
[ "$FEHLER" -gt 0 ] && logger -t cronjobs-proxmox "WARNUNG: $FEHLER defekte Sicherungsdateien gefunden"
exit 0
EOS
        add_cron_line "0 5 * * 0 root $HELPER_DIR/backup-integritaet-pruefen.sh >> $LOG_DIR/sicherung-pruefung.log 2>&1" "$JOBID"
        ;;

    sicherung-bericht-woechentlich)
        write_helper "backup-wochenbericht.sh" <<'EOS'
#!/bin/bash
# Wochenbericht ueber vorhandene Sicherungen
echo "=========================================================="
echo " Sicherungs-Wochenbericht vom $(date '+%d.%m.%Y')"
echo "=========================================================="
echo ""
echo "--- Vorhandene Sicherungsdateien ---"
ls -lht /var/lib/vz/dump/vzdump-* 2>/dev/null | head -40 || echo "Keine Sicherungen gefunden"
echo ""
echo "--- Belegter Speicherplatz ---"
du -sh /var/lib/vz/dump 2>/dev/null
echo ""
echo "--- Systeme OHNE aktuelle Sicherung (aelter als 7 Tage) ---"
for TYP in qm pct; do
    for ID in $($TYP list 2>/dev/null | awk 'NR>1{print $1}'); do
        NEUESTE=$(find /var/lib/vz/dump -name "vzdump-*-${ID}-*" -printf '%T@\n' 2>/dev/null | sort -n | tail -1)
        if [ -z "$NEUESTE" ]; then
            echo "  ID $ID: NOCH NIE gesichert!"
        else
            ALTER=$(( ($(date +%s) - ${NEUESTE%.*}) / 86400 ))
            [ "$ALTER" -gt 7 ] && echo "  ID $ID: letzte Sicherung vor $ALTER Tagen"
        fi
    done
done
echo ""
EOS
        add_cron_line "0 7 * * 1 root $HELPER_DIR/backup-wochenbericht.sh >> $LOG_DIR/sicherung-bericht.log 2>&1" "$JOBID"
        ;;

    sicherung-testrestore-erinnerung-monatlich)
        write_helper "backup-testwiederherstellung-erinnerung.sh" <<'EOS'
#!/bin/bash
# Monatliche Erinnerung an einen Test-Restore
MELDUNG="ERINNERUNG: Bitte diesen Monat eine Sicherung testweise wiederherstellen. Eine nie getestete Sicherung ist keine Sicherung."
echo "$(date '+%d.%m.%Y %H:%M') - $MELDUNG"
logger -t cronjobs-proxmox "$MELDUNG"
echo ""
echo "So gehst du vor (in der Weboberflaeche):"
echo "  1. Eine beliebige, unwichtige VM oder Container auswaehlen"
echo "  2. Reiter 'Backup' oeffnen"
echo "  3. Eine Sicherung markieren und auf 'Restore' klicken"
echo "  4. Als neue ID eine freie Nummer waehlen (Original bleibt unangetastet)"
echo "  5. Testsystem starten, kurz pruefen, danach wieder loeschen"
EOS
        add_cron_line "0 8 1 * * root $HELPER_DIR/backup-testwiederherstellung-erinnerung.sh >> $LOG_DIR/sicherung-erinnerung.log 2>&1" "$JOBID"
        ;;

    # ---------- Snapshots ----------
    snapshot-erstellen-taeglich)
        write_helper "snapshot-taeglich-erstellen.sh" <<'EOS'
#!/bin/bash
# Erstellt taegliche Momentaufnahmen mit dem Namen auto-JJJJMMTT
NAME="auto-$(date '+%Y%m%d')"
echo "$(date '+%d.%m.%Y %H:%M') - Erstelle Snapshots mit Namen $NAME"
for TYP in qm pct; do
    for ID in $($TYP list 2>/dev/null | awk 'NR>1 && $2=="running"{print $1}'); do
        if $TYP listsnapshot "$ID" 2>/dev/null | grep -q "$NAME"; then
            echo "  ID $ID: Snapshot $NAME existiert bereits"
            continue
        fi
        if $TYP snapshot "$ID" "$NAME" --description "Automatisch erstellt" >/dev/null 2>&1; then
            echo "  ID $ID: Snapshot $NAME erstellt"
        else
            echo "  ID $ID: Snapshot fehlgeschlagen (Speicher unterstuetzt evtl. keine Snapshots)"
        fi
    done
done
EOS
        add_cron_line "30 4 * * * root $HELPER_DIR/snapshot-taeglich-erstellen.sh >> $LOG_DIR/snapshot-erstellen.log 2>&1" "$JOBID"
        ;;

    snapshot-aufraeumen-taeglich)
        PREFIX=$(eingabe_dialog "Namensanfang der Snapshots" \
            "Nur Snapshots, deren Name so beginnt, werden geloescht.\n\nSo bleiben von Hand angelegte Snapshots garantiert erhalten." "auto-")
        [ -z "${PREFIX:-}" ] && PREFIX="auto-"
        DAYS=$(eingabe_dialog "Aufbewahrungsdauer" \
            "Snapshots aelter als wie viele Tage loeschen?\n\nEmpfehlung: 7 Tage." "7")
        [ -z "${DAYS:-}" ] && DAYS=7
        write_helper "snapshot-alte-aufraeumen.sh" <<EOS
#!/bin/bash
# Loescht automatische Snapshots aelter als $DAYS Tage
MAX_TAGE=$DAYS
PRAEFIX='$PREFIX'
echo "\$(date '+%d.%m.%Y %H:%M') - Raeume Snapshots mit Praefix '\$PRAEFIX' aelter als \$MAX_TAGE Tage auf"
for TYP in qm pct; do
    for ID in \$(\$TYP list 2>/dev/null | awk 'NR>1{print \$1}'); do
        for SNAP in \$(\$TYP listsnapshot "\$ID" 2>/dev/null | grep -v current | awk '{print \$2}' | grep -v '^\$'); do
            case "\$SNAP" in
                "\$PRAEFIX"*) ;;
                *) continue ;;
            esac
            ZEIT=\$(\$TYP config "\$ID" --snapshot "\$SNAP" 2>/dev/null | grep snaptime | awk '{print \$2}')
            [ -z "\$ZEIT" ] && continue
            ALTER=\$(( (\$(date +%s) - ZEIT) / 86400 ))
            if [ "\$ALTER" -gt "\$MAX_TAGE" ]; then
                echo "  ID \$ID: loesche Snapshot '\$SNAP' (\${ALTER} Tage alt)"
                \$TYP delsnapshot "\$ID" "\$SNAP" >/dev/null 2>&1
            fi
        done
    done
done
EOS
        add_cron_line "30 5 * * * root $HELPER_DIR/snapshot-alte-aufraeumen.sh >> $LOG_DIR/snapshot-aufraeumen.log 2>&1" "$JOBID"
        ;;

    snapshot-zfs-aufraeumen-taeglich)
        DAYS=$(eingabe_dialog "Aufbewahrungsdauer" \
            "ZFS-Snapshots aelter als wie viele Tage loeschen?\n\nAchtung: Snapshots der Proxmox-Replikation\nwerden NICHT angefasst." "14")
        [ -z "${DAYS:-}" ] && DAYS=14
        write_helper "zfs-snapshots-aufraeumen.sh" <<EOS
#!/bin/bash
# Loescht verwaiste ZFS-Snapshots aelter als $DAYS Tage
MAX_TAGE=$DAYS
JETZT=\$(date +%s)
echo "\$(date '+%d.%m.%Y %H:%M') - Suche ZFS-Snapshots aelter als \$MAX_TAGE Tage"
zfs list -t snapshot -H -o name,creation -p 2>/dev/null | while read -r NAME ERSTELLT; do
    # Replikations-Snapshots von Proxmox unangetastet lassen
    case "\$NAME" in
        *__replicate_*|*@__base__*) continue ;;
    esac
    ALTER=\$(( (JETZT - ERSTELLT) / 86400 ))
    if [ "\$ALTER" -gt "\$MAX_TAGE" ]; then
        echo "  loesche \$NAME (\${ALTER} Tage alt)"
        zfs destroy "\$NAME" 2>&1
    fi
done
EOS
        add_cron_line "45 5 * * * root $HELPER_DIR/zfs-snapshots-aufraeumen.sh >> $LOG_DIR/snapshot-zfs.log 2>&1" "$JOBID"
        ;;

    snapshot-anzahl-warnung-taeglich)
        write_helper "snapshot-anzahl-warnung.sh" <<'EOS'
#!/bin/bash
# Warnt, wenn eine VM/ein Container zu viele Snapshots hat
GRENZE=10
for TYP in qm pct; do
    for ID in $($TYP list 2>/dev/null | awk 'NR>1{print $1}'); do
        ANZ=$($TYP listsnapshot "$ID" 2>/dev/null | grep -vc current)
        if [ "$ANZ" -gt "$GRENZE" ]; then
            MELDUNG="ID $ID hat $ANZ Snapshots (Grenze $GRENZE) - bitte aufraeumen, das kostet Speicher und Leistung"
            echo "$(date '+%d.%m.%Y %H:%M') - $MELDUNG"
            logger -t cronjobs-proxmox "$MELDUNG"
        fi
    done
done
EOS
        add_cron_line "0 9 * * * root $HELPER_DIR/snapshot-anzahl-warnung.sh >> $LOG_DIR/snapshot-warnung.log 2>&1" "$JOBID"
        ;;

    # ---------- Speicher und ZFS ----------
    zfs-scrub-monatlich)
        write_helper "zfs-scrub-datenpruefung.sh" <<'EOS'
#!/bin/bash
# Startet fuer jeden ZFS-Pool eine Datenpruefung (Scrub)
# Nur am ersten Sonntag im Monat ausfuehren
[ "$(date +%d)" -gt 7 ] && exit 0
for POOL in $(zpool list -H -o name 2>/dev/null); do
    if zpool status "$POOL" | grep -q "scrub in progress"; then
        echo "$(date '+%d.%m.%Y %H:%M') - Pool $POOL: Scrub laeuft bereits"
        continue
    fi
    echo "$(date '+%d.%m.%Y %H:%M') - Starte Scrub fuer Pool $POOL"
    zpool scrub "$POOL"
done
EOS
        add_cron_line "0 2 * * 0 root $HELPER_DIR/zfs-scrub-datenpruefung.sh >> $LOG_DIR/zfs-scrub.log 2>&1" "$JOBID"
        ;;

    zfs-pool-status-taeglich)
        write_helper "zfs-pool-gesundheit-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft den Zustand aller ZFS-Pools
command -v zpool >/dev/null 2>&1 || exit 0
for POOL in $(zpool list -H -o name 2>/dev/null); do
    ZUSTAND=$(zpool list -H -o health "$POOL")
    BELEGT=$(zpool list -H -o capacity "$POOL")
    if [ "$ZUSTAND" != "ONLINE" ]; then
        MELDUNG="ACHTUNG: ZFS-Pool $POOL ist im Zustand $ZUSTAND - moeglicherweise ist eine Festplatte ausgefallen!"
        echo "$(date '+%d.%m.%Y %H:%M') - $MELDUNG"
        logger -t cronjobs-proxmox "$MELDUNG"
        zpool status "$POOL"
    else
        echo "$(date '+%d.%m.%Y %H:%M') - Pool $POOL: in Ordnung ($BELEGT belegt)"
    fi
    FEHLER=$(zpool status "$POOL" | awk '/ONLINE|DEGRADED|FAULTED/ && NF>=5 {s+=$3+$4+$5} END{print s+0}')
    if [ "${FEHLER:-0}" -gt 0 ]; then
        MELDUNG="ACHTUNG: Pool $POOL meldet $FEHLER Lese-/Schreib-/Pruefsummenfehler"
        echo "$MELDUNG"
        logger -t cronjobs-proxmox "$MELDUNG"
    fi
done
EOS
        add_cron_line "30 6 * * * root $HELPER_DIR/zfs-pool-gesundheit-pruefen.sh >> $LOG_DIR/zfs-status.log 2>&1" "$JOBID"
        ;;

    zfs-trim-monatlich)
        write_helper "zfs-trim-ssd.sh" <<'EOS'
#!/bin/bash
# Fuehrt TRIM auf allen ZFS-Pools aus (haelt SSDs schnell)
[ "$(date +%d)" -gt 7 ] && exit 0
for POOL in $(zpool list -H -o name 2>/dev/null); do
    echo "$(date '+%d.%m.%Y %H:%M') - Starte TRIM fuer Pool $POOL"
    zpool trim "$POOL" 2>&1 || echo "  (Pool unterstuetzt kein TRIM - das ist bei normalen Festplatten normal)"
done
EOS
        add_cron_line "0 3 * * 6 root $HELPER_DIR/zfs-trim-ssd.sh >> $LOG_DIR/zfs-trim.log 2>&1" "$JOBID"
        ;;

    zfs-arc-bericht-woechentlich)
        write_helper "zfs-arc-speicher-bericht.sh" <<'EOS'
#!/bin/bash
# Bericht ueber den Arbeitsspeicher, den ZFS als Cache belegt
echo "$(date '+%d.%m.%Y %H:%M') - ZFS Arbeitsspeicher-Cache (ARC)"
if [ -f /proc/spl/kstat/zfs/arcstats ]; then
    GROESSE=$(awk '/^size /{printf "%.1f", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats)
    MAX=$(awk '/^c_max /{printf "%.1f", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats)
    TREFFER=$(awk '/^hits /{h=$3} /^misses /{m=$3} END{if(h+m>0) printf "%.1f", h*100/(h+m)}' /proc/spl/kstat/zfs/arcstats)
    echo "  Aktuell belegt: ${GROESSE} GB"
    echo "  Maximal erlaubt: ${MAX} GB"
    echo "  Trefferquote: ${TREFFER} % (hoeher ist besser, ueber 90% ist sehr gut)"
    echo ""
    echo "  Hinweis: Wenn deine VMs zu wenig Arbeitsspeicher haben, kannst du"
    echo "  das Maximum begrenzen (Menue -> Reparatur -> Speicher und ZFS)."
else
    echo "  ZFS ist auf diesem System nicht aktiv."
fi
free -h
EOS
        add_cron_line "0 8 * * 0 root $HELPER_DIR/zfs-arc-speicher-bericht.sh >> $LOG_DIR/zfs-arc.log 2>&1" "$JOBID"
        ;;

    speicherplatz-warnung-taeglich)
        write_helper "speicherplatz-warnung.sh" <<'EOS'
#!/bin/bash
# Warnt, wenn ein Laufwerk voll wird
GRENZE=90
df -hP -x tmpfs -x devtmpfs -x squashfs 2>/dev/null | awk -v g="$GRENZE" 'NR>1 {
    gsub("%","",$5);
    if ($5+0 > g) print "ACHTUNG: " $6 " ist zu " $5 "% voll (Geraet " $1 ", nur noch " $4 " frei)";
    else print "OK: " $6 " (" $5 "% belegt, " $4 " frei)"
}' | while IFS= read -r ZEILE; do
    echo "$(date '+%d.%m.%Y %H:%M') - $ZEILE"
    case "$ZEILE" in ACHTUNG*) logger -t cronjobs-proxmox "$ZEILE" ;; esac
done
EOS
        add_cron_line "0 8 * * * root $HELPER_DIR/speicherplatz-warnung.sh >> $LOG_DIR/speicherplatz.log 2>&1" "$JOBID"
        ;;

    lvm-thin-pruefen-taeglich)
        write_helper "lvm-thin-pool-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft LVM-Thin-Pools auf Ueberfuellung
command -v lvs >/dev/null 2>&1 || exit 0
lvs --noheadings -o lv_name,vg_name,lv_size,data_percent,metadata_percent --select 'lv_layout=~thin' 2>/dev/null | \
while read -r NAME VG GROESSE DATEN META; do
    [ -z "$NAME" ] && continue
    DATEN_INT=${DATEN%%.*}; META_INT=${META%%.*}
    echo "$(date '+%d.%m.%Y %H:%M') - Thin-Pool $VG/$NAME: Daten ${DATEN}%, Metadaten ${META}%"
    if [ "${DATEN_INT:-0}" -gt 85 ] || [ "${META_INT:-0}" -gt 85 ]; then
        MELDUNG="ACHTUNG: Thin-Pool $VG/$NAME ist fast voll (Daten ${DATEN}%, Metadaten ${META}%). Bei 100% werden VM-Festplatten beschaedigt!"
        echo "$MELDUNG"
        logger -t cronjobs-proxmox "$MELDUNG"
    fi
done
EOS
        add_cron_line "15 8 * * * root $HELPER_DIR/lvm-thin-pool-pruefen.sh >> $LOG_DIR/lvm-thin.log 2>&1" "$JOBID"
        ;;

    verwaiste-datentraeger-woechentlich)
        write_helper "verwaiste-datentraeger-suchen.sh" <<'EOS'
#!/bin/bash
# Sucht virtuelle Festplatten von bereits geloeschten VMs/Containern
echo "$(date '+%d.%m.%Y %H:%M') - Suche verwaiste virtuelle Festplatten"
VORHANDEN=$( (pct list 2>/dev/null | awk 'NR>1{print $1}'; qm list 2>/dev/null | awk 'NR>1{print $1}') )
GEFUNDEN=0
for DS in $(zfs list -H -o name 2>/dev/null | grep -E 'subvol-|vm-'); do
    ID=$(echo "$DS" | grep -oE '(subvol|vm)-[0-9]+' | grep -oE '[0-9]+')
    [ -z "$ID" ] && continue
    if ! echo "$VORHANDEN" | grep -qx "$ID"; then
        GROESSE=$(zfs list -H -o used "$DS" 2>/dev/null)
        echo "  $DS  (ID $ID existiert nicht mehr, belegt $GROESSE)"
        GEFUNDEN=1
    fi
done
if [ "$GEFUNDEN" -eq 0 ]; then
    echo "  Keine verwaisten Datentraeger gefunden - alles sauber."
else
    echo ""
    echo "  WICHTIG: Es wurde NICHTS geloescht. Bitte pruefe die Liste."
    echo "  Loeschen kannst du sie im Menue unter Reparatur -> Aufraeumen."
fi
EOS
        add_cron_line "0 9 * * 6 root $HELPER_DIR/verwaiste-datentraeger-suchen.sh >> $LOG_DIR/verwaiste-datentraeger.log 2>&1" "$JOBID"
        ;;

    speicher-status-taeglich)
        write_helper "speicher-status-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft, ob alle eingebundenen Speicher erreichbar sind
pvesm status 2>/dev/null | awk 'NR>1{print $1, $2, $3}' | while read -r NAME TYP AKTIV; do
    if [ "$AKTIV" != "active" ]; then
        MELDUNG="ACHTUNG: Speicher '$NAME' (Typ $TYP) ist NICHT erreichbar. VMs darauf starten nicht und Sicherungen schlagen fehl."
        echo "$(date '+%d.%m.%Y %H:%M') - $MELDUNG"
        logger -t cronjobs-proxmox "$MELDUNG"
    else
        echo "$(date '+%d.%m.%Y %H:%M') - Speicher '$NAME' ($TYP): erreichbar"
    fi
done
EOS
        add_cron_line "30 7 * * * root $HELPER_DIR/speicher-status-pruefen.sh >> $LOG_DIR/speicher-status.log 2>&1" "$JOBID"
        ;;

    # ---------- Wartung ----------
    updates-pruefen-woechentlich)
        write_helper "updates-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft auf verfuegbare Updates - installiert bewusst NICHTS
apt-get update -qq 2>/dev/null
LISTE=$(apt list --upgradable 2>/dev/null | grep -v '^Listing')
if [ -n "$LISTE" ]; then
    ANZ=$(echo "$LISTE" | wc -l)
    echo "$(date '+%d.%m.%Y %H:%M') - $ANZ Updates verfuegbar:"
    echo "$LISTE"
    echo ""
    echo "Installieren kannst du sie in der Weboberflaeche unter"
    echo "Node -> Updates -> Refresh -> Upgrade."
else
    echo "$(date '+%d.%m.%Y %H:%M') - System ist aktuell, keine Updates verfuegbar"
fi
EOS
        add_cron_line "0 6 * * 1 root $HELPER_DIR/updates-pruefen.sh >> $LOG_DIR/updates.log 2>&1" "$JOBID"
        ;;

    sicherheitsupdates-pruefen-taeglich)
        write_helper "sicherheitsupdates-pruefen.sh" <<'EOS'
#!/bin/bash
# Meldet ausschliesslich sicherheitsrelevante Updates
apt-get update -qq 2>/dev/null
LISTE=$(apt-get -s dist-upgrade 2>/dev/null | grep -i '^Inst.*security')
if [ -n "$LISTE" ]; then
    ANZ=$(echo "$LISTE" | wc -l)
    MELDUNG="$ANZ Sicherheitsupdates verfuegbar - diese sollten zeitnah eingespielt werden"
    echo "$(date '+%d.%m.%Y %H:%M') - $MELDUNG"
    echo "$LISTE"
    logger -t cronjobs-proxmox "$MELDUNG"
else
    echo "$(date '+%d.%m.%Y %H:%M') - Keine Sicherheitsupdates ausstehend"
fi
EOS
        add_cron_line "15 6 * * * root $HELPER_DIR/sicherheitsupdates-pruefen.sh >> $LOG_DIR/sicherheitsupdates.log 2>&1" "$JOBID"
        ;;

    smart-pruefen-taeglich)
        write_helper "festplatten-smart-pruefen.sh" <<'EOS'
#!/bin/bash
# Liest die Selbstdiagnose-Werte aller Festplatten und SSDs aus
command -v smartctl >/dev/null 2>&1 || { echo "smartctl fehlt - bitte 'smartmontools' installieren"; exit 0; }
for PLATTE in $(lsblk -d -n -o NAME 2>/dev/null | grep -E '^sd|^nvme'); do
    ERGEBNIS=$(smartctl -H "/dev/$PLATTE" 2>/dev/null | grep -iE 'result|status' | head -1)
    echo "$(date '+%d.%m.%Y %H:%M') - /dev/$PLATTE: ${ERGEBNIS:-keine SMART-Daten}"
    if echo "$ERGEBNIS" | grep -qiE 'failed|failing'; then
        MELDUNG="ACHTUNG: Festplatte /dev/$PLATTE meldet einen Fehler. Bitte zeitnah austauschen und Sicherung pruefen!"
        echo "$MELDUNG"
        logger -t cronjobs-proxmox "$MELDUNG"
    fi
    DEFEKT=$(smartctl -A "/dev/$PLATTE" 2>/dev/null | awk '/Reallocated_Sector_Ct|Current_Pending_Sector/{print $2": "$10}')
    [ -n "$DEFEKT" ] && echo "    Defekte Sektoren: $DEFEKT"
done
EOS
        add_cron_line "0 6 * * * root $HELPER_DIR/festplatten-smart-pruefen.sh >> $LOG_DIR/smart.log 2>&1" "$JOBID"
        ;;

    kernel-neustart-pruefen-taeglich)
        write_helper "kernel-neustart-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft, ob nach einem Kernel-Update ein Neustart faellig ist
LAEUFT=$(uname -r)
INSTALLIERT=$(dpkg -l 2>/dev/null | grep -E 'proxmox-kernel-[0-9]|pve-kernel-[0-9]' | awk '{print $3}' | sed 's/^[0-9]*://' | sort -V | tail -1)
if [ -n "$INSTALLIERT" ] && ! echo "$INSTALLIERT" | grep -q "$(echo "$LAEUFT" | cut -d- -f1)"; then
    MELDUNG="Ein Neustart ist faellig: es laeuft Kernel $LAEUFT, installiert ist bereits $INSTALLIERT"
    echo "$(date '+%d.%m.%Y %H:%M') - $MELDUNG"
    logger -t cronjobs-proxmox "$MELDUNG"
    echo "Neustart planen: am besten ausserhalb der Arbeitszeit, VMs fahren dabei mit herunter."
else
    echo "$(date '+%d.%m.%Y %H:%M') - Kein Neustart noetig (Kernel $LAEUFT ist aktuell)"
fi
EOS
        add_cron_line "0 7 * * * root $HELPER_DIR/kernel-neustart-pruefen.sh >> $LOG_DIR/kernel.log 2>&1" "$JOBID"
        ;;

    logs-aufraeumen-woechentlich)
        write_helper "logs-aufraeumen.sh" <<'EOS'
#!/bin/bash
# Begrenzt die Groesse der System-Protokolle
VORHER=$(journalctl --disk-usage 2>/dev/null)
journalctl --vacuum-size=500M 2>&1
NACHHER=$(journalctl --disk-usage 2>/dev/null)
echo "$(date '+%d.%m.%Y %H:%M') - Logs aufgeraeumt"
echo "  Vorher:  $VORHER"
echo "  Nachher: $NACHHER"
EOS
        add_cron_line "0 3 * * 0 root $HELPER_DIR/logs-aufraeumen.sh >> $LOG_DIR/logs-aufraeumen.log 2>&1" "$JOBID"
        ;;

    paketcache-leeren-woechentlich)
        write_helper "paketcache-leeren.sh" <<'EOS'
#!/bin/bash
# Loescht heruntergeladene, nicht mehr benoetigte Installationsdateien
VORHER=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
apt-get clean
NACHHER=$(du -sh /var/cache/apt/archives 2>/dev/null | cut -f1)
echo "$(date '+%d.%m.%Y %H:%M') - Paketcache geleert: $VORHER -> $NACHHER"
EOS
        add_cron_line "30 3 * * 0 root $HELPER_DIR/paketcache-leeren.sh >> $LOG_DIR/paketcache.log 2>&1" "$JOBID"
        ;;

    alte-kernel-entfernen-monatlich)
        write_helper "alte-kernel-entfernen.sh" <<'EOS'
#!/bin/bash
# Entfernt alte, nicht mehr benoetigte Kernel-Versionen
echo "$(date '+%d.%m.%Y %H:%M') - Entferne nicht mehr benoetigte Kernel"
if command -v proxmox-boot-tool >/dev/null 2>&1; then
    proxmox-boot-tool kernel list 2>/dev/null
fi
apt-get autoremove --purge -y 2>&1 | tail -20
if command -v proxmox-boot-tool >/dev/null 2>&1; then
    proxmox-boot-tool refresh 2>&1 | tail -5
fi
echo "Freier Platz auf /boot:"
df -h /boot 2>/dev/null | tail -1
EOS
        add_cron_line "0 4 5 * * root $HELPER_DIR/alte-kernel-entfernen.sh >> $LOG_DIR/kernel-aufraeumen.log 2>&1" "$JOBID"
        ;;

    temp-aufraeumen-woechentlich)
        write_helper "temp-dateien-aufraeumen.sh" <<'EOS'
#!/bin/bash
# Loescht alte, grosse temporaere Dateien
ANZ=$(find /tmp /var/tmp -type f -mtime +7 -size +10M 2>/dev/null | wc -l)
if [ "$ANZ" -gt 0 ]; then
    echo "$(date '+%d.%m.%Y %H:%M') - Loesche $ANZ alte temporaere Dateien:"
    find /tmp /var/tmp -type f -mtime +7 -size +10M -print -delete 2>/dev/null
else
    echo "$(date '+%d.%m.%Y %H:%M') - Keine alten temporaeren Dateien gefunden"
fi
EOS
        add_cron_line "30 4 * * 6 root $HELPER_DIR/temp-dateien-aufraeumen.sh >> $LOG_DIR/temp-aufraeumen.log 2>&1" "$JOBID"
        ;;

    dienste-ueberwachen-alle-15min)
        write_helper "pve-dienste-ueberwachen.sh" <<'EOS'
#!/bin/bash
# Startet abgestuerzte Proxmox-Dienste automatisch neu
for DIENST in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
    systemctl list-unit-files 2>/dev/null | grep -q "^${DIENST}.service" || continue
    if ! systemctl is-active --quiet "$DIENST"; then
        MELDUNG="Dienst $DIENST war gestoppt - wird neu gestartet"
        echo "$(date '+%d.%m.%Y %H:%M') - $MELDUNG"
        logger -t cronjobs-proxmox "$MELDUNG"
        systemctl restart "$DIENST" 2>&1
        sleep 3
        if systemctl is-active --quiet "$DIENST"; then
            echo "  Neustart erfolgreich"
        else
            echo "  Neustart FEHLGESCHLAGEN - bitte manuell pruefen"
            logger -t cronjobs-proxmox "Neustart von $DIENST fehlgeschlagen"
        fi
    fi
done
EOS
        add_cron_line "*/15 * * * * root $HELPER_DIR/pve-dienste-ueberwachen.sh >> $LOG_DIR/dienste.log 2>&1" "$JOBID"
        ;;

    # ---------- Sicherheit ----------
    ssl-zertifikat-erneuern-taeglich)
        write_helper "ssl-zertifikat-erneuern.sh" <<'EOS'
#!/bin/bash
# Erneuert das HTTPS-Zertifikat, falls noetig
if ! pvenode acme cert order --help >/dev/null 2>&1; then
    exit 0
fi
AUSGABE=$(pvenode acme cert renew 2>&1)
echo "$(date '+%d.%m.%Y %H:%M') - $AUSGABE"
echo "$AUSGABE" | logger -t cronjobs-proxmox
EOS
        add_cron_line "0 3 * * * root $HELPER_DIR/ssl-zertifikat-erneuern.sh >> $LOG_DIR/zertifikat.log 2>&1" "$JOBID"
        ;;

    anmeldungen-pruefen-taeglich)
        write_helper "anmeldungen-pruefen.sh" <<'EOS'
#!/bin/bash
# Zaehlt fehlgeschlagene Anmeldeversuche der letzten 24 Stunden
echo "$(date '+%d.%m.%Y %H:%M') - Fehlgeschlagene Anmeldeversuche (letzte 24h)"
SSH=$(journalctl -u ssh -u sshd --since "24 hours ago" 2>/dev/null | grep -ci "failed password")
WEB=$(journalctl --since "24 hours ago" 2>/dev/null | grep -ci "authentication failure")
echo "  SSH:            ${SSH:-0}"
echo "  Weboberflaeche: ${WEB:-0}"
echo ""
echo "  Haeufigste Absender-Adressen:"
journalctl -u ssh -u sshd --since "24 hours ago" 2>/dev/null | grep -i "failed password" | \
    grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort | uniq -c | sort -rn | head -10
GESAMT=$(( ${SSH:-0} + ${WEB:-0} ))
if [ "$GESAMT" -gt 50 ]; then
    MELDUNG="ACHTUNG: $GESAMT fehlgeschlagene Anmeldeversuche in 24 Stunden - moeglicherweise ein Angriffsversuch"
    echo "$MELDUNG"
    logger -t cronjobs-proxmox "$MELDUNG"
fi
EOS
        add_cron_line "45 7 * * * root $HELPER_DIR/anmeldungen-pruefen.sh >> $LOG_DIR/anmeldungen.log 2>&1" "$JOBID"
        ;;

    firewall-status-woechentlich)
        write_helper "firewall-status-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft, ob die Proxmox-Firewall aktiv ist
echo "$(date '+%d.%m.%Y %H:%M') - Firewall-Status"
pve-firewall status 2>&1
echo ""
echo "--- Aktive Regeln (Datacenter) ---"
cat /etc/pve/firewall/cluster.fw 2>/dev/null || echo "Keine clusterweiten Regeln konfiguriert"
if ! pve-firewall status 2>/dev/null | grep -qi "enabled"; then
    logger -t cronjobs-proxmox "Hinweis: Die Proxmox-Firewall ist derzeit nicht aktiv"
fi
EOS
        add_cron_line "15 7 * * 1 root $HELPER_DIR/firewall-status-pruefen.sh >> $LOG_DIR/firewall.log 2>&1" "$JOBID"
        ;;

    zeitsynchronisierung-pruefen-taeglich)
        write_helper "zeitsynchronisierung-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft, ob die Systemuhr korrekt synchronisiert ist
echo "$(date '+%d.%m.%Y %H:%M') - Zeitsynchronisierung"
if command -v timedatectl >/dev/null 2>&1; then
    timedatectl status 2>/dev/null | grep -E "Local time|Time zone|synchronized|NTP service"
    if ! timedatectl status 2>/dev/null | grep -qi "synchronized: yes"; then
        MELDUNG="ACHTUNG: Die Systemuhr ist nicht synchronisiert. Das fuehrt zu Problemen mit Zertifikaten, Cluster und Sicherungen."
        echo "$MELDUNG"
        logger -t cronjobs-proxmox "$MELDUNG"
    fi
fi
if command -v chronyc >/dev/null 2>&1; then
    chronyc tracking 2>/dev/null | grep -E "System time|Last offset"
fi
EOS
        add_cron_line "45 6 * * * root $HELPER_DIR/zeitsynchronisierung-pruefen.sh >> $LOG_DIR/zeit.log 2>&1" "$JOBID"
        ;;

    benutzer-audit-monatlich)
        write_helper "benutzerkonten-pruefen.sh" <<'EOS'
#!/bin/bash
# Uebersicht ueber alle Proxmox-Benutzer, Gruppen und Zugangstokens
echo "=========================================================="
echo " Benutzer-Uebersicht vom $(date '+%d.%m.%Y')"
echo "=========================================================="
echo ""
echo "--- Benutzerkonten ---"
pveum user list 2>/dev/null
echo ""
echo "--- Gruppen ---"
pveum group list 2>/dev/null
echo ""
echo "--- API-Zugangstokens ---"
for U in $(pveum user list 2>/dev/null | awk 'NR>2{print $2}' | grep '@'); do
    T=$(pveum user token list "$U" 2>/dev/null | awk 'NR>2{print $2}')
    [ -n "$T" ] && echo "  $U: $T"
done
echo ""
echo "Bitte pruefen: Gibt es Konten oder Tokens, die niemand mehr braucht?"
echo "Loeschen in der Weboberflaeche unter Datacenter -> Permissions."
EOS
        add_cron_line "0 9 1 * * root $HELPER_DIR/benutzerkonten-pruefen.sh >> $LOG_DIR/benutzer.log 2>&1" "$JOBID"
        ;;

    # ---------- Cluster ----------
    cluster-quorum-pruefen-stuendlich)
        write_helper "cluster-quorum-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft, ob der Cluster beschlussfaehig ist
command -v pvecm >/dev/null 2>&1 || exit 0
[ -f /etc/pve/corosync.conf ] || exit 0   # kein Cluster konfiguriert
if pvecm status 2>/dev/null | grep -qi "Quorate:.*Yes"; then
    echo "$(date '+%d.%m.%Y %H:%M') - Cluster ist beschlussfaehig (in Ordnung)"
else
    MELDUNG="ACHTUNG: Der Cluster hat kein Quorum! Die Konfiguration ist jetzt schreibgeschuetzt und VMs lassen sich nicht mehr starten."
    echo "$(date '+%d.%m.%Y %H:%M') - $MELDUNG"
    logger -t cronjobs-proxmox "$MELDUNG"
    pvecm status 2>&1
fi
EOS
        add_cron_line "0 * * * * root $HELPER_DIR/cluster-quorum-pruefen.sh >> $LOG_DIR/cluster.log 2>&1" "$JOBID"
        ;;

    ha-status-pruefen-taeglich)
        write_helper "ha-status-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft die Hochverfuegbarkeits-Dienste
command -v ha-manager >/dev/null 2>&1 || exit 0
AUSGABE=$(ha-manager status 2>/dev/null)
[ -z "$AUSGABE" ] && exit 0
echo "$(date '+%d.%m.%Y %H:%M') - HA-Status"
echo "$AUSGABE"
if echo "$AUSGABE" | grep -qiE "error|fence|freeze"; then
    MELDUNG="ACHTUNG: Ein hochverfuegbarer Dienst ist in einem Fehlerzustand"
    echo "$MELDUNG"
    logger -t cronjobs-proxmox "$MELDUNG"
fi
EOS
        add_cron_line "15 7 * * * root $HELPER_DIR/ha-status-pruefen.sh >> $LOG_DIR/ha.log 2>&1" "$JOBID"
        ;;

    cluster-netzwerk-pruefen-taeglich)
        write_helper "cluster-netzwerk-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft die Verbindungsqualitaet des Cluster-Netzwerks
command -v corosync-cfgtool >/dev/null 2>&1 || exit 0
[ -f /etc/pve/corosync.conf ] || exit 0
echo "$(date '+%d.%m.%Y %H:%M') - Cluster-Netzwerk (Corosync)"
AUSGABE=$(corosync-cfgtool -s 2>/dev/null)
echo "$AUSGABE"
if echo "$AUSGABE" | grep -qi "FAULTY"; then
    MELDUNG="ACHTUNG: Eine Cluster-Verbindung ist gestoert (FAULTY). Das kann zu unerwarteten Neustarts fuehren."
    echo "$MELDUNG"
    logger -t cronjobs-proxmox "$MELDUNG"
fi
EOS
        add_cron_line "20 7 * * * root $HELPER_DIR/cluster-netzwerk-pruefen.sh >> $LOG_DIR/cluster-netzwerk.log 2>&1" "$JOBID"
        ;;

    replikation-pruefen-taeglich)
        write_helper "replikation-status-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft, ob die ZFS-Replikation fehlerfrei laeuft
command -v pvesr >/dev/null 2>&1 || exit 0
AUSGABE=$(pvesr status 2>/dev/null)
[ -z "$AUSGABE" ] && exit 0
echo "$(date '+%d.%m.%Y %H:%M') - Replikations-Status"
echo "$AUSGABE"
if echo "$AUSGABE" | awk 'NR>1 && $6+0 > 0' | grep -q .; then
    MELDUNG="ACHTUNG: Mindestens ein Replikationsauftrag meldet Fehler. Die Spiegelung auf den zweiten Server funktioniert nicht."
    echo "$MELDUNG"
    logger -t cronjobs-proxmox "$MELDUNG"
fi
EOS
        add_cron_line "25 7 * * * root $HELPER_DIR/replikation-status-pruefen.sh >> $LOG_DIR/replikation.log 2>&1" "$JOBID"
        ;;

    # ---------- Netzwerk ----------
    internetverbindung-pruefen-alle-30min)
        write_helper "internetverbindung-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft Gateway und Internetverbindung
GATEWAY=$(ip route 2>/dev/null | awk '/^default/{print $3; exit}')
PROBLEM=0
if [ -n "$GATEWAY" ]; then
    ping -c 2 -W 2 "$GATEWAY" >/dev/null 2>&1 || { echo "$(date '+%d.%m.%Y %H:%M') - Gateway $GATEWAY NICHT erreichbar"; PROBLEM=1; }
else
    echo "$(date '+%d.%m.%Y %H:%M') - Kein Standard-Gateway konfiguriert"; PROBLEM=1
fi
ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 || { echo "$(date '+%d.%m.%Y %H:%M') - Internet NICHT erreichbar"; PROBLEM=1; }
[ "$PROBLEM" -eq 1 ] && logger -t cronjobs-proxmox "Netzwerkproblem festgestellt (siehe Log)"
exit 0
EOS
        add_cron_line "*/30 * * * * root $HELPER_DIR/internetverbindung-pruefen.sh >> $LOG_DIR/netzwerk.log 2>&1" "$JOBID"
        ;;

    dns-pruefen-taeglich)
        write_helper "dns-aufloesung-pruefen.sh" <<'EOS'
#!/bin/bash
# Prueft, ob die Namensaufloesung funktioniert
FEHLER=0
for NAME in download.proxmox.com deb.debian.org; do
    if getent hosts "$NAME" >/dev/null 2>&1; then
        echo "$(date '+%d.%m.%Y %H:%M') - $NAME: aufloesbar"
    else
        echo "$(date '+%d.%m.%Y %H:%M') - $NAME: NICHT aufloesbar"
        FEHLER=1
    fi
done
if [ "$FEHLER" -eq 1 ]; then
    MELDUNG="ACHTUNG: Namensaufloesung (DNS) funktioniert nicht. Updates und Zertifikatserneuerung schlagen dadurch fehl."
    echo "$MELDUNG"
    logger -t cronjobs-proxmox "$MELDUNG"
    echo "Konfigurierte DNS-Server:"; cat /etc/resolv.conf 2>/dev/null
fi
EOS
        add_cron_line "20 6 * * * root $HELPER_DIR/dns-aufloesung-pruefen.sh >> $LOG_DIR/dns.log 2>&1" "$JOBID"
        ;;

    freigaben-neu-verbinden-alle-5min)
        write_helper "netzwerkfreigaben-neu-verbinden.sh" <<'EOS'
#!/bin/bash
# Verbindet abgerissene Netzwerkfreigaben automatisch neu
awk '$3=="nfs" || $3=="nfs4" || $3=="cifs" {print $2}' /etc/fstab 2>/dev/null | while read -r MP; do
    [ -d "$MP" ] || continue
    if ! mountpoint -q "$MP" 2>/dev/null; then
        echo "$(date '+%d.%m.%Y %H:%M') - $MP ist nicht verbunden, versuche Neuverbindung"
        if mount "$MP" 2>&1; then
            echo "  erfolgreich neu verbunden"
        else
            echo "  Neuverbindung fehlgeschlagen (Server erreichbar?)"
        fi
    fi
done
EOS
        add_cron_line "*/5 * * * * root $HELPER_DIR/netzwerkfreigaben-neu-verbinden.sh >> $LOG_DIR/freigaben.log 2>&1" "$JOBID"
        ;;

    # ---------- Konfiguration und Berichte ----------
    konfiguration-sichern-taeglich)
        write_helper "proxmox-konfiguration-sichern.sh" <<EOS
#!/bin/bash
# Sichert die Proxmox-Konfigurationsdateien
ZIEL="$BACKUP_DIR/konfiguration"
mkdir -p "\$ZIEL"
TS=\$(date '+%Y%m%d_%H%M%S')
tar -czf "\$ZIEL/proxmox-konfig_\${TS}.tar.gz" \\
    /etc/pve/ /etc/network/interfaces /etc/hosts /etc/resolv.conf /etc/fstab \\
    /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null
GROESSE=\$(du -h "\$ZIEL/proxmox-konfig_\${TS}.tar.gz" 2>/dev/null | cut -f1)
echo "\$(date '+%d.%m.%Y %H:%M') - Konfiguration gesichert (\$GROESSE): \$ZIEL/proxmox-konfig_\${TS}.tar.gz"
find "\$ZIEL" -name 'proxmox-konfig_*.tar.gz' -mtime +14 -delete
EOS
        add_cron_line "0 1 * * * root $HELPER_DIR/proxmox-konfiguration-sichern.sh >> $LOG_DIR/konfiguration.log 2>&1" "$JOBID"
        ;;

    vorlagen-aktualisieren-woechentlich)
        write_helper "container-vorlagen-aktualisieren.sh" <<'EOS'
#!/bin/bash
# Aktualisiert die Liste verfuegbarer Container-Vorlagen
echo "$(date '+%d.%m.%Y %H:%M') - Aktualisiere Container-Vorlagen"
pveam update 2>&1
EOS
        add_cron_line "0 5 * * 1 root $HELPER_DIR/container-vorlagen-aktualisieren.sh >> $LOG_DIR/vorlagen.log 2>&1" "$JOBID"
        ;;

    systembericht-woechentlich)
        write_helper "system-wochenbericht.sh" <<'EOS'
#!/bin/bash
# Woechentlicher Gesamtbericht ueber den Systemzustand
echo "=========================================================="
echo " System-Wochenbericht - $(hostname) - $(date '+%d.%m.%Y')"
echo "=========================================================="
echo ""
echo "--- Laufzeit und Auslastung ---"
uptime
echo ""
echo "--- Arbeitsspeicher ---"
free -h
echo ""
echo "--- Speicherplatz ---"
df -h -x tmpfs -x devtmpfs 2>/dev/null
echo ""
echo "--- ZFS-Pools ---"
zpool list 2>/dev/null || echo "Kein ZFS im Einsatz"
echo ""
echo "--- Virtuelle Maschinen ---"
qm list 2>/dev/null || echo "Keine VMs"
echo ""
echo "--- Container ---"
pct list 2>/dev/null || echo "Keine Container"
echo ""
echo "--- Proxmox-Version ---"
pveversion 2>/dev/null
echo ""
echo "--- Letzte Sicherungen ---"
ls -lht /var/lib/vz/dump/vzdump-* 2>/dev/null | head -10 || echo "Keine Sicherungen gefunden"
echo ""
EOS
        add_cron_line "0 20 * * 0 root $HELPER_DIR/system-wochenbericht.sh >> $LOG_DIR/systembericht.log 2>&1" "$JOBID"
        ;;

    gast-agent-pruefen-woechentlich)
        write_helper "gast-agent-pruefen.sh" <<'EOS'
#!/bin/bash
# Findet VMs, bei denen der QEMU-Gast-Agent fehlt oder nicht antwortet
echo "$(date '+%d.%m.%Y %H:%M') - Pruefe QEMU-Gast-Agent"
for ID in $(qm list 2>/dev/null | awk 'NR>1 && $3=="running"{print $1}'); do
    NAME=$(qm config "$ID" 2>/dev/null | awk -F': ' '/^name:/{print $2}')
    if ! qm config "$ID" 2>/dev/null | grep -q "^agent:.*1"; then
        echo "  VM $ID ($NAME): Gast-Agent ist NICHT aktiviert"
        echo "     -> Weboberflaeche: VM -> Options -> QEMU Guest Agent -> Enabled"
    elif ! qm agent "$ID" ping >/dev/null 2>&1; then
        echo "  VM $ID ($NAME): Agent aktiviert, antwortet aber nicht"
        echo "     -> Im Gastsystem installieren: qemu-guest-agent"
    else
        echo "  VM $ID ($NAME): in Ordnung"
    fi
done
EOS
        add_cron_line "30 9 * * 1 root $HELPER_DIR/gast-agent-pruefen.sh >> $LOG_DIR/gast-agent.log 2>&1" "$JOBID"
        ;;

    ressourcen-trend-taeglich)
        write_helper "ressourcen-auslastung-aufzeichnen.sh" <<EOS
#!/bin/bash
# Zeichnet taeglich die Auslastung auf, um Trends zu erkennen
DATEI="$LOG_DIR/auslastung-verlauf.csv"
if [ ! -f "\$DATEI" ]; then
    echo "Datum;CPU-Last;RAM-belegt-%;Root-belegt-%;VMs-laufend;Container-laufend" > "\$DATEI"
fi
LAST=\$(awk '{print \$1}' /proc/loadavg)
RAM=\$(free | awk '/^Mem:/{printf "%.0f", \$3*100/\$2}')
ROOT=\$(df -P / | awk 'NR==2{gsub("%","",\$5); print \$5}')
VMS=\$(qm list 2>/dev/null | awk 'NR>1 && \$3=="running"' | wc -l)
CTS=\$(pct list 2>/dev/null | awk 'NR>1 && \$2=="running"' | wc -l)
echo "\$(date '+%Y-%m-%d');\$LAST;\$RAM;\$ROOT;\$VMS;\$CTS" >> "\$DATEI"
echo "\$(date '+%d.%m.%Y %H:%M') - Auslastung aufgezeichnet: CPU \$LAST, RAM \${RAM}%, Root \${ROOT}%, \$VMS VMs, \$CTS Container"
EOS
        add_cron_line "0 12 * * * root $HELPER_DIR/ressourcen-auslastung-aufzeichnen.sh >> $LOG_DIR/auslastung.log 2>&1" "$JOBID"
        ;;

    *)
        return 1
        ;;
    esac

    log_action "Cron-Job aktiviert: $JOBID"
    return 0
}
