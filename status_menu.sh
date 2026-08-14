#!/bin/bash
# ==========================================================
# Menue 1 - Zustand meines Servers (Ampel-Uebersicht)
# ==========================================================
# Der Einstiegsbildschirm. Zeigt fuer jeden geprueften Punkt
# eine Ampelfarbe. Jeder Punkt ist auswaehlbar: es oeffnet
# sich ein Fenster mit der Erklaerung und - falls vorhanden -
# der Moeglichkeit, das Problem direkt beheben zu lassen.
# ==========================================================

ampel_symbol() {
    case "$1" in
        ROT)   echo "[!!]" ;;
        GELB)  echo "[ ! ]" ;;
        GRUEN) echo "[ok]" ;;
        *)     echo "[--]" ;;
    esac
}

ampel_wort() {
    case "$1" in
        ROT)   echo "HANDELN" ;;
        GELB)  echo "ANSEHEN" ;;
        GRUEN) echo "IN ORDNUNG" ;;
        *)     echo "TRIFFT NICHT ZU" ;;
    esac
}

# Loesung fuer die Sicherungs-Punkte: fuehrt direkt in die
# Checkliste der Kategorie "Sicherung"
fix_ampel_sicherung() {
    job_checklist "sicherung" "Sicherung"
}

status_detail() {
    # $1 = Index in den HEALTH_-Feldern
    local I="$1" TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "${HEALTH_NAME[$I]}"
        echo "=========================================================="
        echo ""
        echo "BEWERTUNG"
        echo "  $(ampel_wort "${HEALTH_STATE[$I]}")  -  ${HEALTH_TEXT[$I]}"
        echo ""
        echo "WAS BEDEUTET DAS?"
        echo -e "${HEALTH_DETAIL[$I]}" | fold -s -w 88 | sed 's/^/  /'
        echo ""
        if [ -n "${HEALTH_FIX[$I]}" ]; then
            echo "----------------------------------------------------------"
            echo "Dieses Werkzeug kann dir dabei helfen."
            echo "Nach dem Schliessen dieses Fensters wirst du gefragt,"
            echo "ob es den passenden Assistenten oeffnen soll."
        fi
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Zustand: ${HEALTH_NAME[$I]}"
    rm -f "$TMPFILE"

    if [ -n "${HEALTH_FIX[$I]}" ]; then
        if confirm "Moechtest du dich jetzt um diesen Punkt kuemmern?\n\n  ${HEALTH_NAME[$I]}\n  ${HEALTH_TEXT[$I]}\n\nIch oeffne dann den passenden Assistenten." "Jetzt beheben?"; then
            "${HEALTH_FIX[$I]}"
            return 1   # danach neu pruefen
        fi
    fi
    return 0
}

status_menu() {
    local NEUPRUEFEN=1 LAST=""
    while true; do
        if [ "$NEUPRUEFEN" -eq 1 ]; then
            warte_hinweis "Der Zustand des Servers wird geprueft.\n\nDas dauert etwa 10 bis 30 Sekunden."
            health_run
            NEUPRUEFEN=0
        fi

        local ROT GELB GRUEN
        ROT=$(health_zaehle ROT); GELB=$(health_zaehle GELB); GRUEN=$(health_zaehle GRUEN)

        # Spaltenbreiten an das Terminal anpassen
        local W PLATZ NAMESP TEXTSP
        W=$(dlg_w 100)
        PLATZ=$(( W - 11 ))
        NAMESP=22
        TEXTSP=$(( PLATZ - NAMESP - 8 ))
        if [ "$TEXTSP" -lt 18 ]; then
            TEXTSP=0
            NAMESP=$(( PLATZ - 8 ))
        fi

        local ITEMS=() I NR=0 IDX=()
        # Erst die dringenden Punkte, dann die unauffaelligen
        local STUFE
        for STUFE in ROT GELB GRUEN GRAU; do
            for I in "${!HEALTH_ID[@]}"; do
                [ "${HEALTH_STATE[$I]}" != "$STUFE" ] && continue
                NR=$((NR+1)); IDX[NR]="$I"
                if [ "$TEXTSP" -gt 0 ]; then
                    ITEMS+=("$NR" "$(printf '%-5s' "$(ampel_symbol "$STUFE")") $(fuellen "${HEALTH_NAME[$I]}" "$NAMESP") $(kuerzen "${HEALTH_TEXT[$I]}" "$TEXTSP")")
                else
                    ITEMS+=("$NR" "$(printf '%-5s' "$(ampel_symbol "$STUFE")") $(kuerzen "${HEALTH_NAME[$I]}" "$NAMESP")")
                fi
            done
        done

        local KOPF
        if [ "$ROT" -gt 0 ]; then
            KOPF="$ROT Punkt(e) brauchen deine Aufmerksamkeit."
        elif [ "$GELB" -gt 0 ]; then
            KOPF="Nichts Dringendes - $GELB Punkt(e) solltest du dir bei Gelegenheit ansehen."
        else
            KOPF="Alles in Ordnung. Es gibt gerade nichts zu tun."
        fi

        ITEMS+=("N" "Zustand neu pruefen")

        local C
        C=$(menu_dialog "Zustand meines Servers" \
            "$KOPF\n\n[!!] = handeln   [ ! ] = ansehen   [ok] = in Ordnung   [--] = trifft nicht zu\n\nPunkt auswaehlen fuer die Erklaerung und die Loesung." \
            26 100 15 "$LAST" "${ITEMS[@]}")
        [ -z "${C:-}" ] && return
        LAST="$C"

        if [ "$C" == "N" ]; then
            NEUPRUEFEN=1
            continue
        fi

        if ! status_detail "${IDX[$C]}"; then
            NEUPRUEFEN=1   # es wurde etwas geaendert -> neu bewerten
            LAST=""
        fi
    done
}
