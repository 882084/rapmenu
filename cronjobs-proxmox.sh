#!/bin/bash
#
# cronjobs-proxmox.sh - CronJobs-Proxmox
#
# Ein einfaches Menue fuer Proxmox VE. Gedacht auch fuer Nutzer OHNE
# Linux- oder Proxmox-Erfahrung: alles per Pfeiltasten und Enter,
# keine Konsolen-Befehle noetig.
#
# Zwei Bereiche:
#   1. Cron-Jobs  - wiederkehrende Aufgaben (Backup, Wartung, Pruefungen)
#                   nach Kategorien sortiert, per Checkliste an-/abwaehlbar
#   2. Reparatur  - Loesungen fuer die haeufigsten Proxmox-Probleme,
#                   jeweils mit Erklaerung in verstaendlicher Sprache
#
# Repo: https://github.com/882084/rapmenu

set -uo pipefail

VERSION="2.0.0"
SCRIPT_DIR="/usr/local/bin"
CONFIG_DIR="/etc/cronjobs-proxmox"
LOG_DIR="/var/log/cronjobs-proxmox"
BACKUP_DIR="/var/backups/cronjobs-proxmox"
CRON_FILE="/etc/cron.d/cronjobs-proxmox"
HELPER_DIR="/usr/local/bin/cronjobs-proxmox-skripte"
CONF_FILE="$CONFIG_DIR/einstellungen.conf"
EDITOR_BIN="${EDITOR:-nano}"

mkdir -p "$LOG_DIR" "$BACKUP_DIR" "$CONFIG_DIR" "$HELPER_DIR"

BTN_OK="Auswaehlen"
BTN_BACK="Zurueck"

# ================================================================
# DARSTELLUNG - Fenstergroessen und Textlaengen
# ================================================================
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

# ================================================================
# KATEGORIEN (Zugehoerigkeitsnamen)
# ================================================================
# Format: Kuerzel|Kurzname (Menue)|Beschreibung (Untermenue)

CATEGORIES=(
"sicherung|Sicherung|Backups von VMs und Containern erstellen, pruefen und aufraeumen"
"snapshots|Momentaufnahmen|Snapshots erstellen und alte automatisch aufraeumen"
"speicher|Speicher und ZFS|Festplatten, ZFS-Pools und freier Speicherplatz"
"wartung|System-Wartung|Updates, Kernel, Protokolle und Aufraeumarbeiten"
"sicherheit|Sicherheit|Zertifikate, Anmeldeversuche und Sicherheitsupdates"
"cluster|Cluster und HA|Quorum, Hochverfuegbarkeit und Replikation"
"netzwerk|Netzwerk|Verbindungen, Namensaufloesung und Freigaben"
"konfiguration|Konfiguration|Einstellungen sichern und regelmaessige Berichte"
)

cat_field() {
    echo "$1" | awk -F'|' -v f="$2" '{print $f}'
}

# ================================================================
# CRON-JOB-DEFINITIONEN
# ================================================================
# Format: ID|Kategorie|Skriptname|Kurzbeschreibung|Zeitplan-Klartext|Ausfuehrliche Erklaerung

