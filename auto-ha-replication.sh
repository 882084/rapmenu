#!/bin/bash
#
# auto-ha-replication.sh
#
# Prüft alle HA-verwalteten LXC-Container (ct:XXX) und legt für jeden,
# der noch keinen Replikations-Job hat, automatisch einen an.
# Verhindert das Szenario "HA versucht Failover, aber Zieldaten fehlen".
#
# Läuft idealerweise auf DEM NODE, der aktuell als HA-CRM-Master aktiv ist,
# muss aber nicht zwingend - pvesr/ha-manager arbeiten clusterweit über /etc/pve.

set -euo pipefail

LOG_TAG="auto-ha-replication"
SCHEDULE="*/30"   # Standard-Replikationsintervall für neu gefundene CTs

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$LOG_TAG] $*" | logger -t "$LOG_TAG"
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*"
}

# Aktueller Node, auf dem das Skript läuft
THIS_NODE=$(hostname)

log "Starte Check: HA-Ressourcen ohne Replikations-Job"

# Alle HA-verwalteten Container-IDs holen (nur ct:, keine vm:)
# Format von 'ha-manager config': "ct:131" ... "vm:200" ...
HA_CTS=$(ha-manager config 2>/dev/null | grep -oP '^ct:\K[0-9]+' || true)

if [ -z "$HA_CTS" ]; then
    log "Keine HA-verwalteten Container gefunden. Ende."
    exit 0
fi

# Bereits existierende Replikations-Jobs holen (Format: "101-0", "105-0", ...)
EXISTING_JOBS=$(pvesr list 2>/dev/null | awk 'NR>1{print $1}' || true)

for CTID in $HA_CTS; do
    # Prüfen ob irgendein Job für diese CTID existiert (z.B. "131-0")
    if echo "$EXISTING_JOBS" | grep -q "^${CTID}-"; then
        continue  # Job existiert schon, überspringen
    fi

    log "CT $CTID hat KEINEN Replikations-Job -> wird jetzt eingerichtet"

    # Herausfinden, auf welchem Node der Container aktuell tatsächlich liegt
    # (durchsucht /etc/pve/nodes/*/lxc/<CTID>.conf)
    SOURCE_NODE=""
    for CONF in /etc/pve/nodes/*/lxc/${CTID}.conf; do
        if [ -f "$CONF" ]; then
            SOURCE_NODE=$(echo "$CONF" | sed -E 's#/etc/pve/nodes/([^/]+)/lxc/.*#\1#')
            break
        fi
    done

    if [ -z "$SOURCE_NODE" ]; then
        log "WARNUNG: Konnte Config/Node fuer CT $CTID nicht finden - ueberspringe"
        continue
    fi

    # Alle anderen Cluster-Nodes ermitteln (Ziel fuer Replikation)
    ALL_NODES=$(pvecm nodes 2>/dev/null | awk 'NR>2{print $3}' | sed 's/^0 //' || true)
    if [ -z "$ALL_NODES" ]; then
        # Fallback ueber /etc/pve/nodes
        ALL_NODES=$(ls /etc/pve/nodes/)
    fi

    for TARGET in $ALL_NODES; do
        if [ "$TARGET" == "$SOURCE_NODE" ]; then
            continue  # nicht zu sich selbst replizieren
        fi

        JOBID="${CTID}-0"

        log "Lege Replikations-Job an: $JOBID (Quelle: $SOURCE_NODE -> Ziel: $TARGET, Schedule: $SCHEDULE)"

        if pvesr create-local-job "$JOBID" "$TARGET" --schedule "$SCHEDULE" 2>&1 | logger -t "$LOG_TAG"; then
            log "OK: Job $JOBID erfolgreich angelegt"
        else
            log "FEHLER: Job $JOBID konnte nicht angelegt werden (evtl. Storage nicht ZFS-faehig oder bereits vorhanden)"
        fi

        # Nur EIN Ziel pro CT (Standard: 2-Node-Cluster -> nur ein moeglicher Zielnode)
        break
    done
done

log "Check abgeschlossen."
