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