CRON_JOB_DEFS=(
# ---------- Sicherung ----------
"sicherung-alle-taeglich|sicherung|backup-alle-vms-und-container.sh|Sichert taeglich ALLE VMs und Container|Taeglich 02:00 Uhr|Erstellt jede Nacht eine vollstaendige Sicherung von allen virtuellen Maschinen und allen Containern auf diesem Server. Verwendet den Snapshot-Modus, damit die Systeme dabei weiterlaufen koennen (kein Ausschalten noetig). Die Sicherungen landen auf dem Speicher, den du beim ersten Aktivieren auswaehlst. Das ist der wichtigste Job ueberhaupt - ohne Backup ist alles weg, wenn eine Festplatte stirbt."
"sicherung-nur-vms-taeglich|sicherung|backup-nur-vms.sh|Sichert taeglich nur die virtuellen Maschinen|Taeglich 02:30 Uhr|Sichert ausschliesslich die virtuellen Maschinen (VMs, z.B. Windows oder Linux mit eigenem Kernel), keine Container. Sinnvoll, wenn du VMs und Container zu unterschiedlichen Zeiten sichern willst, damit sie sich nicht gegenseitig ausbremsen."
"sicherung-nur-container-taeglich|sicherung|backup-nur-container.sh|Sichert taeglich nur die LXC-Container|Taeglich 03:00 Uhr|Sichert ausschliesslich die LXC-Container (die leichtgewichtigen Systeme, die sich den Kernel mit dem Host teilen). Container sind meist deutlich kleiner und schneller gesichert als VMs."
"sicherung-alte-loeschen-woechentlich|sicherung|backup-alte-loeschen.sh|Loescht alte Sicherungen automatisch|Sonntags 04:00 Uhr|Ohne Aufraeumen laeuft die Backup-Festplatte irgendwann voll und dann schlagen ALLE neuen Sicherungen fehl. Dieser Job loescht Sicherungsdateien, die aelter als eine von dir festgelegte Anzahl Tage sind (Standard 30 Tage). Du wirst beim Aktivieren nach der Aufbewahrungsdauer gefragt."
"sicherung-pruefen-woechentlich|sicherung|backup-integritaet-pruefen.sh|Prueft ob die Sicherungen lesbar sind|Sonntags 05:00 Uhr|Eine kaputte Sicherungsdatei merkt man normalerweise erst im Notfall - also genau dann, wenn es zu spaet ist. Dieser Job oeffnet jede Sicherungsdatei testweise und prueft, ob sie fehlerfrei lesbar ist. Ergebnisse stehen im Log."
"sicherung-bericht-woechentlich|sicherung|backup-wochenbericht.sh|Schreibt eine Uebersicht aller Sicherungen|Montags 07:00 Uhr|Erstellt jede Woche eine uebersichtliche Zusammenfassung: welche Sicherungen existieren, wie alt sie sind, wie viel Platz sie belegen und ob eine VM oder ein Container seit laengerem gar nicht mehr gesichert wurde. Gut, um regelmaessig einen Blick darauf zu werfen."
"sicherung-testrestore-erinnerung-monatlich|sicherung|backup-testwiederherstellung-erinnerung.sh|Erinnert monatlich an einen Test-Restore|Am 1. des Monats, 08:00 Uhr|Merksatz aus der Praxis: Eine Sicherung, die nie zurueckgespielt wurde, ist keine Sicherung. Dieser Job schreibt einmal im Monat eine Erinnerung ins Log und ins System-Journal, dass du eine beliebige VM testweise wiederherstellen solltest. Er stellt selbst nichts wieder her - er erinnert nur."

# ---------- Snapshots ----------
"snapshot-erstellen-taeglich|snapshots|snapshot-taeglich-erstellen.sh|Erstellt taeglich Momentaufnahmen|Taeglich 04:30 Uhr|Erstellt von allen laufenden VMs und Containern eine Momentaufnahme (Snapshot) mit dem Namen auto-JJJJMMTT. Damit kannst du innerhalb von Sekunden auf den Stand von gestern zurueck, falls ein Update oder eine Aenderung schiefgeht. Achtung: Snapshots sind KEIN Ersatz fuer Backups, da sie auf derselben Festplatte liegen."
"snapshot-aufraeumen-taeglich|snapshots|snapshot-alte-aufraeumen.sh|Loescht alte automatische Momentaufnahmen|Taeglich 05:30 Uhr|Alte Snapshots fressen Speicherplatz und bremsen mit der Zeit das System aus. Dieser Job loescht nur Snapshots mit einem bestimmten Namensanfang (Standard auto-), die aelter sind als eine von dir gewaehlte Zahl von Tagen. Von Hand angelegte Snapshots ohne diesen Namensanfang bleiben garantiert unangetastet."
"snapshot-zfs-aufraeumen-taeglich|snapshots|zfs-snapshots-aufraeumen.sh|Loescht alte ZFS-Snapshots auf Dateisystemebene|Taeglich 05:45 Uhr|Neben den Proxmox-Snapshots legt auch ZFS selbst Momentaufnahmen an, zum Beispiel bei Replikation oder wenn ein Snapshot mal nicht sauber aufgeraeumt wurde. Dieser Job listet solche verwaisten ZFS-Snapshots auf und loescht die, die aelter sind als die eingestellte Frist."
"snapshot-anzahl-warnung-taeglich|snapshots|snapshot-anzahl-warnung.sh|Warnt bei zu vielen Momentaufnahmen|Taeglich 09:00 Uhr|Wenn eine VM oder ein Container sehr viele Snapshots angesammelt hat, wird sie langsam und der Speicherplatz laeuft schleichend voll. Dieser Job zaehlt die Snapshots pro System und schreibt eine Warnung ins Log, wenn eine Grenze ueberschritten wird."

# ---------- Speicher und ZFS ----------
"zfs-scrub-monatlich|speicher|zfs-scrub-datenpruefung.sh|Prueft monatlich alle Daten auf Fehler|Erster Sonntag im Monat, 02:00 Uhr|Ein Scrub liest jeden einzelnen gespeicherten Datenblock und vergleicht ihn mit seiner Pruefsumme. Stille Datenfehler (Bitrot) werden dabei erkannt und bei gespiegelten Platten automatisch repariert. Der Scrub laeuft im Hintergrund weiter und macht das System waehrenddessen etwas langsamer - deshalb nachts. Empfehlung: einmal pro Monat."
"zfs-pool-status-taeglich|speicher|zfs-pool-gesundheit-pruefen.sh|Prueft taeglich den Zustand der ZFS-Pools|Taeglich 06:30 Uhr|Meldet, wenn ein ZFS-Pool nicht mehr im Zustand ONLINE ist, also zum Beispiel eine Festplatte ausgefallen ist (DEGRADED) oder Lese-/Schreibfehler aufgetreten sind. So bemerkst du einen Plattenausfall am naechsten Tag statt erst dann, wenn auch die zweite Platte stirbt."
"zfs-trim-monatlich|speicher|zfs-trim-ssd.sh|Haelt SSDs schnell (TRIM)|Erster Samstag im Monat, 03:00 Uhr|Teilt der SSD mit, welche Speicherbereiche nicht mehr benoetigt werden. Ohne TRIM werden SSDs mit der Zeit spuerbar langsamer. Bei normalen Festplatten (HDD) hat der Job keine Wirkung und schadet auch nicht."
"zfs-arc-bericht-woechentlich|speicher|zfs-arc-speicher-bericht.sh|Berichtet ueber den ZFS-Arbeitsspeicherverbrauch|Sonntags 08:00 Uhr|ZFS nutzt einen Teil des Arbeitsspeichers als Cache (ARC). Wenn der zu gross wird, bleibt zu wenig RAM fuer die VMs uebrig. Dieser Bericht zeigt, wie viel Speicher ZFS gerade belegt und wie gut der Cache arbeitet."
"speicherplatz-warnung-taeglich|speicher|speicherplatz-warnung.sh|Warnt wenn eine Festplatte voll wird|Taeglich 08:00 Uhr|Wenn die System-Festplatte vollaeuft, geht bei Proxmox sehr schnell gar nichts mehr: die Weboberflaeche zeigt Fehler, VMs starten nicht und die Konfiguration wird schreibgeschuetzt. Dieser Job prueft alle Laufwerke und schreibt eine Warnung, sobald eines ueber 90 Prozent voll ist."
"lvm-thin-pruefen-taeglich|speicher|lvm-thin-pool-pruefen.sh|Prueft LVM-Thin-Speicher auf Ueberfuellung|Taeglich 08:15 Uhr|Wer LVM-Thin statt ZFS nutzt, hat ein zusaetzliches Risiko: Der Thin-Pool kann voll laufen, obwohl scheinbar noch Platz da ist - und dann werden VM-Festplatten schreibgeschuetzt oder beschaedigt. Der Job prueft Daten- und Metadaten-Fuellstand und warnt rechtzeitig."
"verwaiste-datentraeger-woechentlich|speicher|verwaiste-datentraeger-suchen.sh|Findet Festplatten geloeschter VMs|Samstags 09:00 Uhr|Wenn eine VM oder ein Container geloescht wird, bleibt manchmal die virtuelle Festplatte auf dem Speicher zurueck und belegt weiter Platz. Dieser Job sucht solche verwaisten Datentraeger und listet sie im Log auf. Geloescht wird nichts automatisch - das musst du bewusst selbst tun."
"speicher-status-taeglich|speicher|speicher-status-pruefen.sh|Prueft ob alle Speicher erreichbar sind|Taeglich 07:30 Uhr|Wenn ein Netzwerkspeicher (NFS, CIFS, iSCSI) nicht erreichbar ist, starten die darauf liegenden VMs nicht mehr und Sicherungen schlagen fehl. Der Job prueft den Status aller eingebundenen Speicher und meldet alle, die als inaktiv gemeldet werden."

# ---------- Wartung ----------
"updates-pruefen-woechentlich|wartung|updates-pruefen.sh|Prueft ob Updates verfuegbar sind|Montags 06:00 Uhr|Prueft, ob es neue Pakete gibt, und schreibt die Liste ins Log. Es wird bewusst NICHTS installiert - Updates auf einem Virtualisierungsserver sollte man immer bewusst und zu einem passenden Zeitpunkt einspielen, nicht automatisch mitten im Betrieb."
"sicherheitsupdates-pruefen-taeglich|wartung|sicherheitsupdates-pruefen.sh|Meldet taeglich verfuegbare Sicherheitsupdates|Taeglich 06:15 Uhr|Wie die Update-Pruefung, aber nur fuer sicherheitsrelevante Aktualisierungen. Diese sollte man deutlich schneller einspielen als normale Updates. Auch hier wird nichts automatisch installiert."
"smart-pruefen-taeglich|wartung|festplatten-smart-pruefen.sh|Prueft taeglich die Festplatten-Gesundheit|Taeglich 06:00 Uhr|Jede moderne Festplatte und SSD fuehrt selbst Buch ueber ihren Zustand (SMART-Werte). Der Job liest diese Werte aus und warnt, wenn eine Platte Fehler meldet oder bereits Sektoren ausgefallen sind. Damit hast du meist Wochen Vorwarnzeit vor einem Ausfall."
"kernel-neustart-pruefen-taeglich|wartung|kernel-neustart-pruefen.sh|Meldet wenn ein Neustart noetig ist|Taeglich 07:00 Uhr|Nach einem Kernel-Update laeuft der Server noch mit dem alten Kernel, bis er neu gestartet wird. Dieser Job vergleicht laufenden und installierten Kernel und meldet, wenn ein Neustart faellig ist. Neu gestartet wird natuerlich nichts automatisch."
"logs-aufraeumen-woechentlich|wartung|logs-aufraeumen.sh|Begrenzt die Groesse der System-Logs|Sonntags 03:00 Uhr|Die System-Protokolle (journald) koennen unbemerkt mehrere Gigabyte belegen und so die Systemplatte fuellen. Der Job begrenzt sie auf eine feste Groesse (Standard 500 MB) und loescht die aeltesten Eintraege."
"paketcache-leeren-woechentlich|wartung|paketcache-leeren.sh|Loescht heruntergeladene Installationsdateien|Sonntags 03:30 Uhr|Beim Installieren von Updates werden die Paketdateien heruntergeladen und danach nicht mehr gebraucht - sie bleiben aber liegen. Der Job raeumt diesen Zwischenspeicher auf und gibt so oft mehrere hundert Megabyte frei."
"alte-kernel-entfernen-monatlich|wartung|alte-kernel-entfernen.sh|Entfernt nicht mehr benoetigte alte Kernel|Am 5. des Monats, 04:00 Uhr|Bei jedem Update kommt ein neuer Kernel dazu, die alten bleiben liegen. Auf der kleinen Boot-Partition fuehrt das irgendwann zu Fehlern beim Update. Der Job entfernt alte, nicht mehr benoetigte Kernel und behaelt den aktuellen sowie einen Ersatz-Kernel."
"temp-aufraeumen-woechentlich|wartung|temp-dateien-aufraeumen.sh|Raeumt alte temporaere Dateien auf|Samstags 04:30 Uhr|Loescht Dateien in den Temporaer-Verzeichnissen, die aelter als 7 Tage und groesser als 10 MB sind. Das sind fast immer Reste abgebrochener Vorgaenge, die niemand mehr braucht."
"dienste-ueberwachen-alle-15min|wartung|pve-dienste-ueberwachen.sh|Startet abgestuerzte Proxmox-Dienste neu|Alle 15 Minuten|Prueft, ob die wichtigen Proxmox-Dienste laufen (unter anderem der Dienst hinter der Weboberflaeche). Falls einer abgestuerzt ist, wird er automatisch neu gestartet und der Vorfall ins Log geschrieben. Damit ist die Weboberflaeche nach einem Absturz spaetestens nach 15 Minuten wieder da."

# ---------- Sicherheit ----------
"ssl-zertifikat-erneuern-taeglich|sicherheit|ssl-zertifikat-erneuern.sh|Erneuert das HTTPS-Zertifikat automatisch|Taeglich 03:00 Uhr|Wenn du ein Let's-Encrypt-Zertifikat nutzt, laeuft es alle 90 Tage ab und der Browser zeigt dann eine Warnung. Proxmox erneuert normalerweise selbst - dieser Job ist ein Sicherheitsnetz, das taeglich prueft und bei Bedarf erneuert. Ohne Let's Encrypt passiert einfach nichts."
"anmeldungen-pruefen-taeglich|sicherheit|anmeldungen-pruefen.sh|Meldet fehlgeschlagene Anmeldeversuche|Taeglich 07:45 Uhr|Zaehlt die fehlgeschlagenen Anmeldeversuche des letzten Tages (SSH und Weboberflaeche). Viele Fehlversuche von derselben Adresse deuten auf einen Angriffsversuch hin - dann solltest du den Zugang von aussen einschraenken."
"firewall-status-woechentlich|sicherheit|firewall-status-pruefen.sh|Prueft ob die Firewall aktiv ist|Montags 07:15 Uhr|Schreibt woechentlich in das Log, ob die Proxmox-Firewall eingeschaltet ist und welche Regeln aktiv sind. Praktisch, um zu bemerken, wenn die Firewall bei einer Fehlersuche mal abgeschaltet und dann vergessen wurde."
"zeitsynchronisierung-pruefen-taeglich|sicherheit|zeitsynchronisierung-pruefen.sh|Prueft ob die Systemuhr richtig geht|Taeglich 06:45 Uhr|Eine falsch gehende Uhr sorgt fuer erstaunlich viele Probleme: Zertifikate gelten als ungueltig, im Cluster streiten sich die Server, Sicherungen bekommen falsche Zeitstempel. Der Job prueft, ob die Zeitsynchronisierung laeuft und die Abweichung klein ist."
"benutzer-audit-monatlich|sicherheit|benutzerkonten-pruefen.sh|Listet monatlich alle Benutzer und Tokens|Am 1. des Monats, 09:00 Uhr|Schreibt eine Uebersicht aller Proxmox-Benutzerkonten, Gruppen und API-Tokens ins Log. So faellt auf, wenn ein altes Konto oder ein vergessener Zugangstoken noch existiert, den niemand mehr braucht."

# ---------- Cluster ----------
"cluster-quorum-pruefen-stuendlich|cluster|cluster-quorum-pruefen.sh|Prueft ob der Cluster beschlussfaehig ist|Jede Stunde|Nur wenn genug Server im Cluster erreichbar sind, darf Proxmox Aenderungen speichern. Faellt das weg (Quorum verloren), wird die Konfiguration schreibgeschuetzt und VMs lassen sich nicht mehr starten. Dieser Job erkennt den Zustand frueh und schreibt eine Warnung. Auf einem Einzelserver ohne Cluster meldet er einfach nichts."
"ha-status-pruefen-taeglich|cluster|ha-status-pruefen.sh|Prueft die Hochverfuegbarkeits-Dienste|Taeglich 07:15 Uhr|Prueft, ob alle als hochverfuegbar markierten VMs und Container im erwarteten Zustand sind, und meldet Fehlerzustaende wie fence oder error. Ohne konfigurierte HA passiert nichts."
"cluster-netzwerk-pruefen-taeglich|cluster|cluster-netzwerk-pruefen.sh|Prueft die Cluster-Verbindungen|Taeglich 07:20 Uhr|Die Server im Cluster halten ueber ein eigenes Netzwerk (Corosync) staendig Kontakt. Wackelt diese Verbindung, kommt es zu unerklaerlichen Aussetzern und im schlimmsten Fall zu automatischen Neustarts. Der Job prueft die Verbindungsqualitaet aller Links."
"replikation-pruefen-taeglich|cluster|replikation-status-pruefen.sh|Prueft ob die Replikation funktioniert|Taeglich 07:25 Uhr|Wenn VMs per ZFS-Replikation auf einen zweiten Server gespiegelt werden, muss das auch tatsaechlich klappen. Der Job meldet Replikationsauftraege, die Fehler haben oder seit langem nicht mehr erfolgreich gelaufen sind."

# ---------- Netzwerk ----------
"internetverbindung-pruefen-alle-30min|netzwerk|internetverbindung-pruefen.sh|Prueft regelmaessig die Netzwerkverbindung|Alle 30 Minuten|Prueft, ob das Standard-Gateway und ein Server im Internet erreichbar sind, und schreibt Ausfaelle mit Uhrzeit ins Log. So kannst du spaeter nachvollziehen, ob eine Stoerung am Server oder an der Internetleitung lag."
"dns-pruefen-taeglich|netzwerk|dns-aufloesung-pruefen.sh|Prueft ob Namensaufloesung funktioniert|Taeglich 06:20 Uhr|Wenn die Namensaufloesung (DNS) nicht geht, schlagen Updates fehl, Zertifikate lassen sich nicht erneuern und im Cluster finden sich die Server nicht mehr. Der Job testet das taeglich und meldet Probleme frueh."
"freigaben-neu-verbinden-alle-5min|netzwerk|netzwerkfreigaben-neu-verbinden.sh|Verbindet abgerissene Netzwerkfreigaben neu|Alle 5 Minuten|Wenn ein Netzwerkspeicher (NAS) kurz nicht erreichbar war, bleibt die Verbindung manchmal haengen, auch wenn das NAS laengst wieder da ist. Der Job prueft alle eingebundenen Freigaben und verbindet sie bei Bedarf automatisch neu."

# ---------- Konfiguration und Berichte ----------
"konfiguration-sichern-taeglich|konfiguration|proxmox-konfiguration-sichern.sh|Sichert taeglich die Proxmox-Einstellungen|Taeglich 01:00 Uhr|Sichert die Konfigurationsdateien von Proxmox (Speicher-Definitionen, Netzwerk-Einstellungen, Benutzer, VM-Konfigurationen) in ein kleines Archiv. Falls du dich mal aussperrst oder eine Einstellung zerschiesst, kannst du damit den vorherigen Stand nachschauen oder zurueckspielen. Aufbewahrung: 14 Tage."
"vorlagen-aktualisieren-woechentlich|konfiguration|container-vorlagen-aktualisieren.sh|Haelt die Container-Vorlagen aktuell|Montags 05:00 Uhr|Aktualisiert die Liste der herunterladbaren Container-Vorlagen (Debian, Ubuntu, Alpine und so weiter). Ohne das bekommst du beim Anlegen eines neuen Containers nur veraltete Versionen angeboten."
"systembericht-woechentlich|konfiguration|system-wochenbericht.sh|Schreibt einen woechentlichen Systembericht|Sonntags 20:00 Uhr|Fasst einmal pro Woche den Gesamtzustand zusammen: Laufzeit, Auslastung, freier Speicher, Zustand der Pools, Anzahl laufender VMs und Container, letzte Sicherungen. Ein schneller Blick genuegt, um zu sehen, ob alles in Ordnung ist."
"gast-agent-pruefen-woechentlich|konfiguration|gast-agent-pruefen.sh|Findet VMs ohne Gast-Agent|Montags 09:30 Uhr|Ohne den QEMU-Gast-Agent kann Proxmox eine VM nicht sauber herunterfahren und keine konsistenten Sicherungen im laufenden Betrieb erstellen. Der Job listet alle VMs auf, bei denen der Agent fehlt oder nicht antwortet."
"ressourcen-trend-taeglich|konfiguration|ressourcen-auslastung-aufzeichnen.sh|Zeichnet die Auslastung fuer Trends auf|Taeglich 12:00 Uhr|Schreibt jeden Mittag eine Zeile mit Prozessor-, Arbeitsspeicher- und Speicherplatzauslastung in eine Datei. Nach ein paar Wochen sieht man daran gut, ob der Server langsam an seine Grenzen kommt - lange bevor es wirklich eng wird."
)

# ---------- Zugriff auf Job-Felder ----------

job_field() {
    echo "$1" | awk -F'|' -v f="$2" '{print $f}'
}

job_def_by_id() {
    local WANTED="$1" DEF
    for DEF in "${CRON_JOB_DEFS[@]}"; do
        [ "$(job_field "$DEF" 1)" == "$WANTED" ] && { echo "$DEF"; return 0; }
    done
    return 1
}

is_job_enabled() {
    [ -f "$CRON_FILE" ] && grep -q "# job:$1\$" "$CRON_FILE"
}

remove_job_line() {
    [ -f "$CRON_FILE" ] && sed -i "/# job:$1\$/d" "$CRON_FILE"
}

add_cron_line() {
    # $1 = Zeitplan+Befehl (ohne Marker), $2 = Job-ID
    touch "$CRON_FILE"
    remove_job_line "$2"
    echo "$1 # job:$2" >> "$CRON_FILE"
    chmod 644 "$CRON_FILE"
}

