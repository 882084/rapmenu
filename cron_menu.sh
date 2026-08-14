#!/bin/bash
# ==========================================================
# Menue 3 - Automatische Aufgaben (Cron-Jobs)
# ==========================================================

# ================================================================
# CRON-JOB-MENUES
# ================================================================

show_job_info() {
    # Zeigt die ausfuehrliche Beschreibung eines Jobs in einem eigenen Fenster
    local DEF="$1" TMPFILE
    DEF=$(job_def_by_id "$DEF") || return
    TMPFILE=$(mktemp)
    {
        echo "SKRIPT"
        echo "  $(job_field "$DEF" 3)"
        echo ""
        echo "WAS MACHT ES?"
        echo "  $(job_field "$DEF" 4)"
        echo ""
        echo "WANN LAEUFT ES?"
        echo "  $(job_field "$DEF" 5)"
        echo ""
        echo "AUSFUEHRLICH"
        echo "$(job_field "$DEF" 6)" | fold -s -w 92 | sed 's/^/  /'
        echo ""
        echo "STATUS"
        if is_job_enabled "$(job_field "$DEF" 1)"; then
            echo "  Dieser Job ist derzeit AKTIV."
        else
            echo "  Dieser Job ist derzeit NICHT aktiv."
        fi
        echo ""
        echo "PROTOKOLL"
        echo "  $LOG_DIR/"
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Info: $(job_field "$DEF" 3)"
    rm -f "$TMPFILE"
}

job_info_browser() {
    # Liste aller Jobs einer Kategorie; Auswahl oeffnet Info-Fenster,
    # nach dem Schliessen bleibt man in derselben Liste an derselben Stelle.
    # Als Kennzeichen dient eine laufende Nummer, damit die Zeilen kurz
    # bleiben und der Skriptname vollstaendig lesbar ist.
    local CAT="$1" TITEL="$2" LAST=""
    while true; do
        local ITEMS=() IDS=() DEF ID NR=0 SP NSP BSP ZEILE
        # Zeile: Nummer + Leerzeichen + "[x] " + Name + Beschreibung
        SP=$(job_spalten $(( $(dlg_w 104) - 15 )))
        NSP=${SP% *}; BSP=${SP#* }

        for DEF in "${CRON_JOB_DEFS[@]}"; do
            [ "$(job_field "$DEF" 2)" != "$CAT" ] && continue
            ID=$(job_field "$DEF" 1)
            NR=$((NR+1))
            IDS[NR]="$ID"
            local MARKER="[ ]"
            is_job_enabled "$ID" && MARKER="[x]"
            if [ "$BSP" -gt 0 ]; then
                ZEILE="$MARKER $(fuellen "$(job_field "$DEF" 3)" "$NSP") $(kuerzen "$(job_field "$DEF" 4)" "$BSP")"
            else
                ZEILE="$MARKER $(kuerzen "$(job_field "$DEF" 3)" "$NSP")"
            fi
            ITEMS+=("$NR" "$ZEILE")
        done
        [ ${#ITEMS[@]} -eq 0 ] && { pause "In dieser Kategorie sind keine Jobs definiert."; return; }

        local SEL
        SEL=$(menu_dialog "Beschreibungen: $TITEL" \
            "Skript auswaehlen und Enter druecken - es oeffnet sich ein\nFenster mit der ausfuehrlichen Erklaerung.\n\n[x] = derzeit aktiv     [ ] = nicht aktiv" \
            26 104 14 "$LAST" "${ITEMS[@]}")
        [ -z "${SEL:-}" ] && return
        LAST="$SEL"
        show_job_info "${IDS[$SEL]}"
    done
}

job_checklist() {
    local CAT="$1" TITEL="$2"
    touch "$CRON_FILE"

    local ITEMS=() IDS=() DEF ID NR=0 SP NSP BSP ZEILE
    # Zeile: "[ ] " + Nummer + Leerzeichen + Name + Beschreibung
    SP=$(job_spalten $(( $(dlg_w 108) - 15 )))
    NSP=${SP% *}; BSP=${SP#* }

    for DEF in "${CRON_JOB_DEFS[@]}"; do
        [ "$(job_field "$DEF" 2)" != "$CAT" ] && continue
        ID=$(job_field "$DEF" 1)
        NR=$((NR+1))
        IDS[NR]="$ID"
        local STATE="OFF"
        is_job_enabled "$ID" && STATE="ON"
        if [ "$BSP" -gt 0 ]; then
            ZEILE="$(fuellen "$(job_field "$DEF" 3)" "$NSP") $(kuerzen "$(job_field "$DEF" 4)" "$BSP")"
        else
            ZEILE="$(kuerzen "$(job_field "$DEF" 3)" "$NSP")"
        fi
        ITEMS+=("$NR" "$ZEILE" "$STATE")
    done

    [ "$NR" -eq 0 ] && { pause "In dieser Kategorie sind keine Jobs definiert."; return; }

    local SELECTED
    SELECTED=$(checklist_dialog "Jobs an- und abwaehlen: $TITEL" \
        "Leertaste = an/abwaehlen     Enter = uebernehmen\n\nEs werden nur die Jobs dieser Kategorie geaendert." \
        28 108 16 "${ITEMS[@]}")
    [ $? -ne 0 ] && return

    # Alte Zeilen dieser Kategorie entfernen
    local I
    for I in $(seq 1 "$NR"); do
        remove_job_line "${IDS[$I]}"
    done

    eval "local -a AUSGEWAEHLT=($SELECTED)"

    local AKTIV=0 FEHLER=0
    for I in $(seq 1 "$NR"); do
        local GEWAEHLT=0 X
        for X in "${AUSGEWAEHLT[@]:-}"; do
            [ "$X" == "$I" ] && GEWAEHLT=1
        done
        if [ "$GEWAEHLT" -eq 1 ]; then
            if install_cron_job "${IDS[$I]}"; then
                AKTIV=$((AKTIV+1))
            else
                FEHLER=$((FEHLER+1))
            fi
        fi
    done

    local ZUSATZ=""
    [ "$FEHLER" -gt 0 ] && ZUSATZ="\n$FEHLER Job(s) wurden abgebrochen und nicht eingerichtet."

    pause "In der Kategorie\n  $TITEL\nsind jetzt $AKTIV Job(s) aktiv.$ZUSATZ\n\nSie laufen ab sofort automatisch im Hintergrund.\nProtokolle:  $LOG_DIR" "Gespeichert"
}

category_menu() {
    local CAT="$1" TITEL="$2" BESCHR="${3:-}" LAST="1"
    while true; do
        local ANZ_AKTIV=0 GESAMT=0 DEF
        for DEF in "${CRON_JOB_DEFS[@]}"; do
            [ "$(job_field "$DEF" 2)" != "$CAT" ] && continue
            GESAMT=$((GESAMT+1))
            is_job_enabled "$(job_field "$DEF" 1)" && ANZ_AKTIV=$((ANZ_AKTIV+1))
        done

        local CHOICE
        CHOICE=$(menu_dialog "$TITEL" \
            "$BESCHR\n\nVon $GESAMT Skripten sind $ANZ_AKTIV aktiv." \
            18 90 3 "$LAST" \
            "1" "Skripte an- und abwaehlen" \
            "2" "Beschreibungen ansehen - was macht welches Skript?" \
            "3" "Nur die aktiven Skripte anzeigen")
        [ -z "${CHOICE:-}" ] && return
        LAST="$CHOICE"
        case "$CHOICE" in
            1) job_checklist "$CAT" "$TITEL" ;;
            2) job_info_browser "$CAT" "$TITEL" ;;
            3)
                local TMPFILE
                TMPFILE=$(mktemp)
                {
                    echo "Aktive Skripte in der Kategorie: $TITEL"
                    echo "=========================================================="
                    echo ""
                    local GEF=0
                    for DEF in "${CRON_JOB_DEFS[@]}"; do
                        [ "$(job_field "$DEF" 2)" != "$CAT" ] && continue
                        if is_job_enabled "$(job_field "$DEF" 1)"; then
                            echo "  $(job_field "$DEF" 3)"
                            echo "      $(job_field "$DEF" 4)"
                            echo "      Zeitplan: $(job_field "$DEF" 5)"
                            echo ""
                            GEF=1
                        fi
                    done
                    [ "$GEF" -eq 0 ] && echo "  (In dieser Kategorie ist derzeit kein Skript aktiv.)"
                } > "$TMPFILE"
                info_textbox "$TMPFILE" "Aktive Skripte"
                rm -f "$TMPFILE"
                ;;
        esac
    done
}

cron_categories_menu() {
    local LAST=""
    while true; do
        local ITEMS=() KUERZEL=() NAMEN=() TEXTE=()
        local C KURZ BESCHR K ANZ GESAMT DEF NR=0

        # Spalten so aufteilen, dass der Zaehler rechts immer sichtbar bleibt
        local PLATZ NAMESP=18 ZAHLSP=7 BESCHRSP
        PLATZ=$(( $(dlg_w 100) - 11 ))
        BESCHRSP=$(( PLATZ - NAMESP - ZAHLSP - 2 ))
        if [ "$BESCHRSP" -lt 16 ]; then
            BESCHRSP=0
            NAMESP=$(( PLATZ - ZAHLSP - 1 ))
            [ "$NAMESP" -lt 10 ] && NAMESP=10
        fi

        for C in "${CATEGORIES[@]}"; do
            K=$(cat_field "$C" 1)
            KURZ=$(cat_field "$C" 2)
            BESCHR=$(cat_field "$C" 3)
            ANZ=0; GESAMT=0
            for DEF in "${CRON_JOB_DEFS[@]}"; do
                [ "$(job_field "$DEF" 2)" != "$K" ] && continue
                GESAMT=$((GESAMT+1))
                is_job_enabled "$(job_field "$DEF" 1)" && ANZ=$((ANZ+1))
            done
            NR=$((NR+1))
            KUERZEL[NR]="$K"
            NAMEN[NR]="$KURZ"
            TEXTE[NR]="$BESCHR"
            if [ "$BESCHRSP" -gt 0 ]; then
                ITEMS+=("$NR" "$(fuellen "$KURZ" "$NAMESP") $(fuellen "$BESCHR" "$BESCHRSP") $(printf '%*s' "$ZAHLSP" "$ANZ/$GESAMT")")
            else
                ITEMS+=("$NR" "$(fuellen "$KURZ" "$NAMESP") $(printf '%*s' "$ZAHLSP" "$ANZ/$GESAMT")")
            fi
        done

        local CHOICE
        CHOICE=$(menu_dialog "Cron-Jobs - Kategorien" \
            "Waehle einen Bereich aus - danach siehst du die einzelnen Skripte.\n\nDie Zahl rechts zeigt, wie viele Skripte darin gerade aktiv sind." \
            22 100 8 "$LAST" "${ITEMS[@]}")
        [ -z "${CHOICE:-}" ] && return
        LAST="$CHOICE"
        category_menu "${KUERZEL[$CHOICE]}" "${NAMEN[$CHOICE]}" "${TEXTE[$CHOICE]}"
    done
}

show_all_active_jobs() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "Alle aktiven Cron-Jobs"
        echo "=========================================================="
        echo ""
        if [ ! -f "$CRON_FILE" ] || [ ! -s "$CRON_FILE" ]; then
            echo "  Es ist derzeit kein Job aktiv."
            echo ""
            echo "  Jobs aktivierst du im Menue unter"
            echo "  'Cron-Jobs verwalten' -> Kategorie -> 'Skripte an- und abwaehlen'."
        else
            local C KUERZEL NAME DEF GEF
            for C in "${CATEGORIES[@]}"; do
                KUERZEL=$(cat_field "$C" 1); NAME=$(cat_field "$C" 2)
                GEF=0
                for DEF in "${CRON_JOB_DEFS[@]}"; do
                    [ "$(job_field "$DEF" 2)" != "$KUERZEL" ] && continue
                    if is_job_enabled "$(job_field "$DEF" 1)"; then
                        [ "$GEF" -eq 0 ] && { echo "--- $NAME ---"; GEF=1; }
                        printf "  %-45s %s\n" "$(job_field "$DEF" 3)" "$(job_field "$DEF" 5)"
                    fi
                done
                [ "$GEF" -eq 1 ] && echo ""
            done
        fi
        echo ""
        echo "=========================================================="
        echo "Technische Ansicht (Datei $CRON_FILE):"
        echo ""
        cat "$CRON_FILE" 2>/dev/null || echo "(Datei existiert noch nicht)"
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Aktive Cron-Jobs"
    rm -f "$TMPFILE"
}

deactivate_all_jobs() {
    if [ ! -s "$CRON_FILE" ]; then
        pause "Es ist derzeit kein Job aktiv."
        return
    fi
    if confirm_risky "Wirklich ALLE Cron-Jobs deaktivieren?\n\nDamit laufen keine automatischen Sicherungen und Pruefungen mehr.\n\nDie Skripte selbst bleiben erhalten und koennen jederzeit wieder aktiviert werden." "Alle Jobs deaktivieren"; then
        backup_file "$CRON_FILE" > /dev/null
        rm -f "$CRON_FILE"
        log_action "Alle Cron-Jobs deaktiviert"
        pause "Alle Cron-Jobs wurden deaktiviert."
    fi
}

test_run_job() {
    # Ein aktives Skript sofort testweise ausfuehren
    local ITEMS=() IDS=() DEF ID NR=0 SP NSP BSP ZEILE
    SP=$(job_spalten $(( $(dlg_w 104) - 11 )))
    NSP=${SP% *}; BSP=${SP#* }
    for DEF in "${CRON_JOB_DEFS[@]}"; do
        ID=$(job_field "$DEF" 1)
        is_job_enabled "$ID" || continue
        NR=$((NR+1))
        IDS[NR]="$ID"
        if [ "$BSP" -gt 0 ]; then
            ZEILE="$(fuellen "$(job_field "$DEF" 3)" "$NSP") $(kuerzen "$(job_field "$DEF" 4)" "$BSP")"
        else
            ZEILE="$(kuerzen "$(job_field "$DEF" 3)" "$NSP")"
        fi
        ITEMS+=("$NR" "$ZEILE")
    done
    if [ "$NR" -eq 0 ]; then
        pause "Es ist derzeit kein Job aktiv, der getestet werden koennte.\n\nAktiviere zuerst einen Job unter 'Cron-Jobs verwalten'."
        return
    fi

    local NUM SEL
    NUM=$(menu_dialog "Skript jetzt testen" \
        "Welches Skript soll sofort einmal ausgefuehrt werden?\n\nSo siehst du direkt, ob es funktioniert - ohne auf den\nZeitplan zu warten." \
        24 104 12 "" "${ITEMS[@]}")
    [ -z "${NUM:-}" ] && return
    SEL="${IDS[$NUM]}"

    DEF=$(job_def_by_id "$SEL") || return
    local SKRIPT
    SKRIPT="$HELPER_DIR/$(job_field "$DEF" 3)"

    if [ -x "$SKRIPT" ]; then
        run_and_show "'$SKRIPT'" "Testlauf: $(job_field "$DEF" 3)"
    else
        # Job ohne eigenes Helfer-Skript: Befehl aus der Cron-Zeile ausfuehren
        local BEFEHL
        BEFEHL=$(grep "# job:$SEL\$" "$CRON_FILE" | sed -E 's/^[^ ]+ [^ ]+ [^ ]+ [^ ]+ [^ ]+ root //; s/ # job:.*$//')
        if [ -n "$BEFEHL" ]; then
            run_and_show "$BEFEHL" "Testlauf: $(job_field "$DEF" 3)"
        else
            pause "Das Skript wurde nicht gefunden:\n$SKRIPT"
        fi
    fi
}

cron_main_menu() {
    local LAST="1"
    while true; do
        local ANZ=0
        [ -f "$CRON_FILE" ] && ANZ=$(grep -c "# job:" "$CRON_FILE" 2>/dev/null)

        local CHOICE
        CHOICE=$(menu_dialog "Cron-Jobs - Automatische Aufgaben" \
            "Hier stellst du ein, welche Aufgaben Proxmox automatisch\nim Hintergrund erledigen soll.\n\nDerzeit aktiv: ${ANZ:-0} Job(s)" \
            22 96 6 "$LAST" \
            "1" "Cron-Jobs verwalten (nach Kategorien)" \
            "2" "Alle aktiven Jobs anzeigen" \
            "3" "Ein Skript jetzt testweise ausfuehren" \
            "4" "Protokolle der Jobs ansehen" \
            "5" "Alle Jobs deaktivieren")
        [ -z "${CHOICE:-}" ] && return
        LAST="$CHOICE"
        case "$CHOICE" in
            1) cron_categories_menu ;;
            2) show_all_active_jobs ;;
            3) test_run_job ;;
            4) logs_menu ;;
            5) deactivate_all_jobs ;;
        esac
    done
}
