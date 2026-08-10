# Rapmenu

Ein Whiptail-TUI-Menü für Proxmox VE: Replikations-Verwaltung + System-Repair, ähnlich wie [ProxMenux](https://github.com/MacRimi/ProxMenux), aber fokussiert auf ZFS-Replikation für HA-Cluster und schnelle Systemreparaturen.

## Installation

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"
```

oder mit curl:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/882084/rapmenu/main/install.sh)"
```

Danach starten mit:

```bash
repmenu
```

## Features

### Replikation
- HA-Status und alle `pvesr`-Jobs auf einen Blick
- Fehlende Replikations-Jobs für HA-Container automatisch finden & anlegen (verhindert `zfs error: dataset does not exist` bei HA-Failover/Rebalance)
- Alle Jobs sequenziell statt parallel synchronisieren (weniger IO-Spitzen)
- Zeitpläne bequem ändern
- ZFS-Tuning: Compression, Recordsize, ARC-Size
- Cron-Automatisierung mit einem Klick

## Menüstruktur

Das Hauptmenü ist in Kategorien gegliedert:

1. **Replikation** – HA-Status, Jobs anzeigen/anlegen, sequenzieller Sync, ZFS-Tuning, Migrations-Netzwerk, Cron-Automatisierung
2. **Cron-Jobs** – Backup, Snapshot-Verwaltung, System-Wartung, Konfiguration & Sonstiges (je eigene Unterkategorie)
3. **Netzwerkfreigaben (NFS/CIFS)** – Freigaben mit dem Host verbinden, optional per Bind-Mount in LXC-Container einbinden, automatische Wiederverbindung
4. **Paketquellen (APT-Repositories)** – Repos an-/abschalten ohne manuelles Editieren, siehe unten
5. **System Repair** – Config-Dateien bearbeiten, Dateibrowser, Backup-Wiederherstellung, Schnelle Reparaturen
6. **Bereinigung** – Fehlinstallationen (v.a. Docker auf dem PVE-Host) und verwaisten Kram entfernen, siehe unten
7. **Logs & Verlauf** – Rapmenu-Aktionen, Replikations-Logs, Backup/Wartungs-Logs getrennt einsehbar
8. **Deinstallieren**

### Paketquellen (APT-Repositories)

Verwaltet `/etc/apt/sources.list` und alle Dateien unter `/etc/apt/sources.list.d/` (`.list` und `.sources`), ganz ohne die Konsole:

- **Alle Paketquellen anzeigen** – Übersicht aller Dateien und Zeilen
- **PVE Enterprise-Repo an/aus** – erkennt automatisch den aktuellen Zustand und schaltet um
- **PVE No-Subscription-Repo an/aus**
- **Ceph Enterprise-Repo an/aus**
- **Einzelne Zeilen an/abschalten** – Checkliste pro Datei, jede Zeile einzeln per Leertaste an-/abwählbar (entspricht Auskommentieren/Einkommentieren)
- **Datei im Editor bearbeiten** – für alles, was die Checkliste nicht abdeckt
- **apt-get update ausführen** – direkt aus dem Menü

Vor jeder Änderung wird automatisch ein Backup nach `/var/backups/repmenu` angelegt.

### Cron-Jobs

**Eine** zentrale Kategorie im Hauptmenü, darunter vier Unterkategorien mit jeweils eigener Checkliste (Leertaste an/ab, Enter übernimmt nur die Jobs dieser Kategorie – andere Kategorien bleiben unberührt):

**Backup** (LXC/VM via `vzdump`)
- Tägliches Vollbackup (LXC+VM)
- Nur VMs sichern
- Nur LXC-Container sichern
- Alte Backups aufräumen (konfigurierbare Aufbewahrungsdauer)
- Backup-Integrität prüfen

**Snapshot-Verwaltung**
- Automatische Snapshots aufräumen – löscht nur Snapshots mit einem konfigurierbaren Präfix (Standard `auto-`) älter als X Tage; manuell angelegte Snapshots ohne dieses Präfix werden **nicht** angefasst

**System-Wartung**
- ZFS Scrub (monatlich)
- APT Update-Check (nur prüfen, nichts installieren)
- SMART Festplatten-Check
- Kernel-Reboot-Check
- Log-Aufräumen (journald)
- SSL-Zertifikat-Erneuerung (ACME-Sicherheitsnetz)

**Konfiguration & Sonstiges**
- Proxmox-Konfiguration sichern – tarrt `/etc/pve/*.cfg`, Netzwerk-Config etc. in ein Archiv, 14 Tage Aufbewahrung
- Speicherplatz-Warnung – loggt, wenn ein Mount über 90% voll ist
- Container-Templates aktualisieren – `pveam update`

Beim ersten Backup-Job wird einmalig nach dem Ziel-Storage gefragt (aus `pvesm status`). Der aktuelle Auswahlstand wird bei jedem Öffnen automatisch vorausgewählt angezeigt.

### Netzwerkfreigaben (NFS/CIFS)

Verbindet NFS- oder CIFS/SMB-Freigaben mit dem Proxmox-Host und optional per Bind-Mount mit einem LXC-Container – komplett per Menüabfrage, kein manuelles fstab-Editieren nötig.

**Wichtiger Hintergrund:** LXC-Container (besonders unprivilegierte) können NFS/CIFS meist nicht direkt selbst mounten. Der saubere Weg: der **Proxmox-Host** mountet die Freigabe, der Container bekommt sie per `pct set <ID> -mpX <hostpfad>,mp=<containerpfad>` durchgereicht. Rapmenu bietet das automatisch als letzten Schritt nach dem Einrichten der Freigabe an.

**Abgefragte Daten:**
- NFS: Server-IP/Hostname, Export-Pfad, Mountpoint auf dem Host, NFS-Version
- CIFS/SMB: Server, Freigabename, Domain (optional), Benutzername, Passwort, Mountpoint auf dem Host

Zugangsdaten für CIFS werden **nicht** im Klartext in `/etc/fstab` gespeichert, sondern in einer separaten, auf `600` gesicherten Credentials-Datei unter `/etc/repmenu/credentials/`.

**Automatische Wiederverbindung:**
- Mounts nutzen `x-systemd.automount` (verbindet bei Zugriff automatisch neu, z.B. nach Netzwerkausfall oder Reboot)
- Zusätzlich optional ein Cron-Sicherheitsnetz: prüft alle 5 Minuten, ob die Freigaben aktiv sind, und mountet sie bei Bedarf neu

**Weitere Funktionen:**
- Freigaben-Übersicht mit Live-Mount-Status
- Freigabe entfernen (aushängen, fstab-Eintrag + Zugangsdaten entfernen)
- Manueller Reconnect-Check auf Knopfdruck

### Bereinigung (Fehlinstallationen, verwaister Kram)

**Docker auf dem PVE-Host** – der Klassiker: aus Versehen `apt install docker.io` direkt auf dem Proxmox-Host statt in einer VM/LXC ausgeführt. Docker gehört dort nie hin (Konflikte mit cgroups/Netzwerk). Rapmenu kann:
- **Prüfen**: zeigt installierte Docker/Containerd-Pakete, den Dienst-Status und vorhandene Datenverzeichnisse (`/var/lib/docker` etc.) mit Größenangabe
- **Entfernen**: purgt alle Docker/Containerd-Pakete, löscht `/var/lib/docker`, `/var/lib/containerd`, `/etc/docker`, entfernt verwaiste Abhängigkeiten. Zweifache Sicherheitsabfrage, da nicht rückgängig zu machen

**Weitere Aufräumfunktionen:**
- Verwaiste Pakete entfernen (`apt-get autoremove --purge`, mit Vorschau vor dem Löschen)
- Residual-Konfigurationen purgen (Pakete, die deinstalliert sind, aber noch Config-Reste hinterlassen haben)
- Defekte Symlinks unter `/usr/local`, `/opt`, `/etc` finden und entfernen
- Alte/große Dateien in `/tmp` und `/var/tmp` aufräumen (älter als 7 Tage, größer als 10MB)
- APT-Paketcache leeren
- Verwaiste ZFS-Datasets prüfen – findet `subvol-*`/`vm-*`-Datasets, deren zugehörige LXC/VM-ID nicht mehr existiert. Zeigt nur an, löscht **nicht** automatisch – das erfordert manuelle Prüfung

### System Repair
- **Config-Dateien bearbeiten** mit automatischem Backup vor jeder Änderung (`/var/backups/repmenu`)
- **Dateibrowser**: beliebige Datei unter `/etc` navigieren und bearbeiten
- **Backup-Wiederherstellung**: jedes Backup mit einem Klick zurückspielen
- **Schnelle Reparaturen**:
  - APT reparieren (`dpkg --configure -a`, `apt-get install -f`)
  - Netzwerk neu laden
  - Initramfs neu bauen
  - Locales neu generieren
  - ZFS-Pool-Status prüfen / Scrub starten
  - Speicherplatz-Übersicht
  - PVE-Kerndienste prüfen/neustarten

Jede Aktion wird nach `/var/log/repmenu/actions.log` protokolliert.

## ⚠️ Wichtiger Hinweis

Das System-Repair-Modul bearbeitet **echte Systemdateien mit root-Rechten**. Vor jeder Bearbeitung wird automatisch ein Backup angelegt, trotzdem gilt:

- Nutze es mit Bedacht, besonders bei `/etc/network/interfaces` und `/etc/pve/*` (Cluster-weite Wirkung!)
- Backups liegen unter `/var/backups/repmenu` und werden bei der Deinstallation standardmäßig **nicht** gelöscht
- Bei produktiven Clustern: erst in einer Testumgebung ausprobieren

## Deinstallation

Aus dem Menü: `Deinstallieren` wählen.

Oder direkt:
```bash
/usr/local/bin/uninstall.sh
```

Nicht-interaktiv:
```bash
/usr/local/bin/uninstall.sh --yes
```

Entfernt Skripte, Cron-Job und Alias. Backups und bestehende `pvesr`-Jobs bleiben standardmäßig erhalten (Backups werden separat abgefragt).

## Konfiguration

ZFS-Pool-Name ist standardmäßig `ZFS2TB` (in `repmenu.sh`, Variable `ZPOOL_NAME`). Vor dem Push an deine Umgebung anpassen.

Editor für die Config-Bearbeitung: `$EDITOR`, Fallback `nano`.

## Struktur

```
rapmenu/
├── README.md
├── install.sh
├── repmenu.sh                  # Hauptmenü
├── auto-ha-replication.sh      # Findet/erstellt fehlende Replikations-Jobs
├── sequential-replication.sh   # Führt alle Jobs nacheinander aus
└── uninstall.sh
```

## Voraussetzungen

- Proxmox VE (7.x/8.x)
- root-Zugriff
- ZFS-Storage für Replikations- und Tuning-Features

## Lizenz

MIT — ohne Gewähr. Prüfe die Skripte vor Einsatz auf produktiven Systemen.
