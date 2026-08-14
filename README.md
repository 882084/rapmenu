# CronJobs-Proxmox

Ein Textmenü für Proxmox VE, gedacht für Menschen **ohne Linux- oder Proxmox-Erfahrung**. Alles läuft über Pfeiltasten und Enter, es muss kein einziger Befehl getippt werden.

Der Startbildschirm zeigt in einer Ampelübersicht, was in Ordnung ist und was Aufmerksamkeit braucht – jeder rote Punkt führt direkt zur passenden Lösung.

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

Alle Fenster passen sich der tatsächlichen Größe des Terminals an. Auf schmalen Terminals zeigen die Listen nur die Skriptnamen, auf breiten zusätzlich die Kurzbeschreibung – es läuft nie etwas über den Fensterrand hinaus.

## Hauptmenü

```
 1  Zustand meines Servers        Was ist in Ordnung, was muss ich tun?
 2  Ersteinrichtung               Gefuehrter Durchlauf fuer neue Server
 3  Automatische Aufgaben         Sicherungen und Pruefungen nach Zeitplan
 4  Sichern und Wiederherstellen  Backups einrichten und zurueckspielen
 5  Netzwerk                      IP-Adresse, Bruecken, Verbindungen
 6  Speicher und Festplatten      Platten einbinden, NAS verbinden
 7  VMs und Container             Anlegen, aendern, fertige Vorlagen
 8  Geraete durchreichen          Grafikkarte, USB oder Platte an eine VM
 9  Sicherheit und Zugang         Benutzer, Firewall, Zwei-Faktor
10  System und Updates            Updates, Neustart, Energiesparen
11  Problem loesen                Assistenten fuer haeufige Stoerungen
12  Was wurde geaendert           Verlauf aller Aenderungen
13  Nachschlagen                  Glossar, Hilfe, Systembericht
```

Die Punkte 2, 4 bis 10 sind angelegt und zeigen, was dort geplant ist; ihre Funktionen entstehen nach und nach. Vieles davon ist heute schon unter „Problem lösen" erreichbar.

## Zustand meines Servers

Der Startbildschirm prüft vierzehn Punkte und sortiert sie nach Dringlichkeit:

```
 1  [!!]  Sicherungsplan      Keine automatische Sicherung eingerichtet
 2  [!!]  Speicherplatz       Systemplatte ist zu 93% voll
 3  [ ! ] Festplatten         Eine Platte meldet defekte Sektoren
 4  [ok]  Neustart            Kein Neustart noetig
 5  [--]  Cluster             Einzelserver, kein Cluster
```

`[!!]` heißt handeln, `[ ! ]` bei Gelegenheit ansehen, `[ok]` in Ordnung und `[--]` trifft auf diesen Server nicht zu. Wählt man einen Punkt aus, öffnet sich ein Fenster mit der Erklärung – was bedeutet das, warum ist es wichtig, was passiert im schlimmsten Fall – und anschließend die Frage, ob das Werkzeug sich direkt darum kümmern soll.

Geprüft werden: vorhandene Sicherungen und ihr Alter, ein eingerichteter Sicherungsplan, Speicherplatz, Erreichbarkeit aller Speicher, Festplattengesundheit über SMART, ZFS-Pools, ZFS-Arbeitsspeicher, ausstehende Updates, Paketquellen, Benachrichtigungen, Uhrzeit, anstehende Neustarts, Firewall und Cluster-Quorum.

## Automatische Aufgaben

Cron-Jobs sind Aufgaben, die der Server von selbst zu einer festgelegten Zeit erledigt. Einmal ausgewählt laufen sie automatisch weiter.

Der Weg führt immer über die **Kategorie** zu den einzelnen **Skripten**. Jedes Skript ist nach seiner Funktion benannt, sodass am Namen schon erkennbar ist, was es tut. Die acht Kategorien umfassen zusammen 45 fertige Aufgaben: Sicherung (7), Momentaufnahmen (4), Speicher und ZFS (8), System-Wartung (9), Sicherheit (5), Cluster und HA (4), Netzwerk (3) sowie Konfiguration und Berichte (5).

In jeder Kategorie gibt es den Punkt **„Beschreibungen ansehen"**: Skript auswählen, Enter drücken, und es öffnet sich ein Fenster mit einer ausführlichen Erklärung. Nach dem Schließen steht die Auswahl wieder genau an derselben Stelle, sodass sich mehrere Beschreibungen hintereinander durchsehen lassen.

Zusätzlich lassen sich alle aktiven Jobs kategorieübergreifend anzeigen, ein einzelnes Skript sofort testweise ausführen und die Protokolle einsehen.

## Problem lösen

Elf Bereiche, sortiert nach dem, was der Nutzer bemerkt – nicht nach Technik. Jeder Punkt erklärt zuerst in einfacher Sprache, was das Problem ist und was gleich passieren wird; erst danach wird etwas ausgeführt. Gefährliche Aktionen fragen zweimal nach, und der Cursor steht dabei bewusst auf „Abbrechen".