get_backup_storage() {
    local SAVED
    SAVED=$(conf_get "BACKUP_STORAGE")
    if [ -n "$SAVED" ]; then
        echo "$SAVED"
        return 0
    fi

    local ITEMS=() NAME TYPE
    while read -r NAME TYPE _; do
        [ -z "$NAME" ] && continue
        ITEMS+=("$NAME" "Typ: $TYPE")
    done < <(pvesm status 2>/dev/null | awk 'NR>1{print $1, $2}')

    if [ ${#ITEMS[@]} -eq 0 ]; then
        pause "Es konnte kein Speicher gefunden werden.\n\nBitte lege in der Proxmox-Weboberflaeche zuerst einen Speicher fuer Sicherungen an (Datacenter -> Storage)." "Kein Speicher gefunden"
        return 1
    fi

    local STORAGE
    STORAGE=$(menu_dialog "Speicher fuer Sicherungen" \
        "Wohin sollen die Sicherungen geschrieben werden?\n\nTipp: Am besten NICHT auf dieselbe Festplatte, auf der auch die VMs liegen - sonst sind bei einem Plattenausfall Original UND Sicherung weg." \
        22 78 10 "" "${ITEMS[@]}")
    [ -z "${STORAGE:-}" ] && return 1

    conf_set "BACKUP_STORAGE" "$STORAGE"
    echo "$STORAGE"
}

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

# ================================================================
# REPARATUR - LOESUNGEN FUER HAEUFIGE PROXMOX-PROBLEME
# ================================================================
#
# Alle Punkte sind so gebaut, dass man KEINE Konsolenbefehle
# tippen muss. Jeder Punkt erklaert vorher in einfacher Sprache,
# was das Problem ist und was jetzt gemacht wird.

erklaere_und_frage() {
    # $1 = Titel, $2 = Erklaerung, $3 = was wird gemacht
    confirm "PROBLEM\n$2\n\nWAS JETZT PASSIERT\n$3\n\nJetzt ausfuehren?" "$1"
}

# ---------- 1. Weboberflaeche und Zugriff ----------

fix_weboberflaeche_neustart() {
    if erklaere_und_frage "Weboberflaeche nicht erreichbar" \
        "Die Proxmox-Weboberflaeche (Adresse mit :8006) laedt nicht mehr,\nzeigt eine leere Seite oder meldet einen Verbindungsfehler.\nDie VMs laufen dabei meist ganz normal weiter." \
        "Die Dienste hinter der Weboberflaeche werden neu gestartet.\nDas dauert wenige Sekunden. Laufende VMs und Container sind\ndavon NICHT betroffen - sie laufen einfach weiter."; then
        run_and_show "systemctl restart pveproxy pvedaemon; sleep 3; systemctl is-active pveproxy pvedaemon pve-cluster pvestatd; echo ''; echo 'Bitte die Weboberflaeche im Browser neu laden (Strg+F5).'" "Weboberflaeche neu gestartet"
        log_action "Weboberflaeche neu gestartet"
    fi
}

fix_weboberflaeche_pruefen() {
    run_and_show "echo '--- Laufen die Dienste? ---'
for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
    printf '%-16s ' \"\$D\"
    systemctl is-active \$D 2>/dev/null || echo 'nicht vorhanden'
done
echo ''
echo '--- Lauscht der Server auf Port 8006? ---'
ss -tlnp 2>/dev/null | grep 8006 || echo 'NEIN - der Webdienst nimmt keine Verbindungen an.'
echo ''
echo '--- IP-Adressen dieses Servers ---'
ip -4 addr show 2>/dev/null | awk '/inet /{print \"  \" \$2, \"(\" \$NF \")\"}'
echo ''
echo '--- Ist die Systemplatte voll? (haeufige Ursache) ---'
df -h / 2>/dev/null | tail -1
echo ''
echo 'Erreichbar unter: https://<eine der IPs oben>:8006'" "Weboberflaeche - Diagnose"
}

fix_zertifikat_neu() {
    if erklaere_und_frage "Zertifikatsfehler im Browser" \
        "Der Browser meldet ein ungueltiges oder abgelaufenes Zertifikat,\noder die Verbindung wird komplett verweigert. Das passiert\nzum Beispiel, wenn der Servername geaendert wurde." \
        "Proxmox erstellt sich ein neues eigenes Zertifikat und startet\nden Webdienst neu. Danach musst du im Browser einmalig wieder\nbestaetigen, dass du der Seite vertraust."; then
        run_and_show "pvecm updatecerts --force 2>&1; systemctl restart pveproxy; sleep 2; echo ''; echo 'Fertig. Browser-Cache leeren und Seite neu laden (Strg+F5).'" "Zertifikat neu erstellt"
        log_action "Zertifikate neu erstellt"
    fi
}

fix_subscription_hinweis() {
    if erklaere_und_frage "Meldung 'Keine gueltige Subscription'" \
        "Bei jeder Anmeldung erscheint ein Fenster mit dem Hinweis\n'You do not have a valid subscription'. Ausserdem schlagen\nUpdates fehl, weil das kostenpflichtige Paketquellen-Repo\nnicht erreichbar ist." \
        "Das kostenpflichtige Enterprise-Repo wird abgeschaltet und\nstattdessen das kostenlose No-Subscription-Repo eingetragen.\nDanach funktionieren Updates wieder normal.\n\nHinweis: Das Hinweisfenster selbst bleibt - es laesst sich\nohne Eingriff in Proxmox-Dateien nicht sauber entfernen."; then
        local TMPFILE
        TMPFILE=$(mktemp)
        {
            echo "--- Enterprise-Repos werden deaktiviert ---"
            for F in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
                [ -f "$F" ] || continue
                if grep -qE '^[^#].*enterprise\.proxmox\.com' "$F"; then
                    cp -a "$F" "$BACKUP_DIR/$(basename "$F").$(date +%Y%m%d_%H%M%S).bak"
                    sed -i -E '/^[^#].*enterprise\.proxmox\.com/ s/^/#/' "$F"
                    echo "  deaktiviert in: $F"
                fi
            done
            for F in /etc/apt/sources.list.d/*.sources; do
                [ -f "$F" ] || continue
                if grep -q 'enterprise\.proxmox\.com' "$F"; then
                    cp -a "$F" "$BACKUP_DIR/$(basename "$F").$(date +%Y%m%d_%H%M%S).bak"
                    if grep -q '^Enabled:' "$F"; then
                        sed -i 's/^Enabled:.*/Enabled: false/' "$F"
                    else
                        echo "Enabled: false" >> "$F"
                    fi
                    echo "  deaktiviert in: $F"
                fi
            done

            echo ""
            echo "--- Kostenloses Repo wird eingerichtet ---"
            CODENAME=$(. /etc/os-release 2>/dev/null; echo "${VERSION_CODENAME:-bookworm}")
            if grep -rq 'pve-no-subscription' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null; then
                sed -i -E '/pve-no-subscription/ s/^#\s*//' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null
                echo "  war bereits vorhanden, wurde aktiviert"
            else
                echo "deb http://download.proxmox.com/debian/pve $CODENAME pve-no-subscription" \
                    > /etc/apt/sources.list.d/pve-no-subscription.list
                echo "  neu angelegt: /etc/apt/sources.list.d/pve-no-subscription.list"
            fi

            echo ""
            echo "--- Paketlisten werden aktualisiert ---"
            apt-get update 2>&1 | tail -15
        } > "$TMPFILE" 2>&1
        info_textbox "$TMPFILE" "Paketquellen umgestellt"
        rm -f "$TMPFILE"
        log_action "Enterprise-Repo deaktiviert, No-Subscription-Repo aktiviert"
    fi
}

menu_weboberflaeche() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Weboberflaeche und Zugriff" \
            "Probleme beim Zugriff auf Proxmox ueber den Browser." \
            20 96 5 "$LAST" \
            "1" "Weboberflaeche laedt nicht - Dienste neu starten" \
            "2" "Nachsehen woran es liegt (Diagnose)" \
            "3" "Zertifikatsfehler im Browser beheben" \
            "4" "Meldung 'Keine gueltige Subscription' / Updates gehen nicht")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_weboberflaeche_neustart ;;
            2) fix_weboberflaeche_pruefen ;;
            3) fix_zertifikat_neu ;;
            4) fix_subscription_hinweis ;;
        esac
    done
}

# ---------- 2. VMs und Container starten nicht ----------

waehle_gast() {
    # Laesst den Nutzer eine VM oder einen Container auswaehlen
    # Gibt "qm 100" oder "pct 200" zurueck
    local ITEMS=() ID NAME STATUS
    while read -r ID STATUS NAME; do
        [ -z "$ID" ] && continue
        ITEMS+=("qm:$ID" "VM $ID - ${NAME:-ohne Namen} (Status: $STATUS)")
    done < <(qm list 2>/dev/null | awk 'NR>1{print $1, $3, $2}')
    while read -r ID STATUS NAME; do
        [ -z "$ID" ] && continue
        ITEMS+=("pct:$ID" "Container $ID - ${NAME:-ohne Namen} (Status: $STATUS)")
    done < <(pct list 2>/dev/null | awk 'NR>1{print $1, $2, $3}')

    if [ ${#ITEMS[@]} -eq 0 ]; then
        pause "Auf diesem Server sind keine VMs oder Container vorhanden."
        return 1
    fi

    menu_dialog "System auswaehlen" "Welche VM oder welchen Container meinst du?" 24 96 14 "" "${ITEMS[@]}"
}

fix_gast_entsperren() {
    if ! confirm "PROBLEM\nEine VM oder ein Container laesst sich nicht starten, stoppen\noder sichern. Es erscheint eine Meldung wie 'VM is locked'\noder 'got lock request timeout'.\n\nURSACHE\nEin frueherer Vorgang (meist eine abgebrochene Sicherung oder\nMigration) wurde nicht sauber beendet und hat eine Sperre\nhinterlassen.\n\nJetzt fortfahren und ein System auswaehlen?" "Sperre aufheben"; then
        return
    fi
    local SEL
    SEL=$(waehle_gast) || return
    [ -z "${SEL:-}" ] && return
    local TYP="${SEL%%:*}" ID="${SEL#*:}"

    if confirm "Sperre fuer ID $ID wirklich aufheben?\n\nWICHTIG: Stelle sicher, dass gerade wirklich KEINE Sicherung\noder Migration fuer dieses System laeuft. Sonst kann die\nvirtuelle Festplatte beschaedigt werden.\n\nUnter 'Tasks' in der Weboberflaeche siehst du laufende Vorgaenge."; then
        run_and_show "$TYP unlock $ID 2>&1; echo ''; echo 'Sperre aufgehoben. Versuche jetzt erneut zu starten.'; $TYP status $ID 2>&1" "Sperre aufgehoben"
        log_action "Sperre aufgehoben fuer $TYP $ID"
    fi
}

fix_gast_startet_nicht() {
    local SEL
    pause "Diese Funktion sammelt alle Informationen, die erklaeren\nkoennen, warum eine VM oder ein Container nicht startet:\n\n- Konfiguration des Systems\n- Zustand der benoetigten Speicher\n- Vorhandene Sperren\n- Die letzten Fehlermeldungen aus dem Protokoll\n\nDu musst nichts tippen - waehle im naechsten Schritt einfach\ndas betroffene System aus." "Startprobleme untersuchen"
    SEL=$(waehle_gast) || return
    [ -z "${SEL:-}" ] && return
    local TYP="${SEL%%:*}" ID="${SEL#*:}"

    run_and_show "echo '--- Aktueller Status ---'
$TYP status $ID 2>&1
echo ''
echo '--- Konfiguration ---'
$TYP config $ID 2>&1
echo ''
echo '--- Ist eine Sperre gesetzt? ---'
$TYP config $ID 2>/dev/null | grep -i '^lock' || echo 'Keine Sperre gesetzt (gut)'
echo ''
echo '--- Sind alle Speicher erreichbar? ---'
pvesm status 2>&1
echo ''
echo '--- Freier Arbeitsspeicher ---'
free -h
echo ''
echo '--- Letzte Fehlermeldungen zu ID $ID ---'
journalctl --since '2 hours ago' 2>/dev/null | grep -i \"$ID\" | tail -30 || echo 'Keine Eintraege gefunden'
echo ''
echo '--- Startversuch (Testlauf) ---'
$TYP start $ID 2>&1 | tail -20" "Startproblem - Diagnose ID $ID"
}

fix_gast_startreihenfolge() {
    run_and_show "echo 'Startreihenfolge nach einem Neustart des Servers'
echo '================================================'
echo ''
echo 'Systeme, die beim Booten automatisch starten sollen:'
echo ''
for ID in \$(qm list 2>/dev/null | awk 'NR>1{print \$1}'); do
    ON=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^onboot:/{print \$2}')
    ORDER=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^startup:/{print \$2}')
    NAME=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^name:/{print \$2}')
    printf '  VM %-6s %-24s Autostart: %-4s %s\n' \"\$ID\" \"\$NAME\" \"\${ON:-nein}\" \"\$ORDER\"
done
for ID in \$(pct list 2>/dev/null | awk 'NR>1{print \$1}'); do
    ON=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^onboot:/{print \$2}')
    ORDER=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^startup:/{print \$2}')
    NAME=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^hostname:/{print \$2}')
    printf '  CT %-6s %-24s Autostart: %-4s %s\n' \"\$ID\" \"\$NAME\" \"\${ON:-nein}\" \"\$ORDER\"
done
echo ''
echo 'Aendern in der Weboberflaeche:'
echo '  System auswaehlen -> Options -> Start at boot'
echo '  und Start/Shutdown order fuer die Reihenfolge.'" "Startreihenfolge"
}

fix_alle_starten() {
    if erklaere_und_frage "Nach einem Neustart laeuft nichts mehr" \
        "Nach einem Server-Neustart oder Stromausfall sind VMs und\nContainer nicht wieder hochgekommen, weil der Autostart nicht\ngesetzt ist oder ein Speicher zu spaet bereit war." \
        "Alle Systeme, die auf Autostart gesetzt sind, werden jetzt\nnacheinander gestartet. Systeme, die schon laufen, werden\nuebersprungen."; then
        run_and_show "for ID in \$(qm list 2>/dev/null | awk 'NR>1 && \$3!=\"running\"{print \$1}'); do
    if qm config \$ID 2>/dev/null | grep -q '^onboot: 1'; then
        echo \"Starte VM \$ID ...\"; qm start \$ID 2>&1; sleep 3
    fi
done
for ID in \$(pct list 2>/dev/null | awk 'NR>1 && \$2!=\"running\"{print \$1}'); do
    if pct config \$ID 2>/dev/null | grep -q '^onboot: 1'; then
        echo \"Starte Container \$ID ...\"; pct start \$ID 2>&1; sleep 2
    fi
done
echo ''
echo '--- Zustand jetzt ---'
qm list 2>/dev/null; echo ''; pct list 2>/dev/null" "Autostart-Systeme gestartet"
        log_action "Alle Autostart-Systeme gestartet"
    fi
}

menu_gaeste() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "VMs und Container starten nicht" \
            "Probleme mit virtuellen Maschinen und Containern." \
            20 96 5 "$LAST" \
            "1" "Meldung 'is locked' - Sperre aufheben" \
            "2" "System startet nicht - Ursache suchen" \
            "3" "Nach Neustart laeuft nichts - alles wieder starten" \
            "4" "Startreihenfolge und Autostart ansehen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_gast_entsperren ;;
            2) fix_gast_startet_nicht ;;
            3) fix_alle_starten ;;
            4) fix_gast_startreihenfolge ;;
        esac
    done
}

