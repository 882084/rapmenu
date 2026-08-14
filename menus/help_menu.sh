#!/bin/bash
# ==========================================================
# Menue 13 - Nachschlagen (Hilfe, Glossar) + Deinstallation
# ==========================================================

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

glossar_anzeigen() {
    local TMPFILE
    TMPFILE=$(mktemp)
    cat > "$TMPFILE" << 'TEXT'
Glossar - Begriffe einfach erklaert
==========================================================

VIRTUELLE MASCHINE (VM)
  Ein kompletter, nachgebauter Computer im Computer - mit
  eigenem Betriebssystem, eigenem Kernel, eigener virtueller
  Hardware. Braucht mehr Arbeitsspeicher, kann dafuer jedes
  System ausfuehren, auch Windows.

CONTAINER (LXC)
  Ein abgetrennter Bereich, der sich den Kernel mit dem
  Hauptsystem teilt. Startet in Sekunden, braucht wenig
  Arbeitsspeicher, laeuft aber nur mit Linux.
  Faustregel: Linux-Dienst -> Container. Windows oder etwas
  Exotisches -> VM.

PRIVILEGIERT / UNPRIVILEGIERT
  Ein unprivilegierter Container hat weniger Rechte am
  Hauptsystem. Das ist sicherer und der Normalfall. Manche
  Dinge - etwa selbst eine Netzwerkfreigabe einbinden -
  gehen darin allerdings nicht.

HOST
  Der Proxmox-Server selbst, also die Maschine, auf der die
  VMs und Container laufen. Faustregel: Auf dem Host so
  wenig wie moeglich installieren.

SNAPSHOT (Momentaufnahme)
  Ein eingefrorener Zustand einer VM. Damit kannst du in
  Sekunden auf "vor dem Update" zurueck.
  WICHTIG: Ein Snapshot ist KEIN Backup. Er liegt auf
  derselben Festplatte. Geht die Platte kaputt, sind VM und
  Snapshot gleichzeitig weg.

BACKUP (Sicherung)
  Eine vollstaendige Kopie an einem anderen Ort. Ueberlebt
  auch einen Plattenausfall. Das ist der Unterschied.

BRIDGE (Bruecke, meist vmbr0)
  Ein virtueller Netzwerkverteiler im Server. Die VMs haengen
  daran wie Geraete an einem Switch, damit sie ins Netzwerk
  kommen. vmbr0 ist die Standardbruecke.

VLAN
  Mehrere getrennte Netze ueber ein einziges Kabel. Jedes
  bekommt eine Nummer. Damit lassen sich zum Beispiel Gaeste-
  und Heimnetz sauber trennen.

ZFS
  Ein Dateisystem, das jeden Datenblock mit einer Pruefsumme
  ablegt und dadurch stille Datenfehler erkennt und - bei
  gespiegelten Platten - selbst repariert. Kann Snapshots und
  Kompression. Braucht dafuer Arbeitsspeicher.

POOL
  Der Zusammenschluss mehrerer Festplatten zu einem grossen
  Speicher unter ZFS.

SCRUB (Datenpruefung)
  ZFS liest alle gespeicherten Daten und vergleicht sie mit
  den Pruefsummen. Findet Fehler, bevor sie auffallen.
  Empfehlung: einmal im Monat.

ARC
  Der Zwischenspeicher, den ZFS im Arbeitsspeicher anlegt.
  Macht das System schneller, kann aber viel RAM belegen.

SMART
  Die Selbstdiagnose jeder Festplatte. Meldet defekte
  Sektoren und Betriebsstunden - meist Wochen bevor eine
  Platte endgueltig ausfaellt.

THIN-POOL (LVM)
  Ein Speicher, der Platz erst dann wirklich belegt, wenn er
  gebraucht wird. Praktisch, aber gefaehrlich: Laeuft er voll,
  koennen VM-Festplatten beschaedigt werden.

CLUSTER
  Mehrere Proxmox-Server, die gemeinsam verwaltet werden.

QUORUM
  Die Mehrheit im Cluster. Nur wenn genug Server erreichbar
  sind, duerfen Aenderungen gespeichert werden. Ohne Quorum
  ist die Konfiguration schreibgeschuetzt.

HOCHVERFUEGBARKEIT (HA)
  Faellt ein Server aus, starten seine VMs automatisch auf
  einem anderen. Setzt einen funktionierenden Cluster voraus.

REPLIKATION
  Regelmaessiges Spiegeln von VMs auf einen zweiten Server,
  damit HA im Ernstfall auch Daten vorfindet.

CRON
  Der Dienst, der Aufgaben zu festen Zeiten ausfuehrt. Alles
  unter "Automatische Aufgaben" laeuft darueber.

REPOSITORY (Paketquelle)
  Die Bezugsquelle fuer Updates. Das Enterprise-Repo braucht
  eine kostenpflichtige Subscription, das No-Subscription-Repo
  ist kostenlos und fuer private Server der richtige Weg.

GAST-AGENT
  Ein kleines Programm in der VM, damit Proxmox sie sauber
  herunterfahren und im laufenden Betrieb sichern kann.

PASSTHROUGH (Durchreichen)
  Ein Geraet - Grafikkarte, USB-Stick, Festplatte - direkt an
  eine VM geben, sodass die VM es exklusiv nutzt.
TEXT
    info_textbox "$TMPFILE" "Glossar"
    rm -f "$TMPFILE"
}
