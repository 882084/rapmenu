#!/bin/bash
# ==========================================================
# Hauptmenue
# ==========================================================
# Gegliedert nach dem, was der Nutzer erreichen will -
# nicht nach Technik. Die Namen sollen ohne Vorwissen
# verstaendlich sein.
# ==========================================================

# ── Bereiche, die noch im Aufbau sind ───────────────────

menu_ersteinrichtung() {
    noch_nicht_da "Ersteinrichtung" \
"  - Paketquellen umstellen und Updates einspielen
  - Zeitzone und Uhrzeit pruefen
  - E-Mail-Benachrichtigung mit Testmail
  - Ziel fuer die Sicherungen festlegen
  - Erste automatische Sicherung einrichten
  - Festplattenueberwachung aktivieren
  - Bei ZFS: Arbeitsspeicher-Grenze setzen
  - Benutzer neben root anlegen"
}

menu_sicherung() {
    noch_nicht_da "Sichern und Wiederherstellen" \
"  - Sicherungsplan gefuehrt einrichten
  - Einzelne VM wiederherstellen (auf neue Nummer)
  - Sicherungen auf Lesbarkeit pruefen
  - Sicherungsziel aendern (NAS, USB, Backup Server)
  - Unterschied Snapshot und Backup erklaert

Sicherungs-Aufgaben kannst du heute schon unter
'Automatische Aufgaben' einrichten."
}

menu_netzwerk_top() {
    noch_nicht_da "Netzwerk" \
"  - IP-Adresse aendern mit Rueckgaengig-Countdown
  - Zweite Netzwerkkarte einbinden
  - Zusaetzliche Bruecke anlegen
  - VLAN einrichten
  - Notfall: letzte Netzwerkaenderung zuruecknehmen

Netzwerk-Diagnose und DNS-Reparatur findest du heute
schon unter 'Problem loesen'."
}

menu_speicher_top() {
    noch_nicht_da "Speicher und Festplatten" \
"  - Neue Festplatte gefuehrt einbinden
  - Netzwerkfreigabe (NAS) verbinden
  - Freigabe in einen Container durchreichen
  - Platte sicher loeschen und formatieren

Festplattenzustand, Speicherplatz und Aufraeumen
findest du heute schon unter 'Problem loesen'."
}

menu_gaeste() {
    noch_nicht_da "VMs und Container" \
"  - Container aus Vorlage anlegen
  - Docker richtig aufsetzen (im Container, nicht auf dem Host)
  - Fertige Dienste: Pi-hole, Nextcloud, Home Assistant
  - Arbeitsspeicher, Kerne und Platte aendern
  - Gast-Agent nachruesten

Startprobleme und Sperren loest du heute schon unter
'Problem loesen'."
}

menu_durchreichen() {
    noch_nicht_da "Geraete durchreichen" \
"  - USB-Geraet an eine VM oder einen Container
  - Festplatte direkt durchreichen
  - Grafikkarte durchreichen (Intel, AMD, NVIDIA)
  - Durchreichung wieder aufheben"
}

menu_sicherheit() {
    noch_nicht_da "Sicherheit und Zugang" \
"  - Benutzer anlegen, damit du nicht als root arbeitest
  - Zwei-Faktor-Anmeldung einrichten
  - Firewall: nur aus dem eigenen Heimnetz erreichbar
  - SSH mit Schluessel statt Passwort absichern
  - HTTPS-Zertifikat einrichten
  - Pruefen, ob der Server aus dem Internet erreichbar ist

Die Firewall ein- und ausschalten kannst du heute schon
unter 'Problem loesen'."
}

menu_system() {
    noch_nicht_da "System und Updates" \
"  - Neustart planen (Gaeste sauber herunterfahren)
  - Energiesparen einschalten
  - Temperaturen und Luefter anzeigen
  - Von Proxmox 8 auf 9 umsteigen

Updates einspielen und Paketquellen umstellen geht
heute schon unter 'Problem loesen'."
}