# ---------- 3. Speicherplatz und Speicher ----------

fix_speicher_uebersicht() {
    run_and_show "echo '--- Belegung aller Laufwerke ---'
df -h -x tmpfs -x devtmpfs 2>/dev/null
echo ''
echo '--- Proxmox-Speicher ---'
pvesm status 2>&1
echo ''
echo '--- ZFS-Pools ---'
zpool list 2>/dev/null || echo 'Kein ZFS im Einsatz'
echo ''
echo '--- Die groessten Verbraucher unterhalb von /var ---'
du -h --max-depth=2 /var 2>/dev/null | sort -rh | head -15
echo ''
echo '--- Groesse der Sicherungen ---'
du -sh /var/lib/vz/dump 2>/dev/null || echo 'Kein Sicherungsverzeichnis gefunden'
echo ''
echo '--- Groesse der System-Protokolle ---'
journalctl --disk-usage 2>/dev/null" "Speicherplatz - Uebersicht"
}

fix_speicher_freimachen() {
    if erklaere_und_frage "Festplatte ist voll" \
        "Die Systemplatte ist voll oder fast voll. Typische Folgen:\ndie Weboberflaeche zeigt Fehler, VMs starten nicht mehr,\nSicherungen schlagen fehl und die Konfiguration wird\nschreibgeschuetzt." \
        "In einem Durchgang wird sicher aufgeraeumt:\n  - System-Protokolle auf 500 MB begrenzt\n  - heruntergeladene Installationsdateien geloescht\n  - alte temporaere Dateien geloescht\n  - nicht mehr benoetigte Pakete entfernt\n\nVMs, Container und Sicherungen werden dabei NICHT angeruehrt."; then
        run_and_show "echo '--- Vorher ---'; df -h / | tail -1; echo ''
echo '--- System-Protokolle begrenzen ---'
journalctl --vacuum-size=500M 2>&1 | tail -3
echo ''
echo '--- Installationsdateien loeschen ---'
du -sh /var/cache/apt/archives 2>/dev/null; apt-get clean; echo 'erledigt'
echo ''
echo '--- Alte temporaere Dateien loeschen ---'
find /tmp /var/tmp -type f -mtime +7 -size +10M -delete -print 2>/dev/null | head -20
echo ''
echo '--- Nicht mehr benoetigte Pakete entfernen ---'
apt-get autoremove --purge -y 2>&1 | tail -5
echo ''
echo '--- Nachher ---'; df -h / | tail -1" "Speicherplatz freigemacht"
        log_action "Speicherplatz-Aufraeumung durchgefuehrt"
    fi
}

fix_alte_backups_loeschen() {
    local TAGE
    TAGE=$(eingabe_dialog "Alte Sicherungen loeschen" \
        "Sicherungen, die aelter sind als diese Anzahl Tage,\nwerden geloescht.\n\nVorsicht: Das laesst sich nicht rueckgaengig machen.\nEmpfehlung: nicht unter 14 Tage gehen." "30")
    [ -z "${TAGE:-}" ] && return

    local TMPFILE
    TMPFILE=$(mktemp)
    find /var/lib/vz/dump -maxdepth 2 -name 'vzdump-*' -type f -mtime +"$TAGE" -printf '%TY-%Tm-%Td  %10s  %p\n' 2>/dev/null > "$TMPFILE"

    if [ ! -s "$TMPFILE" ]; then
        pause "Es wurden keine Sicherungen gefunden, die aelter als $TAGE Tage sind.\n\nEs wurde nichts geloescht."
        rm -f "$TMPFILE"
        return
    fi

    info_textbox "$TMPFILE" "Diese Sicherungen wuerden geloescht"
    local ANZ
    ANZ=$(wc -l < "$TMPFILE")
    rm -f "$TMPFILE"

    if confirm_risky "Diese $ANZ Sicherungsdatei(en) wirklich endgueltig loeschen?\n\nDas kann NICHT rueckgaengig gemacht werden." "Endgueltig loeschen"; then
        run_and_show "find /var/lib/vz/dump -maxdepth 2 -name 'vzdump-*' -mtime +$TAGE -print -delete 2>/dev/null; echo ''; echo '--- Freier Platz jetzt ---'; df -h /var/lib/vz 2>/dev/null | tail -1" "Alte Sicherungen geloescht"
        log_action "Sicherungen aelter als $TAGE Tage geloescht"
    fi
}

fix_verwaiste_disks() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "Virtuelle Festplatten, deren VM/Container nicht mehr existiert"
        echo "=============================================================="
        echo ""
        VORHANDEN=$( (pct list 2>/dev/null | awk 'NR>1{print $1}'; qm list 2>/dev/null | awk 'NR>1{print $1}') )
        GEF=0
        for DS in $(zfs list -H -o name 2>/dev/null | grep -E 'subvol-|vm-'); do
            ID=$(echo "$DS" | grep -oE '(subvol|vm)-[0-9]+' | grep -oE '[0-9]+')
            [ -z "$ID" ] && continue
            if ! echo "$VORHANDEN" | grep -qx "$ID"; then
                echo "  $DS   (belegt $(zfs list -H -o used "$DS" 2>/dev/null))"
                GEF=1
            fi
        done
        [ "$GEF" -eq 0 ] && echo "  Keine verwaisten Festplatten gefunden - alles sauber."
        echo ""
        echo "WICHTIG"
        echo "  Hier wird bewusst nichts automatisch geloescht. Pruefe die"
        echo "  Liste in Ruhe - manchmal gehoert so ein Eintrag noch zu einem"
        echo "  System auf einem anderen Server im Cluster."
        echo ""
        echo "  Loeschen kannst du sie in der Weboberflaeche unter"
        echo "  Datacenter -> Storage -> <Speicher> -> VM Disks."
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Verwaiste virtuelle Festplatten"
    rm -f "$TMPFILE"
}

fix_lvm_thin() {
    run_and_show "echo '--- LVM-Thin-Pools ---'
lvs -o lv_name,vg_name,lv_size,data_percent,metadata_percent 2>/dev/null || echo 'LVM wird auf diesem System nicht genutzt'
echo ''
echo 'ERKLAERUNG'
echo '  Data%  = wie voll der eigentliche Datenbereich ist'
echo '  Meta%  = wie voll die Verwaltungsinformationen sind'
echo ''
echo '  Beide Werte muessen deutlich unter 100% bleiben. Wird einer'
echo '  davon voll, koennen VM-Festplatten beschaedigt werden.'
echo '  Ab 85% solltest du handeln: alte Systeme oder Snapshots'
echo '  loeschen oder den Pool vergroessern.'" "LVM-Thin-Speicher pruefen"
}

fix_speicher_erreichbarkeit() {
    run_and_show "echo '--- Zustand aller eingebundenen Speicher ---'
pvesm status 2>&1
echo ''
echo '--- Eingebundene Netzwerkfreigaben ---'
mount 2>/dev/null | grep -E 'type (nfs|nfs4|cifs)' || echo 'Keine Netzwerkfreigaben eingebunden'
echo ''
echo 'ERKLAERUNG'
echo '  Steht bei einem Speicher nicht \"active\", ist er gerade nicht'
echo '  erreichbar. VMs auf diesem Speicher starten dann nicht und'
echo '  Sicherungen darauf schlagen fehl.'
echo ''
echo '  Haeufige Ursachen: NAS ausgeschaltet, Netzwerkkabel, falsche'
echo '  Zugangsdaten, oder der Speicher wurde umbenannt.'" "Speicher erreichbar?"
}

menu_speicher() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Speicherplatz und Speicher" \
            "Festplatte voll, Speicher nicht erreichbar, aufraeumen." \
            22 96 6 "$LAST" \
            "1" "Wo ist der Platz hin? (Uebersicht)" \
            "2" "Festplatte voll - sicher aufraeumen" \
            "3" "Alte Sicherungen loeschen (mit Vorschau)" \
            "4" "Speicher nicht erreichbar - pruefen" \
            "5" "Verwaiste Festplatten geloeschter VMs finden" \
            "6" "LVM-Thin-Speicher pruefen (Ueberfuellung)")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_speicher_uebersicht ;;
            2) fix_speicher_freimachen ;;
            3) fix_alte_backups_loeschen ;;
            4) fix_speicher_erreichbarkeit ;;
            5) fix_verwaiste_disks ;;
            6) fix_lvm_thin ;;
        esac
    done
}

# ---------- 4. Netzwerk ----------

fix_netzwerk_uebersicht() {
    run_and_show "echo '--- Netzwerkkarten und Adressen ---'
ip -brief -4 addr show 2>/dev/null
echo ''
echo '--- Bruecken (Bridges) ---'
brctl show 2>/dev/null || ip -brief link show type bridge 2>/dev/null
echo ''
echo '--- Standard-Gateway ---'
ip route 2>/dev/null | grep '^default' || echo 'KEIN Gateway gesetzt - kein Internetzugang moeglich!'
echo ''
echo '--- Namensaufloesung (DNS) ---'
cat /etc/resolv.conf 2>/dev/null
echo ''
echo '--- Verbindungstest ---'
GW=\$(ip route 2>/dev/null | awk '/^default/{print \$3; exit}')
if [ -n \"\$GW\" ]; then
    ping -c 2 -W 2 \$GW >/dev/null 2>&1 && echo \"Gateway \$GW: erreichbar\" || echo \"Gateway \$GW: NICHT erreichbar\"
fi
ping -c 2 -W 3 1.1.1.1 >/dev/null 2>&1 && echo 'Internet: erreichbar' || echo 'Internet: NICHT erreichbar'
getent hosts download.proxmox.com >/dev/null 2>&1 && echo 'Namensaufloesung: funktioniert' || echo 'Namensaufloesung: FUNKTIONIERT NICHT'" "Netzwerk - Uebersicht"
}

fix_netzwerk_neuladen() {
    if confirm_risky "PROBLEM\nNach einer Aenderung an den Netzwerkeinstellungen ist die\nVerbindung weg oder die Aenderung wirkt nicht.\n\nWAS JETZT PASSIERT\nDie Netzwerkkonfiguration wird neu eingelesen und angewendet.\n\nACHTUNG\nWenn in der Konfiguration ein Fehler steckt, verlierst du\ndabei moeglicherweise die Verbindung zum Server und kommst\nnur noch ueber Bildschirm und Tastatur direkt am Geraet\nwieder heran.\n\nTrotzdem fortfahren?" "Netzwerk neu laden"; then
        if command -v ifreload &> /dev/null; then
            run_and_show "ifreload -a 2>&1; sleep 2; ip -brief -4 addr show" "Netzwerk neu geladen"
        else
            run_and_show "systemctl restart networking 2>&1; sleep 2; ip -brief -4 addr show" "Netzwerkdienst neu gestartet"
        fi
        log_action "Netzwerk neu geladen"
    fi
}

fix_firewall() {
    local STATUS
    STATUS=$(pve-firewall status 2>/dev/null | head -1)
    local C
    C=$(menu_dialog "Firewall" \
        "Aktueller Zustand: ${STATUS:-unbekannt}\n\nWenn du dich selbst ausgesperrt hast oder eine VM keine\nVerbindung bekommt, kann die Firewall die Ursache sein." \
        20 96 3 "" \
        "1" "Zustand und Regeln ansehen" \
        "2" "Firewall voruebergehend ausschalten (zum Testen)" \
        "3" "Firewall wieder einschalten")
    [ -z "${C:-}" ] && return
    case "$C" in
        1) run_and_show "pve-firewall status 2>&1; echo ''; echo '--- Regeln Datacenter ---'; cat /etc/pve/firewall/cluster.fw 2>/dev/null || echo 'keine'; echo ''; echo '--- Regeln dieser Server ---'; cat /etc/pve/nodes/\$(hostname)/host.fw 2>/dev/null || echo 'keine'" "Firewall-Zustand" ;;
        2)
            if confirm_risky "Firewall wirklich ausschalten?\n\nDer Server ist danach nicht mehr durch die Proxmox-Firewall\ngeschuetzt. Nur zum Eingrenzen eines Problems verwenden und\ndanach wieder einschalten." "Firewall ausschalten"; then
                run_and_show "pve-firewall stop 2>&1; sleep 1; pve-firewall status 2>&1" "Firewall ausgeschaltet"
                log_action "Firewall ausgeschaltet"
            fi
            ;;
        3)
            run_and_show "pve-firewall start 2>&1; sleep 1; pve-firewall status 2>&1" "Firewall eingeschaltet"
            log_action "Firewall eingeschaltet"
            ;;
    esac
}

