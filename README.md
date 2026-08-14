# CronJobs-Proxmox

Ein Textmenü für Proxmox VE, gedacht für Menschen **ohne Linux- oder Proxmox-Erfahrung**. Alles läuft über Pfeiltasten und Enter, es muss kein einziger Befehl getippt werden.

Das Werkzeug hat zwei Bereiche: automatische Aufgaben (Cron-Jobs) und Problemlösungen (Reparatur).

## Installation

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"
```

Danach starten mit:

```bash
cronjobs-proxmox
```

## Bedienung

Pfeiltasten bewegen die Auswahl, Enter bestätigt, die Leertaste wählt in Checklisten an und ab, Escape geht zurück. Der Cursor steht immer schon auf dem Auswahl-Knopf, ein Druck auf Enter genügt also.

Alle Fenster passen sich der tatsächlichen Größe des Terminals an. Auf schmalen Terminals (80 Spalten) zeigen die Listen nur die Skriptnamen, auf breiten zusätzlich die Kurzbeschreibung – es läuft nie etwas über den Fensterrand hinaus.

## Bereich 1: Cron-Jobs

Cron-Jobs sind Aufgaben, die der Server von selbst zu einer festgelegten Zeit erledigt, zum Beispiel jede Nacht um zwei Uhr eine Sicherung erstellen. Einmal ausgewählt laufen sie automatisch weiter.

Der Weg durch das Menü ist immer derselbe: erst die **Kategorie** wählen, dann die einzelnen **Skripte** darin an- oder abwählen. Jedes Skript ist nach seiner Funktion benannt, sodass am Namen schon erkennbar ist, was es tut.

Die acht Kategorien sind Sicherung (7 Skripte), Momentaufnahmen (4), Speicher und ZFS (8), System-Wartung (9), Sicherheit (5), Cluster und Hochverfügbarkeit (4), Netzwerk (3) und Konfiguration und Berichte (5) – zusammen 45 fertige Aufgaben.

### Beschreibungen nachlesen

In jeder Kategorie gibt es den Punkt **„Beschreibungen ansehen"**. Dort wird ein Skript ausgewählt und mit Enter bestätigt, woraufhin sich ein eigenes Info-Fenster mit einer ausführlichen Erklärung öffnet: was das Skript macht, wann es läuft, warum es sinnvoll ist und ob es gerade aktiv ist. Nach dem Schließen steht die Auswahl wieder genau an derselben Stelle in derselben Liste, sodass sich mehrere Beschreibungen hintereinander durchsehen lassen, ohne das Menü zu verlassen.

### Weitere Funktionen

Alle aktiven Jobs lassen sich kategorieübergreifend anzeigen, ein einzelnes Skript kann sofort testweise ausgeführt werden (statt auf den Zeitplan zu warten), die Protokolle jedes Jobs sind einsehbar und alle Jobs lassen sich auf einen Schlag deaktivieren.

Beim ersten Backup-Job wird einmalig gefragt, auf welchen Speicher gesichert werden soll. Der aktuelle Auswahlstand ist beim Öffnen einer Checkliste immer schon vorausgewählt.

## Bereich 2: Reparatur

Lösungen für die häufigsten Proxmox-Probleme, sortiert nach dem, was der Nutzer bemerkt – nicht nach technischen Kategorien. Jeder Punkt erklärt zuerst in einfacher Sprache, was das Problem ist und was gleich passieren wird; erst danach wird etwas ausgeführt. Gefährliche Aktionen fragen zweimal nach und der Cursor steht dabei bewusst auf „Abbrechen".

Die elf Bereiche decken ab: Weboberfläche lädt nicht, Zertifikatsfehler und die Subscription-Meldung; VMs oder Container starten nicht oder sind gesperrt; Festplatte voll, Speicher nicht erreichbar und sicheres Aufräumen; kein Netzwerk, DNS-Probleme, hängende NAS-Freigaben und Firewall; fehlschlagende Updates und Paketquellen; Festplattenfehler, ZFS-Probleme und zu hoher Arbeitsspeicherverbrauch durch ZFS; Cluster-Probleme, Hochverfügbarkeit und falsche Uhrzeit; langsames System, hängende Dienste und stehengebliebene Aufgaben; Aufräumen von Fehlinstallationen wie Docker auf dem Host; einen Systembericht zum Kopieren ins Support-Forum; und für Fortgeschrittene das direkte Bearbeiten von Konfigurationsdateien.

Vor jeder Änderung an einer Systemdatei wird automatisch eine Kopie unter `/var/backups/cronjobs-proxmox` angelegt, die sich über das Menü zurückspielen lässt.

## Wo liegt was?

Die Job-Skripte liegen unter `/usr/local/bin/cronjobs-proxmox-skripte/`, der Zeitplan in `/etc/cron.d/cronjobs-proxmox`, die Protokolle unter `/var/log/cronjobs-proxmox/` und die Sicherungskopien unter `/var/backups/cronjobs-proxmox/`.

## Empfehlung für den Einstieg

Wer nur wenig Zeit hat, aktiviert diese sechs Jobs und hat damit das Wichtigste abgedeckt: `backup-alle-vms-und-container.sh` und `backup-alte-loeschen.sh` aus der Kategorie Sicherung, `speicherplatz-warnung.sh` und (bei ZFS) `zfs-scrub-datenpruefung.sh` aus Speicher und ZFS, sowie `festplatten-smart-pruefen.sh` und `updates-pruefen.sh` aus der System-Wartung.

## Wichtiger Hinweis

Der Reparatur-Bereich verändert echte Systemeinstellungen mit Administratorrechten. Vor jeder Änderung wird zwar automatisch gesichert, trotzdem gilt: bei produktiven Systemen erst in einer Testumgebung ausprobieren, und besonders vorsichtig sein bei allem, was Netzwerk und Cluster betrifft, da diese Einstellungen alle Server gleichzeitig betreffen.

## Deinstallation

Über den Menüpunkt „Deinstallieren" oder direkt mit `/usr/local/bin/uninstall.sh`. Sicherungen der VMs und Container sowie alle Proxmox-Einstellungen bleiben dabei in jedem Fall unberührt.

## Voraussetzungen

Proxmox VE 7.x oder 8.x, Administratorrechte (root) und `whiptail`, das bei der Installation bei Bedarf automatisch mitinstalliert wird.

## Lizenz

MIT, ohne Gewähr. Die Skripte vor dem Einsatz auf produktiven Systemen bitte prüfen.