Abgedeckt sind: Weboberfläche lädt nicht, Zertifikatsfehler und Subscription-Meldung; VMs oder Container starten nicht oder sind gesperrt; Festplatte voll und Speicher nicht erreichbar; kein Netzwerk, DNS-Probleme, hängende NAS-Freigaben, Firewall; fehlschlagende Updates; Festplattenfehler, ZFS-Probleme, zu hoher Arbeitsspeicherverbrauch durch ZFS; Cluster, Hochverfügbarkeit, falsche Uhrzeit; langsames System und hängende Dienste; Aufräumen von Fehlinstallationen wie Docker auf dem Host; ein Systembericht zum Kopieren ins Forum; und für Fortgeschrittene das direkte Bearbeiten von Konfigurationsdateien.

Vor jeder Änderung an einer Systemdatei wird automatisch eine Kopie unter `/var/backups/cronjobs-proxmox` angelegt, die sich über das Menü zurückspielen lässt.

## Aufbau

Ein Modul je Menübereich, dazu eine gemeinsame Bibliothek:

```
cronjobs-proxmox.sh          Einstiegspunkt, laedt alle Module
version.txt
lib/utils.sh                 Dialoge, Fenstergroessen, Protokoll, Sicherungen
cron/definitions.sh          Kategorien und die 45 Job-Definitionen
cron/install_jobs.sh         Legt Helfer-Skripte und Cron-Zeilen an
health/checks.sh             Die Pruefungen fuer die Ampel
menus/main_menu.sh           Hauptmenue
menus/status_menu.sh          1  Zustand meines Servers
menus/cron_menu.sh            3  Automatische Aufgaben
menus/repair_menu.sh         11  Problem loesen
menus/logs_menu.sh               Protokolle
menus/help_menu.sh           13  Nachschlagen, Glossar, Deinstallation
install.sh / uninstall.sh
```

Installiert wird nach `/usr/local/share/cronjobs-proxmox/`, der Startbefehl liegt als Verweis unter `/usr/local/bin/cronjobs-proxmox`.

## Wo liegt was?

Die Job-Skripte liegen unter `/usr/local/bin/cronjobs-proxmox-skripte/`, der Zeitplan in `/etc/cron.d/cronjobs-proxmox`, die Protokolle unter `/var/log/cronjobs-proxmox/` und die Sicherungskopien unter `/var/backups/cronjobs-proxmox/`.

## Empfehlung für den Einstieg

Nach der Installation zeigt der erste Bildschirm bereits, was zu tun ist. Wer nur wenig Zeit hat, aktiviert diese sechs Jobs und hat das Wichtigste abgedeckt: `backup-alle-vms-und-container.sh` und `backup-alte-loeschen.sh` aus der Kategorie Sicherung, `speicherplatz-warnung.sh` und – bei ZFS – `zfs-scrub-datenpruefung.sh` aus Speicher und ZFS, sowie `festplatten-smart-pruefen.sh` und `updates-pruefen.sh` aus der System-Wartung.

## Wichtiger Hinweis

Der Reparatur-Bereich verändert echte Systemeinstellungen mit Administratorrechten. Vor jeder Änderung wird zwar automatisch gesichert, trotzdem gilt: bei produktiven Systemen erst in einer Testumgebung ausprobieren, und besonders vorsichtig sein bei allem, was Netzwerk und Cluster betrifft, da diese Einstellungen alle Server gleichzeitig betreffen.

## Verhältnis zu ProxMenux

[ProxMenux](https://github.com/MacRimi/ProxMenux) von MacRimi ist das große, ausgereifte Werkzeug in diesem Bereich und hat die Gliederung dieses Menüs inspiriert. Es richtet sich an erfahrene Homelab-Nutzer und deckt Dinge ab, die hier fehlen – Grafikkarten durchreichen, VM-Vorlagen, Versionswechsel.

Dieses Werkzeug setzt einen anderen Schwerpunkt: durchgängig deutsch, jede Aktion vorher in einfacher Sprache erklärt, und mit Funktionen, die ProxMenux nicht hat – die Verwaltung wiederkehrender Aufgaben und die Zustandsampel im Terminal. Beide lassen sich nebeneinander betreiben; die Startbefehle (`menu` dort, `cronjobs-proxmox` hier) kommen sich nicht ins Gehege.

## Deinstallation

Über „Nachschlagen" → „Deinstallieren" oder direkt mit `/usr/local/bin/uninstall-cronjobs-proxmox.sh`. Sicherungen der VMs und Container sowie alle Proxmox-Einstellungen bleiben dabei in jedem Fall unberührt.

## Voraussetzungen

Proxmox VE 7.x, 8.x oder 9.x, Administratorrechte (root) und `whiptail`, das bei der Installation bei Bedarf automatisch mitinstalliert wird. Für die Festplattenprüfung zusätzlich `smartmontools`.

## Lizenz

MIT, ohne Gewähr. Die Skripte vor dem Einsatz auf produktiven Systemen bitte prüfen.