fix_dns() {
    if erklaere_und_frage "Namensaufloesung geht nicht" \
        "Updates schlagen fehl mit Meldungen wie 'Temporary failure\nresolving...', Zertifikate lassen sich nicht erneuern und im\nCluster finden sich die Server nicht mehr." \
        "Es wird geprueft, welche DNS-Server eingetragen sind und ob\nsie antworten. Bei Bedarf kannst du danach einen funktionierenden\nDNS-Server eintragen."; then
        run_and_show "echo '--- Eingetragene DNS-Server ---'; cat /etc/resolv.conf 2>/dev/null
echo ''
echo '--- Test der Namensaufloesung ---'
for N in download.proxmox.com deb.debian.org google.com; do
    printf '%-28s ' \"\$N\"
    getent hosts \$N >/dev/null 2>&1 && echo 'OK' || echo 'FEHLGESCHLAGEN'
done
echo ''
echo '--- Sind die DNS-Server ueberhaupt erreichbar? ---'
grep '^nameserver' /etc/resolv.conf 2>/dev/null | awk '{print \$2}' | while read -r S; do
    printf '%-20s ' \"\$S\"
    ping -c 1 -W 2 \$S >/dev/null 2>&1 && echo 'antwortet' || echo 'antwortet NICHT'
done" "DNS - Diagnose"

        if confirm "Moechtest du jetzt einen anderen DNS-Server eintragen?\n\nEmpfehlung, falls dein Router nicht funktioniert:\n1.1.1.1 (Cloudflare) oder 9.9.9.9 (Quad9)"; then
            local NEU
            NEU=$(eingabe_dialog "DNS-Server" \
                "IP-Adresse des DNS-Servers eingeben:" "1.1.1.1")
            if [ -n "${NEU:-}" ]; then
                backup_file /etc/resolv.conf > /dev/null
                run_and_show "sed -i '1i nameserver $NEU' /etc/resolv.conf; echo 'Neuer Inhalt von /etc/resolv.conf:'; cat /etc/resolv.conf; echo ''; getent hosts download.proxmox.com >/dev/null 2>&1 && echo 'Test: Namensaufloesung funktioniert jetzt' || echo 'Test: funktioniert weiterhin nicht'" "DNS-Server eingetragen"
                log_action "DNS-Server $NEU eingetragen"
            fi
        fi
    fi
}

fix_freigaben_neuverbinden() {
    if erklaere_und_frage "Netzwerkfreigabe (NAS) haengt" \
        "Ein Verzeichnis vom NAS ist nicht mehr erreichbar oder das\nSystem haengt beim Zugriff darauf, obwohl das NAS laengst\nwieder laeuft." \
        "Alle in der Systemkonfiguration eingetragenen Netzwerkfreigaben\nwerden geprueft und bei Bedarf neu verbunden."; then
        run_and_show "GEF=0
awk '\$3==\"nfs\" || \$3==\"nfs4\" || \$3==\"cifs\" {print \$2}' /etc/fstab 2>/dev/null | while read -r MP; do
    GEF=1
    printf '%-40s ' \"\$MP\"
    if mountpoint -q \"\$MP\" 2>/dev/null; then
        echo 'bereits verbunden'
    else
        if mount \"\$MP\" 2>/dev/null; then echo 'neu verbunden'; else echo 'FEHLGESCHLAGEN - Server erreichbar?'; fi
    fi
done
awk '\$3==\"nfs\" || \$3==\"nfs4\" || \$3==\"cifs\"' /etc/fstab 2>/dev/null | grep -q . || echo 'In der Systemkonfiguration sind keine Netzwerkfreigaben eingetragen.'" "Netzwerkfreigaben"
        log_action "Netzwerkfreigaben neu verbunden"
    fi
}

menu_netzwerk() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Netzwerk-Probleme" \
            "Keine Verbindung, DNS geht nicht, Freigaben haengen." \
            20 96 5 "$LAST" \
            "1" "Netzwerk-Uebersicht und Verbindungstest" \
            "2" "Namensaufloesung (DNS) reparieren" \
            "3" "Netzwerkfreigaben (NAS) neu verbinden" \
            "4" "Firewall pruefen / aus- und einschalten" \
            "5" "Netzwerkeinstellungen neu laden (mit Warnung)")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_netzwerk_uebersicht ;;
            2) fix_dns ;;
            3) fix_freigaben_neuverbinden ;;
            4) fix_firewall ;;
            5) fix_netzwerk_neuladen ;;
        esac
    done
}

# ---------- 5. Updates und Paketquellen ----------

fix_apt_reparieren() {
    if erklaere_und_frage "Updates schlagen fehl" \
        "Beim Installieren von Updates bricht der Vorgang ab, es\nerscheinen Meldungen wie 'dpkg was interrupted', 'unmet\ndependencies' oder 'could not get lock'." \
        "Die Paketverwaltung wird repariert: unterbrochene Installationen\nwerden abgeschlossen, fehlende Abhaengigkeiten nachinstalliert\nund die Paketlisten neu eingelesen. Das ist ein sicherer,\nstandardmaessiger Reparaturvorgang."; then
        run_and_show "echo '--- Haengende Sperren entfernen ---'
fuser -k /var/lib/dpkg/lock-frontend 2>/dev/null; fuser -k /var/lib/apt/lists/lock 2>/dev/null
rm -f /var/lib/apt/lists/lock /var/cache/apt/archives/lock /var/lib/dpkg/lock-frontend 2>/dev/null
echo 'erledigt'
echo ''
echo '--- Unterbrochene Installationen abschliessen ---'
dpkg --configure -a 2>&1 | tail -10
echo ''
echo '--- Fehlende Abhaengigkeiten nachinstallieren ---'
apt-get install -f -y 2>&1 | tail -10
echo ''
echo '--- Paketlisten neu einlesen ---'
apt-get update 2>&1 | tail -15" "Paketverwaltung repariert"
        log_action "Paketverwaltung repariert"
    fi
}

