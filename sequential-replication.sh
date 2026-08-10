#!/bin/bash
#
# sequential-replication.sh
#
# Fuehrt fuer JEDEN existierenden Replikations-Job (pvesr) einen manuellen
# Sync-Lauf aus - NACHEINANDER statt gleichzeitig, um IO/CPU-Spitzen zu
# vermeiden. Die eigentliche Replikation ist durch ZFS send/receive ohnehin
# inkrementell: nach dem ersten vollen Sync werden nur noch die Deltas
# (neue/geaenderte Bloecke seit dem letzten Snapshot) uebertragen.
#
# Gedacht fuer: 1x/Stunde per Cron, ersetzt die individuellen Zeitplaene
# der einzelnen pvesr-Jobs (die dann auf "nie"/deaktiviert gesetzt werden
# koennen, siehe Hinweis unten).

set -uo pipefail

LOG_TAG="sequential-replication"
DELAY_BETWEEN_JOBS=5   # Sekunden Pause zwischen zwei Container-Syncs

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $*" | logger -t "$LOG_TAG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

log "=== Start sequenzieller Replikationslauf ==="

# Alle konfigurierten Jobs holen (Format: JobID Enabled Target LastSync NextSync Duration FailCount State)
JOB_IDS=$(pvesr list 2>/dev/null | awk 'NR>1{print $1}')

if [ -z "$JOB_IDS" ]; then
    log "Keine Replikations-Jobs gefunden. Ende."
    exit 0
fi

TOTAL=$(echo "$JOB_IDS" | wc -l)
COUNT=0
FAILED=0

for JOBID in $JOB_IDS; do
    COUNT=$((COUNT+1))
    log "[$COUNT/$TOTAL] Starte Sync fuer Job $JOBID ..."

    START_TS=$(date +%s)

    if pvesr run "$JOBID" 2>&1 | logger -t "$LOG_TAG"; then
        END_TS=$(date +%s)
        DURATION=$((END_TS - START_TS))
        log "[$COUNT/$TOTAL] OK: Job $JOBID abgeschlossen (${DURATION}s)"
    else
        FAILED=$((FAILED+1))
        log "[$COUNT/$TOTAL] FEHLER bei Job $JOBID - weiter mit naechstem"
    fi

    # kurze Pause, damit IO sich beruhigt bevor der naechste Container drankommt
    sleep "$DELAY_BETWEEN_JOBS"
done

log "=== Replikationslauf abgeschlossen: $((TOTAL-FAILED))/$TOTAL erfolgreich, $FAILED fehlgeschlagen ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