menu_journal() {
    local TMPFILE
    if [ ! -s "$LOG_DIR/aktionen.log" ]; then
        info_box "Es wurde ueber dieses Werkzeug noch nichts geaendert.\n\nSobald du etwas einstellst oder reparierst, wird es hier\nmit Datum und Uhrzeit festgehalten." "Was wurde geaendert"
        return
    fi
    TMPFILE=$(mktemp)
    {
        echo "Alle Aenderungen ueber dieses Werkzeug"
        echo "=========================================================="
        echo ""
        tac "$LOG_DIR/aktionen.log" 2>/dev/null | head -200
        echo ""
        echo "=========================================================="
        echo "Geplant fuer eine spaetere Version:"
        echo "  - jede Aenderung einzeln rueckgaengig machen"
        echo ""
        echo "Bis dahin: Sicherungskopien von Konfigurationsdateien"
        echo "liegen unter $BACKUP_DIR und lassen sich unter"
        echo "'Problem loesen' -> 'Konfigurationsdateien' zurueckspielen."
    } > "$TMPFILE"
    info_textbox "$TMPFILE" "Was wurde geaendert"
    rm -f "$TMPFILE"
}

menu_nachschlagen() {
    local LAST="1"
    while true; do
        local C
        C=$(menu_dialog "Nachschlagen" \
            "Erklaerungen und Hilfen." \
            18 90 4 "$LAST" \
            "1" "Kurzanleitung: wie bediene ich das hier?" \
            "2" "Glossar: Begriffe einfach erklaert" \
            "3" "Systembericht erstellen (fuer Forum oder Support)" \
            "4" "CronJobs-Proxmox deinstallieren")
        [ -z "${C:-}" ] && return
        LAST="$C"
        case "$C" in
            1) hilfe_anzeigen ;;
            2) glossar_anzeigen ;;
            3) gesamtdiagnose ;;
            4) uninstall_tool ;;
        esac
    done
}

# ── Hauptmenue ──────────────────────────────────────────

main_menu() {
    local LAST="1"
    while true; do
        local ANZ=0
        [ -f "$CRON_FILE" ] && ANZ=$(grep -c "# job:" "$CRON_FILE" 2>/dev/null)

        local CHOICE
        CHOICE=$(menu_dialog "CronJobs-Proxmox  v$VERSION" \
            "Server: $(hostname)     Automatische Aufgaben aktiv: ${ANZ:-0}\n\nWas moechtest du tun?" \
            26 100 14 "$LAST" \
            "1"  "Zustand meines Servers        Was ist in Ordnung, was muss ich tun?" \
            "2"  "Ersteinrichtung               Gefuehrter Durchlauf fuer neue Server" \
            "3"  "Automatische Aufgaben         Sicherungen und Pruefungen nach Zeitplan" \
            "4"  "Sichern und Wiederherstellen  Backups einrichten und zurueckspielen" \
            "5"  "Netzwerk                      IP-Adresse, Bruecken, Verbindungen" \
            "6"  "Speicher und Festplatten      Platten einbinden, NAS verbinden" \
            "7"  "VMs und Container             Anlegen, aendern, fertige Vorlagen" \
            "8"  "Geraete durchreichen          Grafikkarte, USB oder Platte an eine VM" \
            "9"  "Sicherheit und Zugang         Benutzer, Firewall, Zwei-Faktor" \
            "10" "System und Updates            Updates, Neustart, Energiesparen" \
            "11" "Problem loesen                Assistenten fuer haeufige Stoerungen" \
            "12" "Was wurde geaendert           Verlauf aller Aenderungen" \
            "13" "Nachschlagen                  Glossar, Hilfe, Systembericht")

        [ -z "${CHOICE:-}" ] && break
        LAST="$CHOICE"

        case "$CHOICE" in
            1)  status_menu ;;
            2)  menu_ersteinrichtung ;;
            3)  cron_main_menu ;;
            4)  menu_sicherung ;;
            5)  menu_netzwerk_top ;;
            6)  menu_speicher_top ;;
            7)  menu_gaeste ;;
            8)  menu_durchreichen ;;
            9)  menu_sicherheit ;;
            10) menu_system ;;
            11) repair_menu ;;
            12) menu_journal ;;
            13) menu_nachschlagen ;;
        esac
    done
}
