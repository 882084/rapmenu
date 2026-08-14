#!/bin/bash
# ==========================================================
# CronJobs-Proxmox - Gemeinsame Bibliothek
# ==========================================================
# Enthaelt alles, was von mehreren Menues gebraucht wird:
# Pfade, Fenstergroessen, Dialoge, Protokollierung, Sicherungen.
# Wird von jedem Menue-Skript eingebunden.
# ==========================================================

# ── Pfade ────────────────────────────────────────────────
BASE_DIR="${BASE_DIR:-/usr/local/share/cronjobs-proxmox}"
MENU_DIR="$BASE_DIR/menus"
LIB_DIR="$BASE_DIR/lib"
CRON_LIB_DIR="$BASE_DIR/cron"
HEALTH_DIR="$BASE_DIR/health"

CONFIG_DIR="/etc/cronjobs-proxmox"
LOG_DIR="/var/log/cronjobs-proxmox"
BACKUP_DIR="/var/backups/cronjobs-proxmox"
CRON_FILE="/etc/cron.d/cronjobs-proxmox"
HELPER_DIR="/usr/local/bin/cronjobs-proxmox-skripte"
CONF_FILE="$CONFIG_DIR/einstellungen.conf"
JOURNAL_FILE="$LOG_DIR/aenderungen.log"
EDITOR_BIN="${EDITOR:-nano}"

mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$CONFIG_DIR" "$HELPER_DIR" 2>/dev/null

BTN_OK="Auswaehlen"
BTN_BACK="Zurueck"

# ── Meldungen auf der Konsole (ausserhalb der Dialoge) ───
FARBE_OK='\033[0;32m'; FARBE_WARN='\033[1;33m'; FARBE_ERR='\033[0;31m'
FARBE_INFO='\033[0;34m'; FARBE_AUS='\033[0m'
msg_ok()   { echo -e "${FARBE_OK}[ok]${FARBE_AUS} $*"; }
msg_warn() { echo -e "${FARBE_WARN}[hinweis]${FARBE_AUS} $*"; }
msg_err()  { echo -e "${FARBE_ERR}[fehler]${FARBE_AUS} $*"; }
msg_info() { echo -e "${FARBE_INFO}[info]${FARBE_AUS} $*"; }

#
# Alle Fenster passen sich an die tatsaechliche Groesse des Terminals
# an und zu lange Zeilen werden gekuerzt. Damit laeuft nie etwas ueber
# den Fensterrand hinaus, egal ob das Terminal 80 oder 200 Zeichen
# breit ist.

term_cols() {
    local C
    C=$(tput cols 2>/dev/null) || C=""
    [ -z "$C" ] && C=$(stty size 2>/dev/null | awk '{print $2}')
    [ -z "$C" ] && C=80
    echo "$C"
}

term_rows() {
    local R
    R=$(tput lines 2>/dev/null) || R=""
    [ -z "$R" ] && R=$(stty size 2>/dev/null | awk '{print $1}')
    [ -z "$R" ] && R=24
    echo "$R"
}

dlg_w() {
    # Gewuenschte Breite, begrenzt auf das was ins Terminal passt
    local WANT="${1:-80}" MAX
    MAX=$(( $(term_cols) - 6 ))
    [ "$MAX" -lt 56 ] && MAX=56
    [ "$WANT" -gt "$MAX" ] && WANT="$MAX"
    [ "$WANT" -lt 56 ] && WANT=56
    echo "$WANT"
}

dlg_h() {
    local WANT="${1:-20}" MAX
    MAX=$(( $(term_rows) - 2 ))
    [ "$MAX" -lt 12 ] && MAX=12
    [ "$WANT" -gt "$MAX" ] && WANT="$MAX"
    [ "$WANT" -lt 12 ] && WANT=12
    echo "$WANT"
}

kuerzen() {
    # Kuerzt einen Text auf die angegebene Laenge und haengt ... an
    local T="$1" M="${2:-40}"
    [ "$M" -lt 8 ] && M=8
    if [ "${#T}" -gt "$M" ]; then
        printf '%s...' "${T:0:$((M-3))}"
    else
        printf '%s' "$T"
    fi
}

fuellen() {
    # Fuellt einen Text rechts mit Leerzeichen auf feste Breite auf,
    # damit die Spalten in den Listen sauber untereinander stehen
    printf '%-*s' "$2" "$(kuerzen "$1" "$2")"
}

