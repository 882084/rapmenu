#!/bin/bash
# ==========================================================
# Protokolle und Verlauf
# ==========================================================

# ================================================================
# PROTOKOLLE
# ================================================================

logs_menu() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Protokolle und Verlauf" \
            "Was ist wann passiert?" \
            20 96 5 "$LAST" \
            "1" "Protokolle der Cron-Jobs ansehen" \
            "2" "Verlauf der eigenen Aktionen (was habe ich gemacht?)" \
            "3" "System-Fehlermeldungen der letzten 24 Stunden" \
            "4" "Auslastungs-Verlauf ansehen" \
            "5" "Alte Protokolle dieses Tools loeschen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1)
                local DATEIEN=() PFADE=() F NR=0
                while IFS= read -r F; do
                    [ -f "$F" ] || continue
                    NR=$((NR+1))
                    PFADE[NR]="$F"
                    DATEIEN+=("$NR" "$(fuellen "$(basename "$F")" 30) $(du -h "$F" 2>/dev/null | cut -f1)  zuletzt $(date -r "$F" '+%d.%m. %H:%M' 2>/dev/null)")
                done < <(find "$LOG_DIR" -maxdepth 1 -name '*.log' 2>/dev/null | sort)
                if [ "$NR" -eq 0 ]; then
                    pause "Es sind noch keine Protokolle vorhanden.\n\nSobald ein Cron-Job gelaufen ist, erscheinen sie hier."
                    continue
                fi
                local SEL
                SEL=$(menu_dialog "Protokoll auswaehlen" "Welches Protokoll moechtest du ansehen?" 24 90 14 "" "${DATEIEN[@]}")
                [ -n "${SEL:-}" ] && run_and_show "tail -n 200 '${PFADE[$SEL]}'" "$(basename "${PFADE[$SEL]}")"
                ;;
            2) run_and_show "tail -n 100 '$LOG_DIR/aktionen.log' 2>/dev/null || echo 'Noch keine Aktionen protokolliert.'" "Verlauf der Aktionen" ;;
            3) run_and_show "journalctl -p err --since '24 hours ago' --no-pager 2>/dev/null | tail -80 || echo 'Keine Fehler gefunden.'" "System-Fehlermeldungen" ;;
            4) run_and_show "column -s';' -t '$LOG_DIR/auslastung-verlauf.csv' 2>/dev/null || cat '$LOG_DIR/auslastung-verlauf.csv' 2>/dev/null || echo 'Noch keine Aufzeichnung vorhanden. Aktiviere dazu den Job \"ressourcen-auslastung-aufzeichnen.sh\".'" "Auslastungs-Verlauf" ;;
            5)
                if confirm "Alle Protokolldateien dieses Tools loeschen?\n\nDie Cron-Jobs selbst bleiben aktiv und schreiben danach\nneue Protokolle."; then
                    run_and_show "rm -f '$LOG_DIR'/*.log; echo 'Protokolle geloescht.'" "Protokolle geloescht"
                fi
                ;;
        esac
    done
}