fix_paketquellen_anzeigen() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "Eingetragene Paketquellen"
        echo "=========================================================="
        echo ""
        for F in /etc/apt/sources.list /etc/apt/sources.list.d/*; do
            [ -f "$F" ] || continue
            echo "--- $F ---"
            grep -vE '^\s*$' "$F" | sed 's/^/  /'
            echo ""
        done
        echo "ERKLAERUNG"
        echo "  Zeilen die mit # beginnen sind abgeschaltet."
        echo "  Das Enterprise-Repo funktioniert nur mit bezahlter"
        echo "  Subscription. Ohne Subscription brauchst du stattdessen"
        echo "  das no-subscription-Repo."
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Paketquellen"
    rm -f "$TMPFILE"
}

fix_updates_installieren() {
    if confirm_risky "PROBLEM\nDas System soll auf den neuesten Stand gebracht werden.\n\nWAS JETZT PASSIERT\nAlle verfuegbaren Updates werden installiert (dist-upgrade).\n\nWICHTIG ZU WISSEN\n  - Der Vorgang kann einige Minuten dauern\n  - Laufende VMs sind normalerweise nicht betroffen\n  - Bei einem Kernel-Update ist danach ein Neustart faellig\n  - Auf produktiven Systemen: vorher Sicherung pruefen!\n\nJetzt installieren?" "Updates installieren"; then
        run_and_show "export DEBIAN_FRONTEND=noninteractive
apt-get update 2>&1 | tail -5
echo ''
echo '--- Installiere Updates ---'
apt-get dist-upgrade -y 2>&1 | tail -40
echo ''
echo '--- Ist ein Neustart faellig? ---'
LAEUFT=\$(uname -r)
echo \"Laufender Kernel: \$LAEUFT\"
dpkg -l 2>/dev/null | grep -E 'proxmox-kernel-[0-9]|pve-kernel-[0-9]' | awk '{print \"Installiert: \" \$3}' | tail -3" "Updates installiert"
        log_action "System-Updates installiert"
    fi
}

menu_updates() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Updates und Paketquellen" \
            "Updates gehen nicht, Subscription-Meldung, Paketquellen." \
            20 96 4 "$LAST" \
            "1" "Updates schlagen fehl - Paketverwaltung reparieren" \
            "2" "Subscription-Meldung / kostenloses Repo einrichten" \
            "3" "Eingetragene Paketquellen ansehen" \
            "4" "Alle Updates jetzt installieren")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_apt_reparieren ;;
            2) fix_subscription_hinweis ;;
            3) fix_paketquellen_anzeigen ;;
            4) fix_updates_installieren ;;
        esac
    done
}

# ---------- 6. Festplatten und ZFS ----------

fix_zfs_status() {
    run_and_show "echo '--- Zustand aller ZFS-Pools ---'
zpool status 2>/dev/null || echo 'Kein ZFS im Einsatz'
echo ''
echo '--- Belegung ---'
zpool list 2>/dev/null
echo ''
echo 'ERKLAERUNG DER ZUSTAENDE'
echo '  ONLINE    Alles in Ordnung'
echo '  DEGRADED  Eine Platte ist ausgefallen - der Pool laeuft noch,'
echo '            aber ohne Ausfallsicherheit. JETZT handeln!'
echo '  FAULTED   Schwerer Fehler - Daten sind in Gefahr'
echo '  OFFLINE   Platte wurde bewusst abgeschaltet'
echo ''
echo '  Bei READ/WRITE/CKSUM-Fehlern groesser 0 kuendigt sich meist'
echo '  ein Plattendefekt an. Sicherung pruefen und Platte tauschen.'" "ZFS-Pools - Zustand"
}

fix_zfs_scrub() {
    local POOLS ITEMS=()
    POOLS=$(zpool list -H -o name 2>/dev/null)
    if [ -z "$POOLS" ]; then
        pause "Auf diesem System wird kein ZFS verwendet."
        return
    fi
    while IFS= read -r P; do
        ITEMS+=("$P" "Belegt: $(zpool list -H -o capacity "$P" 2>/dev/null), Zustand: $(zpool list -H -o health "$P" 2>/dev/null)")
    done <<< "$POOLS"

    local SEL
    SEL=$(menu_dialog "Datenpruefung starten" \
        "Ein Scrub liest alle gespeicherten Daten und prueft sie auf\nFehler. Erkannte Fehler werden bei gespiegelten Platten\nautomatisch repariert.\n\nDer Vorgang laeuft im Hintergrund weiter (je nach Datenmenge\nStunden) und macht das System dabei etwas langsamer.\n\nWelchen Pool pruefen?" \
        22 90 8 "" "${ITEMS[@]}")
    [ -z "${SEL:-}" ] && return

    run_and_show "zpool scrub '$SEL' 2>&1; sleep 2; zpool status '$SEL' 2>&1; echo ''; echo 'Der Scrub laeuft jetzt im Hintergrund.'; echo 'Den Fortschritt siehst du jederzeit unter Punkt 1.'" "Datenpruefung gestartet"
    log_action "ZFS-Scrub gestartet fuer Pool $SEL"
}

fix_zfs_fehler_zuruecksetzen() {
    local POOLS ITEMS=()
    POOLS=$(zpool list -H -o name 2>/dev/null)
    [ -z "$POOLS" ] && { pause "Auf diesem System wird kein ZFS verwendet."; return; }
    while IFS= read -r P; do ITEMS+=("$P" "Zustand: $(zpool list -H -o health "$P" 2>/dev/null)"); done <<< "$POOLS"

    local SEL
    SEL=$(menu_dialog "Fehlerzaehler zuruecksetzen" \
        "Nach einem behobenen Problem (zum Beispiel ein loses Kabel,\ndas wieder fest steckt) bleibt der Fehlerzaehler stehen.\n\nWICHTIG: Setze den Zaehler NUR zurueck, wenn du die Ursache\nwirklich behoben hast. Sonst uebersiehst du eine sterbende\nFestplatte.\n\nWelchen Pool?" \
        22 90 8 "" "${ITEMS[@]}")
    [ -z "${SEL:-}" ] && return

    if confirm_risky "Fehlerzaehler fuer Pool '$SEL' wirklich zuruecksetzen?" "Zuruecksetzen"; then
        run_and_show "zpool clear '$SEL' 2>&1; sleep 1; zpool status '$SEL' 2>&1" "Fehlerzaehler zurueckgesetzt"
        log_action "ZFS-Fehlerzaehler zurueckgesetzt fuer $SEL"
    fi
}

fix_zfs_arc_begrenzen() {
    local AKTUELL MAX GESAMT
    if [ -f /proc/spl/kstat/zfs/arcstats ]; then
        AKTUELL=$(awk '/^size /{printf "%.1f", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats)
        MAX=$(awk '/^c_max /{printf "%.1f", $3/1024/1024/1024}' /proc/spl/kstat/zfs/arcstats)
    fi
    GESAMT=$(free -g | awk '/^Mem:/{print $2}')

    if ! confirm "PROBLEM\nDie VMs haben zu wenig Arbeitsspeicher, weil ZFS einen grossen\nTeil davon als Cache belegt.\n\nAKTUELLE WERTE\n  Arbeitsspeicher gesamt:  ${GESAMT:-?} GB\n  ZFS-Cache belegt gerade: ${AKTUELL:-?} GB\n  ZFS-Cache Obergrenze:    ${MAX:-?} GB\n\nWAS DU WISSEN SOLLTEST\nZFS gibt den Cache eigentlich frei, wenn eine VM Speicher\nbraucht. Eine feste Grenze ist trotzdem sinnvoll, damit die\nAufteilung planbar bleibt.\n\nFaustregel: 1 GB Cache pro TB Speicher, mindestens 2 GB,\nhoechstens die Haelfte des Arbeitsspeichers.\n\nGrenze jetzt festlegen?" "ZFS-Cache begrenzen"; then
        return
    fi

    local NEU
    NEU=$(eingabe_dialog "Obergrenze fuer den ZFS-Cache" \
        "Obergrenze in Gigabyte eingeben:\n\nBei ${GESAMT:-?} GB Gesamtspeicher waere etwa\n$(( ${GESAMT:-8} / 4 )) GB ein vernuenftiger Wert." "$(( ${GESAMT:-8} / 4 ))")
    [ -z "${NEU:-}" ] && return

    if ! [[ "$NEU" =~ ^[0-9]+$ ]] || [ "$NEU" -lt 1 ]; then
        pause "Bitte eine ganze Zahl groesser 0 eingeben."
        return
    fi

    local BYTES=$(( NEU * 1024 * 1024 * 1024 ))
    run_and_show "echo $BYTES > /sys/module/zfs/parameters/zfs_arc_max 2>/dev/null && echo 'Sofort wirksam gesetzt.' || echo 'Konnte nicht sofort gesetzt werden.'
echo 'options zfs zfs_arc_max=$BYTES' > /etc/modprobe.d/zfs.conf
echo 'Dauerhaft gespeichert in /etc/modprobe.d/zfs.conf'
update-initramfs -u 2>&1 | tail -3
echo ''
echo 'Die Obergrenze liegt jetzt bei $NEU GB.'
echo 'Vollstaendig wirksam wird sie nach dem naechsten Neustart.'" "ZFS-Cache begrenzt"
    log_action "ZFS-ARC-Obergrenze auf $NEU GB gesetzt"
}

fix_smart() {
    run_and_show "command -v smartctl >/dev/null 2>&1 || { echo 'Das Programm smartctl fehlt.'; echo 'Nachinstallieren: Menue -> Reparatur -> Updates -> Paketverwaltung reparieren'; echo 'und danach: apt install smartmontools'; exit 0; }
echo '--- Zustand aller Festplatten und SSDs ---'
echo ''
for P in \$(lsblk -d -n -o NAME 2>/dev/null | grep -E '^sd|^nvme'); do
    MODELL=\$(smartctl -i /dev/\$P 2>/dev/null | awk -F': +' '/Device Model|Model Number/{print \$2; exit}')
    GESUND=\$(smartctl -H /dev/\$P 2>/dev/null | grep -iE 'result|status' | head -1 | cut -d: -f2-)
    STUNDEN=\$(smartctl -A /dev/\$P 2>/dev/null | awk '/Power_On_Hours|Power On Hours/{print \$10; exit}')
    DEFEKT=\$(smartctl -A /dev/\$P 2>/dev/null | awk '/Reallocated_Sector_Ct/{print \$10; exit}')
    echo \"/dev/\$P  \${MODELL:-unbekannt}\"
    echo \"   Gesundheit:       \${GESUND:-keine Angabe}\"
    echo \"   Betriebsstunden:  \${STUNDEN:-keine Angabe}\"
    echo \"   Defekte Sektoren: \${DEFEKT:-keine Angabe}\"
    echo ''
done
echo 'ERKLAERUNG'
echo '  PASSED / OK      Platte meldet sich als gesund'
echo '  FAILED           Platte meldet einen Defekt - sofort tauschen!'
echo '  Defekte Sektoren Sollte 0 sein. Steigt der Wert, stirbt die Platte.'" "Festplatten-Gesundheit"
}

menu_festplatten() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Festplatten und ZFS" \
            "Plattenfehler, ZFS-Pools, Arbeitsspeicher-Cache." \
            20 96 5 "$LAST" \
            "1" "Zustand der ZFS-Pools ansehen" \
            "2" "Gesundheit der Festplatten pruefen (SMART)" \
            "3" "Datenpruefung starten (Scrub)" \
            "4" "Fehlerzaehler zuruecksetzen (nach behobenem Problem)" \
            "5" "ZFS belegt zu viel Arbeitsspeicher - begrenzen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_zfs_status ;;
            2) fix_smart ;;
            3) fix_zfs_scrub ;;
            4) fix_zfs_fehler_zuruecksetzen ;;
            5) fix_zfs_arc_begrenzen ;;
        esac
    done
}

# ---------- 7. Cluster und Hochverfuegbarkeit ----------

fix_cluster_status() {
    run_and_show "if [ ! -f /etc/pve/corosync.conf ]; then
    echo 'Dieser Server ist kein Teil eines Clusters.'
    echo 'Alle Cluster-Funktionen sind hier ohne Bedeutung.'
    exit 0
fi
echo '--- Cluster-Zustand ---'
pvecm status 2>&1
echo ''
echo '--- Knoten im Cluster ---'
pvecm nodes 2>&1
echo ''
echo '--- Verbindungsqualitaet ---'
corosync-cfgtool -s 2>&1
echo ''
echo 'ERKLAERUNG'
echo '  Quorate: Yes  Der Cluster ist beschlussfaehig, alles in Ordnung'
echo '  Quorate: No   Zu wenige Server erreichbar. Die Konfiguration ist'
echo '                jetzt schreibgeschuetzt, VMs starten nicht mehr.'
echo ''
echo '  FAULTY bei den Verbindungen bedeutet, dass das Cluster-Netzwerk'
echo '  gestoert ist - haeufigste Ursache fuer unerklaerliche Ausfaelle.'" "Cluster-Zustand"
}

fix_cluster_dienste_neustart() {
    if confirm_risky "PROBLEM\nDer Cluster meldet Probleme, /etc/pve ist schreibgeschuetzt\noder die Server sehen sich gegenseitig nicht mehr.\n\nWAS JETZT PASSIERT\nDie Cluster-Dienste auf DIESEM Server werden neu gestartet.\n\nACHTUNG\nWaehrend des Neustarts ist dieser Server kurz nicht Teil des\nClusters. Bei aktivierter Hochverfuegbarkeit kann das im\nschlimmsten Fall einen automatischen Neustart des Servers\nausloesen (Fencing).\n\nBei aktiver HA lieber zuerst den Support-Weg gehen.\n\nTrotzdem fortfahren?" "Cluster-Dienste neu starten"; then
        run_and_show "systemctl restart corosync 2>&1; sleep 5; systemctl restart pve-cluster 2>&1; sleep 5
echo '--- Zustand danach ---'
systemctl is-active corosync pve-cluster
echo ''
pvecm status 2>&1 | head -20" "Cluster-Dienste neu gestartet"
        log_action "Cluster-Dienste neu gestartet"
    fi
}

fix_cluster_quorum_notfall() {
    if ! confirm_risky "NOTFALL-FUNKTION - BITTE GENAU LESEN\n\nPROBLEM\nDer Cluster hat kein Quorum, weil zu wenige Server laufen.\nDie Konfiguration ist schreibgeschuetzt und VMs lassen sich\nnicht starten.\n\nWAS DIESE FUNKTION MACHT\nSie setzt die Anzahl der benoetigten Stimmen auf 1 herunter.\nDamit kann DIESER Server allein weiterarbeiten.\n\nDIE GEFAHR\nWenn die anderen Server in Wahrheit noch laufen und du nur\ndie Netzwerkverbindung verloren hast, arbeiten danach mehrere\nServer unabhaengig voneinander an denselben Daten. Das nennt\nman Split-Brain und fuehrt zu Datenverlust.\n\nNUR verwenden, wenn du SICHER weisst, dass die anderen Server\nwirklich ausgeschaltet sind.\n\nWirklich fortfahren?" "NOTFALL - Split-Brain-Gefahr"; then
        return
    fi
    if ! confirm_risky "Letzte Rueckfrage:\n\nSind die anderen Cluster-Server WIRKLICH ausgeschaltet?" "Wirklich sicher?"; then
        return
    fi
    run_and_show "pvecm expected 1 2>&1; sleep 2; pvecm status 2>&1 | head -20; echo ''; echo 'WICHTIG: Sobald die anderen Server wieder laufen, muss der'; echo 'Cluster-Zustand geprueft werden.'" "Quorum herabgesetzt"
    log_action "NOTFALL: pvecm expected 1 ausgefuehrt"
}

fix_zeit() {
    if erklaere_und_frage "Uhrzeit stimmt nicht" \
        "Eine falsch gehende Uhr verursacht erstaunlich viele Probleme:\nZertifikate gelten als ungueltig, im Cluster streiten sich die\nServer, Sicherungen bekommen falsche Zeitstempel." \
        "Der Zustand der Zeitsynchronisierung wird geprueft und der\nZeitdienst neu gestartet, damit die Uhr sich neu abgleicht."; then
        run_and_show "echo '--- Vorher ---'
timedatectl status 2>&1
echo ''
echo '--- Zeitdienst neu starten ---'
systemctl restart systemd-timesyncd 2>/dev/null || systemctl restart chrony 2>/dev/null || echo 'Kein bekannter Zeitdienst gefunden'
sleep 5
echo ''
echo '--- Nachher ---'
timedatectl status 2>&1
command -v chronyc >/dev/null 2>&1 && chronyc tracking 2>&1 | head -8" "Zeitsynchronisierung"
        log_action "Zeitsynchronisierung neu gestartet"
    fi
}

fix_ha_status() {
    run_and_show "if ! command -v ha-manager >/dev/null 2>&1; then echo 'Hochverfuegbarkeit ist auf diesem System nicht verfuegbar.'; exit 0; fi
echo '--- Zustand der hochverfuegbaren Dienste ---'
ha-manager status 2>&1 || echo 'Keine HA-Dienste konfiguriert'
echo ''
echo '--- Konfiguration ---'
ha-manager config 2>&1 || echo 'Keine HA-Konfiguration vorhanden'
echo ''
echo 'ERKLAERUNG DER ZUSTAENDE'
echo '  started   Laeuft wie gewuenscht'
echo '  stopped   Bewusst gestoppt'
echo '  error     Fehler - muss von Hand quittiert werden'
echo '  fence     Der Server wird gerade zwangsweise neu gestartet'" "Hochverfuegbarkeit"
}

menu_cluster() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Cluster und Hochverfuegbarkeit" \
            "Nur relevant, wenn mehrere Proxmox-Server zusammenarbeiten." \
            20 96 5 "$LAST" \
            "1" "Cluster-Zustand ansehen" \
            "2" "Hochverfuegbarkeit (HA) ansehen" \
            "3" "Uhrzeit stimmt nicht - Zeitdienst reparieren" \
            "4" "Cluster-Dienste neu starten" \
            "5" "NOTFALL: Quorum herabsetzen (Split-Brain-Gefahr)")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_cluster_status ;;
            2) fix_ha_status ;;
            3) fix_zeit ;;
            4) fix_cluster_dienste_neustart ;;
            5) fix_cluster_quorum_notfall ;;
        esac
    done
}

# ---------- 8. Dienste und System ----------

fix_dienste_status() {
    run_and_show "echo '--- Zustand der Proxmox-Dienste ---'
echo ''
for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler pve-firewall corosync; do
    systemctl list-unit-files 2>/dev/null | grep -q \"^\${D}.service\" || continue
    printf '  %-18s %s\n' \"\$D\" \"\$(systemctl is-active \$D 2>/dev/null)\"
done
echo ''
echo '--- Dienste mit Fehlern im gesamten System ---'
systemctl --failed --no-pager 2>&1 | head -20
echo ''
echo 'ERKLAERUNG DER DIENSTE'
echo '  pve-cluster    Verwaltet die Konfiguration (/etc/pve)'
echo '  pvedaemon      Fuehrt die eigentlichen Aufgaben aus'
echo '  pveproxy       Die Weboberflaeche'
echo '  pvestatd       Sammelt Statistiken und Zustaende'
echo '  pvescheduler   Startet geplante Sicherungen'" "Dienste-Zustand"
}

fix_dienste_neustart() {
    if erklaere_und_frage "Proxmox reagiert seltsam" \
        "Die Weboberflaeche zeigt keine aktuellen Werte an, Aufgaben\nbleiben haengen oder Statistiken fehlen - obwohl die VMs\nnormal weiterlaufen." \
        "Alle Proxmox-Kerndienste werden nacheinander neu gestartet.\nLaufende VMs und Container sind davon NICHT betroffen und\nlaufen einfach weiter. Die Weboberflaeche ist waehrenddessen\nfuer einige Sekunden nicht erreichbar."; then
        run_and_show "for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
    systemctl list-unit-files 2>/dev/null | grep -q \"^\${D}.service\" || continue
    printf 'Starte %s neu ... ' \"\$D\"
    systemctl restart \$D 2>&1 && echo 'ok' || echo 'FEHLER'
    sleep 2
done
echo ''
echo '--- Zustand danach ---'
for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
    systemctl list-unit-files 2>/dev/null | grep -q \"^\${D}.service\" || continue
    printf '  %-16s %s\n' \"\$D\" \"\$(systemctl is-active \$D)\"
done
echo ''
echo 'Bitte die Weboberflaeche neu laden (Strg+F5).'" "Dienste neu gestartet"
        log_action "Proxmox-Kerndienste neu gestartet"
    fi
}

fix_auslastung() {
    run_and_show "echo '--- Aktuelle Auslastung ---'
uptime
echo ''
echo '--- Arbeitsspeicher ---'
free -h
echo ''
echo '--- Die 15 groessten Verbraucher ---'
ps aux --sort=-%cpu 2>/dev/null | head -16 | awk '{printf \"%-8s %5s%% CPU %5s%% RAM  %s\n\", \$1, \$3, \$4, substr(\$11,1,50)}'
echo ''
echo '--- Speicherzuweisung der laufenden Systeme ---'
for ID in \$(qm list 2>/dev/null | awk 'NR>1 && \$3==\"running\"{print \$1}'); do
    M=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^memory:/{print \$2}')
    N=\$(qm config \$ID 2>/dev/null | awk -F': ' '/^name:/{print \$2}')
    printf '  VM %-6s %-24s %s MB\n' \"\$ID\" \"\$N\" \"\$M\"
done
for ID in \$(pct list 2>/dev/null | awk 'NR>1 && \$2==\"running\"{print \$1}'); do
    M=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^memory:/{print \$2}')
    N=\$(pct config \$ID 2>/dev/null | awk -F': ' '/^hostname:/{print \$2}')
    printf '  CT %-6s %-24s %s MB\n' \"\$ID\" \"\$N\" \"\$M\"
done
echo ''
echo 'TIPP: Wenn in Summe mehr Speicher zugewiesen ist als vorhanden,'
echo 'wird das System bei Last sehr langsam.'" "Auslastung"
}

fix_haengende_aufgaben() {
    run_and_show "echo '--- Laufende Aufgaben ---'
pvesh get /nodes/\$(hostname)/tasks --running 1 --output-format text 2>/dev/null | head -25 || echo 'Konnte Aufgabenliste nicht abrufen'
echo ''
echo '--- Letzte fehlgeschlagene Aufgaben ---'
pvesh get /nodes/\$(hostname)/tasks --errors 1 --limit 15 --output-format text 2>/dev/null | head -25 || echo 'Keine Fehler gefunden'
echo ''
echo 'TIPP'
echo '  Haengt eine Sicherung sehr lange, ist meist der Zielspeicher'
echo '  nicht erreichbar. Abbrechen kannst du sie in der Weboberflaeche'
echo '  unten im Bereich Tasks per Rechtsklick -> Stop.'" "Laufende und fehlgeschlagene Aufgaben"
}

fix_initramfs() {
    if erklaere_und_frage "Server startet nicht mehr richtig" \
        "Nach einem Kernel-Update oder einer Aenderung an den\nFestplatten startet der Server nicht mehr sauber, oder es\nerscheinen Fehler beim Booten." \
        "Das Start-Abbild (initramfs) wird neu gebaut und die\nBootloader-Konfiguration aktualisiert. Das ist ein sicherer\nStandardvorgang und dauert einige Minuten."; then
        run_and_show "echo '--- Start-Abbild neu bauen ---'
update-initramfs -u -k all 2>&1 | tail -15
echo ''
if command -v proxmox-boot-tool >/dev/null 2>&1; then
    echo '--- Bootloader aktualisieren ---'
    proxmox-boot-tool refresh 2>&1 | tail -10
fi
echo ''
echo 'Fertig. Die Aenderung wird beim naechsten Neustart wirksam.'" "Start-Abbild neu gebaut"
        log_action "Initramfs neu gebaut"
    fi
}

menu_dienste() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Dienste und Systemzustand" \
            "Proxmox reagiert langsam, Aufgaben haengen, Dienste pruefen." \
            20 96 5 "$LAST" \
            "1" "Zustand aller Proxmox-Dienste ansehen" \
            "2" "Proxmox-Dienste neu starten" \
            "3" "System ist langsam - Auslastung ansehen" \
            "4" "Haengende und fehlgeschlagene Aufgaben ansehen" \
            "5" "Server startet nicht sauber - Start-Abbild neu bauen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_dienste_status ;;
            2) fix_dienste_neustart ;;
            3) fix_auslastung ;;
            4) fix_haengende_aufgaben ;;
            5) fix_initramfs ;;
        esac
    done
}

# ---------- 9. Aufraeumen und Fehlinstallationen ----------

fix_docker_pruefen() {
    run_and_show "echo '--- Ist Docker auf dem Proxmox-Host installiert? ---'
dpkg -l 2>/dev/null | grep -iE 'docker|containerd' || echo 'Keine Docker-Pakete installiert (gut so)'
echo ''
echo '--- Docker-Dienst ---'
systemctl status docker --no-pager 2>&1 | head -5 || echo 'Kein Docker-Dienst vorhanden'
echo ''
echo '--- Datenverzeichnisse ---'
for D in /var/lib/docker /var/lib/containerd /etc/docker; do
    if [ -d \"\$D\" ]; then echo \"  \$D vorhanden (\$(du -sh \$D 2>/dev/null | cut -f1))\"; else echo \"  \$D nicht vorhanden\"; fi
done
echo ''
echo 'WARUM IST DAS EIN PROBLEM?'
echo '  Docker direkt auf dem Proxmox-Host zu installieren fuehrt zu'
echo '  Konflikten beim Netzwerk und bei der Ressourcenverwaltung.'
echo '  Der richtige Weg: Docker in einer VM oder in einem LXC-Container'
echo '  betreiben, niemals direkt auf dem Host.'" "Docker auf dem Host?"
}

fix_docker_entfernen() {
    if ! dpkg -l 2>/dev/null | grep -qiE 'docker|containerd' && [ ! -d /var/lib/docker ]; then
        pause "Auf diesem Server ist kein Docker installiert.\n\nEs gibt nichts zu entfernen."
        return
    fi
    if ! confirm_risky "PROBLEM\nDocker wurde versehentlich direkt auf dem Proxmox-Host\ninstalliert statt in einer VM oder einem Container.\n\nWAS JETZT PASSIERT\n  - alle Docker- und Containerd-Pakete werden entfernt\n  - die Verzeichnisse /var/lib/docker, /var/lib/containerd\n    und /etc/docker werden geloescht\n  - nicht mehr benoetigte Pakete werden aufgeraeumt\n\nACHTUNG\nALLE Docker-Container, Images und Volumes auf diesem Host\ngehen dabei unwiderruflich verloren.\n\nWirklich fortfahren?" "Docker vom Host entfernen"; then
        return
    fi
    if ! confirm_risky "Letzte Rueckfrage: Wirklich alles loeschen?\n\nDies kann NICHT rueckgaengig gemacht werden." "Wirklich sicher?"; then
        return
    fi
    run_and_show "apt-get purge -y docker-ce docker-ce-cli docker-ce-rootless-extras containerd.io docker-buildx-plugin docker-compose-plugin docker.io docker-doc docker-compose podman-docker 2>&1 | tail -10
apt-get autoremove -y 2>&1 | tail -5
rm -rf /var/lib/docker /var/lib/containerd /etc/docker
groupdel docker 2>/dev/null
echo ''
echo 'Docker wurde vollstaendig vom Proxmox-Host entfernt.'
echo 'Fuer Container-Workloads bitte eine VM oder einen LXC-Container nutzen.'" "Docker entfernt"
    log_action "Docker vom Host entfernt"
}

fix_verwaiste_pakete() {
    local TMPFILE
    TMPFILE=$(mktemp)
    apt-get autoremove --dry-run 2>/dev/null > "$TMPFILE"
    if ! grep -q "Remv\|Remove" "$TMPFILE"; then
        pause "Es wurden keine ueberfluessigen Pakete gefunden.\n\nDas System ist in dieser Hinsicht sauber."
        rm -f "$TMPFILE"
        return
    fi
    info_textbox "$TMPFILE" "Diese Pakete wuerden entfernt (Vorschau)"
    rm -f "$TMPFILE"
    if confirm "Diese Pakete jetzt entfernen?\n\nEs handelt sich um Pakete, die nur als Abhaengigkeit\ninstalliert wurden und jetzt von nichts mehr benoetigt werden.\nDas Entfernen ist normalerweise unbedenklich."; then
        run_and_show "apt-get autoremove --purge -y 2>&1 | tail -20; echo ''; df -h / | tail -1" "Ueberfluessige Pakete entfernt"
        log_action "Verwaiste Pakete entfernt"
    fi
}

fix_konfigurationsreste() {
    local RESTE
    RESTE=$(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')
    if [ -z "$RESTE" ]; then
        pause "Es wurden keine Konfigurationsreste gefunden.\n\nDas System ist sauber."
        return
    fi
    if confirm "Folgende Pakete sind zwar deinstalliert, haben aber noch\nEinstellungsdateien hinterlassen:\n\n$(echo "$RESTE" | head -20 | tr '\n' ' ')\n\nDiese Reste jetzt vollstaendig entfernen?"; then
        run_and_show "dpkg --purge $RESTE 2>&1 | tail -20" "Konfigurationsreste entfernt"
        log_action "Konfigurationsreste entfernt"
    fi
}

fix_defekte_verknuepfungen() {
    local TMPFILE
    TMPFILE=$(mktemp)
    {
        echo "Defekte Verknuepfungen (Symlinks) unter /usr/local, /opt und /etc"
        echo "=================================================================="
        echo ""
        find /usr/local /opt /etc -xtype l 2>/dev/null || true
        echo ""
        echo "(Wenn oben nichts steht, ist alles in Ordnung.)"
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Defekte Verknuepfungen"
    rm -f "$TMPFILE"
    if confirm "Die oben aufgelisteten defekten Verknuepfungen entfernen?\n\n(Falls die Liste leer war, passiert nichts.)"; then
        run_and_show "find /usr/local /opt /etc -xtype l -print -delete 2>/dev/null; echo ''; echo 'Fertig.'" "Verknuepfungen bereinigt"
        log_action "Defekte Symlinks entfernt"
    fi
}

menu_aufraeumen() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Aufraeumen und Fehlinstallationen" \
            "Versehentlich Installiertes und Ueberreste entfernen." \
            20 96 5 "$LAST" \
            "1" "Docker auf dem Host? - pruefen" \
            "2" "Docker vom Host entfernen" \
            "3" "Ueberfluessige Pakete entfernen" \
            "4" "Konfigurationsreste deinstallierter Pakete entfernen" \
            "5" "Defekte Verknuepfungen finden und entfernen")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) fix_docker_pruefen ;;
            2) fix_docker_entfernen ;;
            3) fix_verwaiste_pakete ;;
            4) fix_konfigurationsreste ;;
            5) fix_defekte_verknuepfungen ;;
        esac
    done
}

# ---------- 10. Konfigurationsdateien (fortgeschritten) ----------

WICHTIGE_DATEIEN=(
    "/etc/network/interfaces|Netzwerk-Einstellungen (IP, Bruecken)"
    "/etc/hosts|Zuordnung von Namen zu IP-Adressen"
    "/etc/resolv.conf|DNS-Server fuer die Namensaufloesung"
    "/etc/fstab|Dauerhaft eingebundene Laufwerke und Freigaben"
    "/etc/pve/storage.cfg|Speicher-Definitionen von Proxmox"
    "/etc/pve/datacenter.cfg|Clusterweite Grundeinstellungen"
    "/etc/apt/sources.list|Paketquellen fuer Updates"
    "/etc/vzdump.conf|Standardeinstellungen fuer Sicherungen"
)

datei_bearbeiten() {
    local DATEI="$1"
    if [ ! -f "$DATEI" ]; then
        pause "Die Datei existiert nicht:\n$DATEI"
        return
    fi
    if ! confirm "Datei bearbeiten:\n$DATEI\n\nVorher wird automatisch eine Sicherungskopie angelegt.\n\nDer Editor '$EDITOR_BIN' oeffnet sich gleich.\nSpeichern mit Strg+O, beenden mit Strg+X."; then
        return
    fi
    local SICHERUNG
    SICHERUNG=$(backup_file "$DATEI")
    clear
    "$EDITOR_BIN" "$DATEI"
    log_action "Datei bearbeitet: $DATEI"
    if [ -n "$SICHERUNG" ] && confirm "Aenderungen im Vergleich zur Sicherungskopie anzeigen?"; then
        run_and_show "diff -u '$SICHERUNG' '$DATEI' || true" "Was wurde geaendert?"
    fi
}

menu_dateien() {
    local LAST=""
    while true; do
        local ITEMS=() PFADE=() E NR=0
        for E in "${WICHTIGE_DATEIEN[@]}"; do
            NR=$((NR+1))
            PFADE[NR]="${E%%|*}"
            ITEMS+=("$NR" "$(fuellen "${E%%|*}" 26) ${E#*|}")
        done
        ITEMS+=("Z" "Eine fruehere Sicherungskopie zurueckspielen")
        ITEMS+=("L" "Vorhandene Sicherungskopien ansehen")

        local C
        C=$(menu_dialog "Konfigurationsdateien (fortgeschritten)" \
            "ACHTUNG: Hier bearbeitest du echte Systemdateien.\nVor jeder Aenderung wird automatisch eine Kopie angelegt.\n\nWenn du unsicher bist, nutze lieber die anderen Menuepunkte." \
            24 96 11 "$LAST" "${ITEMS[@]}")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            Z) sicherung_zurueckspielen ;;
            L) run_and_show "ls -lht '$BACKUP_DIR' 2>/dev/null | head -40 || echo 'Noch keine Sicherungskopien vorhanden.'" "Vorhandene Sicherungskopien" ;;
            *) datei_bearbeiten "${PFADE[$C]}" ;;
        esac
    done
}

sicherung_zurueckspielen() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
        pause "Es sind noch keine Sicherungskopien vorhanden."
        return
    fi
    local ITEMS=() NAMEN=() B NR=0
    while IFS= read -r B; do
        [ -f "$BACKUP_DIR/$B" ] || continue
        NR=$((NR+1))
        NAMEN[NR]="$B"
        ITEMS+=("$NR" "$(fuellen "$B" 44) $(date -r "$BACKUP_DIR/$B" '+%d.%m.%Y %H:%M' 2>/dev/null)")
    done < <(ls -1t "$BACKUP_DIR" 2>/dev/null | head -40)
    [ "$NR" -eq 0 ] && { pause "Es sind keine Sicherungskopien vorhanden."; return; }

    local NUM SEL
    NUM=$(menu_dialog "Sicherungskopie zurueckspielen" "Welche Kopie moechtest du zurueckspielen?" 24 92 14 "" "${ITEMS[@]}")
    [ -z "${NUM:-}" ] && return
    SEL="${NAMEN[$NUM]}"

    local ORIG
    ORIG=$(echo "$SEL" | sed -E 's/\.[0-9]{8}_[0-9]{6}\.bak$//')
    local ZIEL
    ZIEL=$(eingabe_dialog "Zielpfad" \
        "Wohin soll die Kopie zurueckgespielt werden?\n\nBitte pruefen - der Vorschlag ist nur geraten." "/etc/$ORIG")
    [ -z "${ZIEL:-}" ] && return

    if confirm_risky "Sicherungskopie\n  $SEL\nzurueckspielen nach\n  $ZIEL\n\nDie aktuelle Datei wird vorher ebenfalls gesichert.\n\nFortfahren?" "Zurueckspielen"; then
        [ -f "$ZIEL" ] && backup_file "$ZIEL" > /dev/null
        cp -a "$BACKUP_DIR/$SEL" "$ZIEL" && pause "Zurueckgespielt nach:\n$ZIEL" || pause "Fehler beim Zurueckspielen."
        log_action "Sicherungskopie zurueckgespielt: $SEL -> $ZIEL"
    fi
}

# ---------- 11. Gesamtdiagnose ----------

gesamtdiagnose() {
    local BERICHT="$LOG_DIR/diagnose_$(date '+%Y%m%d_%H%M%S').txt"
    whiptail --title " Bitte warten " --infobox "Der Systembericht wird erstellt.\n\nDas dauert etwa 10 bis 30 Sekunden." 10 "$(dlg_w 60)"
    {
        echo "=========================================================="
        echo " Proxmox-Systembericht"
        echo " Server: $(hostname)   Erstellt: $(date '+%d.%m.%Y %H:%M:%S')"
        echo "=========================================================="
        echo ""
        echo "### VERSION ###"
        pveversion -v 2>/dev/null | head -10
        echo ""
        echo "### LAUFZEIT UND AUSLASTUNG ###"
        uptime; echo ""; free -h
        echo ""
        echo "### SPEICHERPLATZ ###"
        df -h -x tmpfs -x devtmpfs 2>/dev/null
        echo ""
        echo "### PROXMOX-SPEICHER ###"
        pvesm status 2>/dev/null
        echo ""
        echo "### ZFS ###"
        zpool list 2>/dev/null || echo "kein ZFS"
        echo ""
        zpool status 2>/dev/null | head -40
        echo ""
        echo "### DIENSTE ###"
        for D in pve-cluster pvedaemon pveproxy pvestatd pvescheduler; do
            printf '  %-16s %s\n' "$D" "$(systemctl is-active "$D" 2>/dev/null)"
        done
        echo ""
        systemctl --failed --no-pager 2>/dev/null | head -15
        echo ""
        echo "### VIRTUELLE MASCHINEN ###"
        qm list 2>/dev/null || echo "keine"
        echo ""
        echo "### CONTAINER ###"
        pct list 2>/dev/null || echo "keine"
        echo ""
        echo "### NETZWERK ###"
        ip -brief -4 addr show 2>/dev/null
        echo ""
        ip route 2>/dev/null | head -10
        echo ""
        cat /etc/resolv.conf 2>/dev/null
        echo ""
        echo "### CLUSTER ###"
        if [ -f /etc/pve/corosync.conf ]; then pvecm status 2>/dev/null | head -25; else echo "kein Cluster"; fi
        echo ""
        echo "### FESTPLATTEN ###"
        lsblk -o NAME,SIZE,TYPE,MOUNTPOINT 2>/dev/null | head -30
        echo ""
        echo "### PAKETQUELLEN ###"
        grep -rhE '^[^#]' /etc/apt/sources.list /etc/apt/sources.list.d/*.list 2>/dev/null | head -15
        echo ""
        echo "### LETZTE FEHLER AUS DEM PROTOKOLL ###"
        journalctl -p err --since "24 hours ago" --no-pager 2>/dev/null | tail -40
        echo ""
        echo "### AKTIVE CRON-JOBS DIESES TOOLS ###"
        cat "$CRON_FILE" 2>/dev/null || echo "keine"
        echo ""
        echo "=========================================================="
        echo " Ende des Berichts"
        echo "=========================================================="
    } > "$BERICHT" 2>&1

    info_textbox "$BERICHT" "Systembericht"
    pause "Der Bericht wurde gespeichert unter:\n\n$BERICHT\n\nDu kannst ihn zum Beispiel in ein Support-Forum kopieren,\nwenn du Hilfe brauchst." "Bericht gespeichert"
    log_action "Systembericht erstellt: $BERICHT"
}

# ---------- Reparatur-Hauptmenue ----------

repair_menu() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Reparatur - Problemloesungen" \
            "Waehle aus, welches Problem du hast. Jeder Punkt erklaert\nvorher in einfachen Worten, was gemacht wird - du musst\nkeine Befehle eingeben." \
            26 100 11 "$LAST" \
            "1" "Weboberflaeche laedt nicht / Zertifikatsfehler / Subscription" \
            "2" "VM oder Container startet nicht / ist gesperrt" \
            "3" "Festplatte voll / Speicher nicht erreichbar / aufraeumen" \
            "4" "Kein Netzwerk / DNS geht nicht / NAS haengt" \
            "5" "Updates schlagen fehl / Paketquellen" \
            "6" "Festplattenfehler / ZFS-Probleme / zu wenig Arbeitsspeicher" \
            "7" "Cluster-Probleme / Hochverfuegbarkeit / falsche Uhrzeit" \
            "8" "System langsam / Dienste haengen / Aufgaben bleiben stehen" \
            "9" "Aufraeumen (Docker auf dem Host, Ueberreste)" \
            "10" "Systembericht erstellen (fuer Support oder Forum)" \
            "11" "Konfigurationsdateien bearbeiten (nur fuer Fortgeschrittene)")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) menu_weboberflaeche ;;
            2) menu_gaeste ;;
            3) menu_speicher ;;
            4) menu_netzwerk ;;
            5) menu_updates ;;
            6) menu_festplatten ;;
            7) menu_cluster ;;
            8) menu_dienste ;;
            9) menu_aufraeumen ;;
            10) gesamtdiagnose ;;
            11) menu_dateien ;;
        esac
    done
}

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

# ================================================================
# DEINSTALLATION
# ================================================================

uninstall_tool() {
    if confirm_risky "CronJobs-Proxmox wirklich deinstallieren?\n\nEntfernt werden:\n  - die Menue-Skripte\n  - alle eingerichteten Cron-Jobs\n  - der Menue-Aufruf\n\nErhalten bleiben:\n  - deine Sicherungskopien von Konfigurationsdateien\n  - alle Sicherungen deiner VMs und Container\n  - saemtliche Proxmox-Einstellungen" "Deinstallieren"; then
        if [ -x "$SCRIPT_DIR/uninstall.sh" ]; then
            clear
            "$SCRIPT_DIR/uninstall.sh" --yes
            echo ""
            echo "CronJobs-Proxmox wurde deinstalliert."
            exit 0
        else
            pause "Das Deinstallations-Skript wurde nicht gefunden:\n$SCRIPT_DIR/uninstall.sh"
        fi
    fi
}

hilfe_anzeigen() {
    local TMPFILE
    TMPFILE=$(mktemp)
    cat > "$TMPFILE" << 'HILFE'
CronJobs-Proxmox - Kurzanleitung
==========================================================

BEDIENUNG
  Pfeiltasten hoch/runter   Auswahl bewegen
  Enter                     Auswahl bestaetigen
  Leertaste                 In Checklisten an-/abwaehlen
  Tab                       Zwischen Knoepfen wechseln
  Escape                    Zurueck / Abbrechen

  Der Cursor steht immer schon auf dem Auswahl-Knopf -
  du kannst also einfach Enter druecken.


WAS SIND CRON-JOBS?
  Das sind Aufgaben, die der Server ganz von allein zu einer
  festgelegten Zeit erledigt - zum Beispiel jede Nacht um zwei
  Uhr eine Sicherung erstellen.

  Du waehlst sie einmal aus, danach laufen sie automatisch.
  Du musst nichts weiter tun.


WIE FANGE ICH AN?
  Empfehlung fuer den Einstieg - diese Jobs aktivieren:

  Kategorie Sicherung:
    backup-alle-vms-und-container.sh   (die wichtigste!)
    backup-alte-loeschen.sh            (sonst laeuft die Platte voll)

  Kategorie Speicher und ZFS:
    speicherplatz-warnung.sh
    zfs-scrub-datenpruefung.sh         (nur bei ZFS)

  Kategorie Wartung:
    festplatten-smart-pruefen.sh
    updates-pruefen.sh

  Damit ist das Wichtigste abgedeckt.


WAS MACHT WELCHES SKRIPT?
  In jeder Kategorie gibt es den Punkt
  "Beschreibungen ansehen".

  Dort waehlst du ein Skript aus und druckst Enter - es
  oeffnet sich ein Info-Fenster mit einer ausfuehrlichen
  Erklaerung. Nach dem Schliessen bist du wieder genau an
  derselben Stelle in der Liste.


DER REPARATUR-BEREICH
  Hier findest du Loesungen fuer die haeufigsten Probleme.
  Jeder Punkt erklaert erst in einfachen Worten, was das
  Problem ist und was gleich passieren wird - erst danach
  wird etwas ausgefuehrt.

  Gefaehrliche Aktionen fragen zweimal nach und der Cursor
  steht dabei bewusst auf "Abbrechen".


WO LIEGT WAS?
  Skripte:        /usr/local/bin/cronjobs-proxmox-skripte/
  Zeitplan:       /etc/cron.d/cronjobs-proxmox
  Protokolle:     /var/log/cronjobs-proxmox/
  Sicherungen:    /var/backups/cronjobs-proxmox/


IM ZWEIFEL
  Erstelle unter Reparatur den Punkt "Systembericht" und
  poste ihn im Proxmox-Forum. Darin steht alles, was jemand
  zum Helfen braucht.
HILFE
    info_textbox "$TMPFILE" "Hilfe und Kurzanleitung"
    rm -f "$TMPFILE"
}

# ================================================================
# HAUPTMENUE
# ================================================================

main_menu() {
    local LAST="1"
    while true; do
        local ANZ=0
        [ -f "$CRON_FILE" ] && ANZ=$(grep -c "# job:" "$CRON_FILE" 2>/dev/null)

        local CHOICE
        CHOICE=$(menu_dialog "CronJobs-Proxmox  v$VERSION" \
            "Server: $(hostname)\nAktive automatische Aufgaben: ${ANZ:-0}\n\nWas moechtest du tun?" \
            22 90 5 "$LAST" \
            "1" "Cron-Jobs - automatische Aufgaben einrichten" \
            "2" "Reparatur - Problemloesungen fuer Proxmox" \
            "3" "Protokolle und Verlauf ansehen" \
            "4" "Hilfe - wie bediene ich das hier?" \
            "5" "CronJobs-Proxmox deinstallieren")

        if [ -z "${CHOICE:-}" ]; then
            break
        fi
        LAST="$CHOICE"

        case "$CHOICE" in
            1) cron_main_menu ;;
            2) repair_menu ;;
            3) logs_menu ;;
            4) hilfe_anzeigen ;;
            5) uninstall_tool ;;
        esac
    done
}

# ================================================================
# START
# ================================================================

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

if ! command -v pveversion &> /dev/null; then
    echo "Achtung: Dieses Werkzeug ist fuer Proxmox VE gedacht."
    echo "Auf diesem System wurde kein Proxmox gefunden."
    read -rp "Trotzdem fortfahren? [j/N] " A
    [[ "$A" =~ ^[Jj]$ ]] || exit 1
fi

main_menu
clear
echo "CronJobs-Proxmox beendet."
echo "Erneut starten mit:  cronjobs-proxmox"