# Breite der Namensspalte in den Job-Listen. Ist das Terminal zu schmal,
# wird die Beschreibungsspalte ganz weggelassen (Rueckgabe 0), damit keine
# auf drei Buchstaben zerhackten Textfetzen entstehen. Die Beschreibungen
# sind dann ueber den Menuepunkt "Beschreibungen ansehen" erreichbar.
job_spalten() {
    # $1 = nutzbare Breite der Zeile -> gibt "NAMENSBREITE BESCHREIBUNGSBREITE" aus
    local PLATZ="$1" NAME=44 REST
    [ "$PLATZ" -lt "$NAME" ] && NAME="$PLATZ"
    REST=$(( PLATZ - NAME - 1 ))
    [ "$REST" -lt 18 ] && REST=0
    echo "$NAME $REST"
}

# ================================================================
# DIALOGE
# ================================================================

# Menue-Dialog. Der Fokus liegt immer auf dem Auswahl-Button (whiptail-Standard,
# deshalb kein --defaultno und keine vertauschte Button-Reihenfolge).
# Ueber $6 wird zusaetzlich der zuletzt gewaehlte Eintrag wieder vorausgewaehlt,
# damit man nach dem Schliessen eines Info-Fensters an derselben Stelle steht.
menu_dialog() {
    # $1=Titel  $2=Text  $3=Hoehe  $4=Breite  $5=Listenhoehe  $6=Vorauswahl  Rest=Eintraege
    local TITLE="$1" TEXT="$2" H W LH DEF="$6"
    H=$(dlg_h "$3")
    W=$(dlg_w "$4")
    LH="$5"
    shift 6

    local -a ITEMS=("$@")
    local I MAXTAG=0
    for ((I=0; I<${#ITEMS[@]}; I+=2)); do
        [ "${#ITEMS[I]}" -gt "$MAXTAG" ] && MAXTAG="${#ITEMS[I]}"
    done

    # Nutzbare Breite fuer den Beschreibungstext einer Zeile
    local PLATZ=$(( W - MAXTAG - 9 ))
    [ "$PLATZ" -lt 12 ] && PLATZ=12
    for ((I=1; I<${#ITEMS[@]}; I+=2)); do
        ITEMS[I]=$(kuerzen "${ITEMS[I]}" "$PLATZ")
    done

    # Listenhoehe an die Fensterhoehe anpassen
    local MAXLH=$(( H - 9 ))
    [ "$MAXLH" -lt 3 ] && MAXLH=3
    [ "$LH" -gt "$MAXLH" ] && LH="$MAXLH"
    local ANZ=$(( ${#ITEMS[@]} / 2 ))
    [ "$LH" -gt "$ANZ" ] && LH="$ANZ"
    [ "$LH" -lt 1 ] && LH=1

    if [ -n "$DEF" ]; then
        whiptail --title " $TITLE " \
            --ok-button "$BTN_OK" --cancel-button "$BTN_BACK" \
            --default-item "$DEF" \
            --menu "$TEXT" "$H" "$W" "$LH" "${ITEMS[@]}" 3>&1 1>&2 2>&3
    else
        whiptail --title " $TITLE " \
            --ok-button "$BTN_OK" --cancel-button "$BTN_BACK" \
            --menu "$TEXT" "$H" "$W" "$LH" "${ITEMS[@]}" 3>&1 1>&2 2>&3
    fi
}

checklist_dialog() {
    # $1=Titel  $2=Text  $3=Hoehe  $4=Breite  $5=Listenhoehe  Rest=Eintraege (Tag Text Status)
    local TITLE="$1" TEXT="$2" H W LH
    H=$(dlg_h "$3")
    W=$(dlg_w "$4")
    LH="$5"
    shift 5

    local -a ITEMS=("$@")
    local I MAXTAG=0
    for ((I=0; I<${#ITEMS[@]}; I+=3)); do
        [ "${#ITEMS[I]}" -gt "$MAXTAG" ] && MAXTAG="${#ITEMS[I]}"
    done

    # Zusaetzlich zum Menue noch Platz fuer das Auswahlkaestchen "[ ] "
    local PLATZ=$(( W - MAXTAG - 13 ))
    [ "$PLATZ" -lt 12 ] && PLATZ=12
    for ((I=1; I<${#ITEMS[@]}; I+=3)); do
        ITEMS[I]=$(kuerzen "${ITEMS[I]}" "$PLATZ")
    done

    local MAXLH=$(( H - 9 ))
    [ "$MAXLH" -lt 3 ] && MAXLH=3
    [ "$LH" -gt "$MAXLH" ] && LH="$MAXLH"
    local ANZ=$(( ${#ITEMS[@]} / 3 ))
    [ "$LH" -gt "$ANZ" ] && LH="$ANZ"
    [ "$LH" -lt 1 ] && LH=1

    whiptail --title " $TITLE " \
        --ok-button "Uebernehmen" --cancel-button "$BTN_BACK" \
        --checklist "$TEXT" "$H" "$W" "$LH" "${ITEMS[@]}" 3>&1 1>&2 2>&3
}

eingabe_dialog() {
    # $1=Titel  $2=Text  $3=Vorgabewert
    whiptail --title " $1 " --ok-button "$BTN_OK" --cancel-button "Abbrechen" \
        --inputbox "$2" "$(dlg_h 14)" "$(dlg_w 72)" "${3:-}" 3>&1 1>&2 2>&3
}

info_box() {
    # Info-Fenster, das mit Enter oder ESC geschlossen wird
    whiptail --title " ${2:-Information} " --ok-button "Schliessen" \
        --msgbox "$1" "$(dlg_h 20)" "$(dlg_w 76)"
}

info_textbox() {
    # Grosses, scrollbares Info-Fenster aus einer Datei
    whiptail --title " ${2:-Information} " --ok-button "Schliessen" --scrolltext \
        --textbox "$1" "$(dlg_h 30)" "$(dlg_w 98)"
}

pause() {
    info_box "$1" "${2:-Hinweis}"
}

confirm() {
    # Fokus liegt auf "Ja" (kein --defaultno)
    whiptail --title " ${2:-Bestaetigen} " --yes-button "Ja" --no-button "Nein" \
        --yesno "$1" "$(dlg_h 18)" "$(dlg_w 76)"
}

confirm_risky() {
    # Fuer gefaehrliche Aktionen: Fokus bewusst auf "Nein"
    whiptail --title " ${2:-ACHTUNG} " --yes-button "Ja, ausfuehren" --no-button "Abbrechen" \
        --defaultno --yesno "$1" "$(dlg_h 22)" "$(dlg_w 76)"
}

run_and_show() {
    local CMD="$1" TITLE="$2" TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "Ausgefuehrt am $(date '+%d.%m.%Y %H:%M:%S')"
        echo "----------------------------------------------------------"
        echo ""
    } > "$TMPFILE"
    eval "$CMD" >> "$TMPFILE" 2>&1
    echo "" >> "$TMPFILE"
    echo "----------------------------------------------------------" >> "$TMPFILE"
    echo "Fertig. Mit 'Schliessen' zurueck zum Menue." >> "$TMPFILE"
    info_textbox "$TMPFILE" "$TITLE"
    rm -f "$TMPFILE"
}

backup_file() {
    local SRC="$1" TS DEST
    TS=$(date '+%Y%m%d_%H%M%S')
    DEST="$BACKUP_DIR/$(basename "$SRC").${TS}.bak"
    mkdir -p "$BACKUP_DIR"
    cp -a "$SRC" "$DEST" 2>/dev/null && echo "$DEST"
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | logger -t cronjobs-proxmox
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG_DIR/aktionen.log"
}

write_helper() {
    # Schreibt ein Helfer-Skript; Inhalt kommt per Heredoc von stdin
    local NAME="$1"
    cat > "$HELPER_DIR/$NAME"
    chmod +x "$HELPER_DIR/$NAME"
}

conf_get() {
    local KEY="$1"
    [ -f "$CONF_FILE" ] && grep "^${KEY}=" "$CONF_FILE" 2>/dev/null | tail -1 | cut -d= -f2-
}

conf_set() {
    local KEY="$1" VAL="$2"
    touch "$CONF_FILE"
    sed -i "/^${KEY}=/d" "$CONF_FILE"
    echo "${KEY}=${VAL}" >> "$CONF_FILE"
}

# ── Warte-Hinweis waehrend laenger dauernder Pruefungen ──
warte_hinweis() {
    whiptail --title " Bitte warten " --infobox "${1:-Einen Moment bitte ...}" 8 "$(dlg_w 60)"
}

# ── Noch nicht gebaute Menuepunkte ──────────────────────
noch_nicht_da() {
    # $1 = Ueberschrift, $2 = geplante Punkte (mehrzeilig)
    info_box "Dieser Bereich ist noch im Aufbau.\n\nGeplant ist hier:\n\n$2\n\nBis dahin findest du vieles davon unter\n'Problem loesen'." "$1"
}
